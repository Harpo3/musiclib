# MusicLib Architecture

## Overview

MusicLib is a hybrid architecture combining a battle-tested shell script backend with modern Qt/KDE frontend interfaces. This design prioritizes stability, maintainability, and deep KDE integration while preserving the reliability of existing shell-based workflows.

**Core Principle**: **Thin clients, authoritative shell backend**. GUI and CLI are smart clients that read data directly but delegate all writes to shell scripts via process invocation.

---

## 1. Component Boundaries

### 1.1 High-Level Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      User Layer                               │
├───────────────┬──────────────────┬───────────────────────────┤
│ musiclib-qt   │  musiclib-cli    │  Desktop Integration      │
│ (Qt/KDE GUI)  │  (C++ Dispatcher)│  (Dolphin, KRunner, Tray) │
│               │                  │                            │
│ • Library View│  • rate          │  • Service Menus          │
│ • Rating UI   │  • mobile        │  • Global Shortcuts       │
│ • Maintenance │  • rebuild       │  • Plasma Widget          │
│ • Mobile Panel│  • tagclean      │  • D-Bus Interface        │
│ • Conky Panel │  • boost         │                           │
│ • Settings    │  • scan          │                           │
│               │  • add-track     │                           │
└───────┬───────┴────────┬─────────┴───────────┬───────────────┘
        │                │                     │
        │ QProcess       │ exec()              │ D-Bus / Scripts
        │                │                     │
        ▼                ▼                     ▼
┌──────────────────────────────────────────────────────────────┐
│              Process Invocation Layer                         │
│  (QProcess, std::system, D-Bus method calls)                 │
└────────────────────────┬─────────────────────────────────────┘
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                Shell Script Backend                           │
│                /usr/lib/musiclib/bin/                         │
├──────────────────────────────────────────────────────────────┤
│  Utility Layer (sourced by all scripts):                     │
│   • musiclib_utils.sh              (config, DB helpers, lock)│
│   • musiclib_utils_tag_functions.sh (tag repair/normalize)   │
├──────────────────────────────────────────────────────────────┤
│  Operation Scripts (invoked by clients):                     │
│   • musiclib_rate.sh           (rating → DSV + tags + Conky) │
│   • musiclib_mobile.sh         (KDE Connect playlist sync)   │
│   • musiclib_audacious.sh      (song-change hook → Conky)    │
│   • musiclib_new_tracks.sh     (import pipeline)             │
│   • musiclib_rebuild.sh        (full DB rebuild from scan)   │
│   • musiclib_tagrebuild.sh     (repair tags from DB)         │
│   • musiclib_tagclean.sh       (ID3v1→v2, APE removal, art)  │
│   • boost_album.sh             (ReplayGain loudness)         │
│   • audpl_scanner.sh           (playlist cross-reference)    │
└────────────────────────┬─────────────────────────────────────┘
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                  External Tools Layer                         │
├──────────────────────────────────────────────────────────────┤
│  Tag/Metadata:        kid3-cli, exiftool, rsgain             │
│  Player Control:      audtool (Audacious CLI)                │
│  Mobile Sync:         kdeconnect-cli                         │
│  File Operations:     flock, bc, readlink, awk, sed          │
│  Desktop:             kdialog, notify-send (KNotifications)  │
└────────────────────────┬─────────────────────────────────────┘
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                    Data Storage Layer                         │
├──────────────────────────────────────────────────────────────┤
│  Database:       ~/.local/share/musiclib/data/musiclib.dsv   │
│  Config:         ~/.config/musiclib/musiclib.conf            │
│  Music Files:    /mnt/music/ (or user-configured MUSIC_REPO) │
│  Playlists:      ~/.local/share/musiclib/playlists/          │
│  Conky Assets:   ~/.local/share/musiclib/data/conky_output/  │
│  Logs:           ~/.local/share/musiclib/logs/               │
│  Tag Backups:    ~/.local/share/musiclib/data/tag_backups/   │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Data Flow Patterns

### 2.1 Read Path (No Locking Required)

