# ADR-001 — Shell Backend as Authoritative Write Layer

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

MusicLib needs to perform write operations — rating tracks, importing new tracks, syncing mobile playlists, rebuilding the database, cleaning tags, applying ReplayGain. These operations each orchestrate several external CLI tools (`kid3-cli`, `exiftool`, `rsgain`, `audtool`, `kdeconnect-cli`) and touch multiple data stores (DSV database, file tags, Conky assets, filesystem xattrs) in a defined order.

Two frontends exist: a Qt/KDE GUI (`musiclib`) and a C++ CLI dispatcher (`musiclib-cli`). Both need identical business logic.

The question is where that logic lives.

---

## Options Considered

**A. Reimplement operations in C++ inside each frontend**  
Both GUI and CLI contain the full write logic. No shell scripts.

**B. Shell scripts as authoritative backend; frontends are thin clients**  
All write logic lives in `bin/*.sh`. GUI and CLI invoke scripts via process call and forward exit codes.

**C. Hybrid: C++ shared library for hot-path ops, shell for maintenance**  
Described in ARCHITECTURE.md §12 as a future migration path.

---

## Decision

**Option B.** Shell scripts in `bin/` are the single authoritative implementation of all write operations. The GUI and CLI do not reimplement business logic — they invoke scripts via `QProcess` / `exec()` and forward exit codes transparently.

---

## Rationale

- **No duplication**: one implementation tested in one place, consumed by two frontends.
- **Shell-native tooling**: `kid3-cli`, `exiftool`, `audtool`, `kdeconnect-cli` all have excellent CLI interfaces; wrapping them in bash is cheaper than binding them in C++.
- **Proven stability**: the 11 backend scripts were battle-tested before the GUI existed.
- **Rapid iteration**: new features prototype faster in bash than C++.
- **Transparency**: operations are inspectable and scriptable by the user without the GUI.

**Accepted costs**:
- Script invocation overhead (~15–20ms per call) is acceptable for non-critical-path operations.
- No <50ms latency guarantee. Acceptable for v0.1–v0.3; revisit if profiling demands it.
- Bash is untyped — mitigated by `set -euo pipefail` and the JSON error contract (ADR-006).

---

## Consequences

- Every new write operation must be implemented in `bin/` first, then exposed via a CLI subcommand and a GUI `QProcess` call.
- `src/cli/` and `src/gui/` must never contain duplicated write logic.
- Option C (C++ shared library) remains the documented migration path for v1.1+ if hot-path latency becomes a real user complaint.

---

## See Also

- ARCHITECTURE.md §8.1 — full rationale with pros/cons table  
- ADR-002 — thin CLI dispatcher consequence of this decision  
- ADR-003 — DSV storage, also shell-friendly by design
