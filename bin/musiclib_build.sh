#!/bin/bash
#
# musiclib_build.sh - Rebuild entire music library database from scratch
# Based on the musicbase concept but integrated with musiclib system
# Usage: musiclib_build.sh [music_directory] [options]
#
# Backend API v1.0 compliant:
#   Exit 0: Success
#   Exit 1: Dry-run complete (informational) or user error
#   Exit 2: System failures (missing directory, tools, lock timeout, scan failure)
#

set -u
set -o pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source utilities if available
if [ -f "$SCRIPT_DIR/musiclib_utils.sh" ]; then
    source "$SCRIPT_DIR/musiclib_utils.sh"
    load_config 2>/dev/null || true
fi

# Fallback configuration
MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"
MUSIC_ROOT_DIR="${MUSIC_ROOT_DIR:-/mnt/music}"
ERROR_LOG="${ERROR_LOG:-${LOGFILE:-$(get_data_dir)/logs/musiclib.log}}"

# Default settings
MIN_DEPTH=1
NO_HEADER=false
QUIET=false
SORT_COLUMN=""
OUTPUT_FILE="$MUSICDB"
TEMP_OUTPUT=""
DRY_RUN=false
SHOW_PROGRESS=true
RESTORE_LASTPLAYED=false

# Default header matching current musiclib.dsv format
DEFAULT_HEADER="ID^Artist^IDAlbum^Album^AlbumArtist^SongTitle^SongPath^Genre^SongLength^Rating^Custom2^GroupDesc^LastTimePlayed^^"

# Kid3 format codes for export
# Note: We'll generate IDs and IDAlbum ourselves
DEFAULT_FORMAT="%{artist}^%{album}^%{albumartist}^%{title}^%{filepath}^%{genre}^%{seconds}000^%{rating}^%{comment}^%{work}^0.000000^^"

#############################################
# Show Usage
#############################################
show_usage() {
    cat << EOF
Usage: musiclib-cli build [MUSIC_DIR] [options]

Rebuild the entire music library database from audio file tags.

Arguments:
  MUSIC_DIR         Root directory of music library (default: $MUSIC_ROOT_DIR)

Options:
  -h, --help        Display this help
  -d, --dry-run     Preview mode - show what would be processed without changes
  -o FILE           Output file path (default: $OUTPUT_FILE)
  -m DEPTH          Minimum subdirectory depth from root (default: 1)
  --no-header       Suppress database header in output
  -q, --quiet       Quiet mode - minimal output
  -s COLUMN         Sort output by column number
  -b, --backup      Create backup of existing database
  -t, --test        Test mode - output to temporary file
  --no-progress     Disable progress indicators
  --restore-lastplayed
                    Read LastTimePlayed from each file's Songs-DB_Custom1 tag
                    via kid3-cli.  Use when rebuilding an existing library so
                    play history is preserved.  Adds one kid3-cli call per
                    file; omit for faster builds on new libraries.

Examples:
  # Preview what would be rebuilt
  musiclib-cli build /mnt/music --dry-run

  # Rebuild entire database (new library — no play history)
  musiclib-cli build /mnt/music

  # Rebuild with backup and include restoring play history
  musiclib-cli build /mnt/music -b --restore-lastplayed

  # Test on subdirectory
  musiclib-cli build /mnt/music/Rock -t

  # Custom output location
  musiclib-cli build /mnt/music -o ~/music_backup.dsv

Exit Codes:
  0 - Success
  1 - Dry-run complete (informational) or user error (invalid arguments)
  2 - System failure (missing directory, tools unavailable, lock timeout, scan failure)

Notes:
  - This will REPLACE the existing database unless -t or --dry-run is used
  - Album IDs (IDAlbum) will be regenerated
  - Track IDs will be sequential starting from 1
  - LastTimePlayed defaults to 0; use --restore-lastplayed to read from file tags
  - Takes a long time to process for large libraries (10,000+ tracks)
  - Use --dry-run in a subdirectory first to preview changes safely

EOF
}

