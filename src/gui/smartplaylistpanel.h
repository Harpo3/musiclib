// smartplaylistpanel.h
// MusicLib Qt GUI — Smart Playlist Panel
//
// Provides a three-section panel for configuring, analyzing, and generating
// smart playlists using musiclib_smartplaylist_analyze.sh and
// musiclib_smartplaylist.sh.
//
// Section 1 (Configuration): Age-threshold spinboxes per POPM rating group,
//   playlist/sample/exclusion size controls, live constraint summary.
// Section 2 (Analyze): Preview button that runs the analyze script and
//   populates a per-group statistics table.
// Section 3 (Generate): Playlist name, Audacious load option, progress bar,
//   and scrolling generation log.
//
// Authority model: spinbox changes are written to both KConfig (via
// MusicLibSettings::self()) and musiclib.conf (via ConfWriter) on every
// change, mirroring the pattern used by CDRippingPanel.
//
// Copyright (c) 2026 MusicLib Project

#pragma once

#include <QWidget>
#include <QProcess>
#include <QByteArray>
#include <QVector>

class ConfWriter;

class QGroupBox;
class QSpinBox;
class QPushButton;
class QLabel;
class QTableWidget;
class QLineEdit;
class QCheckBox;
class QProgressBar;
class QTextEdit;
class QTimer;
class QScrollArea;

/**
 * @brief Smart Playlist generation panel.
 *
 * Construct with a ConfWriter instance — the same one owned by MainWindow.
 * The panel reads initial values from MusicLibSettings (KConfig) and keeps
 * KConfig + musiclib.conf in sync whenever the user changes a spinbox.
 */
class SmartPlaylistPanel : public QWidget
{
    Q_OBJECT

public:
    explicit SmartPlaylistPanel(ConfWriter *conf, QWidget *parent = nullptr);
    ~SmartPlaylistPanel() override;

Q_SIGNALS:
    /// Emitted after a successful playlist generation, carrying the output path.
    void playlistGenerated(const QString &playlistPath);

private Q_SLOTS:
    // ── Configuration group ──
    /// Called when any age-threshold spinbox value changes.
    void onThresholdChanged();
    /// Called when playlist-size, sample-size, or artist-exclusion changes.
    void onSizeChanged();
    /// Reset all spinboxes to KConfigXT-compiled defaults.
    void resetToDefaults();

    // ── Analyze group ──
    /// Launch musiclib_smartplaylist_analyze.sh in preview mode.
    void runPreview();
    void onAnalyzeReadyRead();
    void onAnalyzeFinished(int exitCode, QProcess::ExitStatus status);

    // ── Generate group ──
    /// Launch musiclib_smartplaylist.sh with current settings.
    void runGenerate();
    void onGenerateReadyRead();
    void onGenerateFinished(int exitCode, QProcess::ExitStatus status);

    // ── Audacious availability ──
    /// Poll for a running Audacious process and update the load-checkbox state.
    void checkAudaciousRunning();

    // ── Live constraint display ──
    /// Fired by m_constraintDebounce; runs analyze in counts mode.
    void startCountsRun();
    /// Recomputes and renders the constraint summary from cached stats.
    void updateConstraintDisplay();

private:
    // ── UI construction helpers ──
    QGroupBox *createConfigGroup();
    QGroupBox *createAnalyzeGroup();
    QGroupBox *createGenerateGroup();

    // ── Config I/O ──
    /// Flush current threshold spinbox values to KConfig and musiclib.conf.
    void saveThresholdsToConfig();
    /// Flush playlist-size, sample-size, and artist-exclusion to KConfig and conf.
    void saveGenerationParamsToConfig();

    // ── Script helpers ──
    /// Resolve the full path of a script in the musiclib bin directory.
    /// Checks MUSICLIB_BIN_DIR from conf, then /usr/lib/musiclib/bin/, then PATH.
    QString scriptPath(const QString &scriptName) const;
    /// Build the -g threshold argument string "G1,G2,G3,G4,G5" from spinboxes.
    QString thresholdArg() const;
    /// Set busy state: disable/enable Preview and Generate buttons.
    void setBusy(bool busy);

    // ── Members ──
    ConfWriter *m_conf;

    QTimer     *m_constraintDebounce    = nullptr;  ///< 500ms debounce for counts refresh
    QTimer     *m_audaciousCheckTimer  = nullptr;  ///< 3s poll for Audacious process
    QProcess   *m_analyzeProcess       = nullptr;
    QProcess   *m_generateProcess      = nullptr;
    QByteArray  m_analyzeBuffer;                    ///< Accumulates stdout from analyze
    QByteArray  m_generateBuffer;                   ///< Accumulates stdout from generate
    bool        m_busy                 = false;     ///< True while any subprocess is running
    bool        m_analyzeIsPreview     = false;     ///< Distinguishes preview vs counts run

    /// Per-group statistics populated after each analyze run.
    struct GroupStats {
        int  eligibleTracks        = 0;
        int  uniqueArtistsRaw      = 0;  ///< Raw AlbumArtist distinct count
        int  uniqueArtistsEffective= 0;  ///< After Custom2 merging
        int  custom2CoveragePct    = 0;  ///< % of tracks with Custom2 set
        bool belowFloor            = false;
        // preview-mode fields
        double varianceTotal       = 0.0;
        double sampleWeightPct     = 0.0;
        int    sampleQty           = 0;
    };

    QVector<GroupStats> m_cachedStats;    ///< From last counts or preview run
    QVector<GroupStats> m_previousStats;  ///< From the run before that (for deltas)
    int m_cachedTotalEligible          = 0;
    int m_cachedUniqueArtistsEffective = 0;
    int m_cachedUniqueArtistsRaw       = 0;
    int m_cachedCustom2CoveragePct     = 0;

    // ── Configuration group widgets ──
    QSpinBox    *m_thresholdSpin[5]       = {};  ///< [0]=1★ … [4]=5★ age thresholds
    QSpinBox    *m_playlistSizeSpin       = nullptr;
    QSpinBox    *m_sampleSizeSpin         = nullptr;
    QSpinBox    *m_artistExclusionSpin    = nullptr;
    QPushButton *m_resetButton            = nullptr;
    QLabel      *m_constraintSummaryLabel = nullptr;

    // ── Analyze group widgets ──
    QPushButton  *m_previewButton      = nullptr;
    QTableWidget *m_previewTable       = nullptr;
    QLabel       *m_analyzeStatusLabel = nullptr;

    // ── Generate group widgets ──
    QLineEdit    *m_playlistNameEdit   = nullptr;
    QCheckBox    *m_loadAudaciousCheck = nullptr;
    QPushButton  *m_generateButton     = nullptr;
    QProgressBar *m_generateProgress   = nullptr;
    QTextEdit    *m_generateLog        = nullptr;
};
