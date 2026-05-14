#!/bin/bash
#
# musiclib_db.sh - Database, backup, and locking functions for musiclib scripts
# Source this file in other scripts: source "$MUSICLIB_ROOT/bin/musiclib_db.sh"
# Depends on: musiclib_utils.sh (for log_message, error_exit)
#
set -u
set -o pipefail

#############################################
# DATABASE HELPERS
#############################################

# Resolve a column name to its 1-based awk field index from the DSV header.
# Usage: get_column_index <db_file> <col_name>
# Prints the column number (integer ≥ 1) on success.
# Prints an error message to stderr and returns 1 if the column is not found.
# Example: colnum=$(get_column_index "$MUSICDB" "SongPath")
get_column_index() {
    local db_file="$1"
    local col_name="$2"
    local colnum
    colnum=$(head -1 "$db_file" | tr '^' '\n' | grep -n "^${col_name}$" | cut -d: -f1)
    if [ -z "$colnum" ]; then
        echo "Error: Column '${col_name}' not found in database header of ${db_file}" >&2
        return 1
    fi
    echo "$colnum"
}

# Get next available ID from database
get_next_id() {
    local db_file="$1"

    if [ ! -f "$db_file" ]; then
        echo "Error: Database not found: $db_file" >&2
        return 1
    fi

    local last_id=$(tail -n 1 "$db_file" | cut -d'^' -f1)

    if [ -z "$last_id" ] || [ "$last_id" = "ID" ]; then
        echo "1"
    else
        echo $((last_id + 1))
    fi
}

# Find existing album ID or create new one
find_or_create_album() {
    local db_file="$1"
    local album_name="$2"

    if [ -z "$album_name" ]; then
        echo ""
        return 0
    fi

    # Resolve column indices from header (safe against schema changes).
    local albumcol idalbumcol
    albumcol=$(get_column_index "$db_file" "Album")    || return 1
    idalbumcol=$(get_column_index "$db_file" "IDAlbum") || return 1

    # Search for existing album (exact match on Album column).
    local idalbum
    idalbum=$(awk -F'^' -v album="$album_name" -v acol="$albumcol" -v icol="$idalbumcol" \
        '$acol == album { print $icol; exit }' "$db_file")

    if [ -n "$idalbum" ]; then
        echo "$idalbum"
        return 0
    fi

    # Create new IDAlbum (max existing + 1).
    local max_idalbum
    max_idalbum=$(tail -n +2 "$db_file" | cut -d'^' -f"${idalbumcol}" | grep -E '^[0-9]+$' | sort -n | tail -n1)

    if [ -z "$max_idalbum" ]; then
        echo "1"
    else
        echo $((max_idalbum + 1))
    fi
}

# Check if database file exists and is valid
validate_database() {
    local db_file="$1"

    if [ ! -f "$db_file" ]; then
        echo "Error: Database not found: $db_file" >&2
        return 1
    fi

    # Check if header exists
    local header=$(head -n 1 "$db_file")
    if [[ ! "$header" =~ ^ID\^ ]]; then
        echo "Error: Invalid database format (missing header)" >&2
        return 1
    fi

    return 0
}

#############################################
# DATABASE UPDATE OPERATIONS
#############################################

