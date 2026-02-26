#!/bin/bash
#
# musiclib_audacious.sh - Audacious song change handler
# Integrates with musiclib system for unified play tracking
#
# Exit codes:
#   0 - Success (display updated, scrobble queued)
#   1 - Audacious not running, no track playing
#   2 - System error (exiftool failed, tag write failed, DB lock timeout)
#
set -u
set -o pipefail

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

if ! load_config 2>/dev/null; then
    error_exit 2 "Configuration load failed"
    exit 2
fi

# Configuration values (loaded from config file)
MUSICDB="${MUSICDB:-$MUSICLIB_ROOT/data/musiclib.dsv}"
MUSIC_DISPLAY_DIR="${MUSIC_DISPLAY_DIR:-$MUSICLIB_ROOT/data/conky_output}"
STAR_DIR="${STAR_DIR:-$MUSIC_DISPLAY_DIR/stars}"

# Ensure directories exist
#mkdir -p "$MUSIC_DISPLAY_DIR" "$LOG_DIR" 2>/dev/null || {
#    error_exit 2 "Failed to create required directories" "music_display_dir" "$MUSIC_DISPLAY_DIR" "log_dir" "$LOG_DIR"
#    exit 2
#}

#############################################
# Check if Audacious is running
#############################################
if ! pgrep -x audacious >/dev/null; then
    # Not an error - Audacious just isn't running
    exit 0
fi

FILEPATH=$(audtool --current-song-filename 2>/dev/null || echo "")

if [ -z "$FILEPATH" ] || [ ! -f "$FILEPATH" ]; then
    # Not an error - no track playing or file doesn't exist
    exit 0
fi

