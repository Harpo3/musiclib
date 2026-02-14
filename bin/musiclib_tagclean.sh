#!/bin/bash
#
# musiclib_tagclean.sh - Clean and normalize MP3 tags
# Usage: musiclib_tagclean.sh [file/directory] [options]
#
# Modes:
#   merge (default): ID3v1->ID3v2, remove ID3v1/APE, embed art
#   strip: Remove ID3v1 and APE only
#   embed-art: Embed album art only
#

set -u
set -o pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$HOME/musiclib}"

# Load utilities and config
if ! source "$MUSICLIB_ROOT/bin/musiclib_utils.sh"; then
    echo '{"error":"Failed to load musiclib_utils.sh","script":"musiclib_tagclean.sh","code":2,"context":{},"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' >&2
    exit 2
fi

if ! load_config; then
    error_exit 2 "Configuration load failed"
    exit 2
fi

# Configuration (loaded from config file)
BACKUP_DIR="${TAG_BACKUP_DIR:-$MUSICLIB_ROOT/data/tag_backups}"
MAX_BACKUP_AGE="${MAX_BACKUP_AGE_DAYS:-30}"

# Check for required tools and output JSON error if missing
if ! check_required_tools kid3-cli; then
    error_exit 2 "Required tools not available" "missing" "kid3-cli"
    exit 2
fi

# Options
REMOVE_APE=false
REMOVE_RG=false
DRY_RUN=false
VERBOSE=false
RECURSIVE=false

# Operation modes: merge, strip, embed-art
# Legacy internal modes: full, art-only, ape-only, rg-only (for backward compatibility)
MODE="merge"  # Default mode
LEGACY_MODE_SET=false  # Track if legacy flag was used

# Statistics
TOTAL_PROCESSED=0
V1_MERGED=0
V1_REMOVED=0
APE_REMOVED=0
RG_REMOVED=0
ART_ADDED=0
ERRORS=0

#############################################
# Remove ReplayGain Tags
#############################################
remove_replaygain() {
    local filepath="$1"

    [ "$VERBOSE" = true ] && log_message "Removing ReplayGain tags from $(basename "$filepath")"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would remove ReplayGain tags"
        return 0
    fi

    # Remove ReplayGain from ID3v2 (Tag 2) using kid3-cli
    $KID3_CMD -c "select all" "$filepath" 2>/dev/null
    $KID3_CMD -c "tag 2" "$filepath" 2>/dev/null
    $KID3_CMD -c "set 'REPLAYGAIN_TRACK_GAIN' ''" "$filepath" 2>/dev/null
    $KID3_CMD -c "set 'REPLAYGAIN_TRACK_PEAK' ''" "$filepath" 2>/dev/null
    $KID3_CMD -c "set 'REPLAYGAIN_ALBUM_GAIN' ''" "$filepath" 2>/dev/null
    $KID3_CMD -c "set 'REPLAYGAIN_ALBUM_PEAK' ''" "$filepath" 2>/dev/null
    $KID3_CMD -c "set 'RVA2.track' ''" "$filepath" 2>/dev/null
    $KID3_CMD -c "set 'RVA2.album' ''" "$filepath" 2>/dev/null
    $KID3_CMD -c "save" "$filepath" 2>/dev/null

    return $?
}

#############################################
# Show Usage
#############################################
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [TARGET] [options]

Clean and normalize MP3 ID3 tags for musiclib compatibility.

Commands:
  help              Show this help message
  examples          Show common usage examples
  modes             Explain operation modes
  troubleshoot      Show troubleshooting tips
  process TARGET    Process MP3 file or directory (default if TARGET looks like a path)

Arguments:
  TARGET            MP3 file or directory to process

Options:
  -h, --help        Show this help
  -r, --recursive   Process directories recursively
  -a, --remove-ape  Remove APE tags (default: keep)
  -g, --remove-rg   Remove ReplayGain tags
  -n, --dry-run     Show what would be done without making changes
  -v, --verbose     Show detailed processing information
  -b, --backup-dir DIR  Custom backup directory (default: $BACKUP_DIR)
  --mode MODE       Operation mode: merge (default), strip, embed-art

  --art-only        Alias for --mode embed-art
  --ape-only        Only remove APE tags (legacy mode)
  --rg-only         Only remove ReplayGain tags (legacy mode)

