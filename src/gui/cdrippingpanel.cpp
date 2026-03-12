// cdrippingpanel.cpp
// MusicLib Qt GUI — CD Ripping Panel implementation
// Copyright (c) 2026 MusicLib Project

#include "cdrippingpanel.h"
#include "confwriter.h"

#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGroupBox>
#include <QLabel>
#include <QPushButton>
#include <QRadioButton>
#include <QButtonGroup>
#include <QComboBox>
#include <QSlider>
#include <QSpinBox>
#include <QFrame>
#include <QTimer>
#include <QProcess>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QScrollArea>
#include <QStackedWidget>
#include <QRegularExpression>

// ═════════════════════════════════════════════════════════════
// Construction / Destruction
// ═════════════════════════════════════════════════════════════

CDRippingPanel::CDRippingPanel(ConfWriter *confWriter, QWidget *parent)
    : QWidget(parent)
    , m_confWriter(confWriter)
{
    m_k3bInstalled = m_confWriter->boolValue(QStringLiteral("K3B_INSTALLED"), false);
    buildUi();

    if (!m_k3bInstalled)
        return;   // nothing else to set up

    // Load values into controls without triggering the write pipeline
    loadFromConf();

    // Startup running check — sets correct initial state without waiting
    // for the first timer tick.
    checkK3bRunning();

    // Start the 2-second K3b running-state poll timer.
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(2000);
    connect(m_pollTimer, &QTimer::timeout, this, &CDRippingPanel::checkK3bRunning);
    m_pollTimer->start();

    // Check for drift on panel construction.
    runDriftDetection();
}

CDRippingPanel::~CDRippingPanel() = default;

// ═════════════════════════════════════════════════════════════
// UI Construction
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::buildUi()
{
    auto *outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);

    auto *scrollArea = new QScrollArea;
    scrollArea->setWidgetResizable(true);
    scrollArea->setFrameShape(QFrame::NoFrame);

    auto *scrollWidget = new QWidget;
    auto *mainLayout   = new QVBoxLayout(scrollWidget);
    mainLayout->setContentsMargins(8, 8, 8, 8);
    mainLayout->setSpacing(8);

    if (!m_k3bInstalled) {
        // ── Not installed state ──
        auto *disabledGroup = new QGroupBox(tr("CD Ripping — K3b"));
        disabledGroup->setEnabled(false);
        auto *disabledLayout = new QVBoxLayout(disabledGroup);
        auto *disabledLabel = new QLabel(
            tr("<i>K3b is not installed. Install k3b and run setup again to enable CD ripping.</i>"));
        disabledLabel->setStyleSheet(QStringLiteral("color: gray;"));
        disabledLabel->setWordWrap(true);
        disabledLayout->addWidget(disabledLabel);
        mainLayout->addWidget(disabledGroup);
        mainLayout->addStretch();

        scrollArea->setWidget(scrollWidget);
        outerLayout->addWidget(scrollArea);
        return;
    }

    // ── K3b running banner (shown instead of controls when K3b is open) ──
    m_runningLabel = new QLabel(
        tr("<b>K3b is currently running — close K3b to adjust ripping settings.</b>"));
    m_runningLabel->setStyleSheet(
        QStringLiteral("QLabel { background: #fff3cd; color: #856404; "
                       "border: 1px solid #ffc107; border-radius: 4px; padding: 6px; }"));
    m_runningLabel->setWordWrap(true);
    m_runningLabel->setVisible(false);
    mainLayout->addWidget(m_runningLabel);

    // ── Drift banner ──
    mainLayout->addWidget(createDriftBanner());

    // ── Main controls container ──
    m_controlsContainer = new QWidget;
    auto *controlsLayout = new QVBoxLayout(m_controlsContainer);
    controlsLayout->setContentsMargins(0, 0, 0, 0);
    controlsLayout->setSpacing(8);

    controlsLayout->addWidget(createFormatGroup());
    controlsLayout->addWidget(createParanoiaGroup());

    // ── Output directory (read-only) ──
    auto *dirGroup  = new QGroupBox(tr("Rip Output Directory"));
    auto *dirLayout = new QHBoxLayout(dirGroup);
    m_outputDirLabel = new QLabel;
    m_outputDirLabel->setWordWrap(true);
    auto *settingsHint = new QLabel(
        tr("  <a href='#settings'>(change in Settings)</a>"));
    settingsHint->setTextInteractionFlags(Qt::LinksAccessibleByMouse);
    dirLayout->addWidget(m_outputDirLabel, 1);
    dirLayout->addWidget(settingsHint);
    controlsLayout->addWidget(dirGroup);

    // ── Reset button ──
    auto *resetRow = new QHBoxLayout;
    m_resetBtn = new QPushButton(tr("Reset to defaults"));
    m_resetBtn->setToolTip(
        tr("Remove user overrides for all K3b settings — system defaults will apply."));
    resetRow->addStretch();
    resetRow->addWidget(m_resetBtn);
    connect(m_resetBtn, &QPushButton::clicked, this, &CDRippingPanel::onResetToDefaults);
    controlsLayout->addLayout(resetRow);
    controlsLayout->addStretch();

    mainLayout->addWidget(m_controlsContainer);
    mainLayout->addStretch();

    scrollArea->setWidget(scrollWidget);
    outerLayout->addWidget(scrollArea);
}

