#!/bin/bash
#
# musiclib_smartplaylist.sh - Smart playlist generator
#
# Builds a rated, variety-aware M3U playlist from the musiclib DSV database.
# Tracks are selected using a variance-weighted algorithm that:
#   - Groups tracks by POPM star rating (5 configurable groups)
#   - Excludes tracks played more recently than their group's age threshold
#   - Prioritises tracks most overdue within each group
#   - Maintains artist variety with a rolling effective-artist exclusion window
#     (Custom2 field overrides AlbumArtist for exclusion identity; see Addendum A.3)
#
# Pool building is delegated to musiclib_smartplaylist_analyze.sh -m file.
#
# Exit codes:
#   0 - Success
#   1 - User/validation error (bad arguments, insufficient tracks)
#   2 - System error (config load failure, database unreadable, I/O error)
#
set -u
set -o pipefail

###############################################################################
# Bootstrap
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! source "$SCRIPT_DIR/musiclib_utils.sh" 2>/dev/null; then
    printf '{"error":"Failed to load musiclib_utils.sh","script":"%s","code":2,"context":{"file":"%s"},"timestamp":"%s"}\n' \
        "$(basename "$0")" "$SCRIPT_DIR/musiclib_utils.sh" \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >&2
    exit 2
fi

if ! load_config 2>/dev/null; then
    error_exit 2 "Configuration load failed"
    exit 2
fi

###############################################################################
# Configuration defaults
# SP_AGE_GROUP1-5, SP_PLAYLIST_SIZE, SP_SAMPLE_SIZE, SP_ARTIST_EXCLUSION_COUNT
# are read from musiclib.conf via load_config.  Flags override these values.
###############################################################################

MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"
LOGFILE="${LOGFILE:-$(get_data_dir)/logs/musiclib.log}"
PLAYLISTS_DIR="${PLAYLISTS_DIR:-$(get_data_dir)/playlists}"

# Permanent pool file path — written by analyze script, read here
SP_POOL_FILE="$(get_data_dir)/data/sp_pool.csv"

# Delimiter
DELIM="^"

# Rating group POPM ranges.  Left empty so -u/-v flags and the resolution
# block below can fill them from RatingGroup* config after getopts.
SP_GROUP1_LOW=""
SP_GROUP1_HIGH=""
SP_GROUP2_LOW=""
SP_GROUP2_HIGH=""
SP_GROUP3_LOW=""
SP_GROUP3_HIGH=""
SP_GROUP4_LOW=""
SP_GROUP4_HIGH=""
SP_GROUP5_LOW=""
SP_GROUP5_HIGH=""

# Age thresholds — read from SP_AGE_GROUP* config keys
SP_GROUP1_DAYS="${SP_AGE_GROUP1:-360}"
SP_GROUP2_DAYS="${SP_AGE_GROUP2:-180}"
SP_GROUP3_DAYS="${SP_AGE_GROUP3:-90}"
SP_GROUP4_DAYS="${SP_AGE_GROUP4:-60}"
SP_GROUP5_DAYS="${SP_AGE_GROUP5:-30}"

# Playlist parameters — read from config keys
SP_PLAYLIST_SIZE="${SP_PLAYLIST_SIZE:-50}"
SP_SAMPLE_SIZE="${SP_SAMPLE_SIZE:-20}"
SP_EXCLUDED_ARTISTS="${SP_ARTIST_EXCLUSION_COUNT:-30}"

# Minimum tracks per group before that group contributes to a round
SP_GROUP_MIN=10

# Playlist name (without extension)
playlist_name="Smart Playlist"

# Output file path (set after option parsing)
playlist_output=""

# Load into Audacious after generation?
load_audacious=false

# Additional flags to pass through to analyze script
analyze_extra_flags=""

###############################################################################
# Help
###############################################################################

