// cli_utils.h - CLI utility functions
// Phase 1, Task 2: Argument Parser Implementation

#ifndef CLI_UTILS_H
#define CLI_UTILS_H

#include <QString>
#include <QStringList>

/**
 * @brief Utility functions for CLI operations
 * 
 * Provides helper functions for script execution, path resolution,
 * error handling, and output formatting.
 */
class CLIUtils {
public:
    /**
     * @brief Execute a backend shell script with arguments
     * @param scriptName Name of script (e.g., "musiclib_rate.sh")
     * @param args Arguments to pass to script
     * @return Exit code from script (0=success, 1-3=error codes)
     * 
     * This function:
     * 1. Resolves script path (checks dev paths, then install paths)
     * 2. Replaces this process with the script via execvp
     *    (stdin/stdout/stderr inherited from the terminal — no pipes)
     * 3. Only returns if execvp itself fails (returns exit code 2)
     */
    static int executeScript(const QString& scriptName, const QStringList& args);
    
    /**
     * @brief Resolve full path to a backend script
     * @param scriptName Script filename
     * @return Full path to script, or empty string if not found
     * 
     * Search order:
     * 1. MUSICLIB_SCRIPT_PATH environment variable
     * 2. /usr/lib/musiclib/bin/ (production install)
     * 3. ${CMAKE_SOURCE_DIR}/scripts/ (development - checks relative to binary)
     * 4. ./scripts/ (fallback for direct execution)
     */
    static QString resolveScriptPath(const QString& scriptName);
    
    /**
     * @brief Check if a path is a valid audio file
     * @param filepath Path to check
     * @return true if file exists and has audio extension
     */
    static bool isAudioFile(const QString& filepath);
    
    /**
     * @brief Get list of supported audio extensions
     * @return List of extensions (without dots)
     */
    static QStringList audioExtensions();
};

#endif // CLI_UTILS_H
