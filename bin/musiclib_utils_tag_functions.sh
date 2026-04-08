#!/bin/bash
# ============================================================================
# TAG REPAIR AND NORMALIZATION FUNCTIONS
# ============================================================================
# These functions handle tag corruption repair and new track tag normalization
# Added in Phase 00_03

# Tag schema arrays — populated once by load_tag_schema() from tag_schema.conf.
#
#   SCHEMA_FRAMES_ALLOWED  ID3v2 frame codes that are permitted (both tiers).
#                          Non-TXXX frames not listed here are dropped.
#   SCHEMA_TXXX_ALLOWED    TXXX descriptions that are permitted (both tiers).
#                          TXXX frames whose description is not listed here
#                          are dropped.
#   SCHEMA_TXXX_DB         TXXX descriptions from the [db_written] tier only.
#                          Used to identify DB-authoritative fields so the
#                          pre-extraction loop (which reads file values) can
#                          skip them — those fields are written from the DB.
#   SCHEMA_TXXX_ALL        Union of SCHEMA_TXXX_ALLOWED + SCHEMA_TXXX_DB.
#                          Used by sync_external_tool_config() to build the
#                          kid3 CustomFrames list (all named TXXX fields).
declare -A SCHEMA_FRAMES_ALLOWED
declare -A SCHEMA_TXXX_ALLOWED
declare -A SCHEMA_TXXX_DB
declare -A SCHEMA_TXXX_ALL
FRAMES_LOADED=false
# Guard: kid3 external config sync runs at most once per process
KID3_CONFIG_SYNCED=false

# Static lookup: kid3 unified field names → ID3v2 frame codes.
# Only the ~15 names that actually appear in tag_schema.conf are listed.
# load_tag_schema() uses this table to translate no-prefix schema entries.
# "Album Artist" uses the exact multi-word key from the schema (with space).
declare -A UNIFIED_TO_FRAME=(
    ["Title"]="TIT2"
    ["Artist"]="TPE1"
    ["Album"]="TALB"
    ["Album Artist"]="TPE2"
    ["Genre"]="TCON"
    ["Rating"]="POPM"
    ["Work"]="TIT1"
    ["Track Number"]="TRCK"
    ["Disc Number"]="TPOS"
    ["Date"]="TYER"
    ["BPM"]="TBPM"
    ["Comment"]="COMM"
    ["Lyrics"]="USLT"
    ["Picture"]="APIC"
    ["ISRC"]="TSRC"
)

