#pragma once

#include <QObject>
#include <QString>

class QProcess;

class ScriptRunner : public QObject
{
    Q_OBJECT

public:
    explicit ScriptRunner(QObject *parent = nullptr);

    // Invoke musiclib_rate.sh with filepath and star rating (0-5)
    void rate(const QString &filePath, int stars);

    // Resolve path to a named script (checks dev path then installed path)
    static QString resolveScript(const QString &scriptName);

signals:
    void rateSuccess(const QString &filePath, int stars);
    void rateDeferred(const QString &filePath, int stars);  // exit code 3
    void rateError(const QString &filePath, int stars, const QString &message);

private slots:
    void onProcessFinished(int exitCode);

private:
    QString m_pendingFilePath;
    int     m_pendingStars = 0;
};
