#!/bin/bash
#
# musiclib_mobile.sh - Mobile playlist management and last-played tracking
# Usage: musiclib_mobile.sh upload <playlist.audpl> [device_id]
#        musiclib_mobile.sh update-lastplayed <playlist_name>
#        musiclib_mobile.sh status
#
# Backend API Version: 1.1
# Exit Codes: 0 (success), 1 (user/validation error), 2 (system error)
#

set -u
set -o pipefail
VERBOSE="${VERBOSE:-false}"

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$(dirname "$SCRIPT_DIR")}"

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

if ! check_required_tools kdeconnect-cli sed bc; then
    error_exit 2 "Required tools not available" "tools" "kdeconnect-cli, sed, bc"
    exit 2
fi

# Default Audacious playlists directory (can be overridden in config)
AUDACIOUS_PLAYLISTS_DIR="${AUDACIOUS_PLAYLISTS_DIR:-$HOME/.config/audacious/playlists}"

#############################################
# Mobile-specific logging
#############################################
MOBILE_LOG_DIR="$MUSICLIB_ROOT/logs/mobile"
MOBILE_LOG_FILE="$MOBILE_LOG_DIR/mobile_operations.log"

# Ensure log directory exists
mkdir -p "$MOBILE_LOG_DIR"

# Mobile logging function
mobile_log() {
    local level="$1"
    local operation="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] [$operation] $message" >> "$MOBILE_LOG_FILE"
    
    # Also use main log_message if available
    if command -v log_message >/dev/null 2>&1; then
        log_message "[MOBILE] [$operation] $message"
    fi
}

# Rotate mobile log if it exceeds 10MB
rotate_mobile_log() {
    if [ -f "$MOBILE_LOG_FILE" ]; then
        local size=$(stat -c%s "$MOBILE_LOG_FILE" 2>/dev/null || echo 0)
        if [ $size -gt 10485760 ]; then  # 10MB
            local timestamp=$(date '+%Y%m%d_%H%M%S')
            mv "$MOBILE_LOG_FILE" "${MOBILE_LOG_FILE}.${timestamp}"
            mobile_log "INFO" "ROTATE" "Log rotated to mobile_operations.log.${timestamp}"
            
            # Keep only last 5 rotated logs
            ls -t "${MOBILE_LOG_FILE}".* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
        fi
    fi
}

# Rotate log at startup
rotate_mobile_log

#############################################
# Playlist sync functions
#############################################

