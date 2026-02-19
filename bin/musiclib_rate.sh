#!/bin/bash
#
# musiclib_rate.sh - Rate a track's star rating
# Usage: musiclib_rate.sh <star_rating> [filepath]
#
# When filepath is provided, rates that specific file (GUI mode).
# When filepath is omitted, rates the currently playing track in Audacious
# (keyboard shortcut mode).
#
# Bind META+1 through META+5 for quick rating of current track.
#
# Exit codes:
#   0 - Success
#   1 - User error (invalid input, no track playing)
#   2 - System error (missing dependencies, I/O failure)
#   3 - Deferred success (operation queued due to lock contention)

export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS  # Just in case it's set

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$HOME/musiclib}"

# Source utilities - REQUIRED for locking and error handling
if [ ! -f "$MUSICLIB_ROOT/bin/musiclib_utils.sh" ]; then
    echo '{"error":"musiclib_utils.sh not found","script":"musiclib_rate.sh","code":2,"context":{"expected_path":"'"$MUSICLIB_ROOT/bin/musiclib_utils.sh"'"},"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' >&2
    exit 2
fi

source "$MUSICLIB_ROOT/bin/musiclib_utils.sh"

# Load configuration
if ! load_config 2>/dev/null; then
    error_exit 2 "Failed to load configuration"
    exit 2
fi

# Fallback configuration
MUSIC_DIR="${MUSIC_DIR:-$MUSICLIB_ROOT/data/conky_output}"
MUSICDB="${MUSICDB:-$MUSICLIB_ROOT/data/musiclib.dsv}"
STAR_DIR="${STAR_DIR:-$MUSIC_DIR/stars}"

# Star rating to POPM mapping (midpoints from RatingGroups)
declare -A STAR_TO_POPM=(
    [0]=0
    [1]=64
    [2]=118   # Midpoint of 65-128 = 96.5, rounded up for better visibility
    [3]=153   # Midpoint of 129-185 = 157
    [4]=196   # Midpoint of 186-200 = 193, using 196 to avoid overlap
    [5]=255
)

# Star rating to GroupDesc mapping (simple 1:1)
declare -A STAR_TO_GROUPDESC=(
    [0]=0
    [1]=1
    [2]=2
    [3]=3
    [4]=4
    [5]=5
)

# Star rating to image file mapping
declare -A STAR_TO_IMAGE=(
    [0]="blank.png"
    [1]="one.png"
    [2]="two.png"
    [3]="three.png"
    [4]="four.png"
    [5]="five.png"
)