# Update last played time in database and file tag
update_lastplayed() {
    local db_file="$1"
    local filepath="$2"
    local sql_time="$3"

    # Get LastTimePlayed column number
    local lpcolnum=$(head -1 "$db_file" | tr '^' '\n' | cat -n | grep "LastTimePlayed" | sed -r 's/^([^.]+).*$/\1/; s/^[^0-9]*([0-9]+).*$/\1/')

    if [ -z "$lpcolnum" ]; then
        echo "Error: Could not find LastTimePlayed column in database" >&2
        return 1
    fi

    # Find track in database
    local grepped_string=$(grep -nF "$filepath" "$db_file" 2>/dev/null)

    if [ -z "$grepped_string" ]; then
        echo "Error: Track not found in database: $filepath" >&2
        return 1
    fi

    # Extract row number and old value
    local myrow=$(echo "$grepped_string" | cut -f1 -d:)
    local row_data=$(echo "$grepped_string" | cut -f2- -d:)
    local old_value=$(echo "$row_data" | cut -f"$lpcolnum" -d"^" | xargs)

    # Update database - applies change only to the target column
    if ! awk -F'^' -v OFS='^' -v row="$myrow" -v col="$lpcolnum" -v newval="$sql_time" \
        'NR == row { $col = newval } { print }' \
        "$db_file" > "$db_file.tmp" 2>/dev/null; then
        echo "Error: Failed to update database" >&2
        rm -f "$db_file.tmp"
        return 1
    fi

    mv "$db_file.tmp" "$db_file"

# Update tag using kid3-cli with repair on failure
    if ! $KID3_CMD -c "set Songs-DB_Custom1 $sql_time" "$filepath" 2>/dev/null; then
        log_message "Tag write failed for Songs-DB_Custom1, attempting repair..."
        # rebuild_tag is called from musiclib_utils_tag_functions.sh
        if rebuild_tag "$filepath"; then
            log_message "Tag rebuild successful, retrying write..."

            # Retry the tag write after rebuild
            if ! $KID3_CMD -c "set Songs-DB_Custom1 $sql_time" "$filepath" 2>/dev/null; then
                log_message "ERROR: Tag write still failed after rebuild for $filepath"
                return 1
            fi

            log_message "Tag write successful after rebuild"
        else
            log_message "ERROR: Tag rebuild failed for $filepath"
            return 1
        fi
    fi

   return 0
}

# Remove a track record (or records) from the database by file path
# Usage: delete_record_by_path "$MUSICDB" "/path/to/file.mp3"
# Behavior:
#   - If exactly one matching row is found, it is removed and 0 is returned.
#   - If no rows match, shows a kdialog notice and returns 1.
#   - If multiple rows match, shows a kdialog yes/no confirmation asking whether
#     to proceed.  Yes deletes all matching rows; No exits safely with return 1.
#   - Caller is responsible for acquiring the database lock (with_db_lock).

delete_record_by_path() {
    local db_file="$1"
    local filepath="$2"

    if [ ! -f "$db_file" ]; then
        echo "Error: Database not found: $db_file" >&2
        return 1
    fi

    # Find all matching rows (line numbers) for this path
    local matches
    matches=$(grep -nF "$filepath" "$db_file" 2>/dev/null || true)

    if [ -z "$matches" ]; then
        echo "Error: Track not found in database: $filepath" >&2
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --title 'Delete Failed' --passivepopup \
                "Track not found in database. It may have already been removed.\n$filepath" 5 &
        fi
        return 1
    fi

    # Count matches
    local match_count
    match_count=$(printf '%s\n' "$matches" | wc -l)

    if [ "$match_count" -ne 1 ]; then
        echo "Warning: Found $match_count matching records for path: $filepath" >&2
        printf '%s\n' "$matches" >&2

        # Prompt the user whether to delete all matching rows.
        # kdialog --yesno returns 0 for Yes, 1 for No/Cancel.
        if command -v kdialog >/dev/null 2>&1; then
            if ! kdialog --title 'Multiple Records Found' --yesno \
                "Found $match_count matching records for:\n$filepath\n\nAre you sure you want to delete all of them?"; then
                echo "Deletion cancelled by user." >&2
                return 1
            fi
        else
            # No GUI available — refuse to delete ambiguous matches
            echo "Error: Found $match_count matching records and no GUI available to confirm. Resolve manually." >&2
            return 1
        fi

        # User confirmed — delete every matching row.
        # Build a space-separated list of row numbers and let awk skip them all.
        local row_numbers
        row_numbers=$(printf '%s\n' "$matches" | cut -d: -f1 | tr '\n' ' ')

        if ! awk 'BEGIN { n=split(rows, arr); for(i=1;i<=n;i++) skip[arr[i]]=1 }
                  !(NR in skip) { print }' \
             rows="$row_numbers" "$db_file" > "${db_file}.tmp" 2>/dev/null; then
            echo "Error: Failed to write temporary database while deleting records" >&2
            rm -f "${db_file}.tmp"
            return 1
        fi

        mv "${db_file}.tmp" "$db_file"
        log_message "Deleted $match_count DB records for $filepath (rows: $row_numbers)"
        return 0
    fi

    # Exactly one match — extract its row number and remove it
    local target_row
    target_row=$(printf '%s\n' "$matches" | cut -d: -f1)

    # Rewrite DB without the target row (header and all other rows preserved)
    if ! awk -v row="$target_row" 'NR != row { print }' "$db_file" > "${db_file}.tmp" 2>/dev/null; then
        echo "Error: Failed to write temporary database while deleting record" >&2
        rm -f "${db_file}.tmp"
        return 1
    fi

    mv "${db_file}.tmp" "$db_file"
    log_message "Deleted DB record for $filepath (row $target_row)"
    return 0
}

