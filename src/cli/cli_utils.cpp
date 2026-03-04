// cli_utils.cpp - CLI utility functions implementation
// Phase 1, Task 2: Argument Parser Implementation

#include "cli_utils.h"
#include "output_streams.h"
#include <QFileInfo>
#include <QDir>
#include <QCoreApplication>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <vector>
#include <string>

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
    
    // Replace this process with the script using execvp.
    // The script inherits the real terminal's stdin/stdout/stderr directly —
    // no pipes, no buffering, no Qt event loop in between.
    // This is correct for a thin dispatcher: once the script is found and
    // arguments are validated, there is nothing left for C++ to do.
    // execvp only returns if exec itself fails (e.g. permission denied).
    std::vector<std::string> argStorage;
    argStorage.push_back(scriptPath.toStdString());
    for (const QString& arg : args)
        argStorage.push_back(arg.toStdString());

    std::vector<char*> argv;
    for (auto& s : argStorage)
        argv.push_back(const_cast<char*>(s.c_str()));
    argv.push_back(nullptr);

    execvp(argv[0], argv.data());

    // Only reached if execvp failed
    cerr << "Error: Failed to execute script: " << scriptPath << Qt::endl;
    cerr << "Reason: " << strerror(errno) << Qt::endl;
    return 2;
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
