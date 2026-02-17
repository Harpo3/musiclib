#!/usr/bin/env bash
#############################################
# conform_musiclib.sh
# MusicLib Utility - Filename Conformance Tool
#
# Location: ~/.local/share/musiclib/utilities/conform_musiclib.sh
#
# Purpose: Rename non-conforming music filenames to conform to MusicLib
#          naming standards BEFORE database creation.
#
# Use Case: User has organized directories (artist/album/) but filenames
#           contain uppercase, spaces, or special characters.
#
# Naming Rules:
#   - Lowercase only
#   - Underscores instead of spaces
#   - Safe characters: a-z, 0-9, underscore, hyphen, period
#   - Non-ASCII transliterated to ASCII equivalents
#   - Single period before extension only
#
# Safety: Uses copy-verify-delete workflow to prevent data loss.
#         Requires --execute flag to make changes (dry-run by default).
#
# WARNING: This script modifies your files. Make backups first.
#          Use solely at your own risk.
#############################################

set -euo pipefail

#############################################
# Configuration
#############################################

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"

# XDG directories
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/musiclib"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/musiclib"
LOG_DIR="$DATA_DIR/logs"
UTILITIES_DIR="$DATA_DIR/utilities"

# Log file for this run
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="$LOG_DIR/conform_${TIMESTAMP}.log"

# Music file extensions to recognize
MUSIC_EXT_PATTERN='mp3|ogg|flac|wav|aac|m4a|wma|opus|aiff|alac|ape|mpc|wv'

# Counters
COUNT_SCANNED=0
COUNT_CONFORMING=0
COUNT_NONCONFORMING=0
COUNT_PROCESSED=0
COUNT_SKIPPED=0
COUNT_FAILED=0

# Flags
DRY_RUN=true
VERBOSE=false
MUSIC_REPO=""

#############################################
# Helper Functions
#############################################

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] [MUSIC_REPO]

Rename non-conforming music filenames to MusicLib naming standards.

This tool is for PRE-DATABASE use only. Run this BEFORE musiclib_init_config.sh
when your directories are organized but filenames need normalization.

OPTIONS:
    --execute       Actually rename files (default is dry-run preview)
    --dry-run       Preview changes without renaming (default)
    -v, --verbose   Show detailed output for each file
    -h, --help      Show this help message
    --version       Show version information

ARGUMENTS:
    MUSIC_REPO      Path to music repository (optional)
                    If omitted, reads from musiclib.conf or prompts

NAMING RULES:
    - Lowercase only (Track_01.mp3 -> track_01.mp3)
    - Spaces become underscores (My Song.mp3 -> my_song.mp3)
    - Special characters removed (Cafe.mp3 -> cafe.mp3)
    - Multiple underscores collapsed (a__b.mp3 -> a_b.mp3)

WORKFLOW:
    1. Scan all music files in repository
    2. Identify non-conforming filenames
    3. For each non-conforming file:
       - Copy to new conforming filename
       - Verify copy succeeded (size match)
       - Delete original file
    4. Log all actions

EXAMPLES:
    # Preview changes (dry-run)
    $SCRIPT_NAME /home/user/Music

    # Actually rename files
    $SCRIPT_NAME --execute /home/user/Music

    # Verbose dry-run
    $SCRIPT_NAME --verbose /home/user/Music

WARNING:
    This script modifies your files. Make backups first.
    Use solely at your own risk.

EOF
}

print_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Write to log file
    echo "$timestamp [$level] $message" >> "$LOG_FILE"
    
    # Also print to stdout based on verbosity
    case "$level" in
        ERROR|WARN)
            echo "$timestamp [$level] $message" >&2
            ;;
        INFO|SUMMARY)
            echo "$timestamp [$level] $message"
            ;;
        SCAN|COPY|VERIFY|DELETE|SKIP)
            if [ "$VERBOSE" = true ]; then
                echo "$timestamp [$level] $message"
            fi
            ;;
    esac
}

print_error() {
    echo "ERROR: $1" >&2
}

print_info() {
    echo "INFO: $1"
}

#############################################
# Filename Conformance Check
#############################################

# Check if a filename conforms to MusicLib naming rules
# Returns 0 if conforming, 1 if not
is_filename_conforming() {
    local filename="$1"
    
    # Check for uppercase letters
    if [[ "$filename" =~ [A-Z] ]]; then
        return 1
    fi
    
    # Check for spaces
    if [[ "$filename" =~ \  ]]; then
        return 1
    fi
    
    # Check for unsafe characters (anything not a-z, 0-9, _, -, .)
    if [[ "$filename" =~ [^a-z0-9_.\-] ]]; then
        return 1
    fi
    
    # Check for multiple consecutive underscores
    if [[ "$filename" =~ __ ]]; then
        return 1
    fi
    
    # Check for multiple periods (except one before extension)
    local base="${filename%.*}"
    if [[ "$base" =~ \. ]]; then
        return 1
    fi
    
    return 0
}

