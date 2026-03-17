// smartplaylistpanel.cpp
// MusicLib Qt GUI — Smart Playlist Panel implementation
// Copyright (c) 2026 MusicLib Project

#include "smartplaylistpanel.h"
#include "confwriter.h"
#include "musiclib.h"   // KConfigXT-generated MusicLibSettings singleton

#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFormLayout>
#include <QGroupBox>
#include <QLabel>
#include <QPushButton>
#include <QSpinBox>
#include <QLineEdit>
#include <QCheckBox>
#include <QProgressBar>
#include <QTextEdit>
#include <QTableWidget>
#include <QHeaderView>
#include <QScrollArea>
#include <QTimer>
#include <QProcess>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <KLocalizedString>

// ─────────────────────────────────────────────────────────────
// Default values — must match the <default> elements in musiclib.kcfg
// SmartPlaylist group.  Hardcoded here because KConfigXT for this project
// does not emit defaultXxx() accessor methods.
// ─────────────────────────────────────────────────────────────
static constexpr int kDefaultThreshold[5] = {360, 180, 90, 60, 30};
static constexpr int kDefaultPlaylistSize          = 50;
static constexpr int kDefaultSampleSize            = 20;
static constexpr int kDefaultArtistExclusionCount  = 30;

// ═════════════════════════════════════════════════════════════
// Construction / Destruction
// ═════════════════════════════════════════════════════════════

SmartPlaylistPanel::SmartPlaylistPanel(ConfWriter *conf, QWidget *parent)
    : QWidget(parent)
    , m_conf(conf)
{
    // ── Debounce timer for live constraint refresh ──
    m_constraintDebounce = new QTimer(this);
    m_constraintDebounce->setSingleShot(true);
    m_constraintDebounce->setInterval(500);
    connect(m_constraintDebounce, &QTimer::timeout,
            this, &SmartPlaylistPanel::startCountsRun);

    // ── Build UI ──
    auto *scroll = new QScrollArea(this);
    scroll->setWidgetResizable(true);
    scroll->setFrameStyle(QFrame::NoFrame);

    auto *content = new QWidget(scroll);
    auto *layout  = new QVBoxLayout(content);
    layout->setSpacing(10);
    layout->setContentsMargins(8, 8, 8, 8);

    layout->addWidget(createConfigGroup());
    layout->addWidget(createAnalyzeGroup());
    layout->addWidget(createGenerateGroup());
    layout->addStretch();

    scroll->setWidget(content);

    auto *mainLayout = new QVBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->addWidget(scroll);
    setLayout(mainLayout);

    // ── Initialize constraint display placeholder ──
    updateConstraintDisplay();

    // ── Audacious availability poll ──
    // Check immediately so the checkbox starts in the correct state, then
    // recheck every 3 seconds so it tracks Audacious being launched or closed.
    m_audaciousCheckTimer = new QTimer(this);
    m_audaciousCheckTimer->setInterval(3000);
    connect(m_audaciousCheckTimer, &QTimer::timeout,
            this, &SmartPlaylistPanel::checkAudaciousRunning);
    m_audaciousCheckTimer->start();
    checkAudaciousRunning();
}

SmartPlaylistPanel::~SmartPlaylistPanel()
{
    if (m_analyzeProcess && m_analyzeProcess->state() != QProcess::NotRunning) {
        m_analyzeProcess->kill();
        m_analyzeProcess->waitForFinished(1000);
    }
    if (m_generateProcess && m_generateProcess->state() != QProcess::NotRunning) {
        m_generateProcess->kill();
        m_generateProcess->waitForFinished(1000);
    }
}

// ═════════════════════════════════════════════════════════════
// UI construction helpers
// ═════════════════════════════════════════════════════════════

