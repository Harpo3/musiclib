# MusicLib Backend API Contract v1.0

## Document Purpose

Canonical specification of the interface between `musiclib-qt` GUI, `musiclib-cli` dispatcher, and shell scripts. All backend scripts must conform to this contract to ensure reliable integration.

**Scope**: Exit codes, error JSON format, locking protocol, script invocation signatures, configuration reading, and CLI subcommand reference.

---

## 1. Common Conventions

### 1.1 Exit Codes

All MusicLib backend scripts use a standardized exit code contract:

| Exit Code | Semantic | When to Use | Example |
|-----------|----------|-------------|---------|
| **0** | Success | Operation completed successfully, all side effects applied | `musiclib_rate.sh` updates rating in DSV, file tags, Conky assets, and DB |
| **1** | User/Validation Error | Invalid input, missing preconditions, user cancellation | Invalid star rating (not 0–5), file not in database, user Ctrl-C |
| **2** | System/Operational Error | Config missing, tool unavailable, I/O failure, lock timeout | `kid3-cli` not installed, DB file unreadable, permissions denied, `flock` timeout >5s |
| **3** | Deferred | Operation queued for retry due to lock contention | Lock timeout → operation added to pending queue, success notification delayed |

**Current Status**: Exit code 3 (deferred operations) is **proposed design, not yet implemented**. Currently, lock timeouts return exit code 2.

**Usage Rules**:
1. **Exit 0 only on complete success** — All required side effects must be applied (file tags, DB updates, notifications, Conky artifacts). Partial success is exit 2.
2. **Exit 1 for user errors** — Validate arguments and preconditions before operations. Exit 1 immediately with no side effects if validation fails.
3. **Exit 2 for system failures** — Config errors, missing tools, permissions, I/O failures, lock timeouts (until exit 3 implemented).
4. **Exit 3 for deferred work** — Operation queued to process pending file, user gets "pending" notification now, "completed" notification later.
5. **No other exit codes** — Scripts must only use 0, 1, 2, or 3.

---

### 1.2 Error JSON Schema

On exit codes 1, 2, or 3, scripts must output valid JSON to stderr:

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

**Requirements**:
- Valid JSON (use `jq` or `printf` for escaping)
- No raw newlines in strings (use `\n` in JSON if needed)
- `context` values must be strings (convert numbers/arrays to strings)
- Timestamp in UTC ISO8601 format (`YYYY-MM-DDTHH:MM:SSZ`)
- No trailing commas or incomplete JSON

**Examples**:

```json
{
  "error": "Invalid star rating - must be 0-5",
  "script": "musiclib_rate.sh",
  "code": 1,
  "context": {
    "provided": "6"
  },
  "timestamp": "2026-02-07T18:45:23Z"
}
```

```json
{
  "error": "Database lock timeout - another process may be using the database",
  "script": "musiclib_mobile.sh",
  "code": 2,
  "context": {
    "timeout": "5 seconds",
    "database": "/home/user/.local/share/musiclib/data/musiclib.dsv"
  },
  "timestamp": "2026-02-07T18:45:23Z"
}
```

```json
{
  "error": "Required tools not available",
  "script": "musiclib_tagclean.sh",
  "code": 2,
  "context": {
    "missing": "[\"kid3-cli\", \"exiftool\"]"
  },
  "timestamp": "2026-02-07T18:45:23Z"
}
```

---

### 1.3 Database Locking Protocol

MusicLib uses file-based locking via `flock` to serialize concurrent writes and prevent corruption.

**Status**: Deferred operations queue (exit code 3) is **proposed, not yet implemented**. Currently, lock timeouts return exit 2.

#### 1.3.1 Utility Functions (Primary Interface)

Scripts access locking through `musiclib_utils.sh` functions, not direct `flock` calls.

##### `error_exit(exit_code, error_message, [key value ...])`

Outputs JSON error to stderr and returns exit code. **Does not exit** — caller must handle.

**Signature**:
```bash
error_exit exit_code error_message [context_key context_value ...]
```

**Example**:
```bash
#!/bin/bash
source musiclib_utils.sh || exit 2

if [ -z "$MUSICDB" ]; then
    error_exit 1 "Database path not configured"
    exit $?
fi

if ! kid3-cli --version &>/dev/null; then
    error_exit 2 "Required tool not available" "missing" "kid3-cli"
    exit $?
fi
```

##### `with_db_lock(callback_function)`

