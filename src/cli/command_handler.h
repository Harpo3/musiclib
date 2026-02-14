// command_handler.h - Command registry and routing for musiclib-cli
// Phase 1, Task 2: Argument Parser Implementation

#ifndef COMMAND_HANDLER_H
#define COMMAND_HANDLER_H

#include <QMap>
#include <QString>
#include <QStringList>
#include <functional>

/**
 * @brief Information about a registered subcommand
 */
struct CommandInfo {
    QString name;           // Command name (e.g., "rate", "build")
    QString description;    // Short description for help text
    QString usage;          // Usage syntax (e.g., "<filepath> <0-5>")
    QString scriptName;     // Backend script filename
    std::function<int(const QStringList&)> handler;  // Handler function
};

/**
 * @brief Central command registry and dispatcher
 * 
 * Manages registration of all subcommands and routes invocations
 * to appropriate handlers. Each handler validates arguments and
 * invokes the corresponding backend shell script.
 */
class CommandHandler {
public:
    /**
     * @brief Register all available subcommands
     * 
     * Must be called once during application startup before
     * executing any commands.
     */
    static void registerCommands();
    
    /**
     * @brief Execute a registered subcommand
     * @param cmd Subcommand name
     * @param args Arguments passed to the subcommand
     * @return Exit code from script execution (0=success, 1-3=error)
     */
    static int executeCommand(const QString& cmd, const QStringList& args);
    
    /**
     * @brief Show help for a specific command or all commands
     * @param cmd Optional command name. If empty, shows global help.
     */
    static void showHelp(const QString& cmd = QString());
    
    /**
     * @brief Show list of available commands with descriptions
     */
    static void showAvailableCommands();
    
private:
    // Command handlers (one per subcommand)
    static int handleRate(const QStringList& args);
    static int handleMobile(const QStringList& args);
    static int handleBuild(const QStringList& args);
    static int handleTagclean(const QStringList& args);
    static int handleTagrebuild(const QStringList& args);
    static int handleNewTracks(const QStringList& args);
    static int handleProcessPending(const QStringList& args);
    
    // Command registry
    static QMap<QString, CommandInfo> commands_;
    static bool registered_;
};

#endif // COMMAND_HANDLER_H