#############################################
# Filename Transformation
#############################################

# Transliterate non-ASCII characters to ASCII equivalents
# Uses perl for reliable UTF-8 character transliteration
transliterate_to_ascii() {
    local input="$1"
    
    # Use perl for reliable UTF-8 transliteration
    if command -v perl >/dev/null 2>&1; then
        printf '%s' "$input" | perl -CSD -Mutf8 -pe '
            use utf8;
            # Lowercase accented vowels
            tr/àáâãäåāăą/a/;
            tr/èéêëēĕėęě/e/;
            tr/ìíîïĩīĭį/i/;
            tr/òóôõöøōŏő/o/;
            tr/ùúûüũūŭůű/u/;
            tr/ýÿŷ/y/;
            # Uppercase accented vowels
            tr/ÀÁÂÃÄÅĀĂĄ/A/;
            tr/ÈÉÊËĒĔĖĘĚ/E/;
            tr/ÌÍÎÏĨĪĬĮ/I/;
            tr/ÒÓÔÕÖØŌŎŐ/O/;
            tr/ÙÚÛÜŨŪŬŮŰ/U/;
            tr/ÝŸŶ/Y/;
            # Consonants
            tr/ñńņň/n/;
            tr/ÑŃŅŇ/N/;
            tr/çćĉċč/c/;
            tr/ÇĆĈĊČ/C/;
            tr/śŝşš/s/;
            tr/ŚŜŞŠ/S/;
            tr/źżž/z/;
            tr/ŹŻŽ/Z/;
            tr/ðđ/d/;
            tr/ÐĐ/D/;
            tr/ł/l/;
            tr/Ł/L/;
            tr/ŕřŗ/r/;
            tr/ŔŘŖ/R/;
            tr/ţťŧ/t/;
            tr/ŢŤŦ/T/;
            tr/ğĝģ/g/;
            tr/ĞĜĢ/G/;
            tr/ĥħ/h/;
            tr/ĤĦ/H/;
            tr/ĵ/j/;
            tr/Ĵ/J/;
            tr/ķ/k/;
            tr/Ķ/K/;
            tr/ŵ/w/;
            tr/Ŵ/W/;
            # Multi-character replacements
            s/ß/ss/g;
            s/æ/ae/g;
            s/Æ/AE/g;
            s/œ/oe/g;
            s/Œ/OE/g;
            s/þ/th/g;
            s/Þ/TH/g;
        ' 2>/dev/null
        return
    fi
    
    # Fallback: try iconv (works when locale is properly configured)
    local result
    result="$(printf '%s' "$input" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null)"
    
    # Check if iconv worked (no ? characters and non-empty)
    if [ -n "$result" ] && ! printf '%s' "$result" | grep -q '?'; then
        printf '%s' "$result"
        return
    fi
    
    # Last resort: just return input (unsafe chars will be replaced with _ later)
    printf '%s' "$input"
}

# Transform a filename to conform to MusicLib naming rules
# Outputs the new conforming filename
transform_filename() {
    local filename="$1"
    local newname
    
    # Extract extension first (preserve it)
    local ext="${filename##*.}"
    local base="${filename%.*}"
    
    # Handle files without extension
    if [ "$ext" = "$filename" ]; then
        ext=""
        base="$filename"
    fi
    
    # Transform the base name:
    # 1. Transliterate non-ASCII to ASCII equivalents
    # 2. Convert to lowercase
    # 3. Replace spaces and unsafe chars with underscore
    # 4. Collapse multiple underscores
    # 5. Remove leading/trailing underscores
    
    # Step 1: Transliterate accented characters to ASCII
    newname="$(transliterate_to_ascii "$base")"
    
    # If transliteration produced empty result, use original
    if [ -z "$newname" ]; then
        newname="$base"
    fi
    
    # Step 2: Convert to lowercase
    newname="$(printf '%s' "$newname" | tr '[:upper:]' '[:lower:]')"
    
    # Step 3: Replace spaces and unsafe characters with underscore
    newname="$(printf '%s' "$newname" | sed 's/[^a-z0-9_.-]/_/g')"
    
    # Step 4: Handle periods in base name (convert to underscore)
    newname="$(printf '%s' "$newname" | sed 's/\./_/g')"
    
    # Step 5: Collapse multiple underscores
    newname="$(printf '%s' "$newname" | sed 's/_\+/_/g')"
    
    # Step 6: Remove leading/trailing underscores
    newname="$(printf '%s' "$newname" | sed 's/^_//; s/_$//')"
    
    # Add extension back (lowercase)
    if [ -n "$ext" ]; then
        ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
        newname="${newname}.${ext}"
    fi
    
    # Validate extension is a music extension
    local final_ext="${newname##*.}"
    if ! printf '%s' "$final_ext" | grep -qiE "^(${MUSIC_EXT_PATTERN})$"; then
        # Try to recover original extension
        local orig_ext="${filename##*.}"
        local orig_ext_lower
        orig_ext_lower="$(printf '%s' "$orig_ext" | tr '[:upper:]' '[:lower:]')"
        if printf '%s' "$orig_ext_lower" | grep -qE "^(${MUSIC_EXT_PATTERN})$"; then
            newname="${newname%.*}.${orig_ext_lower}"
        fi
    fi
    
    printf '%s' "$newname"
}

