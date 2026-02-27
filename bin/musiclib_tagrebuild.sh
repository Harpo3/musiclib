#!/bin/bash
#
# musiclib_tagrebuild.sh - Repair corrupted tags on database tracks
#
# This script repairs corrupted or malformed ID3 tags on MP3 files that are
# already in the MusicLib database. It uses rebuild_tag() from
# musiclib_utils_tag_functions.sh to restore tags from database values + preserved metadata.
#
# Usage:
#   musiclib_tagrebuild.sh /path/to/file.mp3              # Rebuild single file
#   musiclib_tagrebuild.sh /path/to/music -r              # Rebuild directory recursively
#   musiclib_tagrebuild.sh /path/to/music -r -n -v        # Preview with details
#
# Options:
#   -r, --recursive      Process directories recursively
#   -n, --dry-run        Preview changes without modifying files
#   -v, --verbose        Show detailed processing information
#   -b, --backup-dir DIR Custom backup directory
#   -h, --help           Show this help message
#

set -u
set -o pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$HOME/musiclib}"

# Load utilities and config
if ! source "$MUSICLIB_ROOT/bin/musiclib_utils.sh"; then
    # Can't use error_exit yet, utils not loaded
    {
        echo "{\"error\":\"Failed to load musiclib_utils.sh\",\"script\":\"$(basename "$0")\",\"code\":2,\"context\":{\"file\":\"$MUSICLIB_ROOT/bin/musiclib_utils.sh\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
    } >&2
    exit 2
fi

if ! load_config; then
    error_exit 2 "Configuration load failed" "config_file" "$MUSICLIB_ROOT/config/musiclib.conf"
    exit 2
fi

# Configuration
BACKUP_DIR="${TAG_BACKUP_DIR:-$MUSICLIB_ROOT/data/tag_backups}"
MAX_BACKUP_AGE="${MAX_BACKUP_AGE_DAYS:-30}"
DB_LOCK_TIMEOUT="${LOCK_TIMEOUT:-5}"

# Options
DRY_RUN=false
VERBOSE=false
RECURSIVE=false
TARGET=""

# Statistics
TOTAL_PROCESSED=0
TAGS_REBUILT=0
TAGS_SKIPPED=0
ERRORS=0

#############################################
# Show Usage
#############################################
show_usage() {
    cat << 'EOF'
Usage: musiclib-cli tagrebuild [TARGET] [options]

Repair corrupted or malformed ID3 tags on MP3 files in the MusicLib database.

This script identifies tracks that are in your musiclib.dsv database and repairs
their corrupted tags by extracting database-authoritative values (artist, album,
title, rating, etc.) and preserved non-database fields (ReplayGain, album art).

TARGET              MP3 file or directory to process

Options:
  -r, --recursive   Process directories recursively
  -n, --dry-run     Preview changes without modifying files
  -v, --verbose     Show detailed processing information
  -b, --backup-dir DIR  Custom backup directory
  -h, --help        Show this help message

Examples:
  # Repair a single file
  musiclib-cli tagrebuild ~/Music/song.mp3

  # Repair all files in a directory (not recursive)
  musiclib-cli tagrebuild ~/Music/

  # Repair all files recursively
  musiclib-cli tagrebuild ~/Music -r

  # Preview with verbose output
  musiclib-cli tagrebuild ~/Music -r -n -v

  # Actual rebuild after preview
  musiclib-cli tagrebuild ~/Music -r

Workflow:
  1. Preview changes first: musiclib-cli tagrebuild ~/Music -r -n -v
  2. Review the output
  3. Run without -n to apply: musiclib-cli tagrebuild ~/Music -r

Notes:
  - Only rebuilds files that are found in the database
  - Files not in the database are skipped (non-fatal)
  - Creates backups before any modifications
  - Requires musiclib_utils_tag_functions.sh with rebuild_tag() function
  - Uses database locking to ensure consistency during metadata reads

Exit Codes:
  0 - Success (all files processed without errors)
  1 - User error (invalid arguments, target not found)
  2 - System error (dependencies missing, database unavailable, tag rebuild failed)

EOF
}

#############################################
# Check if file is in database
#############################################
is_in_database() {
    local filepath="$1"

    if [ ! -f "$MUSICDB" ]; then
        [ "$VERBOSE" = true ] && echo "    Warning: Database not found"
        return 1
    fi

    # Search for file in database by exact filepath match
    if grep -qF "$filepath" "$MUSICDB" 2>/dev/null; then
        return 0
    fi

    return 1
}

