// mainwindow.cpp
// MusicLib Qt GUI - Main Window Implementation (Dolphin-style sidebar layout)
// Phase 2: Settings Dialog prerequisite - Main window redesign
// Copyright (c) 2026 MusicLib Project

#include "mainwindow.h"
#include "albumwindow.h"
#include "librarymodel.h"
#include "libraryview.h"
#include "maintenancepanel.h"
#include "scriptrunner.h"

#include <KXmlGuiWindow>
#include <KActionCollection>
#include <KStandardAction>
#include <KLocalizedString>

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
#include <QProcess>
#include <QFileInfo>
#include <QIcon>
#include <QFont>
#include <QMessageBox>

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
    , m_settingsPanel(nullptr)
    , m_nowPlayingLabel(nullptr)
    , m_playlistDropdown(nullptr)
    , m_statusLabel(nullptr)
    , m_libraryModel(nullptr)
    , m_scriptRunner(nullptr)
    , m_nowPlayingTimer(nullptr)
    , m_fileWatcher(nullptr)
    , m_albumWindow(nullptr)
{
    setWindowTitle(i18n("MusicLib"));

    // ── Resolve config paths ──
    // These follow XDG conventions established by musiclib_init_config.sh.
    // Fallback to ~/musiclib for legacy installs.
    QString xdgData = QDir::homePath() + QStringLiteral("/.local/share/musiclib");
    QString xdgConfig = QDir::homePath() + QStringLiteral("/.config/musiclib");
    QString legacyRoot = QDir::homePath() + QStringLiteral("/musiclib");

    // Use XDG path if it exists, otherwise fall back to legacy
    if (QDir(xdgData).exists()) {
        m_musicDisplayDir = xdgData + QStringLiteral("/data/conky_output");
        m_databasePath    = xdgData + QStringLiteral("/data/musiclib.dsv");
        m_playlistsDir    = xdgData + QStringLiteral("/playlists");
    } else {
        m_musicDisplayDir = legacyRoot + QStringLiteral("/data/conky_output");
        m_databasePath    = legacyRoot + QStringLiteral("/data/musiclib.dsv");
        m_playlistsDir    = legacyRoot + QStringLiteral("/playlists");
    }

    // ── Create data model for album window and status queries ──
    // Note: LibraryView creates and manages its own internal LibraryModel.
    // This separate model instance is used by the Album window and for
    // looking up track data by SongPath (e.g., finding IDAlbum).
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
    // LibraryView creates its own LibraryModel internally.
    // We tell it to load the database, then keep a reference to its model.
    m_libraryPanel = new LibraryView(this);
    m_libraryPanel->loadDatabase(m_databasePath);
    m_panelStack->addWidget(m_libraryPanel);   // index 0

    // ── Maintenance panel (existing) ──
    m_maintenancePanel = new MaintenancePanel(m_scriptRunner, this);
    m_panelStack->addWidget(m_maintenancePanel);   // index 1

    // ── Mobile panel ──
    // Placeholder — will be replaced when Mobile Panel is built.
    m_mobilePanel = new QWidget(this);
    auto *mobileLayout = new QVBoxLayout(m_mobilePanel);
    auto *mobileLabel = new QLabel(
        i18n("Mobile Sync Panel\n\n"
             "Playlist upload, device selection, dry-run preview,\n"
             "progress tracking, and status view.\n\n"
             "(Connect existing MobilePanel widget here)"),
        m_mobilePanel);
    mobileLabel->setAlignment(Qt::AlignCenter);
    mobileLayout->addWidget(mobileLabel);
    m_panelStack->addWidget(m_mobilePanel);   // index 2

    // ── Settings panel ──
    // Placeholder — this is the next task after this main window redesign.
    m_settingsPanel = new QWidget(this);
    auto *settingsLayout = new QVBoxLayout(m_settingsPanel);
    auto *settingsLabel = new QLabel(
        i18n("Settings Panel\n\n"
             "KConfigXT settings mirroring musiclib.conf:\n"
             "• Music directory, DB path\n"
             "• KDE Connect device detection\n"
             "• Default rating for new tracks\n"
             "• Global shortcut assignments\n"
             "• System tray behavior\n\n"
             "(Settings panel implementation pending)"),
        m_settingsPanel);
    settingsLabel->setAlignment(Qt::AlignCenter);
    settingsLayout->addWidget(settingsLabel);
    m_panelStack->addWidget(m_settingsPanel);   // index 3
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
    // Displayed as clickable star characters in the toolbar.
    // Button 0 is hidden (clear rating), buttons 1-5 are shown.
    // Active stars are filled (★), inactive are empty (☆).
    for (int i = 0; i <= 5; ++i) {
        m_starButtons[i] = new QToolButton(this);
        m_starButtons[i]->setAutoRaise(true);
        m_starButtons[i]->setToolTip(
            i == 0 ? i18n("Clear rating")
                   : i18n("Rate %1 star(s)", i));

        // Star 0 (clear) uses an icon; stars 1-5 use text characters
        if (i == 0) {
            // Hidden by default — accessible via right-click or context menu
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
    m_playlistDropdown->setToolTip(i18n("Select a playlist — switches to Mobile panel"));
    populatePlaylistDropdown();
    connect(m_playlistDropdown, QOverload<int>::of(&QComboBox::activated),
            this, &MainWindow::onPlaylistSelected);
    toolbar->addWidget(m_playlistDropdown);

    toolbar->addSeparator();

    // ── Audacious button ──
    QAction *audaciousAction = new QAction(
        QIcon::fromTheme(QStringLiteral("audacious")),
        i18n("Audacious"), this);
    audaciousAction->setToolTip(i18n("Switch to Audacious (launch if needed)"));
    connect(audaciousAction, &QAction::triggered, this, &MainWindow::activateAudacious);
    toolbar->addAction(audaciousAction);

    // ── Kid3 button ──
    QAction *kid3Action = new QAction(
        QIcon::fromTheme(QStringLiteral("kid3-qt")),
        i18n("Kid3"), this);
    kid3Action->setToolTip(i18n("Switch to Kid3 tag editor (launch if needed)"));
    connect(kid3Action, &QAction::triggered, this, &MainWindow::activateKid3);
    toolbar->addAction(kid3Action);
}

// ═════════════════════════════════════════════════════════════
// Status bar setup
// ═════════════════════════════════════════════════════════════

void MainWindow::setupStatusBar()
{
    m_statusLabel = new QLabel(i18n("Ready"), this);
    statusBar()->addWidget(m_statusLabel, 1);  // stretch factor 1 = fill width
}

// ═════════════════════════════════════════════════════════════
// Standard KDE actions
// ═════════════════════════════════════════════════════════════

void MainWindow::setupActions()
{
    // Standard quit action
    KStandardAction::quit(qApp, &QCoreApplication::quit, actionCollection());

    // Could add more KDE standard actions here (preferences, etc.)
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
    if (currentRow >= 0 && currentRow < m_panelStack->count()) {
        m_panelStack->setCurrentIndex(currentRow);
    }
}

void MainWindow::switchToPanel(int index)
{
    if (index >= 0 && index < PanelCount) {
        m_sidebar->setCurrentRow(index);
    }
}

void MainWindow::switchToMobileWithPlaylist(const QString &playlistPath)
{
    switchToPanel(PanelMobile);

    // If the mobile panel has a method to pre-select a playlist, call it here.
    // For now, just switch to the panel — the playlist selection will be
    // handled when the mobile panel is fully implemented.
    Q_UNUSED(playlistPath);
}

// ═════════════════════════════════════════════════════════════
// Slot: Playlist dropdown selection
// ═════════════════════════════════════════════════════════════

void MainWindow::onPlaylistSelected(int index)
{
    if (index < 0) {
        return;
    }

    QString playlistPath = m_playlistDropdown->itemData(index).toString();
    if (!playlistPath.isEmpty()) {
        switchToMobileWithPlaylist(playlistPath);
    }
}

void MainWindow::populatePlaylistDropdown()
{
    m_playlistDropdown->clear();
    m_playlistDropdown->addItem(i18n("Select playlist..."), QString());

    QDir playlistDir(m_playlistsDir);
    if (!playlistDir.exists()) {
        return;
    }

    // List .audpl, .m3u, .m3u8, .pls files
    QStringList filters;
    filters << QStringLiteral("*.audpl")
            << QStringLiteral("*.m3u")
            << QStringLiteral("*.m3u8")
            << QStringLiteral("*.pls");

    QFileInfoList playlists = playlistDir.entryInfoList(
        filters, QDir::Files | QDir::Readable, QDir::Name);

    for (const QFileInfo &fi : playlists) {
        m_playlistDropdown->addItem(fi.fileName(), fi.absoluteFilePath());
    }
}

// ═════════════════════════════════════════════════════════════
// Slot: Database file changed
// ═════════════════════════════════════════════════════════════

void MainWindow::onDatabaseChanged(const QString &path)
{
    Q_UNUSED(path);

    // Reload models after a brief debounce
    // (QFileSystemWatcher may fire multiple times for a single write)
    QTimer::singleShot(500, this, [this]() {
        // Reload the album-query model
        m_libraryModel->loadFromFile(m_databasePath);

        // Reload the LibraryView's internal model
        m_libraryPanel->loadDatabase(m_databasePath);

        // Re-add the watch (some systems drop the watch after modification)
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

        // Playlist position and length
        QString posStr = queryAudtool({QStringLiteral("--playlist-position")});
        QString lenStr = queryAudtool({QStringLiteral("--playlist-length")});
        m_nowPlaying.playlistPosition = posStr.toInt();
        m_nowPlaying.playlistLength   = lenStr.toInt();

        // Try to determine the playlist name from Audacious
        // audtool doesn't directly expose the playlist filename,
        // so we read from the mobile tracking if available.
        QString currentPlaylistFile = m_playlistsDir
            + QStringLiteral("/mobile/current_playlist");
        QFile cpFile(currentPlaylistFile);
        if (cpFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            m_nowPlaying.playlistName = QTextStream(&cpFile).readLine().trimmed();
            cpFile.close();
        }
        // If no mobile tracking, try to get from audtool
        if (m_nowPlaying.playlistName.isEmpty()) {
            // audtool doesn't expose playlist filenames directly,
            // so we leave this blank or use a generic label
        }
    }

    // ── Update toolbar: Now Playing label ──
    if (m_nowPlaying.isPlaying && !m_nowPlaying.artist.isEmpty()) {
        m_nowPlayingLabel->setText(
            m_nowPlaying.artist
            + QStringLiteral(" \u2013 ")   // en-dash
            + m_nowPlaying.title);
    } else {
        m_nowPlayingLabel->setText(i18n("Not playing"));
    }

    // ── Update toolbar: Star buttons ──
    int currentRating = m_nowPlaying.ratingGroup.toInt();
    for (int i = 1; i <= 5; ++i) {
        if (i <= currentRating) {
            m_starButtons[i]->setText(QString(QChar(0x2605)));  // ★ filled
        } else {
            m_starButtons[i]->setText(QString(QChar(0x2606)));  // ☆ empty
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

    // Invoke musiclib_rate.sh via ScriptRunner::rate()
    // rate() expects the file path and star count.
    // It reads the current track path from audtool internally via the script,
    // but the ScriptRunner::rate() API requires us to pass the path explicitly.
    m_scriptRunner->rate(m_nowPlaying.songPath, stars);

    // Optimistic UI update — show the new rating immediately
    m_nowPlaying.ratingGroup = QString::number(stars);
    for (int i = 1; i <= 5; ++i) {
        if (i <= stars) {
            m_starButtons[i]->setText(QString(QChar(0x2605)));  // ★
        } else {
            m_starButtons[i]->setText(QString(QChar(0x2606)));  // ☆
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

    // Find the IDAlbum for the current track by looking up SongPath in the model
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

    // Create or reuse album window
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
// External app activation (Audacious, Kid3)
// ═════════════════════════════════════════════════════════════

void MainWindow::activateAudacious()
{
    raiseOrLaunchApp(QStringLiteral("audacious"),
                     QStringLiteral("/usr/bin/audacious"));
}

void MainWindow::activateKid3()
{
    raiseOrLaunchApp(QStringLiteral("kid3-qt"),
                     QStringLiteral("/usr/bin/kid3-qt"));
}

void MainWindow::raiseOrLaunchApp(const QString &processName,
                                  const QString &executablePath)
{
    // Try to raise using wmctrl (works on both X11 and Wayland with XWayland)
    // If the process isn't running, launch it.

    // Check if process is running
    QProcess pgrep;
    pgrep.start(QStringLiteral("pgrep"), {QStringLiteral("-x"), processName});
    pgrep.waitForFinished(2000);

    if (pgrep.exitCode() == 0) {
        // Process is running — try to raise its window
        // Use xdotool for X11, or kdotool / dbus for Wayland
        QProcess raise;
        raise.start(QStringLiteral("wmctrl"),
                    {QStringLiteral("-xa"), processName});
        raise.waitForFinished(2000);

        // Fallback if wmctrl isn't available: try xdotool
        if (raise.exitCode() != 0) {
            QProcess xdotool;
            xdotool.start(QStringLiteral("xdotool"),
                         {QStringLiteral("search"), QStringLiteral("--name"),
                          processName, QStringLiteral("windowactivate")});
            xdotool.waitForFinished(2000);
        }
    } else {
        // Not running — launch it
        QProcess::startDetached(executablePath, {});
    }
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
        // audtool didn't respond in 1 second — Audacious may not be running
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

    // Format: Playing: Artist - Album (Year) - Title  Last Played: date
    //         Playlist: name (pos of total)
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
    // Reserved for future async audtool queries
}
