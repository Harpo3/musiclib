// mobile_panel.cpp - Mobile sync panel for MusicLib GUI
// Phase 3: KDE Integration
//
// See mobile_panel.h for overview and toolbar integration notes.

#include "mobile_panel.h"
#include "scriptrunner.h"   // for ScriptRunner::resolveScript() (static)

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QMessageBox>
#include <QScrollArea>
#include <QUrl>
#include <QVBoxLayout>
#include <QFont>
#include <QRegularExpression>
#include <QApplication>

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

MobilePanel::MobilePanel(const QString &playlistsDir,
                         const QString &audaciousPlaylistsDir,
                         const QString &mobileDir,
                         const QString &configDeviceId,
                         QWidget *parent)
    : QWidget(parent)
    , m_playlistsDir(playlistsDir)
    , m_audaciousPlaylistsDir(audaciousPlaylistsDir)
    , m_mobileDir(mobileDir)
    , m_configDeviceId(configDeviceId)
    , m_deviceScanProcess(nullptr)
    , m_uploadProcess(nullptr)
    , m_statusProcess(nullptr)
    , m_checkUpdateProcess(nullptr)
    , m_operationProcess(nullptr)
    , m_operationInProgress(false)
{
    setupUi();

    // Initial population
    refreshPlaylists();
    scanDevices();
    refreshStatus();
}

MobilePanel::~MobilePanel()
{
    // Kill any running processes
    for (auto *proc : {m_deviceScanProcess, m_uploadProcess,
                       m_statusProcess, m_checkUpdateProcess,
                       m_operationProcess}) {
        if (proc && proc->state() != QProcess::NotRunning) {
            proc->kill();
            proc->waitForFinished(1000);
        }
    }
}

// ---------------------------------------------------------------------------
// UI Construction
// ---------------------------------------------------------------------------

void MobilePanel::setupUi()
{
    // The panel is wrapped in a scroll area so it works on smaller screens
    auto *outerLayout = new QVBoxLayout(this);
    outerLayout->setContentsMargins(0, 0, 0, 0);

    auto *scrollArea = new QScrollArea;
    scrollArea->setWidgetResizable(true);
    scrollArea->setFrameShape(QFrame::NoFrame);

    auto *scrollContent = new QWidget;
    auto *mainLayout = new QVBoxLayout(scrollContent);
    mainLayout->setSpacing(12);

    mainLayout->addWidget(createDeviceSection());
    mainLayout->addWidget(createPlaylistSection());
    mainLayout->addWidget(createOptionsSection());
    mainLayout->addWidget(createActionButtons());
    mainLayout->addWidget(createPreviewSection());
    mainLayout->addWidget(createProgressSection());
    mainLayout->addWidget(createStatusSection());
    mainLayout->addStretch();

    scrollArea->setWidget(scrollContent);
    outerLayout->addWidget(scrollArea);
}

QGroupBox* MobilePanel::createDeviceSection()
{
    auto *group = new QGroupBox(tr("KDE Connect Device"));
    auto *layout = new QHBoxLayout(group);

    m_deviceCombo = new QComboBox;
    m_deviceCombo->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    m_deviceCombo->setPlaceholderText(tr("No devices found — click Refresh"));

    m_deviceStatusLabel = new QLabel;
    m_deviceStatusLabel->setFixedWidth(16);

    m_deviceRefreshBtn = new QPushButton(tr("Refresh"));
    m_deviceRefreshBtn->setToolTip(tr("Re-scan for KDE Connect devices"));
    connect(m_deviceRefreshBtn, &QPushButton::clicked, this, &MobilePanel::scanDevices);

    layout->addWidget(m_deviceStatusLabel);
    layout->addWidget(m_deviceCombo, 1);
    layout->addWidget(m_deviceRefreshBtn);

    return group;
}

QGroupBox* MobilePanel::createPlaylistSection()
{
    auto *group = new QGroupBox(tr("Playlist"));
    auto *layout = new QVBoxLayout(group);

    // Row 1: combo + format label
    auto *row1 = new QHBoxLayout;
    m_playlistCombo = new QComboBox;
    m_playlistCombo->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed);
    m_playlistCombo->setPlaceholderText(tr("Select a playlist..."));
    connect(m_playlistCombo, QOverload<int>::of(&QComboBox::currentIndexChanged),
            this, &MobilePanel::onPlaylistSelected);

    m_formatLabel = new QLabel;
    m_formatLabel->setMinimumWidth(120);

    row1->addWidget(m_playlistCombo, 1);
    row1->addWidget(m_formatLabel);
    layout->addLayout(row1);

    // Row 2: track count + refresh button
    auto *row2 = new QHBoxLayout;
    m_trackCountLabel = new QLabel;

    m_refreshAudaciousBtn = new QPushButton(tr("Refresh from Audacious"));
    m_refreshAudaciousBtn->setToolTip(
        tr("Import all playlists from Audacious into MusicLib playlists directory.\n"
           "Invokes: musiclib_mobile.sh refresh-audacious-only"));
    connect(m_refreshAudaciousBtn, &QPushButton::clicked,
            this, &MobilePanel::refreshFromAudacious);

    row2->addWidget(m_trackCountLabel, 1);
    row2->addWidget(m_refreshAudaciousBtn);
    layout->addLayout(row2);

    return group;
}

