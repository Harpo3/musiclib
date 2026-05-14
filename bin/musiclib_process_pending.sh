#!/bin/bash
#
# musiclib_process_pending.sh - Process queued database operations
#
# This script processes operations that were queued due to database lock contention.
# It is called automatically after database-writing operations complete, and can also
# be invoked manually or run on a timer.
#
# Exit codes:
#   0 - Success (all operations processed or no operations pending)
#   2 - System error (cannot access pending file)
#

set -e
set -u
set -o pipefail

export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source utilities - REQUIRED for locking and error handling
if ! source "$SCRIPT_DIR/musiclib_utils.sh" 2>/dev/null; then
    echo "Error: musiclib_utils.sh not found at $SCRIPT_DIR/musiclib_utils.sh" >&2
    exit 2
fi
if ! source "$SCRIPT_DIR/musiclib_db.sh" 2>/dev/null; then
    echo "Error: musiclib_db.sh not found at $SCRIPT_DIR/musiclib_db.sh" >&2
    exit 2
fi

# Load configuration
if ! load_config 2>/dev/null; then
    echo "Error: Failed to load configuration" >&2
    exit 2
fi

# Fallback configuration
MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"
PENDING_FILE="$(get_data_dir)/data/.pending_operations"
PENDING_LOCK_FILE="${PENDING_FILE}.lock"

# Don't run if no pending operations
if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
    # No pending operations - this is normal, exit quietly
    exit 0
fi

#############################################
# Acquire Lock on Pending File
#############################################

# Prevent concurrent processing
exec {PENDING_LOCK_FD}>"$PENDING_LOCK_FILE"
if ! flock -n "$PENDING_LOCK_FD"; then
    # Another processor is already running - exit silently
    exit 0
fi

#############################################
# Process Pending Operations
#############################################

# DB write step for update_rating_in_db — runs inside with_db_lock subshell.
# Reads myrow, groupdesc_colnum, groupdesc_value, rating_colnum, popm_value, MUSICDB
# from the subshell environment (inherited from update_rating_in_db locals at fork).
_do_rating_db_update() {
    if ! awk -F'^' -v OFS='^' -v target_row="$myrow" \
        -v groupdesc_col="$groupdesc_colnum" -v new_groupdesc="$groupdesc_value" \
        -v rating_col="$rating_colnum" -v new_rating="$popm_value" \
        'NR == target_row { $groupdesc_col = new_groupdesc; $rating_col = new_rating } { print }' \
        "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then
        log_message "ERROR: Failed to update database columns"
        return 1
    fi
    if ! mv "$MUSICDB.tmp" "$MUSICDB" 2>/dev/null; then
        log_message "ERROR: Failed to finalize database update"
        rm -f "$MUSICDB.tmp"
        return 1
    fi
}

# Function to update rating in database
# Args: filepath star_rating
update_rating_in_db() {
    local filepath="$1"
    local star_rating="$2"

    # Star rating to POPM mapping
    local -A STAR_TO_POPM=(
        [0]=0 [1]=64 [2]=118 [3]=153 [4]=196 [5]=255
    )

    # Star rating to GroupDesc mapping
    local -A STAR_TO_GROUPDESC=(
        [0]=0 [1]=1 [2]=2 [3]=3 [4]=4 [5]=5
    )

    local popm_value="${STAR_TO_POPM[$star_rating]}"
    local groupdesc_value="${STAR_TO_GROUPDESC[$star_rating]}"

    # Verify database exists
    if [ ! -f "$MUSICDB" ]; then
        log_message "ERROR: Database file not found: $MUSICDB"
        return 1
    fi

    # Get column numbers
    local groupdesc_colnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep "GroupDesc" | sed -r 's/^[^0-9]*([0-9]+).*$/\1/')
    local rating_colnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep -w "Rating" | sed -r 's/^[^0-9]*([0-9]+).*$/\1/')

    if [ -z "$groupdesc_colnum" ] || [ -z "$rating_colnum" ]; then
        log_message "ERROR: Could not find Rating or GroupDesc columns in database"
        return 1
    fi

    # Find track in database
    local grepped_string=$(grep -nF "$filepath" "$MUSICDB" 2>/dev/null | head -n1)

    if [ -z "$grepped_string" ]; then
        log_message "Note: Track not found in database: $filepath"
        return 0  # Not an error - track may have been removed
    fi

    local myrow=$(echo "$grepped_string" | cut -f1 -d:)

    if ! with_db_lock 5 _do_rating_db_update; then
        return 1
    fi

    # Update file tags
    if command -v kid3-cli >/dev/null 2>&1 && [ -f "$filepath" ]; then
        kid3-cli -c "set POPM $popm_value" "$filepath" 2>/dev/null || true
        kid3-cli -c "set TIT1 $groupdesc_value" "$filepath" 2>/dev/null || true
    fi

    return 0
}

