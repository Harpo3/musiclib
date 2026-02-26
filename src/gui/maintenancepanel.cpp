#include "maintenancepanel.h"
#include "scriptrunner.h"

#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGroupBox>
#include <QLabel>
#include <QLineEdit>
#include <QComboBox>
#include <QCheckBox>
#include <QSlider>
#include <QPushButton>
#include <QPlainTextEdit>
#include <QScrollArea>
#include <QFileDialog>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFont>
#include <QDateTime>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>

// ============================================================================
//  Construction
// ============================================================================

MaintenancePanel::MaintenancePanel(ScriptRunner *runner, QWidget *parent)
    : QWidget(parent)
    , m_runner(runner)
{
    // Cache the music directory from config for file dialog start paths.
    // Falls back to $HOME if config can't be read.
    m_musicRepoDir = configValue("MUSIC_ROOT_DIR");
    if (m_musicRepoDir.isEmpty() || !QDir(m_musicRepoDir).exists())
        m_musicRepoDir = configValue("MUSIC_REPO");
    if (m_musicRepoDir.isEmpty() || !QDir(m_musicRepoDir).exists())
        m_musicRepoDir = QDir::homePath();

    buildUi();

    // Connect generic script signals from ScriptRunner
    connect(m_runner, &ScriptRunner::scriptOutput,
            this, &MaintenancePanel::onScriptOutput);
    connect(m_runner, &ScriptRunner::scriptFinished,
            this, &MaintenancePanel::onScriptFinished);
}

// ============================================================================
//  Config reading — same pattern as MainWindow::configValue()
// ============================================================================

QString MaintenancePanel::configValue(const QString &key)
{
    static const QStringList configPaths = {
        QDir::homePath() + "/musiclib/config/musiclib.conf",
        QDir::homePath() + "/.config/musiclib/musiclib.conf",
    };

    for (const QString &path : configPaths) {
        if (!QFileInfo::exists(path))
            continue;

        QProcess proc;
        proc.setProcessChannelMode(QProcess::MergedChannels);

        QString cmd = QStringLiteral("source \"%1\" 2>/dev/null && echo \"$%2\"")
                          .arg(path, key);
        proc.start("bash", QStringList() << "-c" << cmd);

        if (!proc.waitForFinished(3000))
            continue;
        if (proc.exitCode() != 0)
            continue;

        QString value = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        if (!value.isEmpty())
            return value;
    }

    return QString();
}

QString MaintenancePanel::browseStartDir() const
{
    // Prefer the album directory of the currently playing track in Audacious.
    // audtool returns the full file path; we strip the filename to get the
    // parent directory (album folder).
    QProcess audtool;
    audtool.start("audtool", QStringList() << "--current-song-filename");
    if (audtool.waitForFinished(2000) && audtool.exitCode() == 0) {
        QString songPath = QString::fromUtf8(audtool.readAllStandardOutput()).trimmed();
        if (!songPath.isEmpty()) {
            QFileInfo fi(songPath);
            QString albumDir = fi.absolutePath();
            if (QDir(albumDir).exists())
                return albumDir;
        }
    }

    // Fall back to MUSIC_REPO from config (cached at construction)
    return m_musicRepoDir;
}

// ============================================================================
//  LUFS measurement — reads integrated loudness from the first MP3 in a dir
// ============================================================================

/// Scan a directory for the first .mp3 file and measure its integrated LUFS
/// via ffmpeg's ebur128 filter.  Returns the LUFS value (negative number),
/// or 0.0 if measurement fails or no MP3 is found.
static double measureDirectoryLufs(const QString &dirPath)
{
    // Find the first .mp3 in the directory (non-recursive)
    QDirIterator it(dirPath, QStringList() << "*.mp3",
                    QDir::Files, QDirIterator::NoIteratorFlags);
    if (!it.hasNext())
        return 0.0;

    QString firstMp3 = it.next();

    // Run ffmpeg to measure integrated loudness
    //   ffmpeg -i file -af ebur128=framelog=quiet -f null - 2>&1
    // Output includes a line like:  "    I:         -10.4 LUFS"
    QProcess ffmpeg;
    ffmpeg.setProcessChannelMode(QProcess::MergedChannels);
    ffmpeg.start("ffmpeg", QStringList()
        << "-hide_banner"
        << "-i" << firstMp3
        << "-af" << "ebur128=framelog=quiet"
        << "-f" << "null" << "-");

    if (!ffmpeg.waitForFinished(10000))  // 10 sec timeout for one file
        return 0.0;

    QString output = QString::fromUtf8(ffmpeg.readAllStandardOutput());

    // Parse the last "I:" line (integrated loudness)
    //   I:         -10.4 LUFS
    QRegularExpression re(R"(I:\s+([-\d.]+)\s+LUFS)");
    QRegularExpressionMatchIterator matches = re.globalMatch(output);
    QRegularExpressionMatch lastMatch;
    while (matches.hasNext())
        lastMatch = matches.next();

    if (lastMatch.hasMatch()) {
        bool ok = false;
        double lufs = lastMatch.captured(1).toDouble(&ok);
        if (ok)
            return lufs;
    }

    return 0.0;
}