Modes:
  merge             Merge ID3v1->ID3v2, remove ID3v1, optionally remove APE/RG, embed art
  strip             Remove ID3v1 and APE tags only (no art embedding)
  embed-art         Only embed album art from .jpg files

Examples:
  # Full cleanup with merge mode (default)
  $0 /mnt/music/album -r

  # Strip mode - remove tags only
  $0 /mnt/music/album -r --mode strip

  # Only embed album art
  $0 /mnt/music/album -r --mode embed-art

  # Merge mode with APE and ReplayGain removal
  $0 /mnt/music -r -a -g

  # Dry run to see what would happen
  $0 /mnt/music -r -n

  # Show more examples
  $0 examples

  # Understand operation modes
  $0 modes

  # Get help troubleshooting issues
  $0 troubleshoot

EOF
}

#############################################
# Show Extended Examples
#############################################
show_examples() {
    cat << EOF
=== MusicLib Tag Cleanup - Usage Examples ===

BASIC OPERATIONS:
  # Clean a single file (merge mode)
  $0 ~/Music/song.mp3

  # Clean all MP3s in a directory (non-recursive)
  $0 ~/Music/

  # Clean all MP3s recursively
  $0 ~/Music -r

DRY RUN (preview changes without modifying):
  # See what would be changed
  $0 ~/Music -r -n

  # See details of what would happen
  $0 ~/Music -r -n -v

MODE-SPECIFIC OPERATIONS:
  # Merge mode (default): merge ID3v1->v2, remove v1, embed art
  $0 ~/Music -r --mode merge

  # Strip mode: remove ID3v1 and APE only
  $0 ~/Music -r --mode strip

  # Embed-art mode: only embed missing album art
  $0 ~/Music -r --mode embed-art

LEGACY FLAG OPERATIONS (backward compatible):
  # Only embed missing album art (if .jpg exists in same directory)
  $0 ~/Music -r --art-only

  # Only remove APE tags (keep ID3 intact)
  $0 ~/Music -r --ape-only

  # Only remove ReplayGain metadata
  $0 ~/Music -r --rg-only

COMBINATION OPERATIONS:
  # Remove both APE and ReplayGain in merge mode
  $0 ~/Music -r -a -g

  # Strip mode with APE removal
  $0 ~/Music -r --mode strip -a

CUSTOM BACKUP LOCATION:
  # Use a custom backup directory
  $0 ~/Music -r -b /backup/music_tags

VERBOSE OUTPUT:
  # See detailed processing information
  $0 ~/Music -r -v

  # Combine verbose with dry-run for maximum visibility
  $0 ~/Music -r -n -v

WORKFLOW EXAMPLES:
  1. Preview before committing:
     $0 ~/Music -r -n -v
     [review output]
     $0 ~/Music -r    # commit changes

  2. Fix a specific album:
     $0 ~/Music/Artists/Beatles/Abbey_Road -r -a -g

  3. Just fix art and ReplayGain on everything:
     $0 ~/Music -r --mode embed-art
     $0 ~/Music -r --rg-only

For more information on operation modes, run:
  $0 modes

EOF
}

