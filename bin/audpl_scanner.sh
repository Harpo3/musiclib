#!/bin/bash
# Script to (1) scan playlist files or (2) scan then create CSV with playlist# and position#, and repeats#
# Requires: kid3-cli
#
# Usage:
#   ./audpl_scanner.sh scan     - Only scan and process Audacious playlists
#   ./audpl_scanner.sh create   - Scan playlists AND create CSV with ratings

# ────────────────────────────────────────────────
# CONFIGURATION - use expanded paths
# ────────────────────────────────────────────────

AUDACIOUS_SRC_DIR="$HOME/.config/audacious/playlists" # Audacious .config location of playlist files
PLAYLIST_DIR="$HOME/musiclib/playlists"          # your location for .audpl files
OUTPUT_DIR="$HOME/musiclib/data"                 # location for musiclib data
OUTPUT_FILE="playlist_ratings.csv"

OUTPUT_FILE_FULL="${OUTPUT_DIR}/${OUTPUT_FILE}"

TEMP_FILE="${OUTPUT_DIR}/playlist_ratings_temp.csv"
TEMP_FILE_SORTED="${OUTPUT_DIR}/playlist_ratings_sorted.csv"
TEMP_FILE_WITH_REPEATS="${OUTPUT_DIR}/playlist_ratings_with_repeats.csv"

# ────────────────────────────────────────────────
# FUNCTION: Scan and process Audacious playlists
# ────────────────────────────────────────────────

scan_playlists() {
    echo "=== Scanning and processing Audacious playlists ==="

    # Create destination directory if it doesn't exist
    mkdir -p "$PLAYLIST_DIR" || { echo "Error: Cannot create $PLAYLIST_DIR"; exit 1; }

    # Safety check
    if [[ ! -d "$AUDACIOUS_SRC_DIR" ]]; then
        echo "Error: Source directory $AUDACIOUS_SRC_DIR not found."
        exit 1
    fi

    shopt -s nullglob  # so the loop doesn't run if no files

    local count=0
    for file in "$AUDACIOUS_SRC_DIR"/*.audpl; do
        # Read first line only
        first_line=$(head -n 1 "$file" 2>/dev/null)

        if [[ -z "$first_line" || "$first_line" != title=* ]]; then
            echo "Skipping $file  (no title= on first line)"
            continue
        fi

        # Extract everything after title=
        title_raw="${first_line#title=}"

        # If empty after extraction → skip
        [[ -z "$title_raw" ]] && {
            echo "Skipping $file  (empty title)"
            continue
        }

        # Basic URL-decode first (handles %20 → space, %21 → !, etc.)
        title_decoded=$(printf '%b' "${title_raw//%/\\x}")

        # Sanitize: replace any non-alphanumeric (except - _ .) with _
        # This catches spaces, !@#$%^&*()+= etc.
        title_safe=$(echo "$title_decoded" | tr -s '[:space:][:punct:]' '_' | tr -d '\000-\037' | sed 's/__*/_/g; s/^_//; s/_$//')

        # If after sanitization we have nothing useful → fallback to basename
        if [[ -z "$title_safe" ]]; then
            title_safe=$(basename "$file" .audpl)
            echo "Warning: Empty/unsafe title in $file → using basename $title_safe"
        fi

        # Final destination filename
        dest="$PLAYLIST_DIR/$title_safe.audpl"

        # Copy with verbose + preserve attributes (overwrites if exists)
        cp -vp "$file" "$dest"
        ((count++))
    done

    echo ""
    echo "Scan complete! Processed $count playlist files to $PLAYLIST_DIR"
}

# ────────────────────────────────────────────────
# FUNCTION: Create CSV with playlist ratings
# ────────────────────────────────────────────────