#############################################
# Parse Arguments
#############################################
MUSIC_DIR=""
TEST_MODE=false
CREATE_BACKUP=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -o|--output)
            if [ -z "${2:-}" ]; then
                error_exit 1 "Option -o/--output requires an argument" "option" "-o"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -m|--min-depth)
            if [ -z "${2:-}" ]; then
                error_exit 1 "Option -m/--min-depth requires an argument" "option" "-m"
                exit 1
            fi
            MIN_DEPTH="$2"
            shift 2
            ;;
        --no-header)
            NO_HEADER=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -s|--sort)
            if [ -z "${2:-}" ]; then
                error_exit 1 "Option -s/--sort requires an argument" "option" "-s"
                exit 1
            fi
            SORT_COLUMN="$2"
            shift 2
            ;;
        -b|--backup)
            CREATE_BACKUP=true
            shift
            ;;
        -t|--test)
            TEST_MODE=true
            OUTPUT_FILE="/tmp/musiclib_test_$(date +%Y%m%d_%H%M%S).dsv"
            shift
            ;;
        --no-progress)
            SHOW_PROGRESS=false
            shift
            ;;
        --restore-lastplayed)
            RESTORE_LASTPLAYED=true
            shift
            ;;
        -*)
            show_usage
            error_exit 1 "Unknown option" "option" "$1"
            exit 1
            ;;
        *)
            if [ -z "$MUSIC_DIR" ]; then
                MUSIC_DIR="$1"
            else
                show_usage
                error_exit 1 "Multiple directories specified" "provided" "$*"
                exit 1
            fi
            shift
            ;;
    esac
done

# Use default if not specified
if [ -z "$MUSIC_DIR" ]; then
    MUSIC_DIR="$MUSIC_ROOT_DIR"
fi

# Validate music directory
if [ ! -d "$MUSIC_DIR" ]; then
    error_exit 2 "Music directory not found" "directory" "$MUSIC_DIR"
    exit 2
fi

#############################################
# Validate Required Tools
#############################################
if ! check_required_tools kid3-cli exiftool; then
    error_exit 2 "Required tools not available" "missing" "kid3-cli or exiftool"
    exit 2
fi

#############################################
# exiftool stay_open Daemon
# Keeps one Perl process alive for the entire
# build run, eliminating per-file startup
# overhead (~100 ms saved per file).
#############################################
start_exiftool_daemon() {
    # bash coproc gives us bidirectional pipes to exiftool's stdin/stdout
    coproc EXIFTOOL_COPROC { exec exiftool -stay_open True -@ - 2>/dev/null; }

    # Immediately dup coproc FDs to dedicated numbers (7=read, 8=write)
    # so they survive any bash coproc housekeeping or FD shuffling.
    exec 7<&"${EXIFTOOL_COPROC[0]}" 8>&"${EXIFTOOL_COPROC[1]}"
    ET_DAEMON_PID=$EXIFTOOL_COPROC_PID

    [ "$QUIET" = false ] && echo "exiftool daemon started (PID $ET_DAEMON_PID)"
}

stop_exiftool_daemon() {
    if [[ -v ET_DAEMON_PID ]] && kill -0 "$ET_DAEMON_PID" 2>/dev/null; then
        printf '%s\n' '-stay_open' 'False' >&8 2>/dev/null || true
        exec 8>&- 2>/dev/null || true
        wait "$ET_DAEMON_PID" 2>/dev/null || true
    fi
    exec 7<&- 2>/dev/null || true
}

