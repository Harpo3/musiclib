#!/bin/bash
#
# musiclib_init_config.sh - Simplified Setup Wizard
#
# Writes user-level local configuration to ~/.config/musiclib/musiclib.conf
# Overrides default settings at /usr/lib/musiclib/config/musiclib.conf
# Users can manually copy additional variables from /usr/lib/musiclib/config/musiclib.conf
# to override defaults.
#
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# XDG directories
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

CONFIG_DIR="${XDG_CONFIG_HOME}/musiclib"
DATA_DIR="${XDG_DATA_HOME}/musiclib"
CONFIG_FILE="${CONFIG_DIR}/musiclib.conf"

# Check if config already exists
EXISTING_CONFIG_FILE=""
if [ -f "$CONFIG_FILE" ]; then
    EXISTING_CONFIG_FILE="$CONFIG_FILE"
fi

# Detect Audacious and pre-check plugin-registry readiness
AUDACIOUS_DETECTED=false
AUDACIOUS_REGISTRY_READY=false
SONG_CHANGE_SO="/usr/lib/audacious/General/song_change.so"
PLUGIN_REGISTRY="$HOME/.config/audacious/plugin-registry"

if command -v audacious &>/dev/null; then
    AUDACIOUS_DETECTED=true
    if [ -f "$PLUGIN_REGISTRY" ] && grep -q "^general $SONG_CHANGE_SO" "$PLUGIN_REGISTRY"; then
        AUDACIOUS_REGISTRY_READY=true
    fi
fi

#############################################
# Helper Functions
#############################################

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

print_step() {
    echo ""
    echo "───────────────────────────────────────────────────────────"
    echo "  [$1] $2"
    echo "───────────────────────────────────────────────────────────"
    echo ""
}

print_success() {
    echo "✓ $1"
}

print_info() {
    echo "→ $1"
}

print_error() {
    echo "✗ ERROR: $1" >&2
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" response
    response="${response,,}" # lowercase

    if [ -z "$response" ]; then
        response="$default"
    fi

    [ "$response" = "y" ] || [ "$response" = "yes" ]
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local response

    read -p "$prompt [$default]: " response

    if [ -z "$response" ]; then
        echo "$default"
    else
        echo "$response"
    fi
}

count_audio_files() {
    local dir="$1"
    find "$dir" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.m4a" \) 2>/dev/null | wc -l
}

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

#############################################
# Parse Command Line Arguments
#############################################

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|help)
            cat << 'EOF'
Usage: musiclib_init_config.sh [options]

Simplified setup wizard for MusicLib configuration.

This wizard will:
  1. Locate your music repository
  2. Configure download directory
  3. Optionally configure KDE Connect device
  4. Create XDG directory structure
  5. Generate minimal user configuration
  6. Configure Audacious Song Change integration (if installed)

The wizard writes ONLY user-specific values to ~/.config/musiclib/musiclib.conf
All other settings use system defaults from /usr/lib/musiclib/config/musiclib.conf

Options:
  -h, --help    Show this help message
  --build-db    Build initial database after setup

EOF
            exit 0
            ;;
        --build-db)
            BUILD_DB=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$SCRIPT_NAME --help' for usage information."
            exit 1
            ;;
    esac
done

BUILD_DB="${BUILD_DB:-false}"

#############################################
# Welcome Banner
#############################################

clear
print_header "MusicLib Setup Wizard (Minimal Configuration)"

if [ -n "$EXISTING_CONFIG_FILE" ]; then
    echo "Welcome to MusicLib setup."
    echo "Existing configuration found - you can review and update your settings."
else
    echo "Welcome to MusicLib! Let's configure your music library."
fi
echo ""
echo "This wizard will only ask for essential settings."
echo "All other defaults are loaded from system configuration."
echo ""

if ! prompt_yn "Continue with setup?" "y"; then
    echo "Setup cancelled."
    exit 1
fi

# Early Audacious registry warning - before any wizard steps
if [ "$AUDACIOUS_DETECTED" = true ] && [ "$AUDACIOUS_REGISTRY_READY" = false ]; then
    echo ""
    print_info "Note: Audacious is installed but the Song Change plugin entry"
    print_info "was not found in ~/.config/audacious/plugin-registry."
    print_info "To enable Audacious integration at the end of this wizard:"
    print_info "  Open Audacious, then close it, then re-run setup."
    print_info "Setup will continue - all other steps are unaffected."
    echo ""
fi

#############################################
# Step 1: Locate Music Repository
#############################################

print_step "1/3" "Locating music repository"

# Read existing setting if available
EXISTING_MUSIC_REPO=""
if [ -n "$EXISTING_CONFIG_FILE" ]; then
    EXISTING_MUSIC_REPO=$(grep '^MUSIC_REPO=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')
    EXISTING_MUSIC_REPO=$(eval echo "$EXISTING_MUSIC_REPO" 2>/dev/null || echo "$EXISTING_MUSIC_REPO")
