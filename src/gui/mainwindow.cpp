// mainwindow.cpp
// MusicLib Qt GUI - Main Window Implementation (Dolphin-style sidebar layout)
// Phase 2: Settings Dialog — KConfigXT mirroring musiclib.conf
// Copyright (c) 2026 MusicLib Project

#include "mainwindow.h"
#include "albumwindow.h"
#include "confwriter.h"
#include "librarymodel.h"
#include "libraryview.h"
#include "maintenancepanel.h"
#include "scriptrunner.h"
#include "settingsdialog.h"
#include "mobile_panel.h"

#include <KXmlGuiWindow>
#include <KActionCollection>
#include <KStandardAction>
#include <KLocalizedString>
#include <KWindowSystem>
#include <KX11Extras>
#include <KWindowInfo>
#include <netwm_def.h>

#include <QApplication>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QSplitter>
#include <QStatusBar>
#include <QToolBar>
#include <QAction>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QUrl>
#include <QProcess>
#include <QFileInfo>
#include <QIcon>
#include <QFont>
#include <QMessageBox>
#include <QThread>
#include <QDBusInterface>

// ═════════════════════════════════════════════════════════════
// Construction / Destruction
// ═════════════════════════════════════════════════════════════

MainWindow::MainWindow(QWidget *parent)
    : KXmlGuiWindow(parent)
    , m_sidebar(nullptr)
    , m_panelStack(nullptr)
    , m_libraryPanel(nullptr)
    , m_maintenancePanel(nullptr)
    , m_mobilePanel(nullptr)
    , m_nowPlayingLabel(nullptr)
    , m_playlistDropdown(nullptr)
    , m_statusLabel(nullptr)
    , m_libraryModel(nullptr)
    , m_scriptRunner(nullptr)
    , m_nowPlayingTimer(nullptr)
    , m_fileWatcher(nullptr)
    , m_albumWindow(nullptr)
    , m_confWriter(nullptr)
{
    setWindowTitle(i18n("MusicLib"));

    // ── Load configuration via ConfWriter ──
    // This replaces the hardcoded XDG/legacy path detection.
    // ConfWriter searches: $MUSICLIB_CONFIG_DIR → XDG → ~/musiclib/config/
    setupConfWriter();

    // ── Create data model for album window and status queries ──
    m_libraryModel = new LibraryModel(this);
    m_libraryModel->loadFromFile(m_databasePath);

    // ── Create script runner ──
    m_scriptRunner = new ScriptRunner(this);

    // ── Build UI ──
    setupSidebar();
    setupPanels();
    setupToolbar();
    setupStatusBar();
    setupActions();

    // Assemble main layout: sidebar | panel stack
    auto *centralWidget = new QWidget(this);
    auto *splitter = new QSplitter(Qt::Horizontal, centralWidget);

    splitter->addWidget(m_sidebar);
    splitter->addWidget(m_panelStack);

    // Sidebar gets a fixed comfortable width, panels get the rest
    splitter->setStretchFactor(0, 0);   // sidebar: don't stretch
    splitter->setStretchFactor(1, 1);   // panels: stretch to fill
    splitter->setSizes({160, 700});     // initial sizes in pixels

    auto *centralLayout = new QHBoxLayout(centralWidget);
    centralLayout->setContentsMargins(0, 0, 0, 0);
    centralLayout->addWidget(splitter);

    setCentralWidget(centralWidget);

    // ── Start background services ──
    setupFileWatcher();
    setupNowPlayingTimer();

    // Default to Library panel
    m_sidebar->setCurrentRow(PanelLibrary);

    // Initial now-playing refresh
    refreshNowPlaying();

    // KXmlGuiWindow standard setup (menus, accelerators)
    setupGUI(Default, QStringLiteral("musiclib-qtui.rc"));

    resize(950, 650);
}

MainWindow::~MainWindow()
{
    if (m_albumWindow) {
        m_albumWindow->close();
        delete m_albumWindow;
    }
    // m_confWriter is parented to this, so Qt deletes it automatically.
}

// ═════════════════════════════════════════════════════════════
// Configuration setup — ConfWriter + path resolution
// ═════════════════════════════════════════════════════════════