#############################################
# Validate Input
#############################################
if [ $# -eq 0 ]; then
    echo "Usage: $0 <star_rating> [filepath]"
    echo ""
    echo "Rate a track in the MusicLib database"
    echo ""
    echo "Arguments:"
    echo "  star_rating    Number from 0-5"
    echo "                 0 = Needs rating (unrated)"
    echo "                 1 = 1 star"
    echo "                 2 = 2 stars"
    echo "                 3 = 3 stars"
    echo "                 4 = 4 stars"
    echo "                 5 = 5 stars"
    echo ""
    echo "  filepath       (Optional) Absolute path to the audio file."
    echo "                 If omitted, rates the currently playing track"
    echo "                 in Audacious."
    echo ""
    echo "Keyboard shortcuts (bind these for current-track rating):"
    echo "  META+0  = Needs rating (0 stars)"
    echo "  META+1  = 1 star"
    echo "  META+2  = 2 stars"
    echo "  META+3  = 3 stars"
    echo "  META+4  = 4 stars"
    echo "  META+5  = 5 stars"
    exit 1
fi

STAR_RATING="$1"

# Validate star rating
if [[ ! "$STAR_RATING" =~ ^[0-5]$ ]]; then
    error_exit 1 "Star rating must be between 0 and 5" "provided" "$STAR_RATING"
    exit 1
fi

#############################################
# Determine Track Filepath
#############################################
if [ $# -ge 2 ]; then
    # GUI mode: filepath provided as second argument
    FILEPATH="$2"

    # kid3-cli is always required for tag writes
    check_required_tools kid3-cli || {
        error_exit 2 "Required tools not available" "missing" "kid3-cli"
        exit 2
    }
else
    # Keyboard shortcut mode: get filepath from Audacious
    check_required_tools audtool kid3-cli || {
        error_exit 2 "Required tools not available" "missing" "audtool or kid3-cli"
        exit 2
    }

    if ! pgrep -x audacious >/dev/null; then
        error_exit 1 "Audacious is not running"
        exit 1
    fi

    FILEPATH=$(audtool --current-song-filename 2>/dev/null || echo "")

    if [ -z "$FILEPATH" ]; then
        error_exit 1 "No track is currently playing"
        exit 1
    fi
fi

if [ ! -f "$FILEPATH" ]; then
    error_exit 2 "Track file not found" "filepath" "$FILEPATH"
    exit 2
fi

#############################################
# Get Rating Values
#############################################
POPM_VALUE=${STAR_TO_POPM[$STAR_RATING]}
GROUPDESC_VALUE=${STAR_TO_GROUPDESC[$STAR_RATING]}
IMAGE_FILE=${STAR_TO_IMAGE[$STAR_RATING]}

echo "Rating track: $(basename "$FILEPATH")"
echo "  Stars: $STAR_RATING"
echo "  POPM: $POPM_VALUE"
echo "  GroupDesc: $GROUPDESC_VALUE"

#############################################
# Update File Tags using kid3-cli
#############################################
echo "Updating file tags..."

# Set POPM tag with repair on failure
if ! kid3-cli -c "set POPM $POPM_VALUE" "$FILEPATH" 2>/dev/null; then
    echo "POPM tag write failed, attempting repair..."

    if rebuild_tag "$FILEPATH"; then
        echo "  ✓ Tag rebuild successful, retrying POPM write..."

        # Retry POPM write
        if ! kid3-cli -c "set POPM $POPM_VALUE" "$FILEPATH" 2>/dev/null; then
            error_exit 2 "POPM tag write failed after rebuild" "filepath" "$FILEPATH" "popm" "$POPM_VALUE"
            exit 2
        fi
    else
        error_exit 2 "Tag rebuild failed during rating update" "filepath" "$FILEPATH"
        exit 2
    fi
fi

# Set Work (TIT1 frame) to match GroupDesc in DB
if ! kid3-cli -c "set TIT1 $GROUPDESC_VALUE" "$FILEPATH" 2>/dev/null; then
    # This is a warning, not fatal - notify user but continue
    echo "Warning: Failed to set Work tag" >&2
    if command -v kdialog >/dev/null 2>&1; then
        kdialog --title 'Tag Update Failure' --passivepopup "Warning: Failed to set Work tag" 3 &
    fi
fi

#############################################
# Update Database with Locking
#############################################

# Define the database update function to be called within lock
update_database() {
    if [ ! -f "$MUSICDB" ]; then
        error_exit 2 "Database file not found" "database" "$MUSICDB"
        return 2
    fi

    # Get GroupDesc column number
    groupdesc_colnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep "GroupDesc" | sed -r 's/^[^0-9]*([0-9]+).*$/\1/')

    # Get Rating column number (POPM)
    rating_colnum=$(head -1 "$MUSICDB" | tr '^' '\n' | cat -n | grep -w "Rating" | sed -r 's/^[^0-9]*([0-9]+).*$/\1/')

    if [ -z "$groupdesc_colnum" ] || [ -z "$rating_colnum" ]; then
        error_exit 2 "Could not find Rating or GroupDesc columns in database" "database" "$MUSICDB"
        return 2
    fi

    # Find track in database
    grepped_string=$(grep -nF "$FILEPATH" "$MUSICDB" 2>/dev/null | head -n1)

    if [ -z "$grepped_string" ]; then
        # Track not in database - this is a notice, not an error
        log_message "Note: Track not found in database: $FILEPATH"
        return 0
    fi

    myrow=$(echo "$grepped_string" | cut -f1 -d:)
    old_groupdesc=$(echo "$grepped_string" | cut -f"$groupdesc_colnum" -d"^" | xargs)
    old_rating=$(echo "$grepped_string" | cut -f"$rating_colnum" -d"^" | xargs)

    # Update GroupDesc and Rating using column-aware awk
    if ! awk -F'^' -v OFS='^' -v target_row="$myrow" \
        -v groupdesc_col="$groupdesc_colnum" -v new_groupdesc="$GROUPDESC_VALUE" \
        -v rating_col="$rating_colnum" -v new_rating="$POPM_VALUE" \
        'NR == target_row { $groupdesc_col = new_groupdesc; $rating_col = new_rating } { print }' \
        "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then
        error_exit 2 "Failed to update database columns" "database" "$MUSICDB" "row" "$myrow"
        return 2
    fi

    if ! mv "$MUSICDB.tmp" "$MUSICDB" 2>/dev/null; then
        error_exit 2 "Failed to finalize database update" "database" "$MUSICDB" "row" "$myrow"
        rm -f "$MUSICDB.tmp"
        return 2
    fi
    return 0
}

# Attempt database update with retry
echo "Updating database..."
MAX_ATTEMPTS=3
RETRY_DELAY=2
attempt=1
success=false
NOTIFICATION_PID=""
SHOWED_PROCESSING=false
track_artist=""

while [ $attempt -le $MAX_ATTEMPTS ]; do
    with_db_lock 2 update_database
    lock_result=$?
    if [ "$lock_result" -eq 0 ]; then
        success=true
        break
    fi
    if [ "$lock_result" -eq 1 ]; then
        # Lock timeout

        # Show "Processing..." notification on first retry only
        if [ $attempt -eq 1 ] && command -v kdialog >/dev/null 2>&1; then
            track_title=$(audtool --current-song-tuple-data title 2>/dev/null || basename "$FILEPATH")
            track_artist=$(audtool --current-song-tuple-data artist 2>/dev/null || basename "$FILEPATH")
            if [ "$STAR_RATING" -gt 0 ]; then
                star_display="⭐$(seq -s'⭐' 1 $((STAR_RATING-1)) )"
            else
                star_display="Unrated"
            fi
            kdialog --title 'Rating Update' --passivepopup \
                "Rating $star_display for \"$track_title\" processing..." 6 &
            NOTIFICATION_PID=$!
            SHOWED_PROCESSING=true
        fi

        # Retry if not last attempt
        if [ $attempt -lt $MAX_ATTEMPTS ]; then
            sleep $RETRY_DELAY
            attempt=$((attempt + 1))
        else
            # Final attempt failed
            break
        fi
    else
        # Other error (not timeout) - don't retry
        break
    fi
done

# Kill the "Processing..." notification if still running
if [ -n "$NOTIFICATION_PID" ]; then
    kill $NOTIFICATION_PID 2>/dev/null || true
fi

# Handle result
if [ "$success" = false ]; then
    # All retries failed - queue the operation for later processing
    PENDING_FILE="${MUSICLIB_ROOT}/data/.pending_operations"
    TIMESTAMP=$(date +%s)

    # Ensure pending operations directory exists
    mkdir -p "$(dirname "$PENDING_FILE")" 2>/dev/null || true

    # Queue the rating operation
    echo "$TIMESTAMP|musiclib_rate.sh|rate|$FILEPATH|$STAR_RATING" >> "$PENDING_FILE"

    # Show user feedback - rating is queued
    if command -v kdialog >/dev/null 2>&1; then
        track_title=$(audtool --current-song-tuple-data title 2>/dev/null || basename "$FILEPATH")
        star_display="⭐$(seq -s'⭐' 1 $STAR_RATING | sed 's/[0-9]//g')"
        kdialog --title 'Rating Queued' --passivepopup \
            "Rating $star_display for $track_artist" - "$track_title queued (database busy)..." 5 &
    fi

    # Log the queued operation
    if command -v log_message >/dev/null 2>&1; then
        log_message "PENDING: Rating $FILEPATH -> $STAR_RATING stars (database locked)"
    fi

    # Exit with code 3 = "operation queued"
    error_exit 3 "Operation queued due to database lock contention" \
        "timeout" "${MAX_ATTEMPTS}x${RETRY_DELAY}s" "filepath" "$FILEPATH" "stars" "$STAR_RATING"
    exit 3
fi

#############################################
# Update Conky Display Files
#############################################
echo "Updating Conky display..."

# Create directory if it doesn't exist
if [ ! -d "$MUSIC_DIR" ]; then
    if ! mkdir -p "$MUSIC_DIR" 2>/dev/null; then
        error_exit 2 "Failed to create Conky output directory" "directory" "$MUSIC_DIR"
        exit 2
    fi
fi

# Update currgpnum.txt
if ! echo "$GROUPDESC_VALUE" > "$MUSIC_DIR/currgpnum.txt" 2>/dev/null; then
    error_exit 2 "Failed to update currgpnum.txt" "filepath" "$MUSIC_DIR/currgpnum.txt"
    exit 2
fi

# Update star rating image
rm -f "$MUSIC_DIR/starrating.png"

if [ -n "$IMAGE_FILE" ] && [ -f "$STAR_DIR/$IMAGE_FILE" ]; then
    if ! cp "$STAR_DIR/$IMAGE_FILE" "$MUSIC_DIR/starrating.png" 2>/dev/null; then
        error_exit 2 "Failed to copy rating image" "source" "$STAR_DIR/$IMAGE_FILE" "dest" "$MUSIC_DIR/starrating.png"
        exit 2
    fi
    echo "  ✓ Rating image updated: $IMAGE_FILE"
else
    # This is a warning - star images may not be set up yet
    echo "  Warning: Rating image not found: $STAR_DIR/$IMAGE_FILE" >&2
fi

#############################################
# Show Notification
#############################################
# Only show success notification if we didn't show "Processing..." notification
# (if we showed processing, the user knows it succeeded because it disappeared)
if [ "$SHOWED_PROCESSING" = false ] && command -v kdialog >/dev/null 2>&1; then
    track_title=$(audtool --current-song-tuple-data title 2>/dev/null || basename "$FILEPATH")

    if [ "$STAR_RATING" -eq 0 ]; then
        kdialog --title 'Rating Updated' --passivepopup "\"$track_title\" marked as needing rating" 3 &
    else
    star_display=$(LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 printf '★%.0s' $(seq 1 $STAR_RATING))
    kdialog --title 'Rating Updated' --passivepopup "\"$track_title\" rated: $star_display" 3 &
    fi
fi

echo "✓ Rating complete!"

# Log the operation if logging is available
if command -v log_message >/dev/null 2>&1; then
    log_message "Rated track: $(basename "$FILEPATH") -> $STAR_RATING stars"
fi

#############################################
# Process Any Other Pending Operations
#############################################
# After successfully updating, process any other queued operations
if [ -f "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" ]; then
    "$MUSICLIB_ROOT/bin/musiclib_process_pending.sh" &
fi

exit 0