// ============================================================================
//  UI Construction
// ============================================================================

void MaintenancePanel::buildUi()
{
    // --- Top-level: scroll area wrapping everything -------------------------
    auto *outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);

    auto *scrollArea = new QScrollArea;
    scrollArea->setWidgetResizable(true);
    scrollArea->setFrameShape(QFrame::NoFrame);

    auto *scrollWidget = new QWidget;
    auto *mainLayout   = new QVBoxLayout(scrollWidget);

    // --- Operation group boxes ---------------------------------------------
    mainLayout->addWidget(createBuildGroup());
    mainLayout->addWidget(createTagCleanGroup());
    mainLayout->addWidget(createTagRebuildGroup());
    mainLayout->addWidget(createBoostGroup());
    mainLayout->addWidget(createNewTracksGroup());

    // --- Cancel button (hidden by default) ---------------------------------
    m_cancelBtn = new QPushButton("Cancel Running Operation");
    m_cancelBtn->setVisible(false);
    connect(m_cancelBtn, &QPushButton::clicked, m_runner, &ScriptRunner::cancelScript);
    mainLayout->addWidget(m_cancelBtn);

    // --- Log output area ---------------------------------------------------
    m_clearLogBtn = new QPushButton("Clear Log");
    mainLayout->addWidget(m_clearLogBtn);

    m_logOutput = new QPlainTextEdit;
    m_logOutput->setReadOnly(true);
    m_logOutput->setMaximumBlockCount(5000);  // keep memory bounded
    QFont monoFont("Monospace");
    monoFont.setStyleHint(QFont::Monospace);
    monoFont.setPointSize(9);
    m_logOutput->setFont(monoFont);
    m_logOutput->setMinimumHeight(200);
    mainLayout->addWidget(m_logOutput, 1);  // stretch factor 1 — log gets extra space

    connect(m_clearLogBtn, &QPushButton::clicked,
            m_logOutput, &QPlainTextEdit::clear);

    scrollArea->setWidget(scrollWidget);
    outerLayout->addWidget(scrollArea);
}

// ---------------------------------------------------------------------------
//  Build Library group
// ---------------------------------------------------------------------------
QGroupBox *MaintenancePanel::createBuildGroup()
{
    auto *group  = new QGroupBox("Build Library — musiclib_build.sh");
    auto *layout = new QVBoxLayout(group);

    auto *desc = new QLabel(
        "Full database rebuild from filesystem scan of MUSIC_REPO.  "
        "Backs up the current database before overwriting.  "
        "NOTE: For large music libraries this can take a long time to process.");
    desc->setWordWrap(true);
    layout->addWidget(desc);

    auto *btnRow = new QHBoxLayout;
    m_buildPreviewBtn = new QPushButton("Preview (dry-run)");
    m_buildExecuteBtn = new QPushButton("Execute");
    btnRow->addStretch();
    btnRow->addWidget(m_buildPreviewBtn);
    btnRow->addWidget(m_buildExecuteBtn);
    layout->addLayout(btnRow);

    connect(m_buildPreviewBtn, &QPushButton::clicked,
            this, [this]() { launchBuild(true); });
    connect(m_buildExecuteBtn, &QPushButton::clicked,
            this, [this]() { launchBuild(false); });

    return group;
}