// ---------------------------------------------------------------------------
//  Format group (MP3 / Ogg / FLAC + sub-controls)
// ---------------------------------------------------------------------------
QGroupBox *CDRippingPanel::createFormatGroup()
{
    auto *group  = new QGroupBox(tr("Output Format"));
    auto *layout = new QVBoxLayout(group);

    // ── Top-level format radios ──
    auto *fmtRow = new QHBoxLayout;
    m_fmtMp3  = new QRadioButton(tr("MP3"));
    m_fmtOgg  = new QRadioButton(tr("Ogg Vorbis"));
    m_fmtFlac = new QRadioButton(tr("FLAC"));
    m_fmtGroup = new QButtonGroup(this);
    m_fmtGroup->addButton(m_fmtMp3,  0);
    m_fmtGroup->addButton(m_fmtOgg,  1);
    m_fmtGroup->addButton(m_fmtFlac, 2);
    fmtRow->addWidget(m_fmtMp3);
    fmtRow->addWidget(m_fmtOgg);
    fmtRow->addWidget(m_fmtFlac);
    fmtRow->addStretch();
    layout->addLayout(fmtRow);

    // ── MP3 mode sub-group ──
    m_mp3ModeBox = new QGroupBox(tr("MP3 Encoding Mode"));
    auto *mp3Layout = new QVBoxLayout(m_mp3ModeBox);

    auto *modeRow = new QHBoxLayout;
    m_modeCbr = new QRadioButton(tr("CBR (Constant Bitrate)"));
    m_modeVbr = new QRadioButton(tr("VBR (Variable Bitrate)"));
    m_modeAbr = new QRadioButton(tr("ABR (Average Bitrate)"));
    m_mp3ModeGroup = new QButtonGroup(this);
    m_mp3ModeGroup->addButton(m_modeCbr, 0);
    m_mp3ModeGroup->addButton(m_modeVbr, 1);
    m_mp3ModeGroup->addButton(m_modeAbr, 2);
    modeRow->addWidget(m_modeCbr);
    modeRow->addWidget(m_modeVbr);
    modeRow->addWidget(m_modeAbr);
    modeRow->addStretch();
    mp3Layout->addLayout(modeRow);

    // CBR bitrate dropdown
    m_cbrWidget = new QWidget;
    auto *cbrLayout = new QHBoxLayout(m_cbrWidget);
    cbrLayout->setContentsMargins(0, 0, 0, 0);
    cbrLayout->addWidget(new QLabel(tr("Bitrate:")));
    m_cbrBitrate = new QComboBox;
    m_cbrBitrate->addItem(QStringLiteral("128 kbps"), 128);
    m_cbrBitrate->addItem(QStringLiteral("192 kbps"), 192);
    m_cbrBitrate->addItem(QStringLiteral("256 kbps"), 256);
    m_cbrBitrate->addItem(QStringLiteral("320 kbps"), 320);
    cbrLayout->addWidget(m_cbrBitrate);
    cbrLayout->addStretch();
    mp3Layout->addWidget(m_cbrWidget);

    // VBR quality slider  0=best/largest … 9=fastest/smallest
    m_vbrWidget = new QWidget;
    auto *vbrLayout = new QHBoxLayout(m_vbrWidget);
    vbrLayout->setContentsMargins(0, 0, 0, 0);
    vbrLayout->addWidget(new QLabel(tr("Quality (0=best, 9=smallest):")));
    m_vbrQuality = new QSlider(Qt::Horizontal);
    m_vbrQuality->setRange(0, 9);
    m_vbrQuality->setTickPosition(QSlider::TicksBelow);
    m_vbrQuality->setTickInterval(1);
    m_vbrQuality->setSingleStep(1);
    vbrLayout->addWidget(m_vbrQuality, 1);
    m_vbrLabel = new QLabel(QStringLiteral("2"));
    m_vbrLabel->setMinimumWidth(20);
    vbrLayout->addWidget(m_vbrLabel);
    connect(m_vbrQuality, &QSlider::valueChanged, this,
            [this](int v){ m_vbrLabel->setText(QString::number(v)); });
    mp3Layout->addWidget(m_vbrWidget);

    // ABR target spinbox
    m_abrWidget = new QWidget;
    auto *abrLayout = new QHBoxLayout(m_abrWidget);
    abrLayout->setContentsMargins(0, 0, 0, 0);
    abrLayout->addWidget(new QLabel(tr("Target bitrate (kbps):")));
    m_abrTarget = new QSpinBox;
    m_abrTarget->setRange(32, 320);
    m_abrTarget->setSingleStep(8);
    m_abrTarget->setValue(192);
    abrLayout->addWidget(m_abrTarget);
    abrLayout->addStretch();
    mp3Layout->addWidget(m_abrWidget);

    layout->addWidget(m_mp3ModeBox);

    // ── Ogg Vorbis quality slider  0-10 (10=best) ──
    m_oggWidget = new QWidget;
    auto *oggLayout = new QHBoxLayout(m_oggWidget);
    oggLayout->setContentsMargins(0, 0, 0, 0);
    oggLayout->addWidget(new QLabel(tr("Ogg Vorbis quality (0-10, 10=best):")));
    m_oggQuality = new QSlider(Qt::Horizontal);
    m_oggQuality->setRange(0, 10);
    m_oggQuality->setTickPosition(QSlider::TicksBelow);
    m_oggQuality->setTickInterval(1);
    m_oggQuality->setSingleStep(1);
    oggLayout->addWidget(m_oggQuality, 1);
    m_oggLabel = new QLabel(QStringLiteral("6"));
    m_oggLabel->setMinimumWidth(20);
    oggLayout->addWidget(m_oggLabel);
    connect(m_oggQuality, &QSlider::valueChanged, this,
            [this](int v){ m_oggLabel->setText(QString::number(v)); });
    layout->addWidget(m_oggWidget);

    // ── Wire visibility logic ──
    connect(m_fmtGroup, &QButtonGroup::idClicked, this, [this](int) {
        onFormatChanged();
    });
    connect(m_mp3ModeGroup, &QButtonGroup::idClicked, this, [this](int) {
        onMp3ModeChanged();
    });

    // ── Wire control-changed signals ──
    // Format radios
    connect(m_fmtMp3,  &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_fmtOgg,  &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_fmtFlac, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    // MP3 mode radios
    connect(m_modeCbr, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_modeVbr, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_modeAbr, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    // CBR, VBR, ABR sub-controls
    connect(m_cbrBitrate, QOverload<int>::of(&QComboBox::currentIndexChanged),
            this, [this](int){ onControlChanged(); });
    connect(m_vbrQuality, &QSlider::valueChanged, this, [this](int){ onControlChanged(); });
    connect(m_abrTarget,  QOverload<int>::of(&QSpinBox::valueChanged),
            this, [this](int){ onControlChanged(); });
    // Ogg quality
    connect(m_oggQuality, &QSlider::valueChanged, this, [this](int){ onControlChanged(); });

    return group;
}

// ---------------------------------------------------------------------------
//  Paranoia / retry group
// ---------------------------------------------------------------------------
QGroupBox *CDRippingPanel::createParanoiaGroup()
{
    auto *group  = new QGroupBox(tr("Error Correction & Reliability"));
    auto *layout = new QVBoxLayout(group);

    // Error correction radios
    auto *errLabel = new QLabel(tr("CD read error correction:"));
    layout->addWidget(errLabel);

    auto *errRow = new QHBoxLayout;
    m_paranoia0 = new QRadioButton(tr("Off"));
    m_paranoia1 = new QRadioButton(tr("Overlap"));
    m_paranoia2 = new QRadioButton(tr("Never Skip"));
    m_paranoia3 = new QRadioButton(tr("Full Paranoia"));
    m_paranoiaGroup = new QButtonGroup(this);
    m_paranoiaGroup->addButton(m_paranoia0, 0);
    m_paranoiaGroup->addButton(m_paranoia1, 1);
    m_paranoiaGroup->addButton(m_paranoia2, 2);
    m_paranoiaGroup->addButton(m_paranoia3, 3);
    errRow->addWidget(m_paranoia0);
    errRow->addWidget(m_paranoia1);
    errRow->addWidget(m_paranoia2);
    errRow->addWidget(m_paranoia3);
    errRow->addStretch();
    layout->addLayout(errRow);

    // Sector retry spinbox
    auto *retryRow = new QHBoxLayout;
    retryRow->addWidget(new QLabel(tr("Sector read retries:")));
    m_retries = new QSpinBox;
    m_retries->setRange(0, 128);
    m_retries->setValue(5);
    retryRow->addWidget(m_retries);
    retryRow->addStretch();
    layout->addLayout(retryRow);

    // Wire control-changed signals
    connect(m_paranoia0, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_paranoia1, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_paranoia2, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_paranoia3, &QRadioButton::toggled, this, [this](bool checked){ if (checked) onControlChanged(); });
    connect(m_retries, QOverload<int>::of(&QSpinBox::valueChanged),
            this, [this](int){ onControlChanged(); });

    return group;
}

// ---------------------------------------------------------------------------
//  Drift banner
// ---------------------------------------------------------------------------
QFrame *CDRippingPanel::createDriftBanner()
{
    m_driftBanner = new QFrame;
    m_driftBanner->setFrameShape(QFrame::StyledPanel);
    m_driftBanner->setStyleSheet(
        QStringLiteral("QFrame { background: #d1ecf1; color: #0c5460; "
                       "border: 1px solid #bee5eb; border-radius: 4px; padding: 4px; }"));
    m_driftBanner->setVisible(false);

    auto *bannerLayout = new QVBoxLayout(m_driftBanner);

    auto *driftLabel = new QLabel(
        tr("<b>Settings drift detected:</b> K3b's active config differs from the musiclib profile. "
           "Choose how to resolve:"));
    driftLabel->setWordWrap(true);
    bannerLayout->addWidget(driftLabel);

    auto *btnRow = new QHBoxLayout;
    m_keepK3bBtn = new QPushButton(tr("Keep K3b changes"));
    m_keepK3bBtn->setToolTip(
        tr("Import K3b's current settings into the musiclib profile."));
    m_restoreMuslibBtn = new QPushButton(tr("Restore musiclib profile"));
    m_restoreMuslibBtn->setToolTip(
        tr("Overwrite K3b's config with the musiclib profile."));
    btnRow->addStretch();
    btnRow->addWidget(m_keepK3bBtn);
    btnRow->addWidget(m_restoreMuslibBtn);
    bannerLayout->addLayout(btnRow);

    connect(m_keepK3bBtn,       &QPushButton::clicked, this, &CDRippingPanel::onKeepK3bChanges);
    connect(m_restoreMuslibBtn, &QPushButton::clicked, this, &CDRippingPanel::onRestoreMuslibProfile);

    return m_driftBanner;
}

// ═════════════════════════════════════════════════════════════
// Config helpers
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::loadFromConf()
{
    m_loadingValues = true;

    // Output format
    QString fmt = m_confWriter->value(QStringLiteral("K3B_ENCODER_FORMAT"), QStringLiteral("mp3"));
    if (fmt == QStringLiteral("ogg"))
        m_fmtOgg->setChecked(true);
    else if (fmt == QStringLiteral("flac"))
        m_fmtFlac->setChecked(true);
    else
        m_fmtMp3->setChecked(true);

    // MP3 mode
    QString mode = m_confWriter->value(QStringLiteral("K3B_MP3_MODE"), QStringLiteral("cbr"));
    if (mode == QStringLiteral("vbr"))
        m_modeVbr->setChecked(true);
    else if (mode == QStringLiteral("abr"))
        m_modeAbr->setChecked(true);
    else
        m_modeCbr->setChecked(true);

    // CBR bitrate
    int cbrBitrate = m_confWriter->intValue(QStringLiteral("K3B_MP3_BITRATE"), 320);
    {
        int idx = m_cbrBitrate->findData(cbrBitrate);
        m_cbrBitrate->setCurrentIndex(idx >= 0 ? idx : m_cbrBitrate->count() - 1);
    }

    // VBR quality
    int vbrQuality = m_confWriter->intValue(QStringLiteral("K3B_MP3_VBR_QUALITY"), 2);
    m_vbrQuality->setValue(qBound(0, vbrQuality, 9));

    // ABR target
    int abrTarget = m_confWriter->intValue(QStringLiteral("K3B_MP3_ABR_TARGET"), 192);
    m_abrTarget->setValue(qBound(32, abrTarget, 320));

    // Ogg quality
    int oggQuality = m_confWriter->intValue(QStringLiteral("K3B_OGG_QUALITY"), 6);
    m_oggQuality->setValue(qBound(0, oggQuality, 10));

    // Paranoia mode
    int paranoia = m_confWriter->intValue(QStringLiteral("K3B_PARANOIA_MODE"), 0);
    switch (paranoia) {
    case 1:  m_paranoia1->setChecked(true); break;
    case 2:  m_paranoia2->setChecked(true); break;
    case 3:  m_paranoia3->setChecked(true); break;
    default: m_paranoia0->setChecked(true); break;
    }

    // Retries
    int retries = m_confWriter->intValue(QStringLiteral("K3B_READ_RETRIES"), 5);
    m_retries->setValue(qBound(0, retries, 128));

    // Output directory (read-only display)
    QString outDir = m_confWriter->value(QStringLiteral("NEW_DOWNLOAD_DIR"));
    if (outDir.isEmpty())
        outDir = m_confWriter->value(QStringLiteral("MUSIC_DOWNLOAD_DIR"));
    m_outputDirLabel->setText(outDir.isEmpty() ? tr("(not configured)") : outDir);

    m_loadingValues = false;

    // Apply visibility after loading
    onFormatChanged();
    onMp3ModeChanged();
}

// ═════════════════════════════════════════════════════════════
// K3brc pipeline
// ═════════════════════════════════════════════════════════════

QString CDRippingPanel::encoderPluginForFormat(const QString &format)
{
    if (format == QStringLiteral("ogg"))
        return QStringLiteral("k3boggvorbisencoder");
    // mp3 and flac both use the external encoder
    return QStringLiteral("k3bexternalencoder");
}

QString CDRippingPanel::buildLameCommand() const
{
    // Common prefix
    static const QString prefix =
        QStringLiteral("Mp3 (Lame),mp3,lame -r --bitwidth 16 --little-endian -s 44.1 -h");

    QString mode    = m_confWriter->value(QStringLiteral("K3B_MP3_MODE"), QStringLiteral("cbr"));
    QString tagSuffix = QStringLiteral(" --tt %t --ta %a --tl %m --ty %y --tc %c --tn %n - %f");

    if (mode == QStringLiteral("vbr")) {
        int q = m_confWriter->intValue(QStringLiteral("K3B_MP3_VBR_QUALITY"), 2);
        return prefix + QStringLiteral(" --vbr-new -V %1").arg(q) + tagSuffix;
    } else if (mode == QStringLiteral("abr")) {
        int target = m_confWriter->intValue(QStringLiteral("K3B_MP3_ABR_TARGET"), 192);
        return prefix + QStringLiteral(" --abr %1").arg(target) + tagSuffix;
    } else {
        // cbr (default)
        int bitrate = m_confWriter->intValue(QStringLiteral("K3B_MP3_BITRATE"), 320);
        return prefix + QStringLiteral(" -b %1").arg(bitrate) + tagSuffix;
    }
}

void CDRippingPanel::patchK3brc()
{
    QString target = QDir::homePath() + QStringLiteral("/.config/musiclib/k3brc");
    if (!QFileInfo::exists(target))
        return;

    QString fmt     = m_confWriter->value(QStringLiteral("K3B_ENCODER_FORMAT"), QStringLiteral("mp3"));
    QString encoder = encoderPluginForFormat(fmt);
    QString outDir  = m_confWriter->value(QStringLiteral("NEW_DOWNLOAD_DIR"));
    if (outDir.isEmpty())
        outDir = m_confWriter->value(QStringLiteral("MUSIC_DOWNLOAD_DIR"));
    // k3brc uses file: URI scheme for paths
    QString outDirUri = QStringLiteral("file:") + outDir + QStringLiteral("/");

    int paranoia = m_confWriter->intValue(QStringLiteral("K3B_PARANOIA_MODE"), 0);
    int retries  = m_confWriter->intValue(QStringLiteral("K3B_READ_RETRIES"), 5);
    int oggQuality = m_confWriter->intValue(QStringLiteral("K3B_OGG_QUALITY"), 6);
    QString lameCmd = buildLameCommand();

    // We use a Python one-liner to do section-aware in-place patching,
    // since sed cannot easily track section context.
    // The script reads the file, finds the relevant sections, and replaces
    // the appropriate keys, then writes the result back.
    QString pythonScript = QStringLiteral(
        "import sys, re\n"
        "target = sys.argv[1]\n"
        "fmt = sys.argv[2]\n"
        "encoder = sys.argv[3]\n"
        "out_dir_uri = sys.argv[4]\n"
        "paranoia = sys.argv[5]\n"
        "retries = sys.argv[6]\n"
        "ogg_quality = sys.argv[7]\n"
        "lame_cmd = sys.argv[8]\n"
        "\n"
        "ripping_sections = {'[Audio Ripping]', '[last used Audio Ripping]'}\n"
        "current_section = ''\n"
        "lines = open(target).readlines()\n"
        "out = []\n"
        "for line in lines:\n"
        "    stripped = line.rstrip('\\n')\n"
        "    if stripped.startswith('[') and stripped.endswith(']'):\n"
        "        current_section = stripped\n"
        "        out.append(line)\n"
        "        continue\n"
        "    if current_section in ripping_sections:\n"
        "        if stripped.startswith('encoder='):\n"
        "            line = 'encoder=' + encoder + '\\n'\n"
        "        elif stripped.startswith('filetype='):\n"
        "            line = 'filetype=' + fmt + '\\n'\n"
        "        elif stripped.startswith('last ripping directory[$e]='):\n"
        "            line = 'last ripping directory[$e]=' + out_dir_uri + '\\n'\n"
        "        elif stripped.startswith('paranoia_mode='):\n"
        "            line = 'paranoia_mode=' + paranoia + '\\n'\n"
        "        elif stripped.startswith('read_retries='):\n"
        "            line = 'read_retries=' + retries + '\\n'\n"
        "    elif current_section == '[file view]':\n"
        "        if stripped.startswith('last url[$e]='):\n"
        "            line = 'last url[$e]=' + out_dir_uri + '\\n'\n"
        "    elif current_section == '[K3bOggVorbisEncoderPlugin]':\n"
        "        if stripped.startswith('quality='):\n"
        "            line = 'quality=' + ogg_quality + '\\n'\n"
        "    elif current_section == '[K3bExternalEncoderPlugin]':\n"
        "        if stripped.startswith('command_Mp3 (Lame)='):\n"
        "            line = 'command_Mp3 (Lame)=' + lame_cmd + '\\n'\n"
        "    out.append(line)\n"
        "open(target, 'w').writelines(out)\n"
    );

    QProcess proc;
    proc.start(QStringLiteral("python3"), QStringList()
        << QStringLiteral("-c") << pythonScript
        << target
        << fmt
        << encoder
        << outDirUri
        << QString::number(paranoia)
        << QString::number(retries)
        << QString::number(oggQuality)
        << lameCmd);
    proc.waitForFinished(5000);
}

void CDRippingPanel::deployK3brc()
{
    QString src  = QDir::homePath() + QStringLiteral("/.config/musiclib/k3brc");
    QString dest = QDir::homePath() + QStringLiteral("/.config/k3brc");

    if (!QFileInfo::exists(src))
        return;

    // Remove destination first so QFile::copy() succeeds if it already exists
    if (QFileInfo::exists(dest))
        QFile::remove(dest);

    QFile::copy(src, dest);
}

// ═════════════════════════════════════════════════════════════
// Control changed — write-deploy pipeline
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::onControlChanged()
{
    if (m_loadingValues)
        return;
    if (!m_controlsContainer || !m_controlsContainer->isEnabled())
        return;

    // ── Write K3B_* keys to musiclib.conf ──
    QString fmt;
    if (m_fmtOgg->isChecked())       fmt = QStringLiteral("ogg");
    else if (m_fmtFlac->isChecked()) fmt = QStringLiteral("flac");
    else                             fmt = QStringLiteral("mp3");
    m_confWriter->setValue(QStringLiteral("K3B_ENCODER_FORMAT"), fmt);

    QString mp3Mode;
    if (m_modeVbr->isChecked())      mp3Mode = QStringLiteral("vbr");
    else if (m_modeAbr->isChecked()) mp3Mode = QStringLiteral("abr");
    else                             mp3Mode = QStringLiteral("cbr");
    m_confWriter->setValue(QStringLiteral("K3B_MP3_MODE"), mp3Mode);

    int cbrBitrate = m_cbrBitrate->currentData().toInt();
    m_confWriter->setIntValue(QStringLiteral("K3B_MP3_BITRATE"), cbrBitrate);

    m_confWriter->setIntValue(QStringLiteral("K3B_MP3_VBR_QUALITY"), m_vbrQuality->value());
    m_confWriter->setIntValue(QStringLiteral("K3B_MP3_ABR_TARGET"),  m_abrTarget->value());
    m_confWriter->setIntValue(QStringLiteral("K3B_OGG_QUALITY"),     m_oggQuality->value());

    int paranoia = m_paranoiaGroup->checkedId();
    if (paranoia < 0) paranoia = 0;
    m_confWriter->setIntValue(QStringLiteral("K3B_PARANOIA_MODE"), paranoia);

    m_confWriter->setIntValue(QStringLiteral("K3B_READ_RETRIES"), m_retries->value());

    m_confWriter->save();

    // ── Patch and deploy k3brc ──
    patchK3brc();
    deployK3brc();
}

// ═════════════════════════════════════════════════════════════
// Visibility logic
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::onFormatChanged()
{
    bool isMp3  = m_fmtMp3->isChecked();
    bool isOgg  = m_fmtOgg->isChecked();

    m_mp3ModeBox->setVisible(isMp3);
    m_oggWidget->setVisible(isOgg);

    if (isMp3)
        onMp3ModeChanged();
}

void CDRippingPanel::onMp3ModeChanged()
{
    bool isCbr = m_modeCbr->isChecked();
    bool isVbr = m_modeVbr->isChecked();
    bool isAbr = m_modeAbr->isChecked();

    m_cbrWidget->setVisible(isCbr);
    m_vbrWidget->setVisible(isVbr);
    m_abrWidget->setVisible(isAbr);
}

// ═════════════════════════════════════════════════════════════
// K3b running detection
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::checkK3bRunning()
{
    QString k3bCmd = m_confWriter->value(QStringLiteral("K3B_CMD"), QStringLiteral("k3b"));

    QProcess pgrep;
    pgrep.start(QStringLiteral("pgrep"),
                QStringList() << QStringLiteral("-x") << k3bCmd);
    pgrep.waitForFinished(2000);

    bool running = (pgrep.exitCode() == 0);

    if (running) {
        if (!m_k3bWasRunning) {
            // Transition: not running → running
            setControlsEnabled(false);
            m_runningLabel->setVisible(true);
        }
    } else {
        if (m_k3bWasRunning) {
            // Transition: running → not running
            setControlsEnabled(true);
            m_runningLabel->setVisible(false);
            runDriftDetection();
            Q_EMIT k3bExited();   // MainWindow uses this to clear the PID file
        }
    }

    m_k3bWasRunning = running;
}

void CDRippingPanel::setControlsEnabled(bool enabled)
{
    if (m_controlsContainer)
        m_controlsContainer->setEnabled(enabled);
}

// ═════════════════════════════════════════════════════════════
// Public pipeline entry-point for MainWindow (Scenario A toolbar launch)
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::patchAndDeployK3brc()
{
    patchK3brc();
    deployK3brc();
}

// ═════════════════════════════════════════════════════════════
// Drift detection
// ═════════════════════════════════════════════════════════════

bool CDRippingPanel::runDriftDetection()
{
    if (!m_driftBanner)
        return false;

    QString k3bLive    = QDir::homePath() + QStringLiteral("/.config/k3brc");
    QString k3bManaged = QDir::homePath() + QStringLiteral("/.config/musiclib/k3brc");

    if (!QFileInfo::exists(k3bLive) || !QFileInfo::exists(k3bManaged)) {
        m_driftBanner->setVisible(false);
        return false;
    }

    // Use Python to extract the managed keys from both files and compare.
    // Returns "DRIFT" to stdout if any key differs, "OK" otherwise.
    QString pythonScript = QStringLiteral(
        "import sys\n"
        "ripping_sections = {'[Audio Ripping]', '[last used Audio Ripping]'}\n"
        "managed_keys = {\n"
        "    'Audio Ripping': {'encoder', 'filetype', 'last ripping directory[$e]',\n"
        "                      'paranoia_mode', 'read_retries'},\n"
        "    'last used Audio Ripping': {'encoder', 'filetype',\n"
        "                               'last ripping directory[$e]',\n"
        "                               'paranoia_mode', 'read_retries'},\n"
        "    'file view': {'last url[$e]'},\n"
        "    'K3bOggVorbisEncoderPlugin': {'quality'},\n"
        "    'K3bExternalEncoderPlugin': {'command_Mp3 (Lame)'},\n"
        "}\n"
        "\n"
        "def extract(path):\n"
        "    vals = {}\n"
        "    section = ''\n"
        "    for line in open(path):\n"
        "        line = line.rstrip('\\n')\n"
        "        if line.startswith('[') and line.endswith(']'):\n"
        "            section = line[1:-1]\n"
        "            continue\n"
        "        if '=' in line and section in managed_keys:\n"
        "            k, _, v = line.partition('=')\n"
        "            if k in managed_keys[section]:\n"
        "                vals[(section, k)] = v\n"
        "    return vals\n"
        "\n"
        "a = extract(sys.argv[1])\n"
        "b = extract(sys.argv[2])\n"
        "print('DRIFT' if a != b else 'OK')\n"
    );

    QProcess proc;
    proc.start(QStringLiteral("python3"), QStringList()
        << QStringLiteral("-c") << pythonScript
        << k3bLive
        << k3bManaged);
    proc.waitForFinished(5000);

    QString result = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    bool hasDrift = (result == QStringLiteral("DRIFT"));
    m_driftBanner->setVisible(hasDrift);
    return hasDrift;
}

// ═════════════════════════════════════════════════════════════
// Drift banner actions
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::onKeepK3bChanges()
{
    QString k3bLive    = QDir::homePath() + QStringLiteral("/.config/k3brc");
    QString k3bManaged = QDir::homePath() + QStringLiteral("/.config/musiclib/k3brc");

    if (!QFileInfo::exists(k3bLive))
        return;

    // Copy K3b's live config over the managed copy.
    if (QFileInfo::exists(k3bManaged))
        QFile::remove(k3bManaged);
    QFile::copy(k3bLive, k3bManaged);

    // Parse managed keys back into musiclib.conf via a Python helper.
    // Reads encoder, filetype, paranoia_mode, read_retries from [Audio Ripping]
    // and quality from [K3bOggVorbisEncoderPlugin], then writes them as shell
    // assignment lines to stdout for us to parse.
    QString pythonScript = QStringLiteral(
        "import sys\n"
        "target = sys.argv[1]\n"
        "vals = {}\n"
        "section = ''\n"
        "for line in open(target):\n"
        "    line = line.rstrip('\\n')\n"
        "    if line.startswith('[') and line.endswith(']'):\n"
        "        section = line[1:-1]\n"
        "        continue\n"
        "    if '=' not in line:\n"
        "        continue\n"
        "    k, _, v = line.partition('=')\n"
        "    if section == 'Audio Ripping':\n"
        "        if k in ('encoder','filetype','paranoia_mode','read_retries'):\n"
        "            vals[k] = v\n"
        "    elif section == 'K3bOggVorbisEncoderPlugin':\n"
        "        if k == 'quality':\n"
        "            vals['ogg_quality'] = v\n"
        "    elif section == 'K3bExternalEncoderPlugin':\n"
        "        if k == 'command_Mp3 (Lame)':\n"
        "            vals['lame_cmd'] = v\n"
        "for k, v in vals.items():\n"
        "    print(k + '=' + v)\n"
    );

    QProcess proc;
    proc.start(QStringLiteral("python3"), QStringList()
        << QStringLiteral("-c") << pythonScript
        << k3bManaged);
    proc.waitForFinished(5000);

    QString output = QString::fromUtf8(proc.readAllStandardOutput());
    for (const QString &line : output.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        int eq = line.indexOf(QLatin1Char('='));
        if (eq < 0) continue;
        QString key = line.left(eq).trimmed();
        QString val = line.mid(eq + 1).trimmed();

        if (key == QStringLiteral("filetype")) {
            m_confWriter->setValue(QStringLiteral("K3B_ENCODER_FORMAT"), val);
        } else if (key == QStringLiteral("paranoia_mode")) {
            m_confWriter->setValue(QStringLiteral("K3B_PARANOIA_MODE"), val);
        } else if (key == QStringLiteral("read_retries")) {
            m_confWriter->setValue(QStringLiteral("K3B_READ_RETRIES"), val);
        } else if (key == QStringLiteral("ogg_quality")) {
            m_confWriter->setValue(QStringLiteral("K3B_OGG_QUALITY"), val);
        }
        // MP3 mode is harder to reverse-engineer from the lame command —
        // parse the lame_cmd for -b / --vbr-new / --abr flags.
        if (key == QStringLiteral("lame_cmd")) {
            if (val.contains(QStringLiteral("--vbr-new"))) {
                m_confWriter->setValue(QStringLiteral("K3B_MP3_MODE"), QStringLiteral("vbr"));
                // Extract -V <n>
                QRegularExpression re(QStringLiteral("-V (\\d+)"));
                auto m = re.match(val);
                if (m.hasMatch())
                    m_confWriter->setValue(QStringLiteral("K3B_MP3_VBR_QUALITY"), m.captured(1));
            } else if (val.contains(QStringLiteral("--abr"))) {
                m_confWriter->setValue(QStringLiteral("K3B_MP3_MODE"), QStringLiteral("abr"));
                QRegularExpression re(QStringLiteral("--abr (\\d+)"));
                auto m = re.match(val);
                if (m.hasMatch())
                    m_confWriter->setValue(QStringLiteral("K3B_MP3_ABR_TARGET"), m.captured(1));
            } else {
                // CBR: extract -b <n>
                m_confWriter->setValue(QStringLiteral("K3B_MP3_MODE"), QStringLiteral("cbr"));
                QRegularExpression re(QStringLiteral("-b (\\d+)"));
                auto m = re.match(val);
                if (m.hasMatch())
                    m_confWriter->setValue(QStringLiteral("K3B_MP3_BITRATE"), m.captured(1));
            }
        }
    }

    m_confWriter->save();
    loadFromConf();
    m_driftBanner->setVisible(false);
}

void CDRippingPanel::onRestoreMuslibProfile()
{
    patchK3brc();
    deployK3brc();
    loadFromConf();
    m_driftBanner->setVisible(false);
}

// ═════════════════════════════════════════════════════════════
// Reset to defaults
// ═════════════════════════════════════════════════════════════

void CDRippingPanel::onResetToDefaults()
{
    // Strip all K3B_* lines from the user config so system defaults apply.
    // ConfWriter has no removeKey() method, so we do this directly with sed,
    // then reload ConfWriter from disk to pick up the now-system-default values.
    QString userConf = QDir::homePath() + QStringLiteral("/.config/musiclib/musiclib.conf");

    if (QFileInfo::exists(userConf)) {
        QProcess sed;
        sed.start(QStringLiteral("sed"),
                  QStringList() << QStringLiteral("-i")
                                << QStringLiteral("/^K3B_/d")
                                << userConf);
        sed.waitForFinished(5000);
    }

    // Reload ConfWriter — it now reads system defaults for K3B_* keys.
    m_confWriter->loadFromDefaultLocation();

    loadFromConf();
    patchK3brc();
    deployK3brc();
    m_driftBanner->setVisible(false);
}
