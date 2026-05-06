# ADR-003 — Flat-File DSV Database Over SQLite

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

MusicLib needs persistent storage for track metadata: ratings, last-played timestamps, file paths, group descriptors, and any future columns. The storage must be writable from bash scripts without Qt or any external library dependency, and readable from C++ for the GUI's `QAbstractTableModel`.

---

## Options Considered

**A. SQLite**  
Structured, indexed, transactional. Requires SQLite3 binaries or libraries in scripts; schema migrations on column additions.

**B. Flat-file DSV (caret-delimited `^`)**  
Plain text, one row per track. Readable with `awk`/`grep`. No schema migrations — new columns append to the right. Concurrent writes handled manually via `flock` (ADR-004).

**C. PostgreSQL or another server-backed DB**  
Overkill for a single-user desktop app.

---

## Decision

**Option B.** The database is a flat-file DSV using `^` as the delimiter, stored at `~/.local/share/musiclib/data/musiclib.dsv`. The DSV is the **authoritative store** — all other representations (file tags, Conky assets, filesystem xattrs, Baloo index) are derived views reconstructable from it.

---

## Rationale

- **Shell-friendly**: `awk`, `grep`, and `sed` queries are trivial; no SQLite CLI dependency in scripts.
- **No schema migrations**: adding a column means appending it; existing rows have an empty field — no `ALTER TABLE`.
- **Easy backup**: `cp musiclib.dsv musiclib.dsv.backup` is the entire backup procedure.
- **Human-readable**: advanced users can inspect and manually fix rows in a text editor.
- **Linear scan is acceptable**: at <100k tracks, `awk`/`grep` over the full file is fast enough (10–50ms for a `grep` lookup; 50–200ms for a full parse in the GUI model).

**Accepted costs**:
- O(n) scans — no B-tree indexing. Acceptable for the target library size.
- Manual locking (ADR-004) instead of DB-native transactions.
- The `^` delimiter means track paths or metadata containing a literal `^` would corrupt a row. In practice, `^` does not appear in audio file paths or standard tag values.

**Migration trigger**: if library size exceeds 100k tracks AND queries become visibly slow. Not expected for the target audience.

---

## Consequences

- The DSV schema must be documented and versioned in `docs/`.
- All scripts must treat the DSV as append-only for columns — never remove or reorder existing columns.
- The GUI `LibraryModel` reads DSV directly (no backend call needed for reads); writes go through `bin/` scripts per ADR-001.
- `QFileSystemWatcher` monitors the DSV and triggers a 500ms-debounced model refresh on change.

---

## See Also

- ARCHITECTURE.md §4.3, §8.3 — full rationale  
- ADR-004 — flock locking that compensates for absent DB-native transactions  
- ADR-005 — rename(2) crash safety that compensates for absent DB-native atomicity  
- BACKEND_API.md §1.3.5 — cross-store consistency model (DSV as authority)
