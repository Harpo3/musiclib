// mobile_panel.h - Mobile sync panel for MusicLib GUI
// Phase 3: KDE Integration
//
// Wraps all musiclib_mobile.sh subcommands behind a three-stage GUI:
//   Select → Preview → Execute
//
// Backend script: musiclib_mobile.sh
// Backend API: Section 2.2 (Mobile Operations)
//
// Toolbar integration: The toolbar playlist dropdown fires
//   MainWindow::onPlaylistSelected() → switchToMobileWithPlaylist()
//   which calls setPlaylist() on this panel and switches the stacked
//   widget to PanelMobile.
//
// Script path resolution: Uses ScriptRunner::resolveScript() (static)
//   which checks ~/musiclib/bin/ then /usr/lib/musiclib/bin/.
//   No scriptsDir parameter needed.

#ifndef MOBILEPANEL_H
#define MOBILEPANEL_H

#include <QWidget>
#include <QComboBox>
#include <QCheckBox>
#include <QDateTimeEdit>
#include <QGroupBox>
#include <QLabel>
#include <QProgressBar>
#include <QPushButton>
#include <QTableWidget>
#include <QTextEdit>
#include <QProcess>

// Represents a single KDE Connect device parsed from kdeconnect-cli output
struct KDEConnectDevice {
    QString id;           // Device ID (hex string)
    QString name;         // Human-readable device name
    bool reachable;       // Currently reachable (paired + connected)
};

// Represents a playlist file found in PLAYLISTS_DIR
struct PlaylistEntry {
    QString filePath;     // Full path to .audpl/.m3u/.m3u8/.pls file
    QString displayName;  // Basename without extension (e.g. "workout")
    QString format;       // File extension lowercase (e.g. "audpl")
};

// Represents a track parsed from a playlist file (for preview table)
struct PreviewTrack {
    QString filePath;     // Absolute path extracted from playlist
    QString fileName;     // Basename only
    bool    exists;       // QFile::exists() result
    qint64  sizeBytes;    // File size (0 if missing)
};


class MobilePanel : public QWidget
{
    Q_OBJECT

public:
    /// Construct the panel.
    ///
    /// @param playlistsDir          PLAYLISTS_DIR from musiclib.conf
    /// @param audaciousPlaylistsDir AUDACIOUS_PLAYLISTS_DIR from musiclib.conf
    /// @param mobileDir             MOBILE_DIR from musiclib.conf
    /// @param parent                Parent widget (MainWindow)
    ///
    /// Script paths are resolved at invocation time via the static
    /// ScriptRunner::resolveScript(), so no scriptsDir parameter is needed.
    explicit MobilePanel(const QString &playlistsDir,
                         const QString &audaciousPlaylistsDir,
                         const QString &mobileDir,
                         const QString &configDeviceId,
                         QWidget *parent = nullptr);
    ~MobilePanel() override;

public Q_SLOTS:
    /// Called by MainWindow::switchToMobileWithPlaylist().
    /// Selects the matching playlist in the combo.
    void setPlaylist(const QString &playlistPath);

    /// Refresh the status section by running "musiclib_mobile.sh status"
    void refreshStatus();

Q_SIGNALS:
    /// Emitted after a successful upload completes (for status bar / tray)
    void uploadCompleted(const QString &playlistName, int trackCount);

private Q_SLOTS:
    // --- Device scanning ---
    void scanDevices();
    void onDeviceScanFinished(int exitCode, QProcess::ExitStatus exitStatus);

    // --- Playlist management ---
    void refreshPlaylists();
    void onPlaylistSelected(int index);
    void refreshFromAudacious();
    void onRefreshAudaciousFinished(int exitCode, QProcess::ExitStatus exitStatus);

    // --- Preview ---
    void showPreview();

    // --- Upload workflow ---
    void startUpload();
    void onUploadReadyRead();
    void onUploadFinished(int exitCode, QProcess::ExitStatus exitStatus);

    // --- Check-update (halt-if-newer gate) ---
    void onCheckUpdateFinished(int exitCode, QProcess::ExitStatus exitStatus);

