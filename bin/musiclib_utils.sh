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
    local system_config="${MUSICLIB_SYSTEM_CONFIG_DIR:-/usr/lib/musiclib/config}/musiclib.conf"
    local user_config

    # Determine user config location
    if [ -n "${MUSICLIB_CONFIG_DIR:-}" ]; then
        user_config="${MUSICLIB_CONFIG_DIR}/musiclib.conf"
    elif [ -n "${MUSICLIB_ROOT:-}" ] && [ -f "${MUSICLIB_ROOT}/config/musiclib.conf" ]; then
        user_config="${MUSICLIB_ROOT}/config/musiclib.conf"
    else
        user_config="$(get_config_dir)/musiclib.conf"
    fi

    # Load system defaults first
    if [ -f "$system_config" ]; then
        source "$system_config"
    fi

    # User config overrides system defaults
    if [ -f "$user_config" ]; then
        source "$user_config"
    fi

    # If neither exists, error
    if [ ! -f "$system_config" ] && [ ! -f "$user_config" ]; then
        echo "Error: No configuration found" >&2
        echo "Please run 'musiclib-cli setup' first." >&2
        return 1
    fi

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
# TIME CONVERSION
#############################################

# Convert epoch seconds to SQL serial time format
epoch_to_sql_time() {
    local epoch="$1"
    printf "%.6f" "$(echo "$epoch/86400 + 25569" | bc -l)"
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

    # Strip trailing units or annotations that exiftool may append
    # (e.g. "243.19 s", "3:42 (approx)") so the value is clean for bc.
    duration_str="${duration_str%% *}"

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

# Sanitize a tag value for safe storage in the DSV database.
# Removes/transliterates characters that break kid3-cli command quoting,
# corrupt filenames, or cause display/parsing inconsistencies:
#   - Accented/non-ASCII characters are transliterated to their closest ASCII
#     equivalent (é→e, ü→u, ñ→n, etc.) so values are consistent across paths
#   - Single quotes (') break kid3-cli's command-string quoting
#   - Commas (,) cause inconsistent display in the library UI
# Usage: sanitize_tag_value "value"
# Returns: sanitized value safe for the DSV database and kid3-cli commands
sanitize_tag_value() {
    local value
    # Transliterate accented/non-ASCII to ASCII; fall back to original on error
    value=$(printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT//IGNORE 2>/dev/null) || value="$1"
    printf '%s' "$value" | tr -d "',"
}

# Validate that a DSV entry has the correct number of fields before writing.
# The musiclib DSV schema has 15 fields (13 named + 2 trailing empty),
# separated by 14 caret (^) delimiters.
# Usage: validate_entry_fields "entry_string"
# Returns: 0 if field count is correct, 1 if wrong (prints error to stderr)
validate_entry_fields() {
    local entry="$1"
    local expected_delimiters=14   # 15 fields = 14 ^ separators
    local actual_delimiters
    actual_delimiters=$(printf '%s' "$entry" | tr -cd '^' | wc -c)
    if [ "$actual_delimiters" -ne "$expected_delimiters" ]; then
        echo "ERROR: DB entry has wrong field count (expected 15 fields / 14 delimiters, got $((actual_delimiters + 1)) fields): $entry" >&2
        return 1
    fi
    return 0
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

    # Sanitize values before writing to the DSV database
    artist="$(sanitize_tag_value "$artist")"
    album="$(sanitize_tag_value "$album")"
    albumartist="$(sanitize_tag_value "$albumartist")"
    title="$(sanitize_tag_value "$title")"
    genre="$(sanitize_tag_value "$genre")"

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
# LOGGING
#############################################

# Log message to log file and stdout.
# LOGFILE is not set by every script that sources this file; default to
# /dev/null so the `tee` does not error under `set -u` and the fallback echo
# still reaches stdout.  Without this default, scripts that use `set -u`
# (e.g. musiclib_player_event.sh) crash on the first log_message call.
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] $message" | tee -a "${LOGFILE:-/dev/null}" 2>/dev/null || echo "[$timestamp] $message"
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
# ERROR HANDLING
#############################################

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
