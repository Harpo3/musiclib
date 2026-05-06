# ADR-006 — JSON Error Contract on stderr for All Script Failures

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

Two frontends (GUI and CLI) invoke shell scripts and must display meaningful errors to the user. Scripts can fail in three distinct ways: user/validation errors, system/operational errors, and deferred-queue events. The frontends need structured data — not raw text — to display appropriate dialogs, notifications, or log entries.

---

## Decision

On any non-zero exit (codes 1, 2, or 3), scripts output a JSON object to **stderr**. stdout remains clean for machine-parseable progress output (e.g., `ACCOUNTING: Track N/M:` lines parsed by the mobile panel).

**Schema**:
```json
{
  "error": "Human-readable error message",
  "script": "musiclib_rate.sh",
  "code": 1,
  "context": {
    "key": "value"
  },
  "timestamp": "2026-02-07T18:45:23Z"
}
```

**Exit code semantics**:

| Code | Meaning | GUI response | CLI response |
|------|---------|-------------|-------------|
| 0 | Success | KNotification (success), refresh view | Print success |
| 1 | User/validation error | Warning dialog (user-fixable) | Print error, suggest fix |
| 2 | System/operational error | Error dialog, suggest checking logs | Print error, suggest logs |
| 3 | Deferred | "Pending" KNotification | Print "Queued for retry" |

Scripts emit JSON via `error_exit()` in `musiclib_utils.sh`:
```bash
error_exit exit_code "Human-readable message" [context_key context_value ...]
```

---

## Rationale

- **Structured errors enable UI-appropriate responses.** The GUI shows a warning dialog for code 1 (user can fix it) vs. a critical dialog with a log path for code 2 (likely needs admin/debugging).
- **stderr separation** keeps stdout clean for progress parsing. The mobile panel's `parseProgressLine()` reads stdout; mixing error text there would break progress bar parsing.
- **Consistent format** means the GUI's `QJsonDocument::fromJson(process.readAllStandardError())` path handles all scripts without per-script parsing logic.
- **Only four exit codes** (0–3). Scripts must not use any other values. This is enforced by convention and documented in BACKEND_API.md §1.1.

---

## Consequences

- Every script must `source musiclib_utils.sh` and use `error_exit` rather than raw `echo` + `exit`.
- JSON must be valid: no raw newlines in strings, all values strings, timestamp in UTC ISO8601. `jq` or careful `printf` must be used — string concatenation with unescaped values is a bug.
- The GUI's error-handling code path (`MusicLibProcess::onFinished()` or equivalent) must never assume exit code 2 means a specific thing — it must read `"code"` from the JSON for routing.
- `context` values must be strings. Numbers and arrays must be converted before embedding.

---

## See Also

- BACKEND_API.md §1.1 — exit code table  
- BACKEND_API.md §1.2 — full JSON schema with examples  
- ADR-009 — exit code 3 / deferred queue (the proposed extension to this contract)
