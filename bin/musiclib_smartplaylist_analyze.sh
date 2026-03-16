#!/bin/bash
#
# musiclib_smartplaylist_analyze.sh - Smart playlist pool analysis tool
#
# Reads the musiclib DSV database, applies per-group rating and last-played age
# filters, and calculates variance weights.  Use this to tune age thresholds
# before generating a playlist, or call with -m preview|counts for machine-
# readable output (e.g. GUI preview / live constraint feedback).
#
# Modes (-m):
#   preview  (default) Full analysis: eligible counts, unique artists, variance
#            totals, sample weights, and per-group sample quantities.
#            JSON to stdout.
#   counts   Fast path: per-group eligible track count and unique artist count
#            only.  No variance computation.  JSON to stdout.
#   file     Write the variance-annotated intermediate pool to
#            ~/.local/share/musiclib/data/sp_pool.csv for use by the generator.
#            Emits a brief JSON status object to stdout.
#
# Exit codes:
#   0 - Success
#   1 - User/validation error (bad arguments, insufficient tracks)
#   2 - System error (config load failure, database unreadable, I/O error)
#
set -u
set -o pipefail

###############################################################################
# Bootstrap — resolve script directory and load shared utilities
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
# SP_AGE_GROUP1-5, SP_PLAYLIST_SIZE, SP_SAMPLE_SIZE are read from musiclib.conf
# via load_config.  Command-line flags override these values.
###############################################################################

MUSICDB="${MUSICDB:-$(get_data_dir)/data/musiclib.dsv}"
LOGFILE="${LOGFILE:-$(get_data_dir)/logs/musiclib.log}"

# Permanent pool output path (used by -m file)
SP_POOL_FILE="$(get_data_dir)/data/sp_pool.csv"

# Delimiter for the DSV database (overridable with -d)
DELIM="^"

# Rating group POPM ranges (low and high, inclusive).
# Left empty here so -u/-v flags can override and the resolution block below
# can fill them from RatingGroup* config after getopts.
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

# Age thresholds — read from SP_AGE_GROUP* config keys if available
SP_GROUP1_DAYS="${SP_AGE_GROUP1:-360}"
SP_GROUP2_DAYS="${SP_AGE_GROUP2:-180}"
SP_GROUP3_DAYS="${SP_AGE_GROUP3:-90}"
SP_GROUP4_DAYS="${SP_AGE_GROUP4:-60}"
SP_GROUP5_DAYS="${SP_AGE_GROUP5:-30}"

# POPM filter bounds (tracks outside this range are excluded entirely)
SP_POPM_MIN="${SP_POPM_MIN:-1}"
SP_POPM_MAX="${SP_POPM_MAX:-255}"

# Sample size used to compute per-group breakdown (from config key)
SP_SAMPLE_SIZE="${SP_SAMPLE_SIZE:-20}"

# Playlist size — used as the minimum eligible-pool floor for the warning check
SP_PLAYLIST_SIZE="${SP_PLAYLIST_SIZE:-50}"

# Minimum tracks per group before the group contributes to the sample
SP_GROUP_MIN=10

# Output mode: counts | preview (default) | file
output_mode="preview"

###############################################################################
# Help
###############################################################################

print_help() {
cat <<EOF

musiclib_smartplaylist_analyze.sh — Analyze smart playlist pool composition.

Usage: musiclib_smartplaylist_analyze.sh [options]

Options:
  -d <delim>       Field delimiter for the DSV database.  Default: ^
  -g <thresholds>  Comma-separated age thresholds in days for groups 1–5,
                   from lowest-rated to highest.
                   Default: ${SP_GROUP1_DAYS},${SP_GROUP2_DAYS},${SP_GROUP3_DAYS},${SP_GROUP4_DAYS},${SP_GROUP5_DAYS}
  -h               Show this help and exit.
  -m <mode>        Output mode: counts | preview | file
                     counts  — per-group eligible count and unique artists (fast)
                     preview — full variance analysis (default)
                     file    — write pool to \$MUSICLIB_DATA_DIR/data/sp_pool.csv
  -p <value>       Minimum POPM value to include.  Default: ${SP_POPM_MIN}
  -r <value>       Maximum POPM value to include.  Default: ${SP_POPM_MAX}
  -s <n>           Sample size for the per-group breakdown preview.
                   Default: ${SP_SAMPLE_SIZE}
  -u <ranges>      Comma-separated POPM low bounds for groups 1–5.
                   Default: from RatingGroup1–5 in musiclib.conf
  -v <ranges>      Comma-separated POPM high bounds for groups 1–5.
                   Default: from RatingGroup1–5 in musiclib.conf

Examples:
  # Preview with custom thresholds
  musiclib_smartplaylist_analyze.sh -g 720,360,180,90,45

  # Fast counts for live UI constraint feedback
  musiclib_smartplaylist_analyze.sh -m counts

  # Write pool file for playlist generator
  musiclib_smartplaylist_analyze.sh -m file -g 360,180,90,60,30
EOF
}

