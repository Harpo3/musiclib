#!/bin/bash
#
# musiclib_baloo_sync.sh - Sync MusicLib GroupDesc ratings to Baloo extended attributes
# Usage: musiclib_baloo_sync.sh [--dry-run] [--verbose]
#
# Reads GroupDesc values from musiclib.dsv and writes the corresponding
# user.baloo.rating extended attribute to each audio file so that Dolphin's
# Rating column reflects the same star rating stored in MusicLib.
#
# Baloo uses a 0-10 integer scale for user.baloo.rating.
# MusicLib GroupDesc uses 0-5. Mapping: baloo = GroupDesc * 2.
#
#   GroupDesc 0 (unrated) -> Baloo 0
#   GroupDesc 1 (1 star)  -> Baloo 2
#   GroupDesc 2 (2 stars) -> Baloo 4
#   GroupDesc 3 (3 stars) -> Baloo 6
#   GroupDesc 4 (4 stars) -> Baloo 8
#   GroupDesc 5 (5 stars) -> Baloo 10
#
# Exit codes:
#   0 - Success (all files processed, or nothing to do)
#   1 - User error (invalid arguments)
#   2 - System error (missing dependencies, database not found)

export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! source "$SCRIPT_DIR/musiclib_utils.sh" 2>/dev/null; then
    echo '{"error":"musiclib_utils.sh not found","script":"musiclib_baloo_sync.sh","code":2,"context":{"expected_path":"'"$SCRIPT_DIR/musiclib_utils.sh"'"},"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' >&2
    exit 2
fi

if ! load_config 2>/dev/null; then
    error_exit 2 "Failed to load configuration"
fi

MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"

#############################################
# Parse Arguments
#############################################
DRY_RUN=false
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --verbose) VERBOSE=true ;;
        --help|-h)
            echo "Usage: musiclib_baloo_sync.sh [--dry-run] [--verbose]"
            echo ""
            echo "Syncs GroupDesc star ratings from musiclib.dsv to Baloo's"
            echo "user.baloo.rating extended attribute on each audio file."
            echo "Run this once to back-fill existing ratings so Dolphin"
            echo "displays the correct star rating in its Rating column."
            echo ""
            echo "Options:"
            echo "  --dry-run   Show what would be changed without writing anything"
            echo "  --verbose   Print a line for every file processed"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            error_exit 1 "Unknown argument" "argument" "$arg"
            ;;
    esac
done

#############################################
# Dependency Check
#############################################
if ! command -v setfattr >/dev/null 2>&1; then
    error_exit 2 "setfattr not found - install attr package (e.g. sudo pacman -S attr)" "missing" "setfattr"
fi

#############################################
# Validate Database
#############################################
if [ ! -f "$MUSICDB" ]; then
    error_exit 2 "Database file not found" "database" "$MUSICDB"
fi

#############################################
# Resolve Column Indices from Header
#############################################
header=$(head -1 "$MUSICDB")

songpath_col=$(echo "$header" | tr '^' '\n' | grep -nx "SongPath" | cut -d: -f1)
groupdesc_col=$(echo "$header" | tr '^' '\n' | grep -nx "GroupDesc" | cut -d: -f1)

if [ -z "$songpath_col" ] || [ -z "$groupdesc_col" ]; then
    error_exit 2 "Could not locate SongPath or GroupDesc column in database header" \
        "database" "$MUSICDB" \
        "songpath_col" "${songpath_col:-NOT FOUND}" \
        "groupdesc_col" "${groupdesc_col:-NOT FOUND}"
fi

echo "Database:    $MUSICDB"
echo "SongPath:    column $songpath_col"
echo "GroupDesc:   column $groupdesc_col"
[ "$DRY_RUN" = true ] && echo "Mode:        DRY RUN (no changes will be written)"
echo ""

#############################################
# Process Each Track
#############################################
count_total=0
count_set=0
count_skipped=0
count_missing=0
count_error=0

while IFS= read -r line; do
    # Skip header (already consumed) and blank lines
    [ -z "$line" ] && continue

    songpath=$(echo "$line" | cut -d'^' -f"$songpath_col")
    groupdesc=$(echo "$line" | cut -d'^' -f"$groupdesc_col" | tr -d '[:space:]')

    # Skip rows where path is empty (malformed row)
    [ -z "$songpath" ] && continue

    count_total=$((count_total + 1))

    # GroupDesc must be 0-5; treat anything else as unrated (0)
    if [[ ! "$groupdesc" =~ ^[0-5]$ ]]; then
        groupdesc=0
    fi

    # Compute Baloo rating (0-10 scale)
    baloo_rating=$((groupdesc * 2))

    # Skip files that don't exist on disk
    if [ ! -f "$songpath" ]; then
        count_missing=$((count_missing + 1))
        [ "$VERBOSE" = true ] && echo "  MISSING  $songpath"
        continue
    fi

    # Check existing value to avoid unnecessary writes
    existing=$(getfattr -n "user.baloo.rating" --only-values "$songpath" 2>/dev/null || echo "")

    if [ "$existing" = "$baloo_rating" ]; then
        count_skipped=$((count_skipped + 1))
        [ "$VERBOSE" = true ] && echo "  SKIP     $songpath  (already $baloo_rating)"
        continue
    fi

    if [ "$DRY_RUN" = true ]; then
        count_set=$((count_set + 1))
        [ "$VERBOSE" = true ] && echo "  WOULD SET  $songpath  ($existing -> $baloo_rating)"
        continue
    fi

    # Write the extended attribute
    if setfattr -n "user.baloo.rating" -v "$baloo_rating" "$songpath" 2>/dev/null; then
        count_set=$((count_set + 1))
        [ "$VERBOSE" = true ] && echo "  SET      $songpath  ($existing -> $baloo_rating)"
    else
        count_error=$((count_error + 1))
        echo "  ERROR    $songpath" >&2
    fi

done < <(tail -n +2 "$MUSICDB")

#############################################
# Summary
#############################################
echo "Done."
echo "  Tracks in database:  $count_total"
if [ "$DRY_RUN" = true ]; then
    echo "  Would update:        $count_set"
else
    echo "  Updated:             $count_set"
fi
echo "  Already current:     $count_skipped"
echo "  File not found:      $count_missing"
[ "$count_error" -gt 0 ] && echo "  Errors:              $count_error"

if [ "$DRY_RUN" = false ] && [ "$count_set" -gt 0 ]; then
    # Nudge Baloo to re-index the changed files so Dolphin picks up the new
    # attributes without waiting for the next scheduled sweep.
    if command -v balooctl >/dev/null 2>&1; then
        echo ""
        echo "Notifying Baloo indexer..."
        balooctl check >/dev/null 2>&1 || true
    fi
fi

if [ "$count_error" -gt 0 ]; then
    exit 2
fi

if command -v log_message >/dev/null 2>&1; then
    log_message "baloo_sync: updated=$count_set skipped=$count_skipped missing=$count_missing errors=$count_error dry_run=$DRY_RUN"
fi

exit 0