QGroupBox* MobilePanel::createOptionsSection()
{
    auto *group = new QGroupBox(tr("Options"));
    auto *layout = new QVBoxLayout(group);

    // Halt-if-newer checkbox
    m_haltIfNewerCheck = new QCheckBox(
        tr("Halt upload if Audacious version is newer"));
    m_haltIfNewerCheck->setToolTip(
        tr("When checked, upload will not proceed if a newer version of the\n"
           "selected playlist exists in the Audacious playlists directory.\n"
           "A dialog will notify you. Uncheck to auto-import the newer version."));
    m_haltIfNewerCheck->setChecked(false);
    layout->addWidget(m_haltIfNewerCheck);

    // End-time override
    auto *endTimeRow = new QHBoxLayout;
    m_endTimeCheck = new QCheckBox(tr("Override accounting end time:"));
    m_endTimeCheck->setToolTip(
        tr("Set a custom end timestamp for the previous playlist's accounting\n"
           "window. Used when you want to backdate when you stopped listening\n"
           "on your phone. Default: current time."));

    m_endTimeEdit = new QDateTimeEdit(QDateTime::currentDateTime());
    m_endTimeEdit->setDisplayFormat(QStringLiteral("MM/dd/yyyy HH:mm:ss"));
    m_endTimeEdit->setCalendarPopup(true);
    m_endTimeEdit->setEnabled(false);

    connect(m_endTimeCheck, &QCheckBox::toggled,
            m_endTimeEdit, &QDateTimeEdit::setEnabled);

    endTimeRow->addWidget(m_endTimeCheck);
    endTimeRow->addWidget(m_endTimeEdit, 1);
    layout->addLayout(endTimeRow);

    return group;
}

QWidget* MobilePanel::createActionButtons()
{
    auto *widget = new QWidget;
    auto *layout = new QHBoxLayout(widget);
    layout->setContentsMargins(0, 0, 0, 0);

    m_previewBtn = new QPushButton(tr("Preview"));
    m_previewBtn->setToolTip(tr("Parse the playlist and show track list, file sizes, and status"));
    connect(m_previewBtn, &QPushButton::clicked, this, &MobilePanel::showPreview);

    m_uploadBtn = new QPushButton(tr("Upload"));
    m_uploadBtn->setToolTip(
        tr("Upload playlist and music files to the selected device.\n"
           "Runs Phase A (accounting) then Phase B (transfer)."));
    connect(m_uploadBtn, &QPushButton::clicked, this, &MobilePanel::startUpload);

    m_retryBtn = new QPushButton(tr("Retry"));
    m_retryBtn->setToolTip(
        tr("Re-attempt failed accounting for the selected playlist.\n"
           "Only visible when recovery files (.pending_tracks or .failed) exist."));
    m_retryBtn->setVisible(false);  // Shown conditionally by updateRetryButtonVisibility()
    connect(m_retryBtn, &QPushButton::clicked, this, &MobilePanel::startRetry);

    m_updateLastPlayedBtn = new QPushButton(tr("Update Last-Played"));
    m_updateLastPlayedBtn->setToolTip(
        tr("Manually run accounting (synthetic last-played timestamps) for the\n"
           "selected playlist without uploading. Equivalent to:\n"
           "  musiclib_mobile.sh update-lastplayed <name>"));
    connect(m_updateLastPlayedBtn, &QPushButton::clicked,
            this, &MobilePanel::startUpdateLastPlayed);

    m_cleanupBtn = new QPushButton(tr("Cleanup"));
    m_cleanupBtn->setToolTip(
        tr("Remove orphaned metadata files from the mobile directory.\n"
           "Preserves current playlist and any playlists with recovery files."));
    connect(m_cleanupBtn, &QPushButton::clicked, this, &MobilePanel::startCleanup);

    layout->addWidget(m_previewBtn);
    layout->addWidget(m_uploadBtn);
    layout->addWidget(m_retryBtn);
    layout->addStretch();
    layout->addWidget(m_updateLastPlayedBtn);
    layout->addWidget(m_cleanupBtn);

    return widget;
}

QGroupBox* MobilePanel::createPreviewSection()
{
    m_previewGroup = new QGroupBox(tr("Track Preview"));
    m_previewGroup->setVisible(false);  // Hidden until user clicks Preview
    auto *layout = new QVBoxLayout(m_previewGroup);

    m_previewTable = new QTableWidget;
    m_previewTable->setColumnCount(3);
    m_previewTable->setHorizontalHeaderLabels({tr("Track"), tr("Size"), tr("Status")});
    m_previewTable->horizontalHeader()->setStretchLastSection(true);
    m_previewTable->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    m_previewTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_previewTable->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_previewTable->setAlternatingRowColors(true);
    m_previewTable->setMaximumHeight(250);

    m_previewSummary = new QLabel;
    m_previewSummary->setWordWrap(true);

    layout->addWidget(m_previewTable);
    layout->addWidget(m_previewSummary);

    return m_previewGroup;
}

QGroupBox* MobilePanel::createProgressSection()
{
    m_progressGroup = new QGroupBox(tr("Operation Output"));
    m_progressGroup->setVisible(false);  // Hidden until an operation starts
    auto *layout = new QVBoxLayout(m_progressGroup);

    m_progressBar = new QProgressBar;
    m_progressBar->setMinimum(0);
    m_progressBar->setMaximum(0);  // Indeterminate until we parse totals
    m_progressBar->setTextVisible(true);

    m_outputLog = new QTextEdit;
    m_outputLog->setReadOnly(true);
    m_outputLog->setMaximumHeight(200);
    QFont monoFont(QStringLiteral("monospace"));
    monoFont.setStyleHint(QFont::Monospace);
    m_outputLog->setFont(monoFont);

    layout->addWidget(m_progressBar);
    layout->addWidget(m_outputLog);

    return m_progressGroup;
}