###############################################################################
# Option parsing
###############################################################################

while getopts ":d:g:hm:p:r:s:u:v:" opt; do
    case $opt in
        d)  DELIM="$OPTARG" ;;
        g)
            set -f
            IFS=',' read -r SP_GROUP1_DAYS SP_GROUP2_DAYS SP_GROUP3_DAYS \
                           SP_GROUP4_DAYS SP_GROUP5_DAYS <<< "$OPTARG"
            set +f
            ;;
        h)  print_help; exit 0 ;;
        m)  output_mode="$OPTARG"
            case "$output_mode" in
                counts|preview|file) ;;
                *) error_exit 1 "Invalid mode: -m $OPTARG (must be counts, preview, or file)" \
                       "option" "-m" "value" "$OPTARG"; exit 1 ;;
            esac
            ;;
        p)  SP_POPM_MIN="$OPTARG" ;;
        r)  SP_POPM_MAX="$OPTARG" ;;
        s)  SP_SAMPLE_SIZE="$OPTARG" ;;
        u)
            set -f
            IFS=',' read -r SP_GROUP1_LOW SP_GROUP2_LOW SP_GROUP3_LOW \
                           SP_GROUP4_LOW SP_GROUP5_LOW <<< "$OPTARG"
            set +f
            ;;
        v)
            set -f
            IFS=',' read -r SP_GROUP1_HIGH SP_GROUP2_HIGH SP_GROUP3_HIGH \
                           SP_GROUP4_HIGH SP_GROUP5_HIGH <<< "$OPTARG"
            set +f
            ;;
        \?) error_exit 1 "Invalid option: -$OPTARG" "option" "-$OPTARG"; exit 1 ;;
        :)  error_exit 1 "Option requires an argument: -$OPTARG" "option" "-$OPTARG"; exit 1 ;;
    esac
done

###############################################################################
# Resolve rating group POPM ranges
#
# Priority (highest to lowest):
#   1. -u / -v command-line flags (already set SP_GROUP* above if provided)
#   2. RatingGroup* variables from musiclib.conf (read by load_config)
#   3. Hardcoded POPM defaults (standard 5-group scale)
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
# Validation
###############################################################################

if ! validate_database "$MUSICDB"; then
    error_exit 2 "Database not found or invalid" "path" "$MUSICDB"
    exit 2
fi

# Detect column positions from the DSV header row.
# AlbumArtist is the raw artist column; Custom2 is the effective-artist override.
# If Custom2 is absent from the schema, custom2colnum=0 and the awk guard
# (ccol > 0 && $ccol != "") short-circuits to $acol for every track.
header=$(head -1 "$MUSICDB")
popmcolnum=$(printf '%s\n' "$header" | tr "$DELIM" '\n' | grep -n "^Rating$"        | cut -d: -f1)
timecolnum=$(printf '%s\n' "$header" | tr "$DELIM" '\n' | grep -n "^LastTimePlayed$" | cut -d: -f1)
artistcolnum=$(printf '%s\n' "$header" | tr "$DELIM" '\n' | grep -n "^AlbumArtist$" | cut -d: -f1)
pathcolnum=$(printf '%s\n' "$header"  | tr "$DELIM" '\n' | grep -n "^SongPath$"     | cut -d: -f1)
custom2colnum=$(printf '%s\n' "$header" | tr "$DELIM" '\n' | grep -n "^Custom2$"    | cut -d: -f1)
custom2colnum="${custom2colnum:-0}"   # 0 disables Custom2 lookup in awk guards

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

