# ADR-002 — Thin C++ CLI Dispatcher Over Shell Scripts

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

`musiclib-cli` provides a command-line interface for all MusicLib operations. Given that the shell backend (ADR-001) is authoritative, the question is what the CLI executable should do: be a thin dispatcher into `bin/` scripts, or reimplement operations in C++ for latency or portability reasons.

---

## Options Considered

**A. CLI reimplements operations in C++**  
No script invocation; CLI calls libraries directly. Faster, but duplicates business logic already in `bin/`.

**B. CLI is a thin dispatcher**  
Parses subcommands, resolves script paths, calls scripts via `exec()` or `std::system()`, forwards exit codes verbatim.

---

## Decision

**Option B.** `musiclib-cli` is a thin dispatcher. Its only responsibilities are:

1. Parse the subcommand and arguments (`musiclib-cli rate 5 /path/to/file.mp3`)
2. Resolve the script path (`/usr/lib/musiclib/bin/musiclib_rate.sh`, with a dev fallback to `~/musiclib/bin/`)
3. Invoke the script
4. Forward the exit code transparently to the caller

The CLI adds no business logic of its own.

---

## Rationale

- **Scripts are single source of truth.** No duplication; bug fixes in `bin/` apply to both the GUI and CLI automatically.
- **Unified error handling.** Scripts produce the JSON error contract (ADR-006); the CLI doesn't need to reparse or reformat it.
- **Easier testing.** One backend to test; both frontends inherit correctness.
- **Exit code transparency.** The exit code contract (ADR-006) flows unchanged from script to CLI caller — no translation layer.

**When to revisit**: if CLI usage exceeds GUI usage significantly AND users report latency complaints on batch operations. Unlikely for the target use case.

---

## Consequences

- `src/cli/` stays small — argument parsing and path resolution only.
- Any new subcommand requires a new script in `bin/` first; the CLI entry is then a one-liner dispatch.
- Dev mode path resolution (`~/musiclib/bin/` fallback) must remain in the dispatcher to support the Qt Creator test workflow described in CLAUDE.md.

---

## See Also

- ARCHITECTURE.md §8.2 — full rationale  
- ADR-001 — shell backend, which this ADR is a direct consequence of