QGroupBox* MobilePanel::createStatusSection()
{
    m_statusGroup = new QGroupBox(tr("Mobile Status"));
    auto *layout = new QVBoxLayout(m_statusGroup);

    m_statusText = new QTextEdit;
    m_statusText->setReadOnly(true);
    m_statusText->setMaximumHeight(180);
    QFont monoFont(QStringLiteral("monospace"));
    monoFont.setStyleHint(QFont::Monospace);
    m_statusText->setFont(monoFont);

    auto *refreshStatusBtn = new QPushButton(tr("Refresh Status"));
    connect(refreshStatusBtn, &QPushButton::clicked, this, &MobilePanel::refreshStatus);

    layout->addWidget(m_statusText);
    layout->addWidget(refreshStatusBtn);

    return m_statusGroup;
}

// ---------------------------------------------------------------------------
// Helper: start a script via QProcess using ScriptRunner path resolution
// ---------------------------------------------------------------------------

bool MobilePanel::startScriptProcess(QProcess *process,
                                     const QString &scriptName,
                                     const QStringList &args)
{
    QString scriptPath = ScriptRunner::resolveScript(scriptName);
    if (scriptPath.isEmpty()) {
        appendError(tr("Script not found: %1").arg(scriptName));
        return false;
    }

    QStringList fullArgs;
    fullArgs << scriptPath << args;
    process->start(QStringLiteral("bash"), fullArgs);
    return true;
}

// ---------------------------------------------------------------------------
// Device scanning — kdeconnect-cli -l
// ---------------------------------------------------------------------------

void MobilePanel::scanDevices()
{
    if (m_deviceScanProcess && m_deviceScanProcess->state() != QProcess::NotRunning)
        return;

    m_deviceRefreshBtn->setEnabled(false);
    m_deviceStatusLabel->setText(QStringLiteral("..."));

    if (!m_deviceScanProcess) {
        m_deviceScanProcess = new QProcess(this);
        connect(m_deviceScanProcess,
                QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &MobilePanel::onDeviceScanFinished);
    }

    m_deviceScanProcess->start(QStringLiteral("kdeconnect-cli"),
                               {QStringLiteral("-l")});
}

void MobilePanel::onDeviceScanFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    m_deviceRefreshBtn->setEnabled(true);

    if (exitCode != 0) {
        m_deviceCombo->clear();
        m_deviceStatusLabel->setText(QStringLiteral("\u2717"));  // ✗
        m_deviceStatusLabel->setToolTip(tr("kdeconnect-cli failed (exit %1)").arg(exitCode));
        return;
    }

    QByteArray output = m_deviceScanProcess->readAllStandardOutput();
    auto devices = parseDeviceList(output);

    // Preserve current selection if possible
    QString previousId;
    if (m_deviceCombo->currentIndex() >= 0)
        previousId = m_deviceCombo->currentData().toString();

    m_deviceCombo->clear();
    int restoreIndex = -1;

    for (const auto &dev : devices) {
        QString label = QStringLiteral("%1 (%2)%3")
            .arg(dev.name, dev.id, dev.reachable ? QString() : tr(" [offline]"));
        m_deviceCombo->addItem(label, dev.id);

        if (dev.id == previousId)
            restoreIndex = m_deviceCombo->count() - 1;
    }

    if (restoreIndex >= 0) {
        m_deviceCombo->setCurrentIndex(restoreIndex);
    } else if (m_deviceCombo->count() > 0) {
        // No previous UI selection — pick a smart default
        int defaultIndex = -1;

        // First: prefer the device matching DEVICE_ID from config
        if (!m_configDeviceId.isEmpty()) {
            for (int i = 0; i < m_deviceCombo->count(); ++i) {
                if (m_deviceCombo->itemData(i).toString() == m_configDeviceId) {
                    defaultIndex = i;
                    break;
                }
            }
        }

        // Second: fall back to first reachable device
        if (defaultIndex < 0) {
            for (int i = 0; i < devices.size(); ++i) {
                if (devices[i].reachable) {
                    defaultIndex = i;
                    break;
                }
            }
        }

        if (defaultIndex >= 0)
            m_deviceCombo->setCurrentIndex(defaultIndex);
        // else: no reachable devices — placeholder text shows naturally
    }

    // Update status indicator based on selected device
    bool anyReachable = false;
    for (const auto &dev : devices) {
        if (dev.reachable) { anyReachable = true; break; }
    }
    m_deviceStatusLabel->setText(anyReachable
        ? QStringLiteral("\u25CF") : QStringLiteral("\u25CB"));  // ● or ○
    m_deviceStatusLabel->setStyleSheet(anyReachable
        ? QStringLiteral("color: green;") : QStringLiteral("color: red;"));
    m_deviceStatusLabel->setToolTip(anyReachable
        ? tr("Device(s) reachable") : tr("No reachable devices"));
}

QList<KDEConnectDevice> MobilePanel::parseDeviceList(const QByteArray &output) const
{
    // kdeconnect-cli -l output format:
    //   - DeviceName: abc123def456 (paired and reachable)
    //   - DeviceName: abc123def456 (paired)
    QList<KDEConnectDevice> devices;
    static const QRegularExpression re(
        QStringLiteral(R"(^-\s+(.+?):\s+([a-f0-9_]+)\s+\((.+)\))"),
        QRegularExpression::MultilineOption);

    QString text = QString::fromUtf8(output);
    auto it = re.globalMatch(text);
    while (it.hasNext()) {
        auto match = it.next();
        KDEConnectDevice dev;
        dev.name = match.captured(1).trimmed();
        dev.id = match.captured(2).trimmed();
        dev.reachable = match.captured(3).contains(QStringLiteral("reachable"));
        devices.append(dev);
    }

    return devices;
}

