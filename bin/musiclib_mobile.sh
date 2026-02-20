#!/bin/bash
#
# musiclib_mobile.sh - Mobile playlist management and last-played tracking
#
# Usage: musiclib_mobile.sh upload <playlist.audpl> [device_id] [--non-interactive] [--end-time "MM/DD/YYYY HH:MM:SS"]
#        musiclib_mobile.sh update-lastplayed <playlist_name> [--end-time "MM/DD/YYYY HH:MM:SS"]
#        musiclib_mobile.sh retry <playlist_name>
#        musiclib_mobile.sh refresh-audacious-only
#        musiclib_mobile.sh status
#        musiclib_mobile.sh logs [filter]
#        musiclib_mobile.sh cleanup
#
# Backend API Version: 1.0
# Exit Codes: 0 (success), 1 (user/validation error), 2 (system error)
#
# Workflow (upload):
#   Phase A - Accounting (device-independent):
#     1. Validate playlist file
#     2. Check for Audacious playlist updates (refresh if newer)
#     3. Check for previous playlist; if exists, process synthetic last-played
#     4. On partial failure: write .pending_tracks or .failed, preserve metadata
#     5. On full success: clean up previous playlist metadata
#   Phase B - Upload (device-required):
#     6. Hard device connectivity check
#     7. Log new playlist as current, write .meta and .tracks
#     8. Transfer .m3u + all track files via kdeconnect-cli --share
#
# Output contract:
#   stdout: Prefixed progress lines (ACCOUNTING: / UPLOAD:)
#   stderr: JSON errors per Backend API v1.0
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
# Global flags (parsed from command line)
#############################################
NON_INTERACTIVE=false
END_TIME_OVERRIDE=""

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

        # Basic URL-decode (handles %20 -> space, %21 -> !, etc.)
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

        # If empty after extraction, skip
        [[ -z "$title_raw" ]] && {
            echo "Skipping $file  (empty title)"
            continue
        }

        # Basic URL-decode first (handles %20 -> space, %21 -> !, etc.)
        title_decoded=$(printf '%b' "${title_raw//%/\\x}")

        # Sanitize: replace any non-alphanumeric (except - _ .) with _
        # This catches spaces, !@#$%^&*()+= etc.
        title_safe=$(echo "$title_decoded" | tr -s '[:space:][:punct:]' '_' | tr -d '\000-\037' | sed 's/__*/_/g; s/^_//; s/_$//')

        # If after sanitization we have nothing useful, fallback to basename
        if [[ -z "$title_safe" ]]; then
            title_safe=$(basename "$file" .audpl)
            echo "Warning: Empty/unsafe title in $file -> using basename $title_safe"
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
# Phase A: Accounting - process previous playlist
#############################################