# Remove exactly one track record from the database by ID and file path.
# Usage: delete_record_by_id_and_path "$MUSICDB" "<record_id>" "/path/to/file.mp3"
# Behavior:
#   - Matches on BOTH field 1 (ID) AND field 7 (SongPath) simultaneously.
#   - If exactly one such row is found, it is removed and 0 is returned.
#   - If no row matches, shows a kdialog notice and returns 1.
#   - This function is safe to call when duplicates exist: only the row with
#     the specified ID is removed, leaving all other rows intact.
#   - Caller is responsible for acquiring the database lock (with_db_lock).

delete_record_by_id_and_path() {
    local db_file="$1"
    local record_id="$2"
    local filepath="$3"

    if [ ! -f "$db_file" ]; then
        echo "Error: Database not found: $db_file" >&2
        return 1
    fi

    # Resolve SongPath column index from header (safe against schema changes).
    local pathcol
    pathcol=$(get_column_index "$db_file" "SongPath") || return 1

    # Use awk to find rows where field 1 (ID) and SongPath column both match.
    # FS=^ matches the DSV caret delimiter.  NR==1 (header) is never a match.
    local match_count
    match_count=$(awk -F'^' -v id="$record_id" -v path="$filepath" -v pcol="$pathcol" \
        'NR > 1 && $1 == id && $pcol == path { count++ } END { print count+0 }' \
        "$db_file" 2>/dev/null)

    if [ "$match_count" -eq 0 ]; then
        echo "Error: No record found with ID=$record_id and path=$filepath" >&2
        if command -v kdialog >/dev/null 2>&1; then
            kdialog --title 'Delete Failed' --passivepopup \
                "Track not found in database (ID $record_id may have already been removed)." 5 &
        fi
        return 1
    fi

    # Rewrite the DB, keeping every row that does NOT match both ID and path.
    # The header row (NR==1) is always kept.
    if ! awk -F'^' -v id="$record_id" -v path="$filepath" -v pcol="$pathcol" \
        'NR == 1 || !($1 == id && $pcol == path) { print }' \
        "$db_file" > "${db_file}.tmp" 2>/dev/null; then
        echo "Error: Failed to write temporary database while deleting record" >&2
        rm -f "${db_file}.tmp"
        return 1
    fi

    mv "${db_file}.tmp" "$db_file"
    log_message "Deleted DB record ID=$record_id for $(basename "$filepath")"
    return 0
}

#############################################
# BACKUP FUNCTIONS
#############################################

# Create backup of database
backup_database() {
    local db_file="$1"
    local backup_dir=$(dirname "$db_file")
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${backup_dir}/musiclib.dsv.backup.${timestamp}"

    if [ -f "$db_file" ]; then
        cp "$db_file" "$backup_file"
        echo "Backup created: $backup_file"

        # Keep only last 5 backups
        ls -t "${backup_dir}"/musiclib.dsv.backup.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

        return 0
    fi

    return 1
}

# Create backup of any file with timestamp
# Usage: backup_file <filepath> <backup_dir>
# Returns: Outputs backup filename on success, empty on failure
backup_file() {
    local filepath="$1"
    local backup_dir="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local basename=$(basename "$filepath")
    local backup_file="$backup_dir/${basename}.backup.${timestamp}"

    if [ ! -f "$filepath" ]; then
        echo "Error: File not found: $filepath" >&2
        return 1
    fi

    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" || return 1
    fi

    cp "$filepath" "$backup_file" || return 1

    # Verify backup
    if ! cmp -s "$filepath" "$backup_file"; then
        echo "Error: Backup verification failed for $filepath" >&2
        rm -f "$backup_file"
        return 1
    fi

    echo "$backup_file"
    return 0
}