// ---------------------------------------------------------------------------
// Playlist scanning — read PLAYLISTS_DIR
// ---------------------------------------------------------------------------

void MobilePanel::refreshPlaylists()
{
    QString previousSelection;
    if (m_playlistCombo->currentIndex() >= 0)
        previousSelection = m_playlistCombo->currentData().toString();

    m_playlistCombo->clear();

    auto entries = scanPlaylistDir();
    int restoreIndex = -1;

    for (const auto &entry : entries) {
        m_playlistCombo->addItem(entry.displayName, entry.filePath);
        if (entry.filePath == previousSelection)
            restoreIndex = m_playlistCombo->count() - 1;
    }

    if (restoreIndex >= 0) {
        m_playlistCombo->setCurrentIndex(restoreIndex);
    } else if (m_playlistCombo->count() > 0) {
        // No previous UI selection — try to match the currently uploaded playlist
        int currentPlaylistIndex = -1;
        QString currentPlaylistFile = m_mobileDir + QStringLiteral("/current_playlist");
        QFile cpFile(currentPlaylistFile);
        if (cpFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString currentName = QString::fromUtf8(cpFile.readAll()).trimmed();
            cpFile.close();
            if (!currentName.isEmpty()) {
                for (int i = 0; i < m_playlistCombo->count(); ++i) {
                    QString entryName = QFileInfo(
                        m_playlistCombo->itemData(i).toString()).completeBaseName();
                    if (entryName == currentName) {
                        currentPlaylistIndex = i;
                        break;
                    }
                }
            }
        }

        if (currentPlaylistIndex >= 0)
            m_playlistCombo->setCurrentIndex(currentPlaylistIndex);
        else
            m_playlistCombo->setCurrentIndex(0);  // Fall back to first entry
    }
}

QList<PlaylistEntry> MobilePanel::scanPlaylistDir() const
{
    QList<PlaylistEntry> entries;
    QDir dir(m_playlistsDir);

    if (!dir.exists())
        return entries;

    // Match the same formats as MainWindow::populatePlaylistDropdown()
    QStringList filters = {
        QStringLiteral("*.audpl"),
        QStringLiteral("*.m3u"),
        QStringLiteral("*.m3u8"),
        QStringLiteral("*.pls")
    };
    auto fileList = dir.entryInfoList(filters, QDir::Files, QDir::Name | QDir::IgnoreCase);

    for (const auto &fi : fileList) {
        PlaylistEntry entry;
        entry.filePath = fi.absoluteFilePath();
        entry.displayName = fi.completeBaseName();
        entry.format = fi.suffix().toLower();
        entries.append(entry);
    }

    return entries;
}

void MobilePanel::onPlaylistSelected(int index)
{
    if (index < 0) {
        m_formatLabel->clear();
        m_trackCountLabel->clear();
        return;
    }

    QString filePath = m_playlistCombo->currentData().toString();
    QFileInfo fi(filePath);

    // Format label with upload-support indicator
    QString suffix = fi.suffix().toLower();
    if (suffix == QStringLiteral("audpl")) {
        m_formatLabel->setText(tr("Format: Audacious (.audpl)"));
    } else if (suffix == QStringLiteral("m3u") || suffix == QStringLiteral("m3u8")) {
        m_formatLabel->setText(tr("Format: M3U (.%1) — upload not yet supported").arg(suffix));
    } else if (suffix == QStringLiteral("pls")) {
        m_formatLabel->setText(tr("Format: PLS (.pls) — upload not yet supported"));
    } else {
        m_formatLabel->setText(tr("Format: %1").arg(suffix));
    }

    // Quick track count (format-aware)
    auto tracks = parsePlaylist(filePath);
    m_trackCountLabel->setText(tr("%1 tracks").arg(tracks.size()));

    // Update retry button visibility based on recovery files
    updateRetryButtonVisibility();
}

// ---------------------------------------------------------------------------
// Refresh from Audacious — musiclib_mobile.sh refresh-audacious-only
// ---------------------------------------------------------------------------

void MobilePanel::refreshFromAudacious()
{
    if (m_operationInProgress)
        return;

    setOperationInProgress(true);
    m_progressGroup->setVisible(true);
    m_outputLog->clear();
    m_progressBar->setMaximum(0);  // Indeterminate
    appendOutput(tr("--- Refreshing playlists from Audacious ---"));

    if (!m_operationProcess) {
        m_operationProcess = new QProcess(this);
    } else if (m_operationProcess->state() != QProcess::NotRunning) {
        setOperationInProgress(false);
        return;
    }

    // Disconnect previous connections (shared process)
    disconnect(m_operationProcess, nullptr, this, nullptr);
    connect(m_operationProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MobilePanel::onRefreshAudaciousFinished);
    connect(m_operationProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        while (m_operationProcess->canReadLine()) {
            QString line = QString::fromUtf8(m_operationProcess->readLine()).trimmed();
            appendOutput(line);
        }
    });

    startScriptProcess(m_operationProcess,
                       QStringLiteral("musiclib_mobile.sh"),
                       {QStringLiteral("refresh-audacious-only"),
                        QStringLiteral("--non-interactive")});
}