# Process synthetic last-played timestamps for the previous playlist.
# This is the accounting phase — no device connectivity required.
#
# Args:
#   $1 - new playlist name (basename without extension)
#   $2 - end timestamp (epoch seconds) for the time window
#
# Returns:
#   0 - all tracks processed successfully (or no previous playlist)
#   1 - partial failure: .pending_tracks or .failed written
#   2 - system error (DB lock, schema error, etc.)
#
# Side effects on partial failure:
#   Writes $MOBILE_DIR/<prev_playlist>.pending_tracks  (tracks not in DB)
#   Writes $MOBILE_DIR/<prev_playlist>.failed          (DB/tag write failures)
#   Does NOT delete previous playlist .meta/.tracks
#
process_previous_playlist() {
    local new_playlist="$1"
    local end_epoch="$2"
    local skipped_notindb=0

    if ! validate_database "$MUSICDB"; then
        error_exit 2 "Database validation failed" "database" "$MUSICDB"
        return 2
    fi

    local current_playlist_file="$CURRENT_PLAYLIST_FILE"

    # Check if there's a previous playlist to process
    if [ ! -f "$current_playlist_file" ]; then
        # First time — just log and return success
        echo "ACCOUNTING: No previous playlist found — first-time initialization"
        mobile_log "INFO" "INIT" "No previous playlist — first-time setup"
        return 0
    fi

    local prev_playlist=$(cat "$current_playlist_file")

    # If same playlist, nothing to do
    if [ "$prev_playlist" = "$new_playlist" ]; then
        echo "ACCOUNTING: Same playlist selected — no accounting needed"
        mobile_log "INFO" "SKIP" "Same playlist uploaded: $new_playlist"
        return 0
    fi

    echo "ACCOUNTING: Processing previous playlist: $prev_playlist"
    mobile_log "INFO" "PROCESS" "Processing previous playlist: $prev_playlist"

    local prev_meta="$MOBILE_DIR/${prev_playlist}.meta"
    local prev_tracks="$MOBILE_DIR/${prev_playlist}.tracks"

    # Check if previous playlist metadata exists
    if [ ! -f "$prev_meta" ] || [ ! -f "$prev_tracks" ]; then
        echo "ACCOUNTING: Warning — metadata not found for previous playlist $prev_playlist"
        mobile_log "WARN" "METADATA" "Metadata files missing for: $prev_playlist"
        return 0
    fi

    # Get time window
    local start_epoch=$(cat "$prev_meta")

    # Safety check: Detect clock skew
    if [ "$start_epoch" -gt "$end_epoch" ]; then
        mobile_log "ERROR" "ACCOUNTING" "Clock skew detected (start=$start_epoch, end=$end_epoch)"
        error_exit 2 "Clock skew detected — start time is in the future" "start_epoch" "$start_epoch" "end_epoch" "$end_epoch"
        return 2
    fi

    local window=$((end_epoch - start_epoch))

    # Check if window is reasonable (at least MIN_PLAY_WINDOW, max MOBILE_WINDOW_DAYS)
    local min_window="${MIN_PLAY_WINDOW:-3600}"
    local max_window_seconds=$(( ${MOBILE_WINDOW_DAYS:-40} * 86400 ))

    if [ "$window" -lt "$min_window" ]; then
        echo "ACCOUNTING: Warning — time window too short ($window seconds < ${min_window}s minimum), skipping"
        mobile_log "WARN" "WINDOW" "Time window too short: $window seconds"
        return 0
    fi

    if [ "$window" -gt "$max_window_seconds" ]; then
        echo "ACCOUNTING: Warning — time window is $(($window / 86400)) days (max configured: ${MOBILE_WINDOW_DAYS:-40} days)"
        mobile_log "WARN" "WINDOW" "Time window very long: $(($window / 86400)) days"
    fi

    echo "ACCOUNTING: Time window: $(($window / 86400)) days, $(($window % 86400 / 3600)) hours"
    echo "ACCOUNTING: Start: $(date -d "@$start_epoch" '+%m/%d/%Y %H:%M:%S')"
    echo "ACCOUNTING: End:   $(date -d "@$end_epoch" '+%m/%d/%Y %H:%M:%S')"

    # Acquire database lock before processing tracks
    if ! acquire_db_lock 5; then
        mobile_log "ERROR" "LOCK" "Failed to acquire database lock"
        error_exit 2 "Database lock timeout" "timeout" "5 seconds" "database" "$MUSICDB"
        return 2
    fi

    # Read track list
    local track_num=0
    local total_tracks=$(wc -l < "$prev_tracks")
    local updated=0
    local skipped_desktop=0
    local failed_count=0

    # Prepare recovery files (write to temp, move on completion)
    local pending_file="$MOBILE_DIR/${prev_playlist}.pending_tracks"
    local failed_file="$MOBILE_DIR/${prev_playlist}.failed"
    local temp_pending=$(mktemp)
    local temp_failed=$(mktemp)

    echo "ACCOUNTING: Processing $total_tracks tracks..."

    # Get LastTimePlayed column number (once, outside the loop)
    local lpcolnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep "LastTimePlayed" | sed -r 's/^([^.]+).*$/\1/; s/^[^0-9]*([0-9]+).*$/\1/')

    if [ -z "$lpcolnum" ]; then
        mobile_log "ERROR" "COLUMN" "LastTimePlayed column not found"
        release_db_lock
        rm -f "$temp_pending" "$temp_failed"
        error_exit 2 "Database schema error — LastTimePlayed column not found"
        return 2
    fi

    while IFS= read -r filepath; do
        track_num=$((track_num + 1))

        # Check if track exists in database
        if ! grep -qF "$filepath" "$MUSICDB" 2>/dev/null; then
            # --- FAILURE POINT 1: Track not in database ---
            # Calculate what the synthetic timestamp would be so retry can apply it later
            local offset=$(echo "scale=0; $window * $track_num / $total_tracks" | bc)
            local synthetic_epoch=$((start_epoch + offset))
            local synthetic_sql=$(epoch_to_sql_time "$synthetic_epoch")
            local synthetic_human=$(date -d "@$synthetic_epoch" '+%m/%d/%Y %H:%M:%S')

            echo "ACCOUNTING: Track $track_num/$total_tracks: NOT IN DB — $filepath"
            echo "$filepath^$synthetic_sql^$synthetic_human" >> "$temp_pending"
            mobile_log "ERROR" "NOTINDB" "Track not in database: $filepath"

            {
                echo "{\"error\":\"Track not in database\",\"script\":\"musiclib_mobile.sh\",\"code\":1,\"context\":{\"file\":\"$filepath\",\"action\":\"pending\",\"intended_timestamp\":\"$synthetic_human\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
            } >&2

            skipped_notindb=$((skipped_notindb + 1))
            continue
        fi

        # Get current last-played value
        local grepped_string=$(grep -nF "$filepath" "$MUSICDB" 2>/dev/null)
        if [ -z "$grepped_string" ]; then
            continue
        fi

        local myrow=$(echo "$grepped_string" | cut -f1 -d:)
        local row_data=$(echo "$grepped_string" | cut -f2- -d:)
        local current_lp=$(echo "$row_data" | cut -f"$lpcolnum" -d"^" | xargs)

        # Parse current last-played time (SQL serial format)
        local current_epoch=0
        if [ -n "$current_lp" ] && [ "$current_lp" != "0" ]; then
            # Convert SQL serial time to epoch: (sql_time - 25569) * 86400
            current_epoch=$(echo "($current_lp - 25569) * 86400" | bc | cut -d. -f1)
        fi

        # Only update tracks with existing timestamps earlier than the upload date
        # (tracks played on desktop during the mobile window keep their desktop timestamp)
        if [ "$current_epoch" -ge "$start_epoch" ] && [ "$current_epoch" -le "$end_epoch" ]; then
            # Desktop timestamp is within the window — preserve it
            [ "$VERBOSE" = true ] && echo "ACCOUNTING: Track $track_num/$total_tracks: desktop timestamp preserved ($(date -d "@$current_epoch" '+%m/%d/%Y %H:%M:%S'))"
            skipped_desktop=$((skipped_desktop + 1))
            continue
        fi

        # Generate synthetic timestamp within the window
        # Distribute evenly: start + (window * track_position / total_tracks)
        local offset=$(echo "scale=0; $window * $track_num / $total_tracks" | bc)
        local synthetic_epoch=$((start_epoch + offset))
        local synthetic_sql=$(epoch_to_sql_time "$synthetic_epoch")
        local synthetic_human=$(date -d "@$synthetic_epoch" '+%m/%d/%Y %H:%M:%S')

        echo "ACCOUNTING: Track $track_num/$total_tracks: applying synthetic timestamp $synthetic_human"

        # --- FAILURE POINT 2: DB update or tag write failure ---
        # Update database
        if ! awk -F'^' -v OFS='^' -v row="$myrow" -v col="$lpcolnum" -v newval="$synthetic_sql" \
            'NR == row { $col = newval } { print }' \
            "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then

            echo "ACCOUNTING: Track $track_num/$total_tracks: DB UPDATE FAILED — $(basename "$filepath")"
            echo "$filepath^$synthetic_sql^$synthetic_human^db_write_failed" >> "$temp_failed"
            mobile_log "ERROR" "DBUPDATE" "Database update failed: $filepath"

            {
                echo "{\"error\":\"Database update failed\",\"script\":\"musiclib_mobile.sh\",\"code\":2,\"context\":{\"file\":\"$filepath\",\"action\":\"failed\",\"intended_timestamp\":\"$synthetic_human\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
            } >&2

            rm -f "$MUSICDB.tmp"
            failed_count=$((failed_count + 1))
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
                    echo "ACCOUNTING: Track $track_num/$total_tracks: TAG WRITE FAILED (after rebuild) — $(basename "$filepath")"
                    echo "$filepath^$synthetic_sql^$synthetic_human^tag_write_failed_after_rebuild" >> "$temp_failed"
                    mobile_log "ERROR" "TAGWRITE" "Tag write failed after rebuild: $filepath"

                    {
                        echo "{\"error\":\"Tag write failed after rebuild\",\"script\":\"musiclib_mobile.sh\",\"code\":2,\"context\":{\"file\":\"$filepath\",\"action\":\"failed\",\"intended_timestamp\":\"$synthetic_human\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
                    } >&2

                    failed_count=$((failed_count + 1))
                    continue
                fi
                log_message "Tag write successful after rebuild"
            else
                echo "ACCOUNTING: Track $track_num/$total_tracks: TAG REBUILD FAILED — $(basename "$filepath")"
                echo "$filepath^$synthetic_sql^$synthetic_human^tag_rebuild_failed" >> "$temp_failed"
                mobile_log "ERROR" "TAGREBUILD" "Tag rebuild failed: $filepath"

                {
                    echo "{\"error\":\"Tag rebuild failed\",\"script\":\"musiclib_mobile.sh\",\"code\":2,\"context\":{\"file\":\"$filepath\",\"action\":\"failed\",\"intended_timestamp\":\"$synthetic_human\"},\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}"
                } >&2

                failed_count=$((failed_count + 1))
                continue
            fi
        fi

        updated=$((updated + 1))

    done < "$prev_tracks"

    # Release database lock
    release_db_lock

    # --- Post-processing: determine success/partial failure ---
    local has_pending=false
    local has_failed=false

    # Move pending tracks file if it has content
    if [ -s "$temp_pending" ]; then
        mv "$temp_pending" "$pending_file"
        has_pending=true
        echo "ACCOUNTING: Wrote recovery file: $(basename "$pending_file") ($skipped_notindb tracks)"
        mobile_log "WARN" "RECOVERY" "Wrote pending_tracks: $skipped_notindb tracks not in DB"
    else
        rm -f "$temp_pending"
    fi

    # Move failed file if it has content
    if [ -s "$temp_failed" ]; then
        mv "$temp_failed" "$failed_file"
        has_failed=true
        echo "ACCOUNTING: Wrote recovery file: $(basename "$failed_file") ($failed_count tracks)"
        mobile_log "WARN" "RECOVERY" "Wrote failed: $failed_count tracks with write errors"
    else
        rm -f "$temp_failed"
    fi

    # Summary line
    local summary="$updated updated"
    if [ "$skipped_notindb" -gt 0 ]; then
        summary="$summary, $skipped_notindb not-in-db"
    fi
    if [ "$failed_count" -gt 0 ]; then
        summary="$summary, $failed_count failed"
    fi
    if [ "$skipped_desktop" -gt 0 ]; then
        summary="$summary, all others updated on desktop"
    fi

    echo "ACCOUNTING: Complete — $summary"
    mobile_log "STATS" "SUMMARY" "Total: $total_tracks, Updated: $updated, Desktop: $skipped_desktop, NotInDB: $skipped_notindb, Failed: $failed_count"

    # Conditional cleanup: only delete previous metadata if fully successful
    if [ "$has_pending" = false ] && [ "$has_failed" = false ]; then
        # All tracks processed cleanly — safe to remove previous metadata
        if [ -f "$prev_meta" ]; then
            rm -f "$prev_meta"
            [ "$VERBOSE" = true ] && echo "ACCOUNTING: Cleaned up: ${prev_playlist}.meta"
        fi
        if [ -f "$prev_tracks" ]; then
            rm -f "$prev_tracks"
            [ "$VERBOSE" = true ] && echo "ACCOUNTING: Cleaned up: ${prev_playlist}.tracks"
        fi
        mobile_log "INFO" "CLEANUP" "Removed metadata: ${prev_playlist}.meta/.tracks"
        log_message "Updated mobile last-played: $prev_playlist ($updated tracks)"
        return 0
    else
        # Partial failure — preserve metadata for retry
        echo "ACCOUNTING: Previous playlist metadata preserved for retry"
        if [ "$has_pending" = true ]; then
            echo "ACCOUNTING: To resolve not-in-db tracks: import them with musiclib_new_tracks.sh, then run:"
            echo "ACCOUNTING:   musiclib_mobile.sh retry $prev_playlist"
        fi
        if [ "$has_failed" = true ]; then
            echo "ACCOUNTING: To retry failed writes:"
            echo "ACCOUNTING:   musiclib_mobile.sh retry $prev_playlist"
        fi
        mobile_log "WARN" "PARTIAL" "Partial failure — metadata preserved for: $prev_playlist"
        log_message "Partial mobile last-played update: $prev_playlist ($updated of $total_tracks)"
        return 1
    fi
}

