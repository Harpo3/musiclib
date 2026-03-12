// cdrippingpanel.h
// MusicLib Qt GUI — CD Ripping Panel
//
// Wraps K3b CD ripping settings behind a Qt widget panel.
// Controls map directly to K3B_* keys in musiclib.conf and their
// derived counterparts in ~/.config/musiclib/k3brc.
//
// Panel lifecycle:
//   1. Constructor reads K3B_INSTALLED.  If false, shows a disabled
//      placeholder and skips all further setup (mirrors MaintenancePanel's
//      RSGAIN_INSTALLED pattern).
//   2. If installed: builds all controls, loads values from ConfWriter,
//      starts a 2-second poll timer for K3b running detection.
//
// Write-deploy pipeline (every control change):
//   onControlChanged() → write K3B_* to musiclib.conf (ConfWriter)
//                      → patchK3brc()  (update derived keys in musiclib k3brc)
//                      → deployK3brc() (copy musiclib k3brc → ~/.config/k3brc)
//
// Drift detection:
//   Compares managed keys between ~/.config/k3brc and
//   ~/.config/musiclib/k3brc.  Triggered on panel open and on every
//   K3b running→not-running transition.  Shows a banner with two
//   resolution buttons when drift is detected.
//
// Copyright (c) 2026 MusicLib Project

#pragma once

#include <QWidget>
#include <QString>

class QLabel;
class QFrame;
class QPushButton;
class QRadioButton;
class QButtonGroup;
class QComboBox;
class QSlider;
class QSpinBox;
class QGroupBox;
class QStackedWidget;
class QTimer;
class ConfWriter;

///
/// CDRippingPanel — K3b CD ripping settings panel.
///
/// All K3B_* config keys are read and written through the supplied
/// ConfWriter instance (the same one owned by MainWindow).
///
class CDRippingPanel : public QWidget
{
    Q_OBJECT

public:
    /// Construct the panel.
    /// @param confWriter  Shared ConfWriter for musiclib.conf access.
    /// @param parent      Parent widget (MainWindow).
    explicit CDRippingPanel(ConfWriter *confWriter, QWidget *parent = nullptr);
    ~CDRippingPanel() override;

    /// Run drift detection immediately (callable from MainWindow on panel switch and
    /// from onRipCdTriggered before launch).
    /// @returns true if drift was detected (banner shown), false if in sync.
    bool runDriftDetection();

    /// Patch the musiclib-managed k3brc with current ConfWriter values, then
    /// deploy it to ~/.config/k3brc.  Called by MainWindow before launching K3b
    /// (Scenario A of the toolbar Rip CD action).
    void patchAndDeployK3brc();

Q_SIGNALS:
    /// Emitted when the poll timer detects the K3b running→not-running transition.
    /// MainWindow connects to this to clean up the PID file after K3b exits.
    void k3bExited();

private Q_SLOTS:
    /// Poll timer — check whether K3b is currently running.
    void checkK3bRunning();

    /// Any control changed — write → patch → deploy.
    void onControlChanged();

    /// Output format radio changed — update sub-control visibility.
    void onFormatChanged();

    /// MP3 mode radio changed — update bitrate sub-control visibility.
    void onMp3ModeChanged();

    /// "Keep K3b changes" drift banner button.
    void onKeepK3bChanges();

    /// "Restore musiclib profile" drift banner button.
    void onRestoreMuslibProfile();

    /// "Reset to defaults" button.
    void onResetToDefaults();

private:
    // ── UI construction ──
    void buildUi();
    QGroupBox *createFormatGroup();
    QGroupBox *createParanoiaGroup();
    QFrame    *createDriftBanner();

    // ── Config helpers ──

    /// Populate all controls from current ConfWriter values.
    void loadFromConf();

    // ── K3brc pipeline ──

    /// Update all derived keys in the given k3brc file path in-place.
    /// Uses QProcess+sed to apply each substitution.
    void patchK3brc();

    /// Copy ~/.config/musiclib/k3brc → ~/.config/k3brc.
    void deployK3brc();

    // ── Control enable/disable ──

    /// Enable or disable all ripping controls (used for K3b-running state).
    void setControlsEnabled(bool enabled);

    // ── Helpers ──

    /// Assemble the lame command string from current K3B_MP3_* values.
    QString buildLameCommand() const;

    /// Map K3B_ENCODER_FORMAT → k3brc encoder= value.
    static QString encoderPluginForFormat(const QString &format);

    // ── Members ──
    ConfWriter *m_confWriter = nullptr;
    QTimer     *m_pollTimer  = nullptr;
    bool        m_k3bInstalled   = false;
    bool        m_k3bWasRunning  = false;   ///< Previous poll state (for transition detection)
    bool        m_loadingValues  = false;   ///< True while loadFromConf() is running

    // Format group
    QRadioButton *m_fmtMp3  = nullptr;
    QRadioButton *m_fmtOgg  = nullptr;
    QRadioButton *m_fmtFlac = nullptr;
    QButtonGroup *m_fmtGroup = nullptr;

    // MP3 mode group (visible only when MP3 selected)
    QGroupBox    *m_mp3ModeBox   = nullptr;
    QRadioButton *m_modeCbr      = nullptr;
    QRadioButton *m_modeVbr      = nullptr;
    QRadioButton *m_modeAbr      = nullptr;
    QButtonGroup *m_mp3ModeGroup = nullptr;

    // MP3 sub-controls (each visible only for its matching mode)
    QWidget  *m_cbrWidget  = nullptr;   ///< Container for CBR bitrate dropdown
    QWidget  *m_vbrWidget  = nullptr;   ///< Container for VBR quality slider
    QWidget  *m_abrWidget  = nullptr;   ///< Container for ABR target spinbox
    QComboBox *m_cbrBitrate = nullptr;
    QSlider   *m_vbrQuality = nullptr;
    QLabel    *m_vbrLabel   = nullptr;
    QSpinBox  *m_abrTarget  = nullptr;

    // Ogg Vorbis quality (visible only when Ogg selected)
    QWidget *m_oggWidget  = nullptr;
    QSlider *m_oggQuality = nullptr;
    QLabel  *m_oggLabel   = nullptr;

    // Error correction
    QRadioButton *m_paranoia0 = nullptr;   ///< Off
    QRadioButton *m_paranoia1 = nullptr;   ///< Overlap
    QRadioButton *m_paranoia2 = nullptr;   ///< Never skip
    QRadioButton *m_paranoia3 = nullptr;   ///< Full paranoia
    QButtonGroup *m_paranoiaGroup = nullptr;

    // Sector retry
    QSpinBox *m_retries = nullptr;

    // Output directory (read-only label)
    QLabel *m_outputDirLabel = nullptr;

    // Reset button
    QPushButton *m_resetBtn = nullptr;

    // K3b running state banner
    QLabel *m_runningLabel = nullptr;

    // Drift banner
    QFrame      *m_driftBanner          = nullptr;
    QPushButton *m_keepK3bBtn           = nullptr;
    QPushButton *m_restoreMuslibBtn     = nullptr;

    // Main controls container — disabled when K3b is running
    QWidget *m_controlsContainer = nullptr;
};