Executes callback function with exclusive DB lock. Handles timeout/retry logic.

**Signature**:
```bash
with_db_lock callback_function
```

**Example**:
```bash
#!/bin/bash
source musiclib_utils.sh || exit 2

update_rating() {
    local filepath="$1"
    local rating="$2"
    # Update DSV, tags, Conky
    # ...
}

with_db_lock update_rating "/path/to/song.mp3" 4
```

##### `acquire_db_lock()` / `release_db_lock()`

Low-level lock acquisition. Use `with_db_lock` instead when possible.

**Example**:
```bash
acquire_db_lock || { error_exit 2 "Lock timeout"; exit $?; }
trap release_db_lock EXIT

# Perform DB operations
# ...

release_db_lock
```

#### 1.3.2 Lock Timeout Policy

- Default timeout: **5 seconds**
- Configurable via `LOCK_TIMEOUT` in `musiclib.conf`
- On timeout (current): exit 2, JSON error
- On timeout (future): exit 3, queue to pending operations file

#### 1.3.3 Lock File Location

- Lock file: `${MUSICDB}.lock` (e.g., `~/.local/share/musiclib/data/musiclib.dsv.lock`)
- Automatically created/removed by utility functions
- Safe for NFS with kernel ≥2.6.12 (document: local filesystems recommended)

---

### 1.4 Path Conventions

- All paths in DB are **absolute** (e.g., `/mnt/music/artist/album/track.mp3`)
- Paths use **forward slashes** (even on edge-case filesystems)
- Symbolic links are **resolved to real paths** before DB insertion (`readlink -f`)
- Paths are **URL-decoded** if sourced from `.audpl` files (`uri=file://...`)

---

### 1.5 Configuration Reading

Scripts source `musiclib.conf` via `musiclib_utils.sh::load_config()`:

**Standard Config Variables**:
```bash
MUSICDB              # Path to musiclib.dsv
MUSIC_REPO           # Root music directory
CONKY_OUTPUT_DIR     # Conky artifacts output
DEVICE_ID            # KDE Connect device ID
DEFAULT_RATING       # Default rating for new tracks (0-5)
BACKUP_RETENTION     # Backup retention period (days)
LOCK_TIMEOUT         # Lock timeout (seconds)
LOGFILE              # Main log file path
```

**Example**:
```bash
#!/bin/bash
source /usr/lib/musiclib/bin/musiclib_utils.sh || exit 2
load_config

echo "Database: $MUSICDB"
echo "Music repo: $MUSIC_REPO"
```

---

## 2. Script Reference (CLI Subcommands)

### 2.1 `musiclib-cli rate` → `musiclib_rate.sh`

**Purpose**: Set star rating (0–5) for a track, update DSV, file tags, and Conky assets.

**Invocation**:
```bash
musiclib_rate.sh FILEPATH RATING
```

**Parameters**:
- `FILEPATH`: Absolute path to audio file (must exist in DB)
- `RATING`: Integer 0–5 (0=unrated, 5=highest)

**Side Effects**:
- Updates `musiclib.dsv` (Rating column)
- Updates POPM tag in file (via `kid3-cli`)
- Updates Grouping tag (star symbols: ★★★★★)
- Regenerates Conky assets (`starrating.png`, `detail.txt`)
- Logs to `musiclib.log`
- Sends KNotification (if GUI running)

**Exit Codes**:
- 0: Success
- 1: Invalid rating, file not in DB, file not found
- 2: `kid3-cli` unavailable, tag write failure, DB lock timeout

**Example**:
```bash
musiclib-cli rate "/mnt/music/Pink Floyd/Dark Side/Money.mp3" 5
```

**Equivalent GUI**: Right-click track → Rate → 5 stars, or inline star click

---

### 2.2 `musiclib-cli mobile upload` → `musiclib_mobile.sh upload`

**Purpose**: Transfer playlist to Android device via KDE Connect, update last-played timestamps.

**Invocation**:
```bash
musiclib_mobile.sh upload DEVICE_ID PLAYLIST_FILE
```

**Parameters**:
- `DEVICE_ID`: KDE Connect device identifier (from `kdeconnect-cli -l`)
- `PLAYLIST_FILE`: Path to `.audpl`, `.m3u`, `.m3u8`, or `.pls` file