void MobilePanel::onRefreshAudaciousFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    setOperationInProgress(false);
    m_progressBar->setMaximum(1);
    m_progressBar->setValue(1);

    if (exitCode == 0) {
        appendOutput(tr("--- Refresh complete ---"));
        refreshPlaylists();  // Repopulate combo with newly synced playlists
    } else {
        appendError(tr("Refresh failed (exit code %1)").arg(exitCode));
        QByteArray errData = m_operationProcess->readAllStandardError();
        if (!errData.isEmpty())
            appendError(QString::fromUtf8(errData));
    }
}

// ---------------------------------------------------------------------------
// Preview — C++-side playlist parsing (no script invocation)
// ---------------------------------------------------------------------------

void MobilePanel::showPreview()
{
    if (m_playlistCombo->currentIndex() < 0)
        return;

    QString filePath = m_playlistCombo->currentData().toString();
    auto tracks = parsePlaylist(filePath);

    m_previewTable->setRowCount(tracks.size());

    qint64 totalSize = 0;
    int missingCount = 0;

    for (int i = 0; i < tracks.size(); ++i) {
        const auto &track = tracks[i];

        auto *nameItem = new QTableWidgetItem(track.fileName);
        nameItem->setToolTip(track.filePath);
        m_previewTable->setItem(i, 0, nameItem);

        QString sizeStr;
        if (track.exists) {
            double mb = track.sizeBytes / 1048576.0;
            sizeStr = QStringLiteral("%1 MB").arg(mb, 0, 'f', 1);
            totalSize += track.sizeBytes;
        } else {
            sizeStr = QStringLiteral("\u2014");  // —
        }
        m_previewTable->setItem(i, 1, new QTableWidgetItem(sizeStr));

        auto *statusItem = new QTableWidgetItem(
            track.exists ? tr("OK") : tr("MISSING"));
        if (!track.exists) {
            statusItem->setForeground(Qt::red);
            missingCount++;
        }
        m_previewTable->setItem(i, 2, statusItem);
    }

    // Summary
    double totalMb = totalSize / 1048576.0;
    QString summary = tr("%1 tracks, %2 MB total")
        .arg(tracks.size())
        .arg(totalMb, 0, 'f', 1);
    if (missingCount > 0)
        summary += tr(", %1 missing").arg(missingCount);

    m_previewSummary->setText(summary);
    m_previewGroup->setVisible(true);
}

QList<PreviewTrack> MobilePanel::parsePlaylist(const QString &filePath) const
{
    QList<PreviewTrack> tracks;
    QFile file(filePath);

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return tracks;

    QString suffix = QFileInfo(filePath).suffix().toLower();

    if (suffix == QStringLiteral("audpl")) {
        // .audpl format: extract uri=file:// lines, URL-decode paths
        while (!file.atEnd()) {
            QByteArray rawLine = file.readLine().trimmed();
            if (!rawLine.startsWith("uri=file://"))
                continue;
            QByteArray encoded = rawLine.mid(11);  // len("uri=file://") == 11
            QString decoded = QUrl::fromPercentEncoding(encoded);

            PreviewTrack track;
            track.filePath = decoded;
            track.fileName = QFileInfo(decoded).fileName();
            track.exists = QFile::exists(decoded);
            track.sizeBytes = track.exists ? QFileInfo(decoded).size() : 0;
            tracks.append(track);
        }
    } else if (suffix == QStringLiteral("m3u") || suffix == QStringLiteral("m3u8")) {
        // .m3u/.m3u8: non-# lines are file paths (absolute or relative)
        QDir playlistDir = QFileInfo(filePath).absoluteDir();
        while (!file.atEnd()) {
            QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (line.isEmpty() || line.startsWith(QLatin1Char('#')))
                continue;

            // Resolve relative paths against the playlist's directory
            QString resolved = QFileInfo(line).isAbsolute()
                ? line
                : playlistDir.absoluteFilePath(line);

            PreviewTrack track;
            track.filePath = resolved;
            track.fileName = QFileInfo(resolved).fileName();
            track.exists = QFile::exists(resolved);
            track.sizeBytes = track.exists ? QFileInfo(resolved).size() : 0;
            tracks.append(track);
        }
    } else if (suffix == QStringLiteral("pls")) {
        // .pls: extract File= entries
        while (!file.atEnd()) {
            QString line = QString::fromUtf8(file.readLine()).trimmed();
            if (!line.startsWith(QStringLiteral("File"), Qt::CaseInsensitive))
                continue;
            int eqPos = line.indexOf(QLatin1Char('='));
            if (eqPos < 0)
                continue;
            QString path = line.mid(eqPos + 1).trimmed();
            // Strip file:// prefix if present
            if (path.startsWith(QStringLiteral("file://")))
                path = QUrl(path).toLocalFile();

            PreviewTrack track;
            track.filePath = path;
            track.fileName = QFileInfo(path).fileName();
            track.exists = QFile::exists(path);
            track.sizeBytes = track.exists ? QFileInfo(path).size() : 0;
            tracks.append(track);
        }
    }

    file.close();
    return tracks;
}

// ---------------------------------------------------------------------------
// Upload workflow — with halt-if-newer gate
// ---------------------------------------------------------------------------

