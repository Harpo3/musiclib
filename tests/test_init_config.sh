#!/bin/bash
# Test suite for bin/musiclib_init_config.sh
#
# Covers:
#   - Unit tests for pure helper functions (read_conf_key, detect_library_format,
#     count_audio_files, backup_k3brc, analyze_library)
#   - Integration test: full wizard run in a sandboxed HOME
#
# Usage: bash tests/test_init_config.sh
# Exit:  0 = all pass, 1 = any fail

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/bin/musiclib_init_config.sh"
PASS=0
FAIL=0

# ── Assertion helpers ─────────────────────────────────────────────────────────

_pass() { echo "  PASS: $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "  FAIL: $1"; FAIL=$(( FAIL + 1 )); }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then _pass "$desc"
    else _fail "$desc (expected='$expected', got='$actual')"; fi
}

assert_num_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" -eq "$actual" ] 2>/dev/null; then _pass "$desc"
    else _fail "$desc (expected=$expected, got=$actual)"; fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [ -f "$path" ]; then _pass "$desc"
    else _fail "$desc (not found: $path)"; fi
}

assert_file_contains() {
    local desc="$1" pattern="$2" file="$3"
    if grep -qF "$pattern" "$file" 2>/dev/null; then _pass "$desc"
    else _fail "$desc (pattern not found: '$pattern' in $file)"; fi
}

assert_file_not_contains() {
    local desc="$1" pattern="$2" file="$3"
    if grep -qF "$pattern" "$file" 2>/dev/null; then _fail "$desc (pattern should not appear: '$pattern')"
    else _pass "$desc"; fi
}

# ── Function loader ───────────────────────────────────────────────────────────
# Source only the helper function definitions — lines before the arg-parsing
# block (while [[ $# -gt 0 ]]).  Strips 'set -' lines to keep the parent
# shell's error handling intact.

FUNC_END=$(grep -n '^while \[\[' "$SCRIPT" | head -1 | cut -d: -f1)
FUNC_END=$(( FUNC_END - 1 ))

load_functions() {
    local tmp; tmp=$(mktemp)
    head -n "$FUNC_END" "$SCRIPT" | grep -v '^set -' > "$tmp"
    # shellcheck source=/dev/null
    source "$tmp"
    rm -f "$tmp"
}

# ── Test: read_conf_key ───────────────────────────────────────────────────────

test_read_conf_key() {
    echo ""
    echo "--- read_conf_key ---"
    local tmp; tmp=$(mktemp)

    cat > "$tmp" << 'EOF'
# Comment line — should be ignored
MUSIC_REPO="/home/user/Music"
NEW_DOWNLOAD_DIR="$HOME/Downloads"
BLANK_VAL=
DEVICE_ID=""
EOF

    assert_eq "reads quoted string value"        "/home/user/Music"   "$(read_conf_key MUSIC_REPO "$tmp")"
    assert_eq "reads value containing \$var ref" '$HOME/Downloads'   "$(read_conf_key NEW_DOWNLOAD_DIR "$tmp")"
    assert_eq "blank value returns empty"        ""                   "$(read_conf_key BLANK_VAL "$tmp")"
    assert_eq "empty-quoted value returns empty" ""                   "$(read_conf_key DEVICE_ID "$tmp")"
    assert_eq "missing key returns empty"        ""                   "$(read_conf_key MISSING "$tmp")"
    assert_eq "missing file returns empty"       ""                   "$(read_conf_key KEY /nonexistent/path)"

    rm -f "$tmp"
}

# ── Test: detect_library_format ───────────────────────────────────────────────

test_detect_library_format() {
    echo ""
    echo "--- detect_library_format ---"
    local d; d=$(mktemp -d)

    assert_eq "empty dir → mp3 fallback" "mp3" "$(detect_library_format "$d")"

    touch "$d/a.mp3" "$d/b.mp3" "$d/c.mp3"
    assert_eq "3 mp3 → mp3"              "mp3" "$(detect_library_format "$d")"

    touch "$d/d.flac" "$d/e.flac" "$d/f.flac" "$d/g.flac"
    assert_eq "4 flac > 3 mp3 → flac"   "flac" "$(detect_library_format "$d")"

    local d2; d2=$(mktemp -d)
    touch "$d2/x.ogg" "$d2/y.ogg" "$d2/z.mp3"
    assert_eq "2 ogg > 1 mp3 → ogg"     "ogg"  "$(detect_library_format "$d2")"

    rm -rf "$d" "$d2"
}

# ── Test: count_audio_files ───────────────────────────────────────────────────

test_count_audio_files() {
    echo ""
    echo "--- count_audio_files ---"
    local d; d=$(mktemp -d)

    assert_num_eq "empty dir → 0" 0 "$(count_audio_files "$d")"

    touch "$d/a.mp3" "$d/b.flac" "$d/c.ogg" "$d/d.m4a"
    assert_num_eq "4 audio files → 4" 4 "$(count_audio_files "$d")"

    touch "$d/cover.jpg" "$d/notes.txt"
    assert_num_eq "non-audio files not counted" 4 "$(count_audio_files "$d")"

    rm -rf "$d"
}