print_help() {
cat <<EOF

musiclib_smartplaylist.sh — Generate a smart playlist from the musiclib database.

Usage: musiclib_smartplaylist.sh [options]

Options:
  -e <n>           Number of recent unique artists to exclude per selection round.
                   Default: ${SP_EXCLUDED_ARTISTS}
  -g <thresholds>  Comma-separated age thresholds in days for groups 1–5,
                   lowest rated to highest.
                   Default: ${SP_GROUP1_DAYS},${SP_GROUP2_DAYS},${SP_GROUP3_DAYS},${SP_GROUP4_DAYS},${SP_GROUP5_DAYS}
  -h               Show this help and exit.
  -n <name>        Playlist name (without .m3u extension).
                   Default: "${playlist_name}"
  -o <file>        Full output file path (overrides -n and default directory).
  -p <n>           Target playlist size (number of tracks).
                   Default: ${SP_PLAYLIST_SIZE}
  -s <n>           Sample size — tracks considered per selection round.
                   Default: ${SP_SAMPLE_SIZE}
  -u <ranges>      Comma-separated POPM low bounds for groups 1–5.
                   Default: from RatingGroup1–5 in musiclib.conf
  -v <ranges>      Comma-separated POPM high bounds for groups 1–5.
                   Default: from RatingGroup1–5 in musiclib.conf
  --load-audacious Load the generated playlist into Audacious after writing.

Examples:
  # Generate a default 50-track playlist and load it into Audacious
  musiclib_smartplaylist.sh --load-audacious

  # 100-track playlist with tighter thresholds for a large library
  musiclib_smartplaylist.sh -p 100 -g 180,90,45,30,14 -n MyPlaylist

  # Specify a custom output path
  musiclib_smartplaylist.sh -o ~/playlist.m3u
EOF
}

###############################################################################
# Option parsing (handle --load-audacious as a long option before getopts)
###############################################################################

_args=()
for _arg in "$@"; do
    if [[ "$_arg" == "--load-audacious" ]]; then
        load_audacious=true
    else
        _args+=("$_arg")
    fi
done
set -- "${_args[@]+"${_args[@]}"}"

while getopts ":e:g:hn:o:p:s:u:v:" opt; do
    case $opt in
        e)  SP_EXCLUDED_ARTISTS="$OPTARG" ;;
        g)
            set -f
            IFS=',' read -r SP_GROUP1_DAYS SP_GROUP2_DAYS SP_GROUP3_DAYS \
                           SP_GROUP4_DAYS SP_GROUP5_DAYS <<< "$OPTARG"
            analyze_extra_flags="${analyze_extra_flags} -g $OPTARG"
            set +f
            ;;
        h)  print_help; exit 0 ;;
        n)  playlist_name="$OPTARG" ;;
        o)  playlist_output="$OPTARG" ;;
        p)  SP_PLAYLIST_SIZE="$OPTARG" ;;
        s)  SP_SAMPLE_SIZE="$OPTARG"
            analyze_extra_flags="${analyze_extra_flags} -s $OPTARG"
            ;;
        u)
            set -f
            IFS=',' read -r SP_GROUP1_LOW SP_GROUP2_LOW SP_GROUP3_LOW \
                           SP_GROUP4_LOW SP_GROUP5_LOW <<< "$OPTARG"
            analyze_extra_flags="${analyze_extra_flags} -u $OPTARG"
            set +f
            ;;
        v)
            set -f
            IFS=',' read -r SP_GROUP1_HIGH SP_GROUP2_HIGH SP_GROUP3_HIGH \
                           SP_GROUP4_HIGH SP_GROUP5_HIGH <<< "$OPTARG"
            analyze_extra_flags="${analyze_extra_flags} -v $OPTARG"
            set +f
            ;;
        \?) error_exit 1 "Invalid option: -$OPTARG" "option" "-$OPTARG"; exit 1 ;;
        :)  error_exit 1 "Option requires an argument: -$OPTARG" "option" "-$OPTARG"; exit 1 ;;
    esac
done

###############################################################################
# Resolve rating group POPM ranges (same priority as analyze script)
###############################################################################

_rg1_low=1;   _rg1_high=32
_rg2_low=33;  _rg2_high=96
_rg3_low=97;  _rg3_high=160
_rg4_low=161; _rg4_high=228
_rg5_low=229; _rg5_high=255

[[ -n "${RatingGroup1:-}" ]] && IFS=',' read -r _rg1_low _rg1_high <<< "$RatingGroup1"
[[ -n "${RatingGroup2:-}" ]] && IFS=',' read -r _rg2_low _rg2_high <<< "$RatingGroup2"
[[ -n "${RatingGroup3:-}" ]] && IFS=',' read -r _rg3_low _rg3_high <<< "$RatingGroup3"
[[ -n "${RatingGroup4:-}" ]] && IFS=',' read -r _rg4_low _rg4_high <<< "$RatingGroup4"
[[ -n "${RatingGroup5:-}" ]] && IFS=',' read -r _rg5_low _rg5_high <<< "$RatingGroup5"