QGroupBox *SmartPlaylistPanel::createConfigGroup()
{
    auto *box    = new QGroupBox(i18n("Configuration"), this);

    // ── Help text ──
    auto *helpLabel = new QLabel(this);
    helpLabel->setWordWrap(true);
    helpLabel->setTextFormat(Qt::RichText);
    helpLabel->setText(i18n(
        "<p>Configuring smart playlists is easy. You prioritize what songs go in and more "
        "importantly, <i>when</i>. It is based on your ratings, when you last heard a song, "
        "and how many different artists must play before the same artist is heard again. "
        "This tool is very different than other tools because it provides real variety.</p>"
        "<p><b>Threshold (in days)</b> — Decides how many days must pass since a track was "
        "played before it can be added to the playlist. The higher you set the threshold "
        "relative to the others, the less frequently that rating category will appear. "
        "For example, if you set 100 days for three-star tracks and a three-star track was "
        "played 99 days ago, that track is ineligible.</p>"
        "<p><b>Playlist size</b> — Constrained by the size of your music library. "
        "The larger the library, the higher this setting can be.</p>"
        "<p><b>Sample size</b> — Click <i>Preview</i> to observe how many tracks from each "
        "rating will appear for a given sample. Usually leave this at 20.</p>"
        "<p><b>Artist exclusion count</b> — Controls variety. When a track is selected "
        "during the build process, that artist is excluded until the exclusion count is "
        "reached. The higher you set this, the longer before a track from the same artist "
        "appears again. The Dynamic Configuration Results Output below shows how many "
        "eligible unique artists exist based on your current settings.</p>"));

    auto *form   = new QFormLayout();
    form->setLabelAlignment(Qt::AlignRight);

    auto *s = MusicLibSettings::self();

    // Five age-threshold spinboxes — read current values from KConfig
    const int currentThresholds[5] = {
        s->ageThresholdGroup1(),
        s->ageThresholdGroup2(),
        s->ageThresholdGroup3(),
        s->ageThresholdGroup4(),
        s->ageThresholdGroup5(),
    };

    const QString starLabels[5] = {
        i18n("1★ threshold (days)"),
        i18n("2★ threshold (days)"),
        i18n("3★ threshold (days)"),
        i18n("4★ threshold (days)"),
        i18n("5★ threshold (days)"),
    };

    for (int i = 0; i < 5; ++i) {
        m_thresholdSpin[i] = new QSpinBox(this);
        m_thresholdSpin[i]->setRange(1, 3650);
        m_thresholdSpin[i]->setValue(currentThresholds[i]);
        m_thresholdSpin[i]->setSuffix(i18n(" days"));
        m_thresholdSpin[i]->setToolTip(
            i18n("Tracks played within this many days are excluded from the %1 rating group.",
                 i + 1));
        connect(m_thresholdSpin[i], QOverload<int>::of(&QSpinBox::valueChanged),
                this, &SmartPlaylistPanel::onThresholdChanged);
        form->addRow(starLabels[i], m_thresholdSpin[i]);
    }

    // Playlist size
    m_playlistSizeSpin = new QSpinBox(this);
    m_playlistSizeSpin->setRange(10, 500);
    m_playlistSizeSpin->setValue(s->playlistSize());
    m_playlistSizeSpin->setToolTip(i18n("Number of tracks in the generated playlist."));
    connect(m_playlistSizeSpin, QOverload<int>::of(&QSpinBox::valueChanged),
            this, &SmartPlaylistPanel::onSizeChanged);
    form->addRow(i18n("Playlist size"), m_playlistSizeSpin);

    // Sample size
    m_sampleSizeSpin = new QSpinBox(this);
    m_sampleSizeSpin->setRange(5, 100);
    m_sampleSizeSpin->setValue(s->sampleSize());
    m_sampleSizeSpin->setToolTip(
        i18n("Tracks per variance-sampling batch — controls rating-group weighting resolution."));
    connect(m_sampleSizeSpin, QOverload<int>::of(&QSpinBox::valueChanged),
            this, &SmartPlaylistPanel::onSizeChanged);
    form->addRow(i18n("Sample size"), m_sampleSizeSpin);

    // Artist exclusion count
    m_artistExclusionSpin = new QSpinBox(this);
    m_artistExclusionSpin->setRange(0, 500);
    m_artistExclusionSpin->setValue(s->artistExclusionCount());
    m_artistExclusionSpin->setToolTip(
        i18n("Most-recently-played unique artists to exclude during track selection."));
    connect(m_artistExclusionSpin, QOverload<int>::of(&QSpinBox::valueChanged),
            this, &SmartPlaylistPanel::onSizeChanged);
    form->addRow(i18n("Artist exclusion count"), m_artistExclusionSpin);

    // Reset to defaults button
    m_resetButton = new QPushButton(i18n("Reset to defaults"), this);
    connect(m_resetButton, &QPushButton::clicked,
            this, &SmartPlaylistPanel::resetToDefaults);

    // Constraint summary label (read-only, word-wrapped)
    m_constraintSummaryLabel = new QLabel(this);
    m_constraintSummaryLabel->setWordWrap(true);
    m_constraintSummaryLabel->setTextFormat(Qt::RichText);
    m_constraintSummaryLabel->setStyleSheet(
        QStringLiteral("QLabel { background: palette(base); border: 1px solid palette(mid);"
                       " border-radius: 3px; padding: 6px; }"));
    m_constraintSummaryLabel->setMinimumHeight(80);

    // ── "Dynamic Configuration Results Output" title label ──
    auto *constraintTitleLabel = new QLabel(i18n("<b>Dynamic Configuration Results Output</b>"), this);
    constraintTitleLabel->setTextFormat(Qt::RichText);

    auto *outerLayout = new QVBoxLayout(box);
    outerLayout->addWidget(helpLabel);
    outerLayout->addLayout(form);
    outerLayout->addWidget(m_resetButton, 0, Qt::AlignLeft);
    outerLayout->addWidget(constraintTitleLabel);
    outerLayout->addWidget(m_constraintSummaryLabel);

    return box;
}