#############################################
# Album Art Extraction
#############################################
extract_album_art() {
    local artdir
    artdir=$(dirname "$FILEPATH")

    # Save art location for other scripts
    echo "$artdir" > "$MUSIC_DISPLAY_DIR/artloc.txt"

    # Helper: copy folder.jpg from album dir to display dir and record size
    _deploy_folder_jpg() {
        cp "$artdir/folder.jpg" "$MUSIC_DISPLAY_DIR/folder.jpg" 2>/dev/null || true
        stat -c%s "$artdir/folder.jpg" > "$MUSIC_DISPLAY_DIR/currartsize.txt" 2>/dev/null || true
    }

    # Step 1 — Fast path: folder.jpg already exists in album dir
    if [ -f "$artdir/folder.jpg" ]; then
        _deploy_folder_jpg
        return 0
    fi

    # Collect all other image files in the album dir (folder.jpg excluded above)
    local images=()
    while IFS= read -r -d '' f; do
        images+=("$f")
    done < <(find "$artdir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) ! -iname 'folder.jpg' -print0 2>/dev/null)

    local img_count=${#images[@]}

    if [ "$img_count" -eq 1 ]; then
        # Step 2 — Single stray image: copy it as folder.jpg
        cp "${images[0]}" "$artdir/folder.jpg" 2>/dev/null || true

    elif [ "$img_count" -gt 1 ]; then
        # Step 3 — Multiple stray images: pick by preferred name, then fall back to largest
        local chosen="" pattern f base
        for pattern in folder cover front album; do
            for f in "${images[@]}"; do
                base=$(basename "$f")
                if echo "$base" | grep -qi "$pattern"; then
                    chosen="$f"
                    break 2
                fi
            done
        done

        # Fallback: pick the largest file by size
        if [ -z "$chosen" ]; then
            local max_size=0 sz
            for f in "${images[@]}"; do
                sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
                if [ "$sz" -gt "$max_size" ]; then
                    max_size=$sz
                    chosen="$f"
                fi
            done
        fi

        [ -n "$chosen" ] && cp "$chosen" "$artdir/folder.jpg" 2>/dev/null || true

    else
        # Step 4 — No image files at all: try to extract embedded cover art
        exiftool -b -Picture "$FILEPATH" > "$artdir/folder.jpg" 2>/dev/null || true

        if [ ! -s "$artdir/folder.jpg" ]; then
            # No embedded art — clean up blank file and remove stale display art
            rm -f "$artdir/folder.jpg"
            rm -f "$MUSIC_DISPLAY_DIR/folder.jpg"
            rm -f "$MUSIC_DISPLAY_DIR/currartsize.txt"
            return 0
        fi
    fi

    # Deploy folder.jpg (created in steps 2, 3, or 4) to display dir
    if [ -f "$artdir/folder.jpg" ]; then
        _deploy_folder_jpg
    fi
}

#############################################
# Extract Track Metadata for Conky
#############################################
extract_metadata() {
    # Full metadata - critical for Conky display
    if ! exiftool -a "$FILEPATH" > "$MUSIC_DISPLAY_DIR/taginfofull.txt" 2>/dev/null; then
        error_exit 2 "exiftool failed to extract metadata" "filepath" "$FILEPATH"
        exit 2
    fi

    # Individual fields - use audtool when possible (more reliable for current track)
    audtool --current-song-tuple-data artist 2>/dev/null > "$MUSIC_DISPLAY_DIR/artist.txt" || echo "" > "$MUSIC_DISPLAY_DIR/artist.txt"
    audtool --current-song-tuple-data album 2>/dev/null > "$MUSIC_DISPLAY_DIR/album.txt" || echo "" > "$MUSIC_DISPLAY_DIR/album.txt"
    audtool --current-song-tuple-data year 2>/dev/null > "$MUSIC_DISPLAY_DIR/year.txt" || echo "" > "$MUSIC_DISPLAY_DIR/year.txt"
    audtool --current-song-tuple-data title 2>/dev/null > "$MUSIC_DISPLAY_DIR/title.txt" || echo "" > "$MUSIC_DISPLAY_DIR/title.txt"
    
    # Comment field from kid3-cli
    if ! $KID3_CMD -c "select \"$FILEPATH\"" -c "get comment" > "$MUSIC_DISPLAY_DIR/detail.txt" 2>/dev/null; then
        echo "" > "$MUSIC_DISPLAY_DIR/detail.txt"
    fi

    # Extract rating from Grouping tag
    awk '/Grouping/&&length($NF)==1{print $NF;found=1;exit}END{if(!found)print 0}' "$MUSIC_DISPLAY_DIR/taginfofull.txt" >"$MUSIC_DISPLAY_DIR/currgpnum.txt" 2>/dev/null || echo 0>"$MUSIC_DISPLAY_DIR/currgpnum.txt"

    # Check for existence of custom weather file, otherwise ignore remainder of function
    detail_file="$MUSIC_DISPLAY_DIR/detail.txt"
    [ ! -s "$detail_file" ] && return 0
    [ -f "$MUSIC_DISPLAY_DIR/weathercount.txt" ] || return 0

    # Weather integration logic (custom user feature)
    lines_weather=$(cat "$MUSIC_DISPLAY_DIR/weathercount.txt" 2>/dev/null || echo 0)
    chars_target=$((700 - 63 * (lines_weather - 6)))
    (( chars_target < 63 )) && chars_target=63
    current_chars=$(wc -c < "$detail_file")

    if (( current_chars == chars_target )); then
        return 0
    fi

    if (( lines_weather == 6 && current_chars < chars_target )); then
        spaces_needed=$((chars_target - current_chars))
        printf "%s%${spaces_needed}s" "$(cat "$detail_file")" "" > "${detail_file}.tmp" && mv "${detail_file}.tmp" "$detail_file"
        return 0
    fi

    if (( current_chars > chars_target )); then
        head -c "$chars_target" "$detail_file" > "${detail_file}.tmp" && mv "${detail_file}.tmp" "$detail_file"
    fi
}

#############################################
# Show Last Played from Database
#############################################
show_last_played() {
    if [ ! -f "$MUSICDB" ]; then
        echo "Never" > "$MUSIC_DISPLAY_DIR/lastplayed.txt"
        return
    fi

    local line=$(grep -F "$FILEPATH" "$MUSICDB" 2>/dev/null | head -n1)

    if [ -z "$line" ]; then
        echo "Never" > "$MUSIC_DISPLAY_DIR/lastplayed.txt"
        return
    fi

    local sql_time=$(echo "$line" | cut -d'^' -f13 | tr -d ' \r')

    if [ -z "$sql_time" ] || [ "$sql_time" = "0" ] || [ "$sql_time" = "0.000000" ]; then
        echo "Never" > "$MUSIC_DISPLAY_DIR/lastplayed.txt"
    else
        # Convert SQL time to readable date
        local epoch_secs=$(echo "($sql_time - 25569) * 86400 / 1" | bc | cut -d. -f1)
        date -d @"$epoch_secs" '+%m/%d/%y' > "$MUSIC_DISPLAY_DIR/lastplayed.txt" 2>/dev/null || echo "Invalid" > "$MUSIC_DISPLAY_DIR/lastplayed.txt"
    fi
}

#############################################
# Display Star Rating Image
#############################################
show_rating() {
    rating=$(tr -cd '0-9' < "$MUSIC_DISPLAY_DIR/currgpnum.txt")

    # Clear existing rating
    rm -f "$MUSIC_DISPLAY_DIR/starrating.png"

    case "$rating" in
        1) [ -f "$STAR_DIR/one.png" ] && cp "$STAR_DIR/one.png" "$MUSIC_DISPLAY_DIR/starrating.png" ;;
        2) [ -f "$STAR_DIR/two.png" ] && cp "$STAR_DIR/two.png" "$MUSIC_DISPLAY_DIR/starrating.png" ;;
        3) [ -f "$STAR_DIR/three.png" ] && cp "$STAR_DIR/three.png" "$MUSIC_DISPLAY_DIR/starrating.png" ;;
        4) [ -f "$STAR_DIR/four.png" ] && cp "$STAR_DIR/four.png" "$MUSIC_DISPLAY_DIR/starrating.png" ;;
        5) [ -f "$STAR_DIR/five.png" ] && cp "$STAR_DIR/five.png" "$MUSIC_DISPLAY_DIR/starrating.png" ;;
        0|''|*)
            # Unrated - notify user (optional, non-critical)
            if command -v kdialog >/dev/null 2>&1; then
                kdialog --title 'Needs a Rating' --passivepopup 'Enter win+num to rate this track' 4 &
            fi
            ;;
    esac
}