SP_GROUP1_LOW="${SP_GROUP1_LOW:-$_rg1_low}"
SP_GROUP1_HIGH="${SP_GROUP1_HIGH:-$_rg1_high}"
SP_GROUP2_LOW="${SP_GROUP2_LOW:-$_rg2_low}"
SP_GROUP2_HIGH="${SP_GROUP2_HIGH:-$_rg2_high}"
SP_GROUP3_LOW="${SP_GROUP3_LOW:-$_rg3_low}"
SP_GROUP3_HIGH="${SP_GROUP3_HIGH:-$_rg3_high}"
SP_GROUP4_LOW="${SP_GROUP4_LOW:-$_rg4_low}"
SP_GROUP4_HIGH="${SP_GROUP4_HIGH:-$_rg4_high}"
SP_GROUP5_LOW="${SP_GROUP5_LOW:-$_rg5_low}"
SP_GROUP5_HIGH="${SP_GROUP5_HIGH:-$_rg5_high}"

###############################################################################
# Resolve output path
###############################################################################

if [[ -z "$playlist_output" ]]; then
    mkdir -p "$PLAYLISTS_DIR" 2>/dev/null || {
        error_exit 2 "Cannot create playlists directory" "path" "$PLAYLISTS_DIR"; exit 2
    }
    # Replace spaces with underscores for the filename
    _fname="${playlist_name// /_}"
    playlist_output="${PLAYLISTS_DIR}/${_fname}.m3u"
fi

###############################################################################
# Validation
###############################################################################

if ! validate_database "$MUSICDB"; then
    error_exit 2 "Database not found or invalid" "path" "$MUSICDB"; exit 2
fi

# If Audacious load is requested, verify it is running before doing any work
if [[ "$load_audacious" == "true" ]]; then
    if ! pgrep -x audacious >/dev/null; then
        error_exit 1 "Audacious is not running — cannot load playlist" "flag" "--load-audacious"
        exit 1
    fi
    if ! command -v audtool >/dev/null 2>&1; then
        error_exit 2 "audtool not found — required for Audacious integration" "tool" "audtool"
        exit 2
    fi
fi

###############################################################################
# Column detection (always dynamic — never hardcode positions)
# Includes Custom2 for effective-artist exclusion (Addendum A.3)
###############################################################################

header=$(head -1 "$MUSICDB")
popmcolnum=$(printf '%s\n' "$header"   | tr "$DELIM" '\n' | grep -n "^Rating$"        | cut -d: -f1)
timecolnum=$(printf '%s\n' "$header"   | tr "$DELIM" '\n' | grep -n "^LastTimePlayed$" | cut -d: -f1)
artistcolnum=$(printf '%s\n' "$header" | tr "$DELIM" '\n' | grep -n "^AlbumArtist$"   | cut -d: -f1)
pathcolnum=$(printf '%s\n' "$header"   | tr "$DELIM" '\n' | grep -n "^SongPath$"      | cut -d: -f1)
custom2colnum=$(printf '%s\n' "$header" | tr "$DELIM" '\n' | grep -n "^Custom2$"      | cut -d: -f1)
custom2colnum="${custom2colnum:-0}"   # 0 disables Custom2 in awk guards

if [[ -z "$popmcolnum" ]]; then
    error_exit 1 "Column 'Rating' not found in database header" "database" "$MUSICDB"; exit 1
fi
if [[ -z "$timecolnum" ]]; then
    error_exit 1 "Column 'LastTimePlayed' not found in database header" "database" "$MUSICDB"; exit 1
fi
if [[ -z "$artistcolnum" ]]; then
    error_exit 1 "Column 'AlbumArtist' not found in database header" "database" "$MUSICDB"; exit 1
fi
if [[ -z "$pathcolnum" ]]; then
    error_exit 1 "Column 'SongPath' not found in database header" "database" "$MUSICDB"; exit 1
fi

# Variance column: one past the last original DSV field
varcol=$(( $(printf '%s\n' "$header" | tr -cd "$DELIM" | wc -c) + 2 ))

