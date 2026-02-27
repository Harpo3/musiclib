// systemtrayicon.cpp
// MusicLib Qt GUI — System Tray Icon Implementation
// Copyright (c) 2026 MusicLib Project

#include "systemtrayicon.h"
#include "mainwindow.h"

#include <KLocalizedString>

#include <QApplication>
#include <QClipboard>
#include <QCursor>
#include <QFont>
#include <QFrame>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QMenu>
#include <QPainter>
#include <QPixmap>
#include <QPushButton>
#include <QScreen>
#include <QToolButton>
#include <QVBoxLayout>

// ═════════════════════════════════════════════════════════════
// Construction / Destruction
// ═════════════════════════════════════════════════════════════

SystemTrayIcon::SystemTrayIcon(MainWindow *mainWindow, QObject *parent)
    : QSystemTrayIcon(parent)
    , m_mainWindow(mainWindow)
{
    // ── Normal icon: reuse the application icon ──
    m_iconNormal = QIcon(QStringLiteral(":/icons/musiclib.png"));

    // ── Dormant icon: same artwork rendered at ~35 % opacity ──
    // We composite onto a transparent 32×32 pixmap so the icon dims cleanly
    // without leaving artefacts at the edge.
    {
        QPixmap src = m_iconNormal.pixmap(32, 32);
        QPixmap dst(32, 32);
        dst.fill(Qt::transparent);
        QPainter p(&dst);
        p.setOpacity(0.35);
        p.drawPixmap(0, 0, src);
        p.end();
        m_iconDormant = QIcon(dst);
    }

    setIcon(m_iconDormant);   // start in dormant state

    // ── Build UI ──
    buildPopup();
    buildContextMenu();

    // ── Wire activation signal ──
    connect(this, &QSystemTrayIcon::activated,
            this, &SystemTrayIcon::onActivated);
}

SystemTrayIcon::~SystemTrayIcon()
{
    // m_popup is a top-level QWidget with no parent — delete explicitly.
    delete m_popup;
}

// ═════════════════════════════════════════════════════════════
// State update API
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::updateTrackInfo(const TrackInfo &info)
{
    // ── Reset session rating tracking when the track changes ──
    if (info.filePath != m_sessionFilePath) {
        m_sessionFilePath     = info.filePath;
        m_sessionRatingBefore = -1;  // no change yet for this track
    }

    m_current = info;

    updateTrayIcon();
    refreshTooltip();

    if (m_popup->isVisible())
        refreshPopupContent();
}

void SystemTrayIcon::setBackgroundTaskStatus(const QString &statusLine)
{
    m_bgTaskStatus = statusLine;
    refreshTooltip();
}

// ═════════════════════════════════════════════════════════════
// Public slots
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::showPopup()
{
    refreshPopupContent();
    m_popup->adjustSize();

    // ── Position near the tray icon ──
    // QSystemTrayIcon::geometry() returns the icon's screen rect on X11/KDE.
    // Fall back to cursor position when unavailable (e.g. Wayland).
    QRect iconRect = geometry();
    QPoint pos;

    if (iconRect.isValid()) {
        // Prefer showing above the icon; the tray is usually at the bottom.
        pos = iconRect.topLeft();
        pos.setY(pos.y() - m_popup->sizeHint().height() - 6);
    } else {
        pos = QCursor::pos();
        pos.setY(pos.y() - m_popup->sizeHint().height() - 6);
    }

    // Clamp to available screen area
    QScreen *screen = QApplication::screenAt(pos.isNull() ? QCursor::pos() : pos);
    if (!screen)
        screen = QApplication::primaryScreen();
    const QRect avail = screen->availableGeometry();

    if (pos.x() + m_popup->sizeHint().width() > avail.right())
        pos.setX(avail.right() - m_popup->sizeHint().width());
    if (pos.x() < avail.left())
        pos.setX(avail.left());
    if (pos.y() < avail.top()) {
        // No room above → show below icon
        pos.setY(iconRect.isValid() ? iconRect.bottom() + 6
                                    : QCursor::pos().y() + 6);
    }

    m_popup->move(pos);
    m_popup->show();
    m_popup->raise();
    m_popup->activateWindow();
}

void SystemTrayIcon::hidePopup()
{
    m_popup->hide();
}

