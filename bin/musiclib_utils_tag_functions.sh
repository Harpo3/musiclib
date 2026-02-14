#!/bin/bash
# ============================================================================
# TAG REPAIR AND NORMALIZATION FUNCTIONS
# ============================================================================
# These functions handle tag corruption repair and new track tag normalization
# Added in Phase 00_03

# Global array for excluded frames (loaded once)
declare -A EXCLUDED_FRAMES
FRAMES_LOADED=false

#############################################
# Load frame exclude list from config
# Usage: load_frame_excludes
# Returns: 0=success, 1=fallback to defaults
#############################################
load_frame_excludes() {
    # Only load once
    [ "$FRAMES_LOADED" = true ] && return 0

    local config_dir
    if [ -n "${MUSICLIB_ROOT:-}" ]; then
    config_dir="${MUSICLIB_ROOT}/config"
    else
    # Use XDG-aware detection from musiclib_utils.sh
    config_dir="$(get_config_dir)"
    fi

    local custom_file="${MUSICLIB_ROOT}/config/tag_excludes.conf"
    local default_file="${MUSICLIB_ROOT}/config/ID3v2_frame_excludes.txt"
    local exclude_file=""

    # Priority: custom config > default file > built-in defaults
    if [ -f "$custom_file" ]; then
        exclude_file="$custom_file"
        log_message "Loading frame excludes from: $custom_file"
    elif [ -f "$default_file" ]; then
        exclude_file="$default_file"
        log_message "Loading frame excludes from: $default_file"
    else
        log_message "No frame exclude list found, using built-in defaults"
        load_default_excludes
        FRAMES_LOADED=true
        return 1
    fi

    # Parse exclude file for frame codes
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Extract frame code (first 4 uppercase letters/numbers)
        if [[ "$line" =~ ^[[:space:]]*([A-Z0-9]{4}) ]]; then
            local frame="${BASH_REMATCH[1]}"
            EXCLUDED_FRAMES["$frame"]=1
        fi
    done < "$exclude_file"

    FRAMES_LOADED=true
    log_message "Loaded ${#EXCLUDED_FRAMES[@]} excluded ID3v2 frames"
    return 0
}

#############################################
# Load built-in default excludes (fallback)
# Usage: load_default_excludes
# Returns: Always 0
#############################################
load_default_excludes() {
    local defaults=(
        # Personnel
        "TPE3" "TPE4" "TCOM" "TEXT" "TOLY"
        # Original/Source
        "TOAL" "TOPE"
        # Legal/Commercial
        "TOWN" "TENC" "TCOP" "TCMP"
        # URLs
        "WCOM" "WCOP" "WOAF" "WOAR" "WOAS" "WORS" "WPAY" "WPUB" "WXXX"
        # Technical
        "TKEY" "TLAN" "TDLY" "TSIZ" "UFID" "GEOB" "PRIV" "ETCO"
        "AENC" "ENCR" "GRID" "LINK"
    )

    for frame in "${defaults[@]}"; do
        EXCLUDED_FRAMES["$frame"]=1
    done

    log_message "Loaded ${#defaults[@]} default excluded frames"
}