**Example**: GUI displays library view

```
User opens GUI
    ↓
musiclib-qt reads ~/.local/share/musiclib/data/musiclib.dsv
    ↓
Parses DSV into QAbstractTableModel
    ↓
Displays in QTreeView (sortable, filterable)
    ↓
User sees library (no backend invocation needed)
```

**Optimization**: QFileSystemWatcher monitors DSV, triggers model refresh on change (debounced 500ms).

---

### 2.2 Write Path (Shell Backend with Locking)

**Example**: User rates a track via GUI

```
User clicks 5th star on track in library view
    ↓
musiclib-qt invokes QProcess:
    /usr/lib/musiclib/bin/musiclib_rate.sh "/path/to/song.mp3" 5
    ↓
musiclib_rate.sh sources musiclib_utils.sh
    ↓
Calls with_db_lock() helper:
    • Acquires flock on musiclib.dsv.lock
    • Updates DSV (Rating column, GroupDesc column)
    • Updates file tags (POPM via kid3-cli, Grouping)
    • Regenerates Conky assets (starrating.png, detail.txt)
    • Releases lock
    ↓
Returns exit code 0 (success) to QProcess
    ↓
musiclib-qt receives exit code, shows KNotification:
    "Rated: Artist – Title (★★★★★)"
    ↓
QFileSystemWatcher detects DSV change, triggers model refresh
    ↓
Library view updates (rating column shows 5 stars)
```

**Error Handling**:
```
musiclib_rate.sh exits with code 2 (lock timeout)
    ↓
Outputs JSON to stderr:
    {"error": "Database lock timeout", "code": 2, ...}
    ↓
musiclib-qt parses JSON, shows error dialog:
    "Unable to rate track: Database lock timeout (another operation in progress)"
    ↓
Logs error to ~/.local/share/musiclib/logs/musiclib.log
```

---

### 2.3 Audacious Song-Change Hook

**Setup**: User configures Audacious hook in preferences:
```
Preferences → Plugins → Song Change → Command:
/usr/lib/musiclib/bin/musiclib_audacious.sh
```

**Flow**:
```
Audacious plays new track
    ↓
Invokes musiclib_audacious.sh
    ↓
Script queries audtool --current-song-filename
    ↓
Looks up track in musiclib.dsv by SongPath
    ↓
with_db_lock():
    • Updates LastTimePlayed in DSV (Excel serial time)
    • Updates Songs-DB_Custom1 tag in file (via kid3-cli)
    ↓
Extracts album art from file (exiftool)
    ↓
Generates Conky assets:
    • artist.txt, title.txt, album.txt, year.txt
    • lastplayed.txt (formatted timestamp)
    • starrating.png (composite image from rating)
    • folder.jpg (album art copy)
    ↓
Logs to logs/audacious/audacioushist.log
    ↓
Returns exit code 0
    ↓
Audacious continues playback
```

**Conky Integration**:
```
Conky reads ~/.local/share/musiclib/data/conky_output/artist.txt
    ↓
Displays "Now Playing: Pink Floyd – Time" on desktop
    ↓
Shows starrating.png (5-star image)
    ↓
Shows folder.jpg (album art)
```

---

### 2.4 Mobile Sync Workflow

**Example**: User uploads playlist to Android device

```
User selects "workout.audpl" in GUI Mobile panel
    ↓
Clicks "Upload" button
    ↓
musiclib-qt invokes QProcess:
    /usr/lib/musiclib/bin/musiclib_mobile.sh upload abc123def456 \
        /home/user/.local/share/musiclib/playlists/workout.audpl
    ↓
musiclib_mobile.sh:
    1. Parses workout.audpl (extracts file paths)
    2. Generates .m3u with basenames only
    3. Transfers .m3u + all MP3 files via kdeconnect-cli --share
    4. Saves metadata:
       • playlists/mobile/workout.tracks (file list)
       • playlists/mobile/workout.meta (upload timestamp)
    5. Processes previous playlist (if exists):
       • Reads previous .tracks and .meta
       • Calculates synthetic last-played times (evenly distributed)
       • with_db_lock():
           - Updates LastTimePlayed in DSV for each track
           - Updates Songs-DB_Custom1 tags via kid3-cli
    ↓
Returns exit code 0 (success)
    ↓
musiclib-qt shows success notification:
    "Uploaded 42 tracks to Samsung Galaxy S21"
    ↓
Updated last-played times appear in library view after refresh
```