# DB write step for add_track — runs inside with_db_lock subshell.
# Reads filepath, artist, album, albumartist, title, genre, songlength,
# local_default_rating, local_default_groupdesc, lastplayed, MUSICDB, CUSTOM2
# from the subshell environment (inherited from caller's locals at fork).
# Returns: 0 success, 2 validation failure, 3 write failure
_do_add_track_db() {
    local next_id idalbum new_entry
    next_id=$(get_next_id "$MUSICDB")
    idalbum=$(find_or_create_album "$MUSICDB" "${album:-}")
    new_entry="${next_id}^${artist:-}^${idalbum}^${album:-}^${albumartist:-}^${title:-}^${filepath}^${genre:-}^${songlength}^${local_default_rating}^${CUSTOM2:-}^${local_default_groupdesc}^${lastplayed}^^"
    if ! validate_entry_fields "$new_entry"; then
        log_message "ERROR: Rejecting malformed DB entry for pending add_track: $filepath"
        return 2
    fi
    if ! echo "$new_entry" >> "$MUSICDB" 2>/dev/null; then
        log_message "ERROR: Failed to write pending add_track to database: $filepath"
        return 3
    fi
    log_message "COMPLETED PENDING: Added track $filepath (ID: $next_id)"
}

# Process each line in the pending operations file
temp_pending=$(mktemp)
processed_lines=""

