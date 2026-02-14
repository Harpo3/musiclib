#!/bin/bash
#
# musiclib_utils.sh - Shared utility functions for musiclib scripts
# Source this file in other scripts: source "$MUSICLIB_ROOT/bin/musiclib_utils.sh"
#
set -u
set -o pipefail

#############################################
# BACKEND API VERSION
#############################################

# Backend API version - checked by GUI/CLI for compatibility
BACKEND_API_VERSION="1.0"

#############################################
# XDG BASE DIRECTORY SUPPORT
#############################################

# Get XDG-compliant config directory
# Returns: ~/.config/musiclib (or $XDG_CONFIG_HOME/musiclib if set)
get_xdg_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/musiclib"
}

# Get XDG-compliant data directory
# Returns: ~/.local/share/musiclib (or $XDG_DATA_HOME/musiclib if set)
get_xdg_data_dir() {
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/musiclib"
}

# Detect configuration directory (XDG or legacy)
# Returns: Path to config directory that exists, or XDG path if neither exists
get_config_dir() {
    local xdg_config="$(get_xdg_config_dir)"
    local legacy_config="$HOME/musiclib/config"
    
    if [ -d "$xdg_config" ]; then
        echo "$xdg_config"
    elif [ -d "$legacy_config" ]; then
        echo "$legacy_config"
    else
        # Default to XDG for new installations
        echo "$xdg_config"
    fi
}

# Detect data directory (XDG or legacy)
# Returns: Path to data directory that exists, or XDG path if neither exists
get_data_dir() {
    local xdg_data="$(get_xdg_data_dir)"
    local legacy_data="$HOME/musiclib/data"
    
    if [ -d "$xdg_data" ]; then
        echo "$xdg_data"
    elif [ -d "$legacy_data" ]; then
        echo "$legacy_data"
    else
        # Default to XDG for new installations
        echo "$xdg_data"
    fi
}

#############################################
# CONFIGURATION MANAGEMENT
#############################################

# Load configuration
load_config() {
    local config_dir

    # Use XDG-aware detection if MUSICLIB_ROOT not set
    if [ -n "${MUSICLIB_ROOT:-}" ]; then
        config_dir="${MUSICLIB_ROOT}/config"
    else
        config_dir="$(get_config_dir)"
    fi

    local config_file="$config_dir/musiclib.conf"
    if [ ! -f "$config_file" ]; then
        echo "Error: Configuration file not found: $config_file" >&2
        echo "Please run the setup script first." >&2
        return 1
    fi
    source "$config_file"
    return 0
}

#############################################
# DEPENDENCY VALIDATION
#############################################

# Validate required dependencies
validate_dependencies() {
    local missing=()

    command -v "$EXIFTOOL_CMD" >/dev/null 2>&1 || missing+=("exiftool")
    command -v "$KID3_CMD" >/dev/null 2>&1 || missing+=("kid3-cli")
    command -v "$KDECONNECT_CMD" >/dev/null 2>&1 || missing+=("kdeconnect-cli")
    command -v bc >/dev/null 2>&1 || missing+=("bc")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}" >&2
        return 1
    fi

    return 0
}

# Check for required tools from a list
# Usage: check_required_tools "tool1" "tool2" "tool3"
# Returns: 0 if all found, 1 if any missing (with error message)
check_required_tools() {
    local missing=()

    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing[*]}" >&2
        return 1
    fi

    return 0
}

#############################################
# DATABASE HELPERS
#############################################

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

    # Search for existing album (exact match on second field)
    local idalbum=$(awk -F'^' -v album="$album_name" '$4 == album {print $3; exit}' "$db_file")

    if [ -n "$idalbum" ]; then
        echo "$idalbum"
        return 0
    fi

    # Create new IDAlbum (max existing + 1)
    local max_idalbum=$(tail -n +2 "$db_file" | cut -d'^' -f3 | grep -E '^[0-9]+$' | sort -n | tail -n1)

    if [ -z "$max_idalbum" ]; then
        echo "1"
    else
        echo $((max_idalbum + 1))
    fi
}