###############################################################################
# Temp file setup
###############################################################################

TMPDIR_SP="$(get_data_dir)/tmp"
mkdir -p "$TMPDIR_SP" 2>/dev/null || {
    error_exit 2 "Cannot create temp directory" "path" "$TMPDIR_SP"; exit 2
}

SP_PREFIX="${TMPDIR_SP}/sp_gen_$$"
SP_POOL="${SP_PREFIX}_pool.dsv"       # Working copy of the pool (modified during loop)
SP_FILTERED="${SP_PREFIX}_filt.dsv"   # Pool with excluded artists removed
SP_EXCL="${SP_PREFIX}_excl.txt"       # Rolling excluded effective-artists list
SP_SAMPLE="${SP_PREFIX}_sample.txt"   # Current selection batch (path^effectiveArtist)
SP_SORTED="${SP_PREFIX}_sorted.dsv"   # Pool sorted by variance descending

cleanup() { rm -f "${SP_PREFIX}"* 2>/dev/null || true; }
trap cleanup EXIT

###############################################################################
# Step 1 — Build variance-annotated pool via analyze script (-m file)
###############################################################################

printf 'PROGRESS:0:%d\n' "$SP_PLAYLIST_SIZE"
printf 'Building eligible pool...\n'

# shellcheck disable=SC2086
"$SCRIPT_DIR/musiclib_smartplaylist_analyze.sh" \
    -m file \
    -g "${SP_GROUP1_DAYS},${SP_GROUP2_DAYS},${SP_GROUP3_DAYS},${SP_GROUP4_DAYS},${SP_GROUP5_DAYS}" \
    -s "$SP_SAMPLE_SIZE" \
    -u "${SP_GROUP1_LOW},${SP_GROUP2_LOW},${SP_GROUP3_LOW},${SP_GROUP4_LOW},${SP_GROUP5_LOW}" \
    -v "${SP_GROUP1_HIGH},${SP_GROUP2_HIGH},${SP_GROUP3_HIGH},${SP_GROUP4_HIGH},${SP_GROUP5_HIGH}" \
    2>&1 || {
    error_exit 2 "Pool build failed (analyze script returned non-zero)" \
        "script" "musiclib_smartplaylist_analyze.sh"
    exit 2
}

if [[ ! -f "$SP_POOL_FILE" ]]; then
    error_exit 2 "Pool file not found after analyze step" "path" "$SP_POOL_FILE"
    exit 2
fi

# Make a working copy so the loop can mutate it without touching the source
cp "$SP_POOL_FILE" "$SP_POOL" 2>/dev/null || {
    error_exit 2 "Cannot copy pool file" "src" "$SP_POOL_FILE" "dst" "$SP_POOL"
    exit 2
}

###############################################################################
# Pool size check — single consistent minimum using playlist target size
###############################################################################

pool_size=$(wc -l < "$SP_POOL")
printf 'Eligible pool: %d tracks\n' "$pool_size"

if [[ "$pool_size" -lt "$SP_PLAYLIST_SIZE" ]]; then
    error_exit 1 "Insufficient eligible tracks to build playlist" \
        "eligible" "$pool_size" "playlist_size" "$SP_PLAYLIST_SIZE"
    exit 1
fi

###############################################################################
# Build initial excluded-artists list
# Seed with the most recently played unique effective artists from the pool.
###############################################################################

sort -t"$DELIM" -k"$timecolnum" -rn "$SP_POOL" \
    | awk -F"$DELIM" \
        -v acol="$artistcolnum" \
        -v ccol="$custom2colnum" \
        -v n="$SP_EXCLUDED_ARTISTS" \
        '{ ea = (ccol > 0 && $ccol != "") ? $ccol : $acol
           if (seen[ea]++ == 0 && got < n) { print ea; got++ }
           if (got >= n) exit }' \
    > "$SP_EXCL" 2>/dev/null || touch "$SP_EXCL"

###############################################################################
# Main playlist generation loop
###############################################################################

printf 'Generating playlist: %s\n' "$playlist_output"
rm -f "$playlist_output"
currsize=0
round=0

