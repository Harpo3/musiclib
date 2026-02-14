#!/bin/bash
#
# test_diagnose_corruption.sh - Diagnose tag corruption and test repair strategies
#
# This script analyzes the corrupted Johnny Cash file to determine:
# 1. Which tags are readable and which are corrupted
# 2. Which tools can extract metadata
# 3. Whether tag removal is possible
# 4. What a successful repair would look like
#

set -e
export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS 2>/dev/null || true


# Test file and database data
TEST_FILE="/mnt/music/Music/johnny_cash/at_san_quentin/11_-_johnny_cash_-_a_boy_named_sue.mp3"
DB_DATA="6903^Johnny Cash^1133^At San Quentin^^A Boy Named Sue^/mnt/music/Music/johnny_cash/at_san_quentin/11_-_johnny_cash_-_a_boy_named_sue.mp3^1960s Country/Rock^338000^153^Cash^3^43353.9598958333"

# Parse database values
IFS='^' read -r DB_ID DB_ARTIST DB_IDALBUM DB_ALBUM DB_ALBUMARTIST DB_TITLE DB_PATH DB_GENRE DB_LENGTH DB_RATING DB_CUSTOM2 DB_GROUPDESC DB_LASTPLAYED DB_EXTRA <<< "$DB_DATA"

echo "=========================================="
echo "MusicLib Tag Corruption Diagnostic"
echo "=========================================="
echo ""
echo "Test File: $TEST_FILE"
echo "Database Record ID: $DB_ID"
echo ""

# Check file exists
if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: Test file not found!"
    exit 1
fi

echo "File exists: $(ls -lh "$TEST_FILE" | awk '{print $5}')"
echo ""

# Create temporary working directory
WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"
echo ""

# ==========================================
# PHASE 1: Tag Reading Analysis
# ==========================================
echo "=========================================="
echo "PHASE 1: Tag Reading Analysis"
echo "=========================================="
echo ""

# Test 1: exiftool
echo "--- Test 1A: exiftool (full metadata) ---"
if command -v exiftool >/dev/null 2>&1; then
    exiftool "$TEST_FILE" > "$WORK_DIR/exiftool_full.txt" 2>&1
    echo "Output saved to: $WORK_DIR/exiftool_full.txt"
    echo ""
    echo "Key tags found by exiftool:"
    grep -E "^(Artist|Album|Title|Genre|Comment|Year|Original Release|POPM|Grouping|Songs-DB|REPLAYGAIN)" "$WORK_DIR/exiftool_full.txt" || echo "  (No standard tags found)"
    echo ""
else
    echo "exiftool not available"
    echo ""
fi

echo "--- Test 1B: exiftool (JSON format) ---"
if command -v exiftool >/dev/null 2>&1; then
    exiftool -json "$TEST_FILE" > "$WORK_DIR/exiftool_json.txt" 2>&1
    echo "JSON output saved to: $WORK_DIR/exiftool_json.txt"
    echo ""
else
    echo "exiftool not available"
    echo ""
fi

# Test 2: kid3-cli
echo "--- Test 2: kid3-cli (get all tags) ---"
if command -v kid3-cli >/dev/null 2>&1; then
    kid3-cli -c "select \"$TEST_FILE\"" -c "get" > "$WORK_DIR/kid3_get.txt" 2>&1
    echo "Output saved to: $WORK_DIR/kid3_get.txt"
    echo ""
    echo "Key tags found by kid3-cli:"
    grep -E "^\s*(Artist|Album|Title|Genre|Comment|Year|Rating|Grouping|Songs-DB|REPLAYGAIN)" "$WORK_DIR/kid3_get.txt" || echo "  (No standard tags found)"
    echo ""
    
    # Test specific tag reads
    echo "Attempting to read Songs-DB_Custom1 (LastTimePlayed):"
    kid3-cli -c "select \"$TEST_FILE\"" -c "get Songs-DB_Custom1" 2>&1 | tee "$WORK_DIR/kid3_custom1.txt"
    echo ""
    
    echo "Attempting to read POPM (Rating):"
    kid3-cli -c "select \"$TEST_FILE\"" -c "get POPM" 2>&1 | tee "$WORK_DIR/kid3_popm.txt"
    echo ""
else
    echo "kid3-cli not available"
    echo ""
fi

# Test 3: id3v2 (if available)
echo "--- Test 3: id3v2 (list tags) ---"
if command -v id3v2 >/dev/null 2>&1; then
    id3v2 -l "$TEST_FILE" > "$WORK_DIR/id3v2_list.txt" 2>&1
    echo "Output saved to: $WORK_DIR/id3v2_list.txt"
    cat "$WORK_DIR/id3v2_list.txt"
    echo ""
else
    echo "id3v2 not available"
    echo ""
fi

