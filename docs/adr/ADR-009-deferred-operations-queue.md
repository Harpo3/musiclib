# ADR-009 — Deferred Operations Queue (Exit Code 3)

**Date**: 2026-04-30  
**Status**: Proposed  
**Deciders**: Louis (sole maintainer)

---

## Context

When the DSV lock times out (ADR-004), the current system exits with code 2 (system error) and shows the user an error dialog. The operation is lost — the user must manually retry.

This happens when:
- Audacious song-change hook holds the lock while the user rates a track
- A rebuild runs while a rating is attempted
- Two operations land within the same 5-second window

The user experience is poor: a visible error for a transient condition. The data is also at risk: a keyboard shortcut rate during playback tracking is silently dropped unless the user notices and retries.

---

## Decision (Proposed)

**Not yet implemented.** The design is fully specified and exit code 3 is reserved in the error contract (ADR-006). The implementation is pending.

When implemented, the behavior will be:

1. Lock times out after `LOCK_TIMEOUT` seconds (default 5)
2. Instead of exit 2, the script writes the operation to `.pending_operations` and exits 3
3. The GUI shows a "pending" KNotification rather than an error dialog
4. `musiclib_process_pending.sh` retries the operation on the next invocation (daemon, cron, or next-write trigger)
5. On successful retry, a "completed" KNotification is shown

**Pending operations file format** (`~/.local/share/musiclib/data/.pending_operations`):
```
TIMESTAMP|script|operation|remaining_args
```
Pipe-delimited, one operation per line. Current defined operation types: `rate` (from `musiclib_rate.sh`) and `add_track` (from `musiclib_new_tracks.sh`). Both are handled by `musiclib_process_pending.sh`.

**Known constraint**: a filepath containing a literal `|` would corrupt the record. No current validation guards against this.

---

## Rationale for Deferring Implementation

- The infrastructure (exit code 3, JSON error schema, GUI code path for code 3) is already in place.
- `musiclib_process_pending.sh` already handles both `rate` and `add_track` operation types.
- The remaining work is wiring: triggering the processor reliably (daemon vs. cron vs. next-write hook), and testing the retry loop under real contention.
- This is low-priority because lock contention is rare in practice (single-user desktop). The current exit-2 behavior is acceptable for v0.1.

---

## Why This ADR Exists

This entry is the most important ADR in this directory for a future collaborator or AI agent to read.

Exit code 3 and `.pending_operations` are not dead code or an oversight. They are an intentional, partially-implemented design. Without this ADR, any architecture review would flag the reserved exit code, the processor script, and the deferred code path in the GUI as "unused" candidates for deletion. They should not be deleted — they should be completed.

**Do not re-litigate** whether a deferred queue is the right approach. The alternative (blocking indefinitely) is worse. The question for future work is only: what triggers `musiclib_process_pending.sh`?

---

## Open Questions Before Implementation

1. **Retry trigger mechanism**: daemon (`musiclibd`), systemd timer, cron, or next-write event? Daemon adds a process; cron adds polling lag; next-write is simplest but may delay retry if no writes follow.
2. **Queue durability**: `.pending_operations` is a plain text file. Is it safe to have multiple writers appending concurrently without locking? (Probably yes for append — the OS guarantees atomic short writes — but needs verification.)
3. **Max retry count**: the current `queue_operation` design records `retry_count: 0` but does not increment it. A maximum retry count with dead-letter handling needs to be specified.
4. **`|` in filepaths**: the pipe delimiter is a latent bug. Consider switching to a length-prefixed or JSON format for robustness.

---

## Consequences (When Implemented)

- Scripts that currently exit 2 on lock timeout will exit 3 instead (after calling `queue_operation`).
- The GUI must distinguish code 3 from code 2 — code 3 is not an error, it is a deferred success notification.
- `musiclib_process_pending.sh` must be deployed and triggered reliably, or the queue accumulates without draining.
- The pipe-delimiter constraint on filepaths should be documented in the user manual.

---

## See Also

- ARCHITECTURE.md §5.3 — deferred operations queue design (pseudocode)  
- ARCHITECTURE.md §6.1 — exit code contract table  
- BACKEND_API.md §1.1 — exit code semantics (code 3 is fully specified here)  
- BACKEND_API.md §1.3.2 — lock timeout policy  
- BACKEND_API.md §1.6 — `.pending_operations` wire format specification  
- ADR-004 — flock locking (the problem this queue addresses)  
- ADR-006 — JSON error contract (code 3 is already part of the schema)