#############################################
# Show Operation Modes
#############################################
show_modes() {
    cat << EOF
=== MusicLib Tag Cleanup - Operation Modes ===

MERGE MODE (default):
  Performs comprehensive tag cleanup and normalization:
    1. Detect ID3v1 and ID3v2 tags
    2. Merge ID3v1 data into ID3v2 (if v2 exists but has gaps)
    3. Remove ID3v1 tag (after successful merge)
    4. Optionally remove APE tags (with -a flag)
    5. Optionally remove ReplayGain tags (with -g flag)
    6. Embed album art if missing (finds .jpg in same directory)

  Usage:
    $0 /path/to/music -r                  # Basic merge mode
    $0 /path/to/music -r --mode merge     # Explicit merge mode
    $0 /path/to/music -r -a               # Merge + remove APE
    $0 /path/to/music -r -a -g            # Merge + remove APE + remove ReplayGain

STRIP MODE:
  Removes ID3v1 and APE tags only, without embedding art:
    1. Detect ID3v1 and ID3v2 tags
    2. Merge ID3v1 data into ID3v2 (if v2 exists but has gaps)
    3. Remove ID3v1 tag (after successful merge)
    4. Remove APE tags (always, regardless of -a flag)
    5. NO album art embedding

  Useful when:
    - You want to clean legacy tags without modifying art
    - You're preparing files for a different art embedding tool
    - You want minimal changes to file structure

  Usage:
    $0 /path/to/music -r --mode strip

EMBED-ART MODE:
  Only processes album art embedding, no tag manipulation:
    1. Check if file already has embedded art
    2. If not, search for .jpg files in same directory
    3. Embed the best matching album art

  Useful when:
    - You've fixed tags elsewhere and just need art
    - You want to minimize risk by processing one thing at a time
    - You found album art files and want to embed them

  Usage:
    $0 /path/to/music -r --mode embed-art
    $0 /path/to/music -r --art-only       # Legacy alias

  Requirements:
    - .jpg files in same directory as MP3s (cover.jpg, album.jpg, etc.)

LEGACY MODES (backward compatible):
  --art-only    Alias for --mode embed-art
  --ape-only    Only remove APE tags (deprecated, use --mode strip)
  --rg-only     Only remove ReplayGain tags (can be combined with any mode)

CHOOSING A MODE:
  - Starting fresh with messy tags?      -> Use merge mode with -a and -g
  - Just need to clean legacy tags?      -> Use strip mode
  - Just need album art embedded?        -> Use embed-art mode
  - Need APE removal only?               -> Use --ape-only (legacy)
  - Need ReplayGain removal only?        -> Use --rg-only with any mode

EOF
}

#############################################
# Show Troubleshooting Tips
#############################################
show_troubleshoot() {
    cat << EOF
=== MusicLib Tag Cleanup - Troubleshooting ===

ISSUE: "kid3-cli not found"
  Cause: Required tool is not installed
  Solution:
    Ubuntu/Debian: sudo apt-get install kid3-cli
    Fedora/RHEL:   sudo dnf install kid3
    macOS:         brew install kid3

ISSUE: "exiftool not found"
  Cause: Required dependency missing
  Solution:
    Ubuntu/Debian: sudo apt-get install libimage-exiftool-perl
    Fedora/RHEL:   sudo dnf install perl-Image-ExifTool
    macOS:         brew install exiftool

ISSUE: Files are not changing (but no errors shown)
  Cause: Probably using dry-run mode (-n flag)
  Solution:
    Check if -n or --dry-run is in your command
    Remove that flag to actually make changes
    Example: $0 /path/to/music -r  (without -n)

ISSUE: Album art not being embedded
  Cause: No .jpg file found in the directory, or wrong mode
  Solution:
    1. Place a cover.jpg, album.jpg, or similar in the directory
    2. Ensure it's a JPEG file (.jpg or .jpeg extension)
    3. Make sure you're using merge or embed-art mode
    4. Try again with: $0 /path/to/music -r --mode embed-art

ISSUE: "Invalid mode" error
  Cause: Unsupported mode value provided
  Solution:
    Valid modes are: merge, strip, embed-art
    Example: $0 /path/to/music -r --mode merge

ISSUE: "Backup failed" or "restore from backup"
  Cause: Disk space issue or file permission problem
  Solution:
    1. Check available disk space: df -h
    2. Check directory permissions: ls -ld /path/to/music
    3. Specify a backup directory on a different drive:
       $0 /path/to/music -r -b /alternative/backup/path
    4. Try with a single file first to isolate the problem

ISSUE: Tags not merging from ID3v1 to ID3v2
  Cause: ID3v2 tag already contains the field
  Behavior: Merge only fills empty fields in v2 (doesn't overwrite)
  Solution:
    1. Check existing v2 tags manually:
       kid3-cli -c "select 2" /path/to/song.mp3
    2. Clear specific fields in v2 if needed
    3. Re-run the cleanup

ISSUE: ReplayGain tags not being removed
  Cause: Tags stored in different format (APE instead of ID3)
  Solution:
    Try removing APE tags first:
    $0 /path/to/music -r --ape-only
    Then remove ReplayGain:
    $0 /path/to/music -r --rg-only

ISSUE: Script is slow on large libraries
  Cause: Processing thousands of files with verbose output
  Solution:
    1. Omit -v (verbose) flag for faster processing
    2. Process in smaller batches (by artist or album)
    3. Use --mode embed-art, --ape-only, or --rg-only for specific tasks

GENERAL DEBUGGING:
  Use the --dry-run and --verbose flags together to see what would happen:
    $0 /path/to/music -r -n -v

  Review backups if something goes wrong:
    ls -lh $BACKUP_DIR

  Always start with a dry run on unfamiliar music directories:
    $0 /path/to/music -r -n -v

Need more help? Check the main help:
  $0 help

EOF
}

#############################################
# Parse Arguments with Command Dispatcher
#############################################
TARGET=""

# Extract command (first argument)
COMMAND="${1:-}"

# Handle command dispatcher
case "$COMMAND" in
    -h|--help|help)
        show_usage
        exit 0
        ;;
    examples)
        show_examples
        exit 0
        ;;
    modes)
        show_modes
        exit 0
        ;;
    troubleshoot)
        show_troubleshoot
        exit 0
        ;;
    process)
        # Explicit process command
        shift  # Remove 'process' from arguments
        if [ $# -lt 1 ]; then
            show_usage
            error_exit 1 "process command requires a TARGET"
            exit 1
        fi
        TARGET="$1"
        shift
        ;;
    *)
        # Backward compatibility: if first arg looks like a path, treat as TARGET
        # Check if it starts with / or . or ~ or contains /
        if [[ "$COMMAND" =~ ^(/|\.|\~) ]] || [[ "$COMMAND" =~ / ]]; then
            TARGET="$COMMAND"
            shift
        elif [ -n "$COMMAND" ]; then
            # It's neither a recognized command nor a path
            show_usage
            error_exit 1 "Unknown command or invalid target" "command" "$COMMAND"
            exit 1
        else
            # No arguments provided
            show_usage
            error_exit 1 "No command or target specified"
            exit 1
        fi
        ;;
