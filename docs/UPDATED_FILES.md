# MusicLib Updated Files (v0.1 Transition)

This document lists all files to add, modify, remove, or replace during the transition from standalone shell scripts to the integrated CLI/GUI architecture.

---

## 1. Files to Add (New)

### 1.1 C++ Source Files (CLI Dispatcher)

```
src/cli/
  main.cpp                    # CLI entry point, argument parser
  script_runner.cpp/.h        # QProcess wrapper for script invocation
  config_loader.cpp/.h        # Read musiclib.conf, resolve paths
  subcommands/
    rate.cpp/.h               # musiclib-cli rate
    mobile.cpp/.h             # musiclib-cli mobile upload/sync/status
    build.cpp/.h              # musiclib-cli build (renamed from rebuild.cpp)
    tagclean.cpp/.h           # musiclib-cli tagclean
    tagrebuild.cpp/.h         # musiclib-cli tagrebuild (new)
    boost.cpp/.h              # musiclib-cli boost
    scan.cpp/.h               # musiclib-cli scan
    new_tracks.cpp/.h         # musiclib-cli new-tracks (renamed from add_track.cpp)
    setup.cpp/.h              # musiclib-cli setup (new)
    audacious_hook.cpp/.h     # musiclib-cli audacious-hook (new)
    process_pending.cpp/.h    # musiclib-cli process-pending (new)
```

**Changes explained:**
- `rebuild.cpp` → `build.cpp`: CLI command is `build`, not `rebuild`
- `add_track.cpp` → `new_tracks.cpp`: CLI command is `new-tracks`, not `add-track`
- Added `tagrebuild.cpp`: Routes to `musiclib_tagrebuild.sh`
- Added `setup.cpp`: Routes to `musiclib_init_config.sh`
- Added `audacious_hook.cpp`: Routes to `musiclib_audacious.sh`
- Added `process_pending.cpp`: Routes to `musiclib_process_pending.sh`

### 1.2 C++ Source Files (Qt GUI)

```
src/gui/
  main.cpp                    # GUI entry point
  mainwindow.cpp/.h           # KXmlGuiWindow main window
  models/
    library_model.cpp/.h      # QAbstractTableModel for DSV
    dsv_parser.cpp/.h         # DSV file parsing utilities
  views/
    library_view.cpp/.h       # QTreeView with custom delegate
    star_rating_delegate.cpp/.h  # Inline star rating widget
    maintenance_panel.cpp/.h  # Maintenance operations UI
    mobile_panel.cpp/.h       # Mobile sync UI
    conky_panel.cpp/.h        # Conky preview/config UI
  dialogs/
    settings_dialog.cpp/.h    # KConfigXT settings UI
    first_run_wizard.cpp/.h   # Setup wizard
    error_dialog.cpp/.h       # Unified error display
  integration/
    script_invoker.cpp/.h     # QProcess wrapper with error parsing
    tray_icon.cpp/.h          # KStatusNotifierItem
    global_shortcuts.cpp/.h   # KGlobalAccel integration
    dbus_interface.cpp/.h     # D-Bus service registration
```

### 1.3 Build System Files

```
CMakeLists.txt              # Root CMake file
src/cli/CMakeLists.txt      # CLI build config
src/gui/CMakeLists.txt      # GUI build config
cmake/
  FindKF6.cmake             # KDE Frameworks 6 detection
  Modules.cmake             # Common CMake functions
```

### 1.4 Desktop Integration Files

```
data/
  org.musiclib.musiclib-qt.desktop      # .desktop file for GUI
  org.musiclib.musiclib-qt.appdata.xml  # AppStream metadata
  musiclib-dolphin.desktop              # Dolphin service menu
  musiclib.svg                          # Application icon
```

### 1.5 Documentation Files

```
docs/
  ARCHITECTURE.md           # Architecture overview (already written)
  BACKEND_API.md            # Backend API contract (already written)
  PROJECT_PLAN.md           # Project plan (already written)
  USER_GUIDE.md             # User manual
  DEVELOPMENT.md            # Build instructions, contribution guide
  GLOSSARY.md               # Term definitions
  MIGRATION.md              # Upgrade guide from legacy layout
```

### 1.6 Test Files