void MainWindow::setupConfWriter()
{
    m_confWriter = new ConfWriter();

    if (m_confWriter->loadFromDefaultLocation()) {
        // Config loaded — read paths from it.
        // ConfWriter handles shell variable resolution by storing
        // resolved paths, so we get clean absolute paths here.
        m_musicDisplayDir = m_confWriter->value(
            QStringLiteral("MUSIC_DISPLAY_DIR"));
        m_databasePath = m_confWriter->value(
            QStringLiteral("MUSICDB"));
        m_playlistsDir = m_confWriter->value(
            QStringLiteral("PLAYLISTS_DIR"));
        // Mobile-specific paths    
        m_audaciousPlaylistsDir = m_confWriter->value(
            QStringLiteral("AUDACIOUS_PLAYLISTS_DIR"));
        m_mobileDir = m_confWriter->value(
            QStringLiteral("MOBILE_DIR"));

        // Fallback for unresolved shell variables or missing values.
        // ConfWriter reads literally, so shell expansions like
        // ${MUSICLIB_DATA_DIR} appear as raw text.
        //
        // IMPORTANT: m_playlistsDir must be resolved BEFORE m_mobileDir,
        // because the m_mobileDir fallback derives from m_playlistsDir.
        if (m_audaciousPlaylistsDir.isEmpty()
            || m_audaciousPlaylistsDir.contains(QLatin1Char('$'))) {
            m_audaciousPlaylistsDir = QDir::homePath()
                + QStringLiteral("/.config/audacious/playlists");
        }

        QString xdgData = QDir::homePath()
            + QStringLiteral("/.local/share/musiclib");

        if (m_musicDisplayDir.contains(QLatin1Char('$'))) {
            m_musicDisplayDir = xdgData
                + QStringLiteral("/data/conky_output");
        }
        if (m_databasePath.contains(QLatin1Char('$'))) {
            m_databasePath = xdgData
                + QStringLiteral("/data/musiclib.dsv");
        }
        if (m_playlistsDir.contains(QLatin1Char('$'))) {
            m_playlistsDir = xdgData + QStringLiteral("/playlists");
        }
        // m_mobileDir fallback AFTER m_playlistsDir is fully resolved
        if (m_mobileDir.isEmpty()
            || m_mobileDir.contains(QLatin1Char('$'))) {
            m_mobileDir = m_playlistsDir + QStringLiteral("/mobile");
        }
    } else {
        // No config file found — use XDG defaults (same as before).
        // This path is hit on first launch before the setup wizard runs.
        QString xdgData = QDir::homePath()
            + QStringLiteral("/.local/share/musiclib");
        QString legacyRoot = QDir::homePath()
            + QStringLiteral("/musiclib");

        if (QDir(xdgData).exists()) {
            m_musicDisplayDir = xdgData
                + QStringLiteral("/data/conky_output");
            m_databasePath = xdgData
                + QStringLiteral("/data/musiclib.dsv");
            m_playlistsDir = xdgData + QStringLiteral("/playlists");
            m_audaciousPlaylistsDir = QDir::homePath()
                + QStringLiteral("/.config/audacious/playlists");
            m_mobileDir = m_playlistsDir + QStringLiteral("/mobile");
        } else {
            m_musicDisplayDir = legacyRoot
                + QStringLiteral("/data/conky_output");
            m_databasePath = legacyRoot
                + QStringLiteral("/data/musiclib.dsv");
            m_playlistsDir = legacyRoot
                + QStringLiteral("/playlists");
            m_audaciousPlaylistsDir = QDir::homePath()
                + QStringLiteral("/.config/audacious/playlists");
            m_mobileDir = m_playlistsDir + QStringLiteral("/mobile");
        }
    }
}

// ═════════════════════════════════════════════════════════════
// Sidebar setup
// ═════════════════════════════════════════════════════════════

void MainWindow::setupSidebar()
{
    m_sidebar = new QListWidget(this);
    m_sidebar->setViewMode(QListView::ListMode);
    m_sidebar->setIconSize(QSize(22, 22));
    m_sidebar->setSpacing(2);
    m_sidebar->setMaximumWidth(200);
    m_sidebar->setMinimumWidth(120);

    // Use Dolphin-like styling: flat list, highlight on selection
    m_sidebar->setFrameStyle(QFrame::NoFrame);

    // Add navigation entries with icons
    auto addItem = [this](const QString &text, const QString &iconName) {
        auto *item = new QListWidgetItem(QIcon::fromTheme(iconName), text);
        item->setSizeHint(QSize(0, 36));  // comfortable row height
        m_sidebar->addItem(item);
    };

    addItem(i18n("Library"),     QStringLiteral("folder-music"));
    addItem(i18n("Maintenance"), QStringLiteral("configure"));
    addItem(i18n("Mobile"),      QStringLiteral("smartphone"));
    addItem(i18n("Settings"),    QStringLiteral("preferences-system"));

    connect(m_sidebar, &QListWidget::currentRowChanged,
            this, &MainWindow::onSidebarItemChanged);
}

