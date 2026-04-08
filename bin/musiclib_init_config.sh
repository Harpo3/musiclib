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

EXISTING_MUSIC_REPO=""
if command -v audacious &>/dev/null; then
    AUDACIOUS_DETECTED=true
    if [ -f "$PLUGIN_REGISTRY" ] && grep -q "^general $SONG_CHANGE_SO" "$PLUGIN_REGISTRY"; then
        AUDACIOUS_REGISTRY_READY=true
    fi
    # Pre-populate EXISTING_MUSIC_REPO from Audacious [search-tool] path if available
    _aud_config="$HOME/.config/audacious/config"
    if [ -f "$_aud_config" ]; then
        _aud_path=$(awk '/^\[search-tool\]/{found=1; next} found && /^path=/{sub(/^path=/, ""); print; exit} found && /^\[/{exit}' "$_aud_config")
        if [ -n "$_aud_path" ]; then
            EXISTING_MUSIC_REPO="$_aud_path"
            print_info "Library location found in Audacious settings: $_aud_path"
        fi
    fi
fi

# Detect optional tools
RSGAIN_DETECTED=false
if command -v rsgain &>/dev/null; then
    RSGAIN_DETECTED=true
fi

KID3_GUI_DETECTED="none"
if command -v kid3 &>/dev/null; then
    KID3_GUI_DETECTED="kid3"
elif command -v kid3-qt &>/dev/null; then
    KID3_GUI_DETECTED="kid3-qt"
fi

K3B_DETECTED=false
if command -v k3b &>/dev/null; then
    K3B_DETECTED=true
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

# Read a single key=value from a config file (strips quotes).
# Usage: read_conf_key KEY FILE
read_conf_key() {
    local key="$1"
    local file="$2"
    # '|| true' on grep: under 'set -o pipefail' a no-match (exit 1) would
    # otherwise propagate as the pipeline's exit status and abort the script.
    { grep "^${key}=" "$file" 2>/dev/null || true; } | head -1 | cut -d'=' -f2- | tr -d '"'
}

# Return the predominant K3b-supported format (mp3/ogg/flac) found in MUSIC_REPO.
# Falls back to "mp3" when the library is empty or has no supported formats.
detect_library_format() {
    local music_repo="$1"
    local mp3_count ogg_count flac_count
    mp3_count=$(find "$music_repo" -type f -iname "*.mp3" 2>/dev/null | wc -l)
    ogg_count=$(find  "$music_repo" -type f -iname "*.ogg"  2>/dev/null | wc -l)
    flac_count=$(find "$music_repo" -type f -iname "*.flac" 2>/dev/null | wc -l)

    if [ "$mp3_count" -eq 0 ] && [ "$ogg_count" -eq 0 ] && [ "$flac_count" -eq 0 ]; then
        echo "mp3"
        return
    fi

    if [ "$mp3_count" -ge "$ogg_count" ] && [ "$mp3_count" -ge "$flac_count" ]; then
        echo "mp3"
    elif [ "$ogg_count" -ge "$flac_count" ]; then
        echo "ogg"
    else
        echo "flac"
    fi
}

# Create a dated backup of a k3brc file in ~/.config/musiclib/backups/.
# Naming: k3brc_bak_MMDDYYYY_N (increments N if the slot is taken).
backup_k3brc() {
    local source="$1"
    local backup_dir="${CONFIG_DIR}/backups"
    mkdir -p "$backup_dir"

    local today n dest
    today=$(date +%m%d%Y)
    n=1
    while true; do
        dest="${backup_dir}/k3brc_bak_${today}_${n}"
        [ ! -f "$dest" ] && break
        n=$(( n + 1 ))
    done

    cp "$source" "$dest"
    print_info "Backed up existing k3brc → $dest"
}

