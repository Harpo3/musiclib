# MusicLib Development Guide

**For**: Solo developers and contributors working on MusicLib  
**Audience**: Casual coders with basic knowledge of bash, C++, and CMake  
**Last Updated**: 2026-02-10

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
│  • musiclib-qt  (Qt6/KDE GUI)       │
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

#### Option 1: Lightweight (Recommended for Phase 1)

Use your existing editor with language server support:

```bash
sudo pacman -S clangd
```

Configure your editor (Vim, Neovim, VS Code, etc.) to use `clangd` for C++ completion and diagnostics.

#### Option 2: QtCreator (Recommended for Phase 2+)

When you reach Phase 2 (GUI development), QtCreator becomes valuable:

```bash
sudo pacman -S qtcreator
```

**Why wait until Phase 2?**
- Phase 1 (CLI dispatcher) is mostly argument parsing and `QProcess` wrappers—straightforward code
- Phase 2 (GUI) involves QTreeView hierarchies, custom delegates for star ratings, layout management—QtCreator's visual tools save time here

**Size**: ~200MB. Modest cost for a tool that eliminates trial-and-error with Qt layouts.

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

### Phase 1: CLI Dispatcher Only

During Phase 1, you're building just the `musiclib-cli` dispatcher:

```bash
# Configure with CMake
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_GUI=OFF

# Build
make -j$(nproc)

# Optional: Run tests (once written)
make test
```

**CMake Options Explained**:
- `-DCMAKE_BUILD_TYPE=Debug` — includes debug symbols, no optimization (use `Release` for final builds)
- `-DCMAKE_INSTALL_PREFIX=/usr` — matches Arch FHS (Filesystem Hierarchy Standard)
- `-DBUILD_GUI=OFF` — skip GUI compilation (speeds up Phase 1 development)

**Expected Outputs**:
- `build/musiclib-cli` — the CLI dispatcher binary

### Phase 2+: CLI + GUI

Once GUI development begins:

```bash
# Configure with GUI enabled
cmake .. \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DBUILD_GUI=ON

# Build both CLI and GUI
make -j$(nproc)
```

**Expected Outputs**:
- `build/musiclib-cli` — CLI dispatcher
- `build/musiclib-qt` — Qt6/KDE GUI application

### Installation

**Development Install** (installs to `/usr` but from your build directory):

```bash
sudo make install
```

**What gets installed**:
- `/usr/bin/musiclib-cli`
- `/usr/bin/musiclib-qt` (if GUI built)
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
./musiclib-qt
```

**Important**: When running from the build directory, the CLI/GUI will look for shell scripts in:
1. `../scripts/` (relative to binary location)
2. `/usr/lib/musiclib/bin/` (installed location)

So you can develop C++ code without reinstalling scripts on every build.

### Typical Development Cycle

#### Phase 1 (CLI Dispatcher)

```bash
# 1. Edit CLI source code
vim src/cli/main.cpp

# 2. Rebuild
cd build && make -j$(nproc)

# 3. Test against existing shell script
./musiclib-cli rate "/mnt/music/test.mp3" 4

# 4. Verify shell script was invoked correctly
tail -f ~/.local/share/musiclib/logs/musiclib.log
```

**What you're testing**:
- Argument parsing (does CLI correctly parse subcommand + args?)
- Script path resolution (does CLI find the shell script?)
- Process invocation (does CLI correctly exec the script with quoted args?)
- Exit code forwarding (does CLI return the script's exit code?)
- Error JSON parsing (does CLI extract and display script errors?)

#### Phase 2+ (GUI Development)

```bash
# 1. Edit GUI source code
vim src/gui/mainwindow.cpp

# 2. Rebuild
cd build && make -j$(nproc)

# 3. Launch GUI
./musiclib-qt

