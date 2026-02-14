// cli_utils.cpp - CLI utility functions implementation
// Phase 1, Task 2: Argument Parser Implementation

#include "cli_utils.h"
#include "output_streams.h"
#include <QProcess>
#include <QFileInfo>
#include <QDir>
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

int CLIUtils::executeScript(const QString& scriptName, const QStringList& args) {
    // Resolve script path
    QString scriptPath = resolveScriptPath(scriptName);
    
    if (scriptPath.isEmpty()) {
        cerr << "Error: Could not find script: " << scriptName << Qt::endl;
        cerr << "Searched in:" << Qt::endl;
        cerr << "  - MUSICLIB_SCRIPT_PATH environment variable" << Qt::endl;
        cerr << "  - /usr/lib/musiclib/bin/" << Qt::endl;
        cerr << "  - Development paths relative to binary" << Qt::endl;
        return 2;
    }
    
    // Execute script via QProcess
    QProcess process;
    process.setProgram(scriptPath);
    process.setArguments(args);
    
    // Start process and wait for completion
    process.start();
    
    if (!process.waitForStarted()) {
        cerr << "Error: Failed to start script: " << scriptPath << Qt::endl;
        cerr << "Reason: " << process.errorString() << Qt::endl;
        return 2;
    }
    
    if (!process.waitForFinished(-1)) {  // Wait indefinitely
        cerr << "Error: Script execution timeout or crash" << Qt::endl;
        return 2;
    }
    
    // Capture output
    QString stdoutData = QString::fromUtf8(process.readAllStandardOutput());
    QString stderrData = QString::fromUtf8(process.readAllStandardError());
    
    int exitCode = process.exitCode();
    
    // Display stdout (script may have informational output)
    if (!stdoutData.isEmpty()) {
        cout << stdoutData;
        if (!stdoutData.endsWith('\n')) {
            cout << Qt::endl;
        }
    }
    
    // Handle errors (exit code != 0)
    if (exitCode != 0) {
        // Try to parse JSON error from stderr
        if (!stderrData.isEmpty()) {
            // Check if stderr looks like JSON
            if (stderrData.trimmed().startsWith('{')) {
                displayScriptError(stderrData);
            } else {
                // Not JSON, display raw stderr
                cerr << "Script error output:" << Qt::endl;
                cerr << stderrData;
                if (!stderrData.endsWith('\n')) {
                    cerr << Qt::endl;
                }
            }
        } else {
            cerr << "Script failed with exit code " << exitCode << " (no error details)" << Qt::endl;
        }
    }
    
    return exitCode;
}

QString CLIUtils::resolveScriptPath(const QString& scriptName) {
    QStringList searchPaths;
    
    // 1. Environment variable override
    QByteArray envPath = qgetenv("MUSICLIB_SCRIPT_PATH");
    if (!envPath.isEmpty()) {
        searchPaths << QString::fromUtf8(envPath);
    }
    
    // 2. Production install path
    searchPaths << "/usr/lib/musiclib/bin";
    
    // 3. Development paths relative to binary location
    QString appDir = QCoreApplication::applicationDirPath();
    
    // If binary is in build/bin/, scripts are in project root bin/
    QDir buildDir(appDir);
    if (buildDir.cdUp() && buildDir.exists("bin")) {
        searchPaths << buildDir.filePath("bin");
    }
    
    // Also check one more level up (in case binary is in build/bin/Debug or similar)
    QDir buildDir2(appDir);
    if (buildDir2.cdUp() && buildDir2.cdUp() && buildDir2.exists("bin")) {
        searchPaths << buildDir2.filePath("bin");
    }
    
    // 4. Current working directory
    searchPaths << "./bin";
    searchPaths << ".";
    
    // Search for script in all paths
    for (const QString& path : searchPaths) {
        QString fullPath = QDir(path).filePath(scriptName);
        QFileInfo fileInfo(fullPath);
        
        if (fileInfo.exists() && fileInfo.isFile() && fileInfo.isExecutable()) {
            return fileInfo.absoluteFilePath();
        }
    }
    
    return QString();  // Not found
}

void CLIUtils::displayScriptError(const QString& jsonOutput) {
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(jsonOutput.toUtf8(), &parseError);
    
    if (parseError.error != QJsonParseError::NoError) {
        // JSON parsing failed, display raw output
        cerr << "Script error (malformed JSON):" << Qt::endl;
        cerr << jsonOutput << Qt::endl;
        return;
    }
    
    QJsonObject errorObj = doc.object();
    
    // Extract error fields
    QString errorMsg = errorObj["error"].toString("Unknown error");
    QString script = errorObj["script"].toString("unknown");
    int code = errorObj["code"].toInt(-1);
    QString timestamp = errorObj["timestamp"].toString();
    
    // Display formatted error
    cerr << "Error: " << errorMsg << Qt::endl;
    cerr << "Script: " << script;
    if (code >= 0) {
        cerr << " (exit code " << code << ")";
    }
    cerr << Qt::endl;
    
    // Display context if present
    if (errorObj.contains("context")) {
        QJsonObject context = errorObj["context"].toObject();
        if (!context.isEmpty()) {
            cerr << "Context:" << Qt::endl;
            for (auto it = context.begin(); it != context.end(); ++it) {
                cerr << "  " << it.key() << ": " << it.value().toString() << Qt::endl;
            }
        }
    }
}

bool CLIUtils::isAudioFile(const QString& filepath) {
    QFileInfo fileInfo(filepath);
    
    if (!fileInfo.exists() || !fileInfo.isFile()) {
        return false;
    }
    
    QString extension = fileInfo.suffix().toLower();
    return audioExtensions().contains(extension);
}

QStringList CLIUtils::audioExtensions() {
    return {
        "mp3", "flac", "ogg", "opus", "m4a", "aac",
        "wma", "wav", "ape", "wv", "tta", "mpc"
    };
}