// ═════════════════════════════════════════════════════════════
// Private slots — activation
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::onActivated(QSystemTrayIcon::ActivationReason reason)
{
    if (reason == QSystemTrayIcon::Trigger) {
        // Left-click: toggle popup
        if (m_popup->isVisible())
            hidePopup();
        else
            showPopup();
    } else if (reason == QSystemTrayIcon::DoubleClick) {
        // Double-click: restore the main window if it is hidden, or
        // hide it if it is currently visible (toggle).
        hidePopup();  // dismiss popup if accidentally triggered
        if (m_mainWindow->isVisible()) {
            m_mainWindow->hide();
        } else {
            m_mainWindow->show();
            m_mainWindow->raise();
            m_mainWindow->activateWindow();
        }
    }
    // Right-click is handled automatically by the context menu set via
    // QSystemTrayIcon::setContextMenu().
}

// ═════════════════════════════════════════════════════════════
// Private slots — popup actions
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::onRateStar(int stars)
{
    if (!m_current.isPlaying || m_current.filePath.isEmpty())
        return;

    // Capture the "before" rating the first time we change it this session.
    if (m_sessionRatingBefore < 0)
        m_sessionRatingBefore = m_current.rating;

    m_mainWindow->rateCurrentTrack(stars);

    // Optimistic local update so the stars redraw immediately.
    m_current.rating = stars;
    refreshPopupContent();
    refreshTooltip();
}

void SystemTrayIcon::onUndoRating()
{
    if (m_sessionRatingBefore < 0 || !m_current.isPlaying)
        return;

    const int original = m_sessionRatingBefore;
    m_sessionRatingBefore = -1;   // reset — undo is a one-shot

    m_mainWindow->rateCurrentTrack(original);

    m_current.rating = original;
    refreshPopupContent();
    refreshTooltip();
}

void SystemTrayIcon::onEditKid3()
{
    hidePopup();
    m_mainWindow->onOpenKid3();
}

void SystemTrayIcon::onLibraryRecord()
{
    hidePopup();
    raiseMainWindow();
    m_mainWindow->showAlbumWindow();
}

void SystemTrayIcon::onCopyFilepath()
{
    QApplication::clipboard()->setText(m_current.filePath);
    // Leave popup open so the user can still interact with it.
}

void SystemTrayIcon::onOpenLibrary()
{
    hidePopup();
    raiseMainWindow(MainWindow::PanelLibrary);
}

// ═════════════════════════════════════════════════════════════
// Private slots — right-click menu actions
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::onMenuLibrary()
{
    raiseMainWindow(MainWindow::PanelLibrary);
}

void SystemTrayIcon::onMenuMaintenance()
{
    raiseMainWindow(MainWindow::PanelMaintenance);
}

void SystemTrayIcon::onMenuMobile()
{
    raiseMainWindow(MainWindow::PanelMobile);
}

void SystemTrayIcon::onMenuSettings()
{
    raiseMainWindow();
    m_mainWindow->showSettingsDialog();
}