#############################################
# Phase B: Upload playlist to Android
#############################################

# Upload playlist files to device via KDE Connect.
# Requires device to be reachable.
#
# Args:
#   $1 - path to playlist file (.audpl)
#   $2 - device ID
#   $3 - new playlist basename (without extension)
#
upload_to_device() {
    local audpl_file="$1"
    local device_id="$2"
    local pl_basename="$3"

    # Hard device connectivity check
    echo "UPLOAD: Checking device connectivity..."
    if ! $KDECONNECT_CMD -d "$device_id" --ping >/dev/null 2>&1; then
        mobile_log "ERROR" "TRANSFER" "Device unreachable: $device_id"
        error_exit 2 "Device unreachable via KDE Connect" "device_id" "$device_id"
        return 2
    fi

    echo "UPLOAD: Device connected"

    local temp_dir=$(mktemp -d)
    local output_m3u="$temp_dir/${pl_basename}.m3u"

    # Extract file paths and prepare file list
    echo "UPLOAD: Preparing files for transfer..."
    local temp_transfer="$temp_dir/files_to_transfer.txt"

    grep "^uri=file://" "$audpl_file" | while read line; do
        # Remove "uri=file://" prefix
        local file_path="${line#uri=file://}"

        # URL decode the path
        file_path=$(printf '%b' "${file_path//%/\\x}")

        if [ -f "$file_path" ]; then
            echo "$file_path"
        else
            echo "UPLOAD: Warning — file not found: $file_path" >&2
        fi
    done > "$temp_transfer"

    # Check for empty transfer list
    if [ ! -s "$temp_transfer" ]; then
        rm -rf "$temp_dir"
        error_exit 1 "No valid files found in playlist" "playlist" "$audpl_file"
        return 1
    fi

    # Create .m3u playlist with only filenames
    echo "UPLOAD: Creating playlist..."
    while IFS= read -r file_path; do
        basename "$file_path"
    done < "$temp_transfer" > "$output_m3u"

    # Log new playlist as current and write metadata BEFORE transfer
    echo "$pl_basename" > "$CURRENT_PLAYLIST_FILE"
    date +%s > "$MOBILE_DIR/${pl_basename}.meta"
    cp "$temp_transfer" "$MOBILE_DIR/${pl_basename}.tracks" 2>/dev/null

    mobile_log "INFO" "UPLOAD" "Starting upload: $pl_basename"
    mobile_log "INFO" "UPLOAD" "Device ID: $device_id"

    # Transfer playlist first
    echo "UPLOAD: Transferring playlist: ${pl_basename}.m3u"
    $KDECONNECT_CMD -d "$device_id" --share "$output_m3u"

    # Calculate total size for summary
    local total_size=0
    while IFS= read -r file_path; do
        if [ -f "$file_path" ]; then
            total_size=$((total_size + $(stat -c%s "$file_path" 2>/dev/null || echo 0)))
        fi
    done < "$temp_transfer"
    local total_size_mb=$(echo "scale=1; $total_size / 1048576" | bc)

    # Transfer music files
    local transferred=0
    local total=$(wc -l < "$temp_transfer")

    while IFS= read -r file_path; do
        transferred=$((transferred + 1))
        echo "UPLOAD: [$transferred/$total] $(basename "$file_path")"
        $KDECONNECT_CMD -d "$device_id" --share "$file_path"
    done < "$temp_transfer"

    # Cleanup temp directory
    rm -rf "$temp_dir"

    echo "UPLOAD: Complete — $total files transferred (${total_size_mb} MB)"
    mobile_log "INFO" "UPLOAD" "Upload complete: ${pl_basename}.m3u ($total tracks, ${total_size_mb} MB)"
    log_message "Uploaded playlist to mobile: $pl_basename ($total tracks, ${total_size_mb} MB)"

    return 0
}