// ---------------------------------------------------------------------------
//  Clean Tags group
// ---------------------------------------------------------------------------
QGroupBox *MaintenancePanel::createTagCleanGroup()
{
    auto *group  = new QGroupBox("Clean Tags — musiclib_tagclean.sh");
    auto *layout = new QVBoxLayout(group);

    auto *desc = new QLabel(
        "Merge ID3v1 → ID3v2, remove APE tags, embed album art.  "
        "Operates on a file or directory.  Creates tag backups before modifying.");
    desc->setWordWrap(true);
    layout->addWidget(desc);

    // Path row
    auto *pathRow = new QHBoxLayout;
    pathRow->addWidget(new QLabel("Path:"));
    m_tagCleanPath   = new QLineEdit;
    m_tagCleanPath->setPlaceholderText("Select file or directory…");
    m_tagCleanBrowse = new QPushButton("Browse…");
    pathRow->addWidget(m_tagCleanPath, 1);
    pathRow->addWidget(m_tagCleanBrowse);
    layout->addLayout(pathRow);

    connect(m_tagCleanBrowse, &QPushButton::clicked, this, [this]() {
        QString dir = pickDirectory("Select directory for tag cleaning");
        if (!dir.isEmpty())
            m_tagCleanPath->setText(dir);
    });

    // Mode row
    auto *modeRow = new QHBoxLayout;
    modeRow->addWidget(new QLabel("Mode:"));
    m_tagCleanMode = new QComboBox;
    m_tagCleanMode->addItem("merge — ID3v1→v2, remove APE, embed art", "merge");
    m_tagCleanMode->addItem("strip — Remove ID3v1 and APE only",       "strip");
    m_tagCleanMode->addItem("embed-art — Embed folder.jpg if missing", "embed-art");
    modeRow->addWidget(m_tagCleanMode, 1);
    layout->addLayout(modeRow);

    // Buttons
    auto *btnRow = new QHBoxLayout;
    m_tagCleanPreview = new QPushButton("Preview (dry-run)");
    m_tagCleanExecute = new QPushButton("Execute");
    btnRow->addStretch();
    btnRow->addWidget(m_tagCleanPreview);
    btnRow->addWidget(m_tagCleanExecute);
    layout->addLayout(btnRow);

    connect(m_tagCleanPreview, &QPushButton::clicked,
            this, [this]() { launchTagClean(true); });
    connect(m_tagCleanExecute, &QPushButton::clicked,
            this, [this]() { launchTagClean(false); });

    return group;
}

// ---------------------------------------------------------------------------
//  Rebuild Tags group
// ---------------------------------------------------------------------------
QGroupBox *MaintenancePanel::createTagRebuildGroup()
{
    auto *group  = new QGroupBox("Rebuild Tags — musiclib_tagrebuild.sh");
    auto *layout = new QVBoxLayout(group);

    auto *desc = new QLabel(
        "Repair corrupted tags by restoring values from the database.  "
        "Targets must already exist in musiclib.dsv.  Creates tag backups.");
    desc->setWordWrap(true);
    layout->addWidget(desc);

    // Path row
    auto *pathRow = new QHBoxLayout;
    pathRow->addWidget(new QLabel("Path:"));
    m_tagRebuildPath   = new QLineEdit;
    m_tagRebuildPath->setPlaceholderText("Select file or directory…");
    m_tagRebuildBrowse = new QPushButton("Browse…");
    pathRow->addWidget(m_tagRebuildPath, 1);
    pathRow->addWidget(m_tagRebuildBrowse);
    layout->addLayout(pathRow);

    connect(m_tagRebuildBrowse, &QPushButton::clicked, this, [this]() {
        QString dir = pickDirectory("Select directory for tag rebuild");
        if (!dir.isEmpty())
            m_tagRebuildPath->setText(dir);
    });

    // Options row
    auto *optRow = new QHBoxLayout;
    m_tagRebuildRecursive = new QCheckBox("Recursive (-r)");
    m_tagRebuildRecursive->setChecked(true);
    m_tagRebuildVerbose   = new QCheckBox("Verbose (-v)");
    optRow->addWidget(m_tagRebuildRecursive);
    optRow->addWidget(m_tagRebuildVerbose);
    optRow->addStretch();
    layout->addLayout(optRow);

    // Buttons
    auto *btnRow = new QHBoxLayout;
    m_tagRebuildPreview = new QPushButton("Preview (dry-run)");
    m_tagRebuildExecute = new QPushButton("Execute");
    btnRow->addStretch();
    btnRow->addWidget(m_tagRebuildPreview);
    btnRow->addWidget(m_tagRebuildExecute);
    layout->addLayout(btnRow);

    connect(m_tagRebuildPreview, &QPushButton::clicked,
            this, [this]() { launchTagRebuild(true); });
    connect(m_tagRebuildExecute, &QPushButton::clicked,
            this, [this]() { launchTagRebuild(false); });

    return group;
}

