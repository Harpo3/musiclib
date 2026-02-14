#!/bin/bash
# Script to extract MP3 tag information and create rating.csv
# Requires: kid3-cli

# Set output directory
OUTPUT_DIR="$HOME/musiclib/data"
OUTPUT_FILE="$OUTPUT_DIR/rating.csv"
TEMP_FILE="$OUTPUT_DIR/rating_temp.csv"
MUSIC_DIR="/mnt/music/Music"

# Check if kid3-cli is installed
if ! command -v kid3-cli &> /dev/null; then
    echo "Error: kid3-cli is not installed. Please install it first."
    echo "On Ubuntu/Debian: sudo apt-get install kid3-cli"
    exit 1
fi

# Check if music directory exists
if [ ! -d "$MUSIC_DIR" ]; then
    echo "Error: Music directory $MUSIC_DIR does not exist."
    exit 1
fi

# Create output directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Create CSV header with ^ delimiter
echo "filename location^Artist^Title^POPM^Songs-DB_Custom2" > "$TEMP_FILE"

# Find all MP3 files and process them
echo "Scanning for MP3 files in $MUSIC_DIR..."
file_count=0

# Use process substitution instead of pipe to avoid subshell
while IFS= read -r mp3_file; do
    # Get all tags at once for efficiency and suppress Qt warnings
    tag_output=$(kid3-cli -c "select \"$mp3_file\"" -c "get" 2>/dev/null)

    # Extract individual fields - note the spacing in kid3-cli output
    popm=$(echo "$tag_output" | grep "^ *Rating" | sed -E 's/^[^0-9]*([0-9]+).*/\1/')
    artist=$(echo "$tag_output" | grep "^ *Artist" | sed -E 's/^ *Artist[[:space:]]+//' | tr -d '\r\n')
    title=$(echo "$tag_output" | grep "^ *Title" | sed -E 's/^ *Title[[:space:]]+//' | tr -d '\r\n')
    custom2=$(echo "$tag_output" | grep "^ *Songs-DB_Custom2" | sed -E 's/^ *Songs-DB_Custom2[[:space:]]+//' | tr -d '\r\n')

    # Skip if Rating (POPM) is empty
    if [ -z "$popm" ]; then
        continue
    fi

    # Check if POPM is greater than 32 (numeric comparison)
    if [ "$popm" -le 32 ] 2>/dev/null; then
        continue
    fi

    # Escape any ^ characters in fields for our delimiter
    mp3_file=$(echo "$mp3_file" | sed 's/\^/^^/g')
    artist=$(echo "$artist" | sed 's/\^/^^/g')
    title=$(echo "$title" | sed 's/\^/^^/g')
    custom2=$(echo "$custom2" | sed 's/\^/^^/g')

    # Write to temp file with ^ delimiter
    echo "$mp3_file^$artist^$title^$popm^$custom2" >> "$TEMP_FILE"

    ((file_count++))
    if [ $((file_count % 100)) -eq 0 ]; then
        echo "Processed $file_count files so far..."
    fi
done < <(find "$MUSIC_DIR" -type f -iname "*.mp3")

# Sort by Songs-DB_Custom2 (5th column) alphabetically, then by Rating (4th column) numerically descending
echo "Sorting results by Songs-DB_Custom2, then by Rating..."
(head -n 1 "$TEMP_FILE" && tail -n +2 "$TEMP_FILE" | sort -t'^' -k5,5 -k4,4rn) > "$OUTPUT_FILE"

# Clean up temp file
rm "$TEMP_FILE"

# Count results
result_count=$(( $(wc -l < "$OUTPUT_FILE") - 1))
echo ""
echo "Complete! Found $result_count MP3 files with POPM > 32"
echo "Results saved to: $OUTPUT_FILE"