#############################################
# Retry: re-process pending/failed tracks
#############################################

# Re-attempt timestamp writes for tracks that failed during accounting.
# Reads .pending_tracks and/or .failed files for the given playlist.
#
# For .pending_tracks: checks if tracks are now in the DB (user may have
# imported them via musiclib_new_tracks.sh), then applies the stored timestamp.
#
# For .failed: re-attempts the DB update and tag write directly.
#
retry_playlist() {
    local playlist_name="$1"
    local pending_file="$MOBILE_DIR/${playlist_name}.pending_tracks"
    local failed_file="$MOBILE_DIR/${playlist_name}.failed"
    local has_work=false

    if [ -f "$pending_file" ]; then
        has_work=true
    fi
    if [ -f "$failed_file" ]; then
        has_work=true
    fi

    if [ "$has_work" = false ]; then
        echo "No recovery files found for playlist: $playlist_name"
        echo "Expected: ${playlist_name}.pending_tracks or ${playlist_name}.failed"
        exit 0
    fi

    if ! validate_database "$MUSICDB"; then
        error_exit 2 "Database validation failed" "database" "$MUSICDB"
        exit 2
    fi

    # Get LastTimePlayed column number
    local lpcolnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep "LastTimePlayed" | sed -r 's/^([^.]+).*$/\1/; s/^[^0-9]*([0-9]+).*$/\1/')

    if [ -z "$lpcolnum" ]; then
        error_exit 2 "Database schema error — LastTimePlayed column not found"
        exit 2
    fi

    # Acquire database lock
    if ! acquire_db_lock 5; then
        error_exit 2 "Database lock timeout" "timeout" "5 seconds" "database" "$MUSICDB"
        exit 2
    fi

    local retry_success=0
    local retry_still_missing=0
    local retry_still_failed=0
    local temp_still_pending=$(mktemp)
    local temp_still_failed=$(mktemp)

    # Process .pending_tracks (tracks that weren't in DB)
    if [ -f "$pending_file" ]; then
        echo "ACCOUNTING: Retrying not-in-db tracks for: $playlist_name"
        mobile_log "INFO" "RETRY" "Retrying pending tracks: $playlist_name"

        while IFS='^' read -r filepath synthetic_sql synthetic_human; do
            # Check if track is now in the database
            if ! grep -qF "$filepath" "$MUSICDB" 2>/dev/null; then
                echo "ACCOUNTING: Still not in DB — $filepath"
                echo "$filepath^$synthetic_sql^$synthetic_human" >> "$temp_still_pending"
                retry_still_missing=$((retry_still_missing + 1))
                continue
            fi

            # Track is now in DB — apply the stored timestamp
            local grepped_string=$(grep -nF "$filepath" "$MUSICDB" 2>/dev/null)
            local myrow=$(echo "$grepped_string" | cut -f1 -d:)

            if awk -F'^' -v OFS='^' -v row="$myrow" -v col="$lpcolnum" -v newval="$synthetic_sql" \
                'NR == row { $col = newval } { print }' \
                "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then

                mv "$MUSICDB.tmp" "$MUSICDB"

                # Attempt tag write
                if $KID3_CMD -c "set Songs-DB_Custom1 $synthetic_sql" "$filepath" 2>/dev/null; then
                    echo "ACCOUNTING: Retry success — $(basename "$filepath") -> $synthetic_human"
                    retry_success=$((retry_success + 1))
                else
                    echo "ACCOUNTING: DB updated but tag write failed — $(basename "$filepath")"
                    echo "$filepath^$synthetic_sql^$synthetic_human^tag_write_failed" >> "$temp_still_failed"
                    retry_still_failed=$((retry_still_failed + 1))
                fi
            else
                echo "ACCOUNTING: Retry DB update failed — $(basename "$filepath")"
                echo "$filepath^$synthetic_sql^$synthetic_human^db_write_failed" >> "$temp_still_failed"
                rm -f "$MUSICDB.tmp"
                retry_still_failed=$((retry_still_failed + 1))
            fi

        done < "$pending_file"
    fi

    # Process .failed (tracks where DB/tag write failed)
    if [ -f "$failed_file" ]; then
        echo "ACCOUNTING: Retrying failed writes for: $playlist_name"
        mobile_log "INFO" "RETRY" "Retrying failed writes: $playlist_name"

        while IFS='^' read -r filepath synthetic_sql synthetic_human failure_reason; do
            local grepped_string=$(grep -nF "$filepath" "$MUSICDB" 2>/dev/null)
            if [ -z "$grepped_string" ]; then
                echo "ACCOUNTING: Track no longer in DB — $filepath"
                echo "$filepath^$synthetic_sql^$synthetic_human" >> "$temp_still_pending"
                retry_still_missing=$((retry_still_missing + 1))
                continue
            fi

            local myrow=$(echo "$grepped_string" | cut -f1 -d:)

            if awk -F'^' -v OFS='^' -v row="$myrow" -v col="$lpcolnum" -v newval="$synthetic_sql" \
                'NR == row { $col = newval } { print }' \
                "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then

                mv "$MUSICDB.tmp" "$MUSICDB"

                if $KID3_CMD -c "set Songs-DB_Custom1 $synthetic_sql" "$filepath" 2>/dev/null; then
                    echo "ACCOUNTING: Retry success — $(basename "$filepath") -> $synthetic_human"
                    retry_success=$((retry_success + 1))
                else
                    echo "ACCOUNTING: Retry tag write still failing — $(basename "$filepath")"
                    echo "$filepath^$synthetic_sql^$synthetic_human^tag_write_failed" >> "$temp_still_failed"
                    retry_still_failed=$((retry_still_failed + 1))
                fi
            else
                echo "ACCOUNTING: Retry DB update still failing — $(basename "$filepath")"
                echo "$filepath^$synthetic_sql^$synthetic_human^db_write_failed" >> "$temp_still_failed"
                rm -f "$MUSICDB.tmp"
                retry_still_failed=$((retry_still_failed + 1))
            fi

        done < "$failed_file"
    fi

    # Release database lock
    release_db_lock

    # Update recovery files based on retry results
    if [ -s "$temp_still_pending" ]; then
        mv "$temp_still_pending" "$pending_file"
        echo "ACCOUNTING: Updated $(basename "$pending_file") — $retry_still_missing tracks remaining"
    else
        rm -f "$temp_still_pending" "$pending_file"
    fi

    if [ -s "$temp_still_failed" ]; then
        mv "$temp_still_failed" "$failed_file"
        echo "ACCOUNTING: Updated $(basename "$failed_file") — $retry_still_failed tracks remaining"
    else
        rm -f "$temp_still_failed" "$failed_file"
    fi

    # Summary
    echo ""
    echo "ACCOUNTING: Retry complete — $retry_success succeeded, $retry_still_missing still not in DB, $retry_still_failed still failing"
    mobile_log "STATS" "RETRY" "Success: $retry_success, Still missing: $retry_still_missing, Still failing: $retry_still_failed"

    # If all recovery files are now gone, clean up previous playlist metadata too
    if [ ! -f "$pending_file" ] && [ ! -f "$failed_file" ]; then
        local prev_meta="$MOBILE_DIR/${playlist_name}.meta"
        local prev_tracks="$MOBILE_DIR/${playlist_name}.tracks"

        # Only clean up if this is NOT the current playlist
        local current=""
        [ -f "$CURRENT_PLAYLIST_FILE" ] && current=$(cat "$CURRENT_PLAYLIST_FILE")

        if [ "$playlist_name" != "$current" ]; then
            rm -f "$prev_meta" "$prev_tracks"
            echo "ACCOUNTING: All tracks resolved — cleaned up ${playlist_name} metadata"
            mobile_log "INFO" "CLEANUP" "Retry fully resolved: $playlist_name"
        fi
    fi
}

