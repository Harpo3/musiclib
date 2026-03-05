#!/bin/bash
#
# musiclib_remove_record.sh - Remove a single track record from the database
# Usage: musiclib_remove_record.sh <filepath> [record_id] [--delete-file]
#
# Removes the database row matching the given file path.
# By default the audio file on disk is NOT deleted — only the DSV record is
# removed.  Pass --delete-file to also remove the audio file after the DB row
# has been successfully deleted.
#
# When record_id is provided, only the row whose ID field AND SongPath field
# both match is removed.  This is the preferred mode when called from the GUI
# context menu, because it targets exactly one row even if duplicates exist.
#
# When record_id is omitted, falls back to delete_record_by_path() which
# matches on file path alone (legacy behaviour, kept for CLI use).
#
# This is a thin wrapper around delete_record_by_id_and_path() (or
# delete_record_by_path() for the legacy path) in musiclib_utils.sh.
# It handles config loading, argument validation, and database locking so
# the GUI (QProcess) has a single script to invoke.
#
# Exit codes:
#   0 - Success (record removed; file also deleted when --delete-file was given)
#   1 - User error (no match, multiple matches, missing argument)
#   2 - System error (config failure, DB not found, I/O error, lock timeout)

export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source utilities - REQUIRED for locking and error handling
if ! source "$SCRIPT_DIR/musiclib_utils.sh" 2>/dev/null; then
    echo '{"error":"musiclib_utils.sh not found","script":"musiclib_remove_record.sh","code":2,"context":{"expected_path":"'"$SCRIPT_DIR/musiclib_utils.sh"'"},"timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' >&2
    exit 2
fi

# Load configuration
if ! load_config 2>/dev/null; then
    error_exit 2 "Failed to load configuration"
    exit 2
fi

MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"

#############################################
# Validate Input
#############################################
if [ $# -eq 0 ]; then
    echo "Usage: $0 <filepath> [record_id] [--delete-file]"
    echo ""
    echo "Remove a track record from the MusicLib database."
    echo "By default the audio file on disk is NOT deleted."
    echo ""
    echo "Arguments:"
    echo "  filepath       Absolute path to the audio file whose"
    echo "                 database record should be removed."
    echo "  record_id      (Optional) The numeric ID field from the DSV record."
    echo "                 When provided, only the row matching BOTH id AND filepath"
    echo "                 is removed — safe to use when duplicates exist."
    echo "  --delete-file  (Optional) Also delete the audio file from disk after"
    echo "                 the database record has been removed."
    exit 1
fi

FILEPATH="$1"
RECORD_ID=""
DELETE_FILE=false

# Parse remaining optional arguments (record_id and/or --delete-file)
for arg in "${@:2}"; do
    if [ "$arg" = "--delete-file" ]; then
        DELETE_FILE=true
    elif [ -z "$RECORD_ID" ]; then
        RECORD_ID="$arg"
    fi
done

if [ -z "$FILEPATH" ]; then
    error_exit 1 "File path cannot be empty"
    exit 1
fi

# Note: we do NOT check whether the file exists on disk.
# The user may be removing an orphaned record whose file was already deleted.

if [ ! -f "$MUSICDB" ]; then
    error_exit 2 "Database file not found" "database" "$MUSICDB"
    exit 2
fi

#############################################
# Remove Record with Locking
#############################################
echo "Removing record: $(basename "$FILEPATH")"

# Define the delete function to be called within lock.
# If a record ID was supplied, use the precise ID+path match so that only
# the selected row is removed even when duplicate path entries exist.
# Otherwise fall back to the legacy path-only search.
do_delete() {
    if [ -n "$RECORD_ID" ]; then
        delete_record_by_id_and_path "$MUSICDB" "$RECORD_ID" "$FILEPATH"
    else
        delete_record_by_path "$MUSICDB" "$FILEPATH"
    fi
}

# Attempt with retry (same pattern as musiclib_rate.sh)
MAX_ATTEMPTS=3
RETRY_DELAY=2
attempt=1
success=false

while [ $attempt -le $MAX_ATTEMPTS ]; do
    with_db_lock 2 do_delete
    lock_result=$?
    if [ "$lock_result" -eq 0 ]; then
        success=true
        break
    fi
    if [ "$lock_result" -eq 1 ]; then
        # Lock timeout — retry if not last attempt
        if [ $attempt -lt $MAX_ATTEMPTS ]; then
            sleep $RETRY_DELAY
            attempt=$((attempt + 1))
        else
            break
        fi
    else
        # Validation or I/O error from delete_record_by_path — don't retry
        error_exit 1 "Failed to remove record" "filepath" "$FILEPATH"
        exit 1
    fi
done

if [ "$success" = false ]; then
    error_exit 2 "Database lock timeout after $MAX_ATTEMPTS attempts" \
        "timeout" "${MAX_ATTEMPTS}x${RETRY_DELAY}s" "filepath" "$FILEPATH"
    exit 2
fi

#############################################
# Success — DB record removed
#############################################
echo "✓ Record removed: $(basename "$FILEPATH")"

if command -v log_message >/dev/null 2>&1; then
    log_message "Removed DB record via GUI: $(basename "$FILEPATH")"
fi

#############################################
# Optional: delete the audio file from disk
#############################################
if [ "$DELETE_FILE" = true ]; then
    if [ -f "$FILEPATH" ]; then
        if rm -- "$FILEPATH" 2>/dev/null; then
            echo "✓ File deleted: $(basename "$FILEPATH")"
            if command -v log_message >/dev/null 2>&1; then
                log_message "Deleted audio file via GUI: $(basename "$FILEPATH")"
            fi
            if command -v kdialog >/dev/null 2>&1; then
                kdialog --title 'Record & File Removed' --passivepopup \
                    "Removed record and deleted file: $(basename "$FILEPATH")" 3 &
            fi
        else
            # DB removal already succeeded; report the file-deletion failure
            # as a non-fatal warning on stderr but still exit 0 so the GUI
            # refreshes the view.
            echo "Warning: could not delete file: $FILEPATH" >&2
            if command -v kdialog >/dev/null 2>&1; then
                kdialog --title 'Record Removed' --passivepopup \
                    "Record removed but could not delete file: $(basename "$FILEPATH")" 4 &
            fi
        fi
    else
        # File does not exist on disk (orphaned record) — nothing to delete
        echo "Note: file not found on disk (orphaned record): $FILEPATH"
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --title 'Record Removed' --passivepopup \
                "Record removed (file was already absent): $(basename "$FILEPATH")" 3 &
        fi
    fi
else
    if command -v kdialog >/dev/null 2>&1; then
        kdialog --title 'Record Removed' --passivepopup \
            "Removed: $(basename "$FILEPATH")" 3 &
    fi
fi

exit 0