// ---------------------------------------------------------------------------
//  Boost Album group
// ---------------------------------------------------------------------------
QGroupBox *MaintenancePanel::createBoostGroup()
{
    auto *group  = new QGroupBox("Boost Album — boost_album.sh");
    auto *layout = new QVBoxLayout(group);

    // Check if RSGain is installed
    QString rsgainInstalled = configValue("RSGAIN_INSTALLED");
    bool hasRsgain = (rsgainInstalled == "true");

    if (!hasRsgain) {
        // RSGain not installed - disable the entire group
        group->setEnabled(false);
        group->setToolTip(
            "RSGain is not installed. Install rsgain to enable ReplayGain loudness normalization.\n"
            "Run musiclib_init_config.sh again after installation to update configuration.");
        
        auto *disabledLabel = new QLabel(
            "<i>RSGain not installed. This feature requires the 'rsgain' package.</i>");
        disabledLabel->setStyleSheet("color: gray;");
        disabledLabel->setWordWrap(true);
        layout->addWidget(disabledLabel);
        
        return group;
    }

    auto *desc = new QLabel(
        "Apply ReplayGain loudness targeting to an album directory via rsgain.  "
        "Adds ReplayGain tags to files (does not alter audio data).");
    desc->setWordWrap(true);
    layout->addWidget(desc);

    // Path row
    auto *pathRow = new QHBoxLayout;
    pathRow->addWidget(new QLabel("Album directory:"));
    m_boostPath   = new QLineEdit;
    m_boostPath->setPlaceholderText("Select album directory…");
    m_boostBrowse = new QPushButton("Browse…");
    pathRow->addWidget(m_boostPath, 1);
    pathRow->addWidget(m_boostBrowse);
    layout->addLayout(pathRow);

    connect(m_boostBrowse, &QPushButton::clicked, this, [this]() {
        QString dir = pickDirectory("Select album directory for loudness boost");
        if (!dir.isEmpty()) {
            m_boostPath->setText(dir);
            updateBoostSliderFromDirectory(dir);
        }
    });

    // Also update slider when user types/pastes a path and presses Enter
    connect(m_boostPath, &QLineEdit::editingFinished, this, [this]() {
        QString path = m_boostPath->text().trimmed();
        if (!path.isEmpty() && QDir(path).exists())
            updateBoostSliderFromDirectory(path);
    });

    // Target LUFS slider
    //
    // LUFS scale: -23 (quietest) to -6 (loudest).
    // The slider maps left=quiet, right=loud for intuitive use.
    // Slider range 6..23 (absolute LUFS values, displayed as negative).
    // Inverted so moving right = louder (smaller absolute value).

    auto *sliderLabel = new QLabel("Target loudness:");
    layout->addWidget(sliderLabel);

    auto *sliderRow = new QHBoxLayout;

    auto *quietLabel = new QLabel("← Quieter");
    quietLabel->setStyleSheet("color: gray; font-size: 9pt;");
    sliderRow->addWidget(quietLabel);

    m_boostSlider = new QSlider(Qt::Horizontal);
    m_boostSlider->setRange(6, 23);      // absolute LUFS values
    m_boostSlider->setValue(18);          // default: -18 LUFS
    m_boostSlider->setTickPosition(QSlider::TicksBelow);
    m_boostSlider->setTickInterval(1);
    m_boostSlider->setSingleStep(1);
    m_boostSlider->setPageStep(3);
    // Invert so right = louder (lower absolute value = louder)
    m_boostSlider->setInvertedAppearance(true);
    m_boostSlider->setInvertedControls(true);
    sliderRow->addWidget(m_boostSlider, 1);

    auto *loudLabel = new QLabel("Louder →");
    loudLabel->setStyleSheet("color: gray; font-size: 9pt;");
    sliderRow->addWidget(loudLabel);

    m_boostValueLabel = new QLabel("-18 LUFS");
    m_boostValueLabel->setMinimumWidth(70);
    m_boostValueLabel->setAlignment(Qt::AlignCenter);
    QFont valueFont = m_boostValueLabel->font();
    valueFont.setBold(true);
    m_boostValueLabel->setFont(valueFont);
    sliderRow->addWidget(m_boostValueLabel);

    layout->addLayout(sliderRow);

    // Numeric tick labels beneath the slider
    //   -23  -20     -17     -14     -11     -8   -6
    auto *tickRow = new QHBoxLayout;
    tickRow->setContentsMargins(0, 0, 0, 0);
    // Labels spaced to align approximately with slider tick marks.
    // We show labels at the endpoints and every 3 LUFS in between.
    const int tickValues[] = {-23, -20, -17, -14, -11, -8, -6};
    for (int i = 0; i < 7; ++i) {
        auto *tickLabel = new QLabel(QString::number(tickValues[i]));
        tickLabel->setStyleSheet("color: gray; font-size: 8pt;");
        tickLabel->setAlignment(Qt::AlignCenter);
        tickRow->addWidget(tickLabel);
        if (i < 6)
            tickRow->addStretch();
    }
    // Pad left/right to roughly align with the slider area
    // (account for the "← Quieter" / "Louder →" / value label columns)
    auto *tickWrapper = new QHBoxLayout;
    tickWrapper->addSpacing(60);   // approximate width of "← Quieter"
    tickWrapper->addLayout(tickRow, 1);
    tickWrapper->addSpacing(130);  // approximate width of "Louder →" + value label
    layout->addLayout(tickWrapper);

    // Update label when slider moves
    connect(m_boostSlider, &QSlider::valueChanged, this, [this](int value) {
        m_boostValueLabel->setText(QString("-%1 LUFS").arg(value));
    });

    // Buttons (no dry-run for boost_album.sh)
    auto *btnRow = new QHBoxLayout;
    m_boostExecuteBtn = new QPushButton("Execute");
    btnRow->addStretch();
    btnRow->addWidget(m_boostExecuteBtn);
    layout->addLayout(btnRow);

    connect(m_boostExecuteBtn, &QPushButton::clicked,
            this, [this]() { launchBoost(); });

    return group;
}