# Query a single file via the daemon.  Sets global ET_* variables.
# Uses exiftool -s output (padded "TagName : Value" lines) so that
# missing tags simply produce no line and grep returns empty string.
# A 30-second read timeout guards against daemon hangs.
query_exiftool_daemon() {
    local filepath="$1"
    local raw="" line

    # Send tag request + filepath, then -execute to trigger processing.
    # The filepath MUST come before -execute (exiftool's stay_open mode
    # treats -execute as "process everything accumulated so far").
    printf '%s\n' \
        '-Artist' '-Album' '-AlbumArtist' '-Title' '-Genre' \
        '-Duration' '-Popularimeter' '-Grouping' '-Comment' \
        '-Comment-xxx' '-Songs-DB_Custom2' \
        '-s' \
        "$filepath" \
        '-execute' >&8

    while IFS= read -r -t 30 -u 7 line; do
        [[ "$line" == "{ready}" ]] && break
        raw+="$line"$'\n'
    done

    # Extract each tag by name; missing tags yield empty strings
    ET_ARTIST=$(printf '%s'      "$raw" | grep -m1 '^Artist'           | sed 's/^[^:]*:[[:space:]]*//')
    ET_ALBUM=$(printf '%s'       "$raw" | grep -m1 '^Album[[:space:]]' | sed 's/^[^:]*:[[:space:]]*//')
    ET_ALBUMARTIST=$(printf '%s' "$raw" | grep -m1 '^AlbumArtist'      | sed 's/^[^:]*:[[:space:]]*//')
    ET_TITLE=$(printf '%s'       "$raw" | grep -m1 '^Title'            | sed 's/^[^:]*:[[:space:]]*//')
    ET_GENRE=$(printf '%s'       "$raw" | grep -m1 '^Genre'            | sed 's/^[^:]*:[[:space:]]*//')
    ET_DURATION=$(printf '%s'    "$raw" | grep -m1 '^Duration'         | sed 's/^[^:]*:[[:space:]]*//')
    ET_POPM=$(printf '%s'        "$raw" | grep -m1 '^Popularimeter'    | sed 's/^[^:]*:[[:space:]]*//')
    ET_GROUPDESC=$(printf '%s'      "$raw" | grep -m1 '^Grouping'              | sed 's/^[^:]*:[[:space:]]*//')
    # ET_CUSTOM2_TXXX: dedicated TXXX frame "Songs-DB_Custom2" (kid3-cli
    # canonical format).  Authoritative — takes priority over COMM fallback.
    ET_CUSTOM2_TXXX=$(printf '%s'   "$raw" | grep -m1 '^Songs-DB_Custom2'     | sed 's/^[^:]*:[[:space:]]*//')
    # ET_COMMENT_C2: any COMM frame (plain or language-coded, e.g. Comment-xxx)
    # whose value begins with the literal "(Songs-DB_Custom2)" prefix.
    # Matching on the value text ensures unrelated comments/lyrics are ignored.
    ET_COMMENT_C2=$(printf '%s'     "$raw" | grep -m1 '^Comment[[:space:]-].*:[[:space:]]*(Songs-DB_Custom2)' | sed 's/^[^:]*:[[:space:]]*//')
}

start_exiftool_daemon

#############################################
# Backup Existing Database
#############################################
if [ "$CREATE_BACKUP" = true ] && [ -f "$MUSICDB" ] && [ "$TEST_MODE" = false ] && [ "$DRY_RUN" = false ]; then
    [ "$QUIET" = false ] && echo "Creating backup of existing database..."
    if backup_database "$MUSICDB"; then
        [ "$QUIET" = false ] && echo "Backup created successfully"
    else
        echo "Warning: Backup failed but continuing..." >&2
    fi
fi

#############################################
# Main Processing
#############################################
if [ "$DRY_RUN" = true ]; then
    [ "$QUIET" = false ] && echo "=== MusicLib Database Rebuild - DRY RUN MODE ==="
else
    [ "$QUIET" = false ] && echo "=== MusicLib Database Rebuild ==="
fi
[ "$QUIET" = false ] && echo "Source directory: $MUSIC_DIR"
[ "$QUIET" = false ] && [ "$DRY_RUN" = false ] && echo "Output file: $OUTPUT_FILE"
[ "$QUIET" = false ] && echo ""

# Create temporary file for raw export
TEMP_EXPORT=$(mktemp)
CLEANUP_FILES="$TEMP_EXPORT"
trap 'stop_exiftool_daemon; rm -f $CLEANUP_FILES' EXIT

# Scan for audio files — write directly to temp file so the file list
# lives on disk rather than in a shell variable.  This avoids any FD
# interaction between bash herestrings and the exiftool coproc.
[ "$QUIET" = false ] && echo "Scanning for audio files..."
SCAN_FILE="$TEMP_EXPORT"
find "$MUSIC_DIR" -mindepth "$MIN_DEPTH" -type f \( \
    -iname "*.mp3" -o -iname "*.flac" -o -iname "*.m4a" -o \
    -iname "*.ogg" -o -iname "*.opus" -o -iname "*.wma" \) > "$SCAN_FILE" 2>>"$ERROR_LOG"

SCAN_EXIT_CODE=$?
if [ $SCAN_EXIT_CODE -ne 0 ]; then
    error_exit 2 "Filesystem scan failed" "directory" "$MUSIC_DIR" "error" "exit code $SCAN_EXIT_CODE"
    exit 2
fi

