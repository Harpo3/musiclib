#!/bin/bash
#
# musiclib_new_tracks.sh - Import new music downloads into library
#
# Usage: musiclib_new_tracks.sh [artist name]
#
# This script processes files newly downloaded to $NEW_DOWNLOAD_DIR and imports them
# to the music repository ($MUSIC_REPO) by:
#   1. Extracting ZIP files (if present) - AUTOMATIC
#   2. Normalizing MP3 filenames from ID3 tags
#   3. Standardizing volume levels with rsgain
#   4. Organizing files into artist/album folder structure
#   5. Adding tracks to the musiclib.dsv database
#
# The script pauses after extraction to allow tag editing in kid3-qt.
# IMPORTANT: Check the album tag - it determines the folder name in the repository.
#
# Exit codes:
#   0 - Success (all tracks imported)
#   1 - User error (invalid input, missing preconditions)
#   2 - System error (missing tools, I/O failure, config error)
#   3 - Deferred success (operation queued due to lock contention)
#
# Examples:
#   musiclib_new_tracks.sh "Pink Floyd"
#   musiclib_new_tracks.sh "the_beatles"
#   musiclib_new_tracks.sh --help
#
# Define variable values at musiclib/config/musiclib.conf
#

set -u
set -o pipefail

#############################################
# Early Setup and Utilities
#############################################

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$(dirname "$SCRIPT_DIR")}"

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

if ! source "$MUSICLIB_ROOT/bin/musiclib_utils_tag_functions.sh"; then
    # Can't use error_exit yet, utils not loaded
    {
        echo "{\"error\":\"Failed to load /musiclib_utils_tag_functions.sh\",\"script\":\"$(basename "$0")\",\"code\":2,\"context\":{\"file\":\"$MUSICLIB_ROOT/bin/musiclib_utils_tag_functions.sh\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
    } >&2
    exit 2
fi

#############################################
# Help Function
#############################################

show_help() {
    cat << 'EOF'
Usage: musiclib-cli new-tracks [artist name]
       musiclib-cli new-tracks --help|-h|help

Import new music downloads into the music library database.

ARGUMENTS:
  artist name        Artist name for folder organization (optional)
                     If omitted, script prompts interactively
                     Normalized to filesystem-safe format (lowercase, underscores)

  --help, -h, help   Display this help message and exit

DESCRIPTION:
  This script processes files newly downloaded to the configured download
  directory and imports them to the music repository by:

    1. Extracting ZIP files automatically (if present)
    2. Normalizing MP3 filenames from ID3 tags
    3. Standardizing volume levels with rsgain
    4. Organizing files into artist/album folder structure
    5. Adding tracks to the musiclib.dsv database

  The script pauses after extraction to allow tag editing in kid3-qt.

IMPORTANT:
  Check the album tag before continuing – it determines the folder name in
  the repository.

EXAMPLES:
  musiclib-cli new-tracks "Pink Floyd"
  musiclib-cli new-tracks "the_beatles"
  musiclib-cli new-tracks --help

CONFIGURATION:
  Define variable values in: musiclib/config/musiclib.conf

  Required variables:
    - MUSICLIB_ROOT (music library root directory)
    - MUSIC_REPO (repository path for organized music)
    - NEW_DOWNLOAD_DIR (where new downloads are placed)
    - MUSICDB (path to music database file)

REQUIRED TOOLS:
  - kid3-cli (tag editor)
  - exiftool (metadata extractor)
  - unzip (archive extraction)
  - rsgain (optional, for volume normalization)

EXIT CODES:
  0 - Success (all tracks imported successfully)
  1 - User error (invalid input, user cancellation)
  2 - System error (missing tools, I/O failure, config error)
  3 - Deferred (database operations queued due to lock contention)

EOF
}

#############################################
# Check for Help Flag
#############################################

if [ $# -ge 1 ]; then
    case "$1" in
        --help|-h|help)
            show_help
            exit 0
            ;;
    esac
fi

#############################################
# Configuration and Validation
#############################################

# Load configuration
if ! load_config; then
    error_exit 2 "Configuration load failed"
    exit 2
fi

# Validate required tools
if ! check_required_tools kid3-cli exiftool; then
    error_exit 2 "Required tools not available" "missing" "kid3-cli or exiftool"
    exit 2
fi

# Check for unzip (required for ZIP extraction)
if ! command -v unzip >/dev/null 2>&1; then
    error_exit 2 "Required tool not available" "missing" "unzip"
    exit 2