while IFS='|' read -r timestamp script operation remaining_args; do
    case "$operation" in
        add_track)
            # Extract filepath and lastplayed from remaining_args
            # Format: filepath|lastplayed
            filepath=$(echo "$remaining_args" | cut -d'|' -f1)
            lastplayed=$(echo "$remaining_args" | cut -d'|' -f2)

            # Validate inputs
            if [ -z "$filepath" ] || [ -z "$lastplayed" ]; then
                log_message "MALFORMED PENDING OPERATION: Missing filepath or lastplayed for add_track"
                processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
                continue
            fi

            # Skip if file no longer exists
            if [ ! -f "$filepath" ]; then
                log_message "SKIPPING PENDING add_track: File no longer exists: $filepath"
                processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
                continue
            fi

            # Skip if already in database (may have been added by another path)
            if tail -n +2 "$MUSICDB" | grep -qF "^${filepath}^" 2>/dev/null; then
                log_message "SKIPPING PENDING add_track: Already in database: $filepath"
                processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
                continue
            fi

            # Extract metadata before acquiring lock (lock held only for the DB write)
            track_title=$(basename "$filepath")
            artist=""
            album=""
            albumartist=""
            title=""
            genre=""
            if command -v kid3-cli >/dev/null 2>&1; then
                artist=$(kid3-cli -c 'get artist' "$filepath" 2>/dev/null | head -n1 || true)
                album=$(kid3-cli -c 'get album' "$filepath" 2>/dev/null | head -n1 || true)
                albumartist=$(kid3-cli -c 'get albumartist' "$filepath" 2>/dev/null | head -n1 || true)
                title=$(kid3-cli -c 'get title' "$filepath" 2>/dev/null | head -n1 || true)
                genre=$(kid3-cli -c 'get genre' "$filepath" 2>/dev/null | head -n1 || true)
                track_title="${title:-$(basename "$filepath")}"
            fi

            # Get song length
            songlength_ms=$(get_song_length_ms "$filepath" 2>/dev/null || echo "0")
            songlength=$(format_song_length "$songlength_ms" 2>/dev/null || echo "0:00")

            # Default rating/groupdesc values (mirrors musiclib_new_tracks.sh defaults)
            local_default_rating="${DEFAULT_RATING:-0}"
            local_default_groupdesc="${DEFAULT_GROUPDESC:-0}"

            # Acquire lock, write entry; _do_add_track_db inherits all vars above via subshell fork
            add_track_rc=0
            with_db_lock 5 _do_add_track_db || add_track_rc=$?
            case "$add_track_rc" in
                0)
                    # Update file tags
                    if command -v kid3-cli >/dev/null 2>&1 && [ -f "$filepath" ]; then
                        kid3-cli -c "set Songs-DB_Custom1 $lastplayed" "$filepath" 2>/dev/null || true
                        kid3-cli -c "set POPM ${local_default_rating}" "$filepath" 2>/dev/null || true
                        kid3-cli -c "set Work ${local_default_groupdesc}" "$filepath" 2>/dev/null || true
                    fi

                    # Show completion notification
                    if command -v kdialog >/dev/null 2>&1; then
                        kdialog --title 'Track Added' --passivepopup \
                            "\"${track_title}\" added to library" 3 &
                    fi

                    processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
                    ;;
                2)
                    # Validation failure — discard, do not retry
                    processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
                    ;;
                *)
                    # Lock timeout or write failure — leave in queue for next attempt
                    log_message "RETRY FAILED: Cannot add_track $filepath (database locked or write failed, will retry later)"
                    ;;
            esac
            ;;
        rate)
            # Extract filepath and star_rating from remaining_args
            # Format: filepath|star_rating
            filepath=$(echo "$remaining_args" | cut -d'|' -f1)
            star_rating=$(echo "$remaining_args" | cut -d'|' -f2)
            
            # Validate inputs
            if [ -z "$filepath" ] || [ -z "$star_rating" ]; then
                log_message "MALFORMED PENDING OPERATION: Missing filepath or star_rating"
                # Mark for removal
                processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
                continue
            fi
            
            # Attempt to execute the rating
            if update_rating_in_db "$filepath" "$star_rating"; then
                log_message "COMPLETED PENDING: Rated $filepath -> $star_rating stars"
                
                # Show completion notification
                if command -v kdialog >/dev/null 2>&1; then
                    track_title=$(basename "$filepath")
                    star_display=$(printf '★%.0s' $(seq 1 $star_rating))
                    kdialog --title 'Rating Applied' --passivepopup \
                        "Rating $star_display applied to \"$track_title\"" 3 &
                fi
                
                # Mark for removal (operation succeeded)
                processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
            else
                # Failed again - leave in queue, will retry later
                log_message "RETRY FAILED: Cannot rate $filepath (will retry later)"
            fi
            ;;
        *)
            log_message "UNKNOWN PENDING OPERATION: $operation"
            # Remove unknown operations
            processed_lines="${processed_lines}${timestamp}|${script}|${operation}|${remaining_args}"$'\n'
            ;;
    esac
done < "$PENDING_FILE"

# Remove processed operations from pending file
if [ -n "$processed_lines" ]; then
    # Copy pending file to temp, excluding processed lines
    grep -xvFf <(echo -n "$processed_lines") "$PENDING_FILE" > "$temp_pending" 2>/dev/null || true
    mv "$temp_pending" "$PENDING_FILE"
else
    # No operations were processed successfully
    rm -f "$temp_pending"
fi

# Clean up empty pending file
if [ ! -s "$PENDING_FILE" ]; then
    rm -f "$PENDING_FILE"
fi

#############################################
# Release Lock and Exit
#############################################

flock -u "$PENDING_LOCK_FD" 2>/dev/null || true
exec {PENDING_LOCK_FD}>&-

exit 0