QGroupBox *SmartPlaylistPanel::createAnalyzeGroup()
{
    auto *box    = new QGroupBox(i18n("Analyze"), this);
    auto *layout = new QVBoxLayout(box);

    // Button row
    auto *btnRow = new QHBoxLayout();
    m_previewButton = new QPushButton(i18n("Preview"), this);
    m_previewButton->setToolTip(
        i18n("Run a full analysis to see per-group eligible counts, variance, and sampling weights."));
    connect(m_previewButton, &QPushButton::clicked,
            this, &SmartPlaylistPanel::runPreview);
    btnRow->addWidget(m_previewButton);

    m_analyzeStatusLabel = new QLabel(this);
    btnRow->addWidget(m_analyzeStatusLabel, 1);
    layout->addLayout(btnRow);

    // Preview table
    m_previewTable = new QTableWidget(0, 8, this);
    m_previewTable->setHorizontalHeaderLabels({
        i18n("Stars"), i18n("POPM Range"),
        i18n("Threshold (days)"), i18n("Eligible Tracks"), i18n("Unique Artists"),
        i18n("Variance Total"), i18n("Sample Weight %"), i18n("Sample Qty")
    });
    m_previewTable->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
    m_previewTable->horizontalHeader()->setStretchLastSection(true);
    m_previewTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_previewTable->setSelectionMode(QAbstractItemView::NoSelection);
    m_previewTable->setAlternatingRowColors(true);
    m_previewTable->setMinimumHeight(160);
    layout->addWidget(m_previewTable);

    return box;
}

QGroupBox *SmartPlaylistPanel::createGenerateGroup()
{
    auto *box    = new QGroupBox(i18n("Generate"), this);
    auto *layout = new QVBoxLayout(box);

    // Playlist name
    auto *nameRow = new QHBoxLayout();
    nameRow->addWidget(new QLabel(i18n("Playlist name:"), this));
    m_playlistNameEdit = new QLineEdit(this);
    m_playlistNameEdit->setText(QStringLiteral("Smart Playlist"));
    m_playlistNameEdit->setToolTip(i18n("Name for the generated playlist in Audacious."));
    nameRow->addWidget(m_playlistNameEdit, 1);
    layout->addLayout(nameRow);

    // Load into Audacious checkbox
    m_loadAudaciousCheck = new QCheckBox(i18n("Load into Audacious after generating"), this);
    m_loadAudaciousCheck->setChecked(true);
    layout->addWidget(m_loadAudaciousCheck);

    // Generate button + progress bar row
    auto *genRow = new QHBoxLayout();
    m_generateButton = new QPushButton(i18n("Generate Playlist"), this);
    m_generateButton->setToolTip(i18n("Build the smart playlist using the current settings."));
    connect(m_generateButton, &QPushButton::clicked,
            this, &SmartPlaylistPanel::runGenerate);
    genRow->addWidget(m_generateButton);

    m_generateProgress = new QProgressBar(this);
    m_generateProgress->setRange(0, 100);
    m_generateProgress->setVisible(false);
    genRow->addWidget(m_generateProgress, 1);
    layout->addLayout(genRow);

    // Generation log
    m_generateLog = new QTextEdit(this);
    m_generateLog->setReadOnly(true);
    m_generateLog->setFont(QFont(QStringLiteral("Monospace"), 9));
    m_generateLog->setMinimumHeight(120);
    m_generateLog->setMaximumHeight(200);
    layout->addWidget(m_generateLog);

    return box;
}

