#include "scriptrunner.h"

#include <QProcess>
#include <QDir>
#include <QFileInfo>
#include <QTimer>

// ---------------------------------------------------------------------------
// Script search paths (dev first, then installed)
// ---------------------------------------------------------------------------
static const QString DEV_SCRIPT_PATH  = QDir::homePath() + "/musiclib/bin";
static const QString INST_SCRIPT_PATH = "/usr/lib/musiclib/bin";

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------
ScriptRunner::ScriptRunner(QObject *parent)
    : QObject(parent)
{
}

// ---------------------------------------------------------------------------
// Path resolution (unchanged from v1)
// ---------------------------------------------------------------------------
QString ScriptRunner::resolveScript(const QString &scriptName)
{
    // Prefer development path so changes take effect without installing
    QString devPath = DEV_SCRIPT_PATH + "/" + scriptName;
    if (QFileInfo::exists(devPath))
        return devPath;

    QString instPath = INST_SCRIPT_PATH + "/" + scriptName;
    if (QFileInfo::exists(instPath))
        return instPath;

    return QString(); // not found
}

// ===========================================================================
//  Rating — v1 interface, preserved exactly
// ===========================================================================

void ScriptRunner::rate(const QString &filePath, int stars)
{
    QString script = resolveScript("musiclib_rate.sh");
    if (script.isEmpty()) {
        emit rateError(filePath, stars,
            "musiclib_rate.sh not found in ~/musiclib/bin or /usr/lib/musiclib/bin");
        return;
    }

    m_pendingFilePath = filePath;
    m_pendingStars    = stars;

    QProcess *process = new QProcess(this);

    connect(process,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &ScriptRunner::onRateProcessFinished);

    // Run: bash musiclib_rate.sh <stars> "<filepath>"
    // Star rating first, filepath second (optional arg for GUI mode)
    process->start("bash", QStringList()
        << script
        << QString::number(stars)
        << filePath);
}

void ScriptRunner::onRateProcessFinished(int exitCode)
{
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (process)
        process->deleteLater();

    switch (exitCode) {
    case 0:
        emit rateSuccess(m_pendingFilePath, m_pendingStars);
        break;
    case 3:
        emit rateDeferred(m_pendingFilePath, m_pendingStars);
        break;
    default: {
        QString errMsg;
        if (process) {
            errMsg = QString::fromUtf8(process->readAllStandardError()).trimmed();
        }
        if (errMsg.isEmpty())
            errMsg = QString("Script exited with code %1").arg(exitCode);
        emit rateError(m_pendingFilePath, m_pendingStars, errMsg);
        break;
    }
    }
}

// ===========================================================================
//  Record removal — v2.1 addition
// ===========================================================================

void ScriptRunner::removeRecord(const QString &filePath)
{
    QString script = resolveScript("musiclib_remove_record.sh");
    if (script.isEmpty()) {
        emit removeError(filePath,
            "musiclib_remove_record.sh not found in ~/musiclib/bin or /usr/lib/musiclib/bin");
        return;
    }

    m_pendingRemovePath = filePath;

    QProcess *process = new QProcess(this);

    connect(process,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &ScriptRunner::onRemoveProcessFinished);

    // Run: bash musiclib_remove_record.sh "<filepath>"
    process->start("bash", QStringList() << script << filePath);
}

void ScriptRunner::onRemoveProcessFinished(int exitCode)
{
    QProcess *process = qobject_cast<QProcess *>(sender());
    if (process)
        process->deleteLater();

    if (exitCode == 0) {
        emit removeSuccess(m_pendingRemovePath);
    } else {
        QString errMsg;
        if (process) {
            errMsg = QString::fromUtf8(process->readAllStandardError()).trimmed();
        }
        if (errMsg.isEmpty())
            errMsg = QString("Script exited with code %1").arg(exitCode);
        emit removeError(m_pendingRemovePath, errMsg);
    }
}

// ===========================================================================
//  Generic script execution — v2 addition
// ===========================================================================

bool ScriptRunner::isRunning() const
{
    return m_scriptProcess != nullptr
        && m_scriptProcess->state() != QProcess::NotRunning;
}

void ScriptRunner::runScript(const QString &operationId,
                             const QString &scriptName,
                             const QStringList &args)
{
    // Guard: only one generic operation at a time
    if (isRunning()) {
        emit scriptFinished(operationId, -1,
            "Another operation is already running.  Wait for it to finish or cancel it.");
        return;
    }

    QString scriptPath = resolveScript(scriptName);
    if (scriptPath.isEmpty()) {
        emit scriptFinished(operationId, -1,
            scriptName + " not found in ~/musiclib/bin or /usr/lib/musiclib/bin");
        return;
    }

    m_currentOpId = operationId;

    // Create a new QProcess each time (clean state)
    if (m_scriptProcess) {
        m_scriptProcess->deleteLater();
        m_scriptProcess = nullptr;
    }
    m_scriptProcess = new QProcess(this);

    // Merge channels: false — we capture stdout and stderr separately.
    // stdout  → real-time line-by-line via readyReadStandardOutput
    // stderr  → bulk-read on finish (contains JSON error if exit != 0)
    m_scriptProcess->setProcessChannelMode(QProcess::SeparateChannels);

    connect(m_scriptProcess, &QProcess::readyReadStandardOutput,
            this, &ScriptRunner::onScriptReadyRead);

    connect(m_scriptProcess,
            QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &ScriptRunner::onScriptProcessFinished);

    // Build argument list: bash <scriptPath> [args...]
    QStringList fullArgs;
    fullArgs << scriptPath << args;

    m_scriptProcess->start("bash", fullArgs);
}

void ScriptRunner::cancelScript()
{
    if (!isRunning())
        return;

    // Polite SIGTERM first
    m_scriptProcess->terminate();

    // If still running after 3 seconds, SIGKILL
    QTimer::singleShot(3000, this, [this]() {
        if (isRunning())
            m_scriptProcess->kill();
    });
}

// ---------------------------------------------------------------------------
//  Private slots — generic process
// ---------------------------------------------------------------------------

void ScriptRunner::onScriptReadyRead()
{
    if (!m_scriptProcess)
        return;

    // Read all available stdout, split into lines, emit each one.
    // canReadLine() respects line boundaries; readLine() strips \n.
    while (m_scriptProcess->canReadLine()) {
        QByteArray raw = m_scriptProcess->readLine();
        QString line = QString::fromUtf8(raw).trimmed();
        if (!line.isEmpty())
            emit scriptOutput(m_currentOpId, line);
    }
}

void ScriptRunner::onScriptProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    // Flush any remaining stdout that didn't end with a newline
    if (m_scriptProcess) {
        QByteArray remainder = m_scriptProcess->readAllStandardOutput();
        if (!remainder.isEmpty()) {
            QString line = QString::fromUtf8(remainder).trimmed();
            if (!line.isEmpty())
                emit scriptOutput(m_currentOpId, line);
        }
    }

    // Capture full stderr for JSON error parsing by the caller
    QString stderrContent;
    if (m_scriptProcess)
        stderrContent = QString::fromUtf8(m_scriptProcess->readAllStandardError()).trimmed();

    // Treat a crash as exit code -2 so callers can distinguish it
    int effectiveCode = (status == QProcess::CrashExit) ? -2 : exitCode;

    emit scriptFinished(m_currentOpId, effectiveCode, stderrContent);

    // Clean up
    if (m_scriptProcess) {
        m_scriptProcess->deleteLater();
        m_scriptProcess = nullptr;
    }
}
