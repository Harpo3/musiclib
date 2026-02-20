#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QProcess>

///
/// ScriptRunner — Async script executor for the MusicLib GUI.
///
/// Provides two execution modes:
///
///   1. rate()       — Dedicated method for musiclib_rate.sh (unchanged from v1).
///                     Emits rateSuccess / rateDeferred / rateError.
///
///   2. runScript()  — Generic method for any backend script.
///                     Emits scriptOutput (real-time, line-by-line stdout),
///                     scriptFinished (exit code + stderr on completion).
///                     Used by the Maintenance Operations Panel.
///
/// Both modes are non-blocking.  QProcess runs on the main event loop
/// (no QThread needed — QProcess I/O is already async).
///
class ScriptRunner : public QObject
{
    Q_OBJECT

public:
    explicit ScriptRunner(QObject *parent = nullptr);

    // --- Rating (v1 interface, unchanged) -----------------------------------

    /// Invoke musiclib_rate.sh with filepath and star rating (0-5).
    void rate(const QString &filePath, int stars);

    // --- Generic script execution (v2 addition) -----------------------------

    /// Run any backend script asynchronously.
    ///
    /// @param operationId  Caller-chosen tag so signals can be correlated
    ///                     (e.g. "build", "tagclean", "tagrebuild", "boost").
    /// @param scriptName   Basename of the shell script (e.g. "musiclib_build.sh").
    /// @param args         Arguments to pass after the script path.
    ///
    /// While the script runs, scriptOutput() is emitted for every line of
    /// stdout.  When the process exits, scriptFinished() is emitted once.
    ///
    /// Only one generic operation may run at a time.  Call isRunning() first.
    void runScript(const QString &operationId,
                   const QString &scriptName,
                   const QStringList &args = {});

    /// Cancel a running generic operation (sends SIGTERM, then SIGKILL after 3 s).
    void cancelScript();

    /// True while a generic runScript() operation is in progress.
    bool isRunning() const;

    // --- Utility ------------------------------------------------------------

    /// Resolve path to a named script (checks dev path then installed path).
    static QString resolveScript(const QString &scriptName);

signals:
    // --- Rating signals (v1, unchanged) -------------------------------------
    void rateSuccess(const QString &filePath, int stars);
    void rateDeferred(const QString &filePath, int stars);   // exit code 3
    void rateError(const QString &filePath, int stars, const QString &message);

    // --- Generic script signals (v2 addition) -------------------------------

    /// Emitted for each line of stdout while the script runs.
    void scriptOutput(const QString &operationId, const QString &line);

    /// Emitted once when the script process exits.
    /// @param stderrContent  Full stderr captured at exit (may contain JSON error).
    void scriptFinished(const QString &operationId,
                        int exitCode,
                        const QString &stderrContent);

private slots:
    // Rating process handler (v1)
    void onRateProcessFinished(int exitCode);

    // Generic process handlers (v2)
    void onScriptReadyRead();
    void onScriptProcessFinished(int exitCode, QProcess::ExitStatus status);

private:
    // --- Rating state (v1) --------------------------------------------------
    QString m_pendingFilePath;
    int     m_pendingStars = 0;

    // --- Generic execution state (v2) ---------------------------------------
    QProcess *m_scriptProcess  = nullptr;
    QString   m_currentOpId;
};