# Variance is appended after the last original DSV field
varcol=$(( $(printf '%s\n' "$header" | tr -cd "$DELIM" | wc -c) + 2 ))

###############################################################################
# Temp directory setup
###############################################################################

TMPDIR_SP="$(get_data_dir)/tmp"
mkdir -p "$TMPDIR_SP" 2>/dev/null || {
    error_exit 2 "Cannot create temp directory" "path" "$TMPDIR_SP"; exit 2
}
SP_POOL="${TMPDIR_SP}/sp_analyze_${$}_pool.dsv"

cleanup() { rm -f "${TMPDIR_SP}/sp_analyze_${$}_"* 2>/dev/null || true; }
trap cleanup EXIT

###############################################################################
# Current SQL date (OLE Automation / Delphi epoch: days since 1899-12-30)
###############################################################################

currsqldate=$(awk 'BEGIN { print int('"$(date +%s)"' / 86400 + 25569) }')

###############################################################################
# -m counts: fast path — filter only, no variance
# Counts eligible tracks and unique effective-artists per group.
# Writes JSON to stdout and exits.
###############################################################################

if [[ "$output_mode" == "counts" ]]; then

    read -r total_elig ua_eff ua_raw c2cov \
        g1c g1ua_eff g1ua_raw \
        g2c g2ua_eff g2ua_raw \
        g3c g3ua_eff g3ua_raw \
        g4c g4ua_eff g4ua_raw \
        g5c g5ua_eff g5ua_raw < <(
        awk -F"$DELIM" \
            -v today="$currsqldate" \
            -v pcol="$popmcolnum" \
            -v tcol="$timecolnum" \
            -v acol="$artistcolnum" \
            -v ccol="$custom2colnum" \
            -v pmin="$SP_POPM_MIN" -v pmax="$SP_POPM_MAX" \
            -v g1l="$SP_GROUP1_LOW"  -v g1h="$SP_GROUP1_HIGH"  -v g1d="$SP_GROUP1_DAYS" \
            -v g2l="$SP_GROUP2_LOW"  -v g2h="$SP_GROUP2_HIGH"  -v g2d="$SP_GROUP2_DAYS" \
            -v g3l="$SP_GROUP3_LOW"  -v g3h="$SP_GROUP3_HIGH"  -v g3d="$SP_GROUP3_DAYS" \
            -v g4l="$SP_GROUP4_LOW"  -v g4h="$SP_GROUP4_HIGH"  -v g4d="$SP_GROUP4_DAYS" \
            -v g5l="$SP_GROUP5_LOW"  -v g5h="$SP_GROUP5_HIGH"  -v g5d="$SP_GROUP5_DAYS" \
            '
            NR == 1 { next }
            {
                popm = $pcol + 0
                ltp  = $tcol + 0
                if (popm < pmin || popm > pmax) next

                if      (popm >= g5l && popm <= g5h) { thold = g5d; grp = 5 }
                else if (popm >= g4l && popm <= g4h) { thold = g4d; grp = 4 }
                else if (popm >= g3l && popm <= g3h) { thold = g3d; grp = 3 }
                else if (popm >= g2l && popm <= g2h) { thold = g2d; grp = 2 }
                else if (popm >= g1l && popm <= g1h) { thold = g1d; grp = 1 }
                else next

                if (thold <= 0) next
                if (ltp > today - thold) next

                # Effective artist: Custom2 if set, else AlbumArtist
                ea = (ccol > 0 && $ccol != "") ? $ccol : $acol
                raw_artist = $acol

                # Track Custom2 coverage
                if ($acol != "") {
                    total_tracks_with_artist++
                    if (ccol > 0 && $ccol != "") c2_set++
                }

                if (grp == 1) {
                    c1++
                    eff_artists_g1[ea]=1
                    raw_artists_g1[raw_artist]=1
                } else if (grp == 2) {
                    c2++
                    eff_artists_g2[ea]=1
                    raw_artists_g2[raw_artist]=1
                } else if (grp == 3) {
                    c3++
                    eff_artists_g3[ea]=1
                    raw_artists_g3[raw_artist]=1
                } else if (grp == 4) {
                    c4++
                    eff_artists_g4[ea]=1
                    raw_artists_g4[raw_artist]=1
                } else {
                    c5++
                    eff_artists_g5[ea]=1
                    raw_artists_g5[raw_artist]=1
                }
                all_eff_artists[ea]=1
                all_raw_artists[raw_artist]=1
            }
            END {
                ua_eff_tot = length(all_eff_artists)
                ua_raw_tot = length(all_raw_artists)
                c2_pct = (total_tracks_with_artist > 0) ? int(c2_set / total_tracks_with_artist * 100 + 0.5) : 0
                printf "%d %d %d %d  %d %d %d  %d %d %d  %d %d %d  %d %d %d  %d %d %d\n",
                    c1+c2+c3+c4+c5, ua_eff_tot, ua_raw_tot, c2_pct,
                    c1+0, length(eff_artists_g1), length(raw_artists_g1),
                    c2+0, length(eff_artists_g2), length(raw_artists_g2),
                    c3+0, length(eff_artists_g3), length(raw_artists_g3),
                    c4+0, length(eff_artists_g4), length(raw_artists_g4),
                    c5+0, length(eff_artists_g5), length(raw_artists_g5)
            }
        ' "$MUSICDB"
    )

    # Validate: warn if pool is below playlist target size
    if [[ "${total_elig:-0}" -lt "$SP_PLAYLIST_SIZE" ]]; then
        error_exit 1 "Insufficient eligible tracks for playlist target" \
            "eligible" "${total_elig:-0}" "playlist_size" "$SP_PLAYLIST_SIZE"
        exit 1
    fi

    # Build groups JSON array for counts mode
    _groups_json=""
    for g in 1 2 3 4 5; do
        eval "_gc=\${g${g}c:-0}"
        eval "_gua=\${g${g}ua_eff:-0}"
        [[ -n "$_groups_json" ]] && _groups_json="${_groups_json},"
        _entry="{ \"group\": ${g}, \"eligible_tracks\": ${_gc}, \"unique_artists\": ${_gua}"
        if [[ "$_gc" -lt "$SP_GROUP_MIN" ]]; then
            _entry="${_entry}, \"warning\": \"below minimum floor of ${SP_GROUP_MIN}; excluded from sampling\""
        fi
        _entry="${_entry} }"
        _groups_json="${_groups_json}${_entry}"
    done

    printf '{\n  "status": "ok",\n  "total_eligible": %d,\n  "unique_artists_eligible": %d,\n  "unique_artists_raw": %d,\n  "custom2_coverage_pct": %d,\n  "groups": [%s]\n}\n' \
        "${total_elig:-0}" "${ua_eff:-0}" "${ua_raw:-0}" "${c2cov:-0}" "$_groups_json"
    exit 0
