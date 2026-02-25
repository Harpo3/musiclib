#!/bin/bash
#
# musiclib_init_config.sh - Interactive setup wizard
#
# Usage: musiclib_init_config.sh
#
# This script guides users through MusicLib configuration by:
#   1. Detecting Audacious installation
#   2. Locating music repository directories
#   3. Setting download directory
#   4. Creating XDG directory structure
#   5. Optionally building initial database
#   6. Generating/updating musiclib.conf with detected values
#
# The wizard can be run multiple times to update configuration.
# It will read existing settings and use them as defaults.
#
# Exit codes:
#   0 - Success (configuration created/updated)
#   1 - User error (user cancelled setup)
#   2 - System error (cannot create directories, permissions denied)
#
# Examples:
#   musiclib_init_config.sh
#

set -u
set -o pipefail

#############################################
# Setup Variables
#############################################

SCRIPT_NAME="$(basename "$0")"
FORCE_OVERWRITE=false

# XDG paths
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Determine config location
# Priority: MUSICLIB_CONFIG_DIR override > XDG default
CONFIG_DIR="${MUSICLIB_CONFIG_DIR:-$XDG_CONFIG_HOME/musiclib}"
DATA_DIR="$XDG_DATA_HOME/musiclib"
CONFIG_FILE="$CONFIG_DIR/musiclib.conf"

# Check for existing config in any known location
EXISTING_CONFIG_FILE=""

if [ -f "$CONFIG_FILE" ]; then
    # Found at target location (override or XDG)
    EXISTING_CONFIG_FILE="$CONFIG_FILE"
elif [ -f "$HOME/musiclib/config/musiclib.conf" ]; then
    # Legacy location
    EXISTING_CONFIG_FILE="$HOME/musiclib/config/musiclib.conf"
fi

# Detected values (populated during wizard)
DETECTED_AUDACIOUS=""
DETECTED_AUDACIOUS_PATH=""
DETECTED_MUSIC_REPO=""
DETECTED_DOWNLOAD_DIR="$HOME/Downloads"
DETECTED_KDECONNECT=""
DETECTED_RSGAIN=""
DETECTED_KID3_GUI=""
BUILD_INITIAL_DB=false

#############################################
# Helper Functions
#############################################

# Print colored output
print_header() {
    echo ""
    echo "==========================================="
    echo "  $1"
    echo "==========================================="
    echo ""
}

print_step() {
    echo ""
    echo "[$1] $2"
    echo "-------------------------------------------"
}

print_success() {
    echo "[OK] $1"
}

print_error() {
    echo "[X] ERROR: $1" >&2
}

print_info() {
    echo "  $1"
}

# Prompt for yes/no with default
prompt_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n] " response
        response="${response:-y}"
    else
        read -p "$prompt [y/N] " response
        response="${response:-n}"
    fi

    case "$response" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Prompt for input with default
prompt_input() {
    local prompt="$1"
    local default="$2"
    local response

    read -p "$prompt [$default]: " response
    echo "${response:-$default}"
}

# Count audio files in directory
count_audio_files() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo 0
        return
    fi
    find "$dir" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.ogg' \) 2>/dev/null | wc -l
}

#############################################
# Library Structure Analysis
#############################################
# Checks if a path conforms to expected structure:
#   - Directory: artist/album/track.ext (2 levels deep from repo root)
#   - Filename: lowercase, underscores instead of spaces, safe chars only
#
# Returns via global variables:
#   ANALYSIS_TOTAL - total files scanned
#   ANALYSIS_CONFORMING - count of conforming files
#   ANALYSIS_NONCONFORMING - count of non-conforming files
#   ANALYSIS_REPORT_FILE - path to detailed report

