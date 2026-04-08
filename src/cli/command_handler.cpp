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
    
    // Register: tagrestore
    commands_["tagrestore"] = {
        "tagrestore",
        "Restore MP3 tags from a backup created by tagrebuild or tagclean",
        "<FILE.mp3> [options]",
        "musiclib_tagrestore.sh",
        handleTagrestore
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

    // Register: boost
    commands_["boost"] = {
        "boost",
        "Apply ReplayGain loudness targeting to an album",
        "<ALBUM_DIR> <LOUDNESS>",
        "musiclib_boost.sh",
        handleBoost
    };

    // Register: smart-playlist
    commands_["smart-playlist"] = {
        "smart-playlist",
        "Analyze pool composition or generate a variety-optimized playlist",
        "analyze|generate [options]",
        "",
        handleSmartPlaylist
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
        cout << "  Use -b to create a backup before rebuilding." << Qt::endl;
        cout << Qt::endl;
        cout << "Notes:" << Qt::endl;
        cout << "  - Takes a long time to process for large libraries (10,000+ tracks)" << Qt::endl;
        cout << "  - Use --dry-run in a subdirectory first to preview changes safely" << Qt::endl;
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
    else if (cmd == "tagrestore") {
        cout << "Arguments:" << Qt::endl;
        cout << "  <FILE.mp3>  Path to the MP3 file whose tags you want to restore" << Qt::endl;
        cout << Qt::endl;
        cout << "Options:" << Qt::endl;
        cout << "  -n, --dry-run   Show what would be restored without writing" << Qt::endl;
        cout << "  -v, --verbose   List all available backups and show extra detail" << Qt::endl;
        cout << "  -l, --list      List all available backups and exit without restoring" << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Restores an MP3 file's tags from the most recent backup created by" << Qt::endl;
        cout << "  tagrebuild or tagclean when run with --keep-backup." << Qt::endl;
        cout << Qt::endl;
        cout << "Exit codes: 0=success, 1=no backup or bad args, 2=restore failed" << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli tagrestore \"/mnt/music/song.mp3\"" << Qt::endl;
        cout << "  musiclib-cli tagrestore \"/mnt/music/song.mp3\" --dry-run" << Qt::endl;
        cout << "  musiclib-cli tagrestore \"/mnt/music/song.mp3\" --list" << Qt::endl;
    }
    else if (cmd == "new-tracks") {
        cout << "Arguments:" << Qt::endl;
        cout << "  [artist_name]  Artist folder name (optional, prompts if omitted)" << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Imports new music downloads into the library and database." << Qt::endl;
        cout << "  Processes files from the download directory ($NEW_DOWNLOAD_DIR) by:" << Qt::endl;
        cout << "    1. Extracting ZIP files (if present)" << Qt::endl;
        cout << "    2. Pausing for tag editing in GUI (kid3, kid3-qt)" << Qt::endl;
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
    else if (cmd == "boost") {
        cout << "Arguments:" << Qt::endl;
        cout << "  <ALBUM_DIR>  Path to the directory containing the album's MP3 files" << Qt::endl;
        cout << "  <LOUDNESS>   Target loudness as a positive integer (e.g. 12 = -12 LUFS)." << Qt::endl;
        cout << "               Higher number = quieter; lower number = louder." << Qt::endl;
        cout << Qt::endl;
        cout << "Description:" << Qt::endl;
        cout << "  Removes existing ReplayGain tags from all .mp3 files in ALBUM_DIR," << Qt::endl;
        cout << "  then rescans with rsgain at the requested target loudness." << Qt::endl;
        cout << "  Only processes .mp3 files directly inside ALBUM_DIR (not recursive)." << Qt::endl;
        cout << "  Requires both kid3-cli and rsgain to be installed." << Qt::endl;
        cout << Qt::endl;
        cout << "  NOTE: pass a positive integer even though LUFS is normally shown as" << Qt::endl;
        cout << "  negative. To target -16 LUFS, pass 16." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli boost /mnt/music/pink_floyd/the_wall 12    # Target -12 LUFS" << Qt::endl;
        cout << "  musiclib-cli boost /mnt/music/radiohead/ok_computer 19  # Target -19 LUFS" << Qt::endl;
    }
    else if (cmd == "smart-playlist") {
        cout << "Subcommands:" << Qt::endl;
        cout << "  analyze [options]   Analyze the candidate pool and show per-group statistics." << Qt::endl;
        cout << "                      Reads musiclib.dsv, applies rating-group POPM filters and" << Qt::endl;
        cout << "                      last-played age thresholds, and computes variance weights." << Qt::endl;
        cout << "  generate [options]  Generate a variety-optimized M3U playlist." << Qt::endl;
        cout << "                      Delegates pool building to the analyze script, then runs" << Qt::endl;
        cout << "                      the variance-proportional selection loop with a rolling" << Qt::endl;
        cout << "                      artist-exclusion window." << Qt::endl;
        cout << Qt::endl;
        cout << "analyze options:" << Qt::endl;
        cout << "  -m counts|preview|file  Output mode (default: preview)" << Qt::endl;
        cout << "     counts   Per-group eligible track and unique artist counts only (fast)." << Qt::endl;
        cout << "     preview  Full analysis with variance totals and sample breakdown." << Qt::endl;
        cout << "     file     Write variance-annotated pool to sp_pool.csv." << Qt::endl;
        cout << "  -g G1,G2,G3,G4,G5  Age thresholds in days per rating group (1★–5★)." << Qt::endl;
        cout << "  -s <n>              Sample size for per-group breakdown. Default: from config." << Qt::endl;
        cout << "  -u L1,L2,L3,L4,L5  POPM low bounds per rating group." << Qt::endl;
        cout << "  -v H1,H2,H3,H4,H5  POPM high bounds per rating group." << Qt::endl;
        cout << "  -p <value>          Minimum POPM value to include." << Qt::endl;
        cout << "  -r <value>          Maximum POPM value to include." << Qt::endl;
        cout << Qt::endl;
        cout << "generate options:" << Qt::endl;
        cout << "  -n <name>           Playlist name (without .m3u extension). Default: \"Smart Playlist\"." << Qt::endl;
        cout << "  -o <file>           Full output file path (overrides -n and default directory)." << Qt::endl;
        cout << "  -p <n>              Target playlist size (number of tracks). Default: from config." << Qt::endl;
        cout << "  -s <n>              Sample size per selection round. Default: from config." << Qt::endl;
        cout << "  -e <n>              Recent unique artists to exclude per round. Default: from config." << Qt::endl;
        cout << "  -g G1,G2,G3,G4,G5  Age thresholds in days per rating group (1★–5★)." << Qt::endl;
        cout << "  -u L1,L2,L3,L4,L5  POPM low bounds per rating group." << Qt::endl;
        cout << "  -v H1,H2,H3,H4,H5  POPM high bounds per rating group." << Qt::endl;
        cout << "  --load-audacious    Load the generated playlist into Audacious after writing." << Qt::endl;
        cout << Qt::endl;
        cout << "Configuration:" << Qt::endl;
        cout << "  All threshold and size defaults are read from musiclib.conf (SP_AGE_GROUP*," << Qt::endl;
        cout << "  SP_PLAYLIST_SIZE, SP_SAMPLE_SIZE, SP_ARTIST_EXCLUSION_COUNT, RatingGroup1-5)." << Qt::endl;
        cout << Qt::endl;
        cout << "Examples:" << Qt::endl;
        cout << "  musiclib-cli smart-playlist analyze                         # Full preview with defaults" << Qt::endl;
        cout << "  musiclib-cli smart-playlist analyze -m counts               # Fast count check" << Qt::endl;
        cout << "  musiclib-cli smart-playlist analyze -g 720,360,180,90,45   # Preview custom thresholds" << Qt::endl;
        cout << "  musiclib-cli smart-playlist generate                        # Generate 50-track default playlist" << Qt::endl;
        cout << "  musiclib-cli smart-playlist generate --load-audacious       # Generate and load into Audacious" << Qt::endl;
        cout << "  musiclib-cli smart-playlist generate -p 100 -n \"Evening Mix\" -g 180,90,45,30,14" << Qt::endl;
        cout << "  musiclib-cli smart-playlist generate -o ~/Music/playlist.m3u" << Qt::endl;
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
    // 1 arg:  <rating>           - rates currently playing track (uses audtool)
    // 2 args: <rating> <filepath> - rates specific file
    
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
        // Two arguments: rating + filepath
        ratingStr = args[0];
        filepath = args[1];

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
    int exitCode = CLIUtils::executeScript("musiclib_build.sh", args,
                                           /*interactive=*/false, /*streamOutput=*/true);

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

int CommandHandler::handleTagrestore(const QStringList& args) {
    // Pass all arguments directly to musiclib_tagrestore.sh - the script handles its own
    // argument parsing and validation.
    // Supported: <FILE.mp3> [-n/--dry-run] [-v/--verbose] [-l/--list] [-h/--help]
    return CLIUtils::executeScript("musiclib_tagrestore.sh", args);
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
    //
    // interactive=true: this script uses read, clear, and prompts, so it
    // needs direct access to the terminal's stdin/stdout/stderr.
    return CLIUtils::executeScript("musiclib_init_config.sh", args,
                                   /*interactive=*/true);
}

int CommandHandler::handleSmartPlaylist(const QStringList& args) {
    if (args.isEmpty()) {
        cerr << "Error: 'smart-playlist' requires a subcommand (analyze or generate)" << Qt::endl;
        showHelp("smart-playlist");
        return 1;
    }

    QString subcommand = args[0];

    if (subcommand == "analyze") {
        // Pass remaining arguments directly to musiclib_smartplaylist_analyze.sh.
        // The script handles its own option parsing (-m, -g, -s, -u, -v, -p, -r, -d, -h).
        QStringList scriptArgs = args.mid(1);
        return CLIUtils::executeScript("musiclib_smartplaylist_analyze.sh", scriptArgs);
    }
    else if (subcommand == "generate") {
        // Pass remaining arguments directly to musiclib_smartplaylist.sh.
        // The script handles its own option parsing (-e, -g, -h, -n, -o, -p, -s, -u, -v,
        // and the long option --load-audacious).
        QStringList scriptArgs = args.mid(1);
        return CLIUtils::executeScript("musiclib_smartplaylist.sh", scriptArgs);
    }
    else {
        cerr << "Error: Unknown smart-playlist subcommand '" << subcommand << "'" << Qt::endl;
        cerr << "Valid subcommands: analyze, generate" << Qt::endl;
        return 1;
    }
}

int CommandHandler::handleBoost(const QStringList& args) {
    // Check that rsgain is available (as recorded by the setup wizard)
    QString rsgainInstalled = CLIUtils::readConfigValue("RSGAIN_INSTALLED");
    if (rsgainInstalled != "true") {
        cerr << "Error: The 'boost' command requires rsgain, which is not installed." << Qt::endl;
        cerr << "       Install rsgain and re-run 'musiclib-cli setup' to enable this feature." << Qt::endl;
        return 1;
    }

    // boost requires exactly 2 positional arguments: ALBUM_DIR and LOUDNESS
    if (args.size() != 2) {
        cerr << "Error: 'boost' requires exactly 2 arguments: ALBUM_DIR and LOUDNESS" << Qt::endl;
        showHelp("boost");
        return 1;
    }

    QString albumDir    = args[0];
    QString loudnessStr = args[1];

    // Validate directory exists
    if (!QFileInfo::exists(albumDir) || !QFileInfo(albumDir).isDir()) {
        cerr << "Error: Album directory not found: " << albumDir << Qt::endl;
        return 1;
    }

    // Validate loudness is a positive integer
    bool ok;
    int loudness = loudnessStr.toInt(&ok);
    if (!ok || loudness <= 0) {
        cerr << "Error: LOUDNESS must be a positive integer (e.g. 16 for -16 LUFS)" << Qt::endl;
        cerr << "       Do not pass a negative value." << Qt::endl;
        return 1;
    }

    return CLIUtils::executeScript("musiclib_boost.sh", args);
}
