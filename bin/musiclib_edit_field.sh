#!/bin/bash
#
# musiclib_edit_field.sh - Edit a single metadata field in a database record
# Usage: musiclib_edit_field.sh <record_id> <field_name> <new_value>
#
# Updates the named field for the record with the given ID in the DSV database.
# For most fields only the DSV record is changed.
# Exception — Custom2: the Songs-DB_Custom2 tag is also written to the audio
# file via kid3-cli so the value survives a full database rebuild.
#
# Supported field names:
#   Artist, Album, AlbumArtist, SongTitle, Genre, Custom2
#
# Exit codes:
#   0 - Success
#   1 - User error (invalid field, record not found, bad value)
#   2 - System error (config failure, DB not found, I/O error, lock timeout)

set -e
set -u
set -o pipefail

export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! source "$SCRIPT_DIR/musiclib_utils.sh" 2>/dev/null; then
    echo '{"error":"musiclib_utils.sh not found","script":"musiclib_edit_field.sh","code":2}' >&2
    exit 2
fi

if ! load_config 2>/dev/null; then
    error_exit 2 "Failed to load configuration"
    exit 2
fi

MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"

#############################################
# Validate Arguments
#############################################

if [ $# -lt 3 ]; then
    echo "Usage: $0 <record_id> <field_name> <new_value>"
    echo ""
    echo "Supported field names: Artist, Album, AlbumArtist, SongTitle, Genre, Custom2"
    exit 1
fi

RECORD_ID="$1"
FIELD_NAME="$2"
NEW_VALUE="$3"

if [ -z "$RECORD_ID" ]; then
    error_exit 1 "Record ID cannot be empty"
    exit 1
fi

# Whitelist: only these DSV column names are editable
# A.5: Custom2 added to allow the "Custom Artist" cell to be edited via the GUI
case "$FIELD_NAME" in
    Artist|Album|AlbumArtist|SongTitle|Genre|Custom2) ;;
    *)
        error_exit 1 "Unsupported field name" \
            "field" "$FIELD_NAME" \
            "supported" "Artist, Album, AlbumArtist, SongTitle, Genre, Custom2"
        exit 1
        ;;
esac

# Reject values containing the DSV delimiter (^) — would corrupt the file
if [[ "$NEW_VALUE" == *$'^'* ]]; then
    error_exit 1 "New value contains the DSV delimiter (^)" "field" "$FIELD_NAME"
    exit 1
fi

if [ ! -f "$MUSICDB" ]; then
    error_exit 2 "Database file not found" "database" "$MUSICDB"
    exit 2
fi

#############################################
# Update Function (called inside lock)
#############################################

do_edit() {
    # Find the column number for the requested field from the DSV header.
    # grep -n "^FIELDNAME$" gives us an exact match on the field name.
    local colnum
    colnum=$(head -1 "$MUSICDB" | tr '^' '\n' | grep -n "^${FIELD_NAME}$" | cut -d: -f1)

    if [ -z "$colnum" ]; then
        echo "Error: Column '$FIELD_NAME' not found in database header" >&2
        return 2
    fi

    # Verify the record ID exists (skip header row with NR > 1)
    local match_count
    match_count=$(awk -F'^' -v id="$RECORD_ID" 'NR > 1 && $1 == id { count++ } END { print count+0 }' "$MUSICDB")

    if [ "$match_count" -eq 0 ]; then
        echo "Error: No record found with ID '$RECORD_ID'" >&2
        return 1
    fi

    # Update the field — match by ID in column 1, leave header (NR==1) untouched
    if ! awk -F'^' -v OFS='^' \
        -v record_id="$RECORD_ID" \
        -v col="$colnum" \
        -v newval="$NEW_VALUE" \
        'NR > 1 && $1 == record_id { $col = newval } { print }' \
        "$MUSICDB" > "$MUSICDB.tmp" 2>/dev/null; then
        rm -f "$MUSICDB.tmp"
        echo "Error: awk failed to process database" >&2
        return 2
    fi

    if ! mv "$MUSICDB.tmp" "$MUSICDB" 2>/dev/null; then
        rm -f "$MUSICDB.tmp"
        echo "Error: Failed to write updated database" >&2
        return 2
    fi

    return 0
}

#############################################
# Execute with Lock and Retry
#############################################

echo "Updating $FIELD_NAME for record $RECORD_ID..."

MAX_ATTEMPTS=3
RETRY_DELAY=2
attempt=1
success=false

while [ $attempt -le $MAX_ATTEMPTS ]; do
    with_db_lock 2 do_edit
    lock_result=$?

    if [ "$lock_result" -eq 0 ]; then
        success=true
        break
    elif [ "$lock_result" -eq 1 ]; then
        # Lock timeout — retry if not last attempt
        if [ $attempt -lt $MAX_ATTEMPTS ]; then
            sleep $RETRY_DELAY
            attempt=$((attempt + 1))
        else
            break
        fi
    else
        # Validation or I/O error — don't retry
        error_exit 1 "Failed to update field" "field" "$FIELD_NAME" "record" "$RECORD_ID"
        exit 1
    fi
done

if [ "$success" = false ]; then
    error_exit 2 "Database lock timeout after $MAX_ATTEMPTS attempts" \
        "timeout" "${MAX_ATTEMPTS}x${RETRY_DELAY}s" "record" "$RECORD_ID"
    exit 2
fi

#############################################
# Success
#############################################

echo "✓ $FIELD_NAME updated for record $RECORD_ID"

#############################################
# Custom2: also write tag to the audio file
# so the value survives a database rebuild.
#############################################

if [[ "$FIELD_NAME" == "Custom2" ]]; then
    # Locate the SongPath column number from the header
    pathcol=$(head -1 "$MUSICDB" | tr '^' '\n' | grep -n "^SongPath$" | cut -d: -f1)

    if [[ -n "$pathcol" ]]; then
        song_path=$(awk -F'^' -v id="$RECORD_ID" -v pcol="$pathcol" \
            'NR > 1 && $1 == id { print $pcol; exit }' "$MUSICDB")

        if [[ -n "$song_path" ]] && [[ -f "$song_path" ]]; then
            if command -v kid3-cli >/dev/null 2>&1; then
                # Escape any double-quotes in the value before embedding in the
                # -c string (artist names rarely contain them, but be safe).
                escaped_value=$(printf '%s' "$NEW_VALUE" | sed 's/["\\]/\\&/g')
                if kid3-cli -c "set Songs-DB_Custom2 \"$escaped_value\"" \
                       "$song_path" 2>/dev/null; then
                    echo "✓ Songs-DB_Custom2 tag written to file: $(basename "$song_path")"
                else
                    echo "Warning: kid3-cli failed to write tag — database updated but file tag unchanged" >&2
                fi
            else
                echo "Warning: kid3-cli not found — database updated but file tag not written" >&2
            fi
        else
            echo "Warning: SongPath not found or file missing for record $RECORD_ID — database updated but file tag not written" >&2
        fi
    else
        echo "Warning: SongPath column not found in database header — file tag not written" >&2
    fi
fi

if command -v log_message >/dev/null 2>&1; then
    log_message "Edited $FIELD_NAME for record $RECORD_ID via GUI"
fi

exit 0
