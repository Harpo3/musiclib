#include "scriptrunner.h"

#include <QProcess>
#include <QDir>
#include <QFileInfo>

// Development path (running from build dir)
static const QString DEV_SCRIPT_PATH  = QDir::homePath() + "/musiclib/bin";
// Installed path
static const QString INST_SCRIPT_PATH = "/usr/lib/musiclib/bin";

ScriptRunner::ScriptRunner(QObject *parent)
    : QObject(parent)
{
}

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
            this, &ScriptRunner::onProcessFinished);

    // Run: bash musiclib_rate.sh "<filepath>" <stars>
    process->start("bash", QStringList() << script << filePath << QString::number(stars));
}

void ScriptRunner::onProcessFinished(int exitCode)
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