#############################################
# Safe Copy-Verify-Delete Workflow
#############################################

# Process a single non-conforming file
# Returns: 0=success, 1=skipped, 2=failed
process_file() {
    local filepath="$1"
    local dir
    local oldname
    local newname
    local newpath
    local oldsize
    local newsize
    
    dir="$(dirname "$filepath")"
    oldname="$(basename "$filepath")"
    newname="$(transform_filename "$oldname")"
    newpath="${dir}/${newname}"
    
    # Skip if already conforming (shouldn't happen, but safety check)
    if [ "$oldname" = "$newname" ]; then
        log_message "SKIP" "$filepath (already conforming)"
        return 1
    fi
    
    # Check for collision
    if [ -e "$newpath" ]; then
        log_message "SKIP" "$filepath -> $newname (target already exists)"
        log_message "WARN" "Collision detected: $newpath already exists"
        return 1
    fi
    
    # Log the planned operation
    log_message "SCAN" "$filepath -> $newname"
    
    # Dry-run mode: just report what would happen
    if [ "$DRY_RUN" = true ]; then
        echo "  Would rename: $oldname -> $newname"
        return 0
    fi
    
    # Step 1: Copy file to new name
    log_message "COPY" "$filepath -> $newpath"
    if ! cp -p -- "$filepath" "$newpath" 2>/dev/null; then
        log_message "ERROR" "Copy failed: $filepath -> $newpath"
        return 2
    fi
    
    # Step 2: Verify copy (check file exists and size matches)
    if [ ! -f "$newpath" ]; then
        log_message "ERROR" "Verify failed: $newpath does not exist after copy"
        return 2
    fi
    
    oldsize="$(stat -c%s "$filepath" 2>/dev/null || echo "0")"
    newsize="$(stat -c%s "$newpath" 2>/dev/null || echo "0")"
    
    if [ "$oldsize" != "$newsize" ]; then
        log_message "ERROR" "Verify failed: size mismatch ($oldsize vs $newsize)"
        # Remove failed copy
        rm -f -- "$newpath" 2>/dev/null
        return 2
    fi
    
    log_message "VERIFY" "$newname (OK: $newsize bytes)"
    
    # Step 3: Delete original
    log_message "DELETE" "$oldname"
    if ! rm -f -- "$filepath" 2>/dev/null; then
        log_message "ERROR" "Delete failed: $filepath (copy exists at $newpath)"
        return 2
    fi
    
    echo "  Renamed: $oldname -> $newname"
    return 0
}

#############################################
# Load Configuration
#############################################

load_config() {
    local config_file="$CONFIG_DIR/musiclib.conf"
    
    if [ -f "$config_file" ]; then
        # Source config to get MUSIC_REPO if not provided
        # shellcheck disable=SC1090
        source "$config_file" 2>/dev/null || true
    fi
}

#############################################
# Main Processing
#############################################