// ═════════════════════════════════════════════════════════════
// Panel setup
// ═════════════════════════════════════════════════════════════

void MainWindow::setupPanels()
{
    m_panelStack = new QStackedWidget(this);

    // ── Library panel (existing) ──
    m_libraryPanel = new LibraryView(this);
    m_libraryPanel->loadDatabase(m_databasePath);
    m_panelStack->addWidget(m_libraryPanel);   // index 0

    // ── Maintenance panel (existing) ──
    m_maintenancePanel = new MaintenancePanel(m_scriptRunner, this);
    m_panelStack->addWidget(m_maintenancePanel);   // index 1

   // ── Mobile panel ──
    m_mobilePanel = new MobilePanel(
        m_playlistsDir,
        m_audaciousPlaylistsDir,
        m_mobileDir,
        m_confWriter->value(QStringLiteral("DEVICE_ID")),
        this);
    m_panelStack->addWidget(m_mobilePanel);   // index 2

    // Upload completion → status bar notification
    connect(m_mobilePanel, &MobilePanel::uploadCompleted,
            this, [this](const QString &playlistName, int trackCount) {
        statusBar()->showMessage(
            i18n("Uploaded %1 (%2 tracks)", playlistName, trackCount), 5000);
    });

    // ── Settings ──
    // No stacked widget entry for Settings.  The sidebar "Settings" row
    // opens a KConfigDialog instead.  See onSidebarItemChanged().
}

// ═════════════════════════════════════════════════════════════
// Toolbar setup
// ═════════════════════════════════════════════════════════════

void MainWindow::setupToolbar()
{
    QToolBar *toolbar = new QToolBar(i18n("Main Toolbar"), this);
    toolbar->setObjectName(QStringLiteral("mainToolBar"));
    toolbar->setMovable(false);
    toolbar->setIconSize(QSize(22, 22));
    addToolBar(Qt::TopToolBarArea, toolbar);

    // ── Now Playing label ──
    m_nowPlayingLabel = new QLabel(i18n("Not playing"), this);
    m_nowPlayingLabel->setStyleSheet(
        QStringLiteral("QLabel { padding: 0 8px; font-weight: bold; }"));
    toolbar->addWidget(m_nowPlayingLabel);

    // ── Star rating buttons (0–5) ──
    for (int i = 0; i <= 5; ++i) {
        m_starButtons[i] = new QToolButton(this);
        m_starButtons[i]->setAutoRaise(true);
        m_starButtons[i]->setToolTip(
            i == 0 ? i18n("Clear rating")
                   : i18n("Rate %1 star(s)", i));

        if (i == 0) {
            m_starButtons[i]->setVisible(false);
        } else {
            m_starButtons[i]->setText(QString(QChar(0x2606)));  // ☆ empty star
            m_starButtons[i]->setFont(QFont(QString(), 14));
        }

        connect(m_starButtons[i], &QToolButton::clicked, this, [this, i]() {
            rateCurrentTrack(i);
        });

        if (i > 0) {
            toolbar->addWidget(m_starButtons[i]);
        }
    }

    toolbar->addSeparator();

    // ── Album button ──
    QAction *albumAction = new QAction(
        QIcon::fromTheme(QStringLiteral("media-optical-audio")),
        i18n("Album"), this);
    albumAction->setToolTip(i18n("Show album details for current track"));
    connect(albumAction, &QAction::triggered, this, &MainWindow::showAlbumWindow);
    toolbar->addAction(albumAction);

    toolbar->addSeparator();

    // ── Playlist dropdown ──
    auto *playlistLabel = new QLabel(i18n(" Playlist: "), this);
    toolbar->addWidget(playlistLabel);

    m_playlistDropdown = new QComboBox(this);
    m_playlistDropdown->setMinimumWidth(120);
    m_playlistDropdown->setToolTip(i18n("Select a playlist — switches active playlist in Audacious"));
    populatePlaylistDropdown();
    connect(m_playlistDropdown, QOverload<int>::of(&QComboBox::activated),
            this, &MainWindow::onPlaylistSelected);
    toolbar->addWidget(m_playlistDropdown);

    toolbar->addSeparator();

    // ── Audacious button ──
    QAction *audaciousAction = new QAction(
        QIcon::fromTheme(QStringLiteral("audacious")),
        i18n("Audacious"), this);
    audaciousAction->setToolTip(i18n("Launch Audacious or raise it to the foreground"));
    connect(audaciousAction, &QAction::triggered,
            this, &MainWindow::onRaiseAudacious);
    toolbar->addAction(audaciousAction);

    // ── Kid3 button ──
    // Check which Kid3 GUI version is installed (if any)
    QString kid3GuiVersion = m_confWriter->value("KID3_GUI_INSTALLED");
    bool hasKid3Gui = (kid3GuiVersion == "kid3" || kid3GuiVersion == "kid3-qt");
    
    QAction *kid3Action = new QAction(
        QIcon::fromTheme(QStringLiteral("kid3-qt")),
        i18n("Kid3"), this);
    
    if (hasKid3Gui) {
        kid3Action->setToolTip(
            i18n("Open current track in Kid3, or raise Kid3 if already open"));
        connect(kid3Action, &QAction::triggered,
                this, &MainWindow::onOpenKid3);
    } else {
        kid3Action->setEnabled(false);
        kid3Action->setToolTip(
            i18n("Kid3 GUI not installed. Install kid3 or kid3-qt package to enable tag editor.\n"
                 "Run musiclib_init_config.sh again after installation."));
    }
    
    toolbar->addAction(kid3Action);
}