void MobilePanel::startUpload()
{
    if (m_operationInProgress)
        return;

    if (m_playlistCombo->currentIndex() < 0) {
        QMessageBox::warning(this, tr("Upload"),
                             tr("No playlist selected."));
        return;
    }

    if (m_deviceCombo->currentIndex() < 0) {
        QMessageBox::warning(this, tr("Upload"),
                             tr("No KDE Connect device selected.\n"
                                "Click Refresh to scan for devices."));
        return;
    }

    // Check format — currently only .audpl is supported by the backend
    QString playlistPath = m_playlistCombo->currentData().toString();
    QString suffix = QFileInfo(playlistPath).suffix().toLower();
    if (suffix != QStringLiteral("audpl")) {
        QMessageBox::warning(this, tr("Upload"),
            tr("Upload currently only supports .audpl playlists.\n"
               "Selected file is .%1 format.\n\n"
               "Multi-format upload support is planned for a future release.")
            .arg(suffix));
        return;
    }

    QString playlistName = QFileInfo(playlistPath).completeBaseName();

    // --- Halt-if-newer gate ---
    // If the checkbox is checked, we invoke "check-update" first.
    // If unchecked, we skip straight to upload (--non-interactive
    // will auto-refresh any newer Audacious version).
    if (m_haltIfNewerCheck->isChecked()) {
        setOperationInProgress(true);
        m_pendingUploadPlaylist = playlistPath;

        if (!m_checkUpdateProcess) {
            m_checkUpdateProcess = new QProcess(this);
            connect(m_checkUpdateProcess,
                    QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                    this, &MobilePanel::onCheckUpdateFinished);
        }

        startScriptProcess(m_checkUpdateProcess,
                           QStringLiteral("musiclib_mobile.sh"),
                           {QStringLiteral("check-update"), playlistName});
        return;
    }

    // No halt check — proceed directly
    m_pendingUploadPlaylist = playlistPath;
    executeUpload();
}

void MobilePanel::onCheckUpdateFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    // Parse the STATUS: line from stdout
    QByteArray output = m_checkUpdateProcess->readAllStandardOutput();
    QString status = QString::fromUtf8(output).trimmed();

    // check-update exits 0 for newer/new, 1 for same/not_found
    if (exitCode == 0 && (status.contains(QStringLiteral("STATUS:newer")) ||
                          status.contains(QStringLiteral("STATUS:new")))) {
        // Newer version exists and user wants to halt
        setOperationInProgress(false);

        QString playlistName = QFileInfo(m_pendingUploadPlaylist).completeBaseName();
        QString msg;
        if (status.contains(QStringLiteral("STATUS:newer"))) {
            msg = tr("A newer version of '%1' exists in the Audacious playlists directory.\n\n"
                     "Upload halted. To proceed, either:\n"
                     "  \u2022 Uncheck 'Halt if Audacious version is newer', or\n"
                     "  \u2022 Click 'Refresh from Audacious' to import the newer version first")
                .arg(playlistName);
        } else {
            msg = tr("'%1' is a new playlist found in Audacious but not yet in MusicLib.\n\n"
                     "Upload halted. To proceed, either:\n"
                     "  \u2022 Uncheck 'Halt if Audacious version is newer', or\n"
                     "  \u2022 Click 'Refresh from Audacious' to import it first")
                .arg(playlistName);
        }

        QMessageBox::information(this, tr("Playlist Update Detected"), msg);
        return;
    }

    // Same, older, or not found in Audacious — safe to proceed
    executeUpload();
}

void MobilePanel::executeUpload()
{
    // Reset progress UI
    m_progressGroup->setVisible(true);
    m_outputLog->clear();
    m_progressBar->setMaximum(0);  // Indeterminate until first progress line parsed
    m_progressBar->setValue(0);
    setOperationInProgress(true);
    appendOutput(tr("--- Upload started ---"));

    // Build arguments
    QStringList args;
    args << QStringLiteral("upload");
    args << m_pendingUploadPlaylist;

    // Device ID (second positional arg)
    if (m_deviceCombo->currentIndex() >= 0)
        args << m_deviceCombo->currentData().toString();

    args << QStringLiteral("--non-interactive");

    // End-time override
    if (m_endTimeCheck->isChecked()) {
        args << QStringLiteral("--end-time");
        args << m_endTimeEdit->dateTime().toString(QStringLiteral("MM/dd/yyyy HH:mm:ss"));
    }

    // Create/reuse upload process (separate from m_operationProcess since
    // upload is the primary long-running operation and needs dedicated
    // stdout streaming)
    if (!m_uploadProcess) {
        m_uploadProcess = new QProcess(this);
        connect(m_uploadProcess, &QProcess::readyReadStandardOutput,
                this, &MobilePanel::onUploadReadyRead);
        connect(m_uploadProcess,
                QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &MobilePanel::onUploadFinished);
    }

    startScriptProcess(m_uploadProcess,
                       QStringLiteral("musiclib_mobile.sh"), args);
}

void MobilePanel::onUploadReadyRead()
{
    while (m_uploadProcess->canReadLine()) {
        QString line = QString::fromUtf8(m_uploadProcess->readLine()).trimmed();
        if (line.isEmpty())
            continue;

        appendOutput(line);
        parseProgressLine(line);
    }
}

void MobilePanel::onUploadFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    setOperationInProgress(false);
    m_progressBar->setMaximum(1);
    m_progressBar->setValue(1);

    // Read any remaining stderr
    QByteArray errData = m_uploadProcess->readAllStandardError();
    if (!errData.isEmpty())
        appendError(QString::fromUtf8(errData));

    if (exitCode == 0) {
        appendOutput(tr("--- Upload complete ---"));
        QString playlistName = QFileInfo(m_pendingUploadPlaylist).completeBaseName();
        emit uploadCompleted(playlistName, m_progressBar->maximum());
    } else {
        appendError(tr("Upload failed (exit code %1)").arg(exitCode));
    }

    // Refresh status to show updated state
    refreshStatus();
}

// ---------------------------------------------------------------------------
// Progress line parsing
// ---------------------------------------------------------------------------