# ==========================================
# PHASE 2: Attempt Tag Write (Non-Destructive)
# ==========================================
echo "=========================================="
echo "PHASE 2: Tag Write Test"
echo "=========================================="
echo ""

echo "--- Test 4: Attempt to write Songs-DB_Custom1 ---"
echo "Attempting: kid3-cli -c \"set Songs-DB_Custom1 $DB_LASTPLAYED\""
echo ""
if kid3-cli -c "select \"$TEST_FILE\"" -c "set Songs-DB_Custom1 $DB_LASTPLAYED" 2>&1 | tee "$WORK_DIR/write_test.txt"; then
    echo ""
    echo "Write command completed. Checking if it actually worked..."
    
    # Verify write
    VERIFY=$(kid3-cli -c "select \"$TEST_FILE\"" -c "get Songs-DB_Custom1" 2>&1 | grep -v "^File:" | tr -d '\r\n' | xargs)
    echo "Current Songs-DB_Custom1 value: [$VERIFY]"
    echo "Expected value: [$DB_LASTPLAYED]"
    
    if [ "$VERIFY" = "$DB_LASTPLAYED" ]; then
        echo "✓ Write SUCCEEDED"
    else
        echo "✗ Write FAILED (command didn't error but value didn't change)"
    fi
    echo ""
else
    echo ""
    echo "✗ Write FAILED with error"
    echo ""
fi

# ==========================================
# PHASE 3: Album Art Extraction
# ==========================================
echo "=========================================="
echo "PHASE 3: Album Art Extraction"
echo "=========================================="
echo ""

echo "--- Test 5: Extract album art ---"
if command -v exiftool >/dev/null 2>&1; then
    if exiftool -Picture -b "$TEST_FILE" > "$WORK_DIR/cover.jpg" 2>/dev/null; then
        if [ -f "$WORK_DIR/cover.jpg" ] && [ -s "$WORK_DIR/cover.jpg" ]; then
            SIZE=$(stat -c%s "$WORK_DIR/cover.jpg")
            echo "✓ Album art extracted: $SIZE bytes"
            echo "  Saved to: $WORK_DIR/cover.jpg"
            
            # Check if it's valid image
            if file "$WORK_DIR/cover.jpg" | grep -q "image"; then
                echo "  File type: $(file -b "$WORK_DIR/cover.jpg")"
            else
                echo "  WARNING: Extracted data may not be valid image"
            fi
        else
            echo "✗ Album art extraction created empty file"
        fi
    else
        echo "✗ Album art extraction failed"
    fi
else
    echo "exiftool not available for art extraction"
fi
echo ""

# ==========================================
# PHASE 4: ReplayGain Detection
# ==========================================
echo "=========================================="
echo "PHASE 4: ReplayGain Tags"
echo "=========================================="
echo ""

echo "--- Test 6: Check for ReplayGain tags ---"
if command -v exiftool >/dev/null 2>&1; then
    echo "Searching for ReplayGain tags..."
    grep -i "replay.*gain\|rva2" "$WORK_DIR/exiftool_full.txt" > "$WORK_DIR/replaygain.txt" 2>/dev/null || true
    
    if [ -s "$WORK_DIR/replaygain.txt" ]; then
        echo "✓ ReplayGain tags found:"
        cat "$WORK_DIR/replaygain.txt"
    else
        echo "✗ No ReplayGain tags found"
    fi
else
    echo "exiftool not available"
fi
echo ""

# ==========================================
# PHASE 5: Tag Removal Test (on copy)
# ==========================================
echo "=========================================="
echo "PHASE 5: Tag Removal Test"
echo "=========================================="
echo ""

echo "--- Test 7: Test tag removal on a copy ---"
TEST_COPY="$WORK_DIR/test_copy.mp3"
cp "$TEST_FILE" "$TEST_COPY"
echo "Created test copy: $TEST_COPY"
echo ""

# Check initial tag count
echo "Initial tag count:"
exiftool -G1 "$TEST_COPY" 2>/dev/null | grep -c "^ID3" || echo "0"
echo ""

# Try kid3-cli removal
echo "Attempting kid3-cli tag removal..."
echo "  Removing ID3v1..."
kid3-cli -c "select \"$TEST_COPY\"" -c "tag 1" -c "remove" 2>&1 | head -5
echo "  Removing ID3v2..."
kid3-cli -c "select \"$TEST_COPY\"" -c "tag 2" -c "remove" 2>&1 | head -5
echo "  Removing APE..."
kid3-cli -c "select \"$TEST_COPY\"" -c "tag 3" -c "remove" 2>&1 | head -5
echo ""

# Check final tag count
echo "Final tag count after removal:"
TAGS_AFTER=$(exiftool -G1 "$TEST_COPY" 2>/dev/null | grep -c "^ID3" || echo "0")
echo "$TAGS_AFTER"