#############################################
# Process Single MP3 File
#############################################
process_file() {
    local filepath="$1"

    TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))

    echo "Processing: $(basename "$filepath")"

    # Check if file is in database
    if ! is_in_database "$filepath"; then
        [ "$VERBOSE" = true ] && echo "  Track not found in database (skipping)"
        TAGS_SKIPPED=$((TAGS_SKIPPED + 1))
        return 0
    fi

    [ "$VERBOSE" = true ] && echo "  Found in database"

    # Create backup
    local backup_file
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would create backup in $BACKUP_DIR"
        backup_file="[dry-run-backup]"
    else
        backup_file=$(backup_file "$filepath" "$BACKUP_DIR")
        if [ -z "$backup_file" ]; then
            error_exit 2 "Failed to create backup" "filepath" "$filepath" "backup_dir" "$BACKUP_DIR"
            ERRORS=$((ERRORS + 1))
            return 1
        fi
        [ "$VERBOSE" = true ] && echo "  Backup created: $(basename "$backup_file")"
    fi

    # Rebuild tags with database lock
    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY-RUN] Would rebuild tags from database + preserved metadata"
        TAGS_REBUILT=$((TAGS_REBUILT + 1))
        return 0
    fi

    # Call rebuild_tag() with database lock to ensure consistency
    # The rebuild_tag() function reads from MUSICDB, so we need exclusive access
    if with_db_lock "$DB_LOCK_TIMEOUT" rebuild_tag "$filepath"; then
        TAGS_REBUILT=$((TAGS_REBUILT + 1))
        [ "$VERBOSE" = true ] && echo "  Tags rebuilt successfully"
        
        # Remove backup after successful rebuild
        remove_backup "$backup_file"
        echo "  Complete"
        return 0
    else
        rebuild_result=$?
        
        # Check if this was a lock timeout (from with_db_lock)
        if [ "$rebuild_result" -eq 1 ]; then
            error_exit 2 "Database lock timeout during tag rebuild" \
                "filepath" "$filepath" \
                "timeout_seconds" "$DB_LOCK_TIMEOUT" \
                "database" "$MUSICDB"
            echo "  Error: Database lock timeout" >&2
            mv "$backup_file" "$filepath" 2>/dev/null || true
            ERRORS=$((ERRORS + 1))
            return 1
        fi
        
        # Handle rebuild_tag() specific error codes
        case "$rebuild_result" in
            1)
                # Metadata extraction failed
                error_exit 2 "Metadata extraction failed during tag rebuild" \
                    "filepath" "$filepath" \
                    "stage" "extraction"
                echo "  Error: Could not extract metadata" >&2
                mv "$backup_file" "$filepath" 2>/dev/null || true
                ERRORS=$((ERRORS + 1))
                return 1
                ;;
            2)
                # Tag removal failed
                error_exit 2 "Failed to remove corrupted tags" \
                    "filepath" "$filepath" \
                    "stage" "removal"
                echo "  Error: Could not remove corrupted tags" >&2
                mv "$backup_file" "$filepath" 2>/dev/null || true
                ERRORS=$((ERRORS + 1))
                return 1
                ;;
            3)
                # Tag rebuild/write failed
                error_exit 2 "Tag rebuild write operation failed" \
                    "filepath" "$filepath" \
                    "stage" "rebuild"
                echo "  Error: Tag rebuild failed" >&2
                mv "$backup_file" "$filepath" 2>/dev/null || true
                ERRORS=$((ERRORS + 1))
                return 1
                ;;
            *)
                # Unknown error
                error_exit 2 "Unknown error during tag rebuild" \
                    "filepath" "$filepath" \
                    "rebuild_code" "$rebuild_result"
                echo "  Error: Unknown error (code $rebuild_result)" >&2
                mv "$backup_file" "$filepath" 2>/dev/null || true
                ERRORS=$((ERRORS + 1))
                return 1
                ;;
        esac
    fi
}

#############################################
# Process Directory
#############################################
process_directory() {
    local dirpath="$1"

    local find_opts="-maxdepth 1"
    if [ "$RECURSIVE" = true ]; then
        find_opts="-type f"
    fi

    while IFS= read -r mp3_file; do
        process_file "$mp3_file"
    done < <(find "$dirpath" $find_opts -iname "*.mp3" 2>/dev/null | sort)
}

#############################################
# Parse Arguments
#############################################
TARGET="${1:-}"

# Handle help early
if [ "$TARGET" = "-h" ] || [ "$TARGET" = "--help" ] || [ "$TARGET" = "help" ]; then
    show_usage
    exit 0
fi

# If no target, show usage
if [ -z "$TARGET" ]; then
    show_usage
    exit 1
fi

# Shift past TARGET and parse options
shift

while [ $# -gt 0 ]; do
    case "$1" in
        -r|--recursive)
            RECURSIVE=true
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
                error_exit 1 "Option -b/--backup-dir requires a directory argument" "option" "-b/--backup-dir"
                exit 1
            fi
            BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error_exit 1 "Unknown option" "option" "$1"
            exit 1
            ;;
    esac
done

#############################################
# Validate Target
#############################################
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

# Load tag functions
if ! declare -f rebuild_tag >/dev/null 2>&1; then
    if [ -f "$MUSICLIB_ROOT/bin/musiclib_utils_tag_functions.sh" ]; then
        if ! source "$MUSICLIB_ROOT/bin/musiclib_utils_tag_functions.sh"; then
            error_exit 2 "Failed to load tag functions" "file" "musiclib_utils_tag_functions.sh"
            exit 2
        fi
    else
        error_exit 2 "Tag functions file not found" "missing" "musiclib_utils_tag_functions.sh"
        exit 2
    fi
fi

#############################################
# Setup Backup Directory
#############################################
mkdir -p "$BACKUP_DIR"

#############################################
# Main Execution
#############################################

echo "=== MusicLib Tag Rebuild ==="
echo ""

# Cleanup old backups
if [ "$VERBOSE" = true ]; then
    echo "Cleaning backups older than $MAX_BACKUP_AGE days..."
fi
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

#############################################
# Summary
#############################################
echo ""
echo "=== Summary ==="
echo "Total files processed: $TOTAL_PROCESSED"
echo "Tags rebuilt: $TAGS_REBUILT"
echo "Skipped (not in DB): $TAGS_SKIPPED"
echo "Errors: $ERRORS"
echo ""
echo "Backup location: $BACKUP_DIR"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "DRY RUN - No changes were made"
fi

# Exit with appropriate code
if [ "$ERRORS" -gt 0 ]; then
    exit 2
fi

exit 0
