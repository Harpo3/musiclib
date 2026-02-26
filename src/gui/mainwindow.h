// mainwindow.h
// MusicLib Qt GUI - Main Window (Dolphin-style sidebar layout)
// Phase 2: Settings Dialog — KConfigXT mirroring musiclib.conf
//
// Replaces QTabWidget (tabs at top) with:
//   - QListWidget sidebar for panel navigation (Dolphin Places-style)
//   - QStackedWidget for panel content
//   - KToolBar with Now Playing, Album, Playlist, Audacious, Kid3 actions
//   - Rich status bar with track details from conky output + audtool
//
// Settings panel is a KConfigDialog opened on demand (not embedded in
// the stacked widget).  Sidebar "Settings" entry triggers the dialog.
//
// Copyright (c) 2026 MusicLib Project

#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <KXmlGuiWindow>

#include <QListWidget>
#include <QStackedWidget>
#include <QLabel>
#include <QTimer>
#include <QComboBox>
#include <QProcess>
#include <QFileSystemWatcher>
#include <QToolButton>

// Forward declarations - existing panels
class LibraryView;
class LibraryModel;
class MaintenancePanel;
class ScriptRunner;
class MobilePanel;  

// Forward declaration - new album window
class AlbumWindow;

// Forward declarations - settings
class ConfWriter;
class SettingsDialog;

/**
 * @brief Main application window with Dolphin-style sidebar navigation.
 *
 * Layout:
 *   ┌─────────┬────────────────────────────────────┐
 *   │ Toolbar: Now Playing ★★★ | Album | Playlist ▼ | Audacious | Kid3 │
 *   ├─────────┼────────────────────────────────────┤
 *   │         │                                    │
 *   │ Library │     Active Panel Content           │
 *   │ Maint.  │                                    │
 *   │ Mobile  │                                    │
 *   │ Settings│                                    │
 *   │         │                                    │
 *   ├─────────┴────────────────────────────────────┤
 *   │ Status: Playing: Artist - Album (Year) - Title  Last Played: ...  │
 *   └─────────────────────────────────────────────────────────────────────┘
 *
 * The "Settings" sidebar entry opens a KConfigDialog rather than switching
 * to an embedded panel.  This follows KDE convention where settings are
 * a modal-ish dialog, not a permanent workspace panel.
 */
class MainWindow : public KXmlGuiWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

    /// Switch to a specific panel by index
    void switchToPanel(int index);

    /// Switch to Mobile panel with a specific playlist pre-selected
    void switchToMobileWithPlaylist(const QString &playlistPath);

    /// Panel indices for sidebar navigation
    /// Note: PanelSettings is a virtual entry — clicking it opens the
    /// KConfigDialog rather than switching the stacked widget.
    enum PanelIndex {
        PanelLibrary = 0,
        PanelMaintenance,
        PanelMobile,
        PanelSettings,       // opens dialog, not a panel
        PanelCount           // sentinel - must be last
    };

public Q_SLOTS:
    /// Refresh now-playing data from conky output files and audtool
    void refreshNowPlaying();

    /// Rate the currently playing track (called from toolbar stars or global shortcut)
    void rateCurrentTrack(int stars);

    /// Open album detail window for the currently playing track
    void showAlbumWindow();

    /// Raise Audacious to the foreground, or launch it if not running.
    void onRaiseAudacious();

    /// Open the currently playing track in Kid3, or raise Kid3 if already running.
    void onOpenKid3();

    /// Open the Settings dialog (KConfigDialog).
    void showSettingsDialog();

private Q_SLOTS:
    /// Sidebar selection changed
    void onSidebarItemChanged(int currentRow);

    /// Playlist dropdown selection changed
    void onPlaylistSelected(int index);

    /// DSV file changed on disk (QFileSystemWatcher)
    void onDatabaseChanged(const QString &path);

    /// Now-playing poll timer fired
    void onNowPlayingTimer();

    /// Handle audtool process finished (for async queries)
    void onAudtoolFinished(int exitCode, QProcess::ExitStatus exitStatus);

    /// Settings dialog reported a database path change
    void onDatabasePathChanged();

    /// Settings dialog reported a poll interval change
    void onPollIntervalChanged(int newIntervalMs);

private:
    // ── Setup methods ──
    void setupSidebar();
    void setupPanels();
    void setupToolbar();
    void setupStatusBar();
    void setupNowPlayingTimer();
    void setupFileWatcher();
    void setupActions();
    void setupConfWriter();

    // ── Data reading helpers ──
    /// Read a single-line text file, trimmed. Returns empty string on failure.
    QString readConkyFile(const QString &filename) const;

    /// Get the conky output directory path from config
    QString conkyOutputDir() const;

    /// Query audtool for a value (synchronous, with short timeout)
    QString queryAudtool(const QStringList &args) const;

    /// Populate the playlist dropdown from the Audacious playlists directory
    void populatePlaylistDropdown();

    /// Raise an external window by WM_CLASS (X11) or caption (Wayland).
    void raiseWindowByClass(const QString &windowClass);

    /// Check whether a process is currently running (by exact name match via pgrep)
    bool isProcessRunning(const QString &processName) const;

    /// Build status bar text from current now-playing data
    QString buildStatusBarText() const;

    // ── Layout widgets ──
    QListWidget    *m_sidebar;         ///< Left navigation panel
    QStackedWidget *m_panelStack;      ///< Stacked content panels

    // ── Panels ──
    LibraryView      *m_libraryPanel;       ///< Library browser panel
    MaintenancePanel *m_maintenancePanel;   ///< Maintenance operations panel
    MobilePanel          *m_mobilePanel;        ///< Mobile sync panel

    // ── Toolbar widgets ──
    QLabel      *m_nowPlayingLabel;    ///< "Artist – Title" text in toolbar
    QToolButton *m_starButtons[6];     ///< Star rating buttons 0-5 (0 = clear)
    QComboBox   *m_playlistDropdown;   ///< Playlist selector dropdown

    // ── Status bar widgets ──
    QLabel *m_statusLabel;             ///< Rich status bar text

    // ── Data model ──
    LibraryModel *m_libraryModel;      ///< DSV data model
    ScriptRunner *m_scriptRunner;      ///< Shell script invoker

    // ── Timers and watchers ──
    QTimer             *m_nowPlayingTimer;  ///< Poll conky output files
    QFileSystemWatcher *m_fileWatcher;      ///< Watch musiclib.dsv for changes

    // ── Current now-playing state (cached from last poll) ──
    struct NowPlayingData {
        QString artist;
        QString album;
        QString title;
        QString year;
        QString comment;         // detail.txt
        QString lastPlayed;
        QString ratingGroup;     // currgpnum.txt (0-5)
        QString playlistName;
        int     playlistPosition = 0;
        int     playlistLength   = 0;
        QString songPath;        // full path of current track
        bool    isPlaying        = false;
    };
    NowPlayingData m_nowPlaying;

    // ── Album window ──
    AlbumWindow *m_albumWindow = nullptr;

    // ── Settings / config ──
    ConfWriter *m_confWriter;          ///< Shell config file reader/writer
    int m_lastSidebarIndex = 0;        ///< Tracks previous sidebar selection
                                       ///  (used to restore after Settings dialog)

    // ── Config cache ──
    QString m_musicDisplayDir;   // conky output directory
    QString m_databasePath;      // musiclib.dsv path
    QString m_playlistsDir;      // playlists directory
    QString m_audaciousPlaylistsDir;  // AUDACIOUS_PLAYLISTS_DIR
    QString m_mobileDir;              // MOBILE_DIR (playlists/mobile)
};

#endif // MAINWINDOW_H