fi

###############################################################################
# Build variance-annotated pool (single awk pass — filter + variance)
# Used by both -m preview and -m file.
#
# Pool file format: original DSV row + one appended variance field.
# Variance = how far past its eligibility threshold the track is, as a %:
#   variance = round(days_since_last_played / group_threshold * 100 - 100)
# Never-played tracks (LastTimePlayed == 0) receive variance 9999.
###############################################################################

awk -F"$DELIM" -v OFS="$DELIM" \
    -v today="$currsqldate" \
    -v pcol="$popmcolnum"   \
    -v tcol="$timecolnum"   \
    -v pmin="$SP_POPM_MIN"  \
    -v pmax="$SP_POPM_MAX"  \
    -v g1l="$SP_GROUP1_LOW"  -v g1h="$SP_GROUP1_HIGH"  -v g1d="$SP_GROUP1_DAYS" \
    -v g2l="$SP_GROUP2_LOW"  -v g2h="$SP_GROUP2_HIGH"  -v g2d="$SP_GROUP2_DAYS" \
    -v g3l="$SP_GROUP3_LOW"  -v g3h="$SP_GROUP3_HIGH"  -v g3d="$SP_GROUP3_DAYS" \
    -v g4l="$SP_GROUP4_LOW"  -v g4h="$SP_GROUP4_HIGH"  -v g4d="$SP_GROUP4_DAYS" \
    -v g5l="$SP_GROUP5_LOW"  -v g5h="$SP_GROUP5_HIGH"  -v g5d="$SP_GROUP5_DAYS" \
    '
    NR == 1 { next }
    {
        popm = $pcol + 0
        ltp  = $tcol + 0

        if (popm < pmin || popm > pmax) next

        if      (popm >= g5l && popm <= g5h) { thold = g5d }
        else if (popm >= g4l && popm <= g4h) { thold = g4d }
        else if (popm >= g3l && popm <= g3h) { thold = g3d }
        else if (popm >= g2l && popm <= g2h) { thold = g2d }
        else if (popm >= g1l && popm <= g1h) { thold = g1d }
        else next

        if (thold <= 0) next
        if (ltp > today - thold) next

        if (ltp == 0) {
            variance = 9999
        } else {
            days = today - int(ltp)
            if (days < 0) days = 0
            variance = int(days / thold * 100 - 100 + 0.5)
        }

        print $0 OFS variance
    }