**Synthetic Timestamp Logic**:
```
Upload 1 (Monday):   42 tracks uploaded
Upload 2 (Friday):   37 tracks uploaded
    ↓
On Upload 2, process Upload 1 tracks:
    • Time window: Monday → Friday (4 days = 345,600 seconds)
    • Distribute 42 tracks evenly: 345,600 / 42 ≈ 8,229 seconds apart
    • Assign timestamps: Monday + 8229s, Monday + 16458s, ...
    ↓
Result: Realistic-looking last-played distribution in library view
```

---

## 3. Filesystem Layout Details

### 3.1 System-Wide Installation

**Binaries** (`/usr/bin/`):
```
musiclib-cli       # C++ dispatcher, thin wrapper around scripts
musiclib-qt        # Qt/KDE GUI application
```

**Backend Scripts** (`/usr/lib/musiclib/bin/`):
```
musiclib_utils.sh                    # Shared utilities (config, DB, locking)
musiclib_utils_tag_functions.sh      # Tag repair/normalization
musiclib_rate.sh                     # Rating operations
musiclib_mobile.sh                   # Mobile sync (upload/status subcommands)
musiclib_audacious.sh                # Song-change hook
musiclib_new_tracks.sh               # Import pipeline
musiclib_rebuild.sh                  # Full DB rebuild from filesystem
musiclib_tagrebuild.sh               # Repair corrupted tags from DB
musiclib_tagclean.sh                 # ID3v1→v2 merge, APE removal, art embed
boost_album.sh                       # ReplayGain loudness targeting
audpl_scanner.sh                     # Playlist cross-reference CSV generator
```

**Reference Config** (`/usr/lib/musiclib/config/`):
```
tag_excludes.conf                    # Tags to exclude during operations
ID3v2_frame_excludes.txt             # ID3v2 frames to strip
ID3v2_frames.txt                     # Valid ID3v2 frame reference
```

**Shared Data** (`/usr/share/musiclib/`):
```
conky_example.conf                   # Example Conky configuration
musiclib_example.dsv                 # Example database (for testing)
```

**Desktop Integration** (`/usr/share/`):
```
/usr/share/applications/org.musiclib.musiclib-qt.desktop
/usr/share/kservices5/musiclib-dolphin.desktop    # Or kio/servicemenus/
```

---

### 3.2 User Data Directories (XDG)

**Configuration** (`~/.config/musiclib/`):
```
musiclib.conf       # User-specific config (DB path, music dir, device ID, etc.)
```

**Application Data** (`~/.local/share/musiclib/`):
```
data/
  musiclib.dsv                      # Main database (^-delimited)
  musiclib.dsv.lock                 # Lock file for flock
  musiclib.dsv.backup.YYYYMMDD_*    # Automatic backups
  conky_output/                     # Generated Conky assets
    artist.txt, title.txt, album.txt, year.txt
    lastplayed.txt, detail.txt
    starrating.png                  # Composite star image (generated)
    folder.jpg                      # Current album art
    stars/                          # Star image templates (5 levels)
      blank.png, one.png, oneonehalf.png, ..., five.png
  tag_backups/                      # Tag backups before destructive ops
    song.mp3.backup.YYYYMMDD_HHMMSS

playlists/
  *.audpl                           # Audacious playlists
  mobile/
    *.tracks                        # Mobile sync file lists
    *.meta                          # Mobile sync metadata (upload timestamps)
    current_playlist                # Symlink to most recent playlist

logs/
  musiclib.log                      # Main operation log
  audacious/
    audacioushist.log               # Playback history
  mobile/
    upload_YYYYMMDD.log             # Per-upload logs
```