**Workflow**:
1. Parse playlist (format auto-detected by extension)
2. Resolve file paths (URL-decode `.audpl`, resolve basenames in `.m3u`)
3. Generate `.m3u` with basenames only
4. Transfer `.m3u` + all MP3 files via `kdeconnect-cli --share`
5. Save metadata: `<playlist>.tracks` (file list), `<playlist>.meta` (upload timestamp)
6. Process previous playlist's synthetic last-played times
7. Update `musiclib.dsv` and file tags for previous upload

**Side Effects**:
- Writes `~/.local/share/musiclib/playlists/mobile/<playlist>.tracks`
- Writes `~/.local/share/musiclib/playlists/mobile/<playlist>.meta`
- Updates `LastTimePlayed` in DSV and tags for previous playlist
- Logs to `logs/mobile/`

**Exit Codes**:
- 0: Success
- 1: Invalid playlist format, device not reachable
- 2: `kdeconnect-cli` unavailable, transfer failure, DB lock timeout

**Example**:
```bash
musiclib-cli mobile upload abc123def456 "/home/user/.local/share/musiclib/playlists/workout.audpl"
```

**Equivalent GUI**: Mobile panel → Select playlist → Select device → Upload

---

### 2.3 `musiclib-cli mobile status` → `musiclib_mobile.sh status`

**Purpose**: Show last mobile upload timestamp and device info.

**Invocation**:
```bash
musiclib_mobile.sh status
```

**Output** (stdout, human-readable):
```
Last Upload: 2026-02-05 14:32:18
Device: Samsung Galaxy S21 (abc123def456)
Playlist: workout.audpl (42 tracks)
```

**Exit Codes**:
- 0: Success
- 2: No upload history found

---

### 2.4 `musiclib-cli build` → `musiclib_build.sh`

**Purpose**: Full DB build/rebuild from filesystem scan of `MUSIC_REPO`.

**Invocation**:
```bash
musiclib_build.sh [--dry-run]
```

**Options**:
- `--dry-run`: Show what would be added/removed without making changes

**Workflow**:
1. Scan `MUSIC_REPO` recursively for audio files
2. Extract metadata from tags via `exiftool`
3. Back up current `musiclib.dsv`
4. Generate or regenerate DB with all discovered tracks
5. Preserve ratings from old DB where possible (match by path)
6. Log orphaned entries (in old DB but not on filesystem)

**Side Effects**:
- Overwrites `musiclib.dsv`
- Creates backup: `musiclib.dsv.backup.YYYYMMDD_HHMMSS`
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: Dry-run complete (not an error, informational)
- 2: `MUSIC_REPO` not found, DB lock timeout, I/O error

**Example**:
```bash
musiclib-cli build --dry-run
musiclib-cli build
```

**Equivalent GUI**: Maintenance panel → Database Operations → Build Library

---

### 2.5 `musiclib-cli tagclean` → `musiclib_tagclean.sh`

**Purpose**: Merge ID3v1 → ID3v2, remove APE tags, embed album art, normalize tag structure.

**Invocation**:
```bash
musiclib_tagclean.sh PATH [--mode MODE]
```

**Parameters**:
- `PATH`: File or directory path
- `--mode MODE`: `merge` (default), `strip`, `embed-art`

**Modes**:
- `merge`: ID3v1 → ID3v2.4, remove ID3v1, remove APE, embed art if missing
- `strip`: Remove ID3v1 and APE only
- `embed-art`: Embed `folder.jpg` from directory if no art present

**Side Effects**:
- Modifies file tags in place
- Creates tag backups: `~/.local/share/musiclib/data/tag_backups/<file>.backup.YYYYMMDD_HHMMSS`
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: Invalid mode, file/dir not found
- 2: `kid3-cli` unavailable, tag operation failed

**Example**:
```bash
musiclib-cli tagclean "/mnt/music/Pink Floyd" --mode merge
```

**Equivalent GUI**: Maintenance panel → Tag Operations → Clean Tags → Select directory → Mode: Merge

---

### 2.6 `musiclib-cli tagrebuild` → `musiclib_tagrebuild.sh`

**Purpose**: Rebuild corrupted tags from DB values (repair tool).

**Invocation**:
```bash
musiclib_tagrebuild.sh FILEPATH
```

**Parameters**:
- `FILEPATH`: Absolute path to file with corrupted tags

**Workflow**:
1. Look up track in `musiclib.dsv` by path
2. Read Artist, Album, AlbumArtist, Title, Genre, Rating from DB
3. Strip all existing tags from file
4. Write tags from DB values via `kid3-cli`
5. Restore rating as POPM + Grouping