# Patch all musiclib-managed keys in a k3brc file in-place.
# Reads K3B_* values from the user config (overrides) then system config (defaults).
# Uses DOWNLOAD_DIR (set by Step 2) as the rip output directory.
# Usage: patch_k3brc TARGET_FILE
patch_k3brc() {
    local target="$1"
    local system_conf="/usr/lib/musiclib/config/musiclib.conf"

    # Load K3B_* values — user config overrides system defaults
    local enc_format mp3_mode mp3_bitrate mp3_vbr mp3_abr ogg_qual paranoia retries

    enc_format=$(read_conf_key K3B_ENCODER_FORMAT "$CONFIG_FILE")
    [ -z "$enc_format" ] && enc_format=$(read_conf_key K3B_ENCODER_FORMAT "$system_conf")
    enc_format="${enc_format:-mp3}"

    mp3_mode=$(read_conf_key K3B_MP3_MODE "$CONFIG_FILE")
    [ -z "$mp3_mode" ] && mp3_mode=$(read_conf_key K3B_MP3_MODE "$system_conf")
    mp3_mode="${mp3_mode:-cbr}"

    mp3_bitrate=$(read_conf_key K3B_MP3_BITRATE "$CONFIG_FILE")
    [ -z "$mp3_bitrate" ] && mp3_bitrate=$(read_conf_key K3B_MP3_BITRATE "$system_conf")
    mp3_bitrate="${mp3_bitrate:-320}"

    mp3_vbr=$(read_conf_key K3B_MP3_VBR_QUALITY "$CONFIG_FILE")
    [ -z "$mp3_vbr" ] && mp3_vbr=$(read_conf_key K3B_MP3_VBR_QUALITY "$system_conf")
    mp3_vbr="${mp3_vbr:-2}"

    mp3_abr=$(read_conf_key K3B_MP3_ABR_TARGET "$CONFIG_FILE")
    [ -z "$mp3_abr" ] && mp3_abr=$(read_conf_key K3B_MP3_ABR_TARGET "$system_conf")
    mp3_abr="${mp3_abr:-192}"

    ogg_qual=$(read_conf_key K3B_OGG_QUALITY "$CONFIG_FILE")
    [ -z "$ogg_qual" ] && ogg_qual=$(read_conf_key K3B_OGG_QUALITY "$system_conf")
    ogg_qual="${ogg_qual:-6}"

    paranoia=$(read_conf_key K3B_PARANOIA_MODE "$CONFIG_FILE")
    [ -z "$paranoia" ] && paranoia=$(read_conf_key K3B_PARANOIA_MODE "$system_conf")
    paranoia="${paranoia:-0}"

    retries=$(read_conf_key K3B_READ_RETRIES "$CONFIG_FILE")
    [ -z "$retries" ] && retries=$(read_conf_key K3B_READ_RETRIES "$system_conf")
    retries="${retries:-5}"

    # Rip output directory — use DOWNLOAD_DIR (in-session) or fall back to config
    local rip_dir_raw rip_dir
    rip_dir_raw="${DOWNLOAD_DIR:-$(read_conf_key NEW_DOWNLOAD_DIR "$CONFIG_FILE")}"
    rip_dir_raw="${rip_dir_raw%/}"  # strip trailing slash

    # Convert absolute home path to $HOME placeholder for KDE config portability
    rip_dir="${rip_dir_raw/#$HOME/\$HOME}"

    # Encoder plugin name — ogg uses its own plugin; mp3 and flac use external
    local encoder_plugin
    case "$enc_format" in
        ogg) encoder_plugin="k3boggvorbisencoder" ;;
        *)   encoder_plugin="k3bexternalencoder"  ;;
    esac

    # Assemble LAME command based on MP3 mode
    local lame_base lame_meta lame_cmd
    lame_base="lame -r --bitwidth 16 --little-endian -s 44.1 -h"
    lame_meta="--tt %t --ta %a --tl %m --ty %y --tc %c --tn %n - %f"
    case "$mp3_mode" in
        vbr) lame_cmd="${lame_base} --vbr-new -V ${mp3_vbr} ${lame_meta}"  ;;
        abr) lame_cmd="${lame_base} --abr ${mp3_abr} ${lame_meta}"          ;;
        *)   lame_cmd="${lame_base} -b ${mp3_bitrate} ${lame_meta}"         ;;
    esac

    # Remove erroneous Temp Dir (Issue #4) — safe no-op if already absent
    sed -i '/^Temp Dir=/d' "$target"

    # --- [Audio Ripping] and [last used Audio Ripping] ---
    # Global replace hits both sections, keeping them in lock-step.
    #
    # Escaping note for [$e] keys:
    #   In bash double-quotes: \\[ -> \[  and  \$e -> $e (literal $)  and  \\] -> \]
    #   sed receives the pattern \[$e\] which matches the literal string [$e].
    #   In the replacement, [\$e] -> bash sends [$e] -> sed outputs [$e].

    sed -i "s|^last ripping directory\\[\$e\\]=.*|last ripping directory[\$e]=file:${rip_dir}/|" "$target"
    sed -i "s|^encoder=.*|encoder=${encoder_plugin}|" "$target"
    sed -i "s|^filetype=.*|filetype=${enc_format}|"   "$target"
    sed -i "s|^paranoia_mode=.*|paranoia_mode=${paranoia}|" "$target"
    sed -i "s|^read_retries=.*|read_retries=${retries}|"    "$target"

    # --- [file view] ---
    sed -i "s|^last url\\[\$e\\]=.*|last url[\$e]=${rip_dir}/|" "$target"

    # --- [K3bExternalEncoderPlugin] ---
    # Full entry format: DisplayName,extension,shell_command
    sed -i "s|^command_Mp3 (Lame)=.*|command_Mp3 (Lame)=Mp3 (Lame),mp3,${lame_cmd}|" "$target"

    # --- [K3bOggVorbisEncoderPlugin] ---
    # quality= only appears in this section; global replace is safe.
    sed -i "s|^quality=.*|quality=${ogg_qual}|" "$target"
}

