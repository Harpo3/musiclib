# ADR-004 — flock-Based Write Serialization for the DSV

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

Multiple processes can attempt concurrent writes to `musiclib.dsv`:

- Audacious song-change hook (`musiclib_audacious.sh`) updates `LastTimePlayed`
- User rates a track via GUI or keyboard shortcut (`musiclib_rate.sh`)
- A background rebuild runs (`musiclib_rebuild.sh`)

Without coordination, concurrent writers produce corrupted DSV files (partial writes, interleaved lines) and lost updates. Because the database is a flat file (ADR-003), it has no native transaction mechanism.

---

## Decision

All DSV writes are serialized via `flock(1)` on a companion lock file (`musiclib.dsv.lock`). Scripts access locking exclusively through the helper functions in `musiclib_utils.sh` — they do not call `flock` directly.

**API**:
```bash
with_db_lock <callback_function> [args...]   # preferred: acquires, runs, releases
acquire_db_lock                              # low-level: call before manual lock scope
release_db_lock                             # low-level: release after manual lock scope
```

**Timeout**: 5 seconds by default; configurable via `LOCK_TIMEOUT` in `musiclib.conf`.

**On timeout**: exit code 2 (system error). When the deferred queue is active (ADR-009), exit code 3 is used instead and the operation is queued.

**Lock file lifecycle**: `musiclib.dsv.lock` is created on first use and never deleted. It is an advisory lock — the file itself is never written; it exists only as a `flock` target.

---

## Rationale

- `flock` is part of `util-linux`, universally available on Linux systems.
- Advisory file locking works correctly for MusicLib's single-machine, single-user deployment model.
- The helper abstraction (`with_db_lock`) means scripts cannot accidentally skip the unlock on early exit — the `trap release_db_lock EXIT` inside the helper handles cleanup.

**Important distinction**: `flock` serializes writers. It does not protect against a mid-write crash leaving a partial file. That guarantee is provided separately by ADR-005 (`rename(2)` via `.tmp` + `mv`). Both are required; neither is sufficient alone.

---

## Consequences

- Every script that writes to the DSV must use `with_db_lock` or the acquire/release pair. Direct DSV writes without locking are a bug.
- NFS deployments are not officially supported (advisory locking on NFS requires kernel ≥2.6.12 and correct server configuration).
- The 5-second timeout is a UX choice: users will see an error after 5 seconds of contention rather than blocking indefinitely.

---

## See Also

- ARCHITECTURE.md §5.2 — implementation detail and code sample  
- ADR-003 — DSV database this lock protects  
- ADR-005 — crash-safe rename that handles the failure mode flock does not  
- ADR-009 — deferred queue: the planned response when lock timeout occurs