while [[ "$currsize" -lt "$SP_PLAYLIST_SIZE" ]]; do
    round=$(( round + 1 ))

    # --- Filter pool by excluded effective-artists (exact field match) -------
    awk -F"$DELIM" \
        -v acol="$artistcolnum" \
        -v ccol="$custom2colnum" \
        'NR==FNR { excl[$0]=1; next }
         { ea = (ccol > 0 && $ccol != "") ? $ccol : $acol
           if (!(ea in excl)) print }' \
        "$SP_EXCL" "$SP_POOL" > "$SP_FILTERED" 2>/dev/null || {
        error_exit 2 "Artist filter failed on round $round"; exit 2
    }

    # --- Per-group counts and variance totals for the filtered pool -----------
    c1=0; v1=0; c2=0; v2=0; c3=0; v3=0; c4=0; v4=0; c5=0; v5=0
    read -r c1 v1 c2 v2 c3 v3 c4 v4 c5 v5 < <(
        awk -F"$DELIM" \
            -v pcol="$popmcolnum" -v vcol="$varcol" \
            -v g1l="$SP_GROUP1_LOW" -v g1h="$SP_GROUP1_HIGH" \
            -v g2l="$SP_GROUP2_LOW" -v g2h="$SP_GROUP2_HIGH" \
            -v g3l="$SP_GROUP3_LOW" -v g3h="$SP_GROUP3_HIGH" \
            -v g4l="$SP_GROUP4_LOW" -v g4h="$SP_GROUP4_HIGH" \
            -v g5l="$SP_GROUP5_LOW" -v g5h="$SP_GROUP5_HIGH" \
            '{
                popm = $pcol + 0
                var  = $vcol + 0
                if      (popm >= g5l && popm <= g5h) { c5++; v5+=var }
                else if (popm >= g4l && popm <= g4h) { c4++; v4+=var }
                else if (popm >= g3l && popm <= g3h) { c3++; v3+=var }
                else if (popm >= g2l && popm <= g2h) { c2++; v2+=var }
                else if (popm >= g1l && popm <= g1h) { c1++; v1+=var }
            }
            END { print c1+0, v1+0, c2+0, v2+0, c3+0, v3+0, c4+0, v4+0, c5+0, v5+0 }
        ' "$SP_FILTERED"
    )

    # Apply per-group minimum floor
    [[ "$c1" -lt "$SP_GROUP_MIN" ]] && { eff_c1=0; eff_v1=0; } || { eff_c1=$c1; eff_v1=$v1; }
    [[ "$c2" -lt "$SP_GROUP_MIN" ]] && { eff_c2=0; eff_v2=0; } || { eff_c2=$c2; eff_v2=$v2; }
    [[ "$c3" -lt "$SP_GROUP_MIN" ]] && { eff_c3=0; eff_v3=0; } || { eff_c3=$c3; eff_v3=$v3; }
    [[ "$c4" -lt "$SP_GROUP_MIN" ]] && { eff_c4=0; eff_v4=0; } || { eff_c4=$c4; eff_v4=$v4; }
    [[ "$c5" -lt "$SP_GROUP_MIN" ]] && { eff_c5=0; eff_v5=0; } || { eff_c5=$c5; eff_v5=$v5; }

    total_eff=$(( eff_c1 + eff_c2 + eff_c3 + eff_c4 + eff_c5 ))
    eff_vtot=$(( eff_v1 + eff_v2 + eff_v3 + eff_v4 + eff_v5 ))

    # Safety check after artist filter
    if [[ "$total_eff" -lt "$SP_PLAYLIST_SIZE" ]]; then
        printf 'WARNING: Pool dropped below playlist size after artist filter (round %d, %d tracks remaining).\n' \
            "$round" "$total_eff"
        printf 'Consider reducing -e (excluded artists) or relaxing age thresholds.\n'
        # If pool is completely empty, exit gracefully with what we have
        if [[ "$total_eff" -eq 0 ]]; then
            printf 'Pool exhausted — stopping at %d tracks.\n' "$currsize"
            break
        fi
    fi

    # Compute per-group sample slot counts
    if [[ "$eff_vtot" -gt 0 ]]; then
        s1=$(awk -v gv="$eff_v1" -v av="$eff_vtot" -v ss="$SP_SAMPLE_SIZE" \
            'BEGIN { printf "%d", int(gv/av*ss + 0.5) }')
        s2=$(awk -v gv="$eff_v2" -v av="$eff_vtot" -v ss="$SP_SAMPLE_SIZE" \
            'BEGIN { printf "%d", int(gv/av*ss + 0.5) }')
        s3=$(awk -v gv="$eff_v3" -v av="$eff_vtot" -v ss="$SP_SAMPLE_SIZE" \
            'BEGIN { printf "%d", int(gv/av*ss + 0.5) }')
        s4=$(awk -v gv="$eff_v4" -v av="$eff_vtot" -v ss="$SP_SAMPLE_SIZE" \
            'BEGIN { printf "%d", int(gv/av*ss + 0.5) }')
        s5=$(awk -v gv="$eff_v5" -v av="$eff_vtot" -v ss="$SP_SAMPLE_SIZE" \
            'BEGIN { printf "%d", int(gv/av*ss + 0.5) }')
    else
        # Flat fallback if all variances are zero
        per=$(( SP_SAMPLE_SIZE / 5 ))
        s1=$per; s2=$per; s3=$per; s4=$per; s5=$per
    fi

    # --- Sort filtered pool by variance descending (most overdue first) -------
    sort -t"$DELIM" -k"$varcol" -rn "$SP_FILTERED" > "$SP_SORTED" 2>/dev/null || {
        error_exit 2 "Sort failed on round $round"; exit 2
    }

    # --- Build sample: top N tracks from each group (path^effectiveArtist) ---
    awk -F"$DELIM" \
        -v pcol="$popmcolnum" \
        -v acol="$artistcolnum" \
        -v ccol="$custom2colnum" \
        -v pathcol="$pathcolnum" \
        -v g1l="$SP_GROUP1_LOW" -v g1h="$SP_GROUP1_HIGH" -v n1="$s1" \
        -v g2l="$SP_GROUP2_LOW" -v g2h="$SP_GROUP2_HIGH" -v n2="$s2" \
        -v g3l="$SP_GROUP3_LOW" -v g3h="$SP_GROUP3_HIGH" -v n3="$s3" \
        -v g4l="$SP_GROUP4_LOW" -v g4h="$SP_GROUP4_HIGH" -v n4="$s4" \
        -v g5l="$SP_GROUP5_LOW" -v g5h="$SP_GROUP5_HIGH" -v n5="$s5" \
        '{
            popm = $pcol + 0
            ea   = (ccol > 0 && $ccol != "") ? $ccol : $acol
            if      (popm >= g5l && popm <= g5h) { if (c5++ < n5) print $pathcol "^" ea }
            else if (popm >= g4l && popm <= g4h) { if (c4++ < n4) print $pathcol "^" ea }
            else if (popm >= g3l && popm <= g3h) { if (c3++ < n3) print $pathcol "^" ea }
            else if (popm >= g2l && popm <= g2h) { if (c2++ < n2) print $pathcol "^" ea }
            else if (popm >= g1l && popm <= g1h) { if (c1++ < n1) print $pathcol "^" ea }
        }
    ' "$SP_SORTED" > "$SP_SAMPLE" 2>/dev/null || {
        error_exit 2 "Sample selection failed on round $round"; exit 2
    }

    # Shuffle the sample so groups are interleaved randomly
    shuf "$SP_SAMPLE" -o "$SP_SAMPLE" 2>/dev/null || {
        error_exit 2 "shuf failed — ensure GNU coreutils is installed"; exit 2
    }

    # --- Process sample: add tracks, update exclusion window -----------------
    while IFS="$DELIM" read -r trackpath trackartist; do
        [[ -z "$trackpath" ]] && continue

        # Guard against the open-fd problem: the "remove same-artist entries from
        # $SP_SAMPLE" step below replaces the file on disk, but this loop's file
        # descriptor was opened before that replacement and still reads from the
        # original inode.  Check the live exclusion list so we never emit two
        # tracks by the same effective artist in the same round.
        if grep -qFx "$trackartist" "$SP_EXCL" 2>/dev/null; then
            continue
        fi

        # Add to playlist
        printf '%s\n' "$trackpath" >> "$playlist_output"

        # Update excluded effective-artists FIFO: push new, drop oldest
        {
            printf '%s\n' "$trackartist"
            head -n $(( SP_EXCLUDED_ARTISTS - 1 )) "$SP_EXCL"
        } > "${SP_EXCL}.tmp"
        mv "${SP_EXCL}.tmp" "$SP_EXCL"

        # Remove this track from the pool (can't be picked again)
        awk -F"$DELIM" -v pathcol="$pathcolnum" -v p="$trackpath" \
            '$pathcol != p { print }' "$SP_POOL" > "${SP_POOL}.tmp"
        mv "${SP_POOL}.tmp" "$SP_POOL"

        # Remove other tracks by the same effective artist from the current
        # sample to prevent back-to-back same artist within one batch
        awk -F"$DELIM" -v a="$trackartist" '$2 != a { print }' \
            "$SP_SAMPLE" > "${SP_SAMPLE}.tmp"
        mv "${SP_SAMPLE}.tmp" "$SP_SAMPLE"

        currsize=$(( currsize + 1 ))
        printf 'PROGRESS:%d:%d\n' "$currsize" "$SP_PLAYLIST_SIZE"
        printf '  [%d/%d] %s\n' "$currsize" "$SP_PLAYLIST_SIZE" \
            "$(basename "$trackpath")"

        [[ "$currsize" -ge "$SP_PLAYLIST_SIZE" ]] && break
    done < "$SP_SAMPLE"

    # If pool is exhausted, stop cleanly
    if [[ "$(wc -l < "$SP_POOL")" -eq 0 ]]; then
        printf 'Pool exhausted after %d tracks.\n' "$currsize"
        break
    fi
