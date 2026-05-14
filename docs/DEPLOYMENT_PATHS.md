# MusicLib Deployment Path Map

This is the single source of truth for where files in the project tree land after `cmake --install` (via pacman or direct install). Every file in `config/` must have a row here and a matching `install()` rule in `CMakeLists.txt`.

When a new file or subfolder is added to `config/`, update this table and `CMakeLists.txt` in the same commit.

---

## config/ → System destinations

| Source path | CMake destination | Resolves to (with PREFIX=/usr) | Status |
|---|---|---|---|
| `config/musiclib.conf` | `lib/musiclib/config` | `/usr/lib/musiclib/config/` | ✓ Installed |
| `config/tag_schema.conf` | `lib/musiclib/config` | `/usr/lib/musiclib/config/` | ✓ Installed |
| `config/dsv_schema.conf` | `lib/musiclib/config` | `/usr/lib/musiclib/config/` | ✓ Installed (via `*.conf` glob) |
| `config/k3brc` | `lib/musiclib/config` | `/usr/lib/musiclib/config/` | ✓ Installed |
| `config/servicemenus/musiclib-rate.desktop` | `share/kio/servicemenus` | `/usr/share/kio/servicemenus/` | ✓ Installed |
| `config/systemd/musiclib-mpris.service` | `lib/systemd/user` | `/usr/lib/systemd/user/` | ✓ Installed |
| `config/images/stars/*.png` | `share/musiclib/images/stars` | `/usr/share/musiclib/images/stars/` | ✓ Installed |

---

## Other installed files

| Source path | CMake destination | Resolves to (with PREFIX=/usr) | Status |
|---|---|---|---|
| `bin/*.sh` | `lib/musiclib/bin` | `/usr/lib/musiclib/bin/` | ✓ Installed |
| `desktop/org.musiclib.musiclib.desktop` | `share/applications` | `/usr/share/applications/` | ✓ Installed |
| `desktop/icons/musiclib_NxN.png` | `share/icons/hicolor/NxN/apps` | `/usr/share/icons/hicolor/NxN/apps/` | ✓ Installed |
| `man/musiclib-cli.1` | `share/man/man1` | `/usr/share/man/man1/` | ✓ Installed |

---

## Files intentionally NOT installed

| File | Reason |
|---|---|
| `config/CLAUDE.md` | Developer instructions only — not part of the package |

---

## Working configuration (development)

In normal development, the full pacman install is required because the systemd service unit file cannot be redirected. The following paths must stay in sync manually during development:

| System path | Kept in sync with |
|---|---|
| `/usr/lib/musiclib/config/` | `config/` (manual copy on change) |
| `/usr/lib/musiclib/bin/` | `bin/` (manual copy when service scripts change) |
| `~/.config/musiclib/` | `deliverables/sample_config_musiclib/musiclib/` (occasional sync) |
| `~/.local/share/musiclib/` | `deliverables/sample_local_share_musiclib/musiclib/` (occasional sync) |

Scripts in `bin/` and the CLI dispatcher in `build/bin/` run directly from the repo — no copy needed for those. The GUI binary is launched from Qt Creator.