#############################################
# Main upload workflow (combines Phase A + B)
#############################################
upload_playlist() {
    local audpl_input="$1"
    local device_id="${2:-$DEVICE_ID}"

    # Construct full path to playlist file
    local audpl_file
    if [[ "$audpl_input" == /* ]]; then
        audpl_file="$audpl_input"
    else
        audpl_file="$PLAYLISTS_DIR/$audpl_input"
    fi

    # Extract playlist name for checking updates
    local pl_basename=$(basename "$audpl_file" .audpl)

    # Validate dependencies
    if ! validate_dependencies; then
        error_exit 2 "Dependencies validation failed"
        exit 2
    fi

    #############################################
    # Check for playlist updates from Audacious
    #############################################
    if check_playlist_updates "$pl_basename"; then
        case "$PLAYLIST_STATUS" in
            newer)
                if [ "$NON_INTERACTIVE" = true ]; then
                    # In non-interactive mode, auto-refresh newer playlists
                    echo "UPLOAD: Audacious version of '$pl_basename' is newer — auto-refreshing"
                    scan_single_playlist
                    mobile_log "INFO" "PLAYLIST_SYNC" "Auto-refreshed newer playlist: $pl_basename"
                else
                    echo ""
                    echo "Audacious version of '$pl_basename' is newer than Musiclib copy."
                    read -p "Refresh from Audacious? [y/N] " -n 1 -r
                    echo ""
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        scan_single_playlist
                        echo ""
                        read -p "Continue with upload? [Y/n] " -n 1 -r
                        echo ""
                        if [[ $REPLY =~ ^[Nn]$ ]]; then
                            echo "Upload cancelled. Playlist was refreshed."
                            mobile_log "INFO" "UPLOAD" "User refreshed playlist but cancelled upload: $pl_basename"
                            exit 0
                        fi
                    fi
                fi
                ;;
            new)
                if [ "$NON_INTERACTIVE" = true ]; then
                    # In non-interactive mode, auto-copy new playlists
                    echo "UPLOAD: New Audacious playlist detected — auto-copying"
                    scan_single_playlist
                    audpl_file="$PLAYLISTS_DIR/${pl_basename}.audpl"
                    mobile_log "INFO" "PLAYLIST_SYNC" "Auto-copied new playlist: $pl_basename"
                else
                    echo ""
                    echo "This is a new Audacious playlist."
                    read -p "Copy now and proceed with upload? [y/N] " -n 1 -r
                    echo ""
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        scan_single_playlist
                        # Update audpl_file to point to newly copied file
                        audpl_file="$PLAYLISTS_DIR/${pl_basename}.audpl"
                    else
                        echo "Upload cancelled. Playlist not copied."
                        mobile_log "INFO" "UPLOAD" "User declined to copy new playlist: $pl_basename"
                        exit 0
                    fi
                fi
                ;;
        esac
    fi
    # If same, older, or not found in Audacious, continue with upload

    # Check if file exists
    if [ ! -f "$audpl_file" ]; then
        mobile_log "ERROR" "UPLOAD" "File not found: $audpl_file"
        error_exit 1 "File not found" "file" "$audpl_file"
        exit 1
    fi

    # Determine end timestamp for accounting
    local end_epoch
    if [ -n "$END_TIME_OVERRIDE" ]; then
        # Parse user-provided timestamp (MM/DD/YYYY HH:MM:SS)
        end_epoch=$(date -d "$END_TIME_OVERRIDE" +%s 2>/dev/null)
        if [ -z "$end_epoch" ]; then
            error_exit 1 "Invalid end time format" "provided" "$END_TIME_OVERRIDE" "expected" "MM/DD/YYYY HH:MM:SS"
            exit 1
        fi
        echo "ACCOUNTING: Using user-provided end time: $END_TIME_OVERRIDE"
    else
        end_epoch=$(date +%s)
    fi

    # =========================================
    # PHASE A: Accounting (device-independent)
    # =========================================
    local accounting_result=0
    process_previous_playlist "$pl_basename" "$end_epoch" || accounting_result=$?

    if [ "$accounting_result" -eq 2 ]; then
        # System error in accounting — abort
        exit 2
    fi

    # Phase A partial failure (exit 1) is non-blocking for Phase B.
    # The user gets recovery files and can retry later.

    # =========================================
    # Interactive gate (CLI only)
    # =========================================
    if [ "$NON_INTERACTIVE" = false ]; then
        echo ""
        echo "Please delete old music files from your phone's Downloads folder."
        echo "Press Enter when ready to continue with upload..."
        read -r
        echo ""
    fi

    # =========================================
    # PHASE B: Upload (device-required)
    # =========================================
    upload_to_device "$audpl_file" "$device_id" "$pl_basename"
    local upload_result=$?

    if [ "$upload_result" -ne 0 ]; then
        exit "$upload_result"
    fi

    # Final status
    if [ "$accounting_result" -eq 1 ]; then
        echo ""
        echo "Upload complete, but accounting had partial failures."
        echo "Run 'musiclib_mobile.sh status' for details."
        exit 0  # Upload itself succeeded
    fi

    exit 0
}

#############################################
# Main command dispatcher
#############################################
show_usage() {
    cat << EOF
Usage: musiclib_mobile.sh <command> [arguments] [options]

Commands:
  upload <playlist.audpl> [device_id]
      Transfer playlist and music files to Android via KDE Connect.
      Checks if Audacious version is newer and offers to refresh first.
      Processes previous playlist accounting first, then uploads.

  refresh-audacious-only
      Refresh all playlists from Audacious to Musiclib playlists directory.
      No mobile upload is performed.

  update-lastplayed <playlist_name>
      Manually trigger last-played time updates for a playlist.

  retry <playlist_name>
      Re-process tracks from .pending_tracks or .failed recovery files.

  status
      Show current mobile playlist tracking status.

  logs [filter]
      View mobile operations log.
      Filters: errors, warnings, stats, today

  cleanup
      Remove orphaned metadata files from mobile directory.

Options:
  --non-interactive     Skip interactive prompts (for GUI invocation).
                        Auto-refreshes newer Audacious playlists.
  --end-time "MM/DD/YYYY HH:MM:SS"
                        Override the completion timestamp for the previous
                        playlist (default: now).

Examples:
  musiclib_mobile.sh upload ~/music/workout.audpl
  musiclib_mobile.sh upload workout.audpl
  musiclib_mobile.sh upload ~/music/workout.audpl --non-interactive
  musiclib_mobile.sh upload ~/music/workout.audpl --end-time "02/15/2026 21:00:00"
  musiclib_mobile.sh refresh-audacious-only
  musiclib_mobile.sh update-lastplayed workout
  musiclib_mobile.sh retry workout
  musiclib_mobile.sh status
  musiclib_mobile.sh logs errors
  musiclib_mobile.sh cleanup

Configuration:
  AUDACIOUS_PLAYLISTS_DIR - Audacious playlists location
                           (default: ~/.config/audacious/playlists)

EOF
}

# Parse global flags from all arguments
parse_global_flags() {
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --end-time)
                if [ $# -lt 2 ]; then
                    error_exit 1 "Missing value for --end-time"
                    exit 1
                fi
                END_TIME_OVERRIDE="$2"
                shift 2
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done
    # Return remaining args via global
    PARSED_ARGS=("${args[@]}")
}

# Parse flags first
parse_global_flags "$@"
set -- "${PARSED_ARGS[@]}"

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
        # Determine end timestamp
        local_end_epoch=$(date +%s)
        if [ -n "$END_TIME_OVERRIDE" ]; then
            local_end_epoch=$(date -d "$END_TIME_OVERRIDE" +%s 2>/dev/null)
            if [ -z "$local_end_epoch" ]; then
                error_exit 1 "Invalid end time format" "provided" "$END_TIME_OVERRIDE" "expected" "MM/DD/YYYY HH:MM:SS"
                exit 1
            fi
        fi
        process_previous_playlist "$2" "$local_end_epoch"
        ;;

    retry)
        if [ $# -lt 2 ]; then
            show_usage
            error_exit 1 "Missing playlist name argument"
            exit 1
        fi
        retry_playlist "$2"
        ;;

    status)
        if [ -f "$CURRENT_PLAYLIST_FILE" ]; then
            current=$(cat "$CURRENT_PLAYLIST_FILE")
            echo "Current mobile playlist: $current"

            if [ -f "$MOBILE_DIR/${current}.meta" ]; then
                upload_time=$(cat "$MOBILE_DIR/${current}.meta")
                upload_date=$(date -d "@$upload_time" '+%m/%d/%Y %H:%M:%S')
                days_ago=$(( ($(date +%s) - upload_time) / 86400 ))
                echo "Uploaded: $upload_date ($days_ago days ago)"
            fi

            if [ -f "$MOBILE_DIR/${current}.tracks" ]; then
                track_count=$(wc -l < "$MOBILE_DIR/${current}.tracks")
                echo "Tracks: $track_count"
            fi

            # Show recovery files if any
            echo ""
            has_recovery=false
            for playlist_dir_file in "$MOBILE_DIR"/*.pending_tracks "$MOBILE_DIR"/*.failed; do
                if [ -f "$playlist_dir_file" ]; then
                    if [ "$has_recovery" = false ]; then
                        echo "Recovery files (require attention):"
                        has_recovery=true
                    fi
                    local_count=$(wc -l < "$playlist_dir_file")
                    echo "  $(basename "$playlist_dir_file"): $local_count tracks"
                fi
            done
            if [ "$has_recovery" = false ]; then
                echo "No recovery files (all accounting clean)"
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
            echo "No current playlist set — nothing to clean"
            exit 0
        fi

        current=$(cat "$CURRENT_PLAYLIST_FILE")
        echo "Current playlist: $current"
        echo "Keeping: ${current}.meta, ${current}.tracks, and any .pending_tracks/.failed files"
        echo ""

        removed=0
        for file in "$MOBILE_DIR"/*.meta "$MOBILE_DIR"/*.tracks; do
            if [ -f "$file" ]; then
                file_basename=$(basename "$file")
                # Skip current playlist files
                if [[ "$file_basename" != "${current}.meta" ]] && [[ "$file_basename" != "${current}.tracks" ]]; then
                    # Check if there's a corresponding .pending_tracks or .failed
                    # If so, don't remove — the metadata is needed for retry
                    local_pl_name="${file_basename%.meta}"
                    local_pl_name="${local_pl_name%.tracks}"
                    if [ -f "$MOBILE_DIR/${local_pl_name}.pending_tracks" ] || [ -f "$MOBILE_DIR/${local_pl_name}.failed" ]; then
                        echo "Keeping: $file_basename (has recovery files)"
                        continue
                    fi
                    echo "Removing: $file_basename"
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