done

###############################################################################
# Trim to exact size (loop may overshoot by up to one batch)
###############################################################################

final_size=$(wc -l < "$playlist_output" 2>/dev/null || echo 0)
if [[ "$final_size" -gt "$SP_PLAYLIST_SIZE" ]]; then
    excess=$(( final_size - SP_PLAYLIST_SIZE ))
    head -n "$SP_PLAYLIST_SIZE" "$playlist_output" > "${playlist_output}.tmp"
    mv "${playlist_output}.tmp" "$playlist_output"
    printf 'Trimmed %d excess track(s).\n' "$excess"
    final_size="$SP_PLAYLIST_SIZE"
fi

printf '\nPlaylist complete: %d tracks\n' "$final_size"
printf 'Output: %s\n' "$playlist_output"
log_message "smartplaylist: generated $final_size tracks -> $playlist_output"

###############################################################################
# Optionally load into Audacious
###############################################################################

if [[ "$load_audacious" == "true" ]]; then
    printf 'Loading playlist into Audacious...\n'

    # Check for an existing playlist with the same name; if found, clear it.
    # Otherwise create a new one.
    num_playlists=$(audtool --number-of-playlists 2>/dev/null || echo 0)
    found_idx=""
    for (( idx=1; idx<=num_playlists; idx++ )); do
        pl_title=$(audtool --playlist-title "$idx" 2>/dev/null || true)
        if [[ "$pl_title" == "$playlist_name" ]]; then
            found_idx="$idx"
            break
        fi
    done

    if [[ -n "$found_idx" ]]; then
        # Select the existing playlist and clear it
        audtool --set-current-playlist "$found_idx" 2>/dev/null || true
        audtool --playlist-clear 2>/dev/null || true
        printf 'Cleared existing playlist "%s" (index %d).\n' "$playlist_name" "$found_idx"
    else
        # Create a new empty playlist and name it
        audtool --new-playlist 2>/dev/null || {
            error_exit 2 "audtool --new-playlist failed" "playlist" "$playlist_name"; exit 2
        }
        audtool --set-current-playlist-name "$playlist_name" 2>/dev/null || true
    fi

    # Add each track to the (now current) playlist
    while IFS= read -r trackpath; do
        [[ -z "$trackpath" ]] && continue
        audtool --playlist-addurl "$trackpath" 2>/dev/null || true
    done < "$playlist_output"

    printf 'Loaded "%s" (%d tracks) into Audacious.\n' "$playlist_name" "$final_size"
    log_message "smartplaylist: loaded '$playlist_name' into Audacious"
fi

###############################################################################
# JSON success output
###############################################################################

printf '{"status": "ok", "playlist": "%s", "tracks": %d, "output": "%s"}\n' \
    "${playlist_name//\"/\\\"}" "$final_size" "${playlist_output//\"/\\\"}"

exit 0