**Side Effects**:
- Overwrites file tags
- Creates tag backup
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: File not in DB
- 2: `kid3-cli` unavailable, tag write failed

**Example**:
```bash
musiclib-cli tagrebuild "/mnt/music/corrupted/song.mp3"
```

**Equivalent GUI**: Maintenance panel → Tag Operations → Rebuild Tags → Select file

---

### 2.7 `musiclib-cli boost` → `boost_album.sh`

**Purpose**: Apply ReplayGain loudness targeting to album (via `rsgain`).

**Invocation**:
```bash
boost_album.sh ALBUM_DIR [--target TARGET_LUFS]
```

**Parameters**:
- `ALBUM_DIR`: Directory containing album tracks
- `--target TARGET_LUFS`: Target loudness in LUFS (default: -18)

**Workflow**:
1. Scan all tracks in `ALBUM_DIR` with `rsgain -a`
2. Apply album-level ReplayGain tags
3. Optionally apply track-level gain

**Side Effects**:
- Adds ReplayGain tags to files
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: Invalid directory, no audio files found
- 2: `rsgain` unavailable

**Example**:
```bash
musiclib-cli boost "/mnt/music/Pink Floyd/The Wall" --target -16
```

**Equivalent GUI**: Maintenance panel → Loudness Operations → Boost Album → Select directory

---

### 2.8 `musiclib-cli scan` → `audpl_scanner.sh`

**Purpose**: Scan playlists and generate cross-reference CSV (which playlists contain which tracks).

**Invocation**:
```bash
audpl_scanner.sh [PLAYLIST_DIR]
```

**Parameters**:
- `PLAYLIST_DIR`: Directory to scan (default: `~/.local/share/musiclib/playlists/`)

**Output** (stdout, CSV):
```csv
Playlist,TrackPath,Artist,Album,Title
workout.audpl,/mnt/music/AC-DC/Back in Black/Hells Bells.mp3,AC/DC,Back in Black,Hells Bells
chill.audpl,/mnt/music/Pink Floyd/Dark Side/Time.mp3,Pink Floyd,The Dark Side of the Moon,Time
```

**Side Effects**:
- Writes to stdout (GUI captures for display)
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: Playlist directory not found

**Example**:
```bash
musiclib-cli scan > playlist_cross_reference.csv
```

**Equivalent GUI**: Maintenance panel → Playlist Operations → Scan Playlists

---

### 2.9 `musiclib-cli new-tracks` → `musiclib_new_tracks.sh`

**Purpose**: Import new music downloads into library (normalize tags, rename, add to DB).

**Invocation**:
```bash
musiclib_new_tracks.sh [artist_name] [options]
```

**Parameters**:
- `artist_name`: Artist folder name (optional, prompts if omitted)
- `--source DIR`: Override download directory
- `--source-dialog`: Show interactive directory picker (kdialog)
- `--no-loudness`: Skip rsgain loudness normalization
- `--no-art`: Skip album art extraction
- `--dry-run`: Preview mode only
- `-v, --verbose`: Detailed output

**Workflow**:
1. If no artist_name, prompt for artist folder
2. Scan source directory (default: `~/Downloads` or override with `--source`)
3. Normalize tags (via `tagclean` logic)
4. Optionally apply ReplayGain loudness normalization (unless `--no-loudness`)
5. Optionally extract album art to Conky display (unless `--no-art`)
6. Add each track to `musiclib.dsv`
7. Move files to `MUSIC_REPO/artist_name/album/`
8. Log to `musiclib.log`

**Side Effects**:
- Adds rows to `musiclib.dsv`
- Modifies file tags
- Moves/renames files to `MUSIC_REPO`
- Extracts album art (unless `--no-art`)
- Optionally applies loudness normalization
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: Invalid artist name, file already in DB, invalid file format
- 2: DB lock timeout, I/O error, ReplayGain/exiftool unavailable

**Examples**:
```bash
musiclib-cli new-tracks "radiohead"
musiclib-cli new-tracks "radiohead" --source /mnt/external/new_music
musiclib-cli new-tracks "pink_floyd" --dry-run
```

**Equivalent GUI**: Maintenance panel → Import New Tracks → Select artist → Import

---

### 2.10 `musiclib-cli audacious-hook` → `musiclib_audacious.sh` (Song-Change Hook)

**Purpose**: Update Conky display assets and last-played timestamp when Audacious plays a new track.