# 4. Interact with UI, check logs
tail -f ~/.local/share/musiclib/logs/musiclib.log
```

**What you're testing**:
- DSV parsing (does model correctly read musiclib.dsv?)
- QProcess invocation (does GUI correctly invoke scripts?)
- UI responsiveness (does progress dialog update during long operations?)
- Error dialogs (does GUI correctly display script errors?)

### Debugging

**CLI Dispatcher**:
```bash
gdb ./musiclib-cli
(gdb) run rate "/mnt/music/test.mp3" 4
```

**GUI**:
```bash
gdb ./musiclib-qt
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
├── CMakeLists.txt              # Root CMake config
├── README.md                   # User-facing documentation
├── ARCHITECTURE.md             # This file's companion (technical deep-dive)
├── PROJECT_PLAN.md             # Phased execution roadmap
├── BACKEND_API.md              # Shell script contract specification
│
├── src/
│   ├── cli/                    # Phase 1: CLI dispatcher
│   │   ├── CMakeLists.txt
│   │   ├── main.cpp            # Argument parser, script invoker
│   │   └── ...
│   │
│   ├── gui/                    # Phase 2+: Qt6/KDE GUI
│   │   ├── CMakeLists.txt
│   │   ├── main.cpp
│   │   ├── mainwindow.cpp      # Main window, library view
│   │   ├── ratingdelegate.cpp  # Star rating widget
│   │   ├── dsvparser.cpp       # musiclib.dsv parser
│   │   └── ...
│   │
│   └── common/                 # Shared utilities (if needed)
│       └── ...
│
├── scripts/                    # Shell script backend
│   ├── musiclib_utils.sh       # Core functions (config, locking, helpers)
│   ├── musiclib_utils_tag_functions.sh  # Tag repair/normalize functions
│   ├── musiclib_rate.sh        # Rating operation
│   ├── musiclib_mobile.sh      # KDE Connect sync
│   ├── musiclib_audacious.sh   # Song-change hook (automatic)
│   ├── musiclib_build.sh       # DB build/rebuild
│   ├── musiclib_tagclean.sh    # Tag cleaning
│   ├── musiclib_tagrebuild.sh  # Tag repair from DB
│   ├── musiclib_new_tracks.sh  # Import pipeline
│   ├── musiclib_init_config.sh       # Setup wizard
│   ├── musiclib_audacious_setup.sh   # Helper: Audacious plugin instructions (called by setup)
│   ├── musiclib_audacious_test.sh    # Helper: Audacious integration verification (called by setup)
│   ├── musiclib_process_pending.sh   # Deferred operation retry
│   ├── boost_album.sh          # ReplayGain loudness
│   └── audpl_scanner.sh        # Playlist cross-reference
│
├── config/                     # Reference configuration files
│   ├── musiclib.conf.example
│   ├── tag_excludes.conf
│   ├── ID3v2_frame_excludes.txt
│   └── ID3v2_frames.txt
│
├── tests/                      # Test suite
│   ├── test_lock_contention.sh
│   ├── test_tag_rebuild.sh
│   └── ...
│
├── docs/                       # Additional documentation
│   ├── GLOSSARY.md
│   ├── USER_GUIDE.md
│   └── ...
│
└── desktop/                    # Desktop integration files
    ├── org.musiclib.musiclib-qt.desktop
    ├── musiclib.svg
    └── musiclib-dolphin.desktop
```

### Key Files to Know

**For C++ Development**:
- `src/cli/main.cpp` — CLI argument parsing, script path resolution, QProcess invocation
- `src/gui/mainwindow.cpp` — Main GUI window, system tray, global shortcuts
- `src/gui/dsvparser.cpp` — Parses `musiclib.dsv` into QAbstractTableModel
- `src/gui/ratingdelegate.cpp` — Custom item delegate for inline star rating

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

### Phase 1: CLI Dispatcher Testing

**Manual Testing**:
```bash
# Build CLI
cd build && make -j$(nproc)

# Test each subcommand
./musiclib-cli --help
./musiclib-cli rate --help
./musiclib-cli rate "/mnt/music/test.mp3" 4
echo $?  # Should be 0 on success

# Test setup wizard
./musiclib-cli setup --force
echo $?  # Should be 0 on success

# Test new-tracks (dry run)
./musiclib-cli new-tracks "test_artist" --dry-run
echo $?

# Test tagrebuild (dry run)
./musiclib-cli tagrebuild "/mnt/music/test_dir" --dry-run
echo $?

# Test error handling
./musiclib-cli rate "/nonexistent.mp3" 4
echo $?  # Should be 1 (user error)
```

**Automated Testing** (once test framework is set up):
```bash
cd build
make test
```

### Phase 2+: GUI Testing

**Manual Testing**:
```bash
# Launch GUI
./musiclib-qt

# Test workflows:
# 1. Library view loads DSV correctly
# 2. Star rating delegate works (click stars)
# 3. Maintenance panel invokes scripts
# 4. Error dialogs display script errors
```

**Qt Test Framework** (when implemented):
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

Example: Adding a "Statistics" panel in Phase 3+.

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
   ./musiclib-qt
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

# CLI only (Phase 1)
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
./musiclib-qt

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
/usr/bin/musiclib-qt

# Installed scripts
/usr/lib/musiclib/bin/
```

---

## Next Steps

Now that your build environment is set up:

1. **Familiarize yourself with the codebase**:
   - Read `ARCHITECTURE.md` for the big picture
   - Read `PROJECT_PLAN.md` for the phased roadmap
   - Read `BACKEND_API.md` for the shell script contract

2. **Start Phase 1 development**:
   - Create `src/cli/` directory
   - Implement argument parser (subcommands: `setup`, `rate`, `build`, `new-tracks`, `tagclean`, `tagrebuild`, `mobile`, `boost`, `scan`, `audacious-hook`, `process-pending`)
   - Implement script path resolution
   - Implement QProcess invocation with stdout/stderr capture
   - Test against existing shell scripts

3. **As you work**:
   - Update this document if you discover better workflows
   - Document any build issues you encounter (for future you or contributors)
   - Keep `BACKEND_API.md` updated if you modify script contracts

---

## Contributing

This is currently a solo project, but if you're reading this as a potential contributor:

1. **Read the docs**: Start with `README.md` → `ARCHITECTURE.md` → this file
2. **Check the project plan**: See `PROJECT_PLAN.md` to understand what phase we're in
3. **Follow the existing patterns**: C++ code invokes scripts, scripts do the real work
4. **Test your changes**: Manual testing is fine for now, automated tests will come later
5. **Update documentation**: If you add features, update relevant `.md` files

---

**Document Version**: 1.1  
**Last Updated**: 2026-02-14  
**Status**: Updated for Phase 0 CLI argument parser resolution