# Generate ~/.config/musiclib/k3brc.
# If ~/.config/k3brc already exists, prompt whether to retain it as the
# baseline (preserving other K3b customisations). Otherwise uses the system
# template. Either way, patch_k3brc is always called to update all
# musiclib-managed keys.
generate_k3brc() {
    local system_template="/usr/lib/musiclib/config/k3brc"
    local live_k3brc="${HOME}/.config/k3brc"
    local target="${CONFIG_DIR}/k3brc"

    if [ ! -f "$system_template" ]; then
        print_error "System k3brc template not found at $system_template — skipping k3brc generation."
        return 1
    fi

    # Backup any existing musiclib k3brc (re-run case)
    if [ -f "$target" ]; then
        backup_k3brc "$target"
    fi

    # Choose baseline
    if [ -f "$live_k3brc" ]; then
        echo ""
        print_info "An existing K3b configuration was found at ~/.config/k3brc."
        if prompt_yn "Did you already configure K3b and want to keep those settings?" "n"; then
            # Copy existing k3brc as baseline; Temp Dir is stripped by patch_k3brc below
            cp "$live_k3brc" "$target"
            print_success "Existing K3b settings captured as baseline."
        else
            cp "$system_template" "$target"
            print_info "Using system default K3b profile as baseline."
        fi
    else
        cp "$system_template" "$target"
        print_info "No existing K3b config found — using system default profile."
    fi

    # Always patch all musiclib-managed keys (rip dir, format, encoder, etc.)
    patch_k3brc "$target"
    print_success "K3b profile written to: $target"
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

analyze_library() {
    local music_repo="$1"
    music_repo="${music_repo%/}"  # strip any trailing slash
    local report_dir="${DATA_DIR}/data"
    local temp_nonconforming
    temp_nonconforming=$(mktemp)
    local report_file="${report_dir}/library_analysis_report.txt"

    local total=0
    local conforming=0
    local nonconforming=0

    while IFS= read -r -d '' filepath; do
        total=$(( total + 1 ))

        # Get path relative to music_repo
        local relpath="${filepath#$music_repo/}"

        # Check structure: should be artist/album/filename.ext (exactly 2 slashes)
        local depth
        depth=$(echo "$relpath" | tr -cd '/' | wc -c)
        local structure_ok=false
        if [ "$depth" -eq 2 ]; then
            structure_ok=true
        fi

        # Check filename: lowercase a-z, digits, underscore, hyphen, period only
        local filename
        filename=$(basename "$filepath")
        local filename_ok=false
        if echo "$filename" | grep -qE '^[a-z0-9_.-]+$'; then
            filename_ok=true
        fi

        # Determine overall conformance
        if [ "$structure_ok" = true ] && [ "$filename_ok" = true ]; then
            conforming=$(( conforming + 1 ))
        else
            nonconforming=$(( nonconforming + 1 ))
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
        if [ $(( total % 500 )) -eq 0 ]; then
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
        echo "Conforming files: $conforming ($(( conforming * 100 / (total > 0 ? total : 1) ))%)"
        echo "Non-conforming files: $nonconforming ($(( nonconforming * 100 / (total > 0 ? total : 1) ))%)"
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
    local nonconforming_list="${report_dir}/nonconforming_files"
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
Usage: musiclib-cli setup [options]

Simplified setup wizard for MusicLib configuration.

This wizard will:
  1. Locate your music repository
  2. Configure download directory
  3. Optionally configure KDE Connect device
  4. Create XDG directory structure
  5. Generate minimal user configuration
  6. Auto-detect optional tools (rsgain, kid3 GUI) and write to config
  7. Scan library for file and directory conformance
  8. Refresh playlists from Audacious (if installed)
  9. Configure Audacious Song Change integration (if installed)
 10. Install Dolphin service menu for right-click track rating (if KIO servicemenus dir is available)

The wizard writes ONLY user-specific values to ~/.config/musiclib/musiclib.conf
All other settings use system defaults from /usr/lib/musiclib/config/musiclib.conf

Options:
  -h, --help    Show this help message

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
# Note: EXISTING_MUSIC_REPO may already be pre-set from Audacious detection above;
# musiclib config takes priority if present, otherwise the Audacious-detected value is kept.
if [ -n "$EXISTING_CONFIG_FILE" ]; then
    _conf_repo=$(read_conf_key MUSIC_REPO "$EXISTING_CONFIG_FILE")
    _conf_repo=$(eval echo "$_conf_repo" 2>/dev/null || echo "$_conf_repo")
    [ -n "$_conf_repo" ] && EXISTING_MUSIC_REPO="$_conf_repo"
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
    EXISTING_DOWNLOAD_DIR=$(read_conf_key NEW_DOWNLOAD_DIR "$EXISTING_CONFIG_FILE")
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
    EXISTING_DEVICE_ID=$(read_conf_key DEVICE_ID "$EXISTING_CONFIG_FILE")
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

# Capture any non-wizard, non-comment lines from existing config before overwriting
CUSTOM_LINES=""
RETAIN_CUSTOM=false
if [ -f "$CONFIG_FILE" ]; then
    WIZARD_KEYS="^(MUSIC_REPO|NEW_DOWNLOAD_DIR|DEVICE_ID|RSGAIN_INSTALLED|KID3_GUI_INSTALLED|K3B_INSTALLED|K3B_ENCODER_FORMAT)="
    while IFS= read -r line; do
        # Skip blank lines and comment lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        # Skip wizard-managed and auto-detected keys
        [[ "$line" =~ $WIZARD_KEYS ]] && continue
        # Accumulate remaining custom lines
        if [ -z "$CUSTOM_LINES" ]; then
            CUSTOM_LINES="$line"
        else
            CUSTOM_LINES="$CUSTOM_LINES"$'\n'"$line"
        fi
    done < "$CONFIG_FILE"

    if [ -n "$CUSTOM_LINES" ]; then
        echo "Other custom settings found:"
        echo ""
        echo "$CUSTOM_LINES"
        echo ""
        if prompt_yn "Retain these settings?" "y"; then
            RETAIN_CUSTOM=true
        fi
        echo ""
    fi
fi

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

# Write optional dependency overrides only when detected (differ from system defaults)
if [ "$RSGAIN_DETECTED" = true ] || [ "$KID3_GUI_DETECTED" != "none" ] || [ "$K3B_DETECTED" = true ]; then
    cat >> "$CONFIG_FILE" << EOF
#############################################
# OPTIONAL DEPENDENCIES (auto-detected by setup)
#############################################

EOF
    if [ "$RSGAIN_DETECTED" = true ]; then
        cat >> "$CONFIG_FILE" << 'EOF'
# rsgain detected - Boost Album feature enabled in the GUI
RSGAIN_INSTALLED=true

EOF
    fi
    if [ "$KID3_GUI_DETECTED" != "none" ]; then
        cat >> "$CONFIG_FILE" << EOF
# kid3 GUI detected - tag editor integration enabled
KID3_GUI_INSTALLED="$KID3_GUI_DETECTED"

EOF
    fi
    # Apply musiclib tag standards to kid3's shared config file.
    # This runs once at install time; runtime drift is caught by sync_external_tool_config()
    # in musiclib_utils_tag_functions.sh on each subsequent script invocation.
    if command -v kid3-cli &>/dev/null; then
        # Read POPM_STAR values from system config; fall back to kid3 defaults.
        # Uses read_conf_key() (pipeline starts with 'head -1' so it never
        # triggers set -o pipefail when the key is absent).
        _sys_conf="/usr/lib/musiclib/config/musiclib.conf"
        _p1=1; _p2=64; _p3=128; _p4=196; _p5=255
        if [ -f "$_sys_conf" ]; then
            _v=$(read_conf_key POPM_STAR1 "$_sys_conf"); [ -n "$_v" ] && _p1=$_v || true
            _v=$(read_conf_key POPM_STAR2 "$_sys_conf"); [ -n "$_v" ] && _p2=$_v || true
            _v=$(read_conf_key POPM_STAR3 "$_sys_conf"); [ -n "$_v" ] && _p3=$_v || true
            _v=$(read_conf_key POPM_STAR4 "$_sys_conf"); [ -n "$_v" ] && _p4=$_v || true
            _v=$(read_conf_key POPM_STAR5 "$_sys_conf"); [ -n "$_v" ] && _p5=$_v || true
        fi
        # Point kid3-cli at the shared GUI config file (same as KID3_CONFIG_FILE in musiclib.conf)
        export KID3_CONFIG_FILE="$HOME/.config/kid3rc"
        # Use kid3-cli config writes only to create kid3rc when it does not yet exist.
        # kid3-cli rewrites the whole file from internal state and strips StarRatingMapping,
        # so writes are limited to bootstrap; the Python patch below handles all subsequent
        # changes.  The starRatingMappingStrings command was read-only and had no effect.
        if [ ! -f "$KID3_CONFIG_FILE" ]; then
            kid3-cli -c "config Tag.customFrames Songs-DB_Custom1 Songs-DB_Custom2 CATALOGNUMBER" &>/dev/null || true
            kid3-cli -c "config Tag.textEncoding TE_UTF8" &>/dev/null || true
        fi
        # Patch kid3rc directly — same three-setting logic used by sync_external_tool_config()
        # at runtime.  StarRatingMapping is updated in-place or injected if absent.
        _kid3rc="$KID3_CONFIG_FILE"
        if [ -f "$_kid3rc" ]; then
            python3 - "$_kid3rc" "$_p1" "$_p2" "$_p3" "$_p4" "$_p5" &>/dev/null << 'PYEOF' || true
import re, sys

rc, p1, p2, p3, p4, p5 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

with open(rc) as f:
    content = f.read()

def patch_in_section(text, section, key, new_val):
    def _repl(m):
        return re.sub(
            r'^(' + re.escape(key) + r'=).*$',
            lambda mm: mm.group(1) + new_val,
            m.group(0),
            flags=re.MULTILINE
        )
    return re.sub(
        r'(?m)^\[' + re.escape(section) + r'\].*?(?=^\[|\Z)',
        _repl,
        text,
        flags=re.DOTALL
    )

content = patch_in_section(content, 'Tags', 'CustomFrames',
                            'Songs-DB_Custom1, Songs-DB_Custom2, CATALOGNUMBER')
content = patch_in_section(content, 'Tags', 'TextEncoding', '2')

srm_pat = r'(StarRatingMapping=POPM\\\\,)\d+(\\\\,)\d+(\\\\,)\d+(\\\\,)\d+(\\\\,)\d+'
srm_repl = r'\g<1>' + p1 + r'\g<2>' + p2 + r'\g<3>' + p3 + r'\g<4>' + p4 + r'\g<5>' + p5
new_content, n = re.subn(srm_pat, srm_repl, content)
if n:
    content = new_content
else:
    new_line = 'StarRatingMapping=POPM\\\\,' + p1 + '\\\\,' + p2 + '\\\\,' + p3 + '\\\\,' + p4 + '\\\\,' + p5 + '\n'
    content = re.sub(r'(?m)(^\[Tags\]\n)', lambda m: m.group(0) + new_line, content, count=1)

with open(rc, 'w') as f:
    f.write(content)
sys.exit(0)
PYEOF
        fi
        unset _kid3rc
        # Seed the runtime stamp so sync_external_tool_config() skips re-application on first run.
        # Stores mtime of the local config file; matches the mtime check used at runtime.
        _hash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/musiclib"
        mkdir -p "$_hash_dir"
        printf '%s\n' "$(stat -c %Y "${XDG_CONFIG_HOME:-$HOME/.config}/musiclib/musiclib.conf" 2>/dev/null)" \
            > "${_hash_dir}/kid3_config.hash"
        unset _sys_conf _p1 _p2 _p3 _p4 _p5 _v _hash_dir
    fi
    if [ "$K3B_DETECTED" = true ]; then
        # Detect the predominant audio format in the library to seed the rip format default.
        # Only write K3B_ENCODER_FORMAT when it differs from the system default (mp3).
        print_info "Scanning library for predominant audio format..."
        K3B_DETECTED_FORMAT=$(detect_library_format "$MUSIC_REPO")
        print_success "Library format detected: $K3B_DETECTED_FORMAT"

        cat >> "$CONFIG_FILE" << 'EOF'
# k3b detected - CD ripping panel enabled
K3B_INSTALLED=true

EOF
        if [ "$K3B_DETECTED_FORMAT" != "mp3" ]; then
            cat >> "$CONFIG_FILE" << EOF
# Rip output format auto-detected from library
K3B_ENCODER_FORMAT=$K3B_DETECTED_FORMAT

EOF
        fi

        # Generate ~/.config/musiclib/k3brc (prompts user if ~/.config/k3brc exists)
        generate_k3brc
        K3B_SETUP_DONE=true
    fi
fi

print_success "Configuration saved to: $CONFIG_FILE"
echo ""
print_info "Configuration contains only your custom settings."
print_info "All other defaults are loaded from system configuration."

# Append retained custom settings
if [ "$RETAIN_CUSTOM" = true ]; then
    {
        printf '\n'
        printf '#############################################\n'
        printf '# RETAINED CUSTOM SETTINGS\n'
        printf '#############################################\n'
        printf '\n'
        printf '%s\n' "$CUSTOM_LINES"
    } >> "$CONFIG_FILE"
    print_success "Custom settings retained."
fi

#############################################
# Library Conformance Check
#############################################

print_header "Library Conformance Check"

if [ "$file_count" -eq 0 ]; then
    print_info "No audio files found in $MUSIC_REPO — skipping conformance check."
else
    print_info "Scanning library for file and directory conformance..."
    echo ""

    ANALYSIS_TOTAL=0
    ANALYSIS_CONFORMING=0
    ANALYSIS_NONCONFORMING=0
    ANALYSIS_REPORT_FILE=""

    analyze_library "$MUSIC_REPO"

    echo "  Total files scanned: $ANALYSIS_TOTAL"
    echo "  Conforming:          $ANALYSIS_CONFORMING"
    echo "  Non-conforming:      $ANALYSIS_NONCONFORMING"
    echo ""

    if [ "$ANALYSIS_NONCONFORMING" -gt 0 ]; then
        CONFORM_PCT=$(( ANALYSIS_NONCONFORMING * 100 / (ANALYSIS_TOTAL > 0 ? ANALYSIS_TOTAL : 1) ))
        echo "⚠ WARNING: Non-conforming filenames detected in your music library."
        echo ""
        echo "Found $ANALYSIS_NONCONFORMING files ($CONFORM_PCT%) with:"
        echo "  - Uppercase letters"
        echo "  - Spaces"
        echo "  - Special characters or incorrect directory depth"
        echo ""
        echo "MusicLib requires lowercase filenames with underscores for reliable"
        echo "operation. Non-conforming files may cause issues with mobile sync"
        echo "and path matching."
        echo ""
        echo "A full report has been saved to:"
        echo "  $ANALYSIS_REPORT_FILE"
        echo ""
        echo "Options:"
        echo "  1. Continue anyway (may cause issues with mobile sync and path matching)"
        echo "  2. Exit and run conform_musiclib.sh to fix filenames"
        echo "  3. Cancel setup"
        echo ""

        CONFORM_CHOICE=""
        while true; do
            read -p "Choice [1/2/3]: " CONFORM_CHOICE
            case "$CONFORM_CHOICE" in
                1)
                    echo ""
                    print_info "⚠ Continuing with non-conforming files. You can fix them later by running:"
                    print_info "  ~/.local/share/musiclib/utilities/conform_musiclib.sh --execute $MUSIC_REPO"
                    print_info "Then rebuild the database with: musiclib-cli build"
                    echo ""
                    break
                    ;;
                2)
                    echo ""
                    print_info "Exiting setup. To fix filenames, run:"
                    echo ""
                    echo "  ~/.local/share/musiclib/utilities/conform_musiclib.sh --execute $MUSIC_REPO"
                    echo ""
                    print_info "After the script completes, re-run setup: musiclib-cli setup"
                    echo ""
                    exit 0
                    ;;
                3)
                    echo ""
                    echo "Setup cancelled."
                    exit 1
                    ;;
                *)
                    echo "Please enter 1, 2, or 3."
                    ;;
            esac
        done
    else
        print_success "All $ANALYSIS_TOTAL files conform to MusicLib naming standards."
    fi
