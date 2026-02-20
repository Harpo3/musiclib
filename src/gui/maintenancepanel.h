#pragma once

#include <QWidget>
#include <QString>

class QPlainTextEdit;
class QPushButton;
class QLineEdit;
class QComboBox;
class QCheckBox;
class QSlider;
class QGroupBox;
class QLabel;
class ScriptRunner;

///
/// MaintenancePanel — GUI panel wrapping four maintenance shell scripts.
///
/// Operations:
///   1. Build Library      (musiclib_build.sh)       — full DB rebuild
///   2. Clean Tags         (musiclib_tagclean.sh)    — ID3 merge/strip/embed-art
///   3. Rebuild Tags       (musiclib_tagrebuild.sh)  — repair corrupted tags from DB
///   4. Boost Album        (boost_album.sh)          — ReplayGain loudness targeting
///
/// Each operation has a Preview button (--dry-run where supported) and an
/// Execute button.  Script stdout streams in real time to a shared log area
/// at the bottom of the panel.  Path inputs use KIO-backed file dialogs.
///
/// Browse dialogs default to the album directory of the currently playing
/// Audacious track (via audtool), falling back to MUSIC_REPO from config.
///
/// The Boost Album slider auto-reads the current integrated LUFS of the
/// first MP3 in the selected directory via ffmpeg's ebur128 filter.
///
class MaintenancePanel : public QWidget
{
    Q_OBJECT

public:
    explicit MaintenancePanel(ScriptRunner *runner, QWidget *parent = nullptr);

private slots:
    // --- Script lifecycle slots (connected to ScriptRunner) -----------------
    void onScriptOutput(const QString &operationId, const QString &line);
    void onScriptFinished(const QString &operationId, int exitCode,
                          const QString &stderrContent);

private:
    // --- UI construction helpers -------------------------------------------
    void buildUi();
    QGroupBox *createBuildGroup();
    QGroupBox *createTagCleanGroup();
    QGroupBox *createTagRebuildGroup();
    QGroupBox *createBoostGroup();

    // --- Operation launchers -----------------------------------------------
    void launchBuild(bool dryRun);
    void launchTagClean(bool dryRun);
    void launchTagRebuild(bool dryRun);
    void launchBoost();

    // --- Boost LUFS auto-detection -----------------------------------------

    /// Measure integrated LUFS of the first MP3 in dirPath via ffmpeg,
    /// then set the slider to that value (clamped to slider range).
    void updateBoostSliderFromDirectory(const QString &dirPath);

    // --- Helpers -----------------------------------------------------------

    /// Read a value from musiclib.conf via bash expansion.
    /// Uses the same source-and-echo pattern as MainWindow::configValue().
    static QString configValue(const QString &key);

    /// Resolve the starting directory for file dialogs.
    /// Prefers the album directory of the currently playing Audacious track
    /// (via audtool --current-song-filename, filename stripped).
    /// Falls back to MUSIC_REPO from config, then $HOME.
    QString browseStartDir() const;

    /// Open a KIO directory picker (native Plasma dialog under KDE).
    /// @param caption  Dialog title text.
    /// @return Selected directory path, or empty string if cancelled.
    QString pickDirectory(const QString &caption);

    /// Open a KIO file picker filtered to *.mp3.
    /// @param caption  Dialog title text.
    /// @return Selected file path, or empty string if cancelled.
    QString pickFile(const QString &caption);

    /// Enable or disable all Preview/Execute buttons.
    void setButtonsEnabled(bool enabled);

    /// Append a styled status line to the log (not script output — UI feedback).
    void logStatus(const QString &message);

    // --- Members -----------------------------------------------------------
    ScriptRunner *m_runner = nullptr;

    // Music directory from config (cached at construction)
    QString m_musicRepoDir;

    // Shared log area
    QPlainTextEdit *m_logOutput   = nullptr;
    QPushButton    *m_clearLogBtn = nullptr;

    // Build Library controls
    QPushButton *m_buildPreviewBtn  = nullptr;
    QPushButton *m_buildExecuteBtn  = nullptr;

    // Clean Tags controls
    QLineEdit   *m_tagCleanPath     = nullptr;
    QPushButton *m_tagCleanBrowse   = nullptr;
    QComboBox   *m_tagCleanMode     = nullptr;
    QPushButton *m_tagCleanPreview  = nullptr;
    QPushButton *m_tagCleanExecute  = nullptr;

    // Rebuild Tags controls
    QLineEdit   *m_tagRebuildPath     = nullptr;
    QPushButton *m_tagRebuildBrowse   = nullptr;
    QCheckBox   *m_tagRebuildRecursive = nullptr;
    QCheckBox   *m_tagRebuildVerbose  = nullptr;
    QPushButton *m_tagRebuildPreview  = nullptr;
    QPushButton *m_tagRebuildExecute  = nullptr;

    // Boost Album controls
    QLineEdit   *m_boostPath       = nullptr;
    QPushButton *m_boostBrowse     = nullptr;
    QSlider     *m_boostSlider     = nullptr;
    QLabel      *m_boostValueLabel = nullptr;
    QPushButton *m_boostExecuteBtn = nullptr;

    // Cancel (shared — visible only while a script is running)
    QPushButton *m_cancelBtn = nullptr;
};