**Design Pattern**: Event-driven hook (not a manual CLI command). Called **automatically** by Audacious via the "Song Change" plugin. Users configure this once during `musiclib-cli setup` and never invoke it manually.

**Invocation** (by Audacious hook):
```bash
musiclib_audacious.sh
# No parameters - reads current track state from audtool
```

**Environment Requirements**:
- Audacious must be running
- `audtool` must be available (from audacious-plugins package)
- Current track must be playing

**Workflow**:
1. Query current track from Audacious via `audtool --current-song-filename`
2. Look up track in `musiclib.dsv`
3. Extract album art to Conky display directory
4. Write track metadata to Conky text files (artist, album, title, rating, last played)
5. Select appropriate star-rating PNG for display
6. Monitor playback to scrobble threshold (50% of track, bounded 30s–4min)
7. Once threshold met, update `LastTimePlayed` in DSV and file tag
8. Append to `audacioushist.log`
9. Optionally send KNotification

**Side Effects** (all atomic via lock):
- **Conky display files**: `detail.txt`, `starrating.png`, `artloc.txt`, `currartsize.txt`, album art copies – all written to `$MUSIC_DISPLAY_DIR/`
- **Database**: Updates `LastTimePlayed` column in `musiclib.dsv` (only after scrobble threshold met)
- **File tags**: Updates `Songs-DB_Custom1` tag with last-played timestamp
- **Logs**: Appends to `audacioushist.log` and `musiclib.log`

**Exit Codes**:

| Code | Meaning | When | Example |
|------|---------|------|---------|
| **0** | Success | Display updated, scrobble queued | Normal playback, track changed |
| **1** | Not an error | Audacious not running or no track playing | User stopped playback, script exits gracefully |
| **2** | System error | Tool unavailable, DB lock timeout, I/O failure | `exiftool` missing, tag write failed |

**Important**: Exit code 1 is **not an error** in this context. It indicates graceful handling of "no track playing" state.

**Error JSON Examples**:

Database lock timeout:
```json
{
  "error": "Database lock timeout - another process may be using the database",
  "script": "musiclib_audacious.sh",
  "code": 2,
  "context": {
    "timeout": "5 seconds",
    "database": "/home/user/.local/share/musiclib/data/musiclib.dsv"
  },
  "timestamp": "2026-02-14T18:45:23Z"
}
```

Tool unavailable:
```json
{
  "error": "Required tool not available",
  "script": "musiclib_audacious.sh",
  "code": 2,
  "context": {
    "missing": "audtool",
    "package": "audacious-plugins"
  },
  "timestamp": "2026-02-14T18:45:23Z"
}
```

**Configuration Dependencies** (from `musiclib.conf`):
```bash
AUDACIOUS_INSTALLED=true
AUDACIOUS_PATH="/usr/bin/audacious"
MUSIC_DISPLAY_DIR="${MUSICLIB_DATA_DIR}/data/conky_output"
SCROBBLE_THRESHOLD_PCT=50
STAR_DIR="$MUSIC_DISPLAY_DIR/stars"
```

**Setup**: Configured during `musiclib-cli setup`, which detects Audacious, provides Song Change plugin instructions, and optionally verifies the integration. See section 2.11.

**Behavioral Notes**:
1. **Idempotent**: Can be called multiple times for same track without side effects
2. **Non-blocking**: Returns quickly to avoid delaying Audacious playback
3. **Lock-aware**: Gracefully handles database lock contention (exit 2, not crash)
4. **Silent operation**: Errors go to stderr (JSON) and log, not user notification

**Troubleshooting**:

If the hook is not firing: check that the Song Change plugin is enabled in Audacious (Settings → Plugins), verify the command path is correct, confirm the hook script is executable (`chmod +x`), and ensure `audtool` is installed.

If Conky files are not updating: check the output directory exists and has correct permissions, and check for database lock timeouts in `musiclib.log`.

**Performance**: Typical execution 50–200ms. CPU negligible, memory <5MB, disk I/O ~50KB per song change.

---

### 2.11 `musiclib-cli setup` → `musiclib_init_config.sh`

**Purpose**: Interactive first-run configuration wizard. Detects system capabilities, creates directory structure, generates configuration, provides Audacious Song Change plugin setup instructions, and optionally verifies the integration.

**Invocation**:
```bash
musiclib_init_config.sh [--force]
```

**Parameters**:
- `--force`: Overwrite existing configuration file