# Check if Audacious version of a playlist is newer than Musiclib version
# Arguments: $1 = playlist name (with or without .audpl extension)
# Returns: 0 if newer or new, 1 if same/older/not found
# Sets global variables: PLAYLIST_STATUS, AUDACIOUS_SOURCE_FILE, AUDACIOUS_TITLE
check_playlist_updates() {
    local playlist_input="$1"
    
    # Strip .audpl extension if present for comparison
    local playlist_name="${playlist_input%.audpl}"
    
    # Safety check for Audacious playlists directory
    if [[ ! -d "$AUDACIOUS_PLAYLISTS_DIR" ]]; then
        [ "$VERBOSE" = true ] && echo "Audacious playlists directory not found: $AUDACIOUS_PLAYLISTS_DIR"
        PLAYLIST_STATUS="not_found"
        return 1
    fi
    
    # Musiclib playlist file path
    local musiclib_file="$PLAYLISTS_DIR/${playlist_name}.audpl"
    
    shopt -s nullglob
    for file in "$AUDACIOUS_PLAYLISTS_DIR"/*.audpl; do
        # Read first line only
        local first_line=$(head -n 1 "$file" 2>/dev/null)
        
        if [[ -z "$first_line" || "$first_line" != title=* ]]; then
            continue
        fi
        
        # Extract everything after title=
        local title_raw="${first_line#title=}"
        
        # If empty after extraction, skip
        [[ -z "$title_raw" ]] && continue
        
        # Basic URL-decode (handles %20 → space, %21 → !, etc.)
        local title_decoded=$(printf '%b' "${title_raw//%/\\x}")
        
        # Sanitize: replace any non-alphanumeric (except - _ .) with _
        local title_safe=$(echo "$title_decoded" | tr -s '[:space:][:punct:]' '_' | tr -d '\000-\037' | sed 's/__*/_/g; s/^_//; s/_$//')
        
        # If after sanitization we have nothing useful, use basename
        if [[ -z "$title_safe" ]]; then
            title_safe=$(basename "$file" .audpl)
        fi
        
        # Check if this matches the playlist we're looking for (case-insensitive)
        if [[ "${title_safe,,}" == "${playlist_name,,}" ]]; then
            # Found matching playlist in Audacious
            AUDACIOUS_SOURCE_FILE="$file"
            AUDACIOUS_TITLE="$title_decoded"
            
            # Check if Musiclib version exists
            if [[ ! -f "$musiclib_file" ]]; then
                PLAYLIST_STATUS="new"
                return 0
            fi
            
            # Compare modification times
            local audacious_mtime=$(stat -c%Y "$file" 2>/dev/null || echo 0)
            local musiclib_mtime=$(stat -c%Y "$musiclib_file" 2>/dev/null || echo 0)
            
            if [[ $audacious_mtime -gt $musiclib_mtime ]]; then
                PLAYLIST_STATUS="newer"
                return 0
            else
                PLAYLIST_STATUS="same"
                return 1
            fi
        fi
    done
    shopt -u nullglob
    
    # Playlist not found in Audacious
    PLAYLIST_STATUS="not_found"
    return 1
}

# Copy a single playlist from Audacious to Musiclib
# Uses global variables set by check_playlist_updates(): AUDACIOUS_SOURCE_FILE, AUDACIOUS_TITLE
scan_single_playlist() {
    if [[ -z "${AUDACIOUS_SOURCE_FILE:-}" ]]; then
        echo "Error: No source file set. Run check_playlist_updates first."
        return 1
    fi
    
    # Create destination directory if it doesn't exist
    mkdir -p "$PLAYLISTS_DIR" || { echo "Error: Cannot create $PLAYLISTS_DIR"; return 1; }
    
    # Read first line to get title
    local first_line=$(head -n 1 "$AUDACIOUS_SOURCE_FILE" 2>/dev/null)
    local title_raw="${first_line#title=}"
    
    # URL-decode
    local title_decoded=$(printf '%b' "${title_raw//%/\\x}")
    
    # Sanitize for filename
    local title_safe=$(echo "$title_decoded" | tr -s '[:space:][:punct:]' '_' | tr -d '\000-\037' | sed 's/__*/_/g; s/^_//; s/_$//')
    
    if [[ -z "$title_safe" ]]; then
        title_safe=$(basename "$AUDACIOUS_SOURCE_FILE" .audpl)
    fi
    
    local dest="$PLAYLISTS_DIR/$title_safe.audpl"
    
    # Copy with preserve attributes
    cp -vp "$AUDACIOUS_SOURCE_FILE" "$dest"
    
    mobile_log "INFO" "PLAYLIST_SYNC" "Copied playlist from Audacious: $title_safe"
    echo "Playlist copied: $title_safe.audpl"
    
    return 0
}