// ═════════════════════════════════════════════════════════════
// Configuration group slots
// ═════════════════════════════════════════════════════════════

void SmartPlaylistPanel::onThresholdChanged()
{
    saveThresholdsToConfig();
    // Restart the debounce timer — starts a counts run after 500ms of quiet
    m_constraintDebounce->start();
}

void SmartPlaylistPanel::onSizeChanged()
{
    saveGenerationParamsToConfig();
    // No subprocess re-run needed; constraint math uses cached stats
    updateConstraintDisplay();
}

void SmartPlaylistPanel::resetToDefaults()
{
    // Block signals while we set all spinboxes so we don't fire n writes
    for (int i = 0; i < 5; ++i)
        m_thresholdSpin[i]->blockSignals(true);
    m_playlistSizeSpin->blockSignals(true);
    m_sampleSizeSpin->blockSignals(true);
    m_artistExclusionSpin->blockSignals(true);

    // Apply compile-time defaults matching musiclib.kcfg SmartPlaylist group
    for (int i = 0; i < 5; ++i)
        m_thresholdSpin[i]->setValue(kDefaultThreshold[i]);
    m_playlistSizeSpin->setValue(kDefaultPlaylistSize);
    m_sampleSizeSpin->setValue(kDefaultSampleSize);
    m_artistExclusionSpin->setValue(kDefaultArtistExclusionCount);

    for (int i = 0; i < 5; ++i)
        m_thresholdSpin[i]->blockSignals(false);
    m_playlistSizeSpin->blockSignals(false);
    m_sampleSizeSpin->blockSignals(false);
    m_artistExclusionSpin->blockSignals(false);

    // Write defaults to config
    saveThresholdsToConfig();
    saveGenerationParamsToConfig();

    // Kick off a fresh counts run
    m_constraintDebounce->start();
}

// ═════════════════════════════════════════════════════════════
// Audacious availability
// ═════════════════════════════════════════════════════════════

void SmartPlaylistPanel::checkAudaciousRunning()
{
    // pgrep -x audacious returns 0 if at least one matching process exists.
    const bool running =
        (QProcess::execute(QStringLiteral("pgrep"),
                           { QStringLiteral("-x"), QStringLiteral("audacious") }) == 0);

    if (!running) {
        // Dim and uncheck — generating with --load-audacious would fail anyway.
        m_loadAudaciousCheck->setChecked(false);
        m_loadAudaciousCheck->setEnabled(false);
        m_loadAudaciousCheck->setToolTip(
            i18n("Activate this feature by launching Audacious."));
    } else {
        m_loadAudaciousCheck->setEnabled(true);
        m_loadAudaciousCheck->setToolTip(
            i18n("Load the generated playlist directly into Audacious."));
    }
}

// ═════════════════════════════════════════════════════════════
// Analyze group slots
// ═════════════════════════════════════════════════════════════

void SmartPlaylistPanel::runPreview()
{
    if (m_busy)
        return;
    if (m_analyzeProcess && m_analyzeProcess->state() != QProcess::NotRunning)
        return;

    setBusy(true);
    m_analyzeIsPreview = true;
    m_analyzeBuffer.clear();
    m_analyzeStatusLabel->setText(i18n("Analyzing…"));

    if (!m_analyzeProcess) {
        m_analyzeProcess = new QProcess(this);
        connect(m_analyzeProcess, &QProcess::readyReadStandardOutput,
                this, &SmartPlaylistPanel::onAnalyzeReadyRead);
        connect(m_analyzeProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &SmartPlaylistPanel::onAnalyzeFinished);
    }

    QStringList args = {
        QStringLiteral("-m"), QStringLiteral("preview"),
        QStringLiteral("-g"), thresholdArg(),
        QStringLiteral("-s"), QString::number(m_sampleSizeSpin->value())
    };
    m_analyzeProcess->start(scriptPath(QStringLiteral("musiclib_smartplaylist_analyze.sh")), args);
}

void SmartPlaylistPanel::startCountsRun()
{
    // Don't interrupt a preview or generate run
    if (m_busy)
        return;
    if (m_analyzeProcess && m_analyzeProcess->state() != QProcess::NotRunning)
        return;

    m_analyzeIsPreview = false;
    m_analyzeBuffer.clear();

    if (!m_analyzeProcess) {
        m_analyzeProcess = new QProcess(this);
        connect(m_analyzeProcess, &QProcess::readyReadStandardOutput,
                this, &SmartPlaylistPanel::onAnalyzeReadyRead);
        connect(m_analyzeProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &SmartPlaylistPanel::onAnalyzeFinished);
    }

    QStringList args = {
        QStringLiteral("-m"), QStringLiteral("counts"),
        QStringLiteral("-g"), thresholdArg()
    };
    m_analyzeProcess->start(scriptPath(QStringLiteral("musiclib_smartplaylist_analyze.sh")), args);
}

