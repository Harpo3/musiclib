# ADR-007 — Bash-Sourceable Key=Value Config Over KConfig

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

MusicLib needs a configuration store readable by both shell scripts and the Qt/KDE GUI. KDE Frameworks provides KConfig, which is the natural choice for Qt applications. But shell scripts cannot use KConfig — they have no Qt dependency.

---

## Options Considered

**A. KConfig only**  
Native Qt/KDE integration. Shell scripts would need `kreadconfig5`/`kreadconfig6` calls — slow, and not all config variables map cleanly to KConfig groups.

**B. Bash-sourceable key=value file (`musiclib.conf`)**  
Scripts `source` the file directly; values become shell variables. The GUI reads the same file and mirrors needed values into KConfig for Qt settings dialogs.

**C. Two separate stores (KConfig for GUI, INI file for scripts)**  
Duplication; sync bugs inevitable.

---

## Decision

**Option B.** `musiclib.conf` is a bash-sourceable `KEY=VALUE` file. It is the single source of truth for all configuration shared between scripts and the GUI.

- **System defaults**: `/usr/lib/musiclib/config/musiclib.conf`
- **User overrides**: `~/.config/musiclib/musiclib.conf`

Scripts load config via `musiclib_utils.sh::load_config()`, which sources the user file (falling back to system defaults for missing keys).

**GUI-only preferences** (poll interval, tray close behavior, start minimized) are stored in KConfig (`~/.config/musiclibrc`) — they have no meaning to shell scripts and don't belong in `musiclib.conf`.

---

## Rationale

- **No Qt dependency in scripts.** Scripts run standalone — they can't link Qt.
- **Direct source is fast.** `source musiclib.conf` is faster than spawning `kreadconfig6` for each variable.
- **Single store eliminates sync bugs.** Scripts and GUI always read the same values; no translation layer.
- **Human-readable.** Users and the setup wizard can read and write it with a text editor or `sed`.

**Accepted cost**: the GUI must read a non-KConfig file for shared preferences. This is handled in `musiclib_init_config.sh` / the C++ config layer, which reads `musiclib.conf` on startup and exposes values to Qt code.

---

## Consequences

- `musiclib.conf` must remain bash-sourceable — no colons in keys, no unquoted special characters in values, no sections.
- The C++ GUI must never write GUI-only preferences (tray behavior, poll interval) to `musiclib.conf`. Those go to `~/.config/musiclibrc` via KConfig.
- CD ripping settings (`K3B_*`, `K3B_ENCODER_FORMAT`, etc.) are stored in `musiclib.conf` but are only read by the C++ `CDRippingPanel` and `patch_k3brc()` — shell scripts do not read them.
- When new config variables are added, they must be documented in BACKEND_API.md §1.5.

---

## See Also

- ARCHITECTURE.md §4.3 — configuration storage rationale  
- BACKEND_API.md §1.5 — full list of config variables  
- ADR-001 — shell backend (the reason scripts need direct config access)
