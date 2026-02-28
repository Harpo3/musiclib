// command_handler.cpp - Command registry and routing implementation
// Phase 1, Task 2: Argument Parser Implementation

#include "command_handler.h"
#include "cli_utils.h"
#include "output_streams.h"
#include <QFileInfo>

// Static member initialization
QMap<QString, CommandInfo> CommandHandler::commands_;
bool CommandHandler::registered_ = false;

void CommandHandler::registerCommands() {
    if (registered_) {
        return; // Already registered
    }
    
    // Register: rate
    commands_["rate"] = {
        "rate",
        "Set star rating for a track (0-5 stars)",
        "<rating> [filepath]",
        "musiclib_rate.sh",
        handleRate
    };
    
    // Register: mobile
    commands_["mobile"] = {
        "mobile",
        "Mobile sync and Audacious playlist management",
        "upload|refresh-audacious-only|update-lastplayed|status|logs|cleanup [args...]",
        "musiclib_mobile.sh",
        handleMobile
    };
    
    // Register: build
    commands_["build"] = {
        "build",
        "Full database build/rebuild from filesystem scan",
        "[MUSIC_DIR] [options]",
        "musiclib_build.sh",
        handleBuild
    };

    // Register: tagclean
    commands_["tagclean"] = {
        "tagclean",
        "Clean and normalize audio file tags",
        "[COMMAND] [TARGET] [options]",
        "musiclib_tagclean.sh",
        handleTagclean
    };

    // Register: tagrebuild
    commands_["tagrebuild"] = {
        "tagrebuild",
        "Repair track tags from database values",
        "[TARGET] [options]",
        "musiclib_tagrebuild.sh",
        handleTagrebuild
    };
    
    // Register: new-tracks
    commands_["new-tracks"] = {
        "new-tracks",
        "Import new music downloads into library and database",
        "[artist_name]",
        "musiclib_new_tracks.sh",
        handleNewTracks
    };
    
    // Register: process-pending
    commands_["process-pending"] = {
        "process-pending",
        "Process deferred operations (queued ratings, etc.)",
        "",
        "musiclib_process_pending.sh",
        handleProcessPending
    };
    
    // Register: setup
    commands_["setup"] = {
        "setup",
        "Interactive first-run configuration wizard",
        "[--build-db]",
        "musiclib_init_config.sh",
        handleSetup
    };
    
    registered_ = true;
}

int CommandHandler::executeCommand(const QString& cmd, const QStringList& args) {
    if (!commands_.contains(cmd)) {
        cerr << "Error: Unknown subcommand '" << cmd << "'" << Qt::endl;
        cerr << Qt::endl;
        showAvailableCommands();
        cerr << Qt::endl;
        cerr << "Use 'musiclib-cli --help' for more information." << Qt::endl;
        return 1;
    }
    
    const CommandInfo& cmdInfo = commands_[cmd];
    
    // Check for subcommand help request
    // Note: "build" and "tagclean" pass --help through to the script (they have their own show_usage)
    if ((args.contains("-h") || args.contains("--help")) && cmd != "build" && cmd != "tagclean") {
        showHelp(cmd);
        return 0;
    }
    
    // Execute handler
    return cmdInfo.handler(args);
}