**Music Files** (user-configured):
```
/mnt/music/                         # Or ~/Music/, configurable via MUSIC_REPO
  Artist/
    Album/
      Track.mp3
```

---

## 4. Technology Stack

### 4.1 Frontend (GUI & CLI)

**Language**: C++20
**Frameworks**:
- Qt 6.5+ (Core, Widgets, DBus, Concurrent)
- KDE Frameworks 6 (KConfig, KNotifications, KIO, KGlobalAccel, KXmlGui, KStatusNotifierItem)

**Build System**: CMake 3.20+
**Compiler**: GCC 11+ or Clang 14+

**GUI Architecture**:
- `KXmlGuiWindow` main window (menu bar, toolbar, status bar auto-configured)
- `QTreeView` with `QSortFilterProxyModel` for library view
- `QStyledItemDelegate` for inline star rating widget
- `QFileSystemWatcher` for database change detection
- `QThread` for non-blocking script execution
- `QProcess` for script invocation with stdout/stderr capture

**CLI Architecture**:
- Argument parser (subcommand pattern: `musiclib-cli rate ...`)
- Script path resolution (`/usr/lib/musiclib/bin/` with dev fallback)
- `std::system()` or `fork()/exec()` for script invocation
- Exit code forwarding (transparent to user)

---

### 4.2 Backend (Shell Scripts)

**Language**: Bash 4.4+ (with `[[`, `((`, arrays, associative arrays)
**Required Tools**:
- **Core**: `bash`, `coreutils` (`awk`, `sed`, `grep`, `readlink`, `date`, `bc`)
- **Locking**: `flock` (util-linux)
- **Tags**: `kid3-cli`, `exiftool`
- **Audio**: `rsgain` (ReplayGain), `audtool` (Audacious control)
- **Mobile**: `kdeconnect-cli`
- **Optional**: `conky` (desktop display), `kdialog` (GUI dialogs from scripts)

**Design Patterns**:
- Utility functions sourced from `musiclib_utils.sh`
- Strict `set -euo pipefail` in all scripts
- `flock`-based locking via helper functions
- JSON error output on stderr (exit codes 1, 2, 3)
- Logging to `musiclib.log` via `log_message()` helper

---

### 4.3 Data Storage

**Database**: Flat-file DSV (`^` -delimited)
- **Why not SQLite**: Simplicity, shell-friendly, easy to backup/inspect, no schema migrations
- **Concurrency**: `flock` for write serialization
- **Performance**: Linear scan acceptable for <100k tracks, awk/grep fast enough

**Configuration**: `musiclib.conf` (bash-sourceable key=value)
- **Why not KConfig**: Scripts need direct access without Qt dependencies
- **Sync**: GUI mirrors config to KConfig for Qt settings UI

**Playlists**: `.audpl` (Audacious), `.m3u`, `.m3u8`, `.pls` (mobile-compatible)

---

## 5. Concurrency & Locking

### 5.1 Problem Statement

Multiple processes may attempt to write to `musiclib.dsv` concurrently:
- Audacious hook updates last-played
- User rates track in GUI
- Background rebuild runs

Without coordination, this causes:
- Corrupted DSV (partial writes, interleaved lines)
- Lost updates (last write wins)
- Inconsistent state (DSV vs. file tags diverge)

### 5.2 Solution: flock-Based Locking

**Mechanism**:
```bash
# In musiclib_utils.sh
acquire_db_lock() {
    exec 200>"${MUSICDB}.lock"
    flock -w 5 200 || return 1
}

release_db_lock() {
    flock -u 200
}

with_db_lock() {
    local callback="$1"
    shift
    acquire_db_lock || { error_exit 2 "Database lock timeout"; return $?; }
    trap release_db_lock EXIT
    "$callback" "$@"
    release_db_lock
}
```