esac

# Parse options for process/target
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -a|--remove-ape)
            REMOVE_APE=true
            shift
            ;;
        -g|--remove-rg)
            REMOVE_RG=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -b|--backup-dir)
            if [ $# -lt 2 ]; then
                show_usage
                error_exit 1 "-b/--backup-dir requires a directory argument" "option" "-b"
                exit 1
            fi
            BACKUP_DIR="$2"
            shift 2
            ;;
        --mode)
            if [ $# -lt 2 ]; then
                show_usage
                error_exit 1 "--mode requires a mode argument" "option" "--mode"
                exit 1
            fi
            # Validate mode value
            case "$2" in
                merge|strip|embed-art)
                    MODE="$2"
                    ;;
                *)
                    show_usage
                    error_exit 1 "Invalid mode - must be merge, strip, or embed-art" "provided" "$2"
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        --art-only)
            # Legacy flag: maps to embed-art mode
            MODE="embed-art"
            LEGACY_MODE_SET=true
            shift
            ;;
        --ape-only)
            # Legacy flag: special internal mode for APE removal only
            MODE="ape-only"
            REMOVE_APE=true
            LEGACY_MODE_SET=true
            shift
            ;;
        --rg-only)
            # Legacy flag: special internal mode for RG removal only
            MODE="rg-only"
            REMOVE_RG=true
            LEGACY_MODE_SET=true
            shift
            ;;
        -*)
            show_usage
            error_exit 1 "Unknown option" "option" "$1"
            exit 1
            ;;
        *)
            # Unexpected positional argument
            show_usage
            error_exit 1 "Unexpected argument" "argument" "$1"
            exit 1
            ;;
    esac
done

# Validate target
if [ -z "$TARGET" ]; then
    show_usage
    error_exit 1 "No target specified"
    exit 1
fi

if [ ! -e "$TARGET" ]; then
    error_exit 1 "Target not found" "target" "$TARGET"
    exit 1
fi

#############################################
# Validate Dependencies
#############################################
if ! validate_dependencies; then
    error_exit 2 "Dependencies validation failed"
    exit 2
fi

# Check for optional id3v2 tool
HAS_ID3V2=false
command -v id3v2 >/dev/null 2>&1 && HAS_ID3V2=true

#############################################
# Setup Backup Directory
#############################################
mkdir -p "$BACKUP_DIR"