#############################################
# Check if a frame is allowed (not in exclude list)
# Usage: is_frame_allowed <frame_code> [description]
# Returns: 0=allowed, 1=excluded
#############################################
is_frame_allowed() {
    local frame="$1"
    local description="${2:-}"

    # Ensure excludes are loaded
    load_frame_excludes 2>/dev/null || true

    # Special handling for TXXX (user-defined text frames)
    if [[ "$frame" == "TXXX" ]]; then
        # Always allow our custom database fields
        if [[ "$description" == "Songs-DB_Custom1" ]] || \
           [[ "$description" == "Songs-DB_Custom2" ]]; then
            return 0
        fi
        # Always allow ReplayGain tags (stored as TXXX)
        if [[ "$description" =~ ^REPLAYGAIN ]]; then
            return 0
        fi
        # Block all other TXXX frames
        return 1
    fi

    # Check if frame is in exclude list
    if [ -n "${EXCLUDED_FRAMES[$frame]:-}" ]; then
        return 1  # Excluded
    fi

    return 0  # Allowed
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
#   - Only frames NOT in the exclude list
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
            log_message "  âœ“ Album art extracted ($(stat -c%s "$album_art") bytes)"
        fi
    fi

    log_message "  âœ“ Metadata extraction complete"

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

    # Remove ID3v1
    $KID3_CMD -c "select \"$filepath\"" -c "tag 1" -c "remove" 2>/dev/null || true

    # Remove ID3v2
    $KID3_CMD -c "select \"$filepath\"" -c "tag 2" -c "remove" 2>/dev/null || true

    # Remove APE
    $KID3_CMD -c "select \"$filepath\"" -c "tag 3" -c "remove" 2>/dev/null || true

    # Verify removal
    local tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^\[ID3" | wc -l)

    if [ "$tags_remaining" -gt 0 ]; then
        # Try harder with id3v2 tool if available
        if command -v id3v2 >/dev/null 2>&1; then
            log_message "  âš  Some tags remain, trying id3v2 tool..."
            id3v2 --delete-all "$filepath" 2>/dev/null || true

            # Check again
            tags_remaining=$(exiftool -G1 "$filepath" 2>/dev/null | grep "^ID3" | wc -l)

            if [ "$tags_remaining" -gt 0 ]; then
                log_message "  ERROR: Cannot remove all tags ($tags_remaining remain)"
                return 2
            fi
        else
            log_message "  ERROR: Cannot remove all tags ($tags_remaining remain) and id3v2 not available"
            return 2
        fi
    fi

    log_message "  âœ“ All tags removed"

    #########################################
    # STAGE 4: Rebuild Tags (Hybrid + Filtered)
    #########################################

    log_message "  Stage 4: Rebuilding tags with frame filtering..."

    # Select ID3v2.3 format (most compatible)
    $KID3_CMD -c "select \"$filepath\"" -c "tag 2" 2>/dev/null

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
    local comment=$(get_extracted_value "Comment")
    local track_num=$(get_extracted_value "Track")
    local disc_num=$(get_extracted_value "DiscNumber")
    local bpm=$(get_extracted_value "BPM")

    # Core Identification Tags (DB authoritative, filter allowed)
    local artist="${db_artist:-$(get_extracted_value "Artist")}"
    local album="${db_album:-$(get_extracted_value "Album")}"
    local albumartist="${db_albumartist:-$(get_extracted_value "AlbumArtist")}"
    local title="${db_title:-$(get_extracted_value "Title")}"
    local genre="${db_genre:-$(get_extracted_value "Genre")}"

    # Always write core tags (these are never excluded)
    [ -n "$artist" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Artist '$artist'" 2>/dev/null
    [ -n "$album" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Album '$album'" 2>/dev/null
    [ -n "$albumartist" ] && $KID3_CMD -c "select \"$filepath\"" -c "set AlbumArtist '$albumartist'" 2>/dev/null
    [ -n "$title" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Title '$title'" 2>/dev/null
    [ -n "$genre" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Genre '$genre'" 2>/dev/null

    # Rating Tags (DB authoritative)
    if [ -n "$db_rating" ]; then
        $KID3_CMD -c "select \"$filepath\"" -c "set POPM $db_rating" 2>/dev/null
    fi
    if [ -n "$db_groupdesc" ]; then
        $KID3_CMD -c "select \"$filepath\"" -c "set Grouping $db_groupdesc" 2>/dev/null
    fi

    # Play Tracking Tags (DB authoritative - always allowed)
    # IMPORTANT: Written after Comment to prevent kid3-cli frame confusion
    if [ -n "$db_lastplayed" ]; then
        $KID3_CMD -c "select \"$filepath\"" -c "set Songs-DB_Custom1 '$db_lastplayed'" 2>/dev/null
    fi
    if [ -n "$db_custom2" ]; then
        $KID3_CMD -c "select \"$filepath\"" -c "set Songs-DB_Custom2 '$db_custom2'" 2>/dev/null
    fi
    if is_frame_allowed "COMM"; then
        if [ -n "$comment" ]; then
            $KID3_CMD -c "select \"$filepath\"" -c "set Comment '$comment'" 2>/dev/null
        fi
    fi


    # ReplayGain Tags (preserve from extracted - always allowed)
    local rg_track_gain=$(get_extracted_value "REPLAYGAIN_TRACK_GAIN")
    local rg_track_peak=$(get_extracted_value "REPLAYGAIN_TRACK_PEAK")
    local rg_album_gain=$(get_extracted_value "REPLAYGAIN_ALBUM_GAIN")
    local rg_album_peak=$(get_extracted_value "REPLAYGAIN_ALBUM_PEAK")

    [ -n "$rg_track_gain" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_TRACK_GAIN '$rg_track_gain'" 2>/dev/null
    [ -n "$rg_track_peak" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_TRACK_PEAK '$rg_track_peak'" 2>/dev/null
    [ -n "$rg_album_gain" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_ALBUM_GAIN '$rg_album_gain'" 2>/dev/null
    [ -n "$rg_album_peak" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_ALBUM_PEAK '$rg_album_peak'" 2>/dev/null

    # Other Extended Metadata (preserve from extracted, check if allowed)
    if is_frame_allowed "TYER"; then
        [ -n "$year" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Year '$year'" 2>/dev/null
    fi

    if is_frame_allowed "TRCK"; then
        [ -n "$track_num" ] && $KID3_CMD -c "select \"$filepath\"" -c "set 'Track Number' '$track_num'" 2>/dev/null
    fi

    if is_frame_allowed "TPOS"; then
        [ -n "$disc_num" ] && $KID3_CMD -c "select \"$filepath\"" -c "set 'Disc Number' '$disc_num'" 2>/dev/null
    fi

    if is_frame_allowed "TBPM"; then
        [ -n "$bpm" ] && $KID3_CMD -c "select \"$filepath\"" -c "set BPM '$bpm'" 2>/dev/null
    fi

    # Album Art (restore from extracted binary - APIC always allowed)
    if [ "$has_album_art" = true ]; then
        if $KID3_CMD -c "select \"$filepath\"" -c "set picture:'$album_art' ''" 2>/dev/null; then
            log_message "  âœ“ Album art restored"
        else
            log_message "  âš  Album art restoration failed (non-critical)"
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
# with only ID3v2.3 frames that are NOT in the exclude list.
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

    #########################################
    # STAGE 2: Remove All Existing Tags
    #########################################

    # Remove ID3v1
    $KID3_CMD -c "select \"$filepath\"" -c "tag 1" -c "remove" 2>/dev/null || true

    # Remove ID3v2
    $KID3_CMD -c "select \"$filepath\"" -c "tag 2" -c "remove" 2>/dev/null || true

    # Remove APE
    $KID3_CMD -c "select \"$filepath\"" -c "tag 3" -c "remove" 2>/dev/null || true

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

    # Select ID3v2.3 format
    $KID3_CMD -c "select \"$filepath\"" -c "tag 2" 2>/dev/null

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

    [ -n "$artist" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Artist '$artist'" 2>/dev/null
    [ -n "$album" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Album '$album'" 2>/dev/null
    [ -n "$albumartist" ] && $KID3_CMD -c "select \"$filepath\"" -c "set AlbumArtist '$albumartist'" 2>/dev/null
    [ -n "$title" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Title '$title'" 2>/dev/null
    [ -n "$genre" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Genre '$genre'" 2>/dev/null

    # ReplayGain (always allowed - just added by rsgain)
    local rg_track_gain=$(get_value "REPLAYGAIN_TRACK_GAIN")
    local rg_track_peak=$(get_value "REPLAYGAIN_TRACK_PEAK")
    local rg_album_gain=$(get_value "REPLAYGAIN_ALBUM_GAIN")
    local rg_album_peak=$(get_value "REPLAYGAIN_ALBUM_PEAK")

    [ -n "$rg_track_gain" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_TRACK_GAIN '$rg_track_gain'" 2>/dev/null
    [ -n "$rg_track_peak" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_TRACK_PEAK '$rg_track_peak'" 2>/dev/null
    [ -n "$rg_album_gain" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_ALBUM_GAIN '$rg_album_gain'" 2>/dev/null
    [ -n "$rg_album_peak" ] && $KID3_CMD -c "select \"$filepath\"" -c "set REPLAYGAIN_ALBUM_PEAK '$rg_album_peak'" 2>/dev/null

    # Extended metadata (check if allowed)
    local year=$(get_value "Year")
    local comment=$(get_value "Comment")
    local track_num=$(get_value "Track")
    local disc_num=$(get_value "DiscNumber")
    local bpm=$(get_value "BPM")

    is_frame_allowed "TYER" && [ -n "$year" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Year '$year'" 2>/dev/null
    is_frame_allowed "COMM" && [ -n "$comment" ] && $KID3_CMD -c "select \"$filepath\"" -c "set Comment '$comment'" 2>/dev/null
    is_frame_allowed "TRCK" && [ -n "$track_num" ] && $KID3_CMD -c "select \"$filepath\"" -c "set 'Track Number' '$track_num'" 2>/dev/null
    is_frame_allowed "TPOS" && [ -n "$disc_num" ] && $KID3_CMD -c "select \"$filepath\"" -c "set 'Disc Number' '$disc_num'" 2>/dev/null
    is_frame_allowed "TBPM" && [ -n "$bpm" ] && $KID3_CMD -c "select \"$filepath\"" -c "set BPM '$bpm'" 2>/dev/null

    # Album art
    if [ "$has_album_art" = true ]; then
        $KID3_CMD -c "select \"$filepath\"" -c "set picture:'$album_art' ''" 2>/dev/null || true
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