# Scan and process all Audacious playlists (full sync)
scan_playlists() {
    echo "=== Scanning and processing Audacious playlists ==="
    
    # Create destination directory if it doesn't exist
    mkdir -p "$PLAYLISTS_DIR" || { echo "Error: Cannot create $PLAYLISTS_DIR"; exit 1; }
    
    # Safety check
    if [[ ! -d "$AUDACIOUS_PLAYLISTS_DIR" ]]; then
        echo "Error: Source directory $AUDACIOUS_PLAYLISTS_DIR not found."
        exit 1
    fi
    
    shopt -s nullglob  # so the loop doesn't run if no files
    local count=0
    
    for file in "$AUDACIOUS_PLAYLISTS_DIR"/*.audpl; do
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
        dest="$PLAYLISTS_DIR/$title_safe.audpl"
        
        # Copy with verbose + preserve attributes (overwrites if exists)
        cp -vp "$file" "$dest"
        ((count++))
    done
    
    shopt -u nullglob
    
    echo ""
    echo "Scan complete! Processed $count playlist files to $PLAYLISTS_DIR"
    mobile_log "INFO" "PLAYLIST_SYNC" "Full sync completed: $count playlists"
}

#############################################
# Upload playlist to Android via KDE Connect
#############################################
upload_playlist() {
    local audpl_input="$1"
    local device_id="${2:-$DEVICE_ID}"

    # Construct full path to playlist file
    # If input is already an absolute path, use it; otherwise prepend PLAYLISTS_DIR
    local audpl_file
    if [[ "$audpl_input" == /* ]]; then
        # Absolute path provided
        audpl_file="$audpl_input"
    else
        # Relative filename - look in PLAYLISTS_DIR
        audpl_file="$PLAYLISTS_DIR/$audpl_input"
    fi

    # Extract playlist name for checking updates
    local playlist_name=$(basename "$audpl_file" .audpl)

    # Validate dependencies
    if ! validate_dependencies; then
        error_exit 2 "Dependencies validation failed"
        exit 2
    fi

    #############################################
    # Check for playlist updates from Audacious
    #############################################
    if check_playlist_updates "$playlist_name"; then
        case "$PLAYLIST_STATUS" in
            newer)
                echo ""
                echo "Audacious version of '$playlist_name' is newer than Musiclib copy."
                read -p "Refresh from Audacious? [y/N] " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    scan_single_playlist
                    echo ""
                    read -p "Continue with upload? [Y/n] " -n 1 -r
                    echo ""
                    if [[ $REPLY =~ ^[Nn]$ ]]; then
                        echo "Upload cancelled. Playlist was refreshed."
                        mobile_log "INFO" "UPLOAD" "User refreshed playlist but cancelled upload: $playlist_name"
                        exit 0
                    fi
                fi
                ;;
            new)
                echo ""
                echo "This is a new Audacious playlist."
                read -p "Copy now and proceed with upload? [y/N] " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    scan_single_playlist
                    # Update audpl_file to point to newly copied file
                    audpl_file="$PLAYLISTS_DIR/${playlist_name}.audpl"
                else
                    echo "Upload cancelled. Playlist not copied."
                    mobile_log "INFO" "UPLOAD" "User declined to copy new playlist: $playlist_name"
                    exit 0
                fi
                ;;
        esac
    fi
    # If same, older, or not found in Audacious, continue with upload

    mobile_log "INFO" "UPLOAD" "Starting upload: $(basename "$audpl_file")"
    mobile_log "INFO" "UPLOAD" "Device ID: $device_id"

    # Check if file exists
    if [ ! -f "$audpl_file" ]; then
        mobile_log "ERROR" "UPLOAD" "File not found: $audpl_file"
        error_exit 1 "File not found" "file" "$audpl_file"
        exit 1
    fi

    # Get basename without extension
    local basename=$(basename "$audpl_file" .audpl)
    local temp_dir=$(mktemp -d)
    local output_m3u="$temp_dir/${basename}.m3u"

    # Check if device is reachable
    if ! $KDECONNECT_CMD -d "$device_id" --ping >/dev/null 2>&1; then
        mobile_log "ERROR" "TRANSFER" "Device unreachable: $device_id"
        rm -rf "$temp_dir"
        error_exit 2 "Device unreachable via KDE Connect" "device_id" "$device_id"
        exit 2
    fi

    echo "Preparing to transfer files to Android..."
    echo ""
    echo "IMPORTANT: Please manually delete old music files from your phone's Downloads folder now."
    echo "Press Enter when ready to continue with upload..."
    read -r
    echo ""

    # Extract file paths and prepare file list
    echo "Preparing files for transfer..."
    local temp_transfer="$temp_dir/files_to_transfer.txt"

    grep "^uri=file://" "$audpl_file" | while read line; do
        # Remove "uri=file://" prefix
        local file_path="${line#uri=file://}"

        # URL decode the path
        file_path=$(printf '%b' "${file_path//%/\\x}")

        if [ -f "$file_path" ]; then
            echo "$file_path"
        else
            echo "  Warning: File not found: $file_path" >&2
        fi
    done > "$temp_transfer"

    # Create .m3u playlist with only filenames
    echo "Creating playlist..."
    grep "^uri=file://" "$audpl_file" | while read line; do
        local file_path="${line#uri=file://}"
        file_path=$(printf '%b' "${file_path//%/\\x}")
        if [ -f "$file_path" ]; then
            basename "$file_path"
        fi
    done > "$output_m3u"

    # Transfer playlist first
    echo "Transferring playlist: ${basename}.m3u"
    $KDECONNECT_CMD -d "$device_id" --share "$output_m3u"

    # Transfer music files
    echo "Transferring music files..."
    local transferred=0
    local total=$(wc -l < "$temp_transfer")
    
    # Calculate total size for logging
    local total_size=0
    while IFS= read -r file_path; do
        if [ -f "$file_path" ]; then
            total_size=$((total_size + $(stat -c%s "$file_path" 2>/dev/null || echo 0)))
        fi
    done < "$temp_transfer"
    local total_size_mb=$(echo "scale=1; $total_size / 1048576" | bc)

    while IFS= read -r file_path; do
        transferred=$((transferred + 1))
        echo "  [$transferred/$total] Transferring: $(basename "$file_path")"
        $KDECONNECT_CMD -d "$device_id" --share "$file_path"
    done < "$temp_transfer"
    
    mobile_log "INFO" "UPLOAD" "Transferred $total tracks (${total_size_mb} MB)"

    # Save track list for mobile last-played tracking
    local tracks_file="$MOBILE_DIR/${basename}.tracks"
    cp "$temp_transfer" "$tracks_file" 2>/dev/null

    # Cleanup temp directory
    rm -rf "$temp_dir"

    # Save upload timestamp
    local meta_file="$MOBILE_DIR/${basename}.meta"
    date +%s > "$meta_file"

    # Update last-played times for previous playlist
    update_lastplayed_workflow "$basename"

    echo ""
    echo "Transfer complete!"
    echo "  Playlist: ${basename}.m3u"
    echo "  Files transferred: $total"
    echo "  Location on phone: Downloads folder"

    mobile_log "INFO" "UPLOAD" "Upload complete: ${basename}.m3u ($total tracks)"
    log_message "Uploaded playlist to mobile: $basename ($total tracks)"
}

#############################################
# Update last-played times for mobile playlist
#############################################
update_lastplayed_workflow() {
    local skipped_notindb=0
    local new_playlist="$1"

    if ! validate_database "$MUSICDB"; then
        error_exit 2 "Database validation failed" "database" "$MUSICDB"
        exit 2
    fi

    local current_playlist_file="$CURRENT_PLAYLIST_FILE"

    # Check if there's a previous playlist to process
    if [ ! -f "$current_playlist_file" ]; then
        # First time - just set current playlist
        echo "$new_playlist" > "$current_playlist_file"
        echo "Mobile playlist tracking initialized: $new_playlist"
        mobile_log "INFO" "INIT" "Mobile playlist tracking initialized: $new_playlist"
        log_message "Initialized mobile tracking: $new_playlist"
        return 0
    fi

    local prev_playlist=$(cat "$current_playlist_file")

    # If same playlist, nothing to do
    if [ "$prev_playlist" = "$new_playlist" ]; then
        echo "Same playlist - no last-played updates needed"
        mobile_log "INFO" "SKIP" "Same playlist uploaded: $new_playlist"
        return 0
    fi

    # Process the previous playlist
    echo "Processing mobile last-played times for playlist: $prev_playlist"
    mobile_log "INFO" "PROCESS" "Processing previous playlist: $prev_playlist"

    local prev_meta="$MOBILE_DIR/${prev_playlist}.meta"
    local prev_tracks="$MOBILE_DIR/${prev_playlist}.tracks"

    # Check if previous playlist metadata exists
    if [ ! -f "$prev_meta" ] || [ ! -f "$prev_tracks" ]; then
        echo "Warning: Metadata not found for previous playlist $prev_playlist"
        mobile_log "WARN" "METADATA" "Metadata files missing for: $prev_playlist"
        echo "$new_playlist" > "$current_playlist_file"
        return 0
    fi

    # Get time window
    local start_epoch=$(cat "$prev_meta")
    local end_epoch=$(date +%s)
    
    # Safety check: Detect clock skew
    if [ $start_epoch -gt $end_epoch ]; then
        mobile_log "ERROR" "UPDATE_LASTPLAYED" "Clock skew detected (start=$start_epoch, end=$end_epoch)"
        error_exit 2 "Clock skew detected - start time in future" "start_epoch" "$start_epoch" "end_epoch" "$end_epoch"
        exit 2
    fi
    
    local window=$((end_epoch - start_epoch))

    # Check if window is reasonable (at least 1 minute, max 90 days)
    if [ $window -lt 60 ]; then
        echo "Warning: Time window too short ($window seconds), skipping update"
        mobile_log "WARN" "WINDOW" "Time window too short: $window seconds"
        echo "$new_playlist" > "$current_playlist_file"
        return 0
    fi

    if [ $window -gt 7776000 ]; then  # 90 days
        echo "Warning: Time window suspiciously long ($(($window / 86400)) days)"
        mobile_log "WARN" "WINDOW" "Time window very long: $(($window / 86400)) days"
    fi

    echo "Time window: $(($window / 86400)) days, $(($window % 86400 / 3600)) hours"
    [ "$VERBOSE" = true ] && echo "Start: $(date -d @$start_epoch '+%Y-%m-%d %H:%M:%S')"
    [ "$VERBOSE" = true ] && echo "End:   $(date -d @$end_epoch '+%Y-%m-%d %H:%M:%S')"

    # Acquire database lock before processing tracks
    if ! acquire_db_lock 5; then
        mobile_log "ERROR" "LOCK" "Failed to acquire database lock"
        error_exit 2 "Database lock timeout" "timeout" "5 seconds" "database" "$MUSICDB"
        exit 2
    fi

    # Read track list
    local track_num=0
    local updated=0
    local skipped=0

    echo "Processing tracks..."

    while IFS= read -r filepath; do
        track_num=$((track_num + 1))
        [ "$VERBOSE" = true ] && echo "  Processing track $track_num: $(basename "$filepath")"

        # Check if track exists in database
        if ! grep -qF "$filepath" "$MUSICDB" 2>/dev/null; then
            echo "  ⚠ Track not in database: $(basename "$filepath")"
            mobile_log "ERROR" "NOTINDB" "Track not in database: $filepath"
            skipped_notindb=$((skipped_notindb + 1))
            continue
        fi

        # Get LastTimePlayed column number
        local lpcolnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep "LastTimePlayed" | sed -r 's/^([^.]+).*$/\1/; s/^[^0-9]*([0-9]+).*$/\1/')

        if [ -z "$lpcolnum" ]; then
            mobile_log "ERROR" "COLUMN" "LastTimePlayed column not found"
            release_db_lock
            error_exit 2 "Database schema error - LastTimePlayed column not found"
            exit 2
        fi

        # Get current last-played value
        local grepped_string=$(grep -nF "$filepath" "$MUSICDB" 2>/dev/null)
        if [ -z "$grepped_string" ]; then
            continue
        fi

        local myrow=$(echo "$grepped_string" | cut -f1 -d:)
        local current_lp=$(echo "$grepped_string" | cut -f"$lpcolnum" -d"^" | xargs)

        # Parse current last-played time (SQL serial format)
        local current_epoch=0
        if [ -n "$current_lp" ] && [ "$current_lp" != "0" ]; then
            # Convert SQL serial time to epoch: (sql_time - 25569) * 86400
            current_epoch=$(echo "($current_lp - 25569) * 86400" | bc | cut -d. -f1)
        fi

        # Check if desktop last-played is within mobile window
        if [ $current_epoch -ge $start_epoch ] && [ $current_epoch -le $end_epoch ]; then
            # Desktop timestamp is more recent and within the window - preserve it
            [ "$VERBOSE" = true ] && echo "  ✓ Preserving desktop timestamp: $(date -d @$current_epoch '+%Y-%m-%d %H:%M:%S')"
            skipped=$((skipped + 1))
            continue
        fi

        # Generate synthetic timestamp within the window
        # Distribute evenly: start + (window * track_position / total_tracks)
        local offset=$(echo "scale=0; $window * $track_num / $(wc -l < "$prev_tracks")" | bc)
        local synthetic_epoch=$((start_epoch + offset))
        local synthetic_sql=$(epoch_to_sql_time $synthetic_epoch)

        [ "$VERBOSE" = true ] && echo "  → Applying synthetic: $(date -d @$synthetic_epoch '+%Y-%m-%d %H:%M:%S')"

        # Update database
        if ! awk -F'^' -v OFS='^' -v row="$myrow" -v col="$lpcolnum" -v newval="$synthetic_sql" \
            'NR == row { $col = newval } { print }' \
            "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then
            echo "  ✗ Database update failed: $(basename "$filepath")"
            mobile_log "ERROR" "DBUPDATE" "Database update failed: $filepath"
            rm -f "$MUSICDB.tmp"
            continue
        fi
        mv "$MUSICDB.tmp" "$MUSICDB"

        # Update tag using kid3-cli with repair on failure
        if ! $KID3_CMD -c "set Songs-DB_Custom1 $synthetic_sql" "$filepath" 2>/dev/null; then
            log_message "Tag write failed for Songs-DB_Custom1, attempting repair..."
            # rebuild_tag is called from musiclib_utils_tag_functions.sh
            if command -v rebuild_tag >/dev/null 2>&1 && rebuild_tag "$filepath"; then
                log_message "Tag rebuild successful, retrying write..."
                # Retry the tag write after rebuild
                if ! $KID3_CMD -c "set Songs-DB_Custom1 $synthetic_sql" "$filepath" 2>/dev/null; then
                    echo "  ✗ Tag write failed after rebuild: $(basename "$filepath")"
                    log_message "ERROR: Tag write still failed after rebuild for $filepath"
                    mobile_log "ERROR" "TAGWRITE" "Tag write failed after rebuild: $filepath"
                    continue
                fi
                log_message "Tag write successful after rebuild"
            else
                echo "  ✗ Tag rebuild failed: $(basename "$filepath")"
                log_message "ERROR: Tag rebuild failed or unavailable for $filepath"
                mobile_log "ERROR" "TAGREBUILD" "Tag rebuild failed: $filepath"
                continue
            fi
        fi

        updated=$((updated + 1))

    done < "$prev_tracks"

    # Release database lock
    release_db_lock

    # Display summary
    echo ""
    echo "Last-played update summary:"
    echo "  Total tracks in playlist: $track_num"
    echo "  Synthetic timestamps applied: $updated"
    echo "  Desktop timestamps preserved: $skipped"
    if [ $((track_num - updated - skipped)) -gt 0 ]; then
        echo "  Skipped (missing/error): $((track_num - updated - skipped))"
    fi
    
    mobile_log "STATS" "SUMMARY" "Total: $track_num, Updated: $updated, Preserved: $skipped, Errors: $((track_num - updated - skipped))"

    # Update current playlist marker
    echo "$new_playlist" > "$current_playlist_file"
    echo "Current mobile playlist set to: $new_playlist"
    mobile_log "INFO" "COMPLETE" "Current playlist set to: $new_playlist"

    # Clean up old metadata files after successful processing
    if [ -f "$prev_meta" ]; then
        rm -f "$prev_meta"
        [ "$VERBOSE" = true ] && echo "Cleaned up: ${prev_playlist}.meta"
    fi

    if [ -f "$prev_tracks" ]; then
        rm -f "$prev_tracks"
        [ "$VERBOSE" = true ] && echo "Cleaned up: ${prev_playlist}.tracks"
    fi
    
    mobile_log "INFO" "CLEANUP" "Removed metadata: ${prev_playlist}.meta/.tracks"

    log_message "Updated mobile last-played: $prev_playlist ($updated tracks)"
    echo ""
    echo "Completed mobile last-played update:"
    echo "  Total tracks in playlist: $track_num"
    echo "  Synthetic timestamps applied: $updated"
    echo "  Desktop timestamps preserved: $skipped"
    if [ "$skipped_notindb" -gt 0 ]; then
        echo "  ⚠  Not in database (skipped): $skipped_notindb"
        echo ""
        echo "To track these files, import them first with:"
        echo "  musiclib_new_tracks.sh [artist name]"
    fi
}

#############################################
# Main command dispatcher
#############################################
show_usage() {
    cat << EOF
Usage: musiclib_mobile.sh <command> [arguments]

Commands:
  upload <playlist.audpl> [device_id]
      Transfer playlist and music files to Android via KDE Connect
      Checks if Audacious version is newer and offers to refresh first

  refresh-audacious-only
      Refresh all playlists from Audacious to Musiclib playlists directory
      No mobile upload is performed

  update-lastplayed <playlist_name>
      Manually trigger last-played time updates for a playlist

  status
      Show current mobile playlist tracking status

  logs [filter]
      View mobile operations log
      Filters: errors, warnings, stats, today

  cleanup
      Remove orphaned metadata files from mobile directory

Examples:
  musiclib_mobile.sh upload ~/music/workout.audpl
  musiclib_mobile.sh upload workout.audpl
  musiclib_mobile.sh refresh-audacious-only
  musiclib_mobile.sh update-lastplayed workout
  musiclib_mobile.sh status
  musiclib_mobile.sh logs
  musiclib_mobile.sh logs errors
  musiclib_mobile.sh cleanup

Configuration:
  AUDACIOUS_PLAYLISTS_DIR - Audacious playlists location
                           (default: ~/.local/share/audacious/playlists)

EOF
}

# Command dispatcher
COMMAND="${1:-}"

case "$COMMAND" in
    upload)
        if [ $# -lt 2 ]; then
            show_usage
            error_exit 1 "Missing playlist file argument"
            exit 1
        fi
        upload_playlist "$2" "${3:-}"
        ;;

    refresh-audacious-only)
        scan_playlists
        ;;

    update-lastplayed)
        if [ $# -lt 2 ]; then
            show_usage
            error_exit 1 "Missing playlist name argument"
            exit 1
        fi
        update_lastplayed_workflow "$2"
        ;;

    status)
        if [ -f "$CURRENT_PLAYLIST_FILE" ]; then
            current=$(cat "$CURRENT_PLAYLIST_FILE")
            echo "Current mobile playlist: $current"

            if [ -f "$MOBILE_DIR/${current}.meta" ]; then
                upload_time=$(cat "$MOBILE_DIR/${current}.meta")
                upload_date=$(date -d "@$upload_time" '+%Y-%m-%d %H:%M:%S')
                days_ago=$(( ($(date +%s) - upload_time) / 86400 ))
                echo "Uploaded: $upload_date ($days_ago days ago)"
            fi

            if [ -f "$MOBILE_DIR/${current}.tracks" ]; then
                track_count=$(wc -l < "$MOBILE_DIR/${current}.tracks")
                echo "Tracks: $track_count"
            fi

            # Show orphaned files
            echo ""
            echo "Metadata files in mobile directory:"
            meta_count=$(find "$MOBILE_DIR" -name "*.meta" -o -name "*.tracks" 2>/dev/null | wc -l)
            if [ "$meta_count" -gt 2 ]; then
                echo "  Warning: $meta_count metadata files found (expected 2)"
                echo "  Run 'musiclib_mobile.sh cleanup' to remove orphaned files"
            else
                echo "  $meta_count files (clean)"
            fi
            
            # Show log information
            if [ -f "$MOBILE_LOG_FILE" ]; then
                echo ""
                echo "Mobile operations log:"
                echo "  Location: $MOBILE_LOG_FILE"
                log_size=$(stat -c%s "$MOBILE_LOG_FILE" 2>/dev/null || echo 0)
                log_size_kb=$((log_size / 1024))
                echo "  Size: ${log_size_kb} KB"
                
                echo ""
                echo "Recent operations (last 5):"
                tail -5 "$MOBILE_LOG_FILE" | while read line; do
                    echo "  $line"
                done
            fi
        else
            echo "No mobile playlist currently active"
        fi
        ;;

    logs)
        if [ ! -f "$MOBILE_LOG_FILE" ]; then
            echo "No mobile operations log found"
            echo "Location: $MOBILE_LOG_FILE"
            exit 0
        fi
        
        case "${2:-}" in
            "")
                # Show last 50 lines
                echo "Recent mobile operations (last 50 lines):"
                echo ""
                tail -50 "$MOBILE_LOG_FILE"
                ;;
            errors)
                echo "Recent errors:"
                echo ""
                grep "\[ERROR\]" "$MOBILE_LOG_FILE" | tail -20
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    echo "No errors found in log"
                fi
                ;;
            warnings)
                echo "Recent warnings:"
                echo ""
                grep "\[WARN\]" "$MOBILE_LOG_FILE" | tail -20
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    echo "No warnings found in log"
                fi
                ;;
            stats)
                echo "Recent statistics:"
                echo ""
                grep "\[STATS\]" "$MOBILE_LOG_FILE" | tail -10
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    echo "No statistics found in log"
                fi
                ;;
            today)
                today=$(date '+%Y-%m-%d')
                echo "Operations from today ($today):"
                echo ""
                grep "$today" "$MOBILE_LOG_FILE"
                if [ $? -ne 0 ]; then
                    echo "No operations logged today"
                fi
                ;;
            *)
                error_exit 1 "Unknown logs filter" "filter" "$2"
                exit 1
                ;;
        esac
        ;;

    cleanup)
        echo "Cleaning up orphaned mobile metadata files..."

        if [ ! -f "$CURRENT_PLAYLIST_FILE" ]; then
            echo "No current playlist set - nothing to clean"
            exit 0
        fi

        current=$(cat "$CURRENT_PLAYLIST_FILE")
        echo "Current playlist: $current"
        echo "Keeping: ${current}.meta and ${current}.tracks"
        echo ""

        removed=0
        for file in "$MOBILE_DIR"/*.meta "$MOBILE_DIR"/*.tracks; do
            if [ -f "$file" ]; then
                basename=$(basename "$file")
                # Skip current playlist files
                if [[ "$basename" != "${current}.meta" ]] && [[ "$basename" != "${current}.tracks" ]]; then
                    echo "Removing: $basename"
                    rm -f "$file"
                    removed=$((removed + 1))
                fi
            fi
        done

        echo ""
        if [ "$removed" -eq 0 ]; then
            echo "No orphaned files found"
        else
            echo "Removed $removed orphaned file(s)"
        fi
        ;;

    "")
        show_usage
        error_exit 1 "No command specified"
        exit 1
        ;;

    *)
        show_usage
        error_exit 1 "Unknown command" "command" "$COMMAND"
        exit 1
        ;;
esac