// ═════════════════════════════════════════════════════════════
// Status bar setup
// ═════════════════════════════════════════════════════════════

void MainWindow::setupStatusBar()
{
    m_statusLabel = new QLabel(i18n("Ready"), this);
    statusBar()->addWidget(m_statusLabel, 1);
}

// ═════════════════════════════════════════════════════════════
// Standard KDE actions
// ═════════════════════════════════════════════════════════════

void MainWindow::setupActions()
{
    // Standard quit action
    KStandardAction::quit(qApp, &QCoreApplication::quit, actionCollection());

    // Standard preferences action — opens Settings dialog from menu bar
    KStandardAction::preferences(this, &MainWindow::showSettingsDialog,
                                 actionCollection());
}

// ═════════════════════════════════════════════════════════════
// File watcher (DSV changes)
// ═════════════════════════════════════════════════════════════

void MainWindow::setupFileWatcher()
{
    m_fileWatcher = new QFileSystemWatcher(this);

    if (QFile::exists(m_databasePath)) {
        m_fileWatcher->addPath(m_databasePath);
    }

    connect(m_fileWatcher, &QFileSystemWatcher::fileChanged,
            this, &MainWindow::onDatabaseChanged);
}

// ═════════════════════════════════════════════════════════════
// Now-playing timer
// ═════════════════════════════════════════════════════════════

void MainWindow::setupNowPlayingTimer()
{
    m_nowPlayingTimer = new QTimer(this);
    m_nowPlayingTimer->setInterval(3000);  // poll every 3 seconds
    connect(m_nowPlayingTimer, &QTimer::timeout,
            this, &MainWindow::onNowPlayingTimer);
    m_nowPlayingTimer->start();
}

// ═════════════════════════════════════════════════════════════
// Slot: Sidebar navigation changed
// ═════════════════════════════════════════════════════════════

void MainWindow::onSidebarItemChanged(int currentRow)
{
    if (currentRow == PanelSettings) {
        // Settings is not an embedded panel — open the dialog instead.
        // Restore the sidebar selection to the previous panel so
        // the highlight doesn't sit on "Settings" while the dialog
        // is open (or after it closes).
        showSettingsDialog();

        // Restore previous selection without re-triggering this slot
        m_sidebar->blockSignals(true);
        m_sidebar->setCurrentRow(m_lastSidebarIndex);
        m_sidebar->blockSignals(false);
        return;
    }

    if (currentRow >= 0 && currentRow < m_panelStack->count()) {
        m_panelStack->setCurrentIndex(currentRow);
        m_lastSidebarIndex = currentRow;
    }
}

void MainWindow::switchToPanel(int index)
{
    if (index >= 0 && index < PanelSettings) {
        m_sidebar->setCurrentRow(index);
    }
}

void MainWindow::switchToMobileWithPlaylist(const QString &playlistPath)
{
    m_mobilePanel->setPlaylist(playlistPath);
    switchToPanel(PanelMobile);
}

// ═════════════════════════════════════════════════════════════
// Settings dialog
// ═════════════════════════════════════════════════════════════