# Count total files
TOTAL_FILES=$(wc -l < "$SCAN_FILE")
TOTAL_FILES=${TOTAL_FILES##* }   # strip any leading whitespace from wc

[ "$QUIET" = false ] && echo "Found $TOTAL_FILES audio files"
[ "$QUIET" = false ] && echo ""

if [ "$TOTAL_FILES" -eq 0 ]; then
    error_exit 2 "No audio files found in directory" "directory" "$MUSIC_DIR" "min_depth" "$MIN_DEPTH"
    exit 2
fi

#############################################
# DRY RUN MODE - Preview Only
#############################################
if [ "$DRY_RUN" = true ]; then
    [ "$QUIET" = false ] && echo "Preview: Analyzing files without making changes..."
    [ "$QUIET" = false ] && echo ""
    
    declare -A ALBUM_PREVIEW=()
    PREVIEW_COUNT=0
    MISSING_TAGS_COUNT=0
    SAMPLE_FILES=()
    
    # Process files for preview
    while IFS= read -r filepath; do
        [ -z "$filepath" ] && continue
        
        PREVIEW_COUNT=$((PREVIEW_COUNT + 1))
        
        # Extract basic metadata for preview via daemon (1 round-trip)
        query_exiftool_daemon "$filepath"
        ARTIST="$ET_ARTIST"
        ALBUM="$ET_ALBUM"
        TITLE="$ET_TITLE"
        
        # Track files with missing critical tags
        if [ -z "$ARTIST" ] || [ -z "$TITLE" ]; then
            MISSING_TAGS_COUNT=$((MISSING_TAGS_COUNT + 1))
            if [ ${#SAMPLE_FILES[@]} -lt 3 ]; then
                SAMPLE_FILES+=("$filepath")
            fi
        fi
        
        # Collect unique albums
        if [ -n "$ALBUM" ]; then
            ALBUM_PREVIEW["$ALBUM"]=1
        fi
        
        # Show progress every 100 files
        if [ "$QUIET" = false ] && [ "$SHOW_PROGRESS" = true ] && [ $((PREVIEW_COUNT % 100)) -eq 0 ]; then
            echo "  Analyzed $PREVIEW_COUNT of $TOTAL_FILES files..."
        fi
    done < "$SCAN_FILE"

    [ "$QUIET" = false ] && echo ""
    echo "=== Dry Run Summary ==="
    echo "Total files found: $TOTAL_FILES"
    echo "Files that would be processed: $TOTAL_FILES"
    echo "Estimated unique albums: ${#ALBUM_PREVIEW[@]}"
    
    if [ $MISSING_TAGS_COUNT -gt 0 ]; then
        echo ""
        echo "WARNING: $MISSING_TAGS_COUNT files missing Artist or Title tags"
        if [ ${#SAMPLE_FILES[@]} -gt 0 ]; then
            echo "Sample files with missing tags:"
            for sample in "${SAMPLE_FILES[@]}"; do
                echo "  - $(basename "$sample")"
            done
        fi
    fi
    
    echo ""
    echo "Database changes:"
    if [ "$TEST_MODE" = true ]; then
        echo "  - Would create: $OUTPUT_FILE (test mode)"
    else
        if [ -f "$OUTPUT_FILE" ]; then
            CURRENT_ENTRIES=$(grep -v "^ID" "$OUTPUT_FILE" 2>/dev/null | wc -l || echo 0)
            echo "  - Would replace: $OUTPUT_FILE"
            echo "  - Current entries: $CURRENT_ENTRIES"
            echo "  - New entries: $TOTAL_FILES"
            [ "$CREATE_BACKUP" = true ] && echo "  - Would backup existing database"
        else
            echo "  - Would create: $OUTPUT_FILE"
            echo "  - New entries: $TOTAL_FILES"
        fi
    fi
    echo ""
    echo "No changes were made (dry-run mode)"
    echo "Run without --dry-run to apply changes"
    
    exit 1  # Exit 1 for dry-run complete (informational, not an error)
fi

#############################################
# NORMAL MODE - Process Files
#############################################
[ "$QUIET" = false ] && echo "Processing files..."

CURRENT_ID=1
declare -A ALBUM_ID_MAP=()
NEXT_ALBUM_ID=1
PROCESSING_ERRORS=0

# Determine working file: test mode writes directly, production uses temp file
if [ "$TEST_MODE" = true ]; then
    WORKING_FILE="$OUTPUT_FILE"
    [ "$QUIET" = false ] && echo "TEST MODE: Writing directly to $OUTPUT_FILE"
else
    # Create temporary file in same directory as target for atomic move
    WORKING_FILE=$(mktemp "${OUTPUT_FILE}.rebuild.XXXXXX") || {
        error_exit 2 "Failed to create temporary database file" "directory" "$(dirname "$OUTPUT_FILE")" "target" "$OUTPUT_FILE"
        exit 2
    }
    CLEANUP_FILES="$CLEANUP_FILES $WORKING_FILE"
    [ "$QUIET" = false ] && echo "Building database in temporary file..."
fi

# Write header if not suppressed
if [ "$NO_HEADER" = false ]; then
    if ! echo "$DEFAULT_HEADER" > "$WORKING_FILE" 2>/dev/null; then
        error_exit 2 "Failed to write database header" "file" "$WORKING_FILE"
        exit 2
    fi
fi

# Process all found files
while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue
    
    # Extract all metadata in a single daemon round-trip (stay_open mode)
    query_exiftool_daemon "$filepath"
    ARTIST="$ET_ARTIST"
    ALBUM="$ET_ALBUM"
    ALBUMARTIST="$ET_ALBUMARTIST"
    TITLE="${ET_TITLE:-$(basename "$filepath" | sed 's/\.[^.]*$//')}"
    GENRE="$ET_GENRE"

    # Duration: strip any trailing annotation like " (approx)"
    DURATION_STR="${ET_DURATION%% *}"

    if [ -n "$DURATION_STR" ]; then
        if [[ "$DURATION_STR" == *:* ]]; then
            IFS=: read -r h m s <<< "$DURATION_STR"
            if [ -z "$s" ]; then
                s=$m
                m=$h
                h=0
            fi
            DURATION_MS=$(echo "($h * 3600 + $m * 60 + $s) * 1000" | bc | cut -d. -f1)
        else
            DURATION_MS=$(echo "$DURATION_STR * 1000" | bc | cut -d. -f1)
        fi
        # SongLength format: whole seconds × 1000 (e.g., 360000 = 6 minutes)
        # Matches format_song_length() in musiclib_utils.sh
        SONGLENGTH=$(echo "$DURATION_MS / 1000" | bc)000
    else
        SONGLENGTH=0
    fi

    # Get rating from Popularimeter data already fetched by daemon
    RATING=$(printf '%s' "$ET_POPM" | sed -n 's/.*Rating=\([0-9][0-9]*\).*/\1/p')

    # Fallback to 0 if no POPM rating present
    [ -z "$RATING" ] && RATING="0"

    # GROUPDESC from Grouping
    GROUPDESC="${ET_GROUPDESC:-0}"

    # LASTPLAYED from Songs-DB_Custom1 tag (Excel serial float, e.g. 46048.762396).
    # exiftool silently skips this TXXX frame on many files; kid3-cli reads it reliably.
    # Only attempted when --restore-lastplayed is set; new libraries skip this for speed.
    if [[ "$RESTORE_LASTPLAYED" == true ]]; then
        KID3_CUSTOM1=$(kid3-cli -c "get Songs-DB_Custom1" "$filepath" 2>/dev/null)
        if [[ -n "$KID3_CUSTOM1" ]] && [[ "$KID3_CUSTOM1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            LASTPLAYED="$KID3_CUSTOM1"
        else
            LASTPLAYED="0.000000"
        fi
    else
        LASTPLAYED="0.000000"
    fi

    # CUSTOM2 resolution — three storage formats are handled in priority order:
    #  1. TXXX frame "Songs-DB_Custom2"  (kid3-cli canonical format)
    #  2. COMM frame (plain or language-coded) whose value carries the
    #     "(Songs-DB_Custom2)" prefix — the grep already screens for this,
    #     so ET_COMMENT_C2 is empty whenever no matching frame exists.
    # Unrelated comments/lyrics are never mistaken for Custom2.
    if [ -n "$ET_CUSTOM2_TXXX" ]; then
        # Priority 1: dedicated TXXX frame — use value directly
        CUSTOM2="$ET_CUSTOM2_TXXX"
    elif [ -n "$ET_COMMENT_C2" ]; then
        # Priority 2: COMM frame with prefix — strip the prefix to get the value
        CUSTOM2=$(printf '%s' "$ET_COMMENT_C2" | sed 's/^(Songs-DB_Custom2)[[:space:]]*//')
    else
        CUSTOM2=""
    fi

    # Generate or lookup album ID
    if [ -n "$ALBUM" ]; then
        if [ -z "${ALBUM_ID_MAP[$ALBUM]:-}" ]; then
            # New album - assign next ID
            IDALBUM=$NEXT_ALBUM_ID
            NEXT_ALBUM_ID=$((NEXT_ALBUM_ID + 1))
            ALBUM_ID_MAP[$ALBUM]=$IDALBUM
        else
            IDALBUM=${ALBUM_ID_MAP[$ALBUM]}
        fi
    else
        IDALBUM=""
    fi

    # Sanitize text fields before writing to DSV database
    ARTIST="$(sanitize_tag_value "$ARTIST")"
    ALBUM="$(sanitize_tag_value "$ALBUM")"
    ALBUMARTIST="$(sanitize_tag_value "$ALBUMARTIST")"
    TITLE="$(sanitize_tag_value "$TITLE")"
    GENRE="$(sanitize_tag_value "$GENRE")"

    # Build database entry
    ENTRY="${CURRENT_ID}^${ARTIST}^${IDALBUM}^${ALBUM}^${ALBUMARTIST}^${TITLE}^${filepath}^${GENRE}^${SONGLENGTH}^${RATING}^${CUSTOM2}^${GROUPDESC}^${LASTPLAYED}^^"

    if ! validate_entry_fields "$ENTRY"; then
        PROCESSING_ERRORS=$((PROCESSING_ERRORS + 1))
        [ "$QUIET" = false ] && echo "  Warning: Skipped malformed entry for: $(basename "$filepath")" >&2
        CURRENT_ID=$((CURRENT_ID - 1))  # Don't burn an ID on a skipped entry
        continue
    fi

    if ! echo "$ENTRY" >> "$WORKING_FILE" 2>/dev/null; then
        PROCESSING_ERRORS=$((PROCESSING_ERRORS + 1))
        [ "$QUIET" = false ] && echo "  Warning: Failed to write entry for: $(basename "$filepath")" >&2
    fi

    # Enhanced progress indicator
    if [ "$QUIET" = false ] && [ "$SHOW_PROGRESS" = true ]; then
        if [ $((CURRENT_ID % 100)) -eq 0 ]; then
            PERCENT=$((CURRENT_ID * 100 / TOTAL_FILES))
            echo "  Processed $CURRENT_ID of $TOTAL_FILES ($PERCENT%)..."
        fi
    fi

    CURRENT_ID=$((CURRENT_ID + 1))
done < "$SCAN_FILE"

TOTAL_PROCESSED=$((CURRENT_ID - 1))

# Check for processing errors
if [ $PROCESSING_ERRORS -gt 0 ]; then
    echo "Warning: $PROCESSING_ERRORS files had processing errors" >&2
fi

[ "$QUIET" = false ] && echo ""
[ "$QUIET" = false ] && echo "=== Rebuild Complete ==="
[ "$QUIET" = false ] && echo "Total tracks processed: $TOTAL_PROCESSED"
[ "$QUIET" = false ] && echo "Unique albums: $((NEXT_ALBUM_ID - 1))"

if [ "$TEST_MODE" = true ]; then
    [ "$QUIET" = false ] && echo "Database file: $OUTPUT_FILE"
    echo ""
    echo "TEST MODE: Database written to test file"
    echo "Review: $OUTPUT_FILE"
    echo ""
    echo "To apply changes, run without -t flag"
else
    # Atomic replacement with database lock
    [ "$QUIET" = false ] && echo "Finalizing database replacement..."

    # Function to perform the atomic move
    perform_database_replacement() {
        mv "$WORKING_FILE" "$OUTPUT_FILE"
        return $?
    }

    # Use with_db_lock to ensure exclusive access during replacement
    if ! with_db_lock 10 perform_database_replacement; then
        error_exit 2 "Failed to replace database file - lock timeout or move failed" \
            "temp_file" "$WORKING_FILE" "target_file" "$OUTPUT_FILE" "timeout" "10 seconds"
        exit 2
    fi

    [ "$QUIET" = false ] && echo "Database file: $OUTPUT_FILE"
    echo ""
    echo "Database rebuild complete!"
    [ "$CREATE_BACKUP" = true ] && echo "Backup created in: $(dirname "$MUSICDB")"

    # Sync Baloo extended attributes so Dolphin's Rating column reflects the
    # rebuilt database.  Non-fatal: skipped silently if setfattr is absent.
    if command -v setfattr >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/musiclib_baloo_sync.sh" ]; then
        [ "$QUIET" = false ] && echo ""
        [ "$QUIET" = false ] && echo "Syncing Baloo rating attributes for Dolphin rating display..."
        if [ "$QUIET" = true ]; then
            "$SCRIPT_DIR/musiclib_baloo_sync.sh" >/dev/null 2>&1 || true
        else
            "$SCRIPT_DIR/musiclib_baloo_sync.sh" || true
        fi
    fi
fi

exit 0