fi

#############################################
# Database Check
#############################################

print_header "Database Check"

DB_FILE="${DATA_DIR}/data/musiclib.dsv"

if [ -f "$DB_FILE" ]; then
    print_success "Database found"
else
    echo "Looks like this is a first time install - no database found at: $DB_FILE"
    echo ""

    if prompt_yn "Build it now?" "n"; then
        echo ""
        if command -v musiclib-cli &>/dev/null; then
            musiclib-cli build "$MUSIC_REPO" || print_error "Database build failed"
        else
            print_error "musiclib-cli not found - install the musiclib package first"
            print_info "When ready just run 'musiclib-cli build' in the terminal."
        fi
    else
        echo ""
        print_info "When ready just run 'musiclib-cli build' in the terminal."
    fi
fi

#############################################
# Audacious Integration
#############################################

if [ "$AUDACIOUS_DETECTED" = true ]; then
    print_header "Audacious Integration"

    print_success "Audacious is installed"
    echo ""
    print_info "MusicLib hooks into Audacious via the Song Change plugin"
    print_info "to update Conky display data whenever the track changes, and "
    print_info "to update the database and file tags with last-played date."
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
fi

#############################################
# Refresh Playlists from Audacious
#############################################

AUDACIOUS_PLAYLISTS_SRC="${HOME}/.config/audacious/playlists"