fi

# Validate required configuration variables
if [ -z "${MUSIC_REPO:-}" ]; then
    error_exit 2 "MUSIC_REPO not defined in config"
    exit 2
fi

if [ -z "${NEW_DOWNLOAD_DIR:-}" ]; then
    error_exit 2 "NEW_DOWNLOAD_DIR not defined in config"
    exit 2
fi

if [ -z "${KID3_CMD:-}" ]; then
    error_exit 2 "KID3_CMD not defined in config"
    exit 2
fi

if [ -z "${MUSICDB:-}" ]; then
    error_exit 2 "MUSICDB not defined in config"
    exit 2
fi

# Validate download directory exists and is accessible
if [ ! -d "$NEW_DOWNLOAD_DIR" ]; then
    error_exit 1 "Download directory does not exist" "directory" "$NEW_DOWNLOAD_DIR"
    exit 1
fi

if [ ! -r "$NEW_DOWNLOAD_DIR" ]; then
    error_exit 2 "Download directory not readable" "directory" "$NEW_DOWNLOAD_DIR"
    exit 2
fi

# Validate database exists and is writable
if ! validate_database "$MUSICDB"; then
    error_exit 2 "Database validation failed" "database" "$MUSICDB"
    exit 2
fi

if ! validate_dependencies; then
    error_exit 2 "Dependencies validation failed"
    exit 2
fi

# Set DOWNLOAD_DIR for backward compatibility
DOWNLOAD_DIR="$NEW_DOWNLOAD_DIR"

shopt -s nullglob

#############################################
# Database Write Function
#############################################

# Function to add a track to the database (with proper locking)
# Args: filepath [lastplayed_timestamp]
# Returns: 0 on success, 1 on error, 3 on deferred
add_track_to_database() {
    local filepath="$1"
    local lastplayed="${2:-$(epoch_to_sql_time $(date +%s))}"

    if [ ! -f "$filepath" ]; then
        echo "  Error: File not found: $filepath" >&2
        return 1
    fi

    # Guard against duplicate entries: scan the entire database for this path.
    # grep -F (fixed-string) avoids any regex interpretation of the path.
    # We search for the path surrounded by the DSV delimiter so a path that
    # is a substring of a longer path cannot produce a false positive.
    # tail -n +2 skips the header row.
    if tail -n +2 "$MUSICDB" | grep -qF "^${filepath}^"; then
        echo "  Skipping (already in database): $(basename "$filepath")"
        return 0
    fi

    # Extract metadata
    local metadata=$(extract_metadata "$filepath")
    local artist album albumartist title genre
    IFS='^' read -r artist album albumartist title genre <<< "$metadata"

    # Get song length in milliseconds
    local songlength_ms=$(get_song_length_ms "$filepath")
    local songlength=$(format_song_length "$songlength_ms")

    # Get next ID
    local next_id=$(get_next_id "$MUSICDB")

    # Get or create IDAlbum
    local idalbum=$(find_or_create_album "$MUSICDB" "$album")

    # Build the new entry line
    local new_entry="${next_id}^${artist}^${idalbum}^${album}^${albumartist}^${title}^${filepath}^${genre}^${songlength}^${DEFAULT_RATING}^${CUSTOM2:-}^${DEFAULT_GROUPDESC}^${lastplayed}^^"

    # Inner function to perform the actual database write
    db_write_entry() {
        echo "$new_entry" >> "$MUSICDB"
    }

    # Attempt to write with lock (5 second timeout)
    if ! with_db_lock 5 db_write_entry; then
        local lock_result=$?
        
        if [ "$lock_result" -eq 1 ]; then
            # Lock timeout - queue the operation for later
            local pending_file="${MUSICLIB_ROOT}/data/.pending_operations"
            local timestamp=$(date +%s)
            
            # Create pending operations directory if it doesn't exist
            mkdir -p "$(dirname "$pending_file")" 2>/dev/null || true
            
            # Queue the add_track operation
            echo "$timestamp|musiclib_new_tracks.sh|add_track|$filepath|$lastplayed" >> "$pending_file"
            
            log_message "PENDING: Add track queued: $title (database locked)"
            echo "  ⏳ Queued: $title (will be added when database is available)"
            
            # Return exit code 3 (deferred)
            return 3
        else
            # Other error (exit code 2)
            log_message "ERROR: Failed to write to database: $filepath"
            return 1
        fi
    fi

    # Database write succeeded - now update tags
    # Suppress Qt warnings
    export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
    unset QT_DEBUG_PLUGINS

    $KID3_CMD -c "set Songs-DB_Custom1 $lastplayed" "$filepath" 2>/dev/null || true
    $KID3_CMD -c "set POPM $DEFAULT_RATING" "$filepath" 2>/dev/null || true
    $KID3_CMD -c "set Work $DEFAULT_GROUPDESC" "$filepath" 2>/dev/null || true

    echo "  ✓ Added: $title (ID: $next_id, Rating: $DEFAULT_RATING, GroupDesc: $DEFAULT_GROUPDESC)"

    # Log the operation
    log_message "Added track: $title (ID: $next_id, Path: $filepath)"

    return 0
}