void CommandHandler::showHelp(const QString& cmd) {
    if (cmd.isEmpty()) {
        // This shouldn't be called directly - global help is in main.cpp
        showAvailableCommands();
        return;
    }
    
    if (!commands_.contains(cmd)) {
        cerr << "Error: Unknown command '" << cmd << "'" << Qt::endl;
        return;
    }
    
    const CommandInfo& cmdInfo = commands_[cmd];
    
    cout << "Usage: musiclib-cli " << cmdInfo.name << " " << cmdInfo.usage << Qt::endl;
    cout << Qt::endl;
    cout << cmdInfo.description << Qt::endl;
    cout << Qt::endl;
    
    // Subcommand-specific help details
    if (cmd == "rate") {
        cout << "Arguments:" << Qt::endl;
        cout << "  <rating>     Star rating (0-5, where 0 removes rating)" << Qt::endl;
        cout << "  [filepath]   Path to audio file (optional - uses currently playing track if omitted)" << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli rate 4                           # Rate currently playing track" << Qt::endl;
        cout << "  musiclib-cli rate 4 \"/mnt/music/song.mp3\"     # Rate specific file" << Qt::endl;
        cout << "  musiclib-cli rate 5 \"~/Music/track.flac\"      # Rate with expanded path" << Qt::endl;
    }
    else if (cmd == "mobile") {
        cout << "Subcommands:" << Qt::endl;
        cout << "  upload <playlist> [device-id]  Upload playlist to mobile device" << Qt::endl;
        cout << "                                 Checks if Audacious version is newer and offers to refresh" << Qt::endl;
        cout << "  refresh-audacious-only         Refresh all playlists from Audacious to Musiclib" << Qt::endl;
        cout << "                                 No mobile upload is performed" << Qt::endl;
        cout << "  update-lastplayed <playlist>   Update last-played times for a playlist" << Qt::endl;
        cout << "  status                         Show current mobile playlist status" << Qt::endl;
        cout << "  logs [filter]                  View mobile operations log" << Qt::endl;
        cout << "                                 Filters: errors, warnings, stats, today" << Qt::endl;
        cout << "  cleanup                        Remove orphaned metadata files" << Qt::endl;
        cout << Qt::endl;
        cout << "Configuration:" << Qt::endl;
        cout << "  AUDACIOUS_PLAYLISTS_DIR - Audacious playlists location" << Qt::endl;
        cout << "                            (default: ~/.config/audacious/playlists)" << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli mobile upload workout.audpl" << Qt::endl;
        cout << "  musiclib-cli mobile upload \"/path/to/playlist.audpl\" abc123" << Qt::endl;
        cout << "  musiclib-cli mobile refresh-audacious-only" << Qt::endl;
        cout << "  musiclib-cli mobile status" << Qt::endl;
        cout << "  musiclib-cli mobile logs errors" << Qt::endl;
        cout << "  musiclib-cli mobile cleanup" << Qt::endl;
    }
    else if (cmd == "build") {
        cout << "Options:" << Qt::endl;
        cout << "  --dry-run   Preview changes without modifying database" << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Scans the music repository and builds/rebuilds the database." << Qt::endl;
        cout << "  Preserves existing ratings when possible (matches by filepath)." << Qt::endl;
        cout << "  Creates automatic backup before making changes." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli build --dry-run   # Preview changes" << Qt::endl;
        cout << "  musiclib-cli build             # Execute build/rebuild" << Qt::endl;
    }
    else if (cmd == "tagclean") {
        cout << "Subcommands:" << Qt::endl;
        cout << "  preview <target>   Preview tag cleaning changes" << Qt::endl;
        cout << "  process <target>   Execute tag cleaning" << Qt::endl;
        cout << Qt::endl;
        cout << "Options:" << Qt::endl;
        cout << "  -r, --recursive    Process directories recursively" << Qt::endl;
        cout << "  --mode <mode>      Cleaning mode: merge|strip|embed-art" << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli tagclean preview /mnt/music/album/" << Qt::endl;
        cout << "  musiclib-cli tagclean process /mnt/music/ --recursive" << Qt::endl;
    }
    else if (cmd == "tagrebuild") {
        cout << "Arguments:" << Qt::endl;
        cout << "  <filepath>  Path to audio file to repair" << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Repairs track metadata by copying values from database back to file tags." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli tagrebuild \"/mnt/music/corrupted.mp3\"" << Qt::endl;
    }
    else if (cmd == "new-tracks") {
        cout << "Arguments:" << Qt::endl;
        cout << "  [artist_name]  Artist folder name (optional, prompts if omitted)" << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Imports new music downloads into the library and database." << Qt::endl;
        cout << "  Processes files from the download directory ($NEW_DOWNLOAD_DIR) by:" << Qt::endl;
        cout << "    1. Extracting ZIP files (if present)" << Qt::endl;
        cout << "    2. Pausing for tag editing in kid3-qt" << Qt::endl;
        cout << "    3. Normalizing MP3 filenames from ID3 tags" << Qt::endl;
        cout << "    4. Standardizing volume levels with rsgain" << Qt::endl;
        cout << "    5. Organizing files into artist/album folder structure" << Qt::endl;
        cout << "    6. Adding tracks to the musiclib.dsv database" << Qt::endl;
        cout << Qt::endl;
        cout << "  IMPORTANT: Check the album tag during the pause - it determines" << Qt::endl;
        cout << "  the folder name in the repository." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli new-tracks                    # Prompts for artist name" << Qt::endl;
        cout << "  musiclib-cli new-tracks \"Pink Floyd\"       # Imports as pink_floyd" << Qt::endl;
        cout << "  musiclib-cli new-tracks \"the_beatles\"      # Imports as the_beatles" << Qt::endl;
    }
    else if (cmd == "process-pending") {
        cout << "Description:" << Qt::endl;
        cout << "  Processes operations that were deferred due to database lock contention." << Qt::endl;
        cout << "  This includes queued rating changes and other pending updates." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli process-pending" << Qt::endl;
    }
    else if (cmd == "setup") {
        cout << "Options:" << Qt::endl;
        cout << "  --build-db    Build initial database after setup completes" << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Interactive wizard for first-run configuration. This wizard will:" << Qt::endl;
        cout << "    1. Detect Audacious installation" << Qt::endl;
        cout << "    2. Locate your music repository" << Qt::endl;
        cout << "    3. Configure download directories" << Qt::endl;
        cout << "    4. Create XDG directory structure" << Qt::endl;
        cout << "    5. Optionally build initial database" << Qt::endl;
        cout << "    6. Generate/update configuration file" << Qt::endl;
        cout << Qt::endl;
        cout << "  The wizard can be run multiple times to update configuration." << Qt::endl;
        cout << "  It will read existing settings as defaults." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli setup              # First-time setup" << Qt::endl;
        cout << "  musiclib-cli setup --build-db   # Setup and immediately build database" << Qt::endl;
    }
}

