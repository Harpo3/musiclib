#!/bin/bash
#
# musiclib_audacious_setup.sh - Audacious integration setup wizard
#
# Usage: musiclib_audacious_setup.sh
#
# This script provides step-by-step instructions for configuring Audacious
# to automatically call musiclib_audacious.sh when songs change.
#
# Exit codes:
#   0 - Success (instructions provided or verification passed)
#   1 - Audacious not installed
#   2 - System error
#

set -u
set -o pipefail

#############################################
# Setup Paths
#############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSICLIB_ROOT="${MUSICLIB_ROOT:-$(dirname "$SCRIPT_DIR")}"

# Determine hook script location
HOOK_SCRIPT="/usr/lib/musiclib/bin/musiclib_audacious.sh"

if [ ! -f "$HOOK_SCRIPT" ]; then
    # Try development location
    HOOK_SCRIPT="$SCRIPT_DIR/musiclib_audacious.sh"
fi

if [ ! -f "$HOOK_SCRIPT" ]; then
    # Try musiclib-cli wrapper
    if command -v musiclib-cli &>/dev/null; then
        HOOK_SCRIPT="musiclib-cli audacious-hook"
    fi
fi

#############################################
# Helper Functions
#############################################

print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════════"
    echo ""
}

print_step() {
    echo ""
    echo "[$1] $2"
}

print_success() {
    echo "✓ $1"
}

print_error() {
    echo "✗ ERROR: $1" >&2
}

print_info() {
    echo "  $1"
}

#############################################
# Check Audacious Installation
#############################################

print_header "Audacious Integration Setup"

if ! command -v audacious &>/dev/null; then
    print_error "Audacious is not installed"
    echo ""
    echo "Install Audacious using your package manager:"
    echo ""
    echo "  Debian/Ubuntu: sudo apt install audacious"
    echo "  Fedora:        sudo dnf install audacious"
    echo "  Arch:          sudo pacman -S audacious"
    echo ""
    exit 1
fi

AUDACIOUS_PATH="$(command -v audacious)"
print_success "Audacious installed at: $AUDACIOUS_PATH"

#############################################
# Check Hook Script
#############################################

if [ ! -f "$HOOK_SCRIPT" ] && [ "$HOOK_SCRIPT" != "musiclib-cli audacious-hook" ]; then
    print_error "Hook script not found: $HOOK_SCRIPT"
    echo ""
    echo "Please ensure MusicLib is properly installed."
    exit 2
fi

print_success "Hook script: $HOOK_SCRIPT"

#############################################
# Check if Already Configured
#############################################

AUDACIOUS_CONFIG="$HOME/.config/audacious/config"

if [ -f "$AUDACIOUS_CONFIG" ]; then
    # Check if song change plugin is configured
    if grep -q "song_change_plugin" "$AUDACIOUS_CONFIG" 2>/dev/null; then
        CURRENT_CMD=$(grep "^command=" "$AUDACIOUS_CONFIG" | cut -d'=' -f2-)
        
        if [ "$CURRENT_CMD" = "$HOOK_SCRIPT" ]; then
            echo ""
            print_success "Audacious integration is already configured!"
            echo ""
            print_info "Current command: $CURRENT_CMD"
            echo ""
            print_info "To verify it's working, run:"
            print_info "  musiclib-cli audacious-test"
            echo ""
            exit 0
        else
            echo ""
            print_info "Song Change plugin is configured but with different command:"
            print_info "  Current: $CURRENT_CMD"
            print_info "  Expected: $HOOK_SCRIPT"
            echo ""
        fi
    fi
fi

#############################################
# Setup Instructions
#############################################

echo ""
print_info "Follow these steps to enable automatic track monitoring:"
echo ""

print_step "1" "Open Audacious"
print_info "Launch Audacious from your application menu or run: audacious"
echo ""

print_step "2" "Open Settings"
print_info "In Audacious menu: Services → Plugins → General"
echo ""

print_step "3" "Enable Song Change Plugin"
print_info "Find and check: 'Song Change'"
echo ""

print_step "4" "Configure Plugin"
print_info "1. Click 'Settings' icon next to 'Song Change'"
print_info "2. Find this entry under Commands: 'Command to run when starting a new song:'"
print_info "3. Set command to:"
echo ""
echo "     $HOOK_SCRIPT"
echo ""
print_info "4. Click 'OK'"
echo ""

print_step "5" "Apply and Close"
print_info "1. Click 'OK' to close Settings"
print_info "2. Play a track to test"
echo ""

#############################################
# What Happens Next
#############################################

print_header "What Happens After Setup"

echo "Once configured, MusicLib will automatically:"
echo ""
echo "  ✓ Update Conky display when tracks change"
echo "  ✓ Track listening history"
echo "  ✓ Update 'last played' timestamps"
echo "  ✓ Display album art and ratings"
echo "  ✓ Queue scrobble tracking"
echo ""

#############################################
# Verification
#############################################

echo ""
echo "After completing setup, verify it's working:"
echo ""
echo "  musiclib-cli audacious-test"
echo ""

#############################################
# Additional Help
#############################################

print_header "Troubleshooting"

echo "If integration doesn't work:"
echo ""
echo "  1. Check Audacious is running:"
echo "     pgrep audacious"
echo ""
echo "  2. Verify hook script is executable:"
echo "     ls -l $HOOK_SCRIPT"
echo ""
echo "  3. Test hook script manually:"
echo "     $HOOK_SCRIPT"
echo ""
echo "  4. Check logs:"
echo "     tail -f ~/.local/share/musiclib/logs/musiclib.log"
echo ""

exit 0