analyze_library_structure() {
    local music_repo="$1"
    local report_dir="$DATA_DIR/logs"
    local report_file="$report_dir/library_analysis.txt"
    local temp_nonconforming=$(mktemp)

    # Ensure report directory exists
    mkdir -p "$report_dir" 2>/dev/null

    # Initialize counters
    local total=0
    local conforming=0
    local nonconforming=0

    # Get repo path length for relative path calculation
    local repo_len=${#music_repo}

    # Scan all audio files
    while IFS= read -r -d '' filepath; do
        ((total++))

        # Get path relative to music repo
        local relpath="${filepath:$((repo_len + 1))}"

        # Check structure: should be artist/album/filename (exactly 2 slashes)
        local slash_count=$(echo "$relpath" | tr -cd '/' | wc -c)
        local structure_ok=false

        if [ "$slash_count" -eq 2 ]; then
            structure_ok=true
        fi

        # Check filename normalization
        local filename=$(basename "$filepath")
        local filename_ok=true

        # Check for uppercase letters
        if [[ "$filename" =~ [A-Z] ]]; then
            filename_ok=false
        fi

        # Check for spaces
        if [[ "$filename" =~ \  ]]; then
            filename_ok=false
        fi

        # Check for unsafe characters (anything not a-z, 0-9, _, -, .)
        if [[ "$filename" =~ [^a-z0-9_.\-] ]]; then
            filename_ok=false
        fi

        # Determine overall conformance
        if [ "$structure_ok" = true ] && [ "$filename_ok" = true ]; then
            ((conforming++))
        else
            ((nonconforming++))

            # Build reason string
            local reasons=""
            if [ "$structure_ok" = false ]; then
                reasons="structure"
            fi
            if [ "$filename_ok" = false ]; then
                if [ -n "$reasons" ]; then
                    reasons="$reasons, filename"
                else
                    reasons="filename"
                fi
            fi

            # Write to temp file for report
            echo "$filepath|$reasons" >> "$temp_nonconforming"
        fi

        # Progress indicator (every 500 files)
        if [ $((total % 500)) -eq 0 ]; then
            printf "\r  Scanned %d files..." "$total"
        fi

    done < <(find "$music_repo" -type f \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.ogg' \) -print0 2>/dev/null)

    # Clear progress line
    printf "\r                                        \r"

    # Generate report file
    {
        echo "MusicLib Library Analysis Report"
        echo "================================"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Music Repository: $music_repo"
        echo ""
        echo "Summary"
        echo "-------"
        echo "Total files scanned: $total"
        echo "Conforming files: $conforming ($((conforming * 100 / (total > 0 ? total : 1)))%)"
        echo "Non-conforming files: $nonconforming ($((nonconforming * 100 / (total > 0 ? total : 1)))%)"
        echo ""
        echo "Expected Structure"
        echo "------------------"
        echo "Directory: MUSIC_REPO/artist/album/track.ext"
        echo "Filename:  lowercase, underscores (no spaces), safe characters only"
        echo "           Allowed: a-z, 0-9, underscore, hyphen, period"
        echo ""

        if [ "$nonconforming" -gt 0 ]; then
            echo "Non-Conforming Files"
            echo "--------------------"
            echo ""

            # Sort and output non-conforming files
            sort "$temp_nonconforming" | while IFS='|' read -r path reason; do
                echo "[$reason] $path"
            done

            echo ""
            echo "Recommendation"
            echo "--------------"
            echo "Consider moving non-conforming files to a separate location,"
            echo "then use 'musiclib-cli new-tracks' to import them properly."
            echo "This will normalize filenames and organize them into the"
            echo "correct artist/album directory structure."
        fi
    } > "$report_file"

    # Generate plain filepath list for non-conforming files
    local nonconforming_list="$report_dir/nonconforming_files"
    if [ "$nonconforming" -gt 0 ]; then
        # Extract just the paths (strip the reason after the pipe)
        sort "$temp_nonconforming" | cut -d'|' -f1 > "$nonconforming_list"
    else
        # Remove old list if no non-conforming files
        rm -f "$nonconforming_list"
    fi

    # Cleanup
    rm -f "$temp_nonconforming"

    # Set global variables for caller
    ANALYSIS_TOTAL=$total
    ANALYSIS_CONFORMING=$conforming
    ANALYSIS_NONCONFORMING=$nonconforming
    ANALYSIS_REPORT_FILE="$report_file"
}

#############################################
# Parse Command Line Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|help)
            cat << 'EOF'
Usage: musiclib_init_config.sh

Interactive setup wizard for MusicLib configuration.

This wizard will:
  1. Detect Audacious installation
  2. Locate your music repository
  3. Analyze library structure (directory layout, filename conventions)
  4. Configure download directories
  5. Detect KDE Connect for mobile sync
  6. Check optional dependencies (RSGain, Kid3 GUI)
  7. Create XDG directory structure
  8. Optionally build initial database
  9. Generate/update configuration file

The wizard can be run multiple times to update configuration.
It will read existing settings as defaults.

Library Analysis:
  MusicLib expects music files organized as: artist/album/track.ext
  with normalized filenames (lowercase, underscores, safe characters).

  The analysis step scans your library and reports any files that
  don't conform to this structure. You can then choose to:
    - Import as-is (some features may behave inconsistently)
    - Exit and reorganize your library before continuing

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$SCRIPT_NAME --help' for usage information."
            exit 1
            ;;
    esac
done

#############################################
# Pre-flight Checks
#############################################

# No pre-flight checks needed - setup wizard should always be able to run
# It will read existing config values as defaults if available

#############################################
# Welcome Banner
#############################################

clear
print_header "MusicLib Setup Wizard"

if [ -n "$EXISTING_CONFIG_FILE" ] && [ -f "$EXISTING_CONFIG_FILE" ]; then
    echo "Welcome to MusicLib setup."
    echo "Existing configuration found - you can review and update your settings."
else
    echo "Welcome to MusicLib! Let's configure your music library."
fi
echo ""

if ! prompt_yn "Continue with setup?" "y"; then
    echo "Setup cancelled."
    exit 1
fi

#############################################
# Step 1: Detect Audacious
#############################################

print_step "1/7" "Checking Audacious..."

# Check existing config for Audacious setting
EXISTING_AUDACIOUS=""
if [ -n "$EXISTING_CONFIG_FILE" ] && [ -f "$EXISTING_CONFIG_FILE" ]; then
    EXISTING_AUDACIOUS=$(grep '^AUDACIOUS_INSTALLED=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
fi

# Detect current Audacious installation status
if command -v audacious &>/dev/null; then
    DETECTED_AUDACIOUS="true"
    DETECTED_AUDACIOUS_PATH="$(command -v audacious)"
    print_success "Audacious installed at: $DETECTED_AUDACIOUS_PATH"

    # Only prompt if previously explicitly disabled
    if [ "$EXISTING_AUDACIOUS" = "false" ]; then
        print_info "Previously disabled in config"
        if prompt_yn "Enable Audacious integration?" "y"; then
            DETECTED_AUDACIOUS="true"
            print_info "Integration enabled"
        else
            DETECTED_AUDACIOUS="false"
            print_info "Audacious integration remains disabled"
        fi
    else
        # Either already enabled or not in config - auto-enable
        DETECTED_AUDACIOUS="true"
        print_info "Integration enabled"
    fi
else
    # Audacious not installed
    DETECTED_AUDACIOUS="false"

    # Check if it was previously enabled
    if [ "$EXISTING_AUDACIOUS" = "true" ]; then
        print_info "Audacious no longer installed (was previously enabled)"
        print_info "Updated config: AUDACIOUS_INSTALLED=false"
    else
        print_info "Audacious not found"
    fi

    if prompt_yn "Install Audacious for best integration experience?" "n"; then
        print_info "Install Audacious using your package manager:"
        print_info "  Debian/Ubuntu: sudo apt install audacious"
        print_info "  Fedora: sudo dnf install audacious"
        print_info "  Arch: sudo pacman -S audacious"
        echo ""
        print_info "Re-run setup after installation to enable integration."
    fi
fi

#############################################
# Step 2: Locate Music Repository
#############################################

print_step "2/7" "Checking music repository..."

# Check if existing config has MUSIC_REPO set
# Read from existing config if available (even in force mode, to show as default)
EXISTING_MUSIC_REPO=""
CONFIG_FILE_EXISTS=false

if [ -n "$EXISTING_CONFIG_FILE" ] && [ -f "$EXISTING_CONFIG_FILE" ]; then
    CONFIG_FILE_EXISTS=true
    print_info "Found existing config: $EXISTING_CONFIG_FILE"

    # Extract MUSIC_REPO from existing config (safely)
    EXISTING_MUSIC_REPO=$(grep '^MUSIC_REPO=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')

    # Show what we found for debugging
    if [ -n "$EXISTING_MUSIC_REPO" ]; then
        print_info "Existing MUSIC_REPO setting: $EXISTING_MUSIC_REPO"
        # Check if directory exists
        if [ -d "$EXISTING_MUSIC_REPO" ]; then
            print_info "Directory status: EXISTS"
        else
            print_info "Directory status: NOT FOUND"
        fi
    else
        print_info "MUSIC_REPO not set in config (or is empty)"
    fi
    echo ""
else
    print_info "No existing configuration file found"
    echo ""
fi

# If existing config has non-empty MUSIC_REPO, confirm with user
if [ -n "$EXISTING_MUSIC_REPO" ] && [ "$EXISTING_MUSIC_REPO" != '""' ]; then
    print_info "Current configuration: $EXISTING_MUSIC_REPO"

    if [ -d "$EXISTING_MUSIC_REPO" ]; then
        file_count=$(count_audio_files "$EXISTING_MUSIC_REPO")
        print_info "Files found: $file_count"
        echo ""

        if prompt_yn "Use existing music repository?" "y"; then
            DETECTED_MUSIC_REPO="$EXISTING_MUSIC_REPO"
            print_success "Music repository: $DETECTED_MUSIC_REPO"

            # Skip scanning - move to next step
        else
            # User wants to change - continue to scanning
            print_info "Scanning for alternative locations..."
            SCAN_FOR_MUSIC=true
        fi
    else
        print_info "Configured repository not found: $EXISTING_MUSIC_REPO"
        print_info "Scanning for available locations..."
        echo ""
        SCAN_FOR_MUSIC=true
    fi
else
    # No existing config or empty MUSIC_REPO - scan for directories
    if [ -f "$CONFIG_FILE" ]; then
        print_info "Music repository not configured (MUSIC_REPO is empty)"
        print_info "Scanning for available locations..."
        echo ""
    fi
    SCAN_FOR_MUSIC=true
fi

# Only scan if we need to find a new location
if [ "${SCAN_FOR_MUSIC:-false}" = "true" ]; then
    print_info "Scanning for music folders in /home and /mnt..."

    # Search for potential music directories
    declare -a music_dirs=()
    declare -a music_counts=()

    # Check common locations
    check_dir() {
        local dir="$1"
        local count

        if [ -d "$dir" ]; then
            count=$(count_audio_files "$dir")
            if [ "$count" -gt 0 ]; then
                music_dirs+=("$dir")
                music_counts+=("$count")
            fi
        fi
    }

    # Search common locations
    check_dir "$HOME/Music"
    check_dir "$HOME/music"

    # Search /mnt for music directories
    if [ -d "/mnt" ]; then
        while IFS= read -r dir; do
            check_dir "$dir"
        done < <(find /mnt -maxdepth 2 -type d \( -iname 'music' -o -iname 'Music' \) 2>/dev/null)
    fi

    # Display found directories
    echo ""
    if [ ${#music_dirs[@]} -eq 0 ]; then
        print_info "No music directories found."
        DETECTED_MUSIC_REPO="$HOME/Music"
    else
        print_info "Found potential music locations:"
        echo ""
        for i in "${!music_dirs[@]}"; do
            printf "  %d) %s (%s files)\n" $((i+1)) "${music_dirs[$i]}" "${music_counts[$i]}"
        done
        echo "  $((${#music_dirs[@]}+1))) Enter custom path"
        echo ""

        # Prompt for selection
        selection=""
        while true; do
            read -p "Select music repository [1-$((${#music_dirs[@]}+1))]: " selection

            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le $((${#music_dirs[@]}+1)) ]; then
                break
            fi
            echo "Invalid selection. Please enter a number between 1 and $((${#music_dirs[@]}+1))."
        done

        if [ "$selection" -eq $((${#music_dirs[@]}+1)) ]; then
            # Custom path
            custom_path=""
            read -p "Enter music repository path: " custom_path
            custom_path="${custom_path/#\~/$HOME}"  # Expand tilde

            if [ ! -d "$custom_path" ]; then
                print_error "Directory not found: $custom_path"

                if prompt_yn "Create directory?" "n"; then
                    mkdir -p "$custom_path" || {
                        print_error "Failed to create directory"
                        exit 2
                    }
                    print_success "Directory created"
                fi
            fi
            DETECTED_MUSIC_REPO="$custom_path"
        else
            DETECTED_MUSIC_REPO="${music_dirs[$((selection-1))]}"
        fi
    fi

    print_success "Music repository: $DETECTED_MUSIC_REPO"
fi  # End of SCAN_FOR_MUSIC block

#############################################
# Step 3: Library Structure Analysis
#############################################

print_step "3/7" "Analyzing library structure..."

print_info "Scanning files in: $DETECTED_MUSIC_REPO"
print_info "(This may take a moment for large libraries)"
echo ""

# Run the analysis
analyze_library_structure "$DETECTED_MUSIC_REPO"

# Display results
echo ""
print_info "Analysis Complete"
echo ""
echo "  Total files scanned:    $ANALYSIS_TOTAL"
echo "  Conforming files:       $ANALYSIS_CONFORMING ($((ANALYSIS_CONFORMING * 100 / (ANALYSIS_TOTAL > 0 ? ANALYSIS_TOTAL : 1)))%)"
echo "  Non-conforming files:   $ANALYSIS_NONCONFORMING ($((ANALYSIS_NONCONFORMING * 100 / (ANALYSIS_TOTAL > 0 ? ANALYSIS_TOTAL : 1)))%)"
echo ""

# Track conformance status for config file
LIBRARY_CONFORMING=true

if [ "$ANALYSIS_NONCONFORMING" -eq 0 ]; then
    # All files conform
    print_success "All files follow expected structure"
    echo ""

    if ! prompt_yn "Continue with setup?" "y"; then
        echo "Setup cancelled."
        exit 1
    fi
else
    # Discrepancies found
    echo "  Examples of non-conforming paths:"
    echo ""

    # Show first 5 examples from report
    grep '^\[' "$ANALYSIS_REPORT_FILE" 2>/dev/null | head -5 | while read -r line; do
        echo "    $line"
    done

    if [ "$ANALYSIS_NONCONFORMING" -gt 5 ]; then
        echo "    ... and $((ANALYSIS_NONCONFORMING - 5)) more"
    fi

    echo ""
    print_info "Full report saved to: $ANALYSIS_REPORT_FILE"
    echo ""
    echo "-----------------------------------------------------------------"
    echo ""
    echo "  Suggestion: Move non-conforming files to a temporary location,"
    echo "  then use 'musiclib-cli new-tracks' to import them properly."
    echo "  This normalizes filenames and organizes into artist/album folders."
    echo ""
    echo "-----------------------------------------------------------------"
    echo ""
    echo "Options:"
    echo "  1) Import as-is (some features may behave inconsistently)"
    echo "  2) Exit setup (reorganize library, then re-run setup)"
    echo ""

    selection=""
    while true; do
        read -p "Select [1-2]: " selection

        case "$selection" in
            1)
                LIBRARY_CONFORMING=false
                print_info "Proceeding with non-conforming library"
                print_info "Note: Path matching and mobile sync may behave inconsistently"
                break
                ;;
            2)
                echo ""
                print_info "Setup cancelled."
                print_info "Review the report: $ANALYSIS_REPORT_FILE"
                print_info "Evaluate use of ~/.local/share/musiclib/utilities/conform_musiclib.sh script."
                print_info "It modifies your files. Make backups first and use solely at your own risk."
                print_info "Re-run setup after reorganizing your library."
                exit 1
                ;;
            *)
                echo "Invalid selection. Please enter 1 or 2."
                ;;
        esac
    done
fi

#############################################
# Step 4: Set Download Directory
#############################################

print_step "4/7" "Checking download directory..."

# Read existing download directory from config if available
if [ -n "$EXISTING_CONFIG_FILE" ] && [ -f "$EXISTING_CONFIG_FILE" ]; then
    EXISTING_DOWNLOAD_DIR=$(grep '^NEW_DOWNLOAD_DIR=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')
    # Expand variables if present (like $HOME)
    EXISTING_DOWNLOAD_DIR=$(eval echo "$EXISTING_DOWNLOAD_DIR")

    if [ -n "$EXISTING_DOWNLOAD_DIR" ]; then
        DETECTED_DOWNLOAD_DIR="$EXISTING_DOWNLOAD_DIR"
    fi
fi

print_info "Current: $DETECTED_DOWNLOAD_DIR"
echo ""

# Only prompt for new location if user wants to change
if prompt_yn "Keep existing download location?" "y"; then
    print_success "Download directory: $DETECTED_DOWNLOAD_DIR"
else
    DETECTED_DOWNLOAD_DIR=$(prompt_input "New music download location" "$DETECTED_DOWNLOAD_DIR")
    DETECTED_DOWNLOAD_DIR="${DETECTED_DOWNLOAD_DIR/#\~/$HOME}"  # Expand tilde

    # Create directory if it doesn't exist
    if [ ! -d "$DETECTED_DOWNLOAD_DIR" ]; then
        if prompt_yn "Create directory?" "y"; then
            mkdir -p "$DETECTED_DOWNLOAD_DIR" || {
                print_error "Failed to create directory: $DETECTED_DOWNLOAD_DIR"
                exit 2
            }
            print_success "Directory created"
        fi
    fi

    print_success "Download directory: $DETECTED_DOWNLOAD_DIR"
fi

#############################################
# Step 5: Database Setup
#############################################

print_step "5/7" "Checking database..."

# Check for existing database in known locations
# Priority order matches config file search
DB_PATH=""
EXISTING_DB_PATH=""

# Check project directory (development)
if [ -f "/mnt/project/musiclib/data/musiclib.dsv" ]; then
    EXISTING_DB_PATH="/mnt/project/musiclib/data/musiclib.dsv"
# Check legacy location
elif [ -f "$HOME/musiclib/data/musiclib.dsv" ]; then
    EXISTING_DB_PATH="$HOME/musiclib/data/musiclib.dsv"
# Check XDG location (future)
elif [ -f "$DATA_DIR/data/musiclib.dsv" ]; then
    EXISTING_DB_PATH="$DATA_DIR/data/musiclib.dsv"
fi

# The new database will be written to XDG location
DB_PATH="$DATA_DIR/data/musiclib.dsv"

if [ -n "$EXISTING_DB_PATH" ] && [ -f "$EXISTING_DB_PATH" ]; then
    track_count=$(wc -l < "$EXISTING_DB_PATH" 2>/dev/null || echo "0")
    print_info "Existing database found: $EXISTING_DB_PATH ($track_count tracks)"

    if prompt_yn "Keep existing database?" "y"; then
        BUILD_INITIAL_DB=false

        # If database is in different location than where we'll write, note it
        if [ "$EXISTING_DB_PATH" != "$DB_PATH" ]; then
            print_info "Database will be referenced from current location"
        fi
    else
        if prompt_yn "Build new database from music repository?" "y"; then
            BUILD_INITIAL_DB=true
        fi
    fi
else
    print_info "No existing database found."
    echo ""

    if prompt_yn "Build initial database from music repository?" "y"; then
        BUILD_INITIAL_DB=true
    else
        print_info "You can build the database later with: musiclib-cli build"
        BUILD_INITIAL_DB=false
    fi
fi

#############################################
# Step 6: KDE Connect (Mobile Sync)
#############################################

print_step "6/7" "KDE Connect (Mobile Sync)..."

DETECTED_DEVICE_ID=""

# Check existing config for device ID
if [ -n "$EXISTING_CONFIG_FILE" ] && [ -f "$EXISTING_CONFIG_FILE" ]; then
    EXISTING_DEVICE_ID=$(grep '^DEVICE_ID=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')
fi

if command -v kdeconnect-cli &>/dev/null; then
    DETECTED_KDECONNECT="true"
    print_success "KDE Connect installed"

    # Check if device ID is already configured
    if [ -n "$EXISTING_DEVICE_ID" ]; then
        print_info "Configured device ID: $EXISTING_DEVICE_ID"

        # Test if device is reachable
        if kdeconnect-cli -d "$EXISTING_DEVICE_ID" --ping >/dev/null 2>&1; then
            print_success "Device is reachable"
            DETECTED_DEVICE_ID="$EXISTING_DEVICE_ID"
        else
            print_info "Device not currently reachable"

            if prompt_yn "Search for available devices?" "y"; then
                # List available devices
                echo ""
                print_info "Available KDE Connect devices:"
                kdeconnect-cli -a 2>/dev/null || print_info "No devices found"
                echo ""

                read -p "Enter device ID (or press Enter to skip): " new_device_id
                if [ -n "$new_device_id" ]; then
                    # Verify device is reachable
                    if kdeconnect-cli -d "$new_device_id" --ping >/dev/null 2>&1; then
                        print_success "Device verified"
                        DETECTED_DEVICE_ID="$new_device_id"
                    else
                        print_info "Could not reach device: $new_device_id"
                        print_info "Keeping existing device ID in config"
                        DETECTED_DEVICE_ID="$EXISTING_DEVICE_ID"
                    fi
                else
                    DETECTED_DEVICE_ID="$EXISTING_DEVICE_ID"
                fi
            else
                DETECTED_DEVICE_ID="$EXISTING_DEVICE_ID"
            fi
        fi
    else
        # No device ID in config - search for devices
        print_info "No device configured"

        if prompt_yn "Search for available KDE Connect devices?" "y"; then
            echo ""
            print_info "Available KDE Connect devices:"
            kdeconnect-cli -a 2>/dev/null || print_info "No devices found"
            echo ""
            print_info "To get device ID: kdeconnect-cli -a"
            echo ""

            read -p "Enter device ID (or press Enter to skip): " new_device_id
            if [ -n "$new_device_id" ]; then
                # Verify device is reachable
                if kdeconnect-cli -d "$new_device_id" --ping >/dev/null 2>&1; then
                    print_success "Device verified and reachable"
                    DETECTED_DEVICE_ID="$new_device_id"
                else
                    print_info "Warning: Could not reach device: $new_device_id"
                    print_info "Saving anyway - ensure device is paired and connected"
                    DETECTED_DEVICE_ID="$new_device_id"
                fi
            else
                print_info "Skipped: You can add device ID later in config"
                DETECTED_DEVICE_ID=""
            fi
        else
            print_info "Skipped: You can add device ID later in config"
            DETECTED_DEVICE_ID=""
        fi
    fi
else
    DETECTED_KDECONNECT="false"
    DETECTED_DEVICE_ID=""
    print_info "KDE Connect not found"

    if prompt_yn "Install KDE Connect for mobile playlist sync?" "n"; then
        print_info "Install KDE Connect using your package manager:"
        print_info "  Debian/Ubuntu: sudo apt install kdeconnect"
        print_info "  Fedora: sudo dnf install kdeconnect"
        print_info "  Arch: sudo pacman -S kdeconnect"
        echo ""
        print_info "Re-run setup after installation to enable integration."
    else
        print_info "Skipped: KDE Connect integration"
    fi
fi

#############################################
# Step 7: Optional Dependencies (RSGain, Kid3)
#############################################

print_step "7/8" "Checking optional dependencies..."

# Detect RSGain (for ReplayGain / loudness normalization)
DETECTED_RSGAIN="false"
if command -v rsgain &>/dev/null; then
    DETECTED_RSGAIN="true"
    print_success "RSGain installed (ReplayGain support enabled)"
else
    DETECTED_RSGAIN="false"
    print_info "RSGain not found (optional - for loudness normalization)"
    
    if prompt_yn "Install RSGain for ReplayGain support?" "n"; then
        print_info "Install RSGain using your package manager:"
        print_info "  Debian/Ubuntu: sudo apt install rsgain"
        print_info "  Fedora: sudo dnf install rsgain"
        print_info "  Arch: sudo pacman -S rsgain"
        echo ""
        print_info "Re-run setup after installation to enable ReplayGain features."
    fi
fi

# Detect Kid3 GUI versions (kid3 = KDE, kid3-qt = Qt standalone)
# Note: kid3-common (CLI) is a required dependency, so we only check for GUI versions
DETECTED_KID3_GUI="none"

if command -v kid3 &>/dev/null; then
    DETECTED_KID3_GUI="kid3"
    print_success "Kid3 (KDE version) installed"
elif command -v kid3-qt &>/dev/null; then
    DETECTED_KID3_GUI="kid3-qt"
    print_success "Kid3-Qt (standalone Qt version) installed"
else
    DETECTED_KID3_GUI="none"
    print_info "Kid3 GUI not found (optional - for tag editing)"
    print_info "Note: kid3-cli is required and should already be installed"
    
    if prompt_yn "Install Kid3 GUI for tag editing interface?" "n"; then
        print_info "Install Kid3 GUI using your package manager:"
        print_info "  Debian/Ubuntu: sudo apt install kid3-qt  (or kid3 for KDE integration)"
        print_info "  Fedora: sudo dnf install kid3-qt  (or kid3 for KDE integration)"
        print_info "  Arch: sudo pacman -S kid3-qt  (or kid3 for KDE integration)"
        echo ""
        print_info "Re-run setup after installation to enable GUI tag editor."
    fi
fi

#############################################
# Step 8: Create Directory Structure
#############################################

print_step "8/8" "Creating directory structure..."

create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            print_error "Failed to create directory: $dir"
            exit 2
        }
        print_success "Created: $dir"
    else
        print_info "Exists: $dir"
    fi
}

create_dir "$CONFIG_DIR"
create_dir "$DATA_DIR/data"
create_dir "$DATA_DIR/data/conky_output"
create_dir "$DATA_DIR/data/conky_output/stars"
create_dir "$DATA_DIR/data/tag_backups"
create_dir "$DATA_DIR/logs"
create_dir "$DATA_DIR/playlists"
create_dir "$DATA_DIR/playlists/mobile"

#############################################
# Generate Configuration File
#############################################

print_header "Generating Configuration"

cat > "$CONFIG_FILE" << EOF
# MusicLib Configuration File
# Generated by setup wizard on $(date +"%Y-%m-%d %H:%M:%S")
#
# Edit these values to customize your setup
# This configuration follows the XDG Base Directory Specification

#############################################
# XDG BASE DIRECTORY DEFAULTS
#############################################

MUSICLIB_XDG_CONFIG="${XDG_CONFIG_HOME}/musiclib"
MUSICLIB_XDG_DATA="${XDG_DATA_HOME}/musiclib"

MUSICLIB_CONFIG_DIR="\$MUSICLIB_XDG_CONFIG"
MUSICLIB_DATA_DIR="\$MUSICLIB_XDG_DATA"

#############################################
# CORE PATHS
#############################################

# Location of Music Repository top directory level
MUSIC_REPO="$DETECTED_MUSIC_REPO"

# Library structure conformance (set by setup wizard analysis)
# true = all files follow artist/album/track structure with normalized names
# false = some files have non-standard paths (features may behave inconsistently)
LIBRARY_CONFORMING=$LIBRARY_CONFORMING

# Database location (XDG default)
MUSICDB="\${MUSICLIB_DATA_DIR}/data/musiclib.dsv"

# Playlists directory (XDG default)
PLAYLISTS_DIR="\${MUSICLIB_DATA_DIR}/playlists"
MOBILE_DIR="\$PLAYLISTS_DIR/mobile"

# Scripts directory (system-wide installation)
SCRIPTS_DIR="/usr/lib/musiclib/bin"

# Log file (XDG default)
LOGFILE="\${MUSICLIB_DATA_DIR}/logs/musiclib.log"

#############################################
# AUDACIOUS INTEGRATION
#############################################

# Audacious detection
AUDACIOUS_INSTALLED=$DETECTED_AUDACIOUS
AUDACIOUS_PATH="$DETECTED_AUDACIOUS_PATH"

# Conky output directory (XDG default)
MUSIC_DISPLAY_DIR="\${MUSICLIB_DATA_DIR}/data/conky_output"

# Scrobble threshold (percentage of song that must play to count as "played")
SCROBBLE_THRESHOLD_PCT=50

# Star rating images directory
STAR_DIR="\$MUSIC_DISPLAY_DIR/stars"

#############################################
# MOBILE SYNC (KDE CONNECT)
#############################################

# KDE Connect detection
KDECONNECT_INSTALLED=$DETECTED_KDECONNECT

# Android device ID (find with: kdeconnect-cli -a)
DEVICE_ID="$DETECTED_DEVICE_ID"

# Mobile playlist settings
MIN_PLAY_WINDOW=3600  # Minimum time window (seconds) for synthetic timestamps
CURRENT_PLAYLIST_FILE="\$MOBILE_DIR/current_playlist"

# Sets the limit for number of days since last mobile upload
MOBILE_WINDOW_DAYS=40

#############################################
# DATABASE SETTINGS
#############################################

# Default database values for new tracks
DEFAULT_RATING=0
DEFAULT_GROUPDESC=0

# Database lock timeout (seconds)
LOCK_TIMEOUT=5

# Backend API version (checked by GUI/CLI for compatibility)
BACKEND_API_VERSION="1.0"

#############################################
# TAG MANAGEMENT
#############################################

# Directory where new downloads / unzipped files are processed
NEW_DOWNLOAD_DIR="$DETECTED_DOWNLOAD_DIR"

# Alternative download locations (for quick switching in GUI)
ALTERNATE_DOWNLOAD_DIR_1=""
ALTERNATE_DOWNLOAD_DIR_2=""
ALTERNATE_DOWNLOAD_DIR_3=""

# Directory where tag backups are stored (XDG default)
TAG_BACKUP_DIR="\${MUSICLIB_DATA_DIR}/data/tag_backups"

# Number of days mp3 backups from tag changes are kept
MAX_BACKUP_AGE_DAYS=30

#############################################
# RATING SYSTEM (POPM VALUES)
#############################################

# POPM (Popularimeter) is the ID3v2 frame used to store ratings
# Rating mapping:
#   0 stars = 0 POPM
#   1 star  = 64 POPM
#   2 stars = 65-128 POPM
#   3 stars = 129-185 POPM
#   4 stars = 186-200 POPM
#   5 stars = 201-255 POPM

RatingGroup1="64,64"
RatingGroup2="65,128"
RatingGroup3="129,185"
RatingGroup4="186,200"
RatingGroup5="201,255"

#############################################
# EXTERNAL DEPENDENCIES
#############################################

EXIFTOOL_CMD="exiftool"
KID3_CMD="kid3-cli"
KDECONNECT_CMD="kdeconnect-cli"

# Optional dependency detection (set by setup wizard)
RSGAIN_INSTALLED=$DETECTED_RSGAIN
KID3_GUI_INSTALLED="$DETECTED_KID3_GUI"
EOF

print_success "Configuration saved to: $CONFIG_FILE"

#############################################
# Build Initial Database
#############################################

if [ "$BUILD_INITIAL_DB" = true ]; then
    print_header "Building Initial Database"

    print_info "Building database from: $DETECTED_MUSIC_REPO"
    print_info "(This may take several minutes for large libraries)"
    echo ""

    # Check if build script exists
    BUILD_SCRIPT="/usr/lib/musiclib/bin/musiclib_build.sh"

    if [ ! -f "$BUILD_SCRIPT" ]; then
        # Try development location
        BUILD_SCRIPT="$(dirname "$(readlink -f "$0")")/musiclib_build.sh"
    fi

    if [ -f "$BUILD_SCRIPT" ]; then
        if "$BUILD_SCRIPT" "$DETECTED_MUSIC_REPO"; then
            local track_count=$(wc -l < "$DB_PATH" 2>/dev/null || echo "0")
            print_success "Database created: $DB_PATH ($track_count tracks)"
        else
            print_error "Database build failed"
            echo ""
            print_info "You can build the database later with:"
            print_info "  musiclib-cli build"
        fi
    else
        print_error "Build script not found: $BUILD_SCRIPT"
        echo ""
        print_info "Install MusicLib and run:"
        print_info "  musiclib-cli build"
    fi
fi

#############################################
# Setup Complete
#############################################

print_header "Setup Complete!"

echo "Configuration saved to: $CONFIG_FILE"

if [ -n "$EXISTING_CONFIG_FILE" ] && [ "$EXISTING_CONFIG_FILE" != "$CONFIG_FILE" ]; then
    echo ""
    echo "NOTE: Configuration read from: $EXISTING_CONFIG_FILE"
    echo "      New configuration saved to: $CONFIG_FILE"
    echo ""
    echo "You may want to update your scripts to use the new location."
fi

echo ""
echo "Next steps:"
echo ""

# Auto-launch Audacious setup if enabled
if [ "$DETECTED_AUDACIOUS" = "true" ]; then
    echo "  1. Configure Audacious integration:"
    echo "     musiclib-cli audacious-setup"
    echo ""

    if prompt_yn "Launch Audacious setup now?" "y"; then
        echo ""
        # Try to find the setup script
        AUDACIOUS_SETUP_SCRIPT=""
        if [ -f "/usr/lib/musiclib/bin/musiclib_audacious_setup.sh" ]; then
            AUDACIOUS_SETUP_SCRIPT="/usr/lib/musiclib/bin/musiclib_audacious_setup.sh"
        elif [ -f "$(dirname "$0")/musiclib_audacious_setup.sh" ]; then
            AUDACIOUS_SETUP_SCRIPT="$(dirname "$0")/musiclib_audacious_setup.sh"
        elif command -v musiclib-cli &>/dev/null; then
            # Use CLI wrapper if available
            musiclib-cli audacious-setup
            AUDACIOUS_SETUP_SCRIPT="done"
        fi

        if [ -n "$AUDACIOUS_SETUP_SCRIPT" ] && [ "$AUDACIOUS_SETUP_SCRIPT" != "done" ] && [ -f "$AUDACIOUS_SETUP_SCRIPT" ]; then
            "$AUDACIOUS_SETUP_SCRIPT"
        elif [ "$AUDACIOUS_SETUP_SCRIPT" != "done" ]; then
            print_info "Audacious setup script not found"
            print_info "Run manually: musiclib-cli audacious-setup"
        fi
        echo ""
    fi
fi

echo "  2. Rate some tracks:"
echo "     musiclib-cli rate <file> <stars>"
echo ""

echo "  3. Import new music:"
echo "     musiclib-cli new-tracks <artist>"
echo ""

if [ "$BUILD_INITIAL_DB" = false ]; then
    echo "  4. Build music database:"
    echo "     musiclib-cli build"
    echo ""
fi

echo "Run 'musiclib-cli help' for full command reference."
echo ""

exit 0