**Workflow**:
1. Check for existing configuration (skip if present, unless `--force`)
2. Detect Audacious installation and `audtool` availability
3. Scan filesystem for music directories (common locations: `/mnt/music`, `~/Music`)
4. Prompt for music repository path
5. Prompt for download directory (default: `~/Downloads`)
6. Create XDG directory structure (`~/.config/musiclib/`, `~/.local/share/musiclib/`)
7. Generate `musiclib.conf` with detected values
8. If Audacious detected:
   a. Display step-by-step Song Change plugin setup instructions
   b. Optionally verify integration (check Audacious running, test hook, validate Conky output)
9. Offer to build initial database via `musiclib_build.sh`
10. Display next-steps summary

**Side Effects**:
- Creates `~/.config/musiclib/musiclib.conf`
- Creates `~/.local/share/musiclib/` directory tree (data, logs, playlists)
- Optionally invokes `musiclib_build.sh` for initial database creation

**Exit Codes**:
- 0: Configuration created successfully
- 1: User cancelled setup
- 2: System error (cannot create directories, permissions denied)

**Auto-trigger**: When any `musiclib-cli` command is run without a valid configuration file, the dispatcher prompts the user to run setup before proceeding.

**Example**:
```bash
# First-time setup
musiclib-cli setup

# Reconfigure (overwrites existing config)
musiclib-cli setup --force
```

**Equivalent GUI**: First-run wizard dialog in `musiclib-qt` (Phase 2+)

---

## 3. Database Schema (`musiclib.dsv`)

**Format**: `^` -delimited (caret), no quoting.

**Header Row** (column names):
```
ID^Artist^IDAlbum^Album^AlbumArtist^SongTitle^SongPath^Genre^SongLength^Rating^Custom2^GroupDesc^LastTimePlayed
```

**Column Definitions**:

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `ID` | Integer | Unique track ID | `1042` |
| `Artist` | String | Track artist | `Pink Floyd` |
| `IDAlbum` | Integer | Album ID (internal) | `523` |
| `Album` | String | Album title | `The Dark Side of the Moon` |
| `AlbumArtist` | String | Album artist | `Pink Floyd` |
| `SongTitle` | String | Track title | `Time` |
| `SongPath` | String | Absolute file path | `/mnt/music/Pink Floyd/Dark Side/Time.mp3` |
| `Genre` | String | Genre | `Progressive Rock` |
| `SongLength` | Integer | Duration (milliseconds) | `415320` |
| `Rating` | Integer | Star rating (0–5) | `5` |
| `Custom2` | String | Reserved (future use) | `` |
| `GroupDesc` | String | Star symbols for Conky | `★★★★★` |
| `LastTimePlayed` | Float | Excel serial time | `45678.543210` |

**Notes**:
- `LastTimePlayed` format: Excel serial date (days since 1899-12-30 + fraction for time)
- Convert from Unix epoch: `epoch_to_sql_time()` in `musiclib_utils.sh`
- Rows are appended (never deleted in normal operation; use `rebuild` to prune)

---

## 4. Integration Patterns

### 4.1 Calling Scripts from GUI (Qt)

**Recommended Pattern**:
```cpp
struct ScriptResult {
    int exitCode;
    QByteArray stdout;
    QByteArray stderr;
};

ScriptResult runScript(const QString& scriptPath, const QStringList& args) {
    QProcess process;
    process.start(scriptPath, args);
    process.waitForFinished(-1);  // Or timeout

    return {
        .exitCode = process.exitCode(),
        .stdout = process.readAllStandardOutput(),
        .stderr = process.readAllStandardError()
    };
}

// Usage
auto result = runScript("/usr/lib/musiclib/bin/musiclib_rate.sh", 
                        {filePath, "4"});
if (result.exitCode != 0) {
    auto errorDoc = QJsonDocument::fromJson(result.stderr);
    auto errorObj = errorDoc.object();
    showNotification(errorObj["error"].toString());
    logError(errorObj);
}
```

### 4.2 Database Refresh Strategy (Qt)

**File Watcher with Debounce**:
```cpp
QFileSystemWatcher watcher;
watcher.addPath(dbPath);

QTimer debounceTimer;
debounceTimer.setSingleShot(true);
debounceTimer.setInterval(500);  // 500ms debounce

connect(&watcher, &QFileSystemWatcher::fileChanged,
        &debounceTimer, qOverload<>(&QTimer::start));
connect(&debounceTimer, &QTimer::timeout,
        this, &MainWindow::reloadDatabase);
```

### 4.3 Calling Scripts from CLI Dispatcher (C++)

