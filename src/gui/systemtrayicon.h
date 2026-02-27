// systemtrayicon.h
// MusicLib Qt GUI — System Tray Icon
//
// Provides:
//   Left-click popup (track playing)
//     • Header:     Artist — Title  (bold)
//     • Sub-header: filepath (truncated, copyable via tooltip / inline button)
//     • Star widget — 5 large, clickable, inline
//     • [Edit in Kid3]   [Library Record]
//     • [Copy Filepath]  [Undo Rating]  (Undo grayed when no session change)
//
//   Left-click popup (no track / Audacious stopped)
//     • Header: "No track playing"
//     • Track action widgets hidden
//     • [Open Library] active
//     • Tray icon shifts to dimmed/dormant variant
//
//   Tooltip
//     • Artist — Title — ★★★☆☆   (or "No track playing · unrated")
//     • Second line when a background task is active:
//       "Scanning: 234/1,840 files"
//
//   Right-click menu
//     Library | Maintenance | Mobile
//     ────────────────────────────
//     Settings | Quit
//
// Copyright (c) 2026 MusicLib Project

#pragma once

#include <QSystemTrayIcon>
#include <QIcon>
#include <QString>

// Forward declarations
class MainWindow;
class QMenu;
class QAction;
class QFrame;
class QLabel;
class QToolButton;
class QPushButton;
class QWidget;

/**
 * @brief System-tray presence for MusicLib.
 *
 * Constructed once by MainWindow.  Call updateTrackInfo() after every
 * now-playing refresh to keep the popup and tooltip current.
 */
class SystemTrayIcon : public QSystemTrayIcon
{
    Q_OBJECT

public:
    explicit SystemTrayIcon(MainWindow *mainWindow, QObject *parent = nullptr);
    ~SystemTrayIcon() override;

    // ── Public data type ────────────────────────────────────────────────────

    /** Snapshot of now-playing state; populated by MainWindow and pushed here. */
    struct TrackInfo {
        QString artist;
        QString title;
        QString filePath;   ///< Absolute path reported by audtool
        int     rating = 0; ///< 0 = unrated, 1-5 stars
        bool    isPlaying = false;
    };

    // ── State update API ────────────────────────────────────────────────────

    /**
     * Refresh popup and tooltip from new track data.
     * Call after every MainWindow::refreshNowPlaying().
     */
    void updateTrackInfo(const TrackInfo &info);

    /**
     * Display (or clear) a background-task progress line in the tooltip.
     * @param statusLine  e.g. "Scanning: 234/1,840 files"
     *                    Pass an empty string to clear.
     */
    void setBackgroundTaskStatus(const QString &statusLine);

public Q_SLOTS:
    void showPopup();
    void hidePopup();

private Q_SLOTS:
    void onActivated(QSystemTrayIcon::ActivationReason reason);

    // Popup actions
    void onRateStar(int stars);   ///< 1-5
    void onUndoRating();
    void onEditKid3();
    void onLibraryRecord();
    void onCopyFilepath();
    void onOpenLibrary();

    // Right-click menu actions
    void onMenuLibrary();
    void onMenuMaintenance();
    void onMenuMobile();
    void onMenuSettings();

private:
    // ── Builders ──
    void buildPopup();
    void buildContextMenu();

    // ── State refreshers ──
    void refreshPopupContent();
    void refreshTooltip();
    void updateTrayIcon();

    // ── Helpers ──
    QString truncatePath(const QString &path, int maxChars = 52) const;
    QString starsString(int rating) const;
    void raiseMainWindow(int panelIndex = 0);

    // ── Owner ──
    MainWindow *m_mainWindow;

    // ── Icons ──
    QIcon m_iconNormal;
    QIcon m_iconDormant;

    // ── Right-click context menu ──
    QMenu *m_contextMenu = nullptr;

    // ── Left-click popup ──
    QFrame      *m_popup        = nullptr;

    // Playing state widgets
    QLabel      *m_headerLabel  = nullptr;   ///< "Artist — Title"
    QLabel      *m_pathLabel    = nullptr;   ///< Truncated filepath
    QToolButton *m_starBtns[5]  = {};        ///< ★ / ☆ (large)
    QPushButton *m_kid3Btn      = nullptr;
    QPushButton *m_libraryBtn   = nullptr;   ///< "Library Record"
    QPushButton *m_copyBtn      = nullptr;
    QPushButton *m_undoBtn      = nullptr;

    // Dormant state widget
    QPushButton *m_openLibBtn   = nullptr;

    // ── Track state cache ──
    TrackInfo m_current;

    // ── Session rating tracking (for "Undo Rating") ──
    //   m_sessionRatingBefore == -1  → no change yet this session for this track
    //   >= 0                         → original rating before first change
    QString m_sessionFilePath;
    int     m_sessionRatingBefore = -1;

    // ── Background task status ──
    QString m_bgTaskStatus;
};