' "$MUSICDB" > "$SP_POOL" 2>/dev/null || {
    error_exit 2 "Failed to build pool from database" "database" "$MUSICDB"; exit 2
}

###############################################################################
# -m file: write permanent pool and exit
###############################################################################

if [[ "$output_mode" == "file" ]]; then
    mkdir -p "$(dirname "$SP_POOL_FILE")" 2>/dev/null
    cp "$SP_POOL" "$SP_POOL_FILE" 2>/dev/null || {
        error_exit 2 "Failed to write pool file" "path" "$SP_POOL_FILE"; exit 2
    }
    pool_count=$(wc -l < "$SP_POOL_FILE" 2>/dev/null || echo 0)
    printf '{"status": "ok", "pool_file": "%s", "pool_tracks": %d}\n' \
        "$SP_POOL_FILE" "$pool_count"
    exit 0
fi

###############################################################################
# -m preview: per-group statistics (counts + variance + unique artists)
###############################################################################

# Single pass: counts, variance totals, unique effective/raw artists, Custom2 coverage
read -r c1 v1 ua1_eff ua1_raw \
        c2 v2 ua2_eff ua2_raw \
        c3 v3 ua3_eff ua3_raw \
        c4 v4 ua4_eff ua4_raw \
        c5 v5 ua5_eff ua5_raw \
        vtot ua_eff_tot ua_raw_tot c2_pct_tot < <(
    awk -F"$DELIM" \
        -v pcol="$popmcolnum" \
        -v vcol="$varcol"     \
        -v acol="$artistcolnum" \
        -v ccol="$custom2colnum" \
        -v g1l="$SP_GROUP1_LOW" -v g1h="$SP_GROUP1_HIGH" \
        -v g2l="$SP_GROUP2_LOW" -v g2h="$SP_GROUP2_HIGH" \
        -v g3l="$SP_GROUP3_LOW" -v g3h="$SP_GROUP3_HIGH" \
        -v g4l="$SP_GROUP4_LOW" -v g4h="$SP_GROUP4_HIGH" \
        -v g5l="$SP_GROUP5_LOW" -v g5h="$SP_GROUP5_HIGH" \
        '{
            popm = $pcol + 0
            var  = $vcol + 0
            ea   = (ccol > 0 && $ccol != "") ? $ccol : $acol
            raw  = $acol

            if (raw != "") {
                all_tracks_for_c2++
                if (ccol > 0 && $ccol != "") c2_total++
            }

            if      (popm >= g5l && popm <= g5h) { c5++; v5+=var; eff5[ea]=1; raw5[raw]=1 }
            else if (popm >= g4l && popm <= g4h) { c4++; v4+=var; eff4[ea]=1; raw4[raw]=1 }
            else if (popm >= g3l && popm <= g3h) { c3++; v3+=var; eff3[ea]=1; raw3[raw]=1 }
            else if (popm >= g2l && popm <= g2h) { c2++; v2+=var; eff2[ea]=1; raw2[raw]=1 }
            else if (popm >= g1l && popm <= g1h) { c1++; v1+=var; eff1[ea]=1; raw1[raw]=1 }
            vtot += var
            all_eff[ea]=1; all_raw[raw]=1
        }
        END {
            c2pct = (all_tracks_for_c2 > 0) ? int(c2_total/all_tracks_for_c2*100+0.5) : 0
            print c1+0, v1+0, length(eff1), length(raw1),
                  c2+0, v2+0, length(eff2), length(raw2),
                  c3+0, v3+0, length(eff3), length(raw3),
                  c4+0, v4+0, length(eff4), length(raw4),
                  c5+0, v5+0, length(eff5), length(raw5),
                  vtot+0, length(all_eff), length(all_raw), c2pct+0
        }
    ' "$SP_POOL"
)

