#!/bin/bash
#
# musiclib_player_event.sh — MPRIS2 song-change handler
# Integrates with musiclib system for unified play tracking.
#
# Canonical track-change handler for any MPRIS2-compliant music player.
# Invoked by musiclib_mpris_listen.sh (via systemd user unit musiclib-mpris.service).
# No per-player hook configuration required.
#
# Supported players: any player whose bus-name suffix appears in
# supported_mpris_players (musiclib.conf).  Default list includes Strawberry,
# Audacious, Clementine, Amarok, Elisa, and mpd (via mpd-mpris bridge).
#
# Dependencies:
#   - playerctl / playerctld (package: playerctl)
#   - qdbus6 (package: qt6-tools)
#   - exiftool, kid3-cli (existing musiclib deps)
#
# Exit codes:
#   0 - Success (display updated, scrobble queued), OR no allowed MPRIS2 player
#       active (treated as no-op, not an error)
#   2 - System error (exiftool failed, tag write failed, DB lock timeout)
#
set -e
set -u
set -o pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure vendor_perl tools (exiftool) are findable when invoked from systemd,
# which runs with a minimal PATH that omits /usr/bin/vendor_perl.
if ! command -v exiftool >/dev/null 2>&1; then
    export PATH="$PATH:/usr/bin/vendor_perl"
fi
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
MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"
MUSIC_DISPLAY_DIR="${MUSIC_DISPLAY_DIR:-$(get_data_dir)/data/conky_output}"
STAR_DIR="${STAR_DIR:-$MUSIC_DISPLAY_DIR/stars}"

# Persistent scrobble log — written even when the systemd journal cannot
# capture the backgrounded monitor_playback subshell's stderr (e.g. when the
# parent handler exits before the subshell flushes).  Tail with:
#   tail -f ~/.local/share/musiclib/data/scrobble.log
LOGFILE="${LOGFILE:-$(get_data_dir)/data/scrobble.log}"
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
export LOGFILE
export KID3_CMD
export SCROBBLE_THRESHOLD_PCT

#############################################
# Detect active player and resolve current track filepath
# (helpers are in musiclib_utils.sh: detect_active_mpris_bus,
#  mpris_metadata_field, mpris_playback_status, file_uri_to_path)
#############################################
detect_active_mpris_bus

if [ -z "$MPRIS_BUS" ]; then
    # No MPRIS2 player active - not an error, just nothing to do
    exit 0
fi

URL=$(mpris_metadata_field "xesam:url" || echo "")
FILEPATH=$(file_uri_to_path "$URL")

if [ -z "$FILEPATH" ] || [ ! -f "$FILEPATH" ]; then
    # No track playing, or non-local URL (stream, etc.) - not an error
    exit 0
fi