if [ "$TAGS_AFTER" -eq 0 ]; then
    echo "✓ All tags successfully removed"
else
    echo "✗ Some tags remain after removal"
fi
echo ""

# ==========================================
# PHASE 6: Fresh Tag Write Test
# ==========================================
echo "=========================================="
echo "PHASE 6: Fresh Tag Write Test"
echo "=========================================="
echo ""

echo "--- Test 8: Write tags to stripped file ---"
echo "Writing basic tags from database..."

# Select ID3v2.3
kid3-cli -c "select \"$TEST_COPY\"" -c "tag 2" 2>/dev/null

# Write core tags
kid3-cli -c "select \"$TEST_COPY\"" -c "set Artist '$DB_ARTIST'" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set Album '$DB_ALBUM'" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set Title '$DB_TITLE'" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set Genre '$DB_GENRE'" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set POPM $DB_RATING" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set Grouping $DB_GROUPDESC" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set Songs-DB_Custom1 $DB_LASTPLAYED" 2>&1 | head -3
kid3-cli -c "select \"$TEST_COPY\"" -c "set Songs-DB_Custom2 '$DB_CUSTOM2'" 2>&1 | head -3

echo ""
echo "Verifying written tags..."
kid3-cli -c "select \"$TEST_COPY\"" -c "get" > "$WORK_DIR/rebuilt_tags.txt" 2>&1
echo "Full tag list saved to: $WORK_DIR/rebuilt_tags.txt"
echo ""
echo "Key tags after rebuild:"
grep -E "^\s*(Artist|Album|Title|Genre|Rating|Grouping|Songs-DB)" "$WORK_DIR/rebuilt_tags.txt" || echo "  (No tags found)"
echo ""

# Verify specific critical tag
REBUILT_CUSTOM1=$(kid3-cli -c "select \"$TEST_COPY\"" -c "get Songs-DB_Custom1" 2>&1 | grep -v "^File:" | tr -d '\r\n' | xargs)
echo "Songs-DB_Custom1 verification:"
echo "  Written: $DB_LASTPLAYED"
echo "  Read back: $REBUILT_CUSTOM1"

if [ "$REBUILT_CUSTOM1" = "$DB_LASTPLAYED" ]; then
    echo "  ✓ Critical tag write/read successful!"
else
    echo "  ✗ Critical tag write/read failed"
fi
echo ""

# ==========================================
# PHASE 7: Database Values Summary
# ==========================================
echo "=========================================="
echo "PHASE 7: Database Reference Values"
echo "=========================================="
echo ""

echo "Database record (ID: $DB_ID):"
echo "  Artist: $DB_ARTIST"
echo "  Album: $DB_ALBUM"
echo "  AlbumArtist: $DB_ALBUMARTIST"
echo "  Title: $DB_TITLE"
echo "  Genre: $DB_GENRE"
echo "  SongLength: $DB_LENGTH ms"
echo "  Rating (POPM): $DB_RATING"
echo "  Custom2: $DB_CUSTOM2"
echo "  GroupDesc: $DB_GROUPDESC"
echo "  LastTimePlayed: $DB_LASTPLAYED"
echo ""

# Convert SQL time to human readable
if command -v bc >/dev/null 2>&1; then
    EPOCH=$(echo "($DB_LASTPLAYED - 25569) * 86400" | bc | cut -d. -f1)
    HUMAN_DATE=$(date -d "@$EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")
    echo "  LastTimePlayed (human): $HUMAN_DATE"
    echo ""
fi

# ==========================================
# SUMMARY AND RECOMMENDATIONS
# ==========================================
echo "=========================================="
echo "DIAGNOSTIC SUMMARY"
echo "=========================================="
echo ""

echo "Test files created in: $WORK_DIR"
echo ""
echo "Key files for review:"
echo "  - exiftool_full.txt: Complete exiftool output"
echo "  - kid3_get.txt: Complete kid3-cli tag list"
echo "  - write_test.txt: Tag write attempt output"
echo "  - rebuilt_tags.txt: Tags after strip & rebuild"
echo "  - test_copy.mp3: Test file with rebuilt tags"
echo ""

echo "To review results:"
echo "  cat $WORK_DIR/exiftool_full.txt"
echo "  cat $WORK_DIR/kid3_get.txt"
echo ""

echo "To compare original vs rebuilt:"
echo "  diff <(exiftool \"$TEST_FILE\") <(exiftool \"$TEST_COPY\")"
echo ""

echo "To keep test files for analysis:"
echo "  cp -r $WORK_DIR ~/musiclib/logs/diagnostic_$(date +%Y%m%d_%H%M%S)"
echo ""

echo "To clean up:"
echo "  rm -rf $WORK_DIR"
echo ""

echo "=========================================="
echo "Diagnostic complete!"
echo "=========================================="