**Example** (`musiclib-cli rate`):
```cpp
int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: musiclib-cli rate FILEPATH RATING\n";
        return 1;
    }

    std::string scriptPath = "/usr/lib/musiclib/bin/musiclib_rate.sh";
    std::vector<std::string> args = {argv[1], argv[2]};

    int exitCode = execScript(scriptPath, args);
    return exitCode;
}
```

---

## 5. Testing Contract

### 5.1 Test Input Conventions

Test files should live in `tests/fixtures/`:
- `test_valid.mp3`: Valid MP3 with complete ID3v2.4 tags
- `test_no_tags.mp3`: Valid MP3 with no tags
- `test_corrupt.mp3`: Corrupted file (invalid headers)
- `test_db.dsv`: Minimal valid database (10 rows)
- `test_playlist.audpl`: Sample Audacious playlist

### 5.2 Expected Behaviors (Idempotency)

- Running `musiclib_new_tracks.sh` twice on same file → exit 1 (already in DB), no DB change
- Running `musiclib_rate.sh` with same rating → exit 0 (no-op update, DSV unchanged)
- Running `musiclib_rebuild.sh --dry-run` → exit 1 (informational, not an error), no DB change
- Running `musiclib_tagclean.sh` twice on same file → exit 0 (idempotent, tags already clean)

### 5.3 Integration Test Examples

```bash
# Test lock contention
./tests/test_lock_contention.sh

# Test rating workflow
./tests/test_rating_workflow.sh

# Test mobile upload dry-run
./tests/test_mobile_upload.sh --dry-run

# Test tag corruption recovery
./tests/test_tag_rebuild.sh
```

---

## 6. Migration & Compatibility

### 6.1 Version Compatibility

Scripts indicate API version via internal variable:
```bash
BACKEND_API_VERSION="1.0"
```

GUI/CLI check this on startup:
```cpp
QString apiVersion = getScriptVersion("/usr/lib/musiclib/bin/musiclib_utils.sh");
if (apiVersion != "1.0") {
    qWarning() << "Backend API version mismatch:" << apiVersion;
    // Show warning dialog
}
```

### 6.2 Schema Evolution

When adding columns to `musiclib.dsv`:
1. **Append** new columns to end (preserve column indices)
2. Provide **default values** for existing rows in `musiclib_rebuild.sh`
3. Update `BACKEND_API_VERSION` minor number (1.0 → 1.1)
4. Document in `docs/MIGRATION.md`

**Example**:
```
# Before (v1.0):
ID^Artist^IDAlbum^Album^AlbumArtist^SongTitle^SongPath^Genre^SongLength^Rating^Custom2^GroupDesc^LastTimePlayed

# After (v1.1):
ID^Artist^IDAlbum^Album^AlbumArtist^SongTitle^SongPath^Genre^SongLength^Rating^Custom2^GroupDesc^LastTimePlayed^PlayCount
                                                                                                                  ^^^^^^^^^^ new column
```

**Migration Script** (`migrate_v1_0_to_v1_1.sh`):
```bash
#!/bin/bash
awk -F'^' 'NR==1 {print $0 "^PlayCount"} NR>1 {print $0 "^0"}' musiclib.dsv > musiclib.dsv.new
mv musiclib.dsv.new musiclib.dsv
```

---

## 7. Backward Compatibility Guarantees

**Guaranteed Stable (v1.0+)**:
- Exit code contract (0, 1, 2, 3 semantics)
- JSON error schema (fields: `error`, `script`, `code`, `context`, `timestamp`)
- DSV column order (ID...LastTimePlayed)
- Script invocation signatures (positional args)
- Config variable names (`MUSICDB`, `MUSIC_REPO`, etc.)

**May Change** (with minor version bump):
- New columns appended to DSV
- New optional script arguments
- New config variables (with defaults)
- Internal helper function signatures in `musiclib_utils.sh`

**Breaking Changes** (require major version bump):
- Removing/reordering DSV columns
- Changing exit code semantics
- Renaming config variables
- Changing script names or required arguments

---

## 8. Future Evolution Path

### 8.1 Exit Code 3 Implementation (Deferred Operations)

**Design**:
1. On lock timeout, write operation to `~/.local/share/musiclib/data/pending_ops.json`:
   ```json
   {
     "timestamp": "2026-02-07T18:45:23Z",
     "operation": "rate",
     "args": ["/path/to/file.mp3", "4"],
     "retry_count": 0
   }
   ```