#############################################
# Main Processing Logic
#############################################

echo ""
echo "=== MusicLib Track Import ==="
echo "Processing directory: $DOWNLOAD_DIR"
echo ""

# Count files
zip_files=("$DOWNLOAD_DIR"/*.zip)
mp3_files=("$DOWNLOAD_DIR"/*.mp3)
num_zip=${#zip_files[@]}
num_mp3=${#mp3_files[@]}

echo "Found: ${num_zip} ZIP file(s), ${num_mp3} MP3 file(s)"
echo ""

#############################################
# CASE 1: Multiple ZIP files - Error
#############################################

if (( num_zip > 1 )); then
    error_exit 1 "Multiple ZIP files found - can only process one at a time" \
        "count" "$num_zip" "directory" "$DOWNLOAD_DIR"
    echo "Error: Found ${num_zip} ZIP files in $DOWNLOAD_DIR"
    echo "This script processes at most one zip at a time. Please leave at most one .zip file and try again."
    exit 1
fi

#############################################
# CASE 2: No ZIP and No MP3 - Nothing to do
#############################################

if (( num_zip == 0 && num_mp3 == 0 )); then
    echo "No .zip or .mp3 files found in $DOWNLOAD_DIR – nothing to do."
    exit 0
fi

#############################################
# CASE 3: Exactly One ZIP - Extract Automatically
#############################################

if (( num_zip == 1 )); then
    zipfile="${zip_files[0]}"
    echo "Processing ZIP: $(basename "$zipfile")"

    # Rename: spaces → underscores
    filename=$(basename "$zipfile")
    newname="${filename// /_}"

    if [ "$filename" != "$newname" ]; then
        echo "  → Replacing spaces: $newname"
        if ! mv -i "$zipfile" "$DOWNLOAD_DIR/$newname" 2>/dev/null; then
            error_exit 2 "Failed to rename ZIP file" "original" "$filename" "new" "$newname"
            exit 2
        fi
        zipfile="$DOWNLOAD_DIR/$newname"
    fi

    # Rename: to lowercase
    filename=$(basename "$zipfile")
    lowercase="${filename,,}"

    if [ "$filename" != "$lowercase" ]; then
        echo "  → Lowercase: $lowercase"
        if ! mv -i "$zipfile" "$DOWNLOAD_DIR/$lowercase" 2>/dev/null; then
            error_exit 2 "Failed to lowercase ZIP filename" "original" "$filename" "new" "$lowercase"
            exit 2
        fi
        zipfile="$DOWNLOAD_DIR/$lowercase"
    fi

    # Extract
    echo " Extracting..."
    if ! unzip -o "$zipfile" -d "$DOWNLOAD_DIR" 2>&1 \
       | { grep -v "^Archive:" | grep -v "^ inflating:"; } && (( PIPESTATUS[0] == 0 )); then
        error_exit 2 "ZIP extraction failed" "file" "$zipfile"
        exit 2
    fi

    # Cleanup
    echo "  Removing original ZIP..."
    rm -f "$zipfile"

    echo "ZIP processing complete."

    # Recount MP3 files after extraction
    mp3_files=("$DOWNLOAD_DIR"/*.mp3)
    num_mp3=${#mp3_files[@]}
    echo "Found ${num_mp3} MP3 file(s) after extraction."
fi

#############################################
# Interactive Tag Editing Pause
#############################################

echo ""
echo "=== Need to tailor the tags in kid3-qt before continuing? Press Enter when ready to continue or Ctrl-C to abort ==="
read -r || {
    error_exit 1 "User cancelled operation"
    exit 1
}

#############################################
# Tag Normalization
#############################################

echo ""
echo "Normalizing ID3v2 tags (removing excluded frames)..."

# Get list of MP3 files to normalize
mp3_files_temp=("$DOWNLOAD_DIR"/*.mp3)

if [ ${#mp3_files_temp[@]} -gt 0 ]; then
    normalized_count=0
    normalize_failed=0

    for file in "${mp3_files_temp[@]}"; do
        [ -f "$file" ] || continue

        if normalize_new_track_tags "$file"; then
            ((normalized_count++))
        else
            ((normalize_failed++))
            echo "  Warning: Tag normalization failed for $(basename "$file")"
        fi
    done

    echo "Tag normalization complete: $normalized_count succeeded, $normalize_failed failed"
else
    echo "No MP3 files found to normalize"
fi

#############################################
# CASE 4: Process MP3 Files
#############################################

# Recount to ensure we have current state
mp3_files=("$DOWNLOAD_DIR"/*.mp3)
num_mp3=${#mp3_files[@]}

if (( num_mp3 == 0 )); then
    echo "No MP3 files found to process."
    exit 0
fi

echo ""
echo "Processing ${num_mp3} MP3 file(s) in $DOWNLOAD_DIR"
if ! pushd "$DOWNLOAD_DIR" >/dev/null 2>&1; then
    error_exit 2 "Cannot change to download directory" "directory" "$DOWNLOAD_DIR"
    exit 2
fi

#############################################
# Step 1: Set Filename from Tags
#############################################

# Uses Tag 2 (ID3v2), format: track_-_artist_-_title
echo "Setting filename from tags..."
"$KID3_CMD" -c "fromtag %{track.2}_-_%{artist}_-_%{title} 2" *.mp3 2>/dev/null || \
    echo "  Warning: kid3-cli fromtag step had issues – continuing to normalization..."

#############################################
# Step 2: Aggressive Filename Normalization
#############################################

# - Lowercase
# - Replace anything not a-z0-9_- with single _
# - Collapse multiple _ → one _
# - Trim leading/trailing _
for f in *.mp3; do
    [ -f "$f" ] || continue
    base="${f%.mp3}"
    norm_base=$(printf '%s\n' "$base" \
        | tr 'A-Z' 'a-z' \
        | sed 's/[^a-z0-9_-]/_/g' \
        | sed 's/_\+/_/g; s/^_//; s/_$//')
    newname="${norm_base}.mp3"
    if [ "$f" = "$newname" ]; then
        continue
    fi
    echo "  $f → $newname"
    if ! mv -i -- "$f" "$newname" 2>/dev/null; then
        error_exit 2 "Failed to rename file" "original" "$f" "new" "$newname"
        popd >/dev/null
        exit 2
    fi
done
echo "MP3 filename processing complete (${num_mp3} file(s))."
popd >/dev/null

#############################################
# Volume Normalization (rsgain)
#############################################

echo ""
echo "Standardizing volume level..."
if ! command -v rsgain >/dev/null 2>&1; then
    echo "Warning: rsgain not found – skipping volume standardization"
else
    rsgain easy -q "$DOWNLOAD_DIR" 2>/dev/null || echo "  Warning: rsgain had issues, continuing..."
fi
echo "Done"

#############################################
# Artist Folder Setup
#############################################

# Get final list of MP3 files to organize
mp3_files=("$DOWNLOAD_DIR"/*.mp3)

if [ ${#mp3_files[@]} -eq 0 ]; then
    echo "No .mp3 files found in $DOWNLOAD_DIR – nothing to organize."
    exit 0
fi

echo "Organizing ${#mp3_files[@]} file(s) into artist/album structure..."

# Determine artist name
if [ $# -ge 1 ] && [ "$1" != "--help" ] && [ "$1" != "-h" ] && [ "$1" != "help" ]; then
    artist_input="$1"
else
    echo -n "Enter artist name for folder organization: "
    read -r artist_input
    
    if [ -z "$artist_input" ]; then
        error_exit 1 "No artist name provided" "action" "user_input_required"
        exit 1
    fi
fi

# Normalize artist name for filesystem
artist_normalized=$(printf '%s' "$artist_input" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s ' ' '_' \
    | sed 's/[^a-z0-9_-]//g' \
    | sed 's/_\+/_/g; s/^_//; s/_$//')

if [ -z "$artist_normalized" ]; then
    error_exit 1 "Artist name normalized to empty string" "original" "$artist_input"
    exit 1
fi

echo "  Artist normalized to: $artist_normalized"

# Create artist directory
ARTIST_DIR="$MUSIC_REPO/$artist_normalized"

if [ -d "$ARTIST_DIR" ]; then
    echo "  Artist folder already exists: $ARTIST_DIR"
else
    echo "  Creating artist folder: $ARTIST_DIR"
    if ! mkdir -p "$ARTIST_DIR" 2>/dev/null; then
        error_exit 2 "Failed to create artist directory" "directory" "$ARTIST_DIR"
        exit 2
    fi
fi

#############################################
# Album Folder Setup
#############################################

# Get album name from tags (use first file as representative)
first_file="${mp3_files[0]}"

# Try to read album tag (ID3v2 preferred)
album_raw=$("$KID3_CMD" -c 'get album' "$first_file" 2>/dev/null | head -n 1)

if [ -z "$album_raw" ] || [ "$album_raw" = "-" ]; then
    # Fallback: try albumartist or just use a generic name
    album_raw=$("$KID3_CMD" -c 'get albumartist' "$first_file" 2>/dev/null | head -n 1)
    if [ -z "$album_raw" ] || [ "$album_raw" = "-" ]; then
        album_normalized="unknown_album_$(date +%Y%m%d)"
        echo "  Warning: No album tag found – using fallback: $album_normalized"
    else
        album_normalized="various"
        echo "  Warning: No album tag, but albumartist found – using 'various'"
    fi
else
    # Normalize album name
    album_normalized=$(printf '%s' "$album_raw" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -s ' ' '_' \
        | sed 's/[^a-z0-9_-]//g' \
        | sed 's/_\+/_/g; s/^_//; s/_$//')

    if [ -z "$album_normalized" ]; then
        album_normalized="untitled_album"
        echo "  Warning: Album name normalized to empty – using 'untitled_album'"
    fi

    echo "  Detected album: $album_raw → normalized to: $album_normalized"
fi

# Full path to target album folder
ALBUM_DIR="$ARTIST_DIR/$album_normalized"

# Create if missing
if [ -d "$ALBUM_DIR" ]; then
    echo "  Album folder already exists: $ALBUM_DIR"
else
    echo "  Creating album folder: $ALBUM_DIR"
    if ! mkdir -p "$ALBUM_DIR" 2>/dev/null; then
        error_exit 2 "Failed to create album directory" "directory" "$ALBUM_DIR"
        exit 2
    fi
fi

#############################################
# Move Files to Album Directory
#############################################

echo "  Moving files to $ALBUM_DIR ..."
if ! mv -i -t "$ALBUM_DIR" "${mp3_files[@]}" 2>&1; then
    error_exit 2 "Failed to move files to album directory" "destination" "$ALBUM_DIR"
    exit 2
fi
echo "Organization complete."

#############################################
# Add Tracks to Database
#############################################

echo ""
echo "Adding processed tracks to music library database..."

added=0
failed=0
deferred=0

# Build the list of newly moved files using their destination paths.
# mp3_files[] still holds the pre-move paths from $DOWNLOAD_DIR; basename
# gives the (post-normalization) filename now sitting in $ALBUM_DIR.
# We must NOT glob "$ALBUM_DIR"/*.mp3 here because that would also pick up
# any tracks that already existed in the folder, causing duplicate DB entries.
declare -a new_track_files=()
for f in "${mp3_files[@]}"; do
    new_track_files+=("$ALBUM_DIR/$(basename "$f")")
done

for file in "${new_track_files[@]}"; do
    [ -f "$file" ] || continue

    add_track_to_database "$file"
    result=$?
    
    case $result in
        0)
            ((added++))
            ;;
        3)
            ((deferred++))
            ;;
        *)
            ((failed++))
            echo "  Failed to add: $(basename "$file")"
            ;;
    esac
done

echo "Database update summary: $added track(s) added, $deferred queued, $failed failed."

# Trigger pending operations processor if any operations were deferred
if [ $deferred -gt 0 ] && [ -f "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" ]; then
    echo "Triggering pending operations processor..."
    "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" &
fi

echo ""
echo "All processing finished."
echo "Files are now in: $ALBUM_DIR"
echo ""

# Determine final exit code
if [ $failed -gt 0 ]; then
    # Some operations failed completely
    error_exit 2 "Some tracks failed to import" "failed_count" "$failed" "added_count" "$added"
    exit 2
elif [ $deferred -gt 0 ]; then
    # Some operations were deferred (but not failed)
    exit 3
else
    # All operations succeeded immediately
    exit 0
fi