void MainWindow::showSettingsDialog()
{
    // KConfigDialog manages singleton instances by name.
    // If the dialog already exists, it just raises it.
    if (KConfigDialog::showDialog(QStringLiteral("MusicLibSettings"))) {
        return;
    }

    auto *dialog = new SettingsDialog(this, m_confWriter);

    // Connect signals for live-refresh when settings change
    connect(dialog, &SettingsDialog::databasePathChanged,
            this, &MainWindow::onDatabasePathChanged);
    connect(dialog, &SettingsDialog::pollIntervalChanged,
            this, &MainWindow::onPollIntervalChanged);

    dialog->show();
}

void MainWindow::onDatabasePathChanged()
{
    // Re-read paths from ConfWriter (it was just saved by the dialog)
    setupConfWriter();

    // Reload models with the (possibly new) database path
    m_libraryModel->loadFromFile(m_databasePath);
    m_libraryPanel->loadDatabase(m_databasePath);

    // Update the file watcher
    if (!m_fileWatcher->files().isEmpty()) {
        m_fileWatcher->removePaths(m_fileWatcher->files());
    }
    if (QFile::exists(m_databasePath)) {
        m_fileWatcher->addPath(m_databasePath);
    }

    // Refresh playlists dropdown (PLAYLISTS_DIR may have changed)
    populatePlaylistDropdown();
}

void MainWindow::onPollIntervalChanged(int newIntervalMs)
{
    m_nowPlayingTimer->setInterval(newIntervalMs);
}

// ═════════════════════════════════════════════════════════════
// Slot: Playlist dropdown selection
// ═════════════════════════════════════════════════════════════

void MainWindow::onPlaylistSelected(int index)
{
    if (index < 0) {
        return;
    }

    bool ok = false;
    int playlistIndex = m_playlistDropdown->itemData(index).toInt(&ok);
    if (!ok || playlistIndex < 1) {
        return; // "Select playlist..." placeholder or invalid entry
    }

    // If Audacious is not running, launch it and let it open its last state.
    // The user can then see the playlist has been switched next time.
    if (!isProcessRunning(QStringLiteral("audacious"))) {
        QProcess::startDetached(QStringLiteral("/usr/bin/audacious"), {});
        return;
    }

    // Switch the active playlist in Audacious via audtool
    QProcess switchCmd;
    switchCmd.start(QStringLiteral("audtool"),
                    {QStringLiteral("--set-current-playlist"),
                     QString::number(playlistIndex)});
    switchCmd.waitForFinished(2000);

    // Bring Audacious to the foreground so the user can see the change
    QProcess showCmd;
    showCmd.start(QStringLiteral("audtool"),
                  {QStringLiteral("--mainwin-show"), QStringLiteral("on")});
    showCmd.waitForFinished(2000);

    QThread::msleep(100);
    raiseWindowByClass(QStringLiteral("audacious"));
}

void MainWindow::populatePlaylistDropdown()
{
    m_playlistDropdown->clear();
    m_playlistDropdown->addItem(i18n("Select playlist..."), QVariant(-1));

    QDir audDir(m_audaciousPlaylistsDir);
    if (!audDir.exists()) {
        return;
    }

    // Read the 'order' file to get playlist IDs in display order.
    // Each ID in the order file corresponds to a <ID>.audpl file.
    // The 1-based position in this list is what audtool's
    // --set-current-playlist command expects.
    QString orderPath = m_audaciousPlaylistsDir + QStringLiteral("/order");
    QFile orderFile(orderPath);
    if (!orderFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }
    QString orderLine = QString::fromUtf8(orderFile.readAll()).trimmed();
    orderFile.close();

    QStringList ids = orderLine.split(QLatin1Char(' '), Qt::SkipEmptyParts);

    for (int i = 0; i < ids.size(); ++i) {
        const QString &id = ids.at(i);
        QString audplPath = m_audaciousPlaylistsDir
                            + QStringLiteral("/") + id
                            + QStringLiteral(".audpl");
        QFile audplFile(audplPath);
        if (!audplFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }

        // First line of .audpl is "title=<URL-encoded name>"
        QString firstLine = QString::fromUtf8(
            audplFile.readLine()).trimmed();
        audplFile.close();

        QString title;
        if (firstLine.startsWith(QLatin1String("title="))) {
            QString encoded = firstLine.mid(6); // strip "title="
            title = QUrl::fromPercentEncoding(encoded.toUtf8());
        }
        if (title.isEmpty()) {
            title = id; // fallback to numeric ID
        }

        // Store 1-based index so audtool --set-current-playlist <N> works
        m_playlistDropdown->addItem(title, QVariant(i + 1));
    }
}

