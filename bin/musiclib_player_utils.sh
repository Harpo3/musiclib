#!/bin/bash
#
# musiclib_player_utils.sh - MPRIS2/player detection functions for musiclib scripts
# Source this file in other scripts: source "$MUSICLIB_ROOT/bin/musiclib_player_utils.sh"
#
set -u
set -o pipefail

#############################################
# MPRIS2 PLAYER HELPERS
#############################################

# Detect the last-active MPRIS2 player via playerctld and validate it against
# the supported_mpris_players allowlist in musiclib.conf.
#
# Sets global MPRIS_BUS to the full bus name
# (e.g. org.mpris.MediaPlayer2.strawberry), or empty string if no allowed
# player is active or playerctld is not running.
#
# Uses playerctld (last-active tracking) rather than enumerating all bus names
# so behaviour matches the listener, which also relies on playerctld.
#
# Usage: detect_active_mpris_bus
# After call: test -n "$MPRIS_BUS" to check success.
detect_active_mpris_bus() {
    MPRIS_BUS=""

    if ! command -v playerctl >/dev/null 2>&1; then
        return 0
    fi

    # Get the name of the last-active player from playerctld's ordering.
    # playerctl without --player= returns the first player in playerctld's
    # priority list (i.e. the most recently active one).
    local active_player
    active_player=$(playerctl metadata --format '{{ playerName }}' 2>/dev/null || echo "")

    [ -z "$active_player" ] && return 0

    # Allowlist check (prefix match, same logic as the listener).
    local allowed=false
    local players="${supported_mpris_players:-strawberry audacious clementine amarok elisa mpd}"
    local entry
    for entry in $players; do
        if [[ "$active_player" == "${entry}"* ]]; then
            allowed=true
            break
        fi
    done

    $allowed || return 0

    # Use the playerctld proxy bus for all subsequent qdbus6 calls.
    # org.mpris.MediaPlayer2.playerctld transparently proxies the active player,
    # so metadata reads always reflect whichever player playerctld is tracking —
    # no need to construct org.mpris.MediaPlayer2.<playername> individually.
    MPRIS_BUS="org.mpris.MediaPlayer2.playerctld"
}

# Read a single Metadata field from the active MPRIS2 player.
# Requires detect_active_mpris_bus to have been called first (MPRIS_BUS set).
#
# Usage: mpris_metadata_field <key>
# Example keys: xesam:url  xesam:title  xesam:artist  mpris:length  mpris:trackid
# Prints the field value to stdout; prints nothing if not found.
mpris_metadata_field() {
    local key="$1"
    [ -z "${MPRIS_BUS:-}" ] && return 1
    qdbus6 "$MPRIS_BUS" /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        org.mpris.MediaPlayer2.Player Metadata 2>/dev/null \
        | awk -F': ' -v k="$key" '$1==k {$1=""; sub(/^ /,""); print; exit}'
}

# Read PlaybackStatus from the active MPRIS2 player.
# Requires MPRIS_BUS to be set.
# Prints one of: Playing  Paused  Stopped  (or empty on error).
# qdbus6 always appends a trailing newline; strip all whitespace so callers
# can compare the result directly with [ "$status" = "Playing" ].
mpris_playback_status() {
    [ -z "${MPRIS_BUS:-}" ] && return 1
    qdbus6 "$MPRIS_BUS" /org/mpris/MediaPlayer2 \
        org.freedesktop.DBus.Properties.Get \
        org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null \
        | tr -d '[:space:]'
}

# Decode a file:// URI to a plain filesystem path.
# Non-file:// URIs (streams, Spotify, etc.) produce an empty string.
# Usage: file_uri_to_path <uri>
file_uri_to_path() {
    local uri="$1"
    [ -z "$uri" ] && { echo ""; return 0; }
    # Only handle file:// URIs; everything else is not a local file.
    [[ "$uri" == file://* ]] || { echo ""; return 0; }
    local path="${uri#file://}"
    # Percent-decode
    printf '%b\n' "${path//%/\\x}"
}

# Convenience wrapper: detect active player, read xesam:url, decode to path.
# Prints the filesystem path of the currently-playing track, or empty string
# if no allowed MPRIS2 player is active or track is non-local.
# Sets (and exports) MPRIS_BUS as a side-effect.
# Usage: FILEPATH=$(get_current_player_filepath)
get_current_player_filepath() {
    detect_active_mpris_bus
    [ -z "${MPRIS_BUS:-}" ] && { echo ""; return 0; }
    local url
    url=$(mpris_metadata_field "xesam:url" || echo "")
    file_uri_to_path "$url"
}