# Set safe defaults if awk produced no output (empty pool)
c1=${c1:-0}; v1=${v1:-0}; ua1_eff=${ua1_eff:-0}; ua1_raw=${ua1_raw:-0}
c2=${c2:-0}; v2=${v2:-0}; ua2_eff=${ua2_eff:-0}; ua2_raw=${ua2_raw:-0}
c3=${c3:-0}; v3=${v3:-0}; ua3_eff=${ua3_eff:-0}; ua3_raw=${ua3_raw:-0}
c4=${c4:-0}; v4=${v4:-0}; ua4_eff=${ua4_eff:-0}; ua4_raw=${ua4_raw:-0}
c5=${c5:-0}; v5=${v5:-0}; ua5_eff=${ua5_eff:-0}; ua5_raw=${ua5_raw:-0}
vtot=${vtot:-0}; ua_eff_tot=${ua_eff_tot:-0}; ua_raw_tot=${ua_raw_tot:-0}
c2_pct_tot=${c2_pct_tot:-0}

# Apply group minimum floor
# Groups below the floor are excluded from sample weighting but still reported
# with a "warning" field so the caller can surface the issue.
[[ "$c1" -lt "$SP_GROUP_MIN" ]] && { eff_c1=0; eff_v1=0; } || { eff_c1=$c1; eff_v1=$v1; }
[[ "$c2" -lt "$SP_GROUP_MIN" ]] && { eff_c2=0; eff_v2=0; } || { eff_c2=$c2; eff_v2=$v2; }
[[ "$c3" -lt "$SP_GROUP_MIN" ]] && { eff_c3=0; eff_v3=0; } || { eff_c3=$c3; eff_v3=$v3; }
[[ "$c4" -lt "$SP_GROUP_MIN" ]] && { eff_c4=0; eff_v4=0; } || { eff_c4=$c4; eff_v4=$v4; }
[[ "$c5" -lt "$SP_GROUP_MIN" ]] && { eff_c5=0; eff_v5=0; } || { eff_c5=$c5; eff_v5=$v5; }

total_eligible=$(( eff_c1 + eff_c2 + eff_c3 + eff_c4 + eff_c5 ))
eff_vtot=$(( eff_v1 + eff_v2 + eff_v3 + eff_v4 + eff_v5 ))

# Validate pool size against playlist target
if [[ "$total_eligible" -lt "$SP_PLAYLIST_SIZE" ]]; then
    error_exit 1 "Insufficient eligible tracks for playlist target" \
        "eligible" "$total_eligible" "playlist_size" "$SP_PLAYLIST_SIZE"
    exit 1
fi

# Per-group sample quantities (proportional to variance totals)
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
    s1=0; s2=0; s3=0; s4=0; s5=0
fi

# Build per-group sample weight percentages (rounded to 1 decimal)
_sw1=0; _sw2=0; _sw3=0; _sw4=0; _sw5=0
if [[ "$eff_vtot" -gt 0 ]]; then
    _sw1=$(awk -v gv="$eff_v1" -v av="$eff_vtot" 'BEGIN { printf "%.1f", gv/av*100 }')
    _sw2=$(awk -v gv="$eff_v2" -v av="$eff_vtot" 'BEGIN { printf "%.1f", gv/av*100 }')
    _sw3=$(awk -v gv="$eff_v3" -v av="$eff_vtot" 'BEGIN { printf "%.1f", gv/av*100 }')
    _sw4=$(awk -v gv="$eff_v4" -v av="$eff_vtot" 'BEGIN { printf "%.1f", gv/av*100 }')
    _sw5=$(awk -v gv="$eff_v5" -v av="$eff_vtot" 'BEGIN { printf "%.1f", gv/av*100 }')
