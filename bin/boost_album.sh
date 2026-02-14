#!/usr/bin/env bash
set -u
set -o pipefail

# Usage: boost_album.sh [/path/to/album_dir] [12] higher number for quieter, lower for louder
# Meaning: target loudness = -12 LUFS
# Usually 12 or 13 will boost the level you want

export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS  # Just in case it's set

command -v kid3-cli >/dev/null 2>&1 || { echo "kid3-cli not found"; exit 1; }
command -v rsgain   >/dev/null 2>&1 || { echo "rsgain not found";   exit 1; }

dir="${1:?Usage: $0 /path/to/album_dir loudness}"
lvl="${2:?Usage: $0 /path/to/album_dir loudness}"

# 1) Remove existing ReplayGain-related fields via kid3-cli
kid3-cli -c "set REPLAYGAIN_TRACK_GAIN ''" \
         -c "set REPLAYGAIN_TRACK_PEAK ''" \
         -c "set REPLAYGAIN_ALBUM_GAIN ''" \
         -c "set REPLAYGAIN_ALBUM_PEAK ''" \
         "$dir"/*.mp3

echo "Removed existing ReplayGain settings from tags."
echo "Boosting $dir to target loudness -${lvl} LUFS..."

# 2) Re-scan and tag with rsgain at the requested loudness
rsgain custom -a -s i -l "-${lvl}" -c a -t -S -m 8 \
  $(find "$dir" -type f -name '*.mp3')
