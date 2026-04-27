#!/bin/bash
set -e
set -u
set -o pipefail
#
# musiclib_audacious.sh - Compatibility wrapper
#
# Historical entry point for the Audacious Song Change plugin. The actual
# track-change handler logic now lives in musiclib_player_event.sh, which
# works with any MPRIS2 player. This wrapper exists so that existing
# Audacious installations whose Song Change plugin is configured to call
# musiclib_audacious.sh continue to work without reconfiguration.
#
# New installations should point their player's song-change hook directly
# at musiclib_player_event.sh.
#
# This wrapper is scheduled for removal one release after MPRIS migration.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/musiclib_player_event.sh" "$@"