fi

# Variance totals as decimals (they are integers from awk but JSON spec wants "14.72" style)
_vt1=$(awk -v v="$v1" 'BEGIN { printf "%.2f", v }')
_vt2=$(awk -v v="$v2" 'BEGIN { printf "%.2f", v }')
_vt3=$(awk -v v="$v3" 'BEGIN { printf "%.2f", v }')
_vt4=$(awk -v v="$v4" 'BEGIN { printf "%.2f", v }')
_vt5=$(awk -v v="$v5" 'BEGIN { printf "%.2f", v }')

# Build groups JSON array
_build_group_entry() {
    local g=$1 stars=$2 plow=$3 phigh=$4 tdays=$5
    local cnt=$6 ua_eff=$7 ua_raw=$8 vt=$9 sw=${10} sq=${11}
    local entry
    entry="{ \"group\": ${g}, \"stars\": ${stars},"
    entry="${entry} \"popm_low\": ${plow}, \"popm_high\": ${phigh},"
    entry="${entry} \"threshold_days\": ${tdays},"
    entry="${entry} \"eligible_tracks\": ${cnt},"
    entry="${entry} \"unique_artists\": ${ua_eff},"
    entry="${entry} \"unique_artists_raw\": ${ua_raw},"
    entry="${entry} \"variance_total\": ${vt},"
    entry="${entry} \"sample_weight_pct\": ${sw},"
    entry="${entry} \"sample_qty\": ${sq}"
    # Add warning for below-floor groups
    if [[ "$cnt" -lt "$SP_GROUP_MIN" ]]; then
        entry="${entry}, \"warning\": \"below minimum floor of ${SP_GROUP_MIN}; excluded from sampling\""
    fi
    entry="${entry} }"
    printf '%s' "$entry"
}

_g1=$(_build_group_entry 1 1 "$SP_GROUP1_LOW" "$SP_GROUP1_HIGH" "$SP_GROUP1_DAYS" \
    "$c1" "$ua1_eff" "$ua1_raw" "$_vt1" "$_sw1" "$s1")
_g2=$(_build_group_entry 2 2 "$SP_GROUP2_LOW" "$SP_GROUP2_HIGH" "$SP_GROUP2_DAYS" \
    "$c2" "$ua2_eff" "$ua2_raw" "$_vt2" "$_sw2" "$s2")
_g3=$(_build_group_entry 3 3 "$SP_GROUP3_LOW" "$SP_GROUP3_HIGH" "$SP_GROUP3_DAYS" \
    "$c3" "$ua3_eff" "$ua3_raw" "$_vt3" "$_sw3" "$s3")
_g4=$(_build_group_entry 4 4 "$SP_GROUP4_LOW" "$SP_GROUP4_HIGH" "$SP_GROUP4_DAYS" \
    "$c4" "$ua4_eff" "$ua4_raw" "$_vt4" "$_sw4" "$s4")
_g5=$(_build_group_entry 5 5 "$SP_GROUP5_LOW" "$SP_GROUP5_HIGH" "$SP_GROUP5_DAYS" \
    "$c5" "$ua5_eff" "$ua5_raw" "$_vt5" "$_sw5" "$s5")

printf '{\n  "status": "ok",\n  "total_eligible": %d,\n  "unique_artists_eligible": %d,\n  "unique_artists_raw": %d,\n  "custom2_coverage_pct": %d,\n  "groups": [\n    %s,\n    %s,\n    %s,\n    %s,\n    %s\n  ]\n}\n' \
    "$total_eligible" "$ua_eff_tot" "$ua_raw_tot" "$c2_pct_tot" \
    "$_g1" "$_g2" "$_g3" "$_g4" "$_g5"

exit 0