// ═════════════════════════════════════════════════════════════
// Slot: Database file changed
// ═════════════════════════════════════════════════════════════

void MainWindow::onDatabaseChanged(const QString &path)
{
    Q_UNUSED(path);

    QTimer::singleShot(500, this, [this]() {
        m_libraryModel->loadFromFile(m_databasePath);
        m_libraryPanel->loadDatabase(m_databasePath);

        if (!m_fileWatcher->files().contains(m_databasePath)) {
            m_fileWatcher->addPath(m_databasePath);
        }
    });
}

// ═════════════════════════════════════════════════════════════
// Now-playing refresh
// ═════════════════════════════════════════════════════════════

void MainWindow::onNowPlayingTimer()
{
    refreshNowPlaying();
}

void MainWindow::refreshNowPlaying()
{
    // ── Read conky output files (instant, no process spawn) ──
    m_nowPlaying.artist     = readConkyFile(QStringLiteral("artist.txt"));
    m_nowPlaying.album      = readConkyFile(QStringLiteral("album.txt"));
    m_nowPlaying.title      = readConkyFile(QStringLiteral("title.txt"));
    m_nowPlaying.year        = readConkyFile(QStringLiteral("year.txt"));
    m_nowPlaying.comment    = readConkyFile(QStringLiteral("detail.txt"));
    m_nowPlaying.lastPlayed = readConkyFile(QStringLiteral("lastplayed.txt"));
    m_nowPlaying.ratingGroup = readConkyFile(QStringLiteral("currgpnum.txt"));

    // ── Query audtool for playback state and playlist info ──
    QString playbackStatus = queryAudtool({QStringLiteral("--playback-status")});
    m_nowPlaying.isPlaying = (playbackStatus == QStringLiteral("playing"));

    if (m_nowPlaying.isPlaying) {
        m_nowPlaying.songPath = queryAudtool({QStringLiteral("--current-song-filename")});

        QString posStr = queryAudtool({QStringLiteral("--playlist-position")});
        QString lenStr = queryAudtool({QStringLiteral("--playlist-length")});
        m_nowPlaying.playlistPosition = posStr.toInt();
        m_nowPlaying.playlistLength   = lenStr.toInt();

        // Ask audtool which playlist is currently active (1-based index),
        // then resolve that to a name via the 'order' file.
        // This is unambiguous even when the same song appears in multiple
        // playlists (e.g. a big "Library" playlist and a curated one).
        m_nowPlaying.playlistName.clear();
        QString curPlStr = queryAudtool({QStringLiteral("--current-playlist")});
        bool plOk = false;
        int curPlIndex = curPlStr.toInt(&plOk); // 1-based
        if (plOk && curPlIndex >= 1) {
            QString orderPath = m_audaciousPlaylistsDir + QStringLiteral("/order");
            QFile orderFile(orderPath);
            if (orderFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QStringList ids = QString::fromUtf8(orderFile.readAll())
                                      .trimmed()
                                      .split(QLatin1Char(' '), Qt::SkipEmptyParts);
                orderFile.close();
                if (curPlIndex - 1 < ids.size()) {
                    const QString &id = ids.at(curPlIndex - 1);
                    QString audplPath = m_audaciousPlaylistsDir
                                        + QStringLiteral("/") + id
                                        + QStringLiteral(".audpl");
                    QFile audplFile(audplPath);
                    if (audplFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                        QString firstLine = QString::fromUtf8(
                            audplFile.readLine()).trimmed();
                        audplFile.close();
                        if (firstLine.startsWith(QLatin1String("title=")))
                            m_nowPlaying.playlistName = QUrl::fromPercentEncoding(
                                firstLine.mid(6).toUtf8());
                    }
                }
            }
        }
    }

    // ── Update toolbar: Now Playing label ──
    if (m_nowPlaying.isPlaying && !m_nowPlaying.artist.isEmpty()) {
        m_nowPlayingLabel->setText(
            m_nowPlaying.artist
            + QStringLiteral(" \u2013 ")
            + m_nowPlaying.title);
    } else {
        m_nowPlayingLabel->setText(i18n("Not playing"));
    }

    // ── Update toolbar: Star buttons ──
    int currentRating = m_nowPlaying.ratingGroup.toInt();
    for (int i = 1; i <= 5; ++i) {
        if (i <= currentRating) {
            m_starButtons[i]->setText(QString(QChar(0x2605)));  // ★
        } else {
            m_starButtons[i]->setText(QString(QChar(0x2606)));  // ☆
        }
    }

    // ── Update status bar ──
    m_statusLabel->setText(buildStatusBarText());
}