**Usage in Scripts**:
```bash
#!/bin/bash
source musiclib_utils.sh

update_rating_impl() {
    local filepath="$1"
    local rating="$2"
    # Perform DSV + tag updates
}

with_db_lock update_rating_impl "/path/to/file.mp3" 4
```

**Timeout Policy**:
- Default: 5 seconds
- Configurable via `LOCK_TIMEOUT` in `musiclib.conf`
- On timeout: exit code 2, JSON error (future: exit code 3, queue operation)

**Lock File Lifecycle**:
- Created on first lock acquisition: `musiclib.dsv.lock`
- Persists across operations (never deleted)
- Safe on NFS with kernel ≥2.6.12 (advisory locking)

---

### 5.3 Future: Deferred Operations Queue

**Design** (not yet implemented):
```bash
# In musiclib_utils.sh (future)
with_db_lock_deferred() {
    local callback="$1"
    shift
    
    if acquire_db_lock; then
        trap release_db_lock EXIT
        "$callback" "$@"
        release_db_lock
        return 0
    else
        # Timeout: queue operation
        queue_operation "$callback" "$@"
        error_exit 3 "Operation queued for retry"
        return 3
    fi
}

queue_operation() {
    local callback="$1"
    shift
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
        --arg ts "$timestamp" \
        --arg op "$callback" \
        --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
        '{timestamp: $ts, operation: $op, args: $args, retry_count: 0}' \
        >> ~/.local/share/musiclib/data/pending_ops.json
}
```

**Benefits**:
- No user-facing lock timeout errors
- Operations never lost
- Background daemon (`musiclibd`) or cron job retries pending ops

---

## 6. Error Handling Strategy

### 6.1 Exit Code Contract

| Exit Code | Meaning | GUI Behavior | CLI Behavior |
|-----------|---------|--------------|--------------|
| 0 | Success | KNotification (success), refresh view | Print "Success" |
| 1 | User error | Show error dialog (user-fixable) | Print error message, suggest fix |
| 2 | System error | Show error dialog (likely admin-fixable) | Print error message, suggest checking logs |
| 3 | Deferred | Show "pending" notification, log operation | Print "Queued for retry" |

### 6.2 JSON Error Format

**Schema**:
```json
{
  "error": "Human-readable error message",
  "script": "scriptname.sh",
  "code": 1,
  "context": {
    "key1": "value1",
    "key2": "value2"
  },
  "timestamp": "2026-02-07T18:45:23Z"
}
```

**GUI Parsing**:
```cpp
QJsonDocument errorDoc = QJsonDocument::fromJson(process.readAllStandardError());
QJsonObject error = errorDoc.object();

QString message = error["error"].toString();
int code = error["code"].toInt();
QJsonObject context = error["context"].toObject();

if (code == 1) {
    // User error: actionable message
    QMessageBox::warning(this, "Input Error", message);
} else if (code == 2) {
    // System error: suggest checking logs
    QMessageBox::critical(this, "Operation Failed", 
        message + "\n\nCheck logs for details: ~/.local/share/musiclib/logs/musiclib.log");
} else if (code == 3) {
    // Deferred: show pending notification
    KNotification::event("pending", "Operation Queued", message);
}
```

---

## 7. KDE Integration Points

### 7.1 System Tray (KStatusNotifierItem)

**Purpose**: Persistent access to rating and operations while Audacious plays.

**Behavior**:
- **Tooltip**: `"Artist – Title ★★★★☆"`
- **Left-click**: Open `musiclib-qt` to Maintenance Panel
- **Right-click menu**:
  - Quick Rate → 0–5 stars (submenu)
  - Open Library
  - Settings
  - Quit

**Implementation**:
```cpp
KStatusNotifierItem* trayIcon = new KStatusNotifierItem(this);
trayIcon->setIconByName("musiclib");
trayIcon->setToolTipTitle("MusicLib");
trayIcon->setToolTipSubTitle(getCurrentTrackInfo());

auto menu = trayIcon->contextMenu();
auto rateMenu = menu->addMenu("Quick Rate");
for (int i = 0; i <= 5; ++i) {
    rateMenu->addAction(QString("%1 Stars").arg(i), [i]() { 
        rateCurrentTrack(i); 
    });
}
```