```
tests/
  fixtures/
    test_db.dsv             # Minimal test database
    test_valid.mp3          # Valid MP3 with tags
    test_no_tags.mp3        # Valid MP3 without tags
    test_corrupt.mp3        # Corrupted MP3
    test_playlist.audpl     # Sample playlist
  unit/
    test_dsv_parser.cpp     # DSV parsing tests (Qt Test)
    test_library_model.cpp  # Library model tests
  integration/
    test_lock_contention.sh     # Lock stress test
    test_rating_workflow.sh     # End-to-end rating test
    test_mobile_upload.sh       # Mobile sync test
    test_rebuild.sh             # Database rebuild test
  CMakeLists.txt            # Test build config
```

### 1.7 Packaging Files

```
packaging/
  aur/
    musiclib/
      PKGBUILD              # AUR package for scripts + CLI
      musiclib.install      # Post-install message
    musiclib-qt/
      PKGBUILD              # AUR package for GUI
      musiclib-qt.install   # Post-install message
```

### 1.8 Man Pages

```
man/
  musiclib-cli.1            # CLI manual page (covers all commands: setup, audacious-hook, new-tracks, tagrebuild, boost, scan, etc.)
  musiclib-qt.1             # GUI manual page
  musiclib.conf.5           # Config file format
```

---

## 2. Files to Modify (Existing Scripts)

### 2.1 Shell Scripts (Add Exit Code Contract)

All scripts need standardized exit codes, JSON error output, and locking:

```
bin/musiclib_rate.sh
  ✓ Already has exit code contract
  ✓ Add JSON error output on failures
  ✓ Verify flock usage via with_db_lock()

bin/musiclib_mobile.sh
  ✓ Add exit code contract (currently inconsistent)
  ✓ Add JSON error output
  ✓ Add with_db_lock() for DB updates
  ✓ Support .m3u, .m3u8, .pls formats (currently .audpl only)

bin/musiclib_audacious.sh
  ✓ Already has basic exit codes
  ✓ Add JSON error output
  ✓ Verify with_db_lock() usage

bin/musiclib_new_tracks.sh
  ✓ Add exit code contract
  ✓ Add JSON error output
  ✓ Add with_db_lock()
  ✓ Support ZIP extraction (currently manual)

bin/musiclib_build.sh
  ✓ Rename from musiclib_rebuild.sh
  ✓ Add --dry-run flag
  ✓ Add JSON error output
  ✓ Strict with_db_lock() (no concurrent rebuilds)

bin/musiclib_tagrebuild.sh
  ✓ Add JSON error output
  ✓ Add with_db_lock()

bin/musiclib_tagclean.sh
  ✓ Add --mode flag (merge/strip/embed-art)
  ✓ Add JSON error output
  ✓ No DB locking needed (tag-only operations)

bin/boost_album.sh
  ✓ Add --target flag for LUFS
  ✓ Add JSON error output
  ✓ No DB locking needed (tag-only operations)

bin/audpl_scanner.sh
  ✓ Add JSON error output
  ✓ Output CSV to stdout (currently writes file)
```

### 2.2 Utility Scripts (Add Locking Functions)

```
bin/musiclib_utils.sh
  ✓ Add error_exit(code, message, [context...])
  ✓ Add acquire_db_lock()
  ✓ Add release_db_lock()
  ✓ Add with_db_lock(callback)
  ✓ Add BACKEND_API_VERSION="1.0"
  ✓ Add default XDG paths (~/.config/musiclib/, ~/.local/share/musiclib/)

bin/musiclib_utils_tag_functions.sh
  ✓ No changes needed (tag-only utilities)
```

### 2.3 Configuration File (Add XDG Defaults)

```
config/musiclib.conf
  ✓ Add XDG_CONFIG_HOME and XDG_DATA_HOME defaults
  ✓ Document LOCK_TIMEOUT variable
  ✓ Add BACKEND_API_VERSION check
  
Example additions:
  # XDG Base Directory defaults
  MUSICLIB_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/musiclib"
  MUSICLIB_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/musiclib"
  MUSICDB="${MUSICLIB_DATA_DIR}/data/musiclib.dsv"
  CONKY_OUTPUT_DIR="${MUSICLIB_DATA_DIR}/data/conky_output"
  
  # Lock timeout (seconds)
  LOCK_TIMEOUT=5
  
  # Backend API version (checked by GUI/CLI)
  BACKEND_API_VERSION="1.0"
```