# Publish the current track path for GUI consumers (replaces audtool calls)
echo "$FILEPATH" > "$MUSIC_DISPLAY_DIR/songpath.txt"

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

    # Individual fields - parse from the exiftool dump we just wrote.
    # Previously these came from `audtool --current-song-tuple-data`; switching to
    # exiftool removes the player-specific dependency and keeps results consistent
    # across MPRIS players (which expose differently-shaped metadata dicts).
    awk -F': *' '/^Artist[[:space:]]*:/ {sub(/^[^:]+: */,""); print; exit}' \
        "$MUSIC_DISPLAY_DIR/taginfofull.txt" > "$MUSIC_DISPLAY_DIR/artist.txt" 2>/dev/null \
        || echo "" > "$MUSIC_DISPLAY_DIR/artist.txt"
    awk -F': *' '/^Album[[:space:]]*:/ {sub(/^[^:]+: */,""); print; exit}' \
        "$MUSIC_DISPLAY_DIR/taginfofull.txt" > "$MUSIC_DISPLAY_DIR/album.txt" 2>/dev/null \
        || echo "" > "$MUSIC_DISPLAY_DIR/album.txt"
    awk -F': *' '/^Year[[:space:]]*:/ {sub(/^[^:]+: */,""); print; exit}' \
        "$MUSIC_DISPLAY_DIR/taginfofull.txt" > "$MUSIC_DISPLAY_DIR/year.txt" 2>/dev/null \
        || echo "" > "$MUSIC_DISPLAY_DIR/year.txt"
    awk -F': *' '/^Title[[:space:]]*:/ {sub(/^[^:]+: */,""); print; exit}' \
        "$MUSIC_DISPLAY_DIR/taginfofull.txt" > "$MUSIC_DISPLAY_DIR/title.txt" 2>/dev/null \
        || echo "" > "$MUSIC_DISPLAY_DIR/title.txt"

    # Comment field from kid3-cli
    if ! $KID3_CMD -c "select \"$FILEPATH\"" -c "get comment" > "$MUSIC_DISPLAY_DIR/detail.txt" 2>/dev/null; then
        echo "" > "$MUSIC_DISPLAY_DIR/detail.txt"
    fi

    # Bitrate — parsed from the exiftool dump; strips trailing " kbps" so conky
    # can append its own label.  Falls back to empty string (not an error).
    awk -F': *' '/^Audio Bitrate[[:space:]]*:/ {sub(/^[^:]+: */,""); sub(/ kbps.*$/,""); print; exit}' \
        "$MUSIC_DISPLAY_DIR/taginfofull.txt" > "$MUSIC_DISPLAY_DIR/currbitrate.txt" 2>/dev/null \
        || echo "" > "$MUSIC_DISPLAY_DIR/currbitrate.txt"

    # Playlist position and length — Audacious-specific via org.atheme.audacious D-Bus.
    # Other MPRIS2 players have no equivalent; write empty on bus absence.
    # Direct calls avoid a grep pipe that triggers SIGPIPE under set -o pipefail.
    local _pos _len
    _pos=$(qdbus6 org.atheme.audacious /org/atheme/audacious \
        org.atheme.audacious.Position 2>/dev/null || true)
    _len=$(qdbus6 org.atheme.audacious /org/atheme/audacious \
        org.atheme.audacious.Length 2>/dev/null || true)
    if [[ "$_pos" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$(( _pos + 1 ))" > "$MUSIC_DISPLAY_DIR/playlistposition.txt"
    else
        echo "" > "$MUSIC_DISPLAY_DIR/playlistposition.txt"
    fi
    if [[ "$_len" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$_len" > "$MUSIC_DISPLAY_DIR/playlistlength.txt"
    else
        echo "" > "$MUSIC_DISPLAY_DIR/playlistlength.txt"
    fi

    # Extract rating from Grouping tag
    awk '/Grouping/&&length($NF)==1{print $NF;found=1;exit}END{if(!found)print 0}' "$MUSIC_DISPLAY_DIR/taginfofull.txt" >"$MUSIC_DISPLAY_DIR/currgpnum.txt" 2>/dev/null || echo 0>"$MUSIC_DISPLAY_DIR/currgpnum.txt"
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

    # Each branch ends with `|| true` so a missing star PNG returns 0 from the
    # case body. Without this, `[ -f ... ]` returning 1 propagates as the case
    # exit status and `set -e` kills the parent script — same footgun as
    # restart_conky_if_needed() (line 478) which uses `return 0` for the same
    # reason. Discovered 2026-04-27 when missing star PNGs silently killed
    # the scrobble fork.
    case "$rating" in
        1) [ -f "$STAR_DIR/one.png" ] && cp "$STAR_DIR/one.png" "$MUSIC_DISPLAY_DIR/starrating.png" || true ;;
        2) [ -f "$STAR_DIR/two.png" ] && cp "$STAR_DIR/two.png" "$MUSIC_DISPLAY_DIR/starrating.png" || true ;;
        3) [ -f "$STAR_DIR/three.png" ] && cp "$STAR_DIR/three.png" "$MUSIC_DISPLAY_DIR/starrating.png" || true ;;
        4) [ -f "$STAR_DIR/four.png" ] && cp "$STAR_DIR/four.png" "$MUSIC_DISPLAY_DIR/starrating.png" || true ;;
        5) [ -f "$STAR_DIR/five.png" ] && cp "$STAR_DIR/five.png" "$MUSIC_DISPLAY_DIR/starrating.png" || true ;;
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
            source "$SCRIPT_DIR/musiclib_utils_tag_functions.sh" || {
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
    local _track_basename
    _track_basename=$(basename "$FILEPATH")
    #log_message "SCROBBLE_DEBUG: monitor_playback started for $_track_basename"

    # State file carries checks_passed across pause/resume for the same track.
    # Keyed by an md5 of FILEPATH so different tracks never collide.
    local _fp_hash
    _fp_hash=$(printf '%s' "$FILEPATH" | md5sum | cut -d' ' -f1)
    local _scrobble_state_file
    _scrobble_state_file="$(get_data_dir)/data/scrobble_state_${_fp_hash}.tmp"
    local _prior_checks=0
    if [ -f "$_scrobble_state_file" ]; then
        _prior_checks=$(cat "$_scrobble_state_file" 2>/dev/null || echo 0)
        # Sanitise: must be a non-negative integer
        [[ "$_prior_checks" =~ ^[0-9]+$ ]] || _prior_checks=0
        #log_message "SCROBBLE_DEBUG: resuming — prior checks_passed=$_prior_checks"
        rm -f "$_scrobble_state_file"
    fi

    # Track length comes from MPRIS mpris:length (microseconds), convert to seconds.
    local length_us
    length_us=$(mpris_metadata_field "mpris:length" 2>/dev/null || echo "")
    # Strip any non-digit characters that qdbus may include
    length_us=$(echo "$length_us" | tr -cd '0-9')
    #log_message "SCROBBLE_DEBUG: length_us=|$length_us|"
    # Guard: if length_us is empty or zero, nothing to scrobble
    if [ -z "$length_us" ] || [ "$length_us" -eq 0 ]; then
        #log_message "SCROBBLE_DEBUG: bail — no track length"
        return 1
    fi
    local track_length=$(( length_us / 1000000 ))
    if [ "$track_length" -eq 0 ]; then
        #log_message "SCROBBLE_DEBUG: bail — track_length is 0s"
        return 1
    fi

    # Calculate scrobble point (50% of track length, minimum 30 seconds, max 4 minutes)
    local scrobble_point=$((track_length * SCROBBLE_THRESHOLD_PCT / 100))
    [ "$scrobble_point" -lt 30 ] && scrobble_point=30
    [ "$scrobble_point" -gt 240 ] && scrobble_point=240

    local check_interval=3
    local checks_needed=$(( scrobble_point / check_interval ))
    # Ensure at least one polling cycle even for very short scrobble points
    [ "$checks_needed" -lt 1 ] && checks_needed=1
    # Subtract checks already completed before the last pause so we don't
    # re-wait for intervals that have already elapsed on this track.
    checks_needed=$(( checks_needed - _prior_checks ))
    [ "$checks_needed" -lt 1 ] && checks_needed=1
    local checks_passed=0
    #log_message "SCROBBLE_DEBUG: track=${track_length}s scrobble_point=${scrobble_point}s checks_needed=$checks_needed"

    while [ $checks_passed -lt $checks_needed ]; do
        sleep $check_interval

        # Check if still playing (re-detect player in case it changed)
        detect_active_mpris_bus
        if [ -z "$MPRIS_BUS" ]; then
            #log_message "SCROBBLE_DEBUG: bail at check $checks_passed — no MPRIS bus"
            return 1
        fi

        # Defensive trim: qdbus6 appends a newline. mpris_playback_status now
        # strips it, but we re-strip here so a regression upstream cannot
        # silently break the scrobble loop again.
        local status
        status=$(mpris_playback_status | tr -d '[:space:]')
        if [ "$status" != "Playing" ]; then
            #log_message "SCROBBLE_DEBUG: bail at check $checks_passed — status=|$status|"
            # Persist progress so a resume can skip already-elapsed checks.
            # Total elapsed = prior checks (already subtracted from checks_needed)
            # plus checks completed in this run.
            local _total_passed=$(( _prior_checks + checks_passed ))
            printf '%s\n' "$_total_passed" > "$_scrobble_state_file"
            #log_message "SCROBBLE_DEBUG: saved total_checks_passed=$_total_passed to state file"
            return 1
        fi

        # Check if still on same track. mpris_metadata_field can occasionally
        # emit more than one line if the awk match fires twice; take the first
        # file:// line only so the comparison is well-defined.
        local current_url current
        current_url=$(mpris_metadata_field "xesam:url" 2>/dev/null | grep -m1 '^file://' || echo "")
        current=$(file_uri_to_path "$current_url")
        if [ "$current" != "$FILEPATH" ]; then
            #log_message "SCROBBLE_DEBUG: bail at check $checks_passed — track changed to $(basename "$current")"
            return 1
        fi

        checks_passed=$((checks_passed + 1))
    done

    # Scrobble point reached — discard any leftover pause-state for this track.
    rm -f "$_scrobble_state_file"
    #log_message "SCROBBLE_DEBUG: scrobble point reached for $_track_basename — writing DB"

    # Reached scrobble point - update everything
    local current_time=$(date +%s)
    local sql_time=$(printf "%.6f" $(echo "$current_time/86400 + 25569" | bc -l))

    update_play_time "$sql_time"
    local update_result=$?
    update_lastplayed_display "$sql_time"
    #log_message "SCROBBLE_DEBUG: update_play_time result=$update_result for $_track_basename"

    # After successful database update, process any pending operations
    if [ $update_result -eq 0 ] && [ -f "$SCRIPT_DIR/musiclib_process_pending.sh" ]; then
        "$SCRIPT_DIR/musiclib_process_pending.sh" &
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

    # Always return 0.  Without this, `set -e` aborts the calling script when
    # conky is already running ([ -eq 0 ] returns 1), preventing the scrobble
    # monitor subshell at end of main from ever forking.
    return 0
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

# Fork the scrobble polling loop.
#
# log_message() in musiclib_utils.sh uses tee -a $LOGFILE, so all logging
# inside the subshell goes to the log without an exec redirect (which would
# cause double-writes). set +e stops set -e from inheriting into the polling loop —
# monitor_playback uses non-zero `return` codes as normal flow control (track
# changed, status not Playing, etc.), and a parent set -e would treat those
# as fatal. The < /dev/null disconnects the subshell's stdin so the parent
# doesn't keep a pipe open after exit. disown drops it from the parent's
# job table so SIGHUP doesn't propagate when the systemd unit is restarted.
#
# Tail with:  tail -f ~/.local/share/musiclib/data/scrobble.log
(
    set +e
    monitor_playback
) < /dev/null &
disown

# Exit immediately so the calling player isn't blocked
exit 0