# Verify that a backup file matches the original
verify_backup() {
    local original="$1"
    local backup="$2"

    if [ ! -f "$original" ] || [ ! -f "$backup" ]; then
        return 1
    fi

    cmp -s "$original" "$backup"
    return $?
}

# Remove backup file
remove_backup() {
    local backup_file="$1"

    if [ -f "$backup_file" ]; then
        rm -f "$backup_file"
    fi
}

#############################################
# DATABASE LOCKING
#############################################

# Global variables for database locking
DB_LOCK_FD=""
DB_LOCK_FILE=""

# Acquire exclusive lock on database
# Usage: acquire_db_lock timeout_seconds
# Returns: 0 on success, 1 on timeout, 2 on error
# Sets global: DB_LOCK_FD (file descriptor)
acquire_db_lock() {
    local timeout="${1:-5}"

    # Determine lock file path
    if [ -z "$MUSICDB" ]; then
        error_exit 2 "MUSICDB not set - cannot acquire lock"
        return 2
    fi

    DB_LOCK_FILE="${MUSICDB}.lock"

    # Open lock file and get file descriptor
    # Use exec to assign to a variable FD
    exec {DB_LOCK_FD}>"$DB_LOCK_FILE" 2>/dev/null || {
        error_exit 2 "Cannot create lock file" "lockfile" "$DB_LOCK_FILE"
        return 2
    }

    # Try to acquire exclusive lock with timeout
    if flock -x -w "$timeout" "$DB_LOCK_FD" 2>/dev/null; then
        # Lock acquired successfully
        return 0
    else
        # Timeout - lock not available
        exec {DB_LOCK_FD}>&-  # Close file descriptor
        DB_LOCK_FD=""
        return 1
    fi
}

# Release database lock
# Usage: release_db_lock
# Returns: Always 0
release_db_lock() {
    if [ -n "$DB_LOCK_FD" ]; then
        # Release lock and close file descriptor
        flock -u "$DB_LOCK_FD" 2>/dev/null || true
        exec {DB_LOCK_FD}>&- 2>/dev/null || true
        DB_LOCK_FD=""
    fi
    return 0
}

# Execute command with database lock (automatic cleanup)
# Usage: with_db_lock timeout_seconds command [args...]
# Returns: Exit code of command
# Example: with_db_lock 5 update_database "$filepath"
with_db_lock() {
    local timeout="$1"
    shift
    (
        # Subshell isolates trap — caller's traps are unaffected
        trap 'release_db_lock 2>/dev/null' EXIT
        if ! acquire_db_lock "$timeout"; then
        exit $? # Propagates 1 (timeout) or 2 (error)
        fi
        "$@"
        # Exit code of callback propagates naturally
    )
}

# Execute command with database lock without a subshell.
# Unlike with_db_lock, the callback runs in the caller's shell process, so
# bash dynamic scoping lets it read and write the calling function's locals.
# Usage: with_db_lock_scope timeout_seconds command [args...]
# Returns: Exit code of command, or 1/2 on lock failure
with_db_lock_scope() {
    local _wdls_timeout="$1"
    shift
    local _wdls_prev_trap _wdls_rc
    _wdls_prev_trap=$(trap -p EXIT 2>/dev/null || true)
    trap 'release_db_lock 2>/dev/null' EXIT
    if ! acquire_db_lock "$_wdls_timeout"; then
        _wdls_rc=$?
        if [ -n "$_wdls_prev_trap" ]; then eval "$_wdls_prev_trap"; else trap - EXIT; fi
        return "$_wdls_rc"
    fi
    _wdls_rc=0
    "$@" || _wdls_rc=$?
    release_db_lock 2>/dev/null
    if [ -n "$_wdls_prev_trap" ]; then eval "$_wdls_prev_trap"; else trap - EXIT; fi
    return "$_wdls_rc"
}
