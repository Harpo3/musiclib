#!/bin/bash
#
# musiclib_mpris_listen.sh — MusicLib MPRIS2 song-change listener
#
# Long-running daemon invoked by the musiclib-mpris.service systemd user unit.
# Subscribes to MPRIS2 PropertiesChanged via `playerctl --follow`, filters
# events through the supported_mpris_players allowlist in musiclib.conf, deduplicates
# on mpris:trackid, and invokes musiclib_player_event.sh on each real track change.
#
# Dependencies: playerctl (provides both playerctl and playerctld)
# Lifecycle:    managed by systemd user unit musiclib-mpris.service
# Logs:         journald (stdout/stderr captured by systemd)
#
set -u
set -o pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

UTILS="${SCRIPT_DIR}/musiclib_utils.sh"
if [ ! -f "$UTILS" ]; then
    echo "ERROR: musiclib_utils.sh not found at $UTILS" >&2
    echo "ERROR: Copy musiclib_utils.sh to $(dirname "$UTILS") before starting the service." >&2
    exit 1
fi
source "$UTILS"

HANDLER="${SCRIPT_DIR}/musiclib_player_event.sh"

if ! command -v playerctl >/dev/null 2>&1; then
    echo "ERROR: playerctl not found. Install the 'playerctl' package." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# read_allowlist — read supported_mpris_players from config and print each
# entry on its own line.
# Re-reads config on every call so config changes take effect without a restart.
# ---------------------------------------------------------------------------
read_allowlist() {
    # Re-source config to pick up any runtime changes to supported_mpris_players.
    load_config 2>/dev/null || true

    # supported_mpris_players is a space-separated list of bus name suffixes.
    # Default to the canonical set if the key is absent.
    local players="${supported_mpris_players:-strawberry audacious clementine amarok elisa mpd}"
    # Print one entry per line for easy iteration.
    printf '%s\n' $players
}

# ---------------------------------------------------------------------------
# player_allowed — return 0 if playername is a prefix-match for any allowlist
# entry, 1 otherwise.
# A prefix match means "vlc" in the allowlist also matches "vlc.instance1234".
# ---------------------------------------------------------------------------
player_allowed() {
    local playername="$1"
    while IFS= read -r entry; do
        [[ "$playername" == "${entry}"* ]] && return 0
    done < <(read_allowlist)
    return 1
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

LAST_ID=""
LAST_STATUS=""
change_key=""

# Resolve MUSIC_DISPLAY_DIR from config for playback-status publishing.
# Done once here; the handler re-reads config on each fire so this is safe.
load_config 2>/dev/null || true
DISPLAY_DIR="${MUSIC_DISPLAY_DIR:-}"
if [ -z "$DISPLAY_DIR" ]; then
    # Fallback: mirror the handler's own default derivation.
    DISPLAY_DIR="${HOME}/.local/share/musiclib/data/conky_output"
fi

# write_status FILE VALUE — atomically write VALUE to FILE if the directory
# exists.  Silent no-op if DISPLAY_DIR is not yet created (first run before
# setup wizard).
write_status() {
    local file="$1" value="$2"
    [ -d "$DISPLAY_DIR" ] || return 0
    printf '%s\n' "$value" > "$DISPLAY_DIR/$file"
}

echo "INFO: musiclib_mpris_listen.sh starting (handler: $HANDLER)"

# playerctl --follow without --player= tracks whichever player playerctld
# considers last-active.  The format string uses a tab separator so IFS
# splitting is unambiguous even when metadata fields contain spaces.
#
# Field order: playerName, mpris:trackid, xesam:url, status
# Empty trackid signals stop/blank; we reset LAST_ID and publish Stopped.

playerctl metadata \
    --format $'{{ playerName }}\t{{ mpris:trackid }}\t{{ xesam:url }}\t{{ status }}' \
    --follow \
| while IFS=$'\t' read -r playername trackid url status; do

    # Blank trackid = player stopped or quit; publish Stopped and clear song path.
    if [[ -z "$trackid" ]]; then
        LAST_ID=""
        write_status "playbackstatus.txt" "Stopped"
        write_status "songpath.txt" ""
        continue
    fi

    # Allowlist filter: ignore browser-integration sources and any other
    # non-music MPRIS2 bus (e.g. Plasma Browser Integration).
    if ! player_allowed "$playername"; then
        continue
    fi

    # URL sanity check: when Audacious stops/restarts, playerctl emits garbled
    # rows where the tab fields collapse and the url field contains "Stopped",
    # "Paused", "Playing", or is empty rather than a real URI.  These must be
    # filtered before deduplication so they don't poison LAST_ID and don't
    # trigger spurious handler firings.
    if [[ "$url" != file://* && "$url" != http://* && "$url" != https://* ]]; then
        echo "INFO: skipping garbled event — player=$playername url='$url' status='$status'"
        continue
    fi

    # Always publish the current playback status — pause/resume events share
    # the same trackid so they are deduped below, but the status field still
    # reflects the true state and the GUI polls it independently.
    write_status "playbackstatus.txt" "$status"

    # Deduplication: pause/resume and seek emit PropertiesChanged but the
    # trackid does not change — suppress handler firings for those events.
    #
    # Audacious exposes a static trackid ('/org/mpris/MediaPlayer2/CurrentTrack')
    # for every song, so trackid alone never advances.  Use a compound key of
    # trackid:url so track changes are detected regardless of player behaviour.
    # Players with real per-track ids (Strawberry, VLC) are unaffected — url is
    # redundant for them but the compound key still deduplicates correctly.
    change_key="${trackid}:${url}"
    if [[ "$change_key" == "$LAST_ID" ]]; then
        # Same track — only fire handler if status just became Playing.
        if [[ "$status" == "Playing" && "$LAST_STATUS" != "Playing" ]]; then
            echo "INFO: playback resumed — player=$playername status=$status url=$url"
            LAST_STATUS="$status"
            if [ ! -x "$HANDLER" ]; then
                echo "WARNING: handler not found or not executable: $HANDLER — skipping fire" >&2
                continue
            fi
            "$HANDLER" &
        fi
        LAST_STATUS="$status"
        continue
    fi

    LAST_ID="$change_key"
    LAST_STATUS="$status"

    echo "INFO: track change detected — player=$playername status=$status trackid=$trackid url=$url"

    # Invoke handler in background (fork-and-exit).
    # The handler reads its own metadata via qdbus6/playerctl; we do not
    # forward the metadata fields here so the handler always gets a fresh read.
    if [ ! -x "$HANDLER" ]; then
        echo "WARNING: handler not found or not executable: $HANDLER — skipping fire" >&2
        continue
    fi
    "$HANDLER" &

done

# playerctl --follow exits if it cannot connect to the D-Bus session.
# systemd Restart=on-failure will relaunch the unit automatically.
echo "INFO: playerctl --follow exited; unit will restart." >&2
exit 1