void SmartPlaylistPanel::onAnalyzeReadyRead()
{
    m_analyzeBuffer += m_analyzeProcess->readAllStandardOutput();
}

void SmartPlaylistPanel::onAnalyzeFinished(int exitCode, QProcess::ExitStatus /*status*/)
{
    const bool wasPreview = m_analyzeIsPreview;
    if (wasPreview)
        setBusy(false);

    // Parse JSON from accumulated buffer
    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(m_analyzeBuffer, &parseErr);

    if (exitCode != 0 || doc.isNull() || !doc.isObject()) {
        if (wasPreview) {
            m_analyzeStatusLabel->setText(i18n("Analysis failed (exit %1)", exitCode));
        }
        return;
    }

    QJsonObject root = doc.object();

    // Save previous stats for delta display
    m_previousStats = m_cachedStats;

    // Read top-level counts
    m_cachedTotalEligible          = root.value(QStringLiteral("total_eligible")).toInt();
    m_cachedUniqueArtistsEffective = root.value(QStringLiteral("unique_artists_effective")).toInt();
    m_cachedUniqueArtistsRaw       = root.value(QStringLiteral("unique_artists_raw")).toInt();
    m_cachedCustom2CoveragePct     = root.value(QStringLiteral("custom2_coverage_pct")).toInt();

    // Fallback for scripts that emit the older "unique_artists_eligible" key
    if (m_cachedUniqueArtistsEffective == 0)
        m_cachedUniqueArtistsEffective =
            root.value(QStringLiteral("unique_artists_eligible")).toInt();

    QJsonArray groups = root.value(QStringLiteral("groups")).toArray();
    m_cachedStats.resize(groups.size());

    for (int i = 0; i < groups.size(); ++i) {
        QJsonObject g = groups[i].toObject();
        auto &stats = m_cachedStats[i];
        stats.eligibleTracks         = g.value(QStringLiteral("eligible_tracks")).toInt();
        stats.uniqueArtistsEffective = g.value(QStringLiteral("unique_artists_effective")).toInt();
        stats.uniqueArtistsRaw       = g.value(QStringLiteral("unique_artists_raw")).toInt();
        stats.custom2CoveragePct     = g.value(QStringLiteral("custom2_coverage_pct")).toInt();
        stats.belowFloor             = g.contains(QStringLiteral("warning"));

        // Fallback for older schema
        if (stats.uniqueArtistsEffective == 0)
            stats.uniqueArtistsEffective =
                g.value(QStringLiteral("unique_artists")).toInt();

        if (wasPreview) {
            stats.varianceTotal   = g.value(QStringLiteral("variance_total")).toDouble();
            stats.sampleWeightPct = g.value(QStringLiteral("sample_weight_pct")).toDouble();
            stats.sampleQty       = g.value(QStringLiteral("sample_qty")).toInt();
        }
    }

    // Update the preview table if this was a full preview run
    if (wasPreview) {
        // Read POPM range info for table rows from the JSON groups
        m_previewTable->setRowCount(groups.size());
        for (int i = 0; i < groups.size(); ++i) {
            QJsonObject g    = groups[i].toObject();
            const auto &stats = m_cachedStats[i];

            auto setCell = [&](int col, const QString &text) {
                auto *item = new QTableWidgetItem(text);
                item->setTextAlignment(Qt::AlignCenter);
                m_previewTable->setItem(i, col, item);
            };

            setCell(0, QString::number(g.value(QStringLiteral("stars")).toInt()));

            int popmLow  = g.value(QStringLiteral("popm_low")).toInt();
            int popmHigh = g.value(QStringLiteral("popm_high")).toInt();
            setCell(1, QStringLiteral("%1–%2").arg(popmLow).arg(popmHigh));

            setCell(2, QString::number(g.value(QStringLiteral("threshold_days")).toInt()));
            setCell(3, QString::number(stats.eligibleTracks));
            setCell(4, QString::number(stats.uniqueArtistsEffective));
            setCell(5, QString::number(stats.varianceTotal, 'f', 2));
            setCell(6, QString::number(stats.sampleWeightPct, 'f', 1) + QStringLiteral("%"));
            setCell(7, QString::number(stats.sampleQty));

            // Amber highlight for below-floor groups
            if (stats.belowFloor) {
                for (int col = 0; col < m_previewTable->columnCount(); ++col) {
                    auto *item = m_previewTable->item(i, col);
                    if (item)
                        item->setBackground(QColor(255, 200, 0, 100));
                }
            }
        }
        m_analyzeStatusLabel->setText(i18n("Preview complete — %1 eligible tracks",
                                           m_cachedTotalEligible));
    }

    updateConstraintDisplay();
}