#############################################
# Update Database After Scrobble Point
#############################################
update_play_time() {
    local play_time="$1"

    if [ ! -f "$MUSICDB" ]; then
        log_message "ERROR: Database not found: $MUSICDB"
        return 1
    fi

    # Get LastTimePlayed column number
    local lpcolnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep "LastTimePlayed" | sed -r 's/^[^0-9]*([0-9]+).*$/\1/')

    if [ -z "$lpcolnum" ]; then
        log_message "ERROR: Could not find LastTimePlayed column in database"
        return 1
    fi

    # Find track in database
    local grepped_string=$(grep -nF "$FILEPATH" "$MUSICDB" 2>/dev/null | head -n1)

    if [ -z "$grepped_string" ]; then
        # Track not in database - this is informational, not an error
        log_message "Track not in database (skipping scrobble): $FILEPATH"
        return 0
    fi

    local myrow=$(echo "$grepped_string" | cut -f1 -d:)
    local old_value=$(echo "$grepped_string" | cut -f"$lpcolnum" -d"^" | xargs)

    # Update database with lock - use 10 second timeout for scrobbling
    if ! with_db_lock 10 awk -F'^' -v OFS='^' -v target_row="$myrow" \
        -v lastplayed_col="$lpcolnum" -v new_playtime="$play_time" \
        'NR == target_row { $lastplayed_col = new_playtime } { print }' \
        "$MUSICDB" > "$MUSICDB.tmp"; then
        
        local lock_result=$?
        if [ $lock_result -eq 1 ]; then
            # Lock timeout - this is OK for scrobbling, just log it
            log_message "Database lock timeout during scrobble (will retry on next track change)"
            return 0
        else
            # Other error
            error_exit 2 "Database update failed during scrobble" "filepath" "$FILEPATH" "lock_error" "$lock_result"
            return 2
        fi
    fi

    # Finalize database update
    if ! mv "$MUSICDB.tmp" "$MUSICDB" 2>/dev/null; then
        rm -f "$MUSICDB.tmp"
        error_exit 2 "Failed to finalize database update" "filepath" "$FILEPATH"
        return 2
    fi

    # Update tag with rebuild on failure
    if ! kid3-cli -c "set Songs-DB_Custom1 $play_time" "$FILEPATH" 2>/dev/null; then
        log_message "Initial tag write failed for $(basename "$FILEPATH") – rebuilding tag"

        # Load tag functions if not already loaded
        if ! type rebuild_tag >/dev/null 2>&1; then
            source "$MUSICLIB_ROOT/bin/musiclib_utils_tag_functions.sh" || {
                error_exit 2 "Failed to load tag functions" "script" "musiclib_utils_tag_functions.sh"
                return 2
            }
        fi

        if rebuild_tag "$FILEPATH" && \
        kid3-cli -c "set Songs-DB_Custom1 $play_time" "$FILEPATH" 2>/dev/null; then
            log_message "Tag write succeeded after repair"
        else
            log_message "ERROR: Tag write failed even after repair: $FILEPATH"
            error_exit 2 "Scrobble tag write failed" "filepath" "$FILEPATH"
            return 2
        fi
    fi

    return 0
}