if [ -d "$AUDACIOUS_PLAYLISTS_SRC" ]; then
    print_header "Refreshing playlists from Audacious"

    MOBILE_SCRIPT="/usr/lib/musiclib/bin/musiclib_mobile.sh"
    if [ ! -f "$MOBILE_SCRIPT" ]; then
        MOBILE_SCRIPT="$(dirname "$(readlink -f "$0")")/musiclib_mobile.sh"
    fi

    if [ ! -f "$MOBILE_SCRIPT" ]; then
        print_info "Skipped: musiclib_mobile.sh not found"
        print_info "Install the musiclib package and re-run setup to populate playlists."
    else
        print_info "Copying Audacious playlists → $DATA_DIR/playlists"
        echo ""
        if "$MOBILE_SCRIPT" refresh-audacious-only 2>/dev/null; then
            echo ""
            print_success "Playlist directory populated from Audacious"
        else
            echo ""
            print_info "Playlist refresh could not complete (kdeconnect-cli may not be installed)"
            print_info "Run manually: musiclib-cli mobile refresh-audacious-only"
        fi
    fi
else
    print_info "No Audacious playlists found at: $AUDACIOUS_PLAYLISTS_SRC"
    print_info "Open Audacious, create playlists, then run: musiclib-cli mobile refresh-audacious-only"