---

### 7.2 Global Shortcuts (KGlobalAccel)

**Purpose**: Rate tracks without focusing GUI (most-requested power-user feature).

**Default Bindings** (user-customizable):
- `Meta+1` → Rate current track 1 star
- `Meta+2` → Rate current track 2 stars
- ...
- `Meta+5` → Rate current track 5 stars
- `Meta+0` → Clear rating

**Implementation**:
```cpp
KGlobalAccel* globalAccel = KGlobalAccel::self();
for (int i = 0; i <= 5; ++i) {
    QAction* rateAction = new QAction(QString("Rate %1 Stars").arg(i), this);
    rateAction->setProperty("componentName", "musiclib-qt");
    rateAction->setProperty("componentDisplayName", "MusicLib");
    globalAccel->setGlobalShortcut(rateAction, 
        QKeySequence(QString("Meta+%1").arg(i)));
    connect(rateAction, &QAction::triggered, [i]() { 
        rateCurrentTrack(i); 
    });
}
```

---

### 7.3 Dolphin Service Menus

**Purpose**: Right-click audio files in Dolphin → "Add to MusicLib".

**File**: `/usr/share/kservices5/musiclib-dolphin.desktop` (or `kio/servicemenus/`)
```ini
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=audio/mpeg;audio/flac;audio/ogg;
Actions=AddToMusicLib

[Desktop Action AddToMusicLib]
Name=Add to MusicLib
Icon=musiclib
Exec=musiclib-cli add-track %f
```

**Behavior**:
- User right-clicks `song.mp3` in Dolphin
- "Add to MusicLib" appears in context menu
- On click, invokes `musiclib-cli add-track /path/to/song.mp3`
- KNotification shows success/failure

---

### 7.4 D-Bus Interface (Future Phase 3)

**Service Name**: `org.musiclib`

**Interfaces**:

```xml
<!-- org.musiclib.Library -->
<interface name="org.musiclib.Library">
  <method name="Search">
    <arg name="query" type="s" direction="in"/>
    <arg name="results" type="a{sv}" direction="out"/>
  </method>
  <method name="GetTrackInfo">
    <arg name="trackId" type="i" direction="in"/>
    <arg name="info" type="a{sv}" direction="out"/>
  </method>
</interface>

<!-- org.musiclib.Player -->
<interface name="org.musiclib.Player">
  <method name="GetCurrentTrack">
    <arg name="trackInfo" type="a{sv}" direction="out"/>
  </method>
  <method name="Rate">
    <arg name="stars" type="i" direction="in"/>
  </method>
</interface>
```

**Consumers**:
- KRunner plugin: `qdbus org.musiclib /Library org.musiclib.Library.Search "dark side"`
- Plasma widget: Subscribe to `CurrentTrackChanged` signal
- Custom scripts: `dbus-send --session --dest=org.musiclib ...`

---

### 7.5 KRunner Plugin (Future Phase 4)

**Example Queries**:
```
ml: dark side          → Search library, show results inline
ml:rate 5              → Rate current track 5 stars
ml:mobile upload       → Trigger mobile sync dialog
ml:status              → Show playback status inline
```

**Implementation**: C++ `AbstractRunner` subclass registered in `/usr/share/kservices5/`.

---

### 7.6 Plasma Widget (Future Phase 4)

**QML Widget**: Desktop/panel widget showing now-playing from Conky output.

**Features**:
- Reads `~/.local/share/musiclib/data/conky_output/` files
- Displays album art, artist, title, rating
- Click to rate (invokes D-Bus method)
- Respects Plasma themes

---

## 8. Rationale for Architecture Choices

### 8.1 Why Keep Shell Backend?

**Pros**:
- ✅ **Proven stability**: 11 scripts, battle-tested in production
- ✅ **Shell-native tools**: `kid3-cli`, `exiftool`, `audtool` have excellent CLI interfaces
- ✅ **Rapid prototyping**: New features iterate faster in bash than C++
- ✅ **Low maintenance**: No library version conflicts, minimal dependencies
- ✅ **Transparency**: Operations are inspectable, debuggable, scriptable