// ═════════════════════════════════════════════════════════════
// Generate group slots
// ═════════════════════════════════════════════════════════════

void SmartPlaylistPanel::runGenerate()
{
    if (m_busy)
        return;

    setBusy(true);
    m_generateBuffer.clear();
    m_generateLog->clear();
    m_generateProgress->setValue(0);
    m_generateProgress->setVisible(true);

    if (!m_generateProcess) {
        m_generateProcess = new QProcess(this);
        connect(m_generateProcess, &QProcess::readyReadStandardOutput,
                this, &SmartPlaylistPanel::onGenerateReadyRead);
        connect(m_generateProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &SmartPlaylistPanel::onGenerateFinished);
    }

    QString playlistName = m_playlistNameEdit->text().trimmed();
    if (playlistName.isEmpty())
        playlistName = QStringLiteral("Smart Playlist");

    QStringList args = {
        QStringLiteral("-p"), QString::number(m_playlistSizeSpin->value()),
        QStringLiteral("-e"), QString::number(m_artistExclusionSpin->value()),
        QStringLiteral("-g"), thresholdArg(),
        QStringLiteral("-s"), QString::number(m_sampleSizeSpin->value()),
        QStringLiteral("-n"), playlistName,
    };
    if (m_loadAudaciousCheck->isChecked())
        args << QStringLiteral("--load-audacious");

    m_generateProcess->start(
        scriptPath(QStringLiteral("musiclib_smartplaylist.sh")), args);
}

void SmartPlaylistPanel::onGenerateReadyRead()
{
    const QByteArray data = m_generateProcess->readAllStandardOutput();
    m_generateBuffer += data;

    // Parse each line for progress tokens and log text
    const QString text = QString::fromUtf8(data);
    const QStringList lines = text.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    static const QRegularExpression progressRe(QStringLiteral("^PROGRESS:(\\d+):(\\d+)$"));

    for (const QString &line : lines) {
        QRegularExpressionMatch m = progressRe.match(line.trimmed());
        if (m.hasMatch()) {
            int n     = m.captured(1).toInt();
            int total = m.captured(2).toInt();
            if (total > 0)
                m_generateProgress->setValue(n * 100 / total);
        } else {
            m_generateLog->append(line);
        }
    }
}

void SmartPlaylistPanel::onGenerateFinished(int exitCode, QProcess::ExitStatus /*status*/)
{
    setBusy(false);
    m_generateProgress->setVisible(false);

    if (exitCode == 0) {
        // Parse JSON success object for the output path
        QJsonDocument doc = QJsonDocument::fromJson(m_generateBuffer);
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            QString outputPath = obj.value(QStringLiteral("output")).toString();
            int trackCount     = obj.value(QStringLiteral("tracks")).toInt();
            QString name       = obj.value(QStringLiteral("playlist")).toString();

            m_generateLog->append(
                i18n("✓ Generated \"%1\" — %2 tracks → %3", name, trackCount, outputPath));

            if (m_loadAudaciousCheck->isChecked())
                m_generateLog->append(i18n("Playlist loaded into Audacious."));

            if (!outputPath.isEmpty())
                emit playlistGenerated(outputPath);
        } else {
            m_generateLog->append(i18n("Generation finished."));
        }
    } else {
        // Try to parse JSON error object
        QJsonDocument doc = QJsonDocument::fromJson(m_generateBuffer);
        QString errMsg;
        if (doc.isObject()) {
            errMsg = doc.object().value(QStringLiteral("message")).toString();
        }
        if (errMsg.isEmpty())
            errMsg = i18n("Script exited with code %1", exitCode);

        // Show error in red in the log
        m_generateLog->append(
            QStringLiteral("<span style='color:red;'>%1: %2</span>")
                .arg(i18n("Generation failed")).arg(errMsg.toHtmlEscaped()));
    }
}