// ============================================================================
//  Boost LUFS auto-detection
// ============================================================================

void MaintenancePanel::updateBoostSliderFromDirectory(const QString &dirPath)
{
    double lufs = measureDirectoryLufs(dirPath);

    if (lufs >= -23.0 && lufs <= -6.0) {
        // Value is within slider range — set it
        int absValue = static_cast<int>(qRound(-lufs));
        m_boostSlider->setValue(absValue);
        logStatus(QString("Measured current loudness: %1 LUFS (first track in %2)")
                  .arg(lufs, 0, 'f', 1)
                  .arg(QFileInfo(dirPath).fileName()));
    } else if (lufs < -23.0) {
        // Quieter than slider min — clamp to min and note it
        m_boostSlider->setValue(23);
        logStatus(QString("Measured current loudness: %1 LUFS (below slider range, clamped to -23)")
                  .arg(lufs, 0, 'f', 1));
    } else if (lufs > -6.0 && lufs != 0.0) {
        // Louder than slider max — clamp to max and note it
        m_boostSlider->setValue(6);
        logStatus(QString("Measured current loudness: %1 LUFS (above slider range, clamped to -6)")
                  .arg(lufs, 0, 'f', 1));
    }
    // lufs == 0.0 means measurement failed — leave slider at current position
}

// ============================================================================
//  Operation Launchers
// ============================================================================

void MaintenancePanel::launchBuild(bool dryRun)
{
    QString opId = dryRun ? "build-preview" : "build";
    logStatus(dryRun ? "=== Build Library (preview) ===" : "=== Build Library ===");

    QStringList args;
    if (dryRun)
        args << "--dry-run";

    setButtonsEnabled(false);
    m_runner->runScript(opId, "musiclib_build.sh", args);
}