// ═════════════════════════════════════════════════════════════
// Rate current track
// ═════════════════════════════════════════════════════════════

void MainWindow::rateCurrentTrack(int stars)
{
    if (stars < 0 || stars > 5) {
        return;
    }

    if (m_nowPlaying.songPath.isEmpty()) {
        statusBar()->showMessage(i18n("No track playing to rate."), 3000);
        return;
    }

    m_scriptRunner->rate(m_nowPlaying.songPath, stars);

    // Optimistic UI update
    m_nowPlaying.ratingGroup = QString::number(stars);
    for (int i = 1; i <= 5; ++i) {
        if (i <= stars) {
            m_starButtons[i]->setText(QString(QChar(0x2605)));
        } else {
            m_starButtons[i]->setText(QString(QChar(0x2606)));
        }
    }

    statusBar()->showMessage(
        i18n("Rated: %1 – %2 (%3 stars)",
             m_nowPlaying.artist, m_nowPlaying.title, stars),
        3000);
}

// ═════════════════════════════════════════════════════════════
// Album detail window
// ═════════════════════════════════════════════════════════════

void MainWindow::showAlbumWindow()
{
    if (!m_nowPlaying.isPlaying || m_nowPlaying.songPath.isEmpty()) {
        statusBar()->showMessage(i18n("No track playing."), 3000);
        return;
    }

    int albumId = -1;
    const int rowCount = m_libraryModel->rowCount();
    for (int row = 0; row < rowCount; ++row) {
        TrackRecord record = m_libraryModel->trackAt(row);
        if (record.songPath == m_nowPlaying.songPath) {
            albumId = record.idAlbum.toInt();
            break;
        }
    }

    if (albumId < 0) {
        statusBar()->showMessage(i18n("Current track not found in database."), 3000);
        return;
    }

    if (!m_albumWindow) {
        m_albumWindow = new AlbumWindow(this);
    }

    QString artworkPath = m_musicDisplayDir + QStringLiteral("/folder.jpg");

    m_albumWindow->populate(
        m_libraryModel,
        albumId,
        m_nowPlaying.artist,
        m_nowPlaying.album,
        m_nowPlaying.year,
        artworkPath,
        m_nowPlaying.comment);

    m_albumWindow->show();
    m_albumWindow->raise();
    m_albumWindow->activateWindow();
}

// ═════════════════════════════════════════════════════════════
// External app: Audacious — raise to foreground or launch
// ═════════════════════════════════════════════════════════════

void MainWindow::onRaiseAudacious()
{
    if (!isProcessRunning(QStringLiteral("audacious"))) {
        QProcess::startDetached(QStringLiteral("/usr/bin/audacious"), {});
        return;
    }

    QProcess showCmd;
    showCmd.start(QStringLiteral("audtool"),
                  {QStringLiteral("--mainwin-show"), QStringLiteral("on")});
    showCmd.waitForFinished(2000);

    QThread::msleep(100);

    raiseWindowByClass(QStringLiteral("audacious"));
}

// ═════════════════════════════════════════════════════════════
// External app: Kid3 — open current track or raise existing
// ═════════════════════════════════════════════════════════════

void MainWindow::onOpenKid3()
{
    // Determine which Kid3 version to use from config
    QString kid3GuiVersion = m_confWriter->value("KID3_GUI_INSTALLED");
    
    if (kid3GuiVersion != "kid3" && kid3GuiVersion != "kid3-qt") {
        // No GUI version installed - should not reach here if button is disabled
        return;
    }
    
    // Determine the process name and executable path
    QString processName = kid3GuiVersion;  // "kid3" or "kid3-qt"
    QString executablePath = "/usr/bin/" + kid3GuiVersion;
    QString windowClass = (kid3GuiVersion == "kid3") ? QStringLiteral("kid3") : QStringLiteral("kid3");
    
    // Get current track path from Audacious
    QString currentTrackPath;
    QProcess audtoolQuery;
    audtoolQuery.start(QStringLiteral("audtool"),
                       {QStringLiteral("--current-song-filename")});
    if (audtoolQuery.waitForFinished(2000)) {
        if (audtoolQuery.exitCode() == 0) {
            currentTrackPath = QString::fromUtf8(
                audtoolQuery.readAllStandardOutput()).trimmed();
        }
    }

    // Check if Kid3 is already running
    if (isProcessRunning(processName)) {
        raiseWindowByClass(windowClass);
    } else {
        // Launch Kid3 with current track if available
        if (!currentTrackPath.isEmpty() && QFile::exists(currentTrackPath)) {
            QProcess::startDetached(executablePath, {currentTrackPath});
        } else {
            QProcess::startDetached(executablePath, {});
        }
    }
}