main() {
    # Ensure log directory exists
    mkdir -p "$LOG_DIR" 2>/dev/null
    
    # Initialize log file
    {
        echo "========================================"
        echo "MusicLib Filename Conformance Tool"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN (preview)" || echo "EXECUTE (renaming files)")"
        echo "Music Repository: $MUSIC_REPO"
        echo "========================================"
        echo ""
    } > "$LOG_FILE"
    
    # Banner
    echo ""
    echo "========================================"
    echo "MusicLib Filename Conformance Tool"
    echo "========================================"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo "MODE: DRY-RUN (preview only, no files will be changed)"
        echo "      Use --execute to actually rename files"
    else
        echo "MODE: EXECUTE (files WILL be renamed)"
        echo ""
        echo "WARNING: This will modify your files!"
        read -r -p "Continue? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted by user."
            exit 0
        fi
    fi
    echo ""
    echo "Music Repository: $MUSIC_REPO"
    echo "Log File: $LOG_FILE"
    echo ""
    echo "Scanning for music files..."
    echo ""
    
    # Scan all music files
    while IFS= read -r -d '' filepath; do
        COUNT_SCANNED=$((COUNT_SCANNED + 1))
        
        filename="$(basename "$filepath")"
        
        # Check if filename conforms
        if is_filename_conforming "$filename"; then
            COUNT_CONFORMING=$((COUNT_CONFORMING + 1))
            if [ "$VERBOSE" = true ]; then
                log_message "SKIP" "$filepath (conforming)"
            fi
            continue
        fi
        
        COUNT_NONCONFORMING=$((COUNT_NONCONFORMING + 1))
        
        # Process the non-conforming file
        result=0
        process_file "$filepath" || result=$?
        
        case $result in
            0) COUNT_PROCESSED=$((COUNT_PROCESSED + 1)) ;;
            1) COUNT_SKIPPED=$((COUNT_SKIPPED + 1)) ;;
            2) COUNT_FAILED=$((COUNT_FAILED + 1)) ;;
        esac
        
        # Progress indicator (every 100 files)
        if [ $((COUNT_SCANNED % 100)) -eq 0 ]; then
            printf "\r  Scanned %d files..." "$COUNT_SCANNED"
        fi
        
    done < <(find "$MUSIC_REPO" -type f \( \
        -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.flac' -o \
        -iname '*.wav' -o -iname '*.aac' -o -iname '*.m4a' -o \
        -iname '*.wma' -o -iname '*.opus' -o -iname '*.aiff' -o \
        -iname '*.alac' -o -iname '*.ape' -o -iname '*.mpc' -o \
        -iname '*.wv' \) -print0 2>/dev/null)
    
    # Clear progress line
    printf "\r                                        \r"
    
    # Summary
    echo ""
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo ""
    echo "  Total files scanned:    $COUNT_SCANNED"
    echo "  Already conforming:     $COUNT_CONFORMING"
    echo "  Non-conforming found:   $COUNT_NONCONFORMING"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo "  Would rename:           $COUNT_PROCESSED"
        echo "  Would skip:             $COUNT_SKIPPED"
        echo ""
        if [ "$COUNT_NONCONFORMING" -gt 0 ]; then
            echo "To actually rename files, run:"
            echo "  $SCRIPT_NAME --execute $MUSIC_REPO"
        fi
    else
        echo "  Successfully renamed:   $COUNT_PROCESSED"
        echo "  Skipped (collision):    $COUNT_SKIPPED"
        echo "  Failed:                 $COUNT_FAILED"
    fi
    
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Log summary
    log_message "SUMMARY" "Scanned: $COUNT_SCANNED, Conforming: $COUNT_CONFORMING, Non-conforming: $COUNT_NONCONFORMING"
    if [ "$DRY_RUN" = true ]; then
        log_message "SUMMARY" "Dry-run: Would rename $COUNT_PROCESSED, Would skip $COUNT_SKIPPED"
    else
        log_message "SUMMARY" "Renamed: $COUNT_PROCESSED, Skipped: $COUNT_SKIPPED, Failed: $COUNT_FAILED"
    fi
    
    # Exit code based on failures
    if [ "$COUNT_FAILED" -gt 0 ]; then
        exit 2
    fi
    
    exit 0
}

#############################################
# Parse Command Line Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        --execute)
            DRY_RUN=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help|help)
            print_usage
            exit 0
            ;;
        --version)
            print_version
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
        *)
            # Positional argument - music repo path
            if [ -z "$MUSIC_REPO" ]; then
                MUSIC_REPO="$1"
            else
                print_error "Multiple paths specified. Only one MUSIC_REPO allowed."
                exit 1
            fi
            shift
            ;;
    esac
done

#############################################
# Validate Music Repository
#############################################

# Try to load from config if not provided
if [ -z "$MUSIC_REPO" ]; then
    load_config
fi

# Expand tilde if present
MUSIC_REPO="${MUSIC_REPO/#\~/$HOME}"

# Prompt if still not set
if [ -z "$MUSIC_REPO" ]; then
    echo "No music repository specified."
    read -r -p "Enter path to music repository: " MUSIC_REPO
    MUSIC_REPO="${MUSIC_REPO/#\~/$HOME}"
fi

# Validate path exists
if [ ! -d "$MUSIC_REPO" ]; then
    print_error "Music repository not found: $MUSIC_REPO"
    exit 1
fi

# Remove trailing slash for consistency
MUSIC_REPO="${MUSIC_REPO%/}"

#############################################
# Run Main
#############################################

main