void MaintenancePanel::launchTagClean(bool dryRun)
{
    QString path = m_tagCleanPath->text().trimmed();
    if (path.isEmpty()) {
        logStatus("ERROR: No path specified for tag cleaning.");
        return;
    }

    QString mode = m_tagCleanMode->currentData().toString();
    QString opId = dryRun ? "tagclean-preview" : "tagclean";
    logStatus(dryRun
        ? QString("=== Clean Tags — preview (%1) ===").arg(mode)
        : QString("=== Clean Tags — %1 ===").arg(mode));

    QStringList args;
    args << path << "--mode" << mode;
    if (dryRun)
        args << "-n";          // tagclean uses -n for dry-run

    setButtonsEnabled(false);
    m_runner->runScript(opId, "musiclib_tagclean.sh", args);
}

void MaintenancePanel::launchTagRebuild(bool dryRun)
{
    QString path = m_tagRebuildPath->text().trimmed();
    if (path.isEmpty()) {
        logStatus("ERROR: No path specified for tag rebuild.");
        return;
    }

    QString opId = dryRun ? "tagrebuild-preview" : "tagrebuild";
    logStatus(dryRun ? "=== Rebuild Tags (preview) ===" : "=== Rebuild Tags ===");

    QStringList args;
    args << path;
    if (m_tagRebuildRecursive->isChecked())
        args << "-r";
    if (dryRun)
        args << "-n";
    if (m_tagRebuildVerbose->isChecked())
        args << "-v";

    setButtonsEnabled(false);
    m_runner->runScript(opId, "musiclib_tagrebuild.sh", args);
}

void MaintenancePanel::launchBoost()
{
    QString path = m_boostPath->text().trimmed();
    if (path.isEmpty()) {
        logStatus("ERROR: No album directory specified for loudness boost.");
        return;
    }

    logStatus("=== Boost Album ===");

    QStringList args;
    args << path;
    // Slider value is absolute; pass as negative LUFS
    args << QString::number(m_boostSlider->value());

    setButtonsEnabled(false);
    m_runner->runScript("boost", "boost_album.sh", args);
}

// ---------------------------------------------------------------------------
//  Add New Tracks group
// ---------------------------------------------------------------------------
QGroupBox *MaintenancePanel::createNewTracksGroup()
{
    auto *group  = new QGroupBox("Add New Tracks — musiclib_new_tracks.sh");
    auto *layout = new QVBoxLayout(group);

    auto *desc = new QLabel(
        "Import new MP3 downloads from the configured NEW_DOWNLOAD_DIR into the library.  "
        "Extracts any ZIP file present, normalizes filenames and volume with rsgain, "
        "organises files into an artist/album folder under MUSIC_REPO, and adds the "
        "tracks to the database.  "
        "<b>Edit tags in kid3-qt before executing</b> — the tag-editing pause is "
        "bypassed automatically in GUI mode.");
    desc->setWordWrap(true);
    desc->setTextFormat(Qt::RichText);
    layout->addWidget(desc);

    // Artist name row
    auto *artistRow = new QHBoxLayout;
    artistRow->addWidget(new QLabel("Artist name:"));
    m_newTracksArtist = new QLineEdit;
    m_newTracksArtist->setPlaceholderText(
        "e.g.  Pink Floyd   (used for the artist sub-folder)");
    artistRow->addWidget(m_newTracksArtist, 1);
    layout->addLayout(artistRow);

    // Buttons (no dry-run — script does not support --dry-run)
    auto *btnRow = new QHBoxLayout;
    m_newTracksExecuteBtn = new QPushButton("Execute");
    btnRow->addStretch();
    btnRow->addWidget(m_newTracksExecuteBtn);
    layout->addLayout(btnRow);

    connect(m_newTracksExecuteBtn, &QPushButton::clicked,
            this, [this]() { launchNewTracks(); });

    return group;
}

void MaintenancePanel::launchNewTracks()
{
    QString artist = m_newTracksArtist->text().trimmed();
    if (artist.isEmpty()) {
        logStatus("ERROR: Artist name is required for new track import.");
        return;
    }

    logStatus("=== Add New Tracks ===");
    setButtonsEnabled(false);

    // If kid3 is open it may be holding file handles on tracks in the
    // download directory.  Close it first so the script can rename and
    // move files freely, then wait 800 ms for the process to exit and
    // release its handles before we start the script.
    if (closeKid3IfRunning()) {
        logStatus("kid3 was open — closing it before importing...");
        QTimer::singleShot(800, this, [this, artist]() {
            QStringList args;
            args << artist;
            m_runner->runScript("newtracks", "musiclib_new_tracks.sh", args, "\n");
        });
    } else {
        QStringList args;
        args << artist;
        m_runner->runScript("newtracks", "musiclib_new_tracks.sh", args, "\n");
    }
}