2. Background daemon (`musiclibd`) or periodic cron job retries pending operations
3. On success, remove from pending queue, send delayed KNotification
4. On repeated failure (3+ retries), mark as failed, log error

**Benefits**:
- No user-facing lock timeout errors
- Operations never lost
- Better UX during concurrent access

---

## 9. Appendix A: Quick Reference

### Common Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| "Lock timeout" error | Another script is writing | Wait 5s or `pkill -f musiclib` |
| Conky not updating | Audacious hook not configured | Set hook in Audacious preferences |
| Mobile upload fails | Device not reachable | `kdeconnect-cli -l` to verify connection |
| Tag write fails | File permissions | `chmod 644 /path/to/file.mp3` |
| DB corruption | Concurrent writes without lock | Restore from backup: `musiclib.dsv.backup.*` |

### Script Paths (Post-Install)

```
/usr/lib/musiclib/bin/musiclib_rate.sh
/usr/lib/musiclib/bin/musiclib_mobile.sh
/usr/lib/musiclib/bin/musiclib_rebuild.sh
/usr/lib/musiclib/bin/musiclib_tagclean.sh
/usr/lib/musiclib/bin/musiclib_tagrebuild.sh
/usr/lib/musiclib/bin/boost_album.sh
/usr/lib/musiclib/bin/audpl_scanner.sh
/usr/lib/musiclib/bin/musiclib_new_tracks.sh
/usr/lib/musiclib/bin/musiclib_audacious.sh
/usr/lib/musiclib/bin/musiclib_utils.sh
/usr/lib/musiclib/bin/musiclib_utils_tag_functions.sh
```

### Config File

```
~/.config/musiclib/musiclib.conf
```

### User Data

```
~/.local/share/musiclib/data/musiclib.dsv
~/.local/share/musiclib/data/conky_output/
~/.local/share/musiclib/playlists/
~/.local/share/musiclib/logs/
```

---

## 10. Standalone Utilities

### 10.1 Overview

MusicLib includes standalone utility scripts that operate **outside** the normal API contract. These tools:

- Do **not** use the dispatcher (`musiclib-cli`)
- Do **not** follow the JSON error schema (Section 1.2)
- Do **not** use database locking (Section 1.3)
- Are **not** invoked by the GUI

They exist for specific pre-setup or maintenance scenarios where the user runs them directly from the command line.

**Location**: `~/.local/share/musiclib/utilities/`

---

### 10.2 `conform_musiclib.sh` — Filename Conformance Tool

**Purpose**: Rename non-conforming music filenames to MusicLib naming standards **before** database creation.

**Use Case**: User has music organized in `artist/album/` directories that also meet format requirements, but filenames still contain uppercase letters, spaces, or special characters that would cause inconsistent behavior in path matching and mobile sync.

**When to Run**: Before `musiclib_init_config.sh` (setup wizard). If the setup wizard's library analysis reports non-conforming filenames and user chooses to exit and reorganize, this tool can help.

**Invocation**:
```bash
# Preview changes (dry-run, default)
~/.local/share/musiclib/utilities/conform_musiclib.sh /path/to/music

# Actually rename files
~/.local/share/musiclib/utilities/conform_musiclib.sh --execute /path/to/music

# Verbose output
~/.local/share/musiclib/utilities/conform_musiclib.sh --verbose /path/to/music
```

**Naming Rules Applied**:
- Lowercase only (`Track_01.mp3` → `track_01.mp3`)
- Spaces become underscores (`My Song.mp3` → `my_song.mp3`)
- Non-ASCII transliterated (`Café.mp3` → `cafe.mp3`)
- Multiple underscores collapsed (`a__b.mp3` → `a_b.mp3`)
- Safe characters only: `a-z`, `0-9`, `_`, `-`, `.`

**Safety Features**:
- Dry-run by default (requires `--execute` to modify files)
- Copy-verify-delete workflow (never moves; copies, verifies size match, then deletes original)
- Collision detection (skips if target filename already exists)
- Detailed logging to `~/.local/share/musiclib/logs/conform_YYYYMMDD_HHMMSS.log`

**Exit Codes**:
- 0: Success (or dry-run completed)
- 1: Invalid arguments or user abort
- 2: File operation failures

**Warning**: This script modifies your files. Make backups first. Use solely at your own risk.

**Document Version**: 1.0  
**Last Updated**: 2026-02-14  
**Status**: Implementation-Ready