void CommandHandler::showAvailableCommands() {
    for (const CommandInfo& cmd : commands_) {
        cout << "  " << cmd.name.leftJustified(18) << cmd.description << Qt::endl;
    }
}

// ============================================================================
// Command Handlers
// ============================================================================

int CommandHandler::handleRate(const QStringList& args) {
    // Rate accepts either 1 or 2 arguments:
    // 1 arg:  <rating> - rates currently playing track (uses audtool)
    // 2 args: <filepath> <rating> - rates specific file
    
    if (args.size() != 1 && args.size() != 2) {
        cerr << "Error: 'rate' requires 1 or 2 arguments" << Qt::endl;
        showHelp("rate");
        return 1;
    }
    
    QString ratingStr;
    QString filepath;
    
    if (args.size() == 1) {
        // Single argument: rating only (current track)
        ratingStr = args[0];
        // Script will use audtool to get current track
    } else {
        // Two arguments: filepath + rating
        filepath = args[0];
        ratingStr = args[1];
        
        // Validate file exists
        if (!QFileInfo::exists(filepath)) {
            cerr << "Error: File not found: " << filepath << Qt::endl;
            return 1;
        }
    }
    
    // Validate rating is 0-5
    bool ok;
    int rating = ratingStr.toInt(&ok);
    if (!ok || rating < 0 || rating > 5) {
        cerr << "Error: Rating must be an integer between 0 and 5" << Qt::endl;
        return 1;
    }
    
    // Build script arguments
    QStringList scriptArgs;
    scriptArgs << ratingStr;  // Rating is always first for the script
    if (!filepath.isEmpty()) {
        scriptArgs << filepath;  // Add filepath if provided
    }
    
    return CLIUtils::executeScript("musiclib_rate.sh", scriptArgs);
}