bool MaintenancePanel::closeKid3IfRunning()
{
    // Check for both common kid3 binary names.
    // pgrep -x matches the exact process name (no substring matches).
    const QStringList kid3Names = {
        QStringLiteral("kid3-qt"),
        QStringLiteral("kid3")
    };

    bool found = false;
    for (const QString &name : kid3Names) {
        QProcess pgrep;
        pgrep.start(QStringLiteral("pgrep"),
                    QStringList() << QStringLiteral("-x") << name);
        pgrep.waitForFinished(2000);

        if (pgrep.exitCode() == 0) {   // exit 0 = at least one match found
            // SIGTERM gives kid3 a chance to clean up before exiting
            QProcess::execute(QStringLiteral("pkill"),
                              QStringList() << QStringLiteral("-TERM")
                                            << QStringLiteral("-x") << name);
            found = true;
        }
    }
    return found;
}

// ============================================================================
//  Script Signal Handlers
// ============================================================================

void MaintenancePanel::onScriptOutput(const QString & /*operationId*/,
                                      const QString &line)
{
    m_logOutput->appendPlainText(line);
}

void MaintenancePanel::onScriptFinished(const QString &operationId,
                                        int exitCode,
                                        const QString &stderrContent)
{
    // Log the outcome
    if (exitCode == 0) {
        logStatus(QString("[%1] Completed successfully.").arg(operationId));
        if (operationId == "newtracks")
            m_newTracksArtist->clear();
    } else if (exitCode == 3) {
        // Deferred: some DB writes were queued because the database was locked.
        // musiclib_process_pending.sh is triggered automatically by the script.
        logStatus(QString("[%1] Completed — some operations queued (database was busy; "
                          "pending operations will be retried automatically).")
                  .arg(operationId));
    } else if (exitCode == 1 && operationId.endsWith("-preview")) {
        // Build dry-run returns exit 1 (informational, not an error)
        logStatus(QString("[%1] Preview complete.").arg(operationId));
    } else if (exitCode == -1) {
        // Pre-launch error (busy / script not found) — message is in stderr
        logStatus(QString("[%1] %2").arg(operationId, stderrContent));
    } else if (exitCode == -2) {
        logStatus(QString("[%1] Process crashed.").arg(operationId));
    } else {
        logStatus(QString("[%1] Exited with code %2.").arg(operationId).arg(exitCode));
        if (!stderrContent.isEmpty())
            logStatus("stderr: " + stderrContent);
    }

    setButtonsEnabled(true);
}

// ============================================================================
//  Helpers
// ============================================================================

QString MaintenancePanel::pickDirectory(const QString &caption)
{
    return QFileDialog::getExistingDirectory(this, caption, browseStartDir(),
        QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks);
}

QString MaintenancePanel::pickFile(const QString &caption)
{
    return QFileDialog::getOpenFileName(this, caption, browseStartDir(),
        "MP3 Files (*.mp3);;All Files (*)");
}

void MaintenancePanel::setButtonsEnabled(bool enabled)
{
    m_buildPreviewBtn->setEnabled(enabled);
    m_buildExecuteBtn->setEnabled(enabled);
    m_tagCleanPreview->setEnabled(enabled);
    m_tagCleanExecute->setEnabled(enabled);
    m_tagRebuildPreview->setEnabled(enabled);
    m_tagRebuildExecute->setEnabled(enabled);
    // m_boostExecuteBtn may be null when rsgain is not installed
    if (m_boostExecuteBtn)
        m_boostExecuteBtn->setEnabled(enabled);
    if (m_newTracksExecuteBtn)
        m_newTracksExecuteBtn->setEnabled(enabled);

    // Show cancel button only while a script is running
    m_cancelBtn->setVisible(!enabled);
}

void MaintenancePanel::logStatus(const QString &message)
{
    QString timestamp = QDateTime::currentDateTime().toString("hh:mm:ss");
    m_logOutput->appendPlainText(QString("[%1] %2").arg(timestamp, message));
}
