// main.cpp - Entry point for musiclib-cli dispatcher
// Phase 1, Task 2: Argument Parser Implementation

#include <QCoreApplication>
#include <QStringList>
#include <QTextStream>
#include <cstdlib>

#include "command_handler.h"
#include "cli_utils.h"

#include "output_streams.h"

// Define global output streams (declared in output_streams.h)
QTextStream cout(stdout);
QTextStream cerr(stderr);

void showVersion() {
    cout << "musiclib-cli version 0.2.0" << Qt::endl;
    cout << "Music library management CLI dispatcher" << Qt::endl;
    cout << "Backend API Version: 1.1" << Qt::endl;
    cout << "Copyright (c) 2025-2026 - Licensed under MIT" << Qt::endl;
}

void showGlobalHelp() {
    cout << "Usage: musiclib-cli <subcommand> [options] [arguments]" << Qt::endl;
    cout << Qt::endl;
    cout << "Music library management command-line interface." << Qt::endl;
    cout << Qt::endl;
    cout << "Global Options:" << Qt::endl;
    cout << "  -h, --help       Show this help message" << Qt::endl;
    cout << "  -v, --version    Show version information" << Qt::endl;
    cout << "  --config <path>  Use alternate config file (default: ~/.config/musiclib/musiclib.conf)" << Qt::endl;
    cout << Qt::endl;
    cout << "Available Subcommands:" << Qt::endl;
    
    CommandHandler::showAvailableCommands();
    
    cout << Qt::endl;
    cout << "Use 'musiclib-cli <subcommand> --help' for subcommand-specific help." << Qt::endl;
    cout << Qt::endl;
    cout << "Examples:" << Qt::endl;
    cout << "  musiclib-cli setup                                     # First-time configuration" << Qt::endl;
    cout << "  musiclib-cli rate 4                                    # Rate currently playing track" << Qt::endl;
    cout << "  musiclib-cli rate 4 \"/mnt/music/song.mp3\"              # Rate specific file" << Qt::endl;
    cout << "  musiclib-cli build --dry-run                           # Preview database rebuild" << Qt::endl;
    cout << "  musiclib-cli mobile upload workout.audpl               # Upload playlist to mobile" << Qt::endl;
    cout << "  musiclib-cli mobile refresh-audacious-only             # Sync all Audacious playlists" << Qt::endl;
    cout << "  musiclib-cli mobile status                             # Show mobile sync status" << Qt::endl;
    cout << "  musiclib-cli new-tracks \"Pink Floyd\"                  # Import new downloads for artist" << Qt::endl;
    cout << "  musiclib-cli tagclean process /mnt/music/album -r      # Clean tags recursively" << Qt::endl;
    cout << "  musiclib-cli tagrebuild \"/mnt/music/corrupted.mp3\"     # Repair tags from database" << Qt::endl;
    cout << "  musiclib-cli process-pending                           # Retry deferred operations" << Qt::endl;
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("musiclib-cli");
    QCoreApplication::setApplicationVersion("0.2.0");
    
    // Initialize command registry early so help can display available commands
    CommandHandler::registerCommands();
    
    QStringList args = QCoreApplication::arguments();
    
    // Remove program name (first argument)
    args.removeFirst();
    
    // Handle no arguments
    if (args.isEmpty()) {
        showGlobalHelp();
        return 1;
    }
    
    // Handle global options
    QString globalOption = args.first();
    
    if (globalOption == "-h" || globalOption == "--help") {
        showGlobalHelp();
        return 0;
    }
    
    if (globalOption == "-v" || globalOption == "--version") {
        showVersion();
        return 0;
    }
    
    if (globalOption == "--config") {
        if (args.size() < 2) {
            cerr << "Error: --config requires a path argument" << Qt::endl;
            return 1;
        }
        // Set config path environment variable for scripts
        qputenv("MUSICLIB_CONFIG", args.at(1).toUtf8());
        args.removeFirst(); // Remove --config
        args.removeFirst(); // Remove path
        
        if (args.isEmpty()) {
            cerr << "Error: No subcommand specified after --config" << Qt::endl;
            showGlobalHelp();
            return 1;
        }
    }
    
    // Extract subcommand
    QString subcommand = args.takeFirst();
    
    // Execute subcommand
    int exitCode = CommandHandler::executeCommand(subcommand, args);
    
    return exitCode;
}