void MobilePanel::parseProgressLine(const QString &line)
{
    // Parse ACCOUNTING: Track N/M: ...
    static const QRegularExpression accountingRe(
        QStringLiteral(R"(ACCOUNTING:\s*Track\s+(\d+)/(\d+):)"));
    auto am = accountingRe.match(line);
    if (am.hasMatch()) {
        int current = am.captured(1).toInt();
        int total = am.captured(2).toInt();
        if (total > 0) {
            m_progressBar->setMaximum(total);
            m_progressBar->setValue(current);
            m_progressBar->setFormat(tr("Accounting: %1/%2").arg(current).arg(total));
        }
        return;
    }

    // Parse UPLOAD: [N/M] filename
    static const QRegularExpression uploadRe(
        QStringLiteral(R"(UPLOAD:\s*\[(\d+)/(\d+)\])"));
    auto um = uploadRe.match(line);
    if (um.hasMatch()) {
        int current = um.captured(1).toInt();
        int total = um.captured(2).toInt();
        if (total > 0) {
            m_progressBar->setMaximum(total);
            m_progressBar->setValue(current);
            m_progressBar->setFormat(tr("Uploading: %1/%2").arg(current).arg(total));
        }
        return;
    }

    // Parse UPLOAD: Complete — N files transferred
    if (line.contains(QStringLiteral("UPLOAD: Complete"))) {
        m_progressBar->setFormat(tr("Complete"));
    }
}

// ---------------------------------------------------------------------------
// Retry — musiclib_mobile.sh retry <playlist_name>
// ---------------------------------------------------------------------------

void MobilePanel::startRetry()
{
    if (m_operationInProgress || m_playlistCombo->currentIndex() < 0)
        return;

    QString playlistName = QFileInfo(
        m_playlistCombo->currentData().toString()).completeBaseName();

    setOperationInProgress(true);
    m_progressGroup->setVisible(true);
    m_outputLog->clear();
    m_progressBar->setMaximum(0);
    appendOutput(tr("--- Retrying accounting for: %1 ---").arg(playlistName));

    if (!m_operationProcess)
        m_operationProcess = new QProcess(this);

    disconnect(m_operationProcess, nullptr, this, nullptr);
    connect(m_operationProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MobilePanel::onRetryFinished);
    connect(m_operationProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        while (m_operationProcess->canReadLine()) {
            QString line = QString::fromUtf8(m_operationProcess->readLine()).trimmed();
            appendOutput(line);
            parseProgressLine(line);
        }
    });

    startScriptProcess(m_operationProcess,
                       QStringLiteral("musiclib_mobile.sh"),
                       {QStringLiteral("retry"), playlistName});
}

void MobilePanel::onRetryFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    setOperationInProgress(false);
    m_progressBar->setMaximum(1);
    m_progressBar->setValue(1);

    if (exitCode == 0)
        appendOutput(tr("--- Retry complete ---"));
    else
        appendError(tr("Retry finished with exit code %1").arg(exitCode));

    QByteArray errData = m_operationProcess->readAllStandardError();
    if (!errData.isEmpty())
        appendError(QString::fromUtf8(errData));

    refreshStatus();
    updateRetryButtonVisibility();
}

// ---------------------------------------------------------------------------
// Update Last-Played — musiclib_mobile.sh update-lastplayed <name>
// ---------------------------------------------------------------------------

void MobilePanel::startUpdateLastPlayed()
{
    if (m_operationInProgress || m_playlistCombo->currentIndex() < 0)
        return;

    QString playlistName = QFileInfo(
        m_playlistCombo->currentData().toString()).completeBaseName();

    setOperationInProgress(true);
    m_progressGroup->setVisible(true);
    m_outputLog->clear();
    m_progressBar->setMaximum(0);
    appendOutput(tr("--- Updating last-played for: %1 ---").arg(playlistName));

    if (!m_operationProcess)
        m_operationProcess = new QProcess(this);

    disconnect(m_operationProcess, nullptr, this, nullptr);
    connect(m_operationProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MobilePanel::onUpdateLastPlayedFinished);
    connect(m_operationProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        while (m_operationProcess->canReadLine()) {
            QString line = QString::fromUtf8(m_operationProcess->readLine()).trimmed();
            appendOutput(line);
            parseProgressLine(line);
        }
    });

    QStringList args;
    args << QStringLiteral("update-lastplayed") << playlistName;
    args << QStringLiteral("--non-interactive");

    if (m_endTimeCheck->isChecked()) {
        args << QStringLiteral("--end-time");
        args << m_endTimeEdit->dateTime().toString(QStringLiteral("MM/dd/yyyy HH:mm:ss"));
    }

    startScriptProcess(m_operationProcess,
                       QStringLiteral("musiclib_mobile.sh"), args);
}

void MobilePanel::onUpdateLastPlayedFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    setOperationInProgress(false);
    m_progressBar->setMaximum(1);
    m_progressBar->setValue(1);

    if (exitCode == 0)
        appendOutput(tr("--- Update complete ---"));
    else
        appendError(tr("Update finished with exit code %1").arg(exitCode));

    QByteArray errData = m_operationProcess->readAllStandardError();
    if (!errData.isEmpty())
        appendError(QString::fromUtf8(errData));

    refreshStatus();
}

// ---------------------------------------------------------------------------
// Cleanup — musiclib_mobile.sh cleanup
// ---------------------------------------------------------------------------