# Convert epoch seconds to SQL serial time format
epoch_to_sql_time() {
    local epoch="$1"
    printf "%.6f" "$(echo "$epoch/86400 + 25569" | bc -l)"
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
# METADATA EXTRACTION
#############################################

# Get song length in milliseconds from file
get_song_length_ms() {
    local filepath="$1"

    local duration_str=$($EXIFTOOL_CMD -Duration -s3 "$filepath" 2>/dev/null)

    if [ -z "$duration_str" ]; then
        echo "0"
        return 0
    fi

    # Check if duration contains colon (HH:MM:SS or MM:SS format)
    if [[ "$duration_str" =~ : ]]; then
        IFS=: read -r h m s <<< "$duration_str"
        if [ -z "$s" ]; then
            # MM:SS format
            s=$m
            m=$h
            h=0
        fi
        echo "($h * 3600 + $m * 60 + $s) * 1000" | bc | cut -d. -f1
    else
        # Already in seconds, convert to milliseconds
        echo "$duration_str * 1000" | bc | cut -d. -f1
    fi
}

# Format song length as seconds with 000 suffix
format_song_length() {
    local length_ms="$1"

    if [ -z "$length_ms" ] || [ "$length_ms" = "0" ]; then
        echo "0"
        return 0
    fi

    # Convert milliseconds to seconds and append 000
    local seconds=$(echo "$length_ms / 1000" | bc)
    echo "${seconds}000"
}

# Extract metadata from audio file
extract_metadata() {
    local filepath="$1"

    if [ ! -f "$filepath" ]; then
        echo "Error: File not found: $filepath" >&2
        return 1
    fi

    local artist=$($EXIFTOOL_CMD -Artist -s3 "$filepath" 2>/dev/null)
    local album=$($EXIFTOOL_CMD -Album -s3 "$filepath" 2>/dev/null)
    local albumartist=$($EXIFTOOL_CMD -AlbumArtist -s3 "$filepath" 2>/dev/null)
    local title=$($EXIFTOOL_CMD -Title -s3 "$filepath" 2>/dev/null)
    local genre=$($EXIFTOOL_CMD -Genre -s3 "$filepath" 2>/dev/null)

    # If Title is empty, use filename without extension
    if [ -z "$title" ]; then
        title=$(basename "$filepath" | sed 's/\.[^.]*$//')
    fi

    # Output as delimited string for easy parsing
    echo "${artist}^${album}^${albumartist}^${title}^${genre}"
}

# Get tag information for an audio file
# Returns: "has_v1,has_v2,has_ape"
get_tag_info() {
    local filepath="$1"
    local has_v1=false
    local has_v2=false
    local has_ape=false

    # Check for ID3v1
    if $EXIFTOOL_CMD -ID3 "$filepath" 2>/dev/null | grep -q "ID3v1"; then
        has_v1=true
    fi

    # Check for ID3v2
    if $EXIFTOOL_CMD "$filepath" 2>/dev/null | grep -q "ID3v2"; then
        has_v2=true
    fi

    # Check for APE
    if $EXIFTOOL_CMD "$filepath" 2>/dev/null | grep -qi "APE"; then
        has_ape=true
    fi

    echo "${has_v1},${has_v2},${has_ape}"
}

# Check if file has embedded album art
has_embedded_art() {
    local filepath="$1"

    # Check if Picture tag exists
    if $EXIFTOOL_CMD "$filepath" 2>/dev/null | grep -q "Picture"; then
        return 0
    fi

    return 1
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

#############################################
# LOGGING AND BACKUP
#############################################

# Log message to log file and stdout
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] $message" | tee -a "$LOGFILE" 2>/dev/null || echo "[$timestamp] $message"
}

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

# Cleanup old files matching pattern in directory
# Usage: cleanup_old_files <directory> <pattern> <days_old>
# Example: cleanup_old_files "$BACKUP_DIR" "*.mp3.backup.*" 30
cleanup_old_files() {
    local directory="$1"
    local pattern="$2"
    local days_old="$3"

    if [ ! -d "$directory" ]; then
        return 0
    fi

    find "$directory" -name "$pattern" -type f -mtime +"$days_old" -delete 2>/dev/null || true
}

#############################################
# ERROR HANDLING AND LOCKING
#############################################

# Global variables for database locking
DB_LOCK_FD=""
DB_LOCK_FILE=""

# Standardized error reporting with JSON output
# Usage: error_exit exit_code error_message [context_key context_value ...]
# Returns: The exit code (does NOT exit - calling script decides)
# Output: JSON error to stderr
error_exit() {
    local exit_code="$1"
    local error_msg="$2"
    shift 2
    
    # Detect script name
    local script_name="unknown"
    if [ -n "$0" ]; then
        script_name=$(basename "$0")
    fi
    
    # Build context object from key-value pairs
    local context="{"
    local first=true
    while [ $# -ge 2 ]; do
        [ "$first" = false ] && context="${context},"
        # Escape quotes in values
        local key="$1"
        local value="${2//\"/\\\"}"
        context="${context}\"${key}\":\"${value}\""
        first=false
        shift 2
    done
    context="${context}}"
    
    # Build JSON error object
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local json_error="{\"error\":\"${error_msg//\"/\\\"}\",\"script\":\"${script_name}\",\"code\":${exit_code},\"context\":${context},\"timestamp\":\"${timestamp}\"}"
    
    # Output to stderr
    echo "$json_error" >&2
    
    # Return the exit code (don't exit!)
    return "$exit_code"
}

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