---

## 3. Scripts Section (Updated)

### 3.1 Shell Scripts Directory Structure

```
scripts/
  musiclib_utils.sh                   # Core utilities and locking
  musiclib_utils_tag_functions.sh     # Tag repair/normalization
  musiclib_rate.sh                    # Star rating operations
  musiclib_mobile.sh                  # KDE Connect mobile sync
  musiclib_audacious.sh               # Audacious player hook
  musiclib_build.sh                   # Full database rebuild (renamed from musiclib_rebuild.sh)
  musiclib_tagclean.sh                # ID3 tag cleanup
  musiclib_tagrebuild.sh              # Tag repair from DB
  musiclib_new_tracks.sh              # Track import pipeline
  musiclib_init_config.sh             # Setup wizard (new)
  musiclib_audacious_setup.sh         # Setup helper for Audacious (new)
  musiclib_audacious_test.sh          # Setup helper for testing (new)
  musiclib_process_pending.sh         # Process pending operations (new)
  boost_album.sh                      # ReplayGain loudness targeting
  audpl_scanner.sh                    # Playlist scanning utility
```

---

## 4. Files to Remove (Deprecated)

### 4.1 Superseded Documentation

```
musiclib_cli_dispatcher_UPDATED.md    → Superseded by musiclib_cli_dispatcher.md v2.0
BACKEND_API_Audacious_Section.md      → Content merged into BACKEND_API.md section 2.10
```

### 4.2 Standalone Script Entry Points (If Any)

If there were standalone wrappers that are now replaced by `musiclib-cli`:

```
bin/rate_track.sh           → Replaced by musiclib-cli rate
bin/upload_playlist.sh      → Replaced by musiclib-cli mobile upload
```

*(Review actual repo to determine if such files exist)*

### 4.3 Legacy Config Locations

```
~/.musiclib.dsv             → Migrated to ~/.local/share/musiclib/data/musiclib.dsv
~/scripts/musiclib_*.sh     → Moved to /usr/lib/musiclib/bin/
```

**Migration Note**: First-run wizard detects legacy layout, offers to migrate.

---

## 5. Files to Replace (Refactored)

### 5.1 README.md

**Current**: Minimal overview, no architecture details.

**Updated**: Add sections:
- Architecture overview (GUI/CLI/scripts diagram)
- Installation (AUR packages: `musiclib`, `musiclib-qt`)
- Quick start (GUI and CLI examples)
- Configuration (XDG layout, `musiclib.conf` reference)
- CLI subcommand reference (with examples)
- Troubleshooting (common issues, log locations)

---

## 6. Summary of Changes by Phase

### Phase 0: Backend Cleanup (1–2 weeks)

**Add**:
- `bin/musiclib_utils.sh`: `error_exit()`, `with_db_lock()`, etc.
- `docs/BACKEND_API.md`
- `tests/integration/test_lock_contention.sh`

**Modify**:
- All scripts in `bin/`: Add exit codes, JSON errors, locking
- `config/musiclib.conf`: XDG defaults, `BACKEND_API_VERSION`

**Remove**: None

---

### Phase 1: CLI Dispatcher (1–2 weeks)

**Add**:
- `src/cli/` (entire directory with 11 subcommand files)
- `CMakeLists.txt` (root + CLI)
- `man/musiclib-cli.1`

**Modify**:
- `README.md`: Add CLI usage section

**Remove**: None

---

### Phase 2: GUI Core (4–6 weeks)

**Add**:
- `src/gui/` (entire directory)
- `data/org.musiclib.musiclib-qt.desktop`
- `data/musiclib.svg`
- `tests/unit/test_library_model.cpp`
- `docs/USER_GUIDE.md`

**Modify**:
- `CMakeLists.txt`: Add GUI build
- `README.md`: Add GUI quick start

**Remove**: None

---

### Phase 3: KDE Integration (3–4 weeks)

**Add**:
- `data/musiclib-dolphin.desktop`
- `src/gui/integration/dbus_interface.cpp/.h`

