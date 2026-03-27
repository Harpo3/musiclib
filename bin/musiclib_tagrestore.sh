#!/bin/bash
#
# musiclib_tagrestore.sh - Restore MP3 tag backup created by tagrebuild or tagclean
#
# Locates the most recent backup for a given MP3 file in the tag_backups directory
# and copies it back over the original, undoing whatever tagrebuild or tagclean did.
#
# Backups are only present when --keep-backup was passed to musiclib_tagrebuild.sh or
# musiclib_tagclean.sh.  After a successful restore the backup file is retained so
# the user can restore again or clean up manually.
#
# Usage:
#   musiclib_tagrestore.sh <filepath.mp3>         # Restore most recent backup
#   musiclib_tagrestore.sh <filepath.mp3> -n      # Dry-run: show what would be restored
#   musiclib_tagrestore.sh <filepath.mp3> -v      # Verbose: list all available backups
#   musiclib_tagrestore.sh <filepath.mp3> -l      # List all backups without restoring
#
# Options:
#   -n, --dry-run    Preview the restore without overwriting the original
#   -v, --verbose    Show all available backups and extra detail
#   -l, --list       List all backups for the given file and exit (no restore)
#   -h, --help       Show this help message
#
# Exit Codes:
#   0  Restore successful (or dry-run completed)
#   1  No backup found, file path does not exist, or invalid arguments
#   2  Backup found but restore failed (copy error)
#

set -u
set -o pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load utilities and config
if ! source "$SCRIPT_DIR/musiclib_utils.sh" 2>/dev/null; then
    {
        echo "{\"error\":\"Failed to load musiclib_utils.sh\",\"script\":\"$(basename "$0")\",\"code\":2,\"context\":{\"file\":\"$SCRIPT_DIR/musiclib_utils.sh\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
    } >&2
    exit 2
fi

if ! load_config; then
    error_exit 2 "Configuration load failed"
    exit 2
fi

# Configuration
BACKUP_DIR="${TAG_BACKUP_DIR:-$(get_data_dir)/data/tag_backups}"

# Options
DRY_RUN=false
VERBOSE=false
LIST_ONLY=false
FILEPATH=""

#############################################
# Show Usage
#############################################
show_usage() {
    cat << 'EOF'
Usage: musiclib-cli tagrestore <FILE.mp3> [options]

Restore an MP3 file's tags from the most recent backup created by
musiclib_tagrebuild.sh or musiclib_tagclean.sh when run with --keep-backup.

FILE.mp3            Path to the MP3 file whose tags you want to restore.

Options:
  -n, --dry-run     Show what would be restored without overwriting the file
  -v, --verbose     List all available backups and show extra detail
  -l, --list        List all available backups and exit without restoring
  -h, --help        Show this help message

Notes:
  - The backup file is NOT removed after restore.  You can restore again from
    the same backup, or delete it manually.
  - Backups are only created when --keep-backup was passed to tagrebuild or
    tagclean.  If no backup exists this script exits with code 1.
  - Backup location: $(get_data_dir)/data/tag_backups/

Exit Codes:
  0  Restore successful (or dry-run/list completed successfully)
  1  No backup found, file does not exist, or invalid arguments
  2  Backup found but restore failed (copy error)

EOF
}

#############################################
# Parse Arguments
#############################################
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        -*)
            error_exit 1 "Unknown option" "option" "$1"
            exit 1
            ;;
        *)
            if [ -n "$FILEPATH" ]; then
                error_exit 1 "Only one file path may be specified" "extra_arg" "$1"
                exit 1
            fi
            FILEPATH="$1"
            shift
            ;;
    esac
done

#############################################
# Validate Input
#############################################
if [ -z "$FILEPATH" ]; then
    echo "Error: No file path specified." >&2
    echo ""
    show_usage
    exit 1
fi

if [ ! -f "$FILEPATH" ]; then
    error_exit 1 "File not found" "filepath" "$FILEPATH"
    exit 1
fi

if [[ ! "$FILEPATH" =~ \.[Mm][Pp]3$ ]]; then
    error_exit 1 "Not an MP3 file" "filepath" "$FILEPATH"
    exit 1
fi

#############################################
# Find Backups
#############################################
BASENAME="$(basename "$FILEPATH")"

# Backups are named: <basename>.backup.<YYYYMMDD_HHMMSS>
# Lexicographic sort on the timestamp suffix gives chronological order.
mapfile -t BACKUPS < <(
    find "$BACKUP_DIR" -maxdepth 1 -name "${BASENAME}.backup.*" -type f 2>/dev/null \
    | sort
)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo "No backup found for: $FILEPATH" >&2
    echo "(Backups are only retained when --keep-backup is passed to tagrebuild or tagclean.)" >&2
    exit 1
fi

# Most recent backup is the last entry after ascending sort
LATEST_BACKUP="${BACKUPS[-1]}"

#############################################
# List Mode
#############################################
if [ "$LIST_ONLY" = true ]; then
    echo "=== Tag Backups for: $BASENAME ==="
    echo ""
    local_count=${#BACKUPS[@]}
    for i in "${!BACKUPS[@]}"; do
        b="${BACKUPS[$i]}"
        bname="$(basename "$b")"
        bdate="$(stat -c %y "$b" 2>/dev/null | cut -d. -f1)"
        if [ "$i" -eq $((local_count - 1)) ]; then
            echo "  [MOST RECENT] $bname  ($bdate)"
        else
            echo "                $bname  ($bdate)"
        fi
    done
    echo ""
    echo "Total backups: $local_count"
    echo "Location: $BACKUP_DIR"
    exit 0
fi

#############################################
# Show What Will Happen
#############################################
echo "=== MusicLib Tag Restore ==="
echo ""
echo "File:            $FILEPATH"
echo "Most recent backup: $(basename "$LATEST_BACKUP")"

if [ "$VERBOSE" = true ] && [ ${#BACKUPS[@]} -gt 1 ]; then
    echo ""
    echo "All available backups (oldest → newest):"
    for b in "${BACKUPS[@]}"; do
        marker=""
        [ "$b" = "$LATEST_BACKUP" ] && marker="  ← will restore"
        echo "  $(basename "$b")${marker}"
    done
fi

echo ""

#############################################
# Dry-Run Exit Point
#############################################
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would restore: $(basename "$LATEST_BACKUP")"
    echo "[DRY-RUN] No changes made."
    exit 0
fi

#############################################
# Perform Restore
#############################################
if ! cp "$LATEST_BACKUP" "$FILEPATH"; then
    error_exit 2 "Restore failed: could not copy backup over original" \
        "source" "$LATEST_BACKUP" \
        "destination" "$FILEPATH"
    exit 2
fi

# Verify the copy succeeded
if ! cmp -s "$LATEST_BACKUP" "$FILEPATH"; then
    error_exit 2 "Restore verification failed: file contents do not match backup" \
        "source" "$LATEST_BACKUP" \
        "destination" "$FILEPATH"
    exit 2
fi

echo "Restored: $(basename "$FILEPATH")"
echo "  from backup: $(basename "$LATEST_BACKUP")"
echo ""
echo "Backup retained at: $LATEST_BACKUP"

exit 0