#############################################
# Load tag schema from tag_schema.conf
# Populates SCHEMA_FRAMES_ALLOWED, SCHEMA_TXXX_ALLOWED,
# SCHEMA_TXXX_DB, and SCHEMA_TXXX_ALL from the config file.
# Usage: load_tag_schema
# Returns: 0=success, 1=fallback to built-in defaults
#############################################
load_tag_schema() {
    # Only load once per process
    [ "$FRAMES_LOADED" = true ] && return 0

    local config_dir
    if [ -n "${MUSICLIB_ROOT:-}" ]; then
        config_dir="${MUSICLIB_ROOT}/config"
    else
        # Use XDG-aware detection from musiclib_utils.sh
        config_dir="$(get_config_dir)"
    fi

    local schema_file="${config_dir}/tag_schema.conf"
    local system_schema="/usr/lib/musiclib/config/tag_schema.conf"
    local load_result=0

    # Priority: project config > system default > built-in defaults
    if [ -f "$schema_file" ]; then
        log_message "Loading tag schema from: $schema_file"
    elif [ -f "$system_schema" ]; then
        schema_file="$system_schema"
        log_message "Loading tag schema from: $system_schema"
    else
        log_message "No tag_schema.conf found, using built-in defaults"
        load_default_excludes
        load_result=1
        sync_external_tool_config || true
        FRAMES_LOADED=true
        return $load_result
    fi

    # Parse tag_schema.conf section by section.
    # Tracks which section we are in ([db_written] or [file_preserved]).
    local current_section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip pure comment lines and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Strip inline comments (everything from the first unquoted '#' onward)
        local stripped="${line%%#*}"
        # Strip trailing whitespace
        stripped="${stripped%"${stripped##*[! ]}"}"
        [ -z "$stripped" ] && continue

        # Detect section headers: [db_written] or [file_preserved]
        if [[ "$stripped" =~ ^\[([a-z_]+)\] ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # For [db_written] entries the format is "entry = db_column".
        # The "= db_column" part is informational only — strip it.
        local entry="${stripped%%=*}"
        # Strip trailing whitespace from entry name
        entry="${entry%"${entry##*[! ]}"}"
        [ -z "$entry" ] && continue

        if [[ "$entry" == !* ]]; then
            # "!" prefix: either a raw 4-char ID3v2 frame code or a TXXX description
            local rest="${entry#!}"
            if [[ "$rest" =~ ^[A-Z][A-Z0-9]{3}$ ]]; then
                # Raw frame code (e.g. !RVA2) — matches [A-Z][A-Z0-9]{3}
                SCHEMA_FRAMES_ALLOWED["$rest"]=1
            else
                # TXXX description (e.g. !Songs-DB_Custom1, !CATALOGNUMBER)
                SCHEMA_TXXX_ALLOWED["$rest"]=1
                if [ "$current_section" = "db_written" ]; then
                    SCHEMA_TXXX_DB["$rest"]=1
                fi
            fi
        else
            # No prefix: kid3 unified name — look up in UNIFIED_TO_FRAME table
            local frame_code="${UNIFIED_TO_FRAME[$entry]:-}"
            if [ -n "$frame_code" ]; then
                SCHEMA_FRAMES_ALLOWED["$frame_code"]=1
            else
                log_message "  Warning: unified name '$entry' not found in UNIFIED_TO_FRAME — skipped"
            fi
        fi
    done < "$schema_file"

    # Build SCHEMA_TXXX_ALL as the union of SCHEMA_TXXX_ALLOWED and SCHEMA_TXXX_DB.
    # Since SCHEMA_TXXX_DB is a subset of SCHEMA_TXXX_ALLOWED, iterating both is
    # redundant, but explicit iteration makes the intent clear and guards against
    # future cases where entries might differ.
    for desc in "${!SCHEMA_TXXX_ALLOWED[@]}"; do
        SCHEMA_TXXX_ALL["$desc"]=1
    done
    for desc in "${!SCHEMA_TXXX_DB[@]}"; do
        SCHEMA_TXXX_ALL["$desc"]=1
    done

    log_message "Loaded ${#SCHEMA_FRAMES_ALLOWED[@]} allowed frame codes, ${#SCHEMA_TXXX_ALLOWED[@]} allowed TXXX descriptions (${#SCHEMA_TXXX_DB[@]} db_written)"

    # Sync kid3 config on first script run (hash-guarded; cheap if nothing changed)
    sync_external_tool_config || true

    FRAMES_LOADED=true
    return $load_result
}

#############################################
# Populate schema arrays with built-in defaults (fallback)
# Called by load_tag_schema() when tag_schema.conf is not found.
# Mirrors the content of config/tag_schema.conf so behaviour is
# identical whether the file is present or not.
# Usage: load_default_excludes
# Returns: Always 0
#############################################
load_default_excludes() {
    # --- Allowed ID3v2 frame codes (mirrors [db_written] + [file_preserved]) ---
    # [db_written] standard frames
    local frame_codes=(
        "TIT2"   # Title
        "TPE1"   # Artist
        "TALB"   # Album
        "TPE2"   # Album Artist
        "TCON"   # Genre
        "POPM"   # Rating
        "TIT1"   # Work / GroupDesc
        # [file_preserved] standard frames
        "TRCK"   # Track Number
        "TPOS"   # Disc Number
        "TYER"   # Date (year)
        "TBPM"   # BPM
        "COMM"   # Comment
        "USLT"   # Lyrics
        "APIC"   # Picture (album art)
        "TSRC"   # ISRC
        # [file_preserved] raw frame code entries
        "RVA2"   # Relative Volume Adjustment v2 (from !RVA2)
    )
    for code in "${frame_codes[@]}"; do
        SCHEMA_FRAMES_ALLOWED["$code"]=1
    done

    # --- Allowed TXXX descriptions from [db_written] ---
    local txxx_db_descs=(
        "Songs-DB_Custom1"   # LastTimePlayed (DB column: lastplayed)
        "Songs-DB_Custom2"   # Custom2        (DB column: custom2)
    )
    for desc in "${txxx_db_descs[@]}"; do
        SCHEMA_TXXX_ALLOWED["$desc"]=1
        SCHEMA_TXXX_DB["$desc"]=1
        SCHEMA_TXXX_ALL["$desc"]=1
    done

    # --- Allowed TXXX descriptions from [file_preserved] ---
    local txxx_file_descs=(
        "CATALOGNUMBER"
        "REPLAYGAIN_TRACK_GAIN"
        "REPLAYGAIN_TRACK_PEAK"
        "REPLAYGAIN_ALBUM_GAIN"
        "REPLAYGAIN_ALBUM_PEAK"
        "MusicMatch_Mood"
    )
    for desc in "${txxx_file_descs[@]}"; do
        SCHEMA_TXXX_ALLOWED["$desc"]=1
        SCHEMA_TXXX_ALL["$desc"]=1
    done

    log_message "Loaded ${#SCHEMA_FRAMES_ALLOWED[@]} allowed frame codes (built-in defaults)"
}

#############################################
# Propagate musiclib tag standards to kid3's config file.
# Applies POPM star-rating mapping, custom frame names, and UTF-8 encoding.
# Uses the mtime of ~/.config/musiclib/musiclib.conf to skip re-application
# when the local config has not changed (lazy-load pattern, same as FRAMES_LOADED).
# Other change signals can be added here later using the same mtime pattern.
# Stamp file: ~/.local/share/musiclib/kid3_config.hash
# Usage: sync_external_tool_config
# Returns: 0=success or skipped, 1=kid3-cli unavailable
#############################################
sync_external_tool_config() {
    # Run at most once per process
    [ "$KID3_CONFIG_SYNCED" = true ] && return 0

    # Require kid3-cli; skip silently if not installed
    if ! command -v kid3-cli &>/dev/null; then
        KID3_CONFIG_SYNCED=true
        return 1
    fi

    # Use mtime of local config as the change signal — cheaper than hashing
    # values and catches any edit to the file, not just POPM_STAR lines.
    local user_conf="${XDG_CONFIG_HOME:-$HOME/.config}/musiclib/musiclib.conf"
    local current_mtime=""
    [ -f "$user_conf" ] && current_mtime=$(stat -c %Y "$user_conf" 2>/dev/null)

    local hash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/musiclib"
    local hash_file="${hash_dir}/kid3_config.hash"
    local stored_mtime=""
    [ -f "$hash_file" ] && stored_mtime=$(cat "$hash_file" 2>/dev/null)

    if [ -n "$current_mtime" ] && [ "$current_mtime" = "$stored_mtime" ]; then
        log_message "sync_external_tool_config: musiclib.conf unchanged (mtime match), skipping"
        KID3_CONFIG_SYNCED=true
        return 0
    fi

    log_message "sync_external_tool_config: applying kid3 config (conf changed or first run)"

    # Re-source the XDG user config to guarantee local POPM_STAR overrides are in scope.
    # load_config() (musiclib_utils.sh) resolves "user_config" to
    # ~/musiclib/config/musiclib.conf when MUSICLIB_ROOT is set, which mirrors
    # system defaults and never reaches ~/.config/musiclib/musiclib.conf.
    # Sourcing here makes local customizations visible regardless of which config
    # path load_config() took.
    # shellcheck source=/dev/null
    [ -f "$user_conf" ] && source "$user_conf"

    # Ensure kid3-cli writes to the shared musiclib config file, not its own default.
    # Must be exported so the kid3-cli subprocess sees it regardless of calling environment.
    export KID3_CONFIG_FILE="${KID3_CONFIG_FILE:-$HOME/.config/kid3rc}"

    # Use POPM_STAR vars from sourced config; fall back to system defaults if unset
    local p1="${POPM_STAR1:-1}"
    local p2="${POPM_STAR2:-64}"
    local p3="${POPM_STAR3:-128}"
    local p4="${POPM_STAR4:-196}"
    local p5="${POPM_STAR5:-255}"

    # Build the comma-separated CustomFrames list from SCHEMA_TXXX_ALL,
    # excluding REPLAYGAIN* entries (those are managed by ReplayGain tools,
    # not the kid3 custom frame UI).  Sorted for stable output.
    local custom_frames_list
    custom_frames_list=$(
        for desc in "${!SCHEMA_TXXX_ALL[@]}"; do
            [[ "$desc" == REPLAYGAIN* ]] && continue
            printf '%s\n' "$desc"
        done | sort | paste -sd ', '
    )

    local kid3rc="${KID3_CONFIG_FILE:-$HOME/.config/kid3rc}"

    # Bootstrap kid3rc if it does not yet exist.
    # kid3-cli config writes create the file from kid3's internal defaults.
    # However, any kid3-cli config write also strips StarRatingMapping because
    # kid3-cli rewrites the whole file from its internal state and cannot write
    # that key.  We therefore only call kid3-cli here — it is skipped on all
    # subsequent runs once the Python patch below takes over.
    if [ ! -f "$kid3rc" ]; then
        kid3-cli -c "config Tag.customFrames Songs-DB_Custom1 Songs-DB_Custom2 CATALOGNUMBER" &>/dev/null
        kid3-cli -c "config Tag.textEncoding TE_UTF8" &>/dev/null
    fi

    # Patch kid3rc directly for all three settings — avoids any kid3-cli config
    # write that would strip StarRatingMapping.
    #
    # CustomFrames and TextEncoding are patched within [Tags] only.  TextEncoding
    # also appears in [Files] (as "System"); a section-aware replace prevents
    # that entry from being overwritten.  TE_UTF8 maps to the integer value 2.
    #
    # StarRatingMapping: update the POPM entry in-place, or inject a POPM-only
    # entry after [Tags] if the line is absent (e.g. after a bootstrap write).
    # kid3 appends defaults for the other entries (WMP, Traktor, etc.) when it
    # next writes the file, so the POPM-only seed is not permanent.
    if [ -f "$kid3rc" ]; then
        python3 - "$kid3rc" "$p1" "$p2" "$p3" "$p4" "$p5" "$custom_frames_list" &>/dev/null << 'PYEOF' || true
import re, sys

rc, p1, p2, p3, p4, p5, custom_frames = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]

with open(rc) as f:
    content = f.read()

def patch_in_section(text, section, key, new_val):
    """Replace key=value only within the named INI section.
    Safe when the same key exists in multiple sections (e.g. TextEncoding
    in both [Files] and [Tags]).  Uses a lookahead so the next section
    header is not consumed by the match."""
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

content = patch_in_section(content, 'Tags', 'CustomFrames', custom_frames)
content = patch_in_section(content, 'Tags', 'TextEncoding', '2')

# Within-entry separator in Qt QStringList INI format is \\, (two literal
# backslashes + comma).  The regex captures each \\, group so it is
# reproduced exactly.  Only the POPM (first) entry is changed; all others
# (WMP, Traktor, IRTD, etc.) are preserved.
srm_pat = r'(StarRatingMapping=POPM\\\\,)\d+(\\\\,)\d+(\\\\,)\d+(\\\\,)\d+(\\\\,)\d+'
srm_repl = r'\g<1>' + p1 + r'\g<2>' + p2 + r'\g<3>' + p3 + r'\g<4>' + p4 + r'\g<5>' + p5
new_content, n = re.subn(srm_pat, srm_repl, content)
if n:
    content = new_content
else:
    # StarRatingMapping absent (e.g. freshly bootstrapped by kid3-cli).
    # Inject a POPM-only entry immediately after [Tags].  Kid3 appends
    # defaults for other entries the next time it writes the file.
    new_line = 'StarRatingMapping=POPM\\\\,' + p1 + '\\\\,' + p2 + '\\\\,' + p3 + '\\\\,' + p4 + '\\\\,' + p5 + '\n'
    content = re.sub(r'(?m)(^\[Tags\]\n)', lambda m: m.group(0) + new_line, content, count=1)

with open(rc, 'w') as f:
    f.write(content)
sys.exit(0)
PYEOF
    fi

    # Persist mtime so we only re-apply when local config changes
    mkdir -p "$hash_dir"
    printf '%s\n' "$current_mtime" > "$hash_file"

    KID3_CONFIG_SYNCED=true
    log_message "sync_external_tool_config: kid3 config applied and mtime stored"
    return 0
}

#############################################
# Strip characters from a tag value that break kid3-cli command-string quoting
# or are otherwise unwanted in the DSV database.
# - Single quotes (') break kid3-cli's quoted argument parsing
#   (e.g. "set Title 'Rollin''" is mis-parsed, leaving the title blank)
# - Commas (,) cause inconsistent display in the library UI
# Unicode is preserved: kid3 is configured for UTF-8 (Tag.textEncoding TE_UTF8),
# so iconv transliteration is unnecessary and would cause data loss.
# Usage: sanitize_for_kid3 "value"
# Returns: sanitized value safe for kid3-cli commands
#############################################
sanitize_for_kid3() {
    printf '%s' "$1" | tr -d "',"
}

#############################################
# Check if a frame is allowed by the tag schema
# Usage: is_frame_allowed <frame_code> [description]
# Returns: 0=allowed, 1=not in schema (drop)
#
# Logic:
#   TXXX frames  — allowed only if description is in SCHEMA_TXXX_ALLOWED
#                  or SCHEMA_TXXX_DB; all others are dropped.
#   Non-TXXX     — allowed only if frame code is in SCHEMA_FRAMES_ALLOWED;
#                  all others are dropped.
#############################################
is_frame_allowed() {
    local frame="$1"
    local description="${2:-}"

    # Ensure schema is loaded
    load_tag_schema 2>/dev/null || true

    # TXXX (user-defined text frames): schema-driven allowlist only
    if [[ "$frame" == "TXXX" ]]; then
        if [ -n "${SCHEMA_TXXX_ALLOWED[$description]:-}" ] || \
           [ -n "${SCHEMA_TXXX_DB[$description]:-}" ]; then
            return 0
        fi
        return 1
    fi

    # Non-TXXX frames: schema-driven allowlist only
    if [ -n "${SCHEMA_FRAMES_ALLOWED[$frame]:-}" ]; then
        return 0
    fi
    return 1
}

#############################################
# Rebuild corrupted tags from backup + database
# Usage: rebuild_tag <filepath>
# Returns: 0=success, 1=extraction failed, 2=removal failed, 3=rebuild failed
#
# This function repairs corrupted tags on tracks ALREADY IN THE DATABASE.
# It extracts all metadata, strips corrupted tags, and rebuilds with:
#   - Database values for core fields (Artist, Album, Title, Rating, etc.)
#   - Preserved values for non-DB fields (ReplayGain, Comment, Year, etc.)
#   - Only frames allowed by the tag schema (SCHEMA_FRAMES_ALLOWED / SCHEMA_TXXX_ALLOWED)
#############################################
rebuild_tag() {
    local filepath="$1"

    if [ ! -f "$filepath" ]; then
        log_message "ERROR: Cannot rebuild tags - file not found: $filepath"
        return 1
    fi

    log_message "Attempting tag rebuild for: $(basename "$filepath")"

    # Create temporary workspace
    local temp_dir=$(mktemp -d)
    local metadata_json="$temp_dir/metadata.json"
    local album_art="$temp_dir/cover.jpg"

    # Cleanup function - guard against unbound temp_dir
    cleanup_rebuild() {
        [ -n "${temp_dir:-}" ] && rm -rf "$temp_dir" 2>/dev/null || true
    }
    trap cleanup_rebuild RETURN

    #########################################
    # STAGE 1: Extract All Metadata
    #########################################

    log_message "  Stage 1: Extracting metadata..."

    # Extract full metadata as JSON using exiftool
    if ! exiftool -json "$filepath" > "$metadata_json" 2>/dev/null; then
        log_message "  ERROR: exiftool metadata extraction failed"
        return 1
    fi

    # Verify JSON is valid and not empty
    if [ ! -s "$metadata_json" ]; then
        log_message "  ERROR: Extracted metadata is empty"
        return 1
    fi

    # Extract album art (binary data)
    exiftool -Picture -b "$filepath" > "$album_art" 2>/dev/null || true

    # Check if album art was extracted
    local has_album_art=false
    if [ -f "$album_art" ] && [ -s "$album_art" ]; then
        # Verify it's actually an image
        if file "$album_art" 2>/dev/null | grep -qi "image"; then
            has_album_art=true
            log_message "  âœ” Album art extracted ($(stat -c%s "$album_art") bytes)"
        fi
    fi

    # Extract lyrics (USLT) to a temp file before tags are stripped.
    # exiftool names USLT frames as "Lyrics-{lang}" in JSON (e.g. Lyrics-xxx,
    # Lyrics-eng). The plain "-Lyrics -s3" flag does not match these names and
    # produces no output. Use jq on the already-extracted metadata JSON to find
    # whatever Lyrics-* key is present, then write its value to a file.
    # Must run before Stage 3 strip.
    local lyrics_file="$temp_dir/lyrics.txt"
    local has_lyrics=false
    if command -v jq >/dev/null 2>&1; then
        local lyrics_key
        lyrics_key=$(jq -r '[.[0] | keys[] | select(test("^Lyrics"))] | first // empty' \
            "$metadata_json" 2>/dev/null)
        if [ -n "$lyrics_key" ]; then
            jq -r ".[0][\"$lyrics_key\"]" "$metadata_json" > "$lyrics_file" 2>/dev/null || true
        fi
    fi
    if [ -s "$lyrics_file" ]; then
        has_lyrics=true
        log_message "  Lyrics extracted for preservation"
    fi

    log_message "  âœ” Metadata extraction complete"

    # Pre-read file-preserved TXXX frames via kid3-cli BEFORE tags are stripped.
    # exiftool does not reliably report all TXXX frames (e.g. Songs-DB_Custom1
    # is invisible to exiftool but readable by kid3-cli — see Bug 6).
    # We iterate SCHEMA_TXXX_ALLOWED entries (from tag_schema.conf [file_preserved]
    # and [db_written]) and capture any values present in the file now; they are
    # written back at the end of Stage 4 after the full rebuild.
    # DB-authoritative entries (SCHEMA_TXXX_DB: Songs-DB_Custom1, Songs-DB_Custom2)
    # are skipped — their values come from the database, not the file, and must
    # not be overwritten by a potentially stale file value at the write-back step.
    load_tag_schema 2>/dev/null || true
    declare -A txxx_preserved_values
    for desc in "${!SCHEMA_TXXX_ALLOWED[@]}"; do
        # Skip DB-authoritative TXXX entries
        [ -n "${SCHEMA_TXXX_DB[$desc]:-}" ] && continue
        local raw_val
        raw_val=$($KID3_CMD -c "get '$desc'" "$filepath" 2>/dev/null | tail -n1)
        [ -n "$raw_val" ] && txxx_preserved_values["$desc"]="$raw_val"
    done
    if [ "${#txxx_preserved_values[@]}" -gt 0 ]; then
        log_message "  Pre-read ${#txxx_preserved_values[@]} preserved TXXX frames"
    fi

    #########################################
    # STAGE 2: Query Database for Authoritative Values
    #########################################

    log_message "  Stage 2: Querying database..."

    # Initialize database values as empty
    local db_artist="" db_album="" db_albumartist="" db_title="" db_genre=""
    local db_rating="" db_groupdesc="" db_lastplayed="" db_custom2=""

    # Query database if MUSICDB is set and file exists
    if [ -n "${MUSICDB:-}" ] && [ -f "$MUSICDB" ]; then
        # Find the track in database
        local db_line=$(grep -F "$filepath" "$MUSICDB" 2>/dev/null | head -n1)

        if [ -n "$db_line" ]; then
            # Parse database fields (ID^Artist^IDAlbum^Album^AlbumArtist^Title^Path^Genre^Length^Rating^Custom2^GroupDesc^LastPlayed^^)
            IFS='^' read -r _ db_artist _ db_album db_albumartist db_title _ db_genre _ db_rating db_custom2 db_groupdesc db_lastplayed _ <<< "$db_line"

            log_message "  âœ“ Found in database (Artist: $db_artist)"
        else
            log_message "  âš  Track not found in database - will use extracted values"
        fi
    else
        log_message "  âš  Database not available - will use extracted values"
    fi

    #########################################
    # STAGE 3: Remove All Existing Tags
    #########################################

    log_message "  Stage 3: Removing corrupted tags..."

    # Remove ID3v1, ID3v2, APE — batched into one kid3-cli invocation
    $KID3_CMD -c "remove 1" -c "remove 2" -c "remove 3" "$filepath" 2>/dev/null || true

    # Verify removal
    local tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^\[ID3" | wc -l)

    if [ "$tags_remaining" -gt 0 ]; then
        # Try harder with id3v2 tool if available
        if command -v id3v2 >/dev/null 2>&1; then
            log_message "  âš  Some tags remain, trying id3v2 tool..."
            id3v2 --delete-all "$filepath" 2>/dev/null || true
            tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^\[ID3" | wc -l)
        fi

        # Last resort: exiftool can strip metadata even from corrupted files
        if [ "$tags_remaining" -gt 0 ]; then
            log_message "  âš  Tags still remain, trying exiftool strip..."
            exiftool -all= -overwrite_original "$filepath" 2>/dev/null || true
            tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^\[ID3" | wc -l)
        fi

        if [ "$tags_remaining" -gt 0 ]; then
            log_message "  ERROR: Cannot remove all tags ($tags_remaining remain)"
            return 2
        fi
    fi

    log_message "  âœ“ All tags removed"

    #########################################
    # STAGE 4: Rebuild Tags (Hybrid + Filtered)
    #########################################

    log_message "  Stage 4: Rebuilding tags with frame filtering..."


    # Helper function to get value from extracted metadata
    get_extracted_value() {
        local tag_name="$1"
        # Query the metadata JSON using exiftool on the saved JSON
        # This is safer than parsing JSON in bash
        local value=""

        # Use exiftool to extract specific field from JSON
        # Fall back to grep if exiftool JSON parsing isn't available
        if command -v jq >/dev/null 2>&1; then
            value=$(jq -r ".[0].\"$tag_name\" // empty" "$metadata_json" 2>/dev/null)
        else
            # Fallback: grep from JSON (crude but works)
            value=$(grep "\"$tag_name\"" "$metadata_json" 2>/dev/null | head -1 | sed 's/.*: "\(.*\)".*/\1/')
        fi

        echo "$value"
    }

    # Temporal/Extended Metadata (preserve from extracted, check if allowed)
    local year=$(get_extracted_value "Year")
    local comment
    comment=$(get_extracted_value "Comment")
    # COMM frames with a content descriptor are stored as "Comment-{lang}" in
    # exiftool JSON (e.g. "Comment-xxx"). The plain "Comment" key is absent,
    # causing get_extracted_value to return empty. Fall back to the first
    # Comment-* key found, then strip the "(descriptor) " prefix that exiftool
    # prepends to the value when the content descriptor is non-empty.
    if [ -z "$comment" ] && command -v jq >/dev/null 2>&1; then
        comment=$(jq -r \
            '[.[0] | to_entries[] | select(.key | test("^Comment")) | .value] | first // empty' \
            "$metadata_json" 2>/dev/null)
        # Strip leading "(descriptor) " prefix e.g. "(Songs-DB_Custom2) Aerosmith" -> "Aerosmith"
        comment="${comment#\(*\) }"
    fi
    comment="$(sanitize_for_kid3 "$comment")"
    local track_num=$(get_extracted_value "Track")
    [ -n "$track_num" ] && track_num=$(printf "%02d" "$((10#${track_num%%/*}))")
    # Fallback: if no track number tag, try to extract it from the filename.
    # Library files are named NN_-_artist_-_title.mp3 where NN is the track number.
    # If neither source has a track number, default to "00" so the tag and
    # filename always carry a track number and maintain consistent format.
    # Note: 10# forces bash to parse the number as base-10, preventing printf
    # from misinterpreting leading-zero values (e.g. "08") as invalid octal.
    if [ -z "$track_num" ]; then
        local fname_noext
        fname_noext=$(basename "$filepath" .mp3)
        if [[ "$fname_noext" =~ ^([0-9]+)_ ]]; then
            track_num=$(printf "%02d" "$((10#${BASH_REMATCH[1]}))")
        else
            track_num="00"
        fi
    fi
    local disc_num=$(get_extracted_value "DiscNumber")
    local bpm=$(get_extracted_value "BPM")

    # Core Identification Tags (DB authoritative, filter allowed)
    local artist="${db_artist:-$(get_extracted_value "Artist")}"
    local album="${db_album:-$(get_extracted_value "Album")}"
    local albumartist="${db_albumartist:-$(get_extracted_value "AlbumArtist")}"
    local title="${db_title:-$(get_extracted_value "Title")}"
    local genre="${db_genre:-$(get_extracted_value "Genre")}"

    # Sanitize text tag values: single quotes break kid3-cli command quoting
    artist="$(sanitize_for_kid3 "$artist")"
    album="$(sanitize_for_kid3 "$album")"
    albumartist="$(sanitize_for_kid3 "$albumartist")"
    title="$(sanitize_for_kid3 "$title")"
    genre="$(sanitize_for_kid3 "$genre")"

    # Accumulate all text "set" commands into an array; flush with a single
    # kid3-cli invocation at the end of Stage 4.  Batching eliminates the per-
    # command process-spawn overhead (Qt + taglib load) for every write.
    # Commands that cannot be batched (remove, to23, picture) remain separate.
    local -a kid3_set_cmds=()

    # Always write core tags (these are never excluded)
    [ -n "$artist" ]       && kid3_set_cmds+=(-c "set Artist '$artist'")
    [ -n "$album" ]        && kid3_set_cmds+=(-c "set Album '$album'")
    [ -n "$albumartist" ]  && kid3_set_cmds+=(-c "set AlbumArtist '$albumartist'")
    [ -n "$title" ]        && kid3_set_cmds+=(-c "set Title '$title'")
    [ -n "$genre" ]        && kid3_set_cmds+=(-c "set Genre '$genre'")

    # Rating Tags (DB authoritative)
    [ -n "$db_rating" ]    && kid3_set_cmds+=(-c "set POPM $db_rating")
    [ -n "$db_groupdesc" ] && kid3_set_cmds+=(-c "set Work $db_groupdesc")

    # Play Tracking Tags (DB authoritative - always allowed)
    # IMPORTANT: Written after Comment to prevent kid3-cli frame confusion
    [ -n "$db_lastplayed" ] && kid3_set_cmds+=(-c "set Songs-DB_Custom1 '$db_lastplayed'")
    [ -n "$db_custom2" ]    && kid3_set_cmds+=(-c "set Songs-DB_Custom2 '$db_custom2'")
    if is_frame_allowed "COMM" && [ -n "$comment" ]; then
        kid3_set_cmds+=(-c "set Comment '$comment'")
    fi

    # ReplayGain Tags (preserve from extracted - always allowed)
    local rg_track_gain=$(get_extracted_value "REPLAYGAIN_TRACK_GAIN")
    local rg_track_peak=$(get_extracted_value "REPLAYGAIN_TRACK_PEAK")
    local rg_album_gain=$(get_extracted_value "REPLAYGAIN_ALBUM_GAIN")
    local rg_album_peak=$(get_extracted_value "REPLAYGAIN_ALBUM_PEAK")

    [ -n "$rg_track_gain" ] && kid3_set_cmds+=(-c "set REPLAYGAIN_TRACK_GAIN '$rg_track_gain'")
    [ -n "$rg_track_peak" ] && kid3_set_cmds+=(-c "set REPLAYGAIN_TRACK_PEAK '$rg_track_peak'")
    [ -n "$rg_album_gain" ] && kid3_set_cmds+=(-c "set REPLAYGAIN_ALBUM_GAIN '$rg_album_gain'")
    [ -n "$rg_album_peak" ] && kid3_set_cmds+=(-c "set REPLAYGAIN_ALBUM_PEAK '$rg_album_peak'")

    # Other Extended Metadata (preserve from extracted, check if allowed)
    if is_frame_allowed "TYER"; then
        [ -n "$year" ]      && kid3_set_cmds+=(-c "set Year '$year'")
    fi
    if is_frame_allowed "TRCK"; then
        [ -n "$track_num" ] && kid3_set_cmds+=(-c "set 'Track Number' '$track_num'")
    fi
    if is_frame_allowed "TPOS"; then
        [ -n "$disc_num" ]  && kid3_set_cmds+=(-c "set 'Disc Number' '$disc_num'")
    fi
    if is_frame_allowed "TBPM"; then
        [ -n "$bpm" ]       && kid3_set_cmds+=(-c "set BPM '$bpm'")
    fi

    # Flush all accumulated text writes in one kid3-cli invocation
    if [ "${#kid3_set_cmds[@]}" -gt 0 ]; then
        $KID3_CMD "${kid3_set_cmds[@]}" "$filepath" 2>/dev/null
    fi

    # Album Art (restore from extracted binary - APIC always allowed)
    # Kept as a separate invocation: picture path arg uses different syntax;
    # mixing it with text sets is fragile.
    if [ "$has_album_art" = true ]; then
        if $KID3_CMD -c "set picture:'$album_art' ''" "$filepath" 2>/dev/null; then
            log_message "  âœ“ Album art restored"
        else
            log_message "  âš  Album art restoration failed (non-critical)"
        fi
    fi

    # Convert to ID3v2.3 (most compatible)
    $KID3_CMD -c "to23" "$filepath" 2>/dev/null || true

    # Restore file-preserved TXXX frames captured before tags were stripped.
    # DB-authoritative entries (SCHEMA_TXXX_DB) were excluded from the
    # txxx_preserved_values loop above, so they cannot appear here and cannot
    # overwrite the DB-sourced values written earlier in Stage 4.
    # Batched: accumulate all TXXX writes and flush in one kid3-cli invocation.
    local -a txxx_set_cmds=()
    for desc in "${!txxx_preserved_values[@]}"; do
        local val_clean
        val_clean="$(sanitize_for_kid3 "${txxx_preserved_values[$desc]}")"
        [ -n "$val_clean" ] && txxx_set_cmds+=(-c "set '$desc' '$val_clean'")
    done
    if [ "${#txxx_set_cmds[@]}" -gt 0 ]; then
        $KID3_CMD "${txxx_set_cmds[@]}" "$filepath" 2>/dev/null
    fi

    # Restore lyrics (USLT) extracted in Stage 1.
    # exiftool cannot write MP3 tags on this system (ver 13.50); use mutagen
    # (Python) instead. Paths are passed via environment variables to avoid
    # quoting/injection issues with arbitrary file paths.
    # Runs after to23 so the ID3v2.3 tag exists before mutagen writes to it.
    # is_frame_allowed "USLT" gates on the schema; if USLT is removed from
    # tag_schema.conf, lyrics will be silently dropped during rebuild.
    if [ "$has_lyrics" = true ] && is_frame_allowed "USLT"; then
        if MUSICLIB_LYRICS_FILE="$lyrics_file" MUSICLIB_MP3_FILE="$filepath" \
                python3 -c "
import os, sys
from mutagen.id3 import ID3, USLT
lf  = os.environ['MUSICLIB_LYRICS_FILE']
mp3 = os.environ['MUSICLIB_MP3_FILE']
with open(lf, 'r', errors='replace') as f:
    lyrics = f.read()
tags = ID3(mp3)
tags.add(USLT(encoding=1, lang='xxx', desc='', text=lyrics))
tags.save(v2_version=3)
" 2>/dev/null; then
            log_message "  Lyrics restored"
        else
            log_message "  Lyrics restoration failed (non-critical)"
        fi
    fi

    #########################################
    # STAGE 5: Verify Rebuild
    #########################################

    log_message "  Stage 5: Verifying rebuild..."

    # Check that at least core tags are present
    local verify_artist=$(exiftool -Artist -s3 "$filepath" 2>/dev/null)
    local verify_title=$(exiftool -Title -s3 "$filepath" 2>/dev/null)

    if [ -z "$verify_artist" ] && [ -z "$verify_title" ]; then
        log_message "  ERROR: Tag rebuild verification failed (no tags present)"
        return 3
    fi

    log_message "  âœ“ Tag rebuild complete"
    log_message "Tag rebuild successful for: $(basename "$filepath")"

    return 0
}

#############################################
# Normalize tags on new tracks before DB import
# Usage: normalize_new_track_tags <filepath>
# Returns: 0=success, 1=extraction failed, 2=removal failed, 3=rebuild failed
#
# This function cleans up tags on NEW TRACKS before they are added to the database.
# It extracts all metadata, strips all tags (including ID3v1, APE), and rebuilds
# with only ID3v2.3 frames allowed by the tag schema.
#
# Unlike rebuild_tag(), this does NOT query the database (track not in DB yet).
# All values come from the file's current tags (assumed to be user-edited).
#############################################
normalize_new_track_tags() {
    local filepath="$1"

    if [ ! -f "$filepath" ]; then
        echo "  ERROR: Cannot normalize tags - file not found: $filepath"
        return 1
    fi

    echo "  Normalizing tags for: $(basename "$filepath")"

    # Create temporary workspace
    local temp_dir=$(mktemp -d)
    local metadata_json="$temp_dir/metadata.json"
    local album_art="$temp_dir/cover.jpg"

    # Cleanup function
    cleanup_normalize() {
        rm -rf "$temp_dir" 2>/dev/null || true
    }
    trap cleanup_normalize RETURN

    #########################################
    # STAGE 1: Extract All Metadata
    #########################################

    # Extract full metadata as JSON
    if ! exiftool -json "$filepath" > "$metadata_json" 2>/dev/null; then
        echo "  ERROR: Metadata extraction failed"
        return 1
    fi

    if [ ! -s "$metadata_json" ]; then
        echo "  ERROR: Extracted metadata is empty"
        return 1
    fi

    # Extract album art
    exiftool -Picture -b "$filepath" > "$album_art" 2>/dev/null || true

    local has_album_art=false
    if [ -f "$album_art" ] && [ -s "$album_art" ]; then
        if file "$album_art" 2>/dev/null | grep -qi "image"; then
            has_album_art=true
        fi
    fi

    # Extract lyrics (USLT) to a temp file before tags are stripped.
    # Same jq-based approach as rebuild_tag(): exiftool names USLT as "Lyrics-{lang}"
    # in JSON, so "-Lyrics -s3" produces no output. Must run before Stage 2 strip.
    local lyrics_file="$temp_dir/lyrics.txt"
    local has_lyrics=false
    if command -v jq >/dev/null 2>&1; then
        local lyrics_key
        lyrics_key=$(jq -r '[.[0] | keys[] | select(test("^Lyrics"))] | first // empty' \
            "$metadata_json" 2>/dev/null)
        if [ -n "$lyrics_key" ]; then
            jq -r ".[0][\"$lyrics_key\"]" "$metadata_json" > "$lyrics_file" 2>/dev/null || true
        fi
    fi
    [ -s "$lyrics_file" ] && has_lyrics=true

    # Pre-read file-preserved TXXX frames via kid3-cli BEFORE tags are stripped.
    # Primary source is kid3-cli (reliable for all TXXX frames including those
    # exiftool silently skips). Exiftool JSON is checked as a fallback for values
    # stored in non-standard formats that kid3-cli may not expose via "get".
    # DB-authoritative entries (SCHEMA_TXXX_DB) are skipped — on normalization of
    # new tracks those fields are not yet in the database, so there is nothing to
    # overwrite, but skipping them keeps the logic symmetric with rebuild_tag().
    load_tag_schema 2>/dev/null || true
    declare -A txxx_preserved_values
    for desc in "${!SCHEMA_TXXX_ALLOWED[@]}"; do
        # Skip DB-authoritative TXXX entries
        [ -n "${SCHEMA_TXXX_DB[$desc]:-}" ] && continue
        local raw_val
        raw_val=$($KID3_CMD -c "get '$desc'" "$filepath" 2>/dev/null | tail -n1)
        if [ -z "$raw_val" ] && command -v jq >/dev/null 2>&1; then
            raw_val=$(jq -r ".[0].\"$desc\" // empty" "$metadata_json" 2>/dev/null)
            [ -z "$raw_val" ] && raw_val=$(jq -r ".[0].\"${desc,,}\" // empty" "$metadata_json" 2>/dev/null)
            [ -z "$raw_val" ] && raw_val=$(jq -r ".[0].\"${desc^}\" // empty" "$metadata_json" 2>/dev/null)
        fi
        [ -n "$raw_val" ] && txxx_preserved_values["$desc"]="$raw_val"
    done

    #########################################
    # STAGE 2: Remove All Existing Tags
    #########################################

    # Remove ID3v1, ID3v2, APE — batched into one kid3-cli invocation
    $KID3_CMD -c "remove 1" -c "remove 2" -c "remove 3" "$filepath" 2>/dev/null || true

    # Verify removal
    local tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^\[ID3" | wc -l)

    if [ "$tags_remaining" -gt 0 ]; then
        if command -v id3v2 >/dev/null 2>&1; then
            id3v2 --delete-all "$filepath" 2>/dev/null || true
            tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^ID3" | wc -l)

            if [ "$tags_remaining" -gt 0 ]; then
                echo "  ERROR: Cannot remove all tags"
                return 2
            fi
        fi
    fi

    #########################################
    # STAGE 3: Rebuild with Filtered Frames
    #########################################


    # Helper to get extracted value
    get_value() {
        local tag_name="$1"
        local value=""

        if command -v jq >/dev/null 2>&1; then
            value=$(jq -r ".[0].\"$tag_name\" // empty" "$metadata_json" 2>/dev/null)
        else
            value=$(grep "\"$tag_name\"" "$metadata_json" 2>/dev/null | head -1 | sed 's/.*: "\(.*\)".*/\1/')
        fi

        echo "$value"
    }

    # Core tags (always allowed)
    local artist=$(get_value "Artist")
    local album=$(get_value "Album")
    local albumartist=$(get_value "AlbumArtist")
    local title=$(get_value "Title")
    local genre=$(get_value "Genre")

    # Sanitize text tag values: single quotes break kid3-cli command quoting
    artist="$(sanitize_for_kid3 "$artist")"
    album="$(sanitize_for_kid3 "$album")"
    albumartist="$(sanitize_for_kid3 "$albumartist")"
    title="$(sanitize_for_kid3 "$title")"
    genre="$(sanitize_for_kid3 "$genre")"

    [ -n "$artist" ] && $KID3_CMD -c "set Artist '$artist'" "$filepath" 2>/dev/null
    [ -n "$album" ] && $KID3_CMD -c "set Album '$album'" "$filepath" 2>/dev/null
    [ -n "$albumartist" ] && $KID3_CMD -c "set AlbumArtist '$albumartist'" "$filepath" 2>/dev/null
    [ -n "$title" ] && $KID3_CMD -c "set Title '$title'" "$filepath" 2>/dev/null
    [ -n "$genre" ] && $KID3_CMD -c "set Genre '$genre'" "$filepath" 2>/dev/null

    # ReplayGain (always allowed - just added by rsgain)
    local rg_track_gain=$(get_value "REPLAYGAIN_TRACK_GAIN")
    local rg_track_peak=$(get_value "REPLAYGAIN_TRACK_PEAK")
    local rg_album_gain=$(get_value "REPLAYGAIN_ALBUM_GAIN")
    local rg_album_peak=$(get_value "REPLAYGAIN_ALBUM_PEAK")

    [ -n "$rg_track_gain" ] && $KID3_CMD -c "set REPLAYGAIN_TRACK_GAIN '$rg_track_gain'" "$filepath" 2>/dev/null
    [ -n "$rg_track_peak" ] && $KID3_CMD -c "set REPLAYGAIN_TRACK_PEAK '$rg_track_peak'" "$filepath" 2>/dev/null
    [ -n "$rg_album_gain" ] && $KID3_CMD -c "set REPLAYGAIN_ALBUM_GAIN '$rg_album_gain'" "$filepath" 2>/dev/null
    [ -n "$rg_album_peak" ] && $KID3_CMD -c "set REPLAYGAIN_ALBUM_PEAK '$rg_album_peak'" "$filepath" 2>/dev/null

    # Extended metadata (check if allowed)
    local year=$(get_value "Year")
    local comment
    comment=$(get_value "Comment")
    # Same Comment-xxx fallback as rebuild_tag() — see that function for explanation.
    if [ -z "$comment" ] && command -v jq >/dev/null 2>&1; then
        comment=$(jq -r \
            '[.[0] | to_entries[] | select(.key | test("^Comment")) | .value] | first // empty' \
            "$metadata_json" 2>/dev/null)
        comment="${comment#\(*\) }"
    fi
    comment="$(sanitize_for_kid3 "$comment")"
    local track_num=$(get_value "Track")
    [ -n "$track_num" ] && track_num=$(printf "%02d" "$((10#${track_num%%/*}))")
    # Fallback: if no track number tag, try to extract it from the filename.
    # New tracks are named NN_-_artist_-_title.mp3 where NN is the track number.
    # If neither source has a track number, default to "00" so the tag and
    # filename always carry a track number and maintain consistent format.
    # Note: 10# forces bash to parse the number as base-10, preventing printf
    # from misinterpreting leading-zero values (e.g. "08") as invalid octal.
    if [ -z "$track_num" ]; then
        local fname_noext
        fname_noext=$(basename "$filepath" .mp3)
        if [[ "$fname_noext" =~ ^([0-9]+)_ ]]; then
            track_num=$(printf "%02d" "$((10#${BASH_REMATCH[1]}))")
        else
            track_num="00"
        fi
    fi
    local disc_num=$(get_value "DiscNumber")
    local bpm=$(get_value "BPM")

    is_frame_allowed "TYER" && [ -n "$year" ] && $KID3_CMD -c "set Year '$year'" "$filepath" 2>/dev/null
    is_frame_allowed "COMM" && [ -n "$comment" ] && $KID3_CMD -c "set Comment '$comment'" "$filepath" 2>/dev/null
    is_frame_allowed "TRCK" && [ -n "$track_num" ] && $KID3_CMD -c "set 'Track Number' '$track_num'" "$filepath" 2>/dev/null
    is_frame_allowed "TPOS" && [ -n "$disc_num" ] && $KID3_CMD -c "set 'Disc Number' '$disc_num'" "$filepath" 2>/dev/null
    is_frame_allowed "TBPM" && [ -n "$bpm" ] && $KID3_CMD -c "set BPM '$bpm'" "$filepath" 2>/dev/null

    # Album art
    if [ "$has_album_art" = true ]; then
        $KID3_CMD -c "set picture:'$album_art' ''" "$filepath" 2>/dev/null || true
    fi

    # Convert to ID3v2.3 (most compatible)
    $KID3_CMD -c "to23" "$filepath" 2>/dev/null || true

    # Restore preserved TXXX frames captured before tags were stripped.
    for desc in "${!txxx_preserved_values[@]}"; do
        local val_clean
        val_clean="$(sanitize_for_kid3 "${txxx_preserved_values[$desc]}")"
        [ -n "$val_clean" ] && \
            $KID3_CMD -c "set '$desc' '$val_clean'" "$filepath" 2>/dev/null
    done

    # Restore lyrics (USLT) extracted in Stage 1.
    # Same mutagen approach as rebuild_tag() — exiftool 13.50 cannot write MP3 tags.
    if [ "$has_lyrics" = true ] && is_frame_allowed "USLT"; then
        if MUSICLIB_LYRICS_FILE="$lyrics_file" MUSICLIB_MP3_FILE="$filepath" \
                python3 -c "
import os, sys
from mutagen.id3 import ID3, USLT
lf  = os.environ['MUSICLIB_LYRICS_FILE']
mp3 = os.environ['MUSICLIB_MP3_FILE']
with open(lf, 'r', errors='replace') as f:
    lyrics = f.read()
tags = ID3(mp3)
tags.add(USLT(encoding=1, lang='xxx', desc='', text=lyrics))
tags.save(v2_version=3)
" 2>/dev/null; then
            echo "  Lyrics restored"
        else
            echo "  Lyrics restoration failed (non-critical)"
        fi
    fi

    #########################################
    # STAGE 4: Verify
    #########################################

    local verify_artist=$(exiftool -Artist -s3 "$filepath" 2>/dev/null)
    local verify_title=$(exiftool -Title -s3 "$filepath" 2>/dev/null)

    if [ -z "$verify_artist" ] && [ -z "$verify_title" ]; then
        echo "  ERROR: Tag normalization verification failed"
        return 3
    fi

    echo "  âœ“ Tag normalization complete"
    return 0
}