**Cons**:
- ❌ **Performance**: <50ms latency not achievable (acceptable for non-critical-path)
- ❌ **Type safety**: Bash is untyped (mitigated by strict mode, tests)
- ❌ **Error handling**: Verbose compared to exceptions (mitigated by `error_exit()`)

**Decision**: Keep for v0.1–v0.3; migrate hot-path ops (rating, playback tracking) to C++ in v1.1+ if profiling shows need.

---

### 8.2 Why Thin CLI Dispatcher?

**Alternative**: CLI could reimplement operations in C++.

**Rationale for Dispatcher**:
- ✅ **Code reuse**: Scripts are single source of truth
- ✅ **Faster development**: No duplication of business logic
- ✅ **Easier testing**: Test one backend, two interfaces
- ✅ **Unified error handling**: Scripts already have JSON error contract

**When to Migrate**: If CLI usage exceeds GUI usage AND users complain about latency (unlikely for batch operations).

---

### 8.3 Why Flat-File DSV Over SQLite?

**Pros**:
- ✅ **Shell-friendly**: awk/grep queries are trivial
- ✅ **No schema migrations**: Append-only column evolution
- ✅ **Easy backup**: `cp musiclib.dsv musiclib.dsv.backup`
- ✅ **Human-readable**: Can inspect/edit in text editor (advanced users)

**Cons**:
- ❌ **Performance**: O(n) scans (acceptable for <100k tracks)
- ❌ **Indexing**: No B-trees (mitigated by sorting + binary search in GUI)
- ❌ **Transactions**: Manual locking (acceptable with `flock`)

**When to Migrate**: If library size >100k tracks AND queries become slow (unlikely for target audience).

---

## 9. Security Considerations

### 9.1 Script Injection

**Risk**: User-controlled input passed to shell scripts could enable command injection.

**Mitigation**:
- ✅ All script arguments are **quoted** in invocations: `"$filepath"` not `$filepath`
- ✅ GUI/CLI validate inputs before invoking scripts (e.g., rating 0–5, paths exist)
- ✅ Scripts use `[[` conditionals (safer than `[`)
- ✅ No use of `eval` or `source` on user input

**Example** (safe):
```bash
musiclib_rate.sh "/path/with spaces/song.mp3" 4
```

**Example** (vulnerable, never done):
```bash
eval "musiclib_rate.sh $user_input"  # DON'T DO THIS
```

---

### 9.2 File Permissions

**Risk**: Unauthorized access to `musiclib.dsv` or config.

**Mitigation**:
- ✅ XDG directories default to `700` (`~/.config/`, `~/.local/share/`)
- ✅ DB file defaults to `600` (owner read/write only)
- ✅ Scripts check file permissions before operations

---

### 9.3 Mobile Sync (KDE Connect)

**Risk**: Untrusted device could receive sensitive playlists.

**Mitigation**:
- ✅ KDE Connect device pairing required (user must authorize device)
- ✅ GUI shows device name before upload (user confirms)
- ✅ No automatic sync; user-initiated only

---

## 10. Performance Characteristics

### 10.1 Database Operations

| Operation | Complexity | Typical Latency | Notes |
|-----------|------------|-----------------|-------|
| Read entire DB | O(n) | 50–200ms (10k tracks) | awk/grep parse, linear scan |
| Find track by path | O(n) | 10–50ms | grep early exit |
| Update rating | O(n) | 100–300ms | Rewrite DSV, update tag, regen Conky |
| Full rebuild | O(n log n) | 5–30s (10k tracks) | Filesystem scan + sort |

**Optimization Opportunities** (future):
- Sorted DSV + binary search → O(log n) lookups
- Incremental rebuild (only scan changed directories)
- In-memory cache in GUI (invalidate on change)

---

### 10.2 Script Invocation Overhead