#############################################
# Merge ID3v1 to ID3v2
#############################################
merge_v1_to_v2() {
    local filepath="$1"

    [ "$VERBOSE" = true ] && log_message "Merging ID3v1 -> ID3v2 for $(basename "$filepath")"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would merge ID3v1 data to ID3v2"
        return 0
    fi

    # Use kid3-cli to copy v1 to v2 where v2 is empty
    $KID3_CMD -c "select all" "$filepath" 2>/dev/null
    $KID3_CMD -c "copy" "$filepath" 2>/dev/null
    $KID3_CMD -c "select 2" "$filepath" 2>/dev/null  # Select ID3v2
    $KID3_CMD -c "paste" "$filepath" 2>/dev/null

    return $?
}

#############################################
# Remove ID3v1 Tag
#############################################
remove_id3v1() {
    local filepath="$1"

    [ "$VERBOSE" = true ] && log_message "Removing ID3v1 tag from $(basename "$filepath")"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would remove ID3v1 tag"
        return 0
    fi

    # Method 1: Use id3v2 if available (most reliable)
    if [ "$HAS_ID3V2" = true ]; then
        id3v2 --delete-v1 "$filepath" 2>/dev/null
        return $?
    fi

    # Method 2: Use kid3-cli
    $KID3_CMD -c "select 1" "$filepath" 2>/dev/null  # Select ID3v1
    $KID3_CMD -c "remove" "$filepath" 2>/dev/null

    return $?
}

#############################################
# Remove APE Tag
#############################################
remove_ape_tag() {
    local filepath="$1"

    [ "$VERBOSE" = true ] && log_message "Removing APE tag from $(basename "$filepath")"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would remove APE tag"
        return 0
    fi

    # Use kid3-cli to remove APE tags
    $KID3_CMD -c "select 3" "$filepath" 2>/dev/null  # Select APE (tag 3)
    $KID3_CMD -c "remove" "$filepath" 2>/dev/null

    return $?
}

#############################################
# Find Best Album Art File
#############################################
find_best_album_art() {
    local dirpath="$1"

    # Priority order for album art files
    local art_names=("cover.jpg" "folder.jpg" "album.jpg" "front.jpg" "Cover.jpg" "Folder.jpg")

    for art_name in "${art_names[@]}"; do
        if [ -f "$dirpath/$art_name" ]; then
            echo "$dirpath/$art_name"
            return 0
        fi
    done

    # Fallback: find any .jpg file
    local first_jpg=$(find "$dirpath" -maxdepth 1 -type f -iname "*.jpg" | head -n 1)
    if [ -n "$first_jpg" ]; then
        echo "$first_jpg"
        return 0
    fi

    return 1
}

#############################################
# Check if File Has Embedded Art
#############################################
has_embedded_art

#############################################
# Embed Album Art
#############################################
embed_album_art() {
    local filepath="$1"
    local art_file="$2"

    [ "$VERBOSE" = true ] && log_message "Embedding album art for $(basename "$filepath"): $(basename "$art_file")"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would embed: $(basename "$art_file")"
        return 0
    fi

    # Use kid3-cli to embed album art
    $KID3_CMD -c "select 2" "$filepath" 2>/dev/null  # Select ID3v2
    $KID3_CMD -c "set picture:'$art_file' ''" "$filepath" 2>/dev/null

    return $?
}

