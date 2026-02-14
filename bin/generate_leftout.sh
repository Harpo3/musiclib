#!/bin/bash

# Script to find songs in ratings.csv that are not in any .audpl playlist
# Creates leftout.csv with songs not found in any playlist

RATINGS_FILE="rating.csv"
LEFTOUT_FILE="leftout.csv"
PLAYLIST_DIR="/home/lpc123/Documents/playlists"
TEMP_PATHS="/tmp/audpl_paths_$$.txt"

# Check if ratings.csv exists
if [ ! -f "$RATINGS_FILE" ]; then
    echo "Error: $RATINGS_FILE not found."
    exit 1
fi

# Check if playlist directory exists
if [ ! -d "$PLAYLIST_DIR" ]; then
    echo "Error: Playlist directory $PLAYLIST_DIR not found."
    exit 1
fi

echo "Extracting file paths from .audpl playlists..."

# Extract all file paths from all .audpl files and convert to ratings.csv format
# Change "uri=file:///mnt/music/Music" to "/mnt/music/Music"
> "$TEMP_PATHS"  # Create empty temp file

# Process numbered playlists 1-10
for i in {1..10}; do
    audpl_file="$PLAYLIST_DIR/${i}.audpl"
    if [ -f "$audpl_file" ]; then
        echo "Processing $audpl_file..."
        grep "^uri=file://" "$audpl_file" | \
            sed 's|^uri=file://||' | \
            python3 -c "import sys, urllib.parse; [print(urllib.parse.unquote(line.strip())) for line in sys.stdin]" >> "$TEMP_PATHS"
    else
        echo "Warning: $audpl_file not found, skipping..."
    fi
done

# Process Multiples.audpl
multiples_file="$PLAYLIST_DIR/Multiples.audpl"
if [ -f "$multiples_file" ]; then
    echo "Processing $multiples_file..."
    grep "^uri=file://" "$multiples_file" | \
        sed 's|^uri=file://||' | \
        python3 -c "import sys, urllib.parse; [print(urllib.parse.unquote(line.strip())) for line in sys.stdin]" >> "$TEMP_PATHS"
else
    echo "Warning: $multiples_file not found, skipping..."
fi

# Sort and remove duplicates from the path list for faster lookup
sort -u "$TEMP_PATHS" -o "$TEMP_PATHS"

path_count=$(wc -l < "$TEMP_PATHS")
echo "Found $path_count unique paths in playlists."

# Create leftout.csv with header
head -n 1 "$RATINGS_FILE" > "$LEFTOUT_FILE"

echo "Comparing ratings.csv with playlist paths..."

# Process each row in ratings.csv (skip header)
leftout_count=0
total_count=0

tail -n +2 "$RATINGS_FILE" | while IFS= read -r line; do
    ((total_count++))

    # Extract the file path (first field, enclosed in quotes)
    # This handles CSV format where first field is quoted
    file_path=$(echo "$line" | sed -E 's/^"([^"]+)".*/\1/')

    # Check if this path exists in any playlist
    if grep -Fxq "$file_path" "$TEMP_PATHS"; then
        # Path found in playlist, skip it
        continue
    else
        # Path NOT found in any playlist, add to leftout.csv
        echo "$line" >> "$LEFTOUT_FILE"
        ((leftout_count++))
    fi

    if [ $((total_count % 100)) -eq 0 ]; then
        echo "Processed $total_count rows from ratings.csv..."
    fi
done

# Clean up temp file
rm "$TEMP_PATHS"

# Count final results
final_count=$(($(wc -l < "$LEFTOUT_FILE") - 1))

echo ""
echo "Complete! Processed $(wc -l < "$RATINGS_FILE") rows from ratings.csv"
echo "Found $final_count songs NOT in any playlist"
echo "Results saved to: $LEFTOUT_FILE"