# ── Test: backup_k3brc ────────────────────────────────────────────────────────

test_backup_k3brc() {
    echo ""
    echo "--- backup_k3brc ---"
    local tmp; tmp=$(mktemp -d)
    CONFIG_DIR="$tmp/config/musiclib"
    mkdir -p "$CONFIG_DIR"

    local src="$tmp/k3brc_source"
    echo "dummy k3brc content" > "$src"

    backup_k3brc "$src"
    local today; today=$(date +%m%d%Y)
    local bak1="${CONFIG_DIR}/backups/k3brc_bak_${today}_1"
    assert_file_exists "first backup created with dated name" "$bak1"

    backup_k3brc "$src"
    local bak2="${CONFIG_DIR}/backups/k3brc_bak_${today}_2"
    assert_file_exists "second backup on same day increments to _2" "$bak2"

    rm -rf "$tmp"
}

# ── Test: analyze_library ─────────────────────────────────────────────────────

test_analyze_library() {
    echo ""
    echo "--- analyze_library ---"
    local tmp; tmp=$(mktemp -d)
    DATA_DIR="$tmp/share/musiclib"
    mkdir -p "${DATA_DIR}/data"

    local music; music=$(mktemp -d)

    # Conforming: artist/album/lowercase.ext (depth = 2 slashes)
    mkdir -p "$music/artist_one/album_one"
    touch "$music/artist_one/album_one/track_01.mp3"
    touch "$music/artist_one/album_one/track_02.flac"

    # Non-conforming filename (uppercase letters)
    touch "$music/artist_one/album_one/Track_Bad.mp3"

    # Non-conforming depth (file at root — 0 slashes in relpath)
    touch "$music/toplevel.mp3"

    analyze_library "$music"

    assert_num_eq "total count"           4 "$ANALYSIS_TOTAL"
    assert_num_eq "conforming count"      2 "$ANALYSIS_CONFORMING"
    assert_num_eq "non-conforming count"  2 "$ANALYSIS_NONCONFORMING"
    assert_file_exists    "report file written"            "$ANALYSIS_REPORT_FILE"
    assert_file_contains  "report includes section header" "Non-Conforming Files" "$ANALYSIS_REPORT_FILE"

    rm -rf "$tmp" "$music"
}

# ── Integration test: fresh install config generation ─────────────────────────
# Runs the full wizard script with a sandboxed HOME, stubbed system commands,
# and pre-piped stdin answers.  Optional-tool detection is kept false by
# omitting rsgain, kid3, and k3b from the stub bin.

test_integration_fresh_config() {
    echo ""
    echo "--- integration: fresh install (no optional tools) ---"

    local tmp; tmp=$(mktemp -d)
    local fake_home="$tmp/home"
    local music_dir="$tmp/music"
    local dl_dir="$tmp/downloads"
    mkdir -p "$fake_home" "$music_dir" "$dl_dir"

    # Stub commands that interact with the system or prompt for hardware state
    local stubs="$tmp/stubs"
    mkdir -p "$stubs"
    for cmd in clear systemctl kdeconnect-cli playerctl qdbus6; do
        printf '#!/bin/bash\nexit 0\n' > "$stubs/$cmd"
        chmod +x "$stubs/$cmd"
    done

    # Stdin for the 6 reads made by the wizard on a clean install:
    #   1. Continue with setup?                   → y
    #   2. Enter music repository path            → $music_dir
    #   3. Enter download directory               → $dl_dir
    #   4. Press Enter when ready (KDE Connect)   → (empty)
    #   5. Configure KDE Connect device?          → n
    #   6. Build database now?                    → n
    local answers
    answers=$(printf '%s\n' "y" "$music_dir" "$dl_dir" "" "n" "n")

    PATH="$stubs:$PATH" HOME="$fake_home" \
        bash "$SCRIPT" <<< "$answers" >/dev/null 2>&1 || true

    local conf="${fake_home}/.config/musiclib/musiclib.conf"
    assert_file_exists        "config file created"                          "$conf"
    assert_file_contains      "MUSIC_REPO written"    "MUSIC_REPO="         "$conf"
    assert_file_contains      "NEW_DOWNLOAD_DIR written" "NEW_DOWNLOAD_DIR=" "$conf"
    assert_file_not_contains  "DEVICE_ID absent (not configured)" "DEVICE_ID=" "$conf"

    rm -rf "$tmp"
}

# ── Runner ────────────────────────────────────────────────────────────────────

echo "Loading functions from $(basename "$SCRIPT") (lines 1–$FUNC_END)..."
load_functions

test_read_conf_key
test_detect_library_format
test_count_audio_files
test_backup_k3brc
test_analyze_library
test_integration_fresh_config

echo ""
echo "══════════════════════════════════════════════════"
printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "══════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