int CommandHandler::handleMobile(const QStringList& args) {
    if (args.isEmpty()) {
        cerr << "Error: 'mobile' requires a subcommand" << Qt::endl;
        cerr << "Valid subcommands: upload, refresh-audacious-only, update-lastplayed, status, logs, cleanup" << Qt::endl;
        showHelp("mobile");
        return 1;
    }
    
    // Validate known subcommands for better error messages
    QString subcommand = args[0];
    QStringList validSubcommands = {"upload", "refresh-audacious-only", "update-lastplayed", "status", "logs", "cleanup", "check-update", "retry"};
    
    if (!validSubcommands.contains(subcommand)) {
        cerr << "Error: Unknown mobile subcommand '" << subcommand << "'" << Qt::endl;
        cerr << "Valid subcommands: " << validSubcommands.join(", ") << Qt::endl;
        return 1;
    }
    
    // Pass all arguments to script (it has its own subcommand parsing)
    return CLIUtils::executeScript("musiclib_mobile.sh", args);
}

int CommandHandler::handleBuild(const QStringList& args) {
    // Pass all arguments directly to musiclib_build.sh - the script handles its own
    // argument parsing and validation, so no whitelist is needed here.
    // Supported flags (see musiclib_build.sh show_usage):
    //   [MUSIC_DIR]  -h/--help  -d/--dry-run  -o FILE  -m DEPTH  --no-header
    //   -q/--quiet   -s COLUMN  -b/--backup   -t/--test  --no-progress
    int exitCode = CLIUtils::executeScript("musiclib_build.sh", args);

    // Exit code 1 from --dry-run / -d is informational (preview complete), not an error
    if (exitCode == 1 && (args.contains("--dry-run") || args.contains("-d"))) {
        return 0;
    }

    return exitCode;
}

int CommandHandler::handleTagclean(const QStringList& args) {
    // Pass all arguments directly to musiclib_tagclean.sh - the script handles its own
    // argument parsing and validation.
    // Supported: [COMMAND] [TARGET] [-r] [-a] [-g] [-n] [-v] [-b DIR] [--mode MODE]
    //            [--art-only] [--ape-only] [--rg-only]
    //            Commands: help, examples, modes, troubleshoot, preview, process
    return CLIUtils::executeScript("musiclib_tagclean.sh", args);
}

int CommandHandler::handleTagrebuild(const QStringList& args) {
    // Pass all arguments directly to musiclib_tagrebuild.sh - the script handles its own
    // argument parsing and validation.
    // Supported: [TARGET] [-r] [-n] [-v] [-b DIR] [-h/--help]
    return CLIUtils::executeScript("musiclib_tagrebuild.sh", args);
}

int CommandHandler::handleNewTracks(const QStringList& args) {
    // new-tracks accepts 0 or 1 argument:
    // 0 args: script will prompt for artist name
    // 1 arg:  artist name provided
    
    if (args.size() > 1) {
        cerr << "Error: 'new-tracks' accepts at most 1 argument (artist name)" << Qt::endl;
        showHelp("new-tracks");
        return 1;
    }
    
    // Pass arguments directly to script (it handles prompting if no artist provided)
    return CLIUtils::executeScript("musiclib_new_tracks.sh", args);
}

int CommandHandler::handleProcessPending(const QStringList& args) {
    // This command takes no arguments
    if (!args.isEmpty()) {
        cerr << "Warning: 'process-pending' ignores arguments" << Qt::endl;
    }
    
    return CLIUtils::executeScript("musiclib_process_pending.sh", {});
}

int CommandHandler::handleSetup(const QStringList& args) {
    // Pass all arguments directly to musiclib_init_config.sh - the script handles its own
    // argument parsing and validation.
    // Supported: [--build-db] [-h/--help]
    return CLIUtils::executeScript("musiclib_init_config.sh", args);
}
