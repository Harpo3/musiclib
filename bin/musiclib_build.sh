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
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$HOME/musiclib}"

# Source utilities if available
if [ -f "$MUSICLIB_ROOT/bin/musiclib_utils.sh" ]; then
    source "$MUSICLIB_ROOT/bin/musiclib_utils.sh"
    load_config 2>/dev/null || true
fi

# Fallback configuration
MUSICDB="${MUSICDB:-$MUSICLIB_ROOT/data/musiclib.dsv}"
MUSIC_ROOT_DIR="${MUSIC_ROOT_DIR:-/mnt/music}"

# Default settings
MIN_DEPTH=1
NO_HEADER=false
QUIET=false
SORT_COLUMN=""
OUTPUT_FILE="$MUSICDB"
TEMP_OUTPUT=""
DRY_RUN=false
SHOW_PROGRESS=true

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
Usage: $0 [MUSIC_DIR] [options]

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

Examples:
  # Preview what would be rebuilt
  $0 /mnt/music --dry-run

  # Rebuild entire database
  $0 /mnt/music

  # Rebuild with backup
  $0 /mnt/music -b

  # Test on subdirectory
  $0 /mnt/music/Rock -t

  # Custom output location
  $0 /mnt/music -o ~/music_backup.dsv

Exit Codes:
  0 - Success
  1 - Dry-run complete (informational) or user error (invalid arguments)
  2 - System failure (missing directory, tools unavailable, lock timeout, scan failure)

Notes:
  - This will REPLACE the existing database unless -t or --dry-run is used
  - Album IDs (IDAlbum) will be regenerated
  - Track IDs will be sequential starting from 1
  - LastTimePlayed will be set to 0 (never played)
  - Takes 10+ minutes for large libraries (10,000+ tracks)
  - Use --dry-run first to preview changes safely

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
trap 'rm -f $CLEANUP_FILES' EXIT

# Scan for audio files and capture output
[ "$QUIET" = false ] && echo "Scanning for audio files..."
SCAN_OUTPUT=$(find "$MUSIC_DIR" -mindepth "$MIN_DEPTH" -type f \( \
    -iname "*.mp3" -o -iname "*.flac" -o -iname "*.m4a" -o \
    -iname "*.ogg" -o -iname "*.opus" -o -iname "*.wma" \) 2>>"$ERROR_LOG")

SCAN_EXIT_CODE=$?
if [ $SCAN_EXIT_CODE -ne 0 ]; then
    error_exit 2 "Filesystem scan failed" "directory" "$MUSIC_DIR" "error" "${SCAN_OUTPUT:-unknown error}"
    exit 2
fi

# Count total files
if [ -z "$SCAN_OUTPUT" ]; then
    TOTAL_FILES=0
else
    TOTAL_FILES=$(echo "$SCAN_OUTPUT" | wc -l)
fi

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
    
    declare -A ALBUM_PREVIEW
    PREVIEW_COUNT=0
    MISSING_TAGS_COUNT=0
    SAMPLE_FILES=()
    
    # Process files for preview
    while IFS= read -r filepath; do
        [ -z "$filepath" ] && continue
        
        PREVIEW_COUNT=$((PREVIEW_COUNT + 1))
        
        # Extract basic metadata for preview
        ARTIST=$(exiftool -Artist -s3 "$filepath" 2>/dev/null || echo "")
        ALBUM=$(exiftool -Album -s3 "$filepath" 2>/dev/null || echo "")
        TITLE=$(exiftool -Title -s3 "$filepath" 2>/dev/null || echo "")
        
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
    done <<< "$SCAN_OUTPUT"
    
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
declare -A ALBUM_ID_MAP
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
    
    # Extract metadata using exiftool
    ARTIST=$(exiftool -Artist -s3 "$filepath" 2>/dev/null || echo "")
    ALBUM=$(exiftool -Album -s3 "$filepath" 2>/dev/null || echo "")
    ALBUMARTIST=$(exiftool -AlbumArtist -s3 "$filepath" 2>/dev/null || echo "")
    TITLE=$(exiftool -Title -s3 "$filepath" 2>/dev/null || echo "$(basename "$filepath" | sed 's/\.[^.]*$//')")
    GENRE=$(exiftool -Genre -s3 "$filepath" 2>/dev/null || echo "")

    # Get song length in milliseconds, then format as seconds000
    DURATION_STR=$(exiftool -Duration -s3 "$filepath" 2>/dev/null)

    # Strip any trailing annotation like " (approx)"
    DURATION_STR=${DURATION_STR%% *}

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

    # Get rating directly from Popularimeter (use POPM byte 0-255 as-is)
    POPM=$(exiftool -Popularimeter -s3 "$filepath" 2>/dev/null)
    RATING=$(echo "$POPM" | sed -n 's/.*Rating=\([0-9][0-9]*\).*/\1/p')

    # Fallback to 0 if no POPM rating present
    [ -z "$RATING" ] && RATING="0"

    # GROUPDESC from Grouping
    GROUPDESC=$(exiftool -Grouping -s3 "$filepath" 2>/dev/null)
    [ -z "$GROUPDESC" ] && GROUPDESC="0"

    # CUSTOM2 from Comment (strip Songs-DB prefix if present)
    CUSTOM2_RAW=$(exiftool -Comment -s3 "$filepath" 2>/dev/null)

    # Remove leading/trailing whitespace
    CUSTOM2_RAW=$(echo "$CUSTOM2_RAW" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    # If it starts with "(Songs-DB_Custom2)", strip that plus any following spaces
    CUSTOM2=$(echo "$CUSTOM2_RAW" | sed 's/^(Songs-DB_Custom2)[[:space:]]*//')

    # Fallback if empty
    [ -z "$CUSTOM2" ] && CUSTOM2="$CUSTOM2_RAW"

    # Generate or lookup album ID
    if [ -n "$ALBUM" ]; then
        if [ -z "${ALBUM_ID_MAP[$ALBUM]:-}" ]; then
            # New album - assign next ID
            IDALBUM=${#ALBUM_ID_MAP[@]}
            IDALBUM=$((IDALBUM + 1))
            ALBUM_ID_MAP[$ALBUM]=$IDALBUM
        else
            IDALBUM=${ALBUM_ID_MAP[$ALBUM]}
        fi
    else
        IDALBUM=""
    fi

    # Build database entry
    ENTRY="${CURRENT_ID}^${ARTIST}^${IDALBUM}^${ALBUM}^${ALBUMARTIST}^${TITLE}^${filepath}^${GENRE}^${SONGLENGTH}^${RATING}^${CUSTOM2}^${GROUPDESC}^0.000000^^"

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
done <<< "$SCAN_OUTPUT"

TOTAL_PROCESSED=$((CURRENT_ID - 1))

# Check for processing errors
if [ $PROCESSING_ERRORS -gt 0 ]; then
    echo "Warning: $PROCESSING_ERRORS files had processing errors" >&2
fi

[ "$QUIET" = false ] && echo ""
[ "$QUIET" = false ] && echo "=== Rebuild Complete ==="
[ "$QUIET" = false ] && echo "Total tracks processed: $TOTAL_PROCESSED"
[ "$QUIET" = false ] && echo "Unique albums: ${#ALBUM_ID_MAP[@]}"

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
fi

exit 0