fi

# Default suggestions
if [ -n "$EXISTING_MUSIC_REPO" ] && [ -d "$EXISTING_MUSIC_REPO" ]; then
    DEFAULT_MUSIC_REPO="$EXISTING_MUSIC_REPO"
elif [ -d "$HOME/Music" ]; then
    DEFAULT_MUSIC_REPO="$HOME/Music"
elif [ -d "/mnt/music" ]; then
    DEFAULT_MUSIC_REPO="/mnt/music"
else
    DEFAULT_MUSIC_REPO="$HOME/Music"
fi

if [ -n "$EXISTING_MUSIC_REPO" ] && [ -d "$EXISTING_MUSIC_REPO" ]; then
    file_count=$(count_audio_files "$EXISTING_MUSIC_REPO")
    print_info "Current: $EXISTING_MUSIC_REPO ($file_count audio files)"
    echo ""

    if prompt_yn "Keep existing music repository?" "y"; then
        MUSIC_REPO="$EXISTING_MUSIC_REPO"
        print_success "Using: $MUSIC_REPO"
    else
        MUSIC_REPO=$(prompt_input "Enter music repository path" "$DEFAULT_MUSIC_REPO")
        MUSIC_REPO="${MUSIC_REPO/#\~/$HOME}"
    fi
else
    print_info "No music repository configured."
    echo ""
    MUSIC_REPO=$(prompt_input "Enter music repository path" "$DEFAULT_MUSIC_REPO")
    MUSIC_REPO="${MUSIC_REPO/#\~/$HOME}"
fi

# Validate directory
if [ ! -d "$MUSIC_REPO" ]; then
    print_error "Directory not found: $MUSIC_REPO"

    if prompt_yn "Create directory?" "n"; then
        mkdir -p "$MUSIC_REPO" || {
            print_error "Failed to create directory"
            exit 2
        }
        print_success "Created: $MUSIC_REPO"
    else
        print_error "Setup cannot continue without a valid music directory"
        exit 1
    fi
fi

file_count=$(count_audio_files "$MUSIC_REPO")
print_success "Music repository: $MUSIC_REPO ($file_count audio files)"

#############################################
# Step 2: Configure Download Directory
#############################################

print_step "2/3" "Configuring download directory"

# Read existing setting
EXISTING_DOWNLOAD_DIR=""
if [ -n "$EXISTING_CONFIG_FILE" ]; then
    EXISTING_DOWNLOAD_DIR=$(grep '^NEW_DOWNLOAD_DIR=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')
    EXISTING_DOWNLOAD_DIR=$(eval echo "$EXISTING_DOWNLOAD_DIR" 2>/dev/null || echo "$EXISTING_DOWNLOAD_DIR")
fi

# Default
if [ -n "$EXISTING_DOWNLOAD_DIR" ] && [ -d "$EXISTING_DOWNLOAD_DIR" ]; then
    DEFAULT_DOWNLOAD_DIR="$EXISTING_DOWNLOAD_DIR"
else
    DEFAULT_DOWNLOAD_DIR="$HOME/Downloads"
fi

if [ -n "$EXISTING_DOWNLOAD_DIR" ] && [ -d "$EXISTING_DOWNLOAD_DIR" ]; then
    print_info "Current: $EXISTING_DOWNLOAD_DIR"
    echo ""

    if prompt_yn "Keep existing download directory?" "y"; then
        DOWNLOAD_DIR="$EXISTING_DOWNLOAD_DIR"
    else
        DOWNLOAD_DIR=$(prompt_input "Enter download directory" "$DEFAULT_DOWNLOAD_DIR")
        DOWNLOAD_DIR="${DOWNLOAD_DIR/#\~/$HOME}"
    fi
else
    DOWNLOAD_DIR=$(prompt_input "Enter download directory" "$DEFAULT_DOWNLOAD_DIR")
    DOWNLOAD_DIR="${DOWNLOAD_DIR/#\~/$HOME}"
fi

# Create if needed
if [ ! -d "$DOWNLOAD_DIR" ]; then
    if prompt_yn "Create directory?" "y"; then
        mkdir -p "$DOWNLOAD_DIR" || {
            print_error "Failed to create directory"
            exit 2
        }
        print_success "Created: $DOWNLOAD_DIR"
    fi
fi

print_success "Download directory: $DOWNLOAD_DIR"

#############################################
# Step 3: KDE Connect (Optional)
#############################################

print_step "3/3" "KDE Connect configuration (optional)"

DEVICE_ID=""