// ═════════════════════════════════════════════════════════════
// Builder: popup widget
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::buildPopup()
{
    // Qt::Popup — auto-closes on any click outside the widget.
    // Qt::Tool  — no taskbar entry and a thinner title bar on some platforms.
    m_popup = new QFrame(nullptr,
                         Qt::Popup | Qt::FramelessWindowHint);
    m_popup->setFrameShape(QFrame::StyledPanel);
    m_popup->setFrameShadow(QFrame::Raised);
    m_popup->setMinimumWidth(310);

    auto *root = new QVBoxLayout(m_popup);
    root->setSpacing(6);
    root->setContentsMargins(12, 12, 12, 12);

    // ── Header: "Artist — Title"  ────────────────────────────────────────
    m_headerLabel = new QLabel(m_popup);
    {
        QFont f = m_headerLabel->font();
        f.setPointSize(f.pointSize() + 2);
        f.setBold(true);
        m_headerLabel->setFont(f);
    }
    m_headerLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_headerLabel->setWordWrap(false);
    root->addWidget(m_headerLabel);

    // ── Sub-header: truncated filepath  ─────────────────────────────────
    m_pathLabel = new QLabel(m_popup);
    {
        QFont f = m_pathLabel->font();
        f.setFamily(QStringLiteral("monospace"));
        f.setPointSize(qMax(f.pointSize() - 1, 7));
        m_pathLabel->setFont(f);
    }
    m_pathLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);
    // Full path shown in tooltip; truncated text shown inline.
    root->addWidget(m_pathLabel);

    // ── Horizontal rule ─────────────────────────────────────────────────
    auto *hr1 = new QFrame(m_popup);
    hr1->setFrameShape(QFrame::HLine);
    hr1->setFrameShadow(QFrame::Sunken);
    root->addWidget(hr1);

    // ── Star rating row (large, primary) ────────────────────────────────
    auto *starRow = new QHBoxLayout();
    starRow->setSpacing(2);
    {
        QFont starFont;
        starFont.setPointSize(22);   // big enough to tap easily
        for (int i = 0; i < 5; ++i) {
            m_starBtns[i] = new QToolButton(m_popup);
            m_starBtns[i]->setFont(starFont);
            m_starBtns[i]->setAutoRaise(true);
            m_starBtns[i]->setFixedSize(44, 44);
            m_starBtns[i]->setText(QString(QChar(0x2606)));  // ☆ default

            const int capturedI = i;
            connect(m_starBtns[i], &QToolButton::clicked,
                    this, [this, capturedI]() { onRateStar(capturedI + 1); });

            starRow->addWidget(m_starBtns[i]);
        }
        starRow->addStretch();
    }
    root->addLayout(starRow);

    // ── Action row 1: Kid3 | Library Record ─────────────────────────────
    auto *row1 = new QHBoxLayout();
    m_kid3Btn = new QPushButton(i18n("Edit in Kid3"), m_popup);
    m_libraryBtn = new QPushButton(i18n("Library Record"), m_popup);
    connect(m_kid3Btn,    &QPushButton::clicked, this, &SystemTrayIcon::onEditKid3);
    connect(m_libraryBtn, &QPushButton::clicked, this, &SystemTrayIcon::onLibraryRecord);
    row1->addWidget(m_kid3Btn);
    row1->addWidget(m_libraryBtn);
    root->addLayout(row1);

    // ── Action row 2: Copy Filepath | Undo Rating ────────────────────────
    auto *row2 = new QHBoxLayout();
    m_copyBtn = new QPushButton(i18n("Copy Filepath"), m_popup);
    m_undoBtn = new QPushButton(i18n("Undo Rating"), m_popup);
    connect(m_copyBtn, &QPushButton::clicked, this, &SystemTrayIcon::onCopyFilepath);
    connect(m_undoBtn, &QPushButton::clicked, this, &SystemTrayIcon::onUndoRating);
    row2->addWidget(m_copyBtn);
    row2->addWidget(m_undoBtn);
    root->addLayout(row2);

    // ── Horizontal rule ─────────────────────────────────────────────────
    auto *hr2 = new QFrame(m_popup);
    hr2->setFrameShape(QFrame::HLine);
    hr2->setFrameShadow(QFrame::Sunken);
    root->addWidget(hr2);

    // ── Dormant: Open Library button ────────────────────────────────────
    m_openLibBtn = new QPushButton(i18n("Open Library"), m_popup);
    connect(m_openLibBtn, &QPushButton::clicked, this, &SystemTrayIcon::onOpenLibrary);
    root->addWidget(m_openLibBtn);

    m_popup->adjustSize();
}

// ═════════════════════════════════════════════════════════════
// Builder: right-click context menu
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::buildContextMenu()
{
    m_contextMenu = new QMenu();   // no parent — owned by this class

    auto *libAction   = m_contextMenu->addAction(
        QIcon::fromTheme(QStringLiteral("view-media-track")),
        i18n("Library"));
    auto *maintAction = m_contextMenu->addAction(
        QIcon::fromTheme(QStringLiteral("tools-wizard")),
        i18n("Maintenance"));
    auto *mobileAction = m_contextMenu->addAction(
        QIcon::fromTheme(QStringLiteral("smartphone")),
        i18n("Mobile"));

    m_contextMenu->addSeparator();

    auto *settingsAction = m_contextMenu->addAction(
        QIcon::fromTheme(QStringLiteral("configure")),
        i18n("Settings"));
    auto *quitAction = m_contextMenu->addAction(
        QIcon::fromTheme(QStringLiteral("application-exit")),
        i18n("Quit"));

    connect(libAction,      &QAction::triggered, this, &SystemTrayIcon::onMenuLibrary);
    connect(maintAction,    &QAction::triggered, this, &SystemTrayIcon::onMenuMaintenance);
    connect(mobileAction,   &QAction::triggered, this, &SystemTrayIcon::onMenuMobile);
    connect(settingsAction, &QAction::triggered, this, &SystemTrayIcon::onMenuSettings);
    connect(quitAction,     &QAction::triggered, qApp, &QApplication::quit);

    setContextMenu(m_contextMenu);
}