// ═════════════════════════════════════════════════════════════
// Live constraint display
// ═════════════════════════════════════════════════════════════

void SmartPlaylistPanel::updateConstraintDisplay()
{
    if (m_cachedTotalEligible == 0) {
        m_constraintSummaryLabel->setText(
            i18n("<i>Run a preview to populate constraint data.</i>"));
        return;
    }

    QString html;

    // ── Total eligible ──
    html += i18n("<b>Total eligible tracks:</b> %1 across all groups<br>",
                 m_cachedTotalEligible);

    // ── Per-group eligibility compact table ──
    html += QStringLiteral("<table style='margin-top:4px; border-collapse:collapse;'>");
    html += QStringLiteral("<tr><th align='left'>Group</th><th>&nbsp;Stars&nbsp;</th>")
            + QStringLiteral("<th>&nbsp;Threshold&nbsp;</th><th>&nbsp;Eligible&nbsp;</th>")
            + QStringLiteral("<th>&nbsp;Note&nbsp;</th></tr>");

    for (int i = 0; i < m_cachedStats.size(); ++i) {
        const auto &stats = m_cachedStats[i];
        QString note;
        if (stats.belowFloor)
            note = QStringLiteral("⚠ &lt;10 tracks");
        html += QStringLiteral("<tr><td>%1</td><td align='center'>%2★</td>"
                               "<td align='center'>%3d</td><td align='center'>%4</td>"
                               "<td>%5</td></tr>")
                    .arg(i + 1)
                    .arg(i + 1)
                    .arg(m_thresholdSpin[i]->value())
                    .arg(stats.eligibleTracks)
                    .arg(note);
    }
    html += QStringLiteral("</table><br>");

    // ── Maximum viable playlist size ──
    const int requestedSize   = m_playlistSizeSpin->value();
    const int maxPlaylistSize = m_cachedTotalEligible;

    html += i18n("<b>Max playlist size with current thresholds:</b> %1 tracks<br>",
                 maxPlaylistSize);

    if (requestedSize > maxPlaylistSize) {
        m_playlistSizeSpin->setStyleSheet(
            QStringLiteral("QSpinBox { border: 2px solid red; }"));
        html += QStringLiteral("<span style='color:red;'>")
                + i18n("⚠ Playlist size exceeds eligible pool — reduce size or loosen thresholds.")
                + QStringLiteral("</span><br>");
    } else {
        m_playlistSizeSpin->setStyleSheet(QString());
    }

    // ── Artist exclusion headroom ──
    const int uniqueArtists = m_cachedUniqueArtistsEffective > 0
                                  ? m_cachedUniqueArtistsEffective
                                  : m_cachedUniqueArtistsRaw;
    const int exclusionCount = m_artistExclusionSpin->value();

    if (uniqueArtists > 0 && exclusionCount > uniqueArtists / 2) {
        html += QStringLiteral("<span style='color:orange;'>")
                + i18n("⚠ Artist exclusion count (%1) is high relative to unique artists in pool (%2). "
                       "Consider reducing to ≤ %3 to avoid stalls.",
                       exclusionCount, uniqueArtists, uniqueArtists / 2)
                + QStringLiteral("</span><br>");
    }

    // ── Exclusion window coverage at current playlist size ──
    if (uniqueArtists > 0) {
        int coveragePct = exclusionCount * 100 / uniqueArtists;
        html += i18n("At playlist size %1, the exclusion window covers <b>%2%</b> of eligible unique artists (%3 total).<br>",
                     requestedSize, coveragePct, uniqueArtists);
    }

    // ── Threshold change deltas (shown if previous stats are available) ──
    if (!m_previousStats.isEmpty() && m_previousStats.size() == m_cachedStats.size()) {
        for (int i = 0; i < m_cachedStats.size(); ++i) {
            int delta = m_cachedStats[i].eligibleTracks - m_previousStats[i].eligibleTracks;
            if (delta != 0) {
                QString sign = delta > 0 ? QStringLiteral("+") : QString();
                html += i18n("%1★ threshold change: %2 → %3 eligible tracks (%4%5)<br>",
                             i + 1,
                             m_previousStats[i].eligibleTracks,
                             m_cachedStats[i].eligibleTracks,
                             sign, delta);
            }
        }
    }

    // ── Custom Artist (Custom2) coverage note ──
    const int mergedArtists = m_cachedUniqueArtistsRaw - m_cachedUniqueArtistsEffective;
    if (m_cachedUniqueArtistsRaw > 0 && mergedArtists > 0) {
        html += i18n("<br><i>Custom Artist field merges %1 artist name variant(s) into fewer effective artists. "
                     "Coverage: %2% of eligible tracks have a Custom Artist value set. "
                     "Tracks without a Custom Artist value appear under their Album Artist name "
                     "and are tracked separately in the exclusion window.</i><br>",
                     mergedArtists, m_cachedCustom2CoveragePct);
        if (m_cachedCustom2CoveragePct < 50) {
            html += QStringLiteral("<span style='color:orange;'><i>")
                    + i18n("Less than half of eligible tracks have a Custom Artist value. "
                           "Consider populating Custom Artist for frequently-played artists "
                           "to improve exclusion accuracy.")
                    + QStringLiteral("</i></span><br>");
        }
    }

    m_constraintSummaryLabel->setText(html);
}