    // --- Other operations ---
    void startRetry();
    void onRetryFinished(int exitCode, QProcess::ExitStatus exitStatus);

    void startUpdateLastPlayed();
    void onUpdateLastPlayedFinished(int exitCode, QProcess::ExitStatus exitStatus);

    void startCleanup();
    void onCleanupFinished(int exitCode, QProcess::ExitStatus exitStatus);

    void onStatusFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    // --- UI construction ---
    void setupUi();
    QGroupBox* createDeviceSection();
    QGroupBox* createPlaylistSection();
    QGroupBox* createOptionsSection();
    QWidget*   createActionButtons();
    QGroupBox* createPreviewSection();
    QGroupBox* createProgressSection();
    QGroupBox* createStatusSection();

    // --- Helpers ---

    /// Start a QProcess running a resolved script with bash.
    /// Uses ScriptRunner::resolveScript() for path lookup.
    /// Returns false if the script was not found.
    bool startScriptProcess(QProcess *process,
                            const QString &scriptName,
                            const QStringList &args);

    QList<PlaylistEntry> scanPlaylistDir() const;
    QList<PreviewTrack> parsePlaylist(const QString &filePath) const;
    QList<KDEConnectDevice> parseDeviceList(const QByteArray &output) const;
    void setOperationInProgress(bool busy);
    void appendOutput(const QString &line);
    void appendError(const QString &line);
    void parseProgressLine(const QString &line);
    void updateRetryButtonVisibility();

    /// Execute the actual upload (called after optional check-update gate)
    void executeUpload();

    // --- Configuration paths (from musiclib.conf, passed by MainWindow) ---
    QString m_playlistsDir;          // ~/.local/share/musiclib/playlists/
    QString m_audaciousPlaylistsDir; // ~/.config/audacious/playlists/
    QString m_mobileDir;             // ~/.local/share/musiclib/playlists/mobile/
    QString m_configDeviceId;        // DEVICE_ID from musiclib.conf (for default selection)

    // --- Async processes ---
    // MobilePanel manages its own QProcess instances rather than using
    // ScriptRunner::runScript() because:
    //   1. runScript() supports only one generic operation at a time
    //   2. MobilePanel needs concurrent processes (device scan, status,
    //      check-update, upload with streaming output)
    // ScriptRunner::resolveScript() is still used for path resolution.
    QProcess *m_deviceScanProcess;
    QProcess *m_uploadProcess;
    QProcess *m_statusProcess;
    QProcess *m_checkUpdateProcess;
    QProcess *m_operationProcess;     // Shared for retry/cleanup/refresh/update-lastplayed

    // --- State ---
    bool m_operationInProgress;
    QString m_pendingUploadPlaylist;  // Set by check-update flow, used by executeUpload()

    // --- Device section widgets ---
    QComboBox   *m_deviceCombo;
    QPushButton *m_deviceRefreshBtn;
    QLabel      *m_deviceStatusLabel;

    // --- Playlist section widgets ---
    QComboBox   *m_playlistCombo;
    QLabel      *m_formatLabel;
    QLabel      *m_trackCountLabel;
    QPushButton *m_refreshAudaciousBtn;

    // --- Options section widgets ---
    QCheckBox    *m_haltIfNewerCheck;
    QCheckBox    *m_endTimeCheck;
    QDateTimeEdit *m_endTimeEdit;

    // --- Action buttons ---
    QPushButton *m_previewBtn;
    QPushButton *m_uploadBtn;
    QPushButton *m_retryBtn;
    QPushButton *m_updateLastPlayedBtn;
    QPushButton *m_cleanupBtn;

    // --- Preview section widgets ---
    QGroupBox    *m_previewGroup;
    QTableWidget *m_previewTable;
    QLabel       *m_previewSummary;

    // --- Progress section widgets ---
    QGroupBox    *m_progressGroup;
    QProgressBar *m_progressBar;
    QTextEdit    *m_outputLog;

    // --- Status section widgets ---
    QGroupBox *m_statusGroup;
    QTextEdit *m_statusText;
};

#endif // MOBILEPANEL_H