#############################################
# Process Single MP3 File
#############################################
process_file() {
    local filepath="$1"

    TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))

    echo "Processing: $(basename "$filepath")"

    # Check tag versions using utility function
    IFS=',' read -r has_v1 has_v2 has_ape <<< "$(get_tag_info "$filepath")"

    [ "$VERBOSE" = true ] && echo "  Tags present: v1=$has_v1, v2=$has_v2, ape=$has_ape"

    # Determine if we need to make changes based on mode
    local needs_changes=false

    case "$MODE" in
        merge)
            # Check if ID3v1 present
            if [ "$has_v1" = "true" ]; then
                needs_changes=true
            fi
            # Check if APE present and removal requested
            if [ "$has_ape" = "true" ] && [ "$REMOVE_APE" = true ]; then
                needs_changes=true
            fi
            # Check if ReplayGain removal requested
            if [ "$REMOVE_RG" = true ]; then
                needs_changes=true
            fi
            # Check if art embedding needed
            if ! has_embedded_art "$filepath"; then
                local dirpath=$(dirname "$filepath")
                local art_file=$(find_best_album_art "$dirpath")
                if [ -n "$art_file" ]; then
                    needs_changes=true
                fi
            fi
            ;;
        strip)
            # Check if ID3v1 present
            if [ "$has_v1" = "true" ]; then
                needs_changes=true
            fi
            # Always remove APE in strip mode
            if [ "$has_ape" = "true" ]; then
                needs_changes=true
            fi
            ;;
        embed-art)
            # Check if art embedding needed
            if ! has_embedded_art "$filepath"; then
                local dirpath=$(dirname "$filepath")
                local art_file=$(find_best_album_art "$dirpath")
                if [ -n "$art_file" ]; then
                    needs_changes=true
                fi
            fi
            ;;
        ape-only)
            # Legacy mode: only APE removal
            if [ "$has_ape" = "true" ]; then
                needs_changes=true
            fi
            ;;
        rg-only)
            # Legacy mode: only ReplayGain removal
            needs_changes=true
            ;;
    esac

    # Skip if no changes needed
    if [ "$needs_changes" = false ]; then
        [ "$VERBOSE" = true ] && echo "  No changes needed"
        return 0
    fi

    # Create backup using utility function
    local backup_file
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would create backup in $BACKUP_DIR"
        backup_file="[dry-run-backup]"
    else
        backup_file=$(backup_file "$filepath" "$BACKUP_DIR")
        if [ -z "$backup_file" ]; then
            echo "  Error: Failed to create backup" >&2
            error_exit 2 "Backup creation failed" "filepath" "$filepath"
            ERRORS=$((ERRORS + 1))
            return 1
        fi
    fi

    # Process based on mode
    case "$MODE" in
        merge)
            # Process ID3v1 if present
            if [ "$has_v1" = "true" ]; then
                if [ "$has_v2" = "true" ]; then
                    # Merge v1 -> v2
                    if ! merge_v1_to_v2 "$filepath"; then
                        echo "  Error: Failed to merge ID3v1" >&2
                        error_exit 2 "ID3v1 merge operation failed" "filepath" "$filepath"
                        if [ "$DRY_RUN" = false ]; then
                            mv "$backup_file" "$filepath" 2>/dev/null || true
                        fi
                        ERRORS=$((ERRORS + 1))
                        return 1
                    fi
                    V1_MERGED=$((V1_MERGED + 1))
                    [ "$VERBOSE" = true ] && echo "  ✓ Merged ID3v1 to ID3v2"
                fi

                # Remove v1
                if ! remove_id3v1 "$filepath"; then
                    echo "  Error: Failed to remove ID3v1" >&2
                    error_exit 2 "ID3v1 removal operation failed" "filepath" "$filepath"
                    if [ "$DRY_RUN" = false ]; then
                        mv "$backup_file" "$filepath" 2>/dev/null || true
                    fi
                    ERRORS=$((ERRORS + 1))
                    return 1
                fi
                V1_REMOVED=$((V1_REMOVED + 1))
                [ "$VERBOSE" = true ] && echo "  ✓ Removed ID3v1"
            fi

            # Remove APE if requested
            if [ "$has_ape" = "true" ] && [ "$REMOVE_APE" = true ]; then
                if ! remove_ape_tag "$filepath"; then
                    echo "  Error: Failed to remove APE tag" >&2
                    error_exit 2 "APE tag removal operation failed" "filepath" "$filepath"
                    if [ "$DRY_RUN" = false ]; then
                        mv "$backup_file" "$filepath" 2>/dev/null || true
                    fi
                    ERRORS=$((ERRORS + 1))
                    return 1
                fi
                APE_REMOVED=$((APE_REMOVED + 1))
                [ "$VERBOSE" = true ] && echo "  ✓ Removed APE tag"
            fi

            # Remove ReplayGain if requested
            if [ "$REMOVE_RG" = true ]; then
                if ! remove_replaygain "$filepath"; then
                    echo "  Error: Failed to remove ReplayGain tags" >&2
                    error_exit 2 "ReplayGain removal operation failed" "filepath" "$filepath"
                    if [ "$DRY_RUN" = false ]; then
                        mv "$backup_file" "$filepath" 2>/dev/null || true
                    fi
                    ERRORS=$((ERRORS + 1))
                    return 1
                fi
                RG_REMOVED=$((RG_REMOVED + 1))
                [ "$VERBOSE" = true ] && echo "  ✓ Removed ReplayGain tags"
            fi

            # Embed album art if missing
            if ! has_embedded_art "$filepath"; then
                local dirpath=$(dirname "$filepath")
                local art_file=$(find_best_album_art "$dirpath")

                if [ -n "$art_file" ]; then
                    if ! embed_album_art "$filepath" "$art_file"; then
                        echo "  Error: Failed to embed album art" >&2
                        error_exit 2 "Album art embedding operation failed" "filepath" "$filepath"
                        if [ "$DRY_RUN" = false ]; then
                            mv "$backup_file" "$filepath" 2>/dev/null || true
                        fi
                        ERRORS=$((ERRORS + 1))
                        return 1
                    fi
                    ART_ADDED=$((ART_ADDED + 1))
                    [ "$VERBOSE" = true ] && echo "  ✓ Embedded album art"
                fi
            fi
            ;;

        strip)
            # Process ID3v1 if present
            if [ "$has_v1" = "true" ]; then
                if [ "$has_v2" = "true" ]; then
                    # Merge v1 -> v2
                    if ! merge_v1_to_v2 "$filepath"; then
                        echo "  Error: Failed to merge ID3v1" >&2
                        error_exit 2 "ID3v1 merge operation failed" "filepath" "$filepath"
                        if [ "$DRY_RUN" = false ]; then
                            mv "$backup_file" "$filepath" 2>/dev/null || true
                        fi
                        ERRORS=$((ERRORS + 1))
                        return 1
                    fi
                    V1_MERGED=$((V1_MERGED + 1))
                    [ "$VERBOSE" = true ] && echo "  ✓ Merged ID3v1 to ID3v2"
                fi

                # Remove v1
                if ! remove_id3v1 "$filepath"; then
                    echo "  Error: Failed to remove ID3v1" >&2
                    error_exit 2 "ID3v1 removal operation failed" "filepath" "$filepath"
                    if [ "$DRY_RUN" = false ]; then
                        mv "$backup_file" "$filepath" 2>/dev/null || true
                    fi
                    ERRORS=$((ERRORS + 1))
                    return 1
                fi
                V1_REMOVED=$((V1_REMOVED + 1))
                [ "$VERBOSE" = true ] && echo "  ✓ Removed ID3v1"
            fi

            # Always remove APE in strip mode
            if [ "$has_ape" = "true" ]; then
                if ! remove_ape_tag "$filepath"; then
                    echo "  Error: Failed to remove APE tag" >&2
                    error_exit 2 "APE tag removal operation failed" "filepath" "$filepath"
                    if [ "$DRY_RUN" = false ]; then
                        mv "$backup_file" "$filepath" 2>/dev/null || true
                    fi
                    ERRORS=$((ERRORS + 1))
                    return 1
                fi
                APE_REMOVED=$((APE_REMOVED + 1))
                [ "$VERBOSE" = true ] && echo "  ✓ Removed APE tag"
            fi
            ;;

        embed-art)
            if ! has_embedded_art "$filepath"; then
                local dirpath=$(dirname "$filepath")
                local art_file=$(find_best_album_art "$dirpath")

                if [ -n "$art_file" ]; then
                    if ! embed_album_art "$filepath" "$art_file"; then
                        echo "  Error: Failed to embed album art" >&2
                        error_exit 2 "Album art embedding operation failed" "filepath" "$filepath"
                        if [ "$DRY_RUN" = false ]; then
                            mv "$backup_file" "$filepath" 2>/dev/null || true
                        fi
                        ERRORS=$((ERRORS + 1))
                        return 1
                    fi
                    ART_ADDED=$((ART_ADDED + 1))
                    [ "$VERBOSE" = true ] && echo "  ✓ Embedded album art"
                fi
            fi
            ;;

        ape-only)
            # Legacy mode: only APE removal
            if [ "$has_ape" = "true" ]; then
                if ! remove_ape_tag "$filepath"; then
                    echo "  Error: Failed to remove APE tag" >&2
                    error_exit 2 "APE tag removal operation failed" "filepath" "$filepath"
                    if [ "$DRY_RUN" = false ]; then
                        mv "$backup_file" "$filepath" 2>/dev/null || true
                    fi
                    ERRORS=$((ERRORS + 1))
                    return 1
                fi
                APE_REMOVED=$((APE_REMOVED + 1))
                [ "$VERBOSE" = true ] && echo "  ✓ Removed APE tag"
            fi
            ;;

        rg-only)
            # Legacy mode: only ReplayGain removal
            if ! remove_replaygain "$filepath"; then
                echo "  Error: Failed to remove ReplayGain tags" >&2
                error_exit 2 "ReplayGain removal operation failed" "filepath" "$filepath"
                if [ "$DRY_RUN" = false ]; then
                    mv "$backup_file" "$filepath" 2>/dev/null || true
                fi
                ERRORS=$((ERRORS + 1))
                return 1
            fi
            RG_REMOVED=$((RG_REMOVED + 1))
            [ "$VERBOSE" = true ] && echo "  ✓ Removed ReplayGain tags"
            ;;
    esac

    # Verify changes were successful
    if [ "$DRY_RUN" = false ]; then
        if [ -f "$filepath" ] && [ -s "$filepath" ]; then
            # File exists and has size - assume success
            remove_backup "$backup_file"
            echo "  ✓ Complete"
        else
            # Restore from backup
            echo "  Error: File corrupted, restoring from backup" >&2
            error_exit 2 "File corruption detected after tag operation" "filepath" "$filepath"
            mv "$backup_file" "$filepath"
            ERRORS=$((ERRORS + 1))
            return 1
        fi
    fi

    return 0
}