**Modify**:
- `src/gui/mainwindow.cpp`: Add D-Bus service registration
- `bin/musiclib_mobile.sh`: Add .m3u/.pls support

**Remove**: None

---

### Phase 4: Advanced Features (4–6 weeks)

**Add**:
- `src/krunner/` (KRunner plugin)
- `src/plasma-widget/` (QML widget)
- `src/gui/dialogs/first_run_wizard.cpp/.h`

**Modify**: None

**Remove**: None

---

### Phase 5: Packaging (2–3 weeks)

**Add**:
- `packaging/aur/musiclib/PKGBUILD`
- `packaging/aur/musiclib-qt/PKGBUILD`
- `docs/DEVELOPMENT.md`
- `docs/GLOSSARY.md`
- `docs/MIGRATION.md`

**Modify**:
- `README.md`: Add installation instructions (AUR)

**Remove**: None

---

## 7. File Count Summary

| Category | Add | Modify | Remove | Total Changed |
|----------|-----|--------|--------|---------------|
| C++ Source | 35+ | 0 | 0 | 35+ |
| Shell Scripts | 3 | 11 | 1 | 15 |
| Build System | 4 | 0 | 0 | 4 |
| Desktop Integration | 3 | 0 | 0 | 3 |
| Documentation | 6 | 1 | 2 | 9 |
| Tests | 10+ | 0 | 0 | 10+ |
| Packaging | 4 | 0 | 0 | 4 |
| **Total** | **65+** | **12** | **3** | **80+** |

---

## 8. Migration Checklist (User Perspective)

When upgrading from standalone scripts to v0.1:

**Automatic** (handled by first-run wizard):
- ✓ Migrate `~/.musiclib.dsv` → `~/.local/share/musiclib/data/musiclib.dsv`
- ✓ Copy playlists to `~/.local/share/musiclib/playlists/`
- ✓ Create XDG directory structure
- ✓ Generate `~/.config/musiclib/musiclib.conf` from defaults

**Manual** (user action required):
- ☐ Reconfigure Audacious hook:
  - Old: `/home/user/scripts/musiclib_audacious.sh`
  - New: `/usr/lib/musiclib/bin/musiclib_audacious.sh`
- ☐ Update Conky config to point to new output directory:
  - Old: `~/musiclib/data/conky_output/`
  - New: `~/.local/share/musiclib/data/conky_output/`
- ☐ Update any custom scripts/aliases that referenced old paths

**Verification**:
```bash
# Check new layout
ls ~/.config/musiclib/musiclib.conf
ls ~/.local/share/musiclib/data/musiclib.dsv

# Test CLI
musiclib-cli rate --help

# Test GUI
musiclib-qt

# Verify Audacious hook
audtool --current-song-filename  # Play a track, check Conky updates
```

---

## 9. Key Implementation Notes

### CLI Subcommand Naming Convention

All CLI commands use kebab-case (hyphens) while script and C++ file names use snake_case (underscores):

| CLI Command | C++ File | Shell Script |
|-------------|----------|--------------|
| `musiclib-cli rate` | `rate.cpp` | `musiclib_rate.sh` |
| `musiclib-cli build` | `build.cpp` | `musiclib_build.sh` |
| `musiclib-cli new-tracks` | `new_tracks.cpp` | `musiclib_new_tracks.sh` |
| `musiclib-cli tag-rebuild` | `tagrebuild.cpp` | `musiclib_tagrebuild.sh` |
| `musiclib-cli tag-clean` | `tagclean.cpp` | `musiclib_tagclean.sh` |
| `musiclib-cli audacious-hook` | `audacious_hook.cpp` | `musiclib_audacious.sh` |
| `musiclib-cli setup` | `setup.cpp` | `musiclib_init_config.sh` |
| `musiclib-cli process-pending` | `process_pending.cpp` | `musiclib_process_pending.sh` |
| `musiclib-cli boost` | `boost.cpp` | `boost_album.sh` |
| `musiclib-cli scan` | `scan.cpp` | `audpl_scanner.sh` |
| `musiclib-cli mobile` | `mobile.cpp` | `musiclib_mobile.sh` |

---

**Document Version**: 1.1  
**Last Updated**: 2026-02-14  
**Status**: Implementation-Ready