- QProcess spawn: ~10ms
- Shell script startup (source utils): ~5–10ms
- Total overhead: ~15–20ms per operation

**Acceptable**: Non-critical-path operations (rating, mobile sync) tolerate 100–300ms total latency.

---

## 11. Testing Strategy

### 11.1 Unit Tests (Scripts)

**Framework**: Bash test harness (custom or BATS)

**Coverage**:
- Utility functions (`musiclib_utils.sh`)
- Tag functions (`musiclib_utils_tag_functions.sh`)
- Error handling (JSON output validation)

**Example**:
```bash
#!/bin/bash
source tests/test_framework.sh
source musiclib_utils.sh

test_epoch_to_sql_time() {
    local epoch=1675000000
    local expected="45678.543210"
    local actual=$(epoch_to_sql_time $epoch)
    assert_equals "$expected" "$actual"
}

run_tests
```

---

### 11.2 Integration Tests (Scripts + Tools)

**Framework**: Bash test scripts with fixtures

**Coverage**:
- Lock contention scenarios (`test_lock_contention.sh`)
- Tag corruption recovery (`test_tag_rebuild.sh`)
- Mobile upload workflow (`test_mobile_upload.sh`)
- Database rebuild accuracy (`test_rebuild.sh`)

---

### 11.3 GUI Tests (Qt Test)

**Framework**: Qt Test

**Coverage**:
- Library view model (DSV parsing, filtering, sorting)
- Script invocation (QProcess mocking)
- Error handling (JSON parsing)
- Settings persistence (KConfig)

**Example**:
```cpp
void TestLibraryModel::testDSVParsing() {
    QFile testDb("tests/fixtures/test_db.dsv");
    testDb.open(QIODevice::ReadOnly);
    LibraryModel model;
    model.loadFromStream(&testDb);
    
    QCOMPARE(model.rowCount(), 10);
    QCOMPARE(model.data(model.index(0, 0)).toString(), "1");
    QCOMPARE(model.data(model.index(0, 5)).toString(), "Time");
}
```

---

### 11.4 End-to-End Smoke Tests

**Framework**: Bash script simulating user workflows

**Coverage**:
1. Install packages
2. Run first-run wizard
3. Import test track
4. Rate track via CLI
5. Rate track via GUI
6. Upload playlist to mock KDE Connect device
7. Rebuild database
8. Verify all operations logged

---

## 12. Future Evolution: Option C (Hybrid)

**Goal**: Migrate hot-path operations to C++ for <50ms latency while keeping shell for maintenance ops.

**Proposed Architecture**:
```
┌─────────────────────────────────────────┐
│  musiclib-qt & musiclib-cli             │
├─────────────────────────────────────────┤
│  Link against libmusiclib.so            │
└─────────────┬───────────────────────────┘
              ▼
┌─────────────────────────────────────────┐
│  libmusiclib.so (C++ Shared Library)    │
├─────────────────────────────────────────┤
│  • DSV read/write (lock-aware)          │
│  • Tag I/O (wrapper around kid3-cli)    │
│  • Rating update (DSV + tags + Conky)   │
│  • Playback tracking                    │
└─────────────┬───────────────────────────┘
              ▼
┌─────────────────────────────────────────┐
│  Shell Scripts (maintenance only)       │
├─────────────────────────────────────────┤
│  • musiclib_rebuild.sh                  │
│  • musiclib_tagclean.sh                 │
│  • musiclib_tagrebuild.sh               │
│  • boost_album.sh                       │
│  • audpl_scanner.sh                     │
│  (Invoke libmusiclib for DB access)     │
└─────────────────────────────────────────┘
```

**Migration Path**:
1. Phase 1: Extract DSV read/write to C++ library
2. Phase 2: Migrate rating logic to library
3. Phase 3: Migrate playback tracking to library
4. Phase 4: Scripts source library via FFI or invoke CLI helpers
5. Phase 5: GUI/CLI link directly against library (bypass scripts for hot paths)

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-07  
**Status**: Implementation-Ready
