#!/bin/bash
#
# test_comment_write.sh - Set comment tag on MP3 file(s)
# Usage: test_comment_write.sh <filepath_or_directory> <comment_text>
#

set -u
set -o pipefail

# Suppress Qt warnings from kid3-cli
export QT_LOGGING_RULES="qt.*.debug=false;qt.qpa.plugin.debug=false;qt.qpa.wayland.debug=false"
unset QT_DEBUG_PLUGINS

#############################################
# Usage
#############################################
show_usage() {
    cat << 'EOF'
Usage: test_comment_write.sh <filepath_or_directory> <comment_text>

Set the Comment tag on MP3 file(s).

Arguments:
  filepath_or_directory   Path to MP3 file OR directory containing MP3s
  comment_text           Comment text (enclose in quotes)

Examples:
  # Single file
  test_comment_write.sh song.mp3 "Simple comment"

  # All MP3s in a directory
  test_comment_write.sh /path/to/album "Released in 1970. Great album!"

  # Current directory
  test_comment_write.sh . "Text for all MP3s here"

Note:
  - Special characters like quotes, apostrophes work in simple cases
  - Complex punctuation may require manual cleanup
  - Only processes MP3 files (*.mp3)

Options:
  -h, --help     Show this help

EOF
}

#############################################
# Parse arguments
#############################################
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

TARGET="$1"
COMMENT="$2"

# Validate arguments
if [ -z "$TARGET" ] || [ -z "$COMMENT" ]; then
    echo "Error: Both target and comment are required" >&2
    show_usage
    exit 1
fi

# Check if target exists
if [ ! -e "$TARGET" ]; then
    echo "Error: Target not found: $TARGET" >&2
    exit 1
fi

# Check for kid3-cli
if ! command -v kid3-cli >/dev/null 2>&1; then
    echo "Error: kid3-cli not found. Please install kid3-cli first." >&2
    exit 1
fi

#############################################
# Function to set comment on a single file
#############################################
set_comment() {
    local filepath="$1"
    local comment="$2"

    echo "Processing: $(basename "$filepath")"

    # Set comment
    kid3-cli -c "set Comment '$comment'" "$filepath" 2>/dev/null

    # Quick verify
    local actual_comment=$(kid3-cli -c "get Comment" "$filepath" 2>/dev/null | grep -v "^$" | head -1)

    if [ -n "$actual_comment" ]; then
        echo "  ✓ Comment set"
    else
        echo "  ⚠ Warning: Comment may not have been set"
    fi
}

#############################################
# Process target (file or directory)
#############################################
if [ -f "$TARGET" ]; then
    # Single file
    if [[ ! "$TARGET" =~ \.(mp3|MP3)$ ]]; then
        echo "Warning: File does not have .mp3 extension: $TARGET"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    echo "Setting comment on single file:"
    echo "File: $TARGET"
    echo "Comment: $COMMENT"
    echo ""

    set_comment "$TARGET" "$COMMENT"

elif [ -d "$TARGET" ]; then
    # Directory - process all MP3 files
    shopt -s nullglob  # Don't error if no MP3s found

    # Find all MP3 files in directory (not recursive)
    MP3_FILES=("$TARGET"/*.mp3 "$TARGET"/*.MP3)

    if [ ${#MP3_FILES[@]} -eq 0 ]; then
        echo "Error: No MP3 files found in directory: $TARGET" >&2
        exit 1
    fi

    echo "Setting comment on MP3 files in directory:"
    echo "Directory: $TARGET"
    echo "Comment: $COMMENT"
    echo "Files found: ${#MP3_FILES[@]}"
    echo ""

    read -p "Continue with batch comment update? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    echo ""

    # Process each file
     count=0
     success=0
     failed=0

    for mp3_file in "${MP3_FILES[@]}"; do
        if [ -f "$mp3_file" ]; then
            count=$((count + 1))
            echo "[$count/${#MP3_FILES[@]}]"

            if set_comment "$mp3_file" "$COMMENT"; then
                success=$((success + 1))
            else
                failed=$((failed + 1))
            fi

            echo ""
        fi
    done

    echo "================================"
    echo "Batch processing complete!"
    echo "Total files: $count"
    echo "Successful: $success"
    if [ $failed -gt 0 ]; then
        echo "Failed: $failed"
    fi
    echo "================================"

else
    echo "Error: Target is neither a file nor a directory: $TARGET" >&2
    exit 1
fi

exit 0