// ═════════════════════════════════════════════════════════════
// State refreshers
// ═════════════════════════════════════════════════════════════

void SystemTrayIcon::refreshPopupContent()
{
    const bool playing = m_current.isPlaying && !m_current.title.isEmpty();

    // ── Header ──────────────────────────────────────────────────────────
    if (playing) {
        const QString header =
            m_current.artist.isEmpty()
            ? m_current.title
            : m_current.artist + QStringLiteral(" \u2014 ") + m_current.title;
        m_headerLabel->setText(header);
    } else {
        m_headerLabel->setText(i18n("No track playing"));
    }

    // ── Filepath sub-header ──────────────────────────────────────────────
    if (playing && !m_current.filePath.isEmpty()) {
        m_pathLabel->setText(truncatePath(m_current.filePath));
        m_pathLabel->setToolTip(m_current.filePath);
        m_pathLabel->show();
    } else {
        m_pathLabel->clear();
        m_pathLabel->setToolTip(QString());
        m_pathLabel->hide();
    }

    // ── Star buttons ─────────────────────────────────────────────────────
    for (int i = 0; i < 5; ++i) {
        m_starBtns[i]->setText(
            (i < m_current.rating)
            ? QString(QChar(0x2605))   // ★ filled
            : QString(QChar(0x2606))); // ☆ empty
        m_starBtns[i]->setEnabled(playing);
        m_starBtns[i]->setVisible(playing);
    }

    // ── Action buttons — only meaningful when playing ────────────────────
    m_kid3Btn->setEnabled(playing);
    m_kid3Btn->setVisible(playing);

    m_libraryBtn->setEnabled(playing);
    m_libraryBtn->setVisible(playing);

    m_copyBtn->setEnabled(playing);
    m_copyBtn->setVisible(playing);

    // Undo Rating: visible when playing, enabled only when a session change exists.
    m_undoBtn->setVisible(playing);
    m_undoBtn->setEnabled(playing && m_sessionRatingBefore >= 0);
    if (m_undoBtn->isEnabled()) {
        m_undoBtn->setToolTip(
            i18n("Restore rating to %1 ★", m_sessionRatingBefore));
    } else {
        m_undoBtn->setToolTip(
            i18n("No rating change this session"));
    }

    // ── Open Library — only shown in dormant state ───────────────────────
    m_openLibBtn->setVisible(!playing);
    m_openLibBtn->setEnabled(true);

    m_popup->adjustSize();
}

void SystemTrayIcon::refreshTooltip()
{
    QString tip;

    if (m_current.isPlaying && !m_current.title.isEmpty()) {
        // "Artist — Title — ★★★☆☆"
        if (!m_current.artist.isEmpty())
            tip = m_current.artist + QStringLiteral(" \u2014 ");
        tip += m_current.title;
        tip += QStringLiteral(" \u2014 ");
        tip += starsString(m_current.rating);
    } else {
        // Dormant nudge
        tip = i18n("MusicLib \u2014 No track playing");
    }

    // Optional background-task line
    if (!m_bgTaskStatus.isEmpty())
        tip += QStringLiteral("\n") + m_bgTaskStatus;

    setToolTip(tip);
}

void SystemTrayIcon::updateTrayIcon()
{
    setIcon(m_current.isPlaying ? m_iconNormal : m_iconDormant);
}

// ═════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════

/**
 * Truncate a path from the left, keeping the filename visible.
 * e.g.  /home/user/Music/Rock/Artist/Album/01 - Title.flac
 * →     …/Rock/Artist/Album/01 - Title.flac
 */
QString SystemTrayIcon::truncatePath(const QString &path, int maxChars) const
{
    if (path.length() <= maxChars)
        return path;
    return QStringLiteral("\u2026") + path.right(maxChars - 1);
}

/** Build a Unicode star string like ★★★☆☆ for the given 0-5 rating. */
QString SystemTrayIcon::starsString(int rating) const
{
    QString s;
    s.reserve(5);
    for (int i = 1; i <= 5; ++i)
        s += (i <= rating) ? QChar(0x2605) : QChar(0x2606);
    return s;
}

/** Show/raise the main window and optionally switch to the given panel. */
void SystemTrayIcon::raiseMainWindow(int panelIndex)
{
    m_mainWindow->show();
    m_mainWindow->raise();
    m_mainWindow->activateWindow();
    if (panelIndex >= 0)
        m_mainWindow->switchToPanel(panelIndex);
}