fi

#############################################
# Dolphin Service Menu (Rate Track)
#############################################

print_header "Dolphin Service Menu"

SERVICEMENU_SRC="/usr/share/kio/servicemenus/musiclib-rate.desktop"
SERVICEMENU_DEST_DIR="${XDG_DATA_HOME}/kio/servicemenus"
SERVICEMENU_DEST="${SERVICEMENU_DEST_DIR}/musiclib-rate.desktop"

if [ ! -f "$SERVICEMENU_SRC" ]; then
    print_info "Skipped: musiclib-rate.desktop not found at $SERVICEMENU_SRC"
    print_info "Install the musiclib package and re-run setup to enable Dolphin rating."
else
    mkdir -p "$SERVICEMENU_DEST_DIR" || {
        print_error "Failed to create KIO servicemenus directory: $SERVICEMENU_DEST_DIR"
    }

    if [ -d "$SERVICEMENU_DEST_DIR" ]; then
        cp "$SERVICEMENU_SRC" "$SERVICEMENU_DEST"
        print_success "Dolphin service menu installed to: $SERVICEMENU_DEST"
        print_info "Right-click any audio file in Dolphin and choose 'Rate Track' to rate it."
        print_info "Note: You may need to restart Dolphin for the menu to appear."
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

if [ "${K3B_SETUP_DONE:-false}" = true ]; then
    echo ""
    print_success "K3b detected — CD ripping panel enabled. Rip profile written to ~/.config/musiclib/k3brc."
    print_info   "Rip output format set to: ${K3B_DETECTED_FORMAT:-mp3}"
    print_info   "Settings can be adjusted in the CD Ripping panel. ~/.config/k3brc is updated on each launch."
else
    echo ""
    print_info "K3b not found — CD ripping panel will be disabled."
    print_info "Install k3b and re-run setup to enable."
fi

if [ -f "$SERVICEMENU_DEST" ]; then
    echo ""
    print_success "Dolphin service menu installed — right-click audio files to rate them."
else
    echo ""
    print_info "Dolphin service menu not installed."
    print_info "Install the musiclib package and re-run setup to enable."
fi

echo ""
echo "Note: If you did not install the GUI version, consider doing that now with musiclib package (KDE)."
echo ""
echo "To customize additional settings, edit:"
echo "  $CONFIG_FILE"
echo ""
echo "For available options, see:"
echo "  /usr/lib/musiclib/config/musiclib.conf"
echo ""

exit 0