// ═════════════════════════════════════════════════════════════
// Window raise helper — KX11Extras (X11) / KWin D-Bus (Wayland)
// ═════════════════════════════════════════════════════════════

void MainWindow::raiseWindowByClass(const QString &windowClass)
{
    if (KWindowSystem::isPlatformX11()) {
        const QByteArray targetClass = windowClass.toLower().toUtf8();
        const QList<WId> windowList = KX11Extras::windows();
        for (WId wid : windowList) {
            KWindowInfo info(wid, NET::Properties(), NET::WM2WindowClass);
            if (info.windowClassClass().toLower().contains(targetClass)) {
                KX11Extras::forceActiveWindow(wid);
                return;
            }
        }
    } else if (KWindowSystem::isPlatformWayland()) {
        QDBusInterface kwin(QStringLiteral("org.kde.KWin"),
                            QStringLiteral("/KWin"),
                            QStringLiteral("org.kde.KWin"));
        if (kwin.isValid()) {
            kwin.call(QStringLiteral("activateWindow"), windowClass);
        }
    }
}

// ═════════════════════════════════════════════════════════════
// Process check helper
// ═════════════════════════════════════════════════════════════

bool MainWindow::isProcessRunning(const QString &processName) const
{
    QProcess pgrep;
    pgrep.start(QStringLiteral("pgrep"),
                {QStringLiteral("-x"), processName});
    pgrep.waitForFinished(1000);
    return (pgrep.exitCode() == 0);
}

// ═════════════════════════════════════════════════════════════
// Conky output file reader
// ═════════════════════════════════════════════════════════════

QString MainWindow::readConkyFile(const QString &filename) const
{
    QString path = m_musicDisplayDir + QStringLiteral("/") + filename;
    QFile file(path);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }

    QTextStream stream(&file);
    QString content = stream.readLine().trimmed();
    file.close();
    return content;
}

QString MainWindow::conkyOutputDir() const
{
    return m_musicDisplayDir;
}

// ═════════════════════════════════════════════════════════════
// Audtool query helper (synchronous, short timeout)
// ═════════════════════════════════════════════════════════════

QString MainWindow::queryAudtool(const QStringList &args) const
{
    QProcess proc;
    proc.start(QStringLiteral("audtool"), args);

    if (!proc.waitForFinished(1000)) {
        proc.kill();
        return QString();
    }

    if (proc.exitCode() != 0) {
        return QString();
    }

    return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
}

// ═════════════════════════════════════════════════════════════
// Status bar text builder
// ═════════════════════════════════════════════════════════════

QString MainWindow::buildStatusBarText() const
{
    if (!m_nowPlaying.isPlaying || m_nowPlaying.artist.isEmpty()) {
        return i18n("Stopped");
    }

    QString text = QStringLiteral("Playing: ")
        + m_nowPlaying.artist
        + QStringLiteral(" - ")
        + m_nowPlaying.album;

    if (!m_nowPlaying.year.isEmpty()) {
        text += QStringLiteral(" (") + m_nowPlaying.year + QStringLiteral(")");
    }

    text += QStringLiteral(" - ") + m_nowPlaying.title;

    if (!m_nowPlaying.lastPlayed.isEmpty()) {
        text += QStringLiteral("  Last Played: ") + m_nowPlaying.lastPlayed;
    }

    if (m_nowPlaying.playlistLength > 0) {
        QString playlistDisplay = m_nowPlaying.playlistName.isEmpty()
            ? i18n("Active")
            : m_nowPlaying.playlistName;

        text += QStringLiteral("  Playlist: ")
            + playlistDisplay
            + QStringLiteral(" (")
            + QString::number(m_nowPlaying.playlistPosition)
            + QStringLiteral(" of ")
            + QString::number(m_nowPlaying.playlistLength)
            + QStringLiteral(")");
    }

    return text;
}

// ═════════════════════════════════════════════════════════════
// Audtool async handler (reserved for future use)
// ═════════════════════════════════════════════════════════════

void MainWindow::onAudtoolFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitCode);
    Q_UNUSED(exitStatus);
}