create_csv() {
    echo "=== Creating CSV with playlist ratings ==="

    # Check if kid3-cli is installed
    if ! command -v kid3-cli &> /dev/null; then
        echo "Error: kid3-cli is not installed. Please install it first."
        echo "On Ubuntu/Debian: sudo apt-get install kid3-cli"
        exit 1
    fi

    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR" || {
        echo "Error: Cannot create output directory $OUTPUT_DIR"
        exit 1
    }

    # Check that all 10 required playlists exist
    echo "Checking for required playlists (1.audpl through 10.audpl)..."
    missing_playlists=()
    for i in {1..10}; do
        if [ ! -f "${PLAYLIST_DIR}/${i}.audpl" ]; then
            missing_playlists+=("${i}.audpl")
        fi
    done

    if [ ${#missing_playlists[@]} -gt 0 ]; then
        echo "Error: Missing required playlist files in $PLAYLIST_DIR:"
        for missing in "${missing_playlists[@]}"; do
            echo "  - $missing"
        done
        echo ""
        echo "All playlists numbered 1-10 must exist before creating CSV."
        echo "Run '$0 scan' first to update playlists, or manually create missing files."
        exit 1
    fi
    echo "✓ All 10 required playlists found"
    echo ""

    # Create CSV header with ^ delimiter
    echo "filename location^Artist^Title^POPM^Songs-DB_Custom2^playlist#^position#" > "$TEMP_FILE"

    total_entries=0

    # Loop through playlists 1-10
    for playlist_num in {1..10}; do
        playlist_file="${PLAYLIST_DIR}/${playlist_num}.audpl"

        if [ ! -f "$playlist_file" ]; then
            echo "Warning: Playlist file $playlist_file not found, skipping..."
            continue
        fi

        echo "Processing playlist $playlist_num..."

        position=0
        while IFS= read -r line; do
            if [[ $line == uri=file://* ]]; then
                # Extract and decode file path
                mp3_file=$(echo "$line" | sed 's/^uri=file:\/\///' | sed 's/%20/ /g; s/%27/'\''/g' | tr -d '\r\n')

                ((position++))

                # Get relevant tags (suppress Qt warnings)
                tag_output=$(kid3-cli -c "select \"$mp3_file\"" -c "get" 2>/dev/null | grep -E "^  (Title|Artist|Rating|Songs-DB_Custom2)")

                popm=$(echo "$tag_output" | grep "^  Rating" | sed -E 's/^[^0-9]*([0-9]+).*/\1/')
                artist=$(echo "$tag_output" | grep "^  Artist" | sed -E 's/^  Artist[[:space:]]+//' | tr -d '\r\n')
                title=$(echo "$tag_output" | grep "^  Title" | sed -E 's/^  Title[[:space:]]+//' | tr -d '\r\n')
                custom2=$(echo "$tag_output" | grep "^  Songs-DB_Custom2" | sed -E 's/^  Songs-DB_Custom2[[:space:]]+//' | tr -d '\r\n')

                # Escape any ^ characters in fields for our delimiter
                mp3_file=$(echo "$mp3_file" | sed 's/\^/^^/g')
                artist=$(echo "$artist" | sed 's/\^/^^/g')
                title=$(echo "$title" | sed 's/\^/^^/g')
                custom2=$(echo "$custom2" | sed 's/\^/^^/g')

                # Write row with ^ delimiter
                printf '%s^%s^%s^%s^%s^%s^%s\n' \
                    "$mp3_file" "$artist" "$title" "$popm" "$custom2" "$playlist_num" "$position" >> "$TEMP_FILE"

                ((total_entries++))
            fi
        done < "$playlist_file"

        echo " Found $position entries in playlist $playlist_num"
    done

    echo "Sorting results by playlist# and position#..."
    # Sort (numeric on columns 6 and 7) using ^ delimiter
    (head -n 1 "$TEMP_FILE"; tail -n +2 "$TEMP_FILE" | sort -t'^' -k6,6n -k7,7n) > "$TEMP_FILE_SORTED"

    echo "Counting repeat occurrences of each file..."
    # New header with repeats
    head -n 1 "$TEMP_FILE_SORTED" | sed 's/$/^repeats/' > "$TEMP_FILE_WITH_REPEATS"

    tail -n +2 "$TEMP_FILE_SORTED" | while IFS='^' read -r filename artist title popm custom2 playlist_num position; do
        # Count occurrences of this exact filename in the sorted file (escape ^ for grep)
        filename_escaped=$(echo "$filename" | sed 's/\^/\\^/g')
        count=$(grep -c "^${filename_escaped}\^" "$TEMP_FILE_SORTED")

        printf '%s^%s^%s^%s^%s^%s^%s^%s\n' \
            "$filename" "$artist" "$title" "$popm" "$custom2" "$playlist_num" "$position" "$count" >> "$TEMP_FILE_WITH_REPEATS"
    done

    # Final move
    mv "$TEMP_FILE_WITH_REPEATS" "$OUTPUT_FILE_FULL" || {
        echo "Error: Failed to move final file to $OUTPUT_FILE_FULL"
        exit 1
    }

    # Clean up
    rm -f "$TEMP_FILE" "$TEMP_FILE_SORTED"

    echo ""
    echo "Complete! Processed $total_entries total entries from playlists"
    echo "Results saved to: $OUTPUT_FILE_FULL"
    ls -l "$OUTPUT_FILE_FULL" 2>/dev/null
}

# ────────────────────────────────────────────────
# MAIN SCRIPT LOGIC
# ────────────────────────────────────────────────

# Check for command argument
if [ $# -eq 0 ]; then
    echo "Error: No command specified"
    echo ""
    echo "Usage:"
    echo "  $0 scan     - Only scan and process Audacious playlists into $PLAYLIST_DIR"
    echo "  $0 create   - Scan playlists AND create CSV with playlist#, position#, and repeats#"
    echo ""
    exit 1
fi

case "$1" in
    scan)
        scan_playlists
        ;;
    create)
        scan_playlists
        echo ""
        create_csv
        ;;
    *)
        echo "Error: Invalid command '$1'"
        echo ""
        echo "Usage:"
        echo "  $0 scan     - Only scan and process Audacious playlists into $PLAYLIST_DIR"
        echo "  $0 create   - Scan playlists AND create CSV with playlist#, position#, and repeats#"
        echo ""
        exit 1
        ;;
esac

exit 0