// ═════════════════════════════════════════════════════════════
// Config I/O helpers
// ═════════════════════════════════════════════════════════════

void SmartPlaylistPanel::saveThresholdsToConfig()
{
    auto *s = MusicLibSettings::self();
    s->setAgeThresholdGroup1(m_thresholdSpin[0]->value());
    s->setAgeThresholdGroup2(m_thresholdSpin[1]->value());
    s->setAgeThresholdGroup3(m_thresholdSpin[2]->value());
    s->setAgeThresholdGroup4(m_thresholdSpin[3]->value());
    s->setAgeThresholdGroup5(m_thresholdSpin[4]->value());
    s->save();

    m_conf->setIntValue(QStringLiteral("SP_AGE_GROUP1"), m_thresholdSpin[0]->value());
    m_conf->setIntValue(QStringLiteral("SP_AGE_GROUP2"), m_thresholdSpin[1]->value());
    m_conf->setIntValue(QStringLiteral("SP_AGE_GROUP3"), m_thresholdSpin[2]->value());
    m_conf->setIntValue(QStringLiteral("SP_AGE_GROUP4"), m_thresholdSpin[3]->value());
    m_conf->setIntValue(QStringLiteral("SP_AGE_GROUP5"), m_thresholdSpin[4]->value());
    m_conf->save();
}

void SmartPlaylistPanel::saveGenerationParamsToConfig()
{
    auto *s = MusicLibSettings::self();
    s->setPlaylistSize(m_playlistSizeSpin->value());
    s->setSampleSize(m_sampleSizeSpin->value());
    s->setArtistExclusionCount(m_artistExclusionSpin->value());
    s->save();

    m_conf->setIntValue(QStringLiteral("SP_PLAYLIST_SIZE"),         m_playlistSizeSpin->value());
    m_conf->setIntValue(QStringLiteral("SP_SAMPLE_SIZE"),           m_sampleSizeSpin->value());
    m_conf->setIntValue(QStringLiteral("SP_ARTIST_EXCLUSION_COUNT"),m_artistExclusionSpin->value());
    m_conf->save();
}

// ═════════════════════════════════════════════════════════════
// Script helpers
// ═════════════════════════════════════════════════════════════

QString SmartPlaylistPanel::scriptPath(const QString &scriptName) const
{
    // 1. Check configured bin directory
    QString binDir = m_conf->value(QStringLiteral("MUSICLIB_BIN_DIR"));
    if (!binDir.isEmpty() && !binDir.contains(QLatin1Char('$'))) {
        QString path = binDir + QLatin1Char('/') + scriptName;
        if (QFile::exists(path))
            return path;
    }
    // 2. Standard install location
    const QString installPath = QStringLiteral("/usr/lib/musiclib/bin/") + scriptName;
    if (QFile::exists(installPath))
        return installPath;
    // 3. Fall back to PATH (will produce a "not found" error if missing)
    return scriptName;
}

QString SmartPlaylistPanel::thresholdArg() const
{
    return QStringLiteral("%1,%2,%3,%4,%5")
        .arg(m_thresholdSpin[0]->value())
        .arg(m_thresholdSpin[1]->value())
        .arg(m_thresholdSpin[2]->value())
        .arg(m_thresholdSpin[3]->value())
        .arg(m_thresholdSpin[4]->value());
}

void SmartPlaylistPanel::setBusy(bool busy)
{
    m_busy = busy;
    if (m_previewButton)
        m_previewButton->setEnabled(!busy);
    if (m_generateButton)
        m_generateButton->setEnabled(!busy);
}
