#!/usr/bin/env bash
# regen_task_list.sh — regenerate deliverables/TASK_LIST.md from open items in task notes.
# Run after closing items in a task note, or after creating a new task note.
# Never edit TASK_LIST.md by hand — this script owns it.
#
# Only processes lines inside a "### Open Items" section of each note.
# Legacy notes with old Section 1–6 structure are ignored safely.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_NOTES_DIR="$REPO_ROOT/deliverables/task_notes"
OUTPUT="$REPO_ROOT/deliverables/TASK_LIST.md"

# ---------------------------------------------------------------------------
# Helper: extract lines from the ### Open Items section of a file.
# Prints "LINENO|LINE" for each line in that section.
# ---------------------------------------------------------------------------
extract_open_items_section() {
    local filepath="$1"
    local in_section=0
    local lineno=0
    while IFS= read -r line; do
        (( lineno++ )) || true
        if [[ "$line" =~ ^###[[:space:]]Open[[:space:]]Items ]]; then
            in_section=1
            continue
        fi
        # A new ### heading ends the section
        if [[ $in_section -eq 1 && "$line" =~ ^### ]]; then
            in_section=0
        fi
        if [[ $in_section -eq 1 ]]; then
            echo "${lineno}|${line}"
        fi
    done < "$filepath"
}

# ---------------------------------------------------------------------------
# 1. Validate: within Open Items sections, no [ ] item without a recognised tag
# ---------------------------------------------------------------------------
error_found=0
while IFS= read -r filepath; do
    filename="$(basename "$filepath")"
    while IFS= read -r entry; do
        lineno="${entry%%|*}"
        line="${entry#*|}"
        if [[ "$line" =~ ^-[[:space:]]\[[[:space:]]\] ]]; then
            if ! [[ "$line" =~ ^-[[:space:]]\[[[:space:]]\][[:space:]]\[(mid-flight|next|someday|wont-fix)\] ]]; then
                echo "ERROR: unrecognised or missing tag in $filename line $lineno:" >&2
                echo "  $line" >&2
                error_found=1
            fi
        fi
    done < <(extract_open_items_section "$filepath")
done < <(find "$TASK_NOTES_DIR" -maxdepth 1 -name "task_note_*.md" | sort)

if [[ "$error_found" -ne 0 ]]; then
    echo "Aborting: fix the above items before regenerating." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Collect open items — only from ### Open Items sections
#    Skip [wont-fix] and [x] lines
# ---------------------------------------------------------------------------
declare -a mf_lines=() next_lines=() someday_lines=()

while IFS= read -r filepath; do
    filename="$(basename "$filepath")"
    while IFS= read -r entry; do
        line="${entry#*|}"
        # Only process open-checkbox lines with an actionable tag
        if [[ "$line" =~ ^-[[:space:]]\[[[:space:]]\][[:space:]]\[(mid-flight|next|someday)\] ]]; then
            tag="${BASH_REMATCH[1]}"

            # Extract added-date for sorting (format: *added YYYY-MM-DD*)
            added_date=""
            if [[ "$line" =~ \*added[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2})\* ]]; then
                added_date="${BASH_REMATCH[1]}"
            fi

            # Append source attribution if not already present
            out_line="$line"
            if ! [[ "$out_line" =~ source: ]]; then
                out_line="${out_line%"${out_line##*[![:space:]]}"}"
                out_line="$out_line — *source: $filename*"
            fi

            sort_key="${added_date:-9999-99-99}|${out_line}"

            case "$tag" in
                mid-flight) mf_lines+=("$sort_key") ;;
                next)       next_lines+=("$sort_key") ;;
                someday)    someday_lines+=("$sort_key") ;;
            esac
        fi
    done < <(extract_open_items_section "$filepath")
done < <(find "$TASK_NOTES_DIR" -maxdepth 1 -name "task_note_*.md" | sort)

# ---------------------------------------------------------------------------
# 3. Sort each bucket by date (field before |)
#    Avoid nameref + mapfile — triggers a bash 5.3 bug where mapfile writes
#    into the wrong array.  Use readarray with process substitution instead.
# ---------------------------------------------------------------------------
[[ "${#mf_lines[@]}"      -gt 0 ]] && readarray -t mf_lines      < <(printf '%s\n' "${mf_lines[@]}"      | sort -t'|' -k1,1)
[[ "${#next_lines[@]}"    -gt 0 ]] && readarray -t next_lines    < <(printf '%s\n' "${next_lines[@]}"    | sort -t'|' -k1,1)
[[ "${#someday_lines[@]}" -gt 0 ]] && readarray -t someday_lines < <(printf '%s\n' "${someday_lines[@]}" | sort -t'|' -k1,1)

# ---------------------------------------------------------------------------
# 4. Write TASK_LIST.md
# ---------------------------------------------------------------------------
{
    printf '%s\n' '# MusicLib Running Task List'
    printf '%s\n' ''
    printf '%s\n' 'Generated by `scripts/regen_task_list.sh` from open items in `deliverables/task_notes/`.'
    printf '%s\n' 'Do not edit by hand. Run the regenerator after closing items in a task note.'
    printf '%s\n' ''
    printf '%s\n' '---'
    printf '%s\n' ''
    printf '%s\n' '## Mid-flight'

    if [[ "${#mf_lines[@]}" -gt 0 ]]; then
        for entry in "${mf_lines[@]}"; do
            echo "${entry#*|}"
        done
    else
        echo "*(none)*"
    fi

    printf '\n## Next\n'
    if [[ "${#next_lines[@]}" -gt 0 ]]; then
        for entry in "${next_lines[@]}"; do
            echo "${entry#*|}"
        done
    else
        echo "*(none)*"
    fi

    printf '\n## Someday\n'
    if [[ "${#someday_lines[@]}" -gt 0 ]]; then
        for entry in "${someday_lines[@]}"; do
            echo "${entry#*|}"
        done
    else
        echo "*(none)*"
    fi
} > "$OUTPUT"

echo "TASK_LIST.md regenerated — $(wc -l < "$OUTPUT") lines."