# Read existing setting
EXISTING_DEVICE_ID=""
if [ -n "$EXISTING_CONFIG_FILE" ]; then
    EXISTING_DEVICE_ID=$(grep '^DEVICE_ID=' "$EXISTING_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')
fi

if command -v kdeconnect-cli &>/dev/null; then
    print_success "KDE Connect installed"

    # List available devices
    echo ""
    print_info "Available devices:"
    kdeconnect-cli -a 2>/dev/null || echo "  (none currently connected)"
    echo ""

    if [ -n "$EXISTING_DEVICE_ID" ]; then
        print_info "Current device ID: $EXISTING_DEVICE_ID"

        if prompt_yn "Keep existing device ID?" "y"; then
            DEVICE_ID="$EXISTING_DEVICE_ID"
        else
            if prompt_yn "Configure KDE Connect device?" "n"; then
                DEVICE_ID=$(prompt_input "Enter device ID (from list above)" "")
            fi
        fi
    else
        if prompt_yn "Configure KDE Connect device for mobile sync?" "n"; then
            DEVICE_ID=$(prompt_input "Enter device ID (from list above)" "")
        fi
    fi

    if [ -n "$DEVICE_ID" ]; then
        print_success "Device ID: $DEVICE_ID"
    else
        print_info "Skipped: Mobile sync disabled"
    fi
else
    print_info "KDE Connect not installed - mobile sync disabled"

    if prompt_yn "Install KDE Connect for mobile sync?" "n"; then
        echo ""
        print_info "Install using your package manager:"
        print_info "  Arch: sudo pacman -S kdeconnect"
        print_info "  Debian/Ubuntu: sudo apt install kdeconnect"
        print_info "  Fedora: sudo dnf install kdeconnect"
        echo ""
        print_info "Re-run setup after installation."
    fi
fi

#############################################
# Create Directory Structure
#############################################

print_header "Creating directory structure"

create_dir "$CONFIG_DIR"
create_dir "$DATA_DIR/data"
create_dir "$DATA_DIR/data/conky_output"
create_dir "$DATA_DIR/data/conky_output/stars"
create_dir "$DATA_DIR/data/tag_backups"
create_dir "$DATA_DIR/logs"
create_dir "$DATA_DIR/playlists"
create_dir "$DATA_DIR/playlists/mobile"
create_dir "$DATA_DIR/logs/audacious"
create_dir "$DATA_DIR/logs/mobile"

#############################################
# Generate MINIMAL Configuration File
#############################################

print_header "Generating configuration"

# Write user-specific overrides after backing up existing
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
fi
cat > "$CONFIG_FILE" << EOF
# MusicLib User Configuration
# Generated by setup wizard on $(date +"%Y-%m-%d %H:%M:%S")
#
# This file contains ONLY user-specific overrides.
# All other settings use defaults from /usr/lib/musiclib/config/musiclib.conf
#
# To customize additional settings, add them below.
# See /usr/lib/musiclib/config/musiclib.conf for available options.

#############################################
# USER-SPECIFIC PATHS
#############################################

# Music repository location
MUSIC_REPO="$MUSIC_REPO"

# Download directory for new track imports
NEW_DOWNLOAD_DIR="$DOWNLOAD_DIR"

EOF

# Only add DEVICE_ID if it was actually configured
if [ -n "$DEVICE_ID" ]; then
    cat >> "$CONFIG_FILE" << EOF
#############################################
# MOBILE SYNC
#############################################

# KDE Connect device ID for mobile playlist sync
DEVICE_ID="$DEVICE_ID"

EOF
fi

print_success "Configuration saved to: $CONFIG_FILE"
echo ""
print_info "Configuration contains only your custom settings."
print_info "All other defaults are loaded from system configuration."

#############################################
# Build Initial Database (Optional)
#############################################

if [ "$BUILD_DB" = true ]; then
    print_header "Building initial database"

    DB_FILE="${DATA_DIR}/data/musiclib.dsv"

    if [ -f "$DB_FILE" ]; then
        print_info "Database already exists: $DB_FILE"

        if ! prompt_yn "Rebuild database (existing data will be backed up)?" "n"; then
            print_info "Skipped: Database rebuild"
            BUILD_DB=false
        fi
    fi

    if [ "$BUILD_DB" = true ]; then
        REBUILD_SCRIPT="/usr/lib/musiclib/bin/musiclib_build.sh"

        if [ -f "$REBUILD_SCRIPT" ]; then
            print_info "Running: $REBUILD_SCRIPT"
            echo ""

            "$REBUILD_SCRIPT" "$MUSIC_REPO" || {
                print_error "Database build failed"
                exit 2
            }

            echo ""
            print_success "Database build complete"
        else
            print_error "Build script not found: $REBUILD_SCRIPT"
            print_info "Install the musiclib package to access backend scripts."
        fi
    fi
fi

#############################################
# Audacious Integration (Optional)
#############################################

if [ "$AUDACIOUS_DETECTED" = true ]; then
    print_header "Audacious Integration"

    print_success "Audacious is installed"
    echo ""
    print_info "MusicLib hooks into Audacious via the Song Change plugin"
    print_info "to update Conky display data whenever the track changes."
    echo ""

    if prompt_yn "Configure Audacious Song Change integration now?" "y"; then
        echo ""

        # Determine hook script path: installed location first, dev/sibling fallback
        HOOK_SCRIPT="/usr/lib/musiclib/bin/musiclib_audacious.sh"
        if [ ! -f "$HOOK_SCRIPT" ]; then
            HOOK_SCRIPT="$(dirname "$(readlink -f "$0")")/musiclib_audacious.sh"
        fi

        if [ ! -f "$HOOK_SCRIPT" ]; then
            print_error "Hook script not found at either installed or development path"
            print_info "Expected: /usr/lib/musiclib/bin/musiclib_audacious.sh"
            print_info "Re-run setup after installing the musiclib package."
        else
            AUDACIOUS_CONFIG="$HOME/.config/audacious/config"
            PLUGIN_REGISTRY="$HOME/.config/audacious/plugin-registry"
            SONG_CHANGE_SO="/usr/lib/audacious/General/song_change.so"

            # Audacious overwrites its config on exit, so it must be closed first
            if pgrep -x audacious >/dev/null 2>&1; then
                print_error "Audacious is currently running"
                print_info "Close Audacious and re-run setup to configure integration."
                print_info "Or configure manually - see: musiclib-cli audacious-setup"
            elif [ "$AUDACIOUS_REGISTRY_READY" = false ]; then
                print_info "Song Change plugin entry not found in plugin-registry"
                print_info "Open and close Audacious once, then re-run setup."
            else
                # Flip enabled 0 -> enabled 1 within the song_change.so block only
                awk -v so="general $SONG_CHANGE_SO" '
                    $0 == so        { in_block=1 }
                    in_block && /^enabled 0$/ { sub(/^enabled 0$/, "enabled 1"); in_block=0 }
                    { print }
                ' "$PLUGIN_REGISTRY" > "${PLUGIN_REGISTRY}.tmp" \
                    && mv "${PLUGIN_REGISTRY}.tmp" "$PLUGIN_REGISTRY"
                print_success "Song Change plugin enabled in plugin-registry"

                # --- Step 2: Write cmd_line to audacious config ---
                if [ ! -f "$AUDACIOUS_CONFIG" ]; then
                    # Config file does not exist - create it with the section
                    mkdir -p "$(dirname "$AUDACIOUS_CONFIG")"
                    printf '\n[song_change]\ncmd_line=%s\n' "$HOOK_SCRIPT" \
                        > "$AUDACIOUS_CONFIG"
                    print_success "Created Audacious config with Song Change hook"
                elif grep -q "^\[song_change\]" "$AUDACIOUS_CONFIG"; then
                    # Section exists - update or insert cmd_line
                    if grep -q "^cmd_line=" "$AUDACIOUS_CONFIG"; then
                        sed -i "s|^cmd_line=.*|cmd_line=$HOOK_SCRIPT|" \
                            "$AUDACIOUS_CONFIG"
                        print_success "Updated Song Change cmd_line in Audacious config"
                    else
                        sed -i "/^\[song_change\]/a cmd_line=$HOOK_SCRIPT" \
                            "$AUDACIOUS_CONFIG"
                        print_success "Added Song Change cmd_line to Audacious config"
                    fi
                else
                    # Section absent - append it
                    printf '\n[song_change]\ncmd_line=%s\n' "$HOOK_SCRIPT" \
                        >> "$AUDACIOUS_CONFIG"
                    print_success "Added [song_change] section to Audacious config"
                fi
            fi
        fi
        echo ""
    else
        print_info "Skipped: Run 'musiclib-cli audacious-setup' at any time to configure."
    fi
fi

#############################################
# Setup Complete
#############################################

print_header "Setup Complete!"

echo "MusicLib has been configured."
echo ""
echo "Configuration file: $CONFIG_FILE"
echo "Music repository:   $MUSIC_REPO"
echo "Download directory: $DOWNLOAD_DIR"

if [ -n "$DEVICE_ID" ]; then
    echo "Mobile device:      $DEVICE_ID"
fi

echo ""
echo "Next steps:"
echo "  1. Install musiclib package if not already installed"
echo "  2. Run 'musiclib-cli build' to create/update database"
echo ""
echo "To customize additional settings, edit:"
echo "  $CONFIG_FILE"
echo ""
echo "For available options, see:"
echo "  /usr/lib/musiclib/config/musiclib.conf"
echo ""

exit 0