#############################################
# Process Directory
#############################################
process_directory() {
    local dirpath="$1"
    local find_opts="-maxdepth 1 -type f"
    while IFS= read -r mp3_file; do
        process_file "$mp3_file"
    done < <(find "$dirpath" $find_opts -iname "*.mp3" 2>/dev/null | sort)
}

#############################################
# Main Execution
#############################################

echo "=== MusicLib Tag Cleanup ==="
echo ""

# Cleanup old backups first using utility function
[ "$VERBOSE" = true ] && echo "Cleaning backups older than $MAX_BACKUP_AGE days..."
cleanup_old_files "$BACKUP_DIR" "*.mp3.backup.*" "$MAX_BACKUP_AGE"

# Process target
if [ -f "$TARGET" ]; then
    # Single file
    if [[ "$TARGET" =~ \.mp3$ ]] || [[ "$TARGET" =~ \.MP3$ ]]; then
        process_file "$TARGET"
    else
        error_exit 1 "Not an MP3 file" "target" "$TARGET"
        exit 1
    fi
elif [ -d "$TARGET" ]; then
    # Directory
    process_directory "$TARGET"
else
    error_exit 1 "Invalid target" "target" "$TARGET"
    exit 1
fi

# Summary
echo ""
echo "=== Summary ==="
echo "Mode: $MODE"
echo "Total files processed: $TOTAL_PROCESSED"

case "$MODE" in
    merge)
        echo "ID3v1 tags merged: $V1_MERGED"
        echo "ID3v1 tags removed: $V1_REMOVED"
        [ "$REMOVE_APE" = true ] && echo "APE tags removed: $APE_REMOVED"
        [ "$REMOVE_RG" = true ] && echo "ReplayGain tags removed: $RG_REMOVED"
        echo "Album art added: $ART_ADDED"
        ;;
    strip)
        echo "ID3v1 tags merged: $V1_MERGED"
        echo "ID3v1 tags removed: $V1_REMOVED"
        echo "APE tags removed: $APE_REMOVED"
        ;;
    embed-art)
        echo "Album art added: $ART_ADDED"
        ;;
    ape-only)
        echo "APE tags removed: $APE_REMOVED"
        ;;
    rg-only)
        echo "ReplayGain tags removed: $RG_REMOVED"
        ;;
esac

echo "Errors: $ERRORS"
echo ""
echo "Backup location: $BACKUP_DIR"
[ "$DRY_RUN" = true ] && echo ""
[ "$DRY_RUN" = true ] && echo "DRY RUN - No changes were made"

exit 0