void MobilePanel::startCleanup()
{
    if (m_operationInProgress)
        return;

    setOperationInProgress(true);
    m_progressGroup->setVisible(true);
    m_outputLog->clear();
    m_progressBar->setMaximum(0);
    appendOutput(tr("--- Cleanup started ---"));

    if (!m_operationProcess)
        m_operationProcess = new QProcess(this);

    disconnect(m_operationProcess, nullptr, this, nullptr);
    connect(m_operationProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MobilePanel::onCleanupFinished);
    connect(m_operationProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        while (m_operationProcess->canReadLine()) {
            QString line = QString::fromUtf8(m_operationProcess->readLine()).trimmed();
            appendOutput(line);
        }
    });

    startScriptProcess(m_operationProcess,
                       QStringLiteral("musiclib_mobile.sh"),
                       {QStringLiteral("cleanup")});
}

void MobilePanel::onCleanupFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    setOperationInProgress(false);
    m_progressBar->setMaximum(1);
    m_progressBar->setValue(1);

    if (exitCode == 0)
        appendOutput(tr("--- Cleanup complete ---"));
    else
        appendError(tr("Cleanup finished with exit code %1").arg(exitCode));

    refreshStatus();
}

// ---------------------------------------------------------------------------
// Status — musiclib_mobile.sh status
// ---------------------------------------------------------------------------

void MobilePanel::refreshStatus()
{
    if (m_statusProcess && m_statusProcess->state() != QProcess::NotRunning)
        return;

    if (!m_statusProcess) {
        m_statusProcess = new QProcess(this);
        connect(m_statusProcess,
                QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &MobilePanel::onStatusFinished);
    }

    if (!startScriptProcess(m_statusProcess,
                            QStringLiteral("musiclib_mobile.sh"),
                            {QStringLiteral("status")})) {
        m_statusText->setPlainText(
            tr("Status unavailable — musiclib_mobile.sh not found.\n"
               "Check that scripts are installed in ~/musiclib/bin/ "
               "or /usr/lib/musiclib/bin/."));
    }
}

void MobilePanel::onStatusFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/)
{
    QByteArray output = m_statusProcess->readAllStandardOutput();
    QByteArray errOutput = m_statusProcess->readAllStandardError();

    if (!output.isEmpty()) {
        m_statusText->setPlainText(QString::fromUtf8(output));
    } else if (exitCode != 0) {
        // Script ran but produced no stdout — show exit code and stderr
        QString msg = tr("Status script exited with code %1").arg(exitCode);
        if (!errOutput.isEmpty())
            msg += QStringLiteral("\n") + QString::fromUtf8(errOutput);
        m_statusText->setPlainText(msg);
    } else {
        m_statusText->setPlainText(
            tr("No status output returned.\n"
               "The status script ran successfully but produced no output."));
    }

    // Update retry button based on whether recovery files are mentioned
    updateRetryButtonVisibility();
}

// ---------------------------------------------------------------------------
// Toolbar integration — setPlaylist()
// ---------------------------------------------------------------------------

void MobilePanel::setPlaylist(const QString &playlistPath)
{
    // Find the matching entry in the combo box
    for (int i = 0; i < m_playlistCombo->count(); ++i) {
        if (m_playlistCombo->itemData(i).toString() == playlistPath) {
            m_playlistCombo->setCurrentIndex(i);
            return;
        }
    }

    // Not found — might need a playlist refresh first
    refreshPlaylists();

    for (int i = 0; i < m_playlistCombo->count(); ++i) {
        if (m_playlistCombo->itemData(i).toString() == playlistPath) {
            m_playlistCombo->setCurrentIndex(i);
            return;
        }
    }
}

// ---------------------------------------------------------------------------
// UI state helpers
// ---------------------------------------------------------------------------

void MobilePanel::setOperationInProgress(bool busy)
{
    m_operationInProgress = busy;

    m_uploadBtn->setEnabled(!busy);
    m_previewBtn->setEnabled(!busy);
    m_retryBtn->setEnabled(!busy && m_retryBtn->isVisible());
    m_updateLastPlayedBtn->setEnabled(!busy);
    m_cleanupBtn->setEnabled(!busy);
    m_refreshAudaciousBtn->setEnabled(!busy);
    m_playlistCombo->setEnabled(!busy);
    m_deviceCombo->setEnabled(!busy);

    QApplication::processEvents();
}

void MobilePanel::appendOutput(const QString &line)
{
    // Color-code by prefix
    QString html;
    if (line.startsWith(QStringLiteral("ACCOUNTING:")))
        html = QStringLiteral("<span style='color:#2196F3;'>%1</span>").arg(line.toHtmlEscaped());
    else if (line.startsWith(QStringLiteral("UPLOAD:")))
        html = QStringLiteral("<span style='color:#4CAF50;'>%1</span>").arg(line.toHtmlEscaped());
    else if (line.startsWith(QStringLiteral("---")))
        html = QStringLiteral("<b>%1</b>").arg(line.toHtmlEscaped());
    else
        html = line.toHtmlEscaped();

    m_outputLog->append(html);
}

void MobilePanel::appendError(const QString &line)
{
    m_outputLog->append(
        QStringLiteral("<span style='color:red;'>%1</span>").arg(line.toHtmlEscaped()));
}

void MobilePanel::updateRetryButtonVisibility()
{
    // Check if any .pending_tracks or .failed files exist in the mobile dir
    QDir mobileDir(m_mobileDir);
    bool hasRecovery = false;

    if (mobileDir.exists()) {
        QStringList pendingFiles = mobileDir.entryList(
            {QStringLiteral("*.pending_tracks"), QStringLiteral("*.failed")},
            QDir::Files);
        hasRecovery = !pendingFiles.isEmpty();
    }

    m_retryBtn->setVisible(hasRecovery);
}
