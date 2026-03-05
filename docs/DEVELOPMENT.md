# MusicLib Development Guide

**For**: Solo developers and contributors working on MusicLib
**Audience**: Casual coders with basic knowledge of bash, C++, and CMake
**Last Updated**: 2026-03-05

---

## Table of Contents

1. [Architecture Quick Reference](#architecture-quick-reference)
2. [Build Environment Setup](#build-environment-setup)
3. [Building the Project](#building-the-project)
4. [Development Workflow](#development-workflow)
5. [Project Structure](#project-structure)
6. [Testing](#testing)
7. [Common Tasks](#common-tasks)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Quick Reference

MusicLib uses a **hybrid architecture**:

```
┌─────────────────────────────────────┐
│  User Interfaces                    │
│  • musiclib  (Qt6/KDE GUI)       │
│  • musiclib-cli (C++ CLI dispatcher)│
└──────────────┬──────────────────────┘
               │ QProcess / exec()
               ▼
┌─────────────────────────────────────┐
│  Shell Script Backend               │
│  /usr/lib/musiclib/bin/             │
│  • musiclib_rate.sh                 │
│  • musiclib_mobile.sh               │
│  • musiclib_rebuild.sh              │
│  • (and 8 more scripts)             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  External Tools                     │
│  kid3-cli, audtool, kdeconnect-cli  │
└─────────────────────────────────────┘
```

**Key Insight**: The C++ components (CLI and GUI) are **thin wrappers** that invoke shell scripts. The shell scripts are the authoritative backend—they handle all write operations, locking, tag manipulation, and external tool orchestration.

**What this means for development**:
- You're not rewriting the backend in C++
- C++ code focuses on: argument parsing, process execution, UI rendering
- Most business logic stays in the battle-tested shell scripts
- You can test shell scripts independently of the C++ layer

---

## Build Environment Setup

### Prerequisites

You need an **Arch Linux** system with **KDE Plasma** (Wayland or X11). MusicLib is explicitly designed for this environment and won't build on other distributions without significant modification.

### Required Packages

Install the minimal build toolchain and Qt/KDE libraries:

```bash
sudo pacman -S --needed \
  base-devel \
  gcc \
  cmake \
  git \
  qt6-base \
  qt6-svg \
  kconfig \
  knotifications \
  kio \
  kglobalaccel \
  kxmlgui
```

**Package Rationale**:
- `base-devel` — make, binutils, fakeroot (standard Arch build tools)
- `gcc` — C++ compiler (clang works too, but GCC is the default)
- `cmake` — build system (MusicLib uses CMake 3.20+)
- `git` — version control
- `qt6-base` — core Qt6 libraries (QProcess, QTreeView, etc.)
- `qt6-svg` — SVG rendering for app icon and star rating graphics
- `kconfig`, `knotifications`, `kio`, `kglobalaccel`, `kxmlgui` — KDE Frameworks 6 modules for config, notifications, file dialogs, shortcuts, menus

**What we deliberately omitted**:
- `qt6-declarative` (QML) — MusicLib uses Qt Widgets, not QtQuick
- `qt6-tools` — only needed if you want Qt Designer standalone
- `plasma-integration`, `xdg-desktop-portal-kde` — already installed on Plasma systems

### Optional Development Tools

#### Option 1: Lightweight

Use your existing editor with language server support:

```bash
sudo pacman -S clangd
```

Configure your editor (Vim, Neovim, VS Code, etc.) to use `clangd` for C++ completion and diagnostics. Works well for focused changes to CLI or shell script code.

#### Option 2: QtCreator (Recommended for GUI work)

QtCreator is valuable when working on the GUI:

```bash
sudo pacman -S qtcreator
```

The GUI involves QTreeView hierarchies, custom delegates for star ratings, KConfigXT-generated settings classes, and layout management — QtCreator's visual tools and integrated debugger save a lot of trial-and-error here.

**Size**: ~200MB. Worth it for GUI-heavy work.

### Runtime Dependencies (Shell Backend)

These tools are required at **runtime** by the shell scripts. They don't affect the C++ build, but you need them to test the full system:

```bash
# Core tools (from official repos)
sudo pacman -S \
  kid3-cli \
  perl-image-exiftool \
  audacious \
  kdeconnect \
  bc \
  bash \
  coreutils

# ReplayGain scanner (from AUR)
yay -S rsgain
```

**What each tool does**:
- `kid3-cli` — tag editing (writes POPM rating, Grouping, Songs-DB_Custom1 fields)
- `perl-image-exiftool` — album art extraction, advanced tag reading
- `audacious` — music player (controlled via `audtool`)
- `kdeconnect` — mobile device sync
- `bc` — floating-point math in shell scripts (Excel serial time calculations)
- `bash`, `coreutils` — shell environment (awk, grep, flock, etc.)
- `rsgain` — ReplayGain analysis (loudness normalization)

---

## Building the Project

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/yourusername/musiclib.git
   cd musiclib
   ```

2. **Create build directory**:
   ```bash
   mkdir build
   cd build
   ```

### Standard Build (CLI + GUI)

Both the CLI dispatcher and GUI are built together by default:

```bash
# Configure with CMake
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/usr

# Build
make -j$(nproc)

# Optional: Run tests
make test
```

**CMake Options Explained**:
- `-DCMAKE_BUILD_TYPE=Debug` — includes debug symbols, no optimization (use `Release` for final/package builds)
- `-DCMAKE_INSTALL_PREFIX=/usr` — matches Arch FHS (Filesystem Hierarchy Standard)

**Expected Outputs**:
- `build/bin/musiclib-cli` — CLI dispatcher
- `build/bin/musiclib` — Qt6/KDE GUI application

### CLI-Only Build (faster iteration on shell/CLI changes)

If you're only working on the CLI dispatcher or shell scripts and want a faster build cycle:

```bash
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_GUI=OFF

make -j$(nproc)
```

**Expected Output**: `build/bin/musiclib-cli` only.

### Installation

**Development Install** (installs to `/usr` but from your build directory):

```bash
sudo make install
```

**What gets installed**:
- `/usr/bin/musiclib-cli`
- `/usr/bin/musiclib` (if GUI built)
- `/usr/lib/musiclib/bin/` — shell scripts
- `/usr/lib/musiclib/config/` — reference configs
- `/usr/share/musiclib/` — example files
- `/usr/share/applications/` — .desktop file (GUI)

**Uninstall**:
```bash
sudo make uninstall  # Or manually remove files
```

---

## Development Workflow

### Running Without Installing

**CLI Dispatcher**:
```bash
# From build directory
./musiclib-cli --help
./musiclib-cli rate "/mnt/music/test.mp3" 4
```

**GUI**:
```bash
# From build directory
./musiclib
```

**Important**: When running from the build directory, the CLI/GUI will look for shell scripts in:
1. `../scripts/` (relative to binary location)
2. `/usr/lib/musiclib/bin/` (installed location)

So you can develop C++ code without reinstalling scripts on every build.

### Typical Development Cycle

#### CLI or Shell Script Changes

```bash
# 1. Edit CLI source or shell script
vim src/cli/main.cpp
# or: vim /usr/lib/musiclib/bin/musiclib_rate.sh

# 2. Rebuild (if C++ changed)
cd build && make -j$(nproc)

# 3. Test
./bin/musiclib-cli rate "/mnt/music/test.mp3" 4

# 4. Verify in logs
tail -f ~/.local/share/musiclib/logs/musiclib.log
```

**What you're testing**:
- Argument parsing (does CLI correctly parse subcommand + args?)
- Script path resolution (does CLI find the shell script?)
- Process invocation (does CLI correctly exec the script with quoted args?)
- Exit code forwarding (does CLI return the script's exit code?)
- Error JSON parsing (does CLI extract and display script errors?)

#### GUI Changes

```bash
# 1. Edit GUI source code
vim src/gui/mainwindow.cpp

# 2. Rebuild
cd build && make -j$(nproc)

# 3. Launch GUI
./bin/musiclib

# 4. Interact with UI, check logs
tail -f ~/.local/share/musiclib/logs/musiclib.log
```

**What you're testing**:
- DSV parsing (does model correctly read musiclib.dsv?)
- QProcess invocation (does GUI correctly invoke scripts?)
- UI responsiveness (does progress dialog update during long operations?)
- Error dialogs (does GUI correctly display script errors?)
- KConfigXT settings sync (do SettingsDialog changes update musiclib.conf?)

### Debugging

**CLI Dispatcher**:
```bash
gdb ./musiclib-cli
(gdb) run rate "/mnt/music/test.mp3" 4
```

**GUI**:
```bash
gdb ./musiclib
(gdb) run
```

**Shell Script Backend**:
```bash
# Enable bash tracing
bash -x /usr/lib/musiclib/bin/musiclib_rate.sh "/mnt/music/test.mp3" 4

# Or add to script temporarily
set -x  # Enable tracing
```

---

## Project Structure

```
musiclib/
├── CMakeLists.txt              # Root CMake config (project version 1.2)
├── README.md                   # User-facing overview
│
├── src/
│   ├── cli/                    # CLI dispatcher
│   │   ├── CMakeLists.txt
│   │   ├── main.cpp            # Argument parser, script invoker
│   │   ├── command_handler.cpp # Per-subcommand routing
│   │   ├── cli_utils.cpp       # Shared CLI helpers
│   │   └── output_streams.h   # stdout/stderr stream wrappers
│   │
│   ├── gui/                    # Qt6/KDE GUI
│   │   ├── CMakeLists.txt
│   │   ├── main.cpp
│   │   ├── mainwindow.cpp      # Main window with Dolphin-style sidebar
│   │   ├── librarymodel.cpp    # DSV data model (QAbstractTableModel)
│   │   ├── libraryview.cpp     # Library browser panel
│   │   ├── ratingdelegate.cpp  # Inline star rating widget
│   │   ├── maintenancepanel.cpp # Five maintenance operations panel
│   │   ├── albumwindow.cpp     # Album detail child window
│   │   ├── mobile_panel.cpp    # Mobile sync panel
│   │   ├── settingsdialog.cpp  # KConfigDialog (3-tab settings)
│   │   ├── configuretoolbarsdialog.cpp  # Toolbar customization dialog
│   │   ├── confwriter.cpp      # musiclib.conf reader/writer
│   │   ├── scriptrunner.cpp    # Async shell script executor
│   │   ├── systemtrayicon.cpp  # System tray icon and popup
│   │   └── musiclib.kcfg       # KConfigXT schema for GUI-only settings
│   │
│   └── common/                 # Shared utilities
│       ├── config_loader.cpp
│       ├── db_reader.cpp
│       ├── json_parser.cpp
│       ├── script_executor.cpp
│       └── utils.cpp
│
├── scripts/                    # Shell script backend
│   ├── build.sh                # Convenience build wrapper
│   ├── clean.sh                # Remove build artifacts
│   ├── install-deps.sh         # Install build + runtime dependencies
│   ├── musiclib_utils.sh       # Core functions (config, locking, helpers)
│   ├── musiclib_utils_tag_functions.sh  # Tag repair/normalize functions
│   ├── musiclib_rate.sh        # Rating operation
│   ├── musiclib_mobile.sh      # KDE Connect sync
│   ├── musiclib_audacious.sh   # Song-change hook (automatic)
│   ├── musiclib_build.sh       # DB build/rebuild
│   ├── musiclib_tagclean.sh    # Tag cleaning
│   ├── musiclib_tagrebuild.sh  # Tag repair from DB
│   ├── musiclib_new_tracks.sh  # Import pipeline
│   ├── musiclib_remove_record.sh  # Remove a DB record (with optional file delete)
│   ├── musiclib_edit_field.sh  # Edit a single metadata field in the DB
│   ├── musiclib_init_config.sh       # Setup wizard
│   ├── musiclib_audacious_setup.sh   # Helper: Audacious plugin instructions
│   ├── musiclib_audacious_test.sh    # Helper: Audacious integration verification
│   ├── musiclib_process_pending.sh   # Deferred operation retry (exit code 3 handler)
│   ├── musiclib_status.sh      # Read-only status/diagnostics
│   ├── musiclib_lock_inspector.sh    # Lock contention diagnostics
│   ├── musiclib_conky_refresh.sh     # Regenerate Conky display files on demand
│   ├── boost_album.sh          # ReplayGain loudness targeting
│   └── audpl_scanner.sh        # Playlist cross-reference CSV
│
├── docs/                       # Documentation
│   ├── ARCHITECTURE.md
│   ├── BACKEND_API.md          # Shell script contract (this doc's companion)
│   ├── DEVELOPMENT.md          # This file
│   ├── MUSICLIB_USER_MANUAL.md
│   ├── SCRIPTS_SUMMARY.md
│   └── reference/              # Supporting reference material
│
├── tests/                      # Test suite
│   ├── test_lock_contention.sh
│   ├── test_tag_rebuild.sh
│   └── ...
│
└── desktop/                    # Desktop integration files
    ├── org.musiclib.musiclib.desktop
    ├── musiclib.svg
    └── musiclib-dolphin.desktop
```

### Key Files to Know

**For C++ Development**:
- `src/cli/main.cpp` — CLI argument parsing, script path resolution, QProcess invocation
- `src/gui/mainwindow.cpp` — Main window with Dolphin-style sidebar, toolbar, status bar, now-playing polling
- `src/gui/librarymodel.cpp` — Parses `musiclib.dsv` into a `QAbstractTableModel`
- `src/gui/libraryview.cpp` — Library browser panel; filtering, context menu, inline cell editing
- `src/gui/ratingdelegate.cpp` — Custom item delegate for inline star rating
- `src/gui/scriptrunner.cpp` — Async `QProcess` wrapper for all backend scripts
- `src/gui/settingsdialog.cpp` — KConfigDialog that syncs GUI settings to `musiclib.conf`
- `src/gui/mobile_panel.cpp` — Full mobile sync panel (device scan, preview, upload, accounting)
- `src/gui/albumwindow.cpp` — Album detail child window (artwork, tracklist, last-played dates)
- `src/gui/systemtrayicon.cpp` — System tray icon, left-click popup, right-click menu

**For Shell Script Backend**:
- `scripts/musiclib_utils.sh` — **Source this first**. Contains config loading, locking helpers, error handling
- `scripts/musiclib_rate.sh` — Example operation script (rating workflow)
- `BACKEND_API.md` — Canonical specification of exit codes, JSON errors, locking protocol

**For Configuration**:
- `config/musiclib.conf.example` — User configuration template (copy to `~/.config/musiclib/musiclib.conf`)
- User data lives in `~/.local/share/musiclib/` (XDG convention)

---

## Testing

### Testing Philosophy

MusicLib's hybrid architecture allows **layered testing**:

1. **Shell scripts** — Test independently with bash test framework
2. **C++ CLI** — Test process invocation, exit code forwarding
3. **C++ GUI** — Test UI interactions, QProcess invocation
4. **Integration** — Test full workflows (GUI → script → external tool → file tag)

### CLI Dispatcher Testing

**Manual Testing**:
```bash
# Build
cd build && make -j$(nproc)

# Test each subcommand
./bin/musiclib-cli --help
./bin/musiclib-cli rate --help
./bin/musiclib-cli rate "/mnt/music/test.mp3" 4
echo $?  # Should be 0 on success

# Test setup wizard
./bin/musiclib-cli setup --force
echo $?  # Should be 0 on success

# Test new-tracks (dry run)
./bin/musiclib-cli new-tracks "test_artist" --dry-run
echo $?

# Test tagrebuild (dry run)
./bin/musiclib-cli tagrebuild "/mnt/music/test_dir" --dry-run
echo $?

# Test remove-record
./bin/musiclib-cli remove-record "/mnt/music/test.mp3"
echo $?  # 0 if record existed, 1 if not found

# Test edit-field
./bin/musiclib-cli edit-field 42 Artist "New Artist Name"
echo $?

# Test error handling
./bin/musiclib-cli rate "/nonexistent.mp3" 4
echo $?  # Should be 1 (user error)
```

**Automated Testing**:
```bash
cd build
make test
```

### GUI Testing

**Manual Testing**:
```bash
# Launch GUI
./bin/musiclib

# Test workflows:
# 1. Library view loads DSV and displays tracks correctly
# 2. Star rating delegate works (click stars in table)
# 3. Double-click cell for inline field editing
# 4. Right-click → Remove Record (with and without "Delete file")
# 5. Toolbar: Now Playing label updates, star buttons rate current track
# 6. Album button opens AlbumWindow with artwork and tracklist
# 7. Maintenance panel Preview/Execute buttons invoke scripts
# 8. Mobile panel: device scan, playlist selection, upload workflow
# 9. Settings dialog: changes sync to musiclib.conf
# 10. System tray: popup shows track, stars clickable, right-click menu works
# 11. Error dialogs display script error JSON correctly
```

**Qt Test Framework**:
```bash
cd build
make test
```

### Shell Script Testing

Shell scripts can be tested **independently** of the C++ layer:

```bash
# Test rating script directly
/usr/lib/musiclib/bin/musiclib_rate.sh "/mnt/music/test.mp3" 4
echo $?

# Test with invalid input (should exit 1)
/usr/lib/musiclib/bin/musiclib_rate.sh "/mnt/music/test.mp3" 99
echo $?

# Test setup wizard
/usr/lib/musiclib/bin/musiclib_init_config.sh --force
echo $?

# Test new-tracks import (dry run)
/usr/lib/musiclib/bin/musiclib_new_tracks.sh "test_artist" --dry-run
echo $?

# Test lock contention
cd tests
./test_lock_contention.sh
```

---

## Common Tasks

### Adding a New CLI Subcommand

Example: Adding `musiclib-cli validate` to check DB integrity.

1. **Create/update shell script** (if new operation):
   ```bash
   # Create scripts/musiclib_validate.sh
   # Follow BACKEND_API.md conventions (exit codes, JSON errors, locking)
   ```

2. **Add subcommand to CLI dispatcher**:
   ```cpp
   // src/cli/main.cpp
   if (subcommand == "validate") {
       QString scriptPath = resolveScriptPath("musiclib_validate.sh");
       QProcess process;
       process.start(scriptPath, args);
       // ... handle exit code, stderr
   }
   ```

3. **Add help text**:
   ```cpp
   if (args.contains("--help")) {
       std::cout << "Usage: musiclib-cli validate [options]\n";
       std::cout << "  Check database integrity\n";
   }
   ```

4. **Test**:
   ```bash
   cd build && make
   ./musiclib-cli validate
   ```

### Adding a GUI Panel

Example: Adding a "Statistics" panel.

1. **Create panel widget**:
   ```cpp
   // src/gui/statisticspanel.h
   class StatisticsPanel : public QWidget {
       Q_OBJECT
   public:
       StatisticsPanel(QWidget *parent = nullptr);
       // ... methods to calculate stats from DSV
   };
   ```

2. **Add to main window**:
   ```cpp
   // src/gui/mainwindow.cpp
   StatisticsPanel *statsPanel = new StatisticsPanel(this);
   tabWidget->addTab(statsPanel, "Statistics");
   ```

3. **Update CMakeLists.txt**:
   ```cmake
   # src/gui/CMakeLists.txt
   set(GUI_SOURCES
       main.cpp
       mainwindow.cpp
       statisticspanel.cpp  # Add new file
       ...
   )
   ```

4. **Build and test**:
   ```bash
   cd build && make
   ./musiclib
   ```

### Modifying Shell Script Backend

**Important**: Shell scripts are the authoritative backend. Changes here affect both CLI and GUI.

1. **Edit script** (example: changing rating scale to 0–10):
   ```bash
   vim scripts/musiclib_rate.sh
   # Update validation logic
   ```

2. **Update `BACKEND_API.md`** if contract changes:
   ```bash
   vim BACKEND_API.md
   # Document new exit codes, argument formats, etc.
   ```

3. **Test script directly**:
   ```bash
   bash -x scripts/musiclib_rate.sh "/mnt/music/test.mp3" 7
   ```

4. **Test CLI/GUI** (no recompilation needed—they invoke scripts):
   ```bash
   ./musiclib-cli rate "/mnt/music/test.mp3" 7
   ```

---

## Troubleshooting

### Problem: CLI can't find shell scripts

**Symptom**:
```
Error: Script not found: /usr/lib/musiclib/bin/musiclib_rate.sh
```

**Solutions**:
1. Install scripts: `sudo make install` (from build directory)
2. Or, temporarily symlink:
   ```bash
   sudo mkdir -p /usr/lib/musiclib/bin
   sudo ln -s $(pwd)/scripts/* /usr/lib/musiclib/bin/
   ```
3. Or, update CLI to look in dev path (if not already implemented)

### Problem: Shell script exits with code 2 (lock timeout)

**Symptom**:
```json
{
  "error": "Database lock timeout",
  "script": "musiclib_rate.sh",
  "code": 2
}
```

**Causes**:
- Another instance of MusicLib is running
- Previous script crashed without releasing lock
- Lock file has wrong permissions

**Solutions**:
1. Check for running processes:
   ```bash
   ps aux | grep musiclib
   ```
2. Manually remove stale lock:
   ```bash
   rm ~/.local/share/musiclib/data/musiclib.dsv.lock
   ```
3. Increase `LOCK_TIMEOUT` in `~/.config/musiclib/musiclib.conf`

### Problem: GUI doesn't update after rating change

**Symptom**: Star rating doesn't reflect new value after clicking.

**Likely Causes**:
- QFileSystemWatcher not monitoring DSV
- Model not refreshing on file change signal
- Script didn't actually update DSV (check exit code)

**Debug Steps**:
1. Check if DSV was updated:
   ```bash
   tail ~/.local/share/musiclib/data/musiclib.dsv
   ```
2. Check script logs:
   ```bash
   tail ~/.local/share/musiclib/logs/musiclib.log
   ```
3. Add debug output to GUI:
   ```cpp
   qDebug() << "DSV changed, refreshing model...";
   ```

### Problem: CMake can't find Qt6 or KDE Frameworks

**Symptom**:
```
CMake Error: Could not find a package configuration file provided by "Qt6"
```

**Solutions**:
1. Verify packages are installed:
   ```bash
   pacman -Q qt6-base kconfig
   ```
2. If missing, install:
   ```bash
   sudo pacman -S qt6-base kconfig knotifications kio kglobalaccel kxmlgui
   ```
3. Clear CMake cache:
   ```bash
   rm -rf build/*
   cmake .. -DCMAKE_BUILD_TYPE=Debug
   ```

### Problem: Runtime errors about missing tools

**Symptom**:
```json
{
  "error": "Required tools not available",
  "script": "musiclib_tagclean.sh",
  "code": 2,
  "context": {
    "missing": "[\"kid3-cli\"]"
  }
}
```

**Solution**: Install runtime dependencies:
```bash
sudo pacman -S kid3-cli perl-image-exiftool audacious kdeconnect bc
yay -S rsgain
```

---

## Quick Reference

### Build Commands

```bash
# Full build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)

# CLI only (faster for shell/CLI work)
cmake .. -DCMAKE_BUILD_TYPE=Debug -DBUILD_GUI=OFF
make -j$(nproc)

# Install to system
sudo make install

# Clean build
rm -rf build && mkdir build && cd build
cmake .. && make -j$(nproc)
```

### Test Commands

```bash
# Run CLI manually
./musiclib-cli rate "/mnt/music/test.mp3" 4

# Run GUI manually
./musiclib

# Test shell script directly
bash -x /usr/lib/musiclib/bin/musiclib_rate.sh "/mnt/music/test.mp3" 4

# Run automated tests (once written)
cd build && make test
```

### Useful Paths

```bash
# User config
~/.config/musiclib/musiclib.conf

# User data
~/.local/share/musiclib/data/musiclib.dsv
~/.local/share/musiclib/logs/musiclib.log

# Installed binaries
/usr/bin/musiclib-cli
/usr/bin/musiclib

# Installed scripts
/usr/lib/musiclib/bin/
```

---

## Getting Oriented

If you're new to the codebase, a good reading order:

1. `docs/ARCHITECTURE.md` — big picture, component diagrams, data flow
2. `docs/BACKEND_API.md` — shell script contract (exit codes, JSON errors, config variables)
3. `src/gui/mainwindow.h` — main window layout and signal/slot map
4. `src/gui/scriptrunner.h` — how C++ calls backend scripts
5. `scripts/musiclib_utils.sh` — the shared utility library all scripts rely on

**As you work**:
- Keep `BACKEND_API.md` updated if you add or change script invocation signatures
- If you add a new configurable setting, decide whether it belongs in `musiclib.conf` (shell-accessible) or KConfig only (GUI-only). See BACKEND_API.md section 1.5.
- Shell script changes take effect immediately without recompilation — run the script directly to test first, then verify the C++ layer picks it up correctly

---

## Contributing

1. **Read the docs**: Start with `README.md` → `ARCHITECTURE.md` → this file
2. **Follow the existing patterns**: C++ code invokes scripts, scripts do the real work
3. **Test your changes**: Manual testing as described above, plus the test suite
4. **Update documentation**: If you add features, update `BACKEND_API.md` and `SCRIPTS_SUMMARY.md`

---

**Document Version**: 1.2
**Last Updated**: 2026-03-05
**Status**: Current — reflects MusicLib v1.2