#############################################
# Update Last Played Display After Scrobble
#############################################
update_lastplayed_display() {
    local sql_time="$1"

    # Convert SQL time back to readable date for display
    local epoch_secs=$(echo "($sql_time - 25569) * 86400 / 1" | bc | cut -d. -f1)
    date -d @"$epoch_secs" '+%m/%d/%y' > "$MUSIC_DISPLAY_DIR/lastplayed.txt" 2>/dev/null || echo "Just Now" > "$MUSIC_DISPLAY_DIR/lastplayed.txt"
}

#############################################
# Monitor Playback and Scrobble
#############################################
monitor_playback() {
    local track_length=$(audtool --current-song-length-seconds 2>/dev/null)

    if [ -z "$track_length" ] || [ "$track_length" -eq 0 ]; then
        return 1
    fi

    # Calculate scrobble point (50% of track length, minimum 30 seconds, max 4 minutes)
    local scrobble_point=$((track_length * SCROBBLE_THRESHOLD_PCT / 100))
    [ "$scrobble_point" -lt 30 ] && scrobble_point=30
    [ "$scrobble_point" -gt 240 ] && scrobble_point=240

    local check_interval=3
    local checks_needed=$((scrobble_point / check_interval))
    local checks_passed=0

    while [ $checks_passed -lt $checks_needed ]; do
        sleep $check_interval

        # Check if still playing
        local status=$(audtool --playback-status 2>/dev/null)
        [ "$status" != "playing" ] && return 1

        # Check if still on same track
        local current=$(audtool --current-song-filename 2>/dev/null)
        [ "$current" != "$FILEPATH" ] && return 1

        checks_passed=$((checks_passed + 1))
    done

    # Reached scrobble point - update everything
    local current_time=$(date +%s)
    local sql_time=$(printf "%.6f" $(echo "$current_time/86400 + 25569" | bc -l))

    update_play_time "$sql_time"
    local update_result=$?
    update_lastplayed_display "$sql_time"

    # After successful database update, process any pending operations
    if [ $update_result -eq 0 ] && [ -f "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" ]; then
        "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" &
    fi

    return 0
}

#############################################
# Conky Watchdog
#############################################
restart_conky_if_needed() {
    local conky_count=$(pidof conky 2>/dev/null | wc -w)

    if [ "$conky_count" -eq 0 ]; then
        /usr/bin/conky &
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --title 'Restart: Conky' --passivepopup 'Restarted Conky display' 2 &
        fi
    fi
}

#############################################
# Main Execution
#############################################

# Update display immediately
extract_album_art
extract_metadata
show_last_played
show_rating
restart_conky_if_needed

# Fork background monitor process for scrobbling
(
    monitor_playback
) </dev/null >/dev/null 2>&1 &

# Exit immediately so Audacious isn't blocked
exit 0
