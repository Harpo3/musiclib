# ADR-005 — rename(2) / .tmp+mv for Crash-Safe DSV Writes

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

DSV writes rewrite the entire file (awk reads the current DSV, emits a modified version). If a script is killed between opening the output file for writing and finishing the write, the partial output replaces the original — data is corrupted or lost.

`flock` (ADR-004) serializes concurrent writers but provides no protection against a mid-write crash. A separate atomicity mechanism is needed.

---

## Decision

All DSV writes use the `.tmp` + `mv` (rename) pattern:

1. Write the new DSV content to `${MUSICDB}.tmp`
2. On completion, `mv "${MUSICDB}.tmp" "${MUSICDB}"`

`rename(2)` is atomic on POSIX-compliant local filesystems — the DSV file is either the old version or the new version; there is no in-between state visible to readers.

**Scripts using this pattern** (crash-safe):
- `musiclib_rate.sh` — rating/GroupDesc DSV update
- `musiclib_utils.sh` — all `update_*` and `delete_record_by_path` helpers
- `musiclib_edit_field.sh` — single-field in-place update
- `musiclib_remove_record.sh` — row removal rewrite
- `musiclib_new_tracks.sh` — `add_track_to_database` (converted from direct `>>` append)

---

## Rationale

- `rename(2)` is atomic on local filesystems. Readers always see a complete file.
- If the process is killed after the `awk` write but before `mv`, `${MUSICDB}.tmp` is left orphaned. `${MUSICDB}` is untouched. The `.tmp` file is cleaned up on the next successful run.
- This is the standard "write-then-rename" pattern used by databases and editors for crash safety.

**What this does not protect against**: two concurrent writers both writing to `.tmp` simultaneously. That case is prevented by ADR-004 (`flock`), which ensures only one writer runs at a time.

---

## Consequences

- The `.tmp` file must always be on the same filesystem as the DSV (so `rename` is atomic, not a copy+delete). Both live in `~/.local/share/musiclib/data/` — this is guaranteed by construction.
- Any new script that rewrites the DSV must use this pattern. Direct overwrites (`> "$MUSICDB"`) are a bug.
- At startup, a stale `musiclib.dsv.tmp` is safe to delete — the authoritative state is always in `musiclib.dsv`.

**Unverified**: `musiclib_mobile.sh` accounting write paths have not been fully audited for `.tmp` + `mv` compliance. Treat as potentially unsafe until confirmed. See `deliverables/TASK_LIST.md`.

---

## See Also

- BACKEND_API.md §1.3.4 — crash safety model and script audit status  
- ADR-004 — flock serialization (the concurrent-writer problem this doesn't solve)  
- ADR-003 — DSV database (the store this pattern protects)
