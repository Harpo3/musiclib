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
1. **Exit 0 only on complete success** -- All required side effects must be applied (file tags, DB updates, notifications, Conky artifacts). Partial success is exit 2.
2. **Exit 1 for user errors** -- Validate arguments and preconditions before operations. Exit 1 immediately with no side effects if validation fails.
3. **Exit 2 for system failures** -- Config errors, missing tools, permissions, I/O failures, lock timeouts (until exit 3 implemented).
4. **Exit 3 for deferred work** -- Operation queued to process pending file, user gets "pending" notification now, "completed" notification later.
5. **No other exit codes** -- Scripts must only use 0, 1, 2, or 3.

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

Outputs JSON error to stderr and returns exit code. **Does not exit** -- caller must handle.

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

**External Dependencies**:
```bash
EXIFTOOL_CMD         # Path/command for exiftool
KID3_CMD             # Path/command for kid3-cli
KDECONNECT_CMD       # Path/command for kdeconnect-cli
```

**Optional Dependency Detection** (set by setup wizard):
```bash
RSGAIN_INSTALLED     # true/false - RSGain loudness tool availability
KID3_GUI_INSTALLED   # "kid3"/"kid3-qt"/"none" - Kid3 GUI variant detection
```

These optional dependency flags are detected during `musiclib-cli setup` and used by the GUI to gracefully disable features when tools are unavailable. See Section 2.10 for setup wizard behavior.

**Example**:
```bash
#!/bin/bash
source /usr/lib/musiclib/bin/musiclib_utils.sh || exit 2
load_config

echo "Database: $MUSICDB"
echo "Music repo: $MUSIC_REPO"
echo "RSGain available: $RSGAIN_INSTALLED"
echo "Kid3 GUI variant: $KID3_GUI_INSTALLED"
```

---

## 2. Script Reference (CLI Subcommands)

### 2.1 `musiclib-cli rate` → `musiclib_rate.sh`

**Purpose**: Set star rating (0–5) for a track, update DSV, file tags, and Conky assets.

**Invocation**:
```bash
musiclib_rate.sh STAR_RATING [FILEPATH]
```

**Parameters**:
- `STAR_RATING`: Integer 0–5 (0=unrated, 5=highest)
- `FILEPATH`: *(Optional)* Absolute path to audio file. When provided, rates that specific file directly (GUI mode). When omitted, queries Audacious for the currently playing track (keyboard shortcut mode).

**Behavior by mode**:
- **GUI mode** (`FILEPATH` provided): Requires `kid3-cli`. Does **not** require Audacious to be running. Allows rating any track in the library regardless of playback state.
- **Keyboard shortcut mode** (`FILEPATH` omitted): Requires both `audtool` and `kid3-cli`. Audacious must be running with a track playing. Rates whatever is currently playing.

**Side Effects**:
- Updates `musiclib.dsv` (Rating and GroupDesc columns)
- Updates POPM tag in file (via `kid3-cli`)
- Updates Work/TIT1 tag to match GroupDesc
- Regenerates Conky assets (`starrating.png`, `currgpnum.txt`)
- Logs to `musiclib.log`
- Shows KDE notification (via `kdialog`, if available)

**Exit Codes**:
- 0: Success
- 1: Invalid rating, no track playing (shortcut mode only), file not found
- 2: `kid3-cli` unavailable, DB lock timeout, tag write failed

**Examples**:
```bash
# GUI mode: rate specific file
musiclib-cli rate 4 "/mnt/music/Pink Floyd/Dark Side/Money.mp3"

# Keyboard shortcut mode: rate currently playing track
musiclib-cli rate 5
```

**Equivalent GUI**: Library view → select track → star rating widget

---

### 2.2 `musiclib-cli mobile` → `musiclib_mobile.sh`

Mobile playlist and accounting operations.

#### 2.2.1 `musiclib-cli mobile upload` → `musiclib_mobile.sh upload`

**Purpose**: Upload a playlist to mobile device via KDE Connect and perform last-played accounting on the previously active playlist.

**Invocation**:
```bash
musiclib_mobile.sh upload <playlist_name> [options]
```

**Parameters**:
- `<playlist_name>`: Playlist basename (without extension). Matched against Audacious playlists using title-extraction and sanitization logic.

**Flags**:
- `--device <device_id>`: Override default KDE Connect device ID
- `--end-time "MM/DD/YYYY HH:MM:SS"`: Override accounting window end time (defaults to current time)
- `--non-interactive`: Auto-refresh from Audacious without prompts (for GUI use)

**Workflow**:

**Phase A (Accounting - Previous Playlist)**:
1. Read current active playlist from metadata
2. If a previous playlist exists and differs from upload target:
   a. Calculate accounting window (last upload time → end-time parameter or now)
   b. Validate window (minimum 1 hour, warn if >40 days)
   c. Generate synthetic `LastTimePlayed` timestamps for tracks (exponential distribution)
   d. Update `musiclib.dsv` and file tags (`Songs-DB_Custom1`)
   e. Write recovery files (`.pending_tracks`, `.failed`) if any tracks fail
3. If accounting fully succeeds, clean up previous playlist metadata

**Phase B (Upload - New Playlist)**:
1. Search Audacious playlists directory for matching playlist
2. If `--non-interactive`: auto-copy from Audacious to MusicLib playlists directory
3. Sanitize playlist (URL-decode paths, validate track existence)
4. Convert to `.m3u` format
5. Send to device via `kdeconnect-cli --share`
6. Record new playlist as current active playlist with upload timestamp

**Side Effects**:
- Acquires DB lock for duration of accounting processing
- Updates `LastTimePlayed` in DSV and file tags for previous playlist tracks
- Creates recovery files if accounting partially fails
- Copies playlist from Audacious to MusicLib playlists directory (if `--non-interactive`)
- Sends `.m3u` file to mobile device
- Writes metadata files: `current_playlist`, `<playlist>.meta`, `<playlist>.tracks`
- Logs to `mobile_operations.log`

**Exit Codes**:
- 0: Full success (accounting + upload complete)
- 1: Partial failure (recovery files written, upload may have succeeded)
- 2: System error (DB lock timeout, device not reachable, schema error, clock skew)

**Examples**:
```bash
# Interactive upload with prompts
musiclib_mobile.sh upload workout

# GUI invocation (non-interactive, auto-refresh)
musiclib_mobile.sh upload workout.audpl --non-interactive

# Backdate the accounting window end time
musiclib_mobile.sh upload workout.audpl --end-time "02/15/2026 21:00:00"
```

**Equivalent GUI**: Mobile panel → Select playlist → Select device → Upload

**Configuration Variables**:
| Variable | Default | Purpose |
|----------|---------|---------|
| `DEVICE_ID` | *(none)* | Default KDE Connect device ID |
| `AUDACIOUS_PLAYLISTS_DIR` | `~/.config/audacious/playlists` | Source directory for Audacious playlist sync |
| `MIN_PLAY_WINDOW` | `3600` (1 hour) | Minimum time window in seconds for accounting to proceed |
| `MOBILE_WINDOW_DAYS` | `40` | Maximum time window in days before warning |

---

#### 2.2.2 `musiclib-cli mobile status` → `musiclib_mobile.sh status`

**Purpose**: Show current mobile playlist tracking status, recovery file state, and recent operations.

**Invocation**:
```bash
musiclib_mobile.sh status
```

**Output** (stdout, human-readable):
```
Current mobile playlist: workout
Uploaded: 02/05/2026 14:32:18 (14 days ago)
Tracks: 42

No recovery files (all accounting clean)

Metadata files in mobile directory:
  2 files (clean)

Mobile operations log:
  Location: /home/user/.local/share/musiclib/logs/mobile/mobile_operations.log
  Size: 24 KB

Recent operations (last 5):
  [2026-02-05 14:32:18] [INFO] [UPLOAD] Upload complete: workout.m3u (42 tracks, 287.3 MB)
  ...
```

When recovery files exist, the output includes:
```
Recovery files (require attention):
  workout.pending_tracks: 3 tracks
  workout.failed: 1 tracks
```

When orphaned metadata files are detected:
```
Metadata files in mobile directory:
  Warning: 6 metadata files found (expected 2)
  Run 'musiclib_mobile.sh cleanup' to remove orphaned files
```

**Exit Codes**:
- 0: Success (including when no playlist is active — prints "No mobile playlist currently active")

---

#### 2.2.3 `musiclib-cli mobile retry` → `musiclib_mobile.sh retry`

**Purpose**: Re-attempt synthetic timestamp writes for tracks that failed during a previous accounting pass. Reads `.pending_tracks` and/or `.failed` recovery files for the named playlist.

**Invocation**:
```bash
musiclib_mobile.sh retry <playlist_name>
```

**Parameters**:
- `<playlist_name>`: Playlist basename (without extension), matching the recovery file prefix

**Behavior**:
- For `.pending_tracks` entries: checks whether the track now exists in the database (user may have imported it via `musiclib_new_tracks.sh`), then applies the stored synthetic timestamp
- For `.failed` entries: re-attempts the DB update and tag write directly
- Updates or removes recovery files based on results
- If all recovery files are fully resolved and the playlist is not the current active playlist, cleans up the associated `.meta`/`.tracks` metadata

**Side Effects**:
- Acquires DB lock for duration of retry processing
- Updates `LastTimePlayed` in DSV and `Songs-DB_Custom1` tags for resolved tracks
- Removes fully resolved recovery files
- May remove `.meta`/`.tracks` for resolved non-current playlists

**Exit Codes**:
- 0: Success (or no recovery files found — informational message printed)
- 2: DB lock timeout, database validation failure

**Example**:
```bash
musiclib_mobile.sh retry workout
```

**Equivalent GUI**: Mobile panel → Recovery section → Retry button

---

#### 2.2.4 `musiclib-cli mobile update-lastplayed` → `musiclib_mobile.sh update-lastplayed`

**Purpose**: Manually trigger synthetic last-played timestamp processing for a named playlist without performing an upload. Useful for re-running accounting independently of the upload workflow.

**Invocation**:
```bash
musiclib_mobile.sh update-lastplayed <playlist_name> [--end-time "MM/DD/YYYY HH:MM:SS"]
```

**Parameters**:
- `<playlist_name>`: Playlist basename (without extension)

**Flags**:
- `--end-time "MM/DD/YYYY HH:MM:SS"`: Override the end timestamp for the accounting window. Defaults to current time.

**Behavior**:
Runs the same Phase A accounting logic as `upload`, but without Phase B. Processes the named playlist as if it were the "previous" playlist being replaced.

**Exit Codes**:
- 0: All tracks processed successfully (or no previous playlist to process)
- 1: Partial failure — recovery files written (`.pending_tracks` and/or `.failed`)
- 2: System error (DB lock timeout, schema error, clock skew)

**Example**:
```bash
# Process with current time as window end
musiclib_mobile.sh update-lastplayed workout

# Process with specific end time
musiclib_mobile.sh update-lastplayed workout --end-time "02/15/2026 21:00:00"
```

**Equivalent GUI**: Mobile panel → Accounting section → Update Last-Played

---

#### 2.2.5 `musiclib-cli mobile refresh-audacious-only` → `musiclib_mobile.sh refresh-audacious-only`

**Purpose**: Scan the Audacious playlists directory and copy all playlists to the MusicLib playlists directory. No mobile upload or accounting is performed.

**Invocation**:
```bash
musiclib_mobile.sh refresh-audacious-only
```

**Behavior**:
1. Scan `AUDACIOUS_PLAYLISTS_DIR` for `.audpl` files
2. Extract playlist titles from files
3. Sanitize titles to filesystem-safe names
4. Copy to `MUSICLIB_PLAYLISTS_DIR` with sanitized names
5. Log operations

**Side Effects**:
- Copies playlist files (overwrites if already present)
- Logs to `mobile_operations.log`

**Exit Codes**:
- 0: Success (including when no playlists found)

**Example**:
```bash
musiclib_mobile.sh refresh-audacious-only
```

**Equivalent GUI**: Mobile panel → Refresh Playlists button (without upload)

---

#### 2.2.6 `musiclib-cli mobile logs` → `musiclib_mobile.sh logs`

**Purpose**: View the mobile operations log with optional filtering.

**Invocation**:
```bash
musiclib_mobile.sh logs [filter]
```

**Parameters**:
- `[filter]`: *(Optional)* One of: `errors`, `warnings`, `stats`, `today`. When omitted, shows last 50 lines.

**Filter Behavior**:
| Filter | Output |
|--------|--------|
| *(none)* | Last 50 log lines |
| `errors` | Last 20 lines matching `[ERROR]` |
| `warnings` | Last 20 lines matching `[WARN]` |
| `stats` | Last 10 lines matching `[STATS]` |
| `today` | All lines matching today's date (`YYYY-MM-DD`) |

**Exit Codes**:
- 0: Success (including when log file doesn't exist — informational message printed)
- 1: Unknown filter value

**Example**:
```bash
musiclib_mobile.sh logs
musiclib_mobile.sh logs errors
musiclib_mobile.sh logs today
```

**Equivalent GUI**: Mobile panel → Log viewer

---

#### 2.2.7 `musiclib-cli mobile cleanup` → `musiclib_mobile.sh cleanup`

**Purpose**: Remove orphaned `.meta` and `.tracks` files from the mobile metadata directory. Preserves files for the current playlist and any playlists with active recovery files. Equivalent GUI: Mobile panel → Maintenance section → Cleanup

**Invocation**:
```bash
musiclib_mobile.sh cleanup
```

**Behavior**:
1. Identifies the current active playlist from `current_playlist` file
2. Scans `MOBILE_DIR` for `.meta` and `.tracks` files
3. Preserves: current playlist files, any files with corresponding `.pending_tracks` or `.failed` recovery files
4. Removes all other `.meta`/`.tracks` files

**Exit Codes**:
- 0: Success (including when no orphaned files found, or no current playlist set)

**Example**:
```bash
musiclib_mobile.sh cleanup
```

---

#### 2.2.8 `musiclib-cli mobile check-update` → `musiclib_mobile.sh check-update`

**Purpose**: Check whether the Audacious playlists directory contains a newer (or entirely new) version of the named playlist compared to the MusicLib playlists directory copy. Intended for GUI pre-flight checks before upload — enables the "halt if Audacious version is newer" workflow without requiring the GUI to replicate the script's title-matching and sanitization logic.

**Invocation**:
```bash
musiclib_mobile.sh check-update <playlist_name>
```

**Parameters**:
- `<playlist_name>`: Playlist basename (without extension). Matched against Audacious playlists using the same title-extraction and sanitization logic as `refresh-audacious-only` (URL-decode, sanitize to safe filename, case-insensitive comparison).

**Output** (stdout, machine-readable):
```
STATUS:newer
```

Possible status values:

| Status | Meaning | Exit Code |
|--------|---------|-----------|
| `newer` | Audacious version has a more recent modification time | 0 |
| `new` | Playlist exists in Audacious but not in MusicLib playlists directory | 0 |
| `same` | Modification times are equal or MusicLib version is newer | 1 |
| `not_found` | Playlist not found in Audacious playlists directory | 1 |

**Exit Codes**:
- 0: Newer or new version found (action may be needed)
- 1: Same, older, or not found (safe to proceed)

**Side Effects**: None. Read-only operation.

**Example**:
```bash
# Check if workout playlist has a newer Audacious version
musiclib_mobile.sh check-update workout
# Output: STATUS:newer (exit 0)

# Check a playlist that hasn't changed
musiclib_mobile.sh check-update oldmix
# Output: STATUS:same (exit 1)
```

**Equivalent GUI**: Mobile panel → "Halt if Audacious version is newer" checkbox. When checked, the GUI calls `check-update` before invoking `upload`. If the result is `STATUS:newer` or `STATUS:new`, the GUI shows a dialog and halts the upload. When unchecked, the GUI skips `check-update` entirely and `--non-interactive` auto-refreshes as usual.

**Implementation Note**: This subcommand calls the existing `check_playlist_updates()` internal function and outputs its `PLAYLIST_STATUS` variable. No new logic is introduced — it exposes an existing capability as a machine-readable subcommand.

---

### 2.3 `musiclib-cli build` → `musiclib_build.sh`

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

### 2.4 `musiclib-cli tagclean` → `musiclib_tagclean.sh`

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

### 2.5 `musiclib-cli tagrebuild` → `musiclib_tagrebuild.sh`

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

### 2.6 `musiclib-cli boost` → `boost_album.sh`

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

**Optional Dependency**: This command requires `rsgain` to be installed. If `RSGAIN_INSTALLED=false` in `musiclib.conf`, the GUI will disable the Boost Album feature with an informative tooltip. See Section 1.5 and Section 2.10 for dependency detection.

---

### 2.7 `musiclib-cli scan` → `audpl_scanner.sh`

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

### 2.8 `musiclib-cli new-tracks` → `musiclib_new_tracks.sh`

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
3. Group files by album (auto-detect or prompt)
4. Normalize tags (ID3v2.4, strip APE/ID3v1)
5. Optionally apply rsgain loudness normalization
6. Rename files to lowercase with underscores
7. Move to `MUSIC_REPO/artist/album/`
8. Extract album art to `folder.jpg`
9. Add to `musiclib.dsv`

**Side Effects**:
- Moves files from source to `MUSIC_REPO`
- Modifies tags
- Adds rows to `musiclib.dsv`
- Creates `folder.jpg` for each album
- Logs to `musiclib.log`

**Exit Codes**:
- 0: Success
- 1: No files found, user cancelled, dry-run complete
- 2: Tool unavailable, DB lock timeout, I/O error

**Example**:
```bash
# Interactive mode
musiclib-cli new-tracks

# Non-interactive mode
musiclib-cli new-tracks "Pink Floyd" --source ~/Downloads/new_album

# Preview only
musiclib-cli new-tracks --dry-run
```

**Equivalent GUI**: Maintenance panel → Import Operations → Import New Tracks

---

### 2.9 `musiclib-cli audacious` → `musiclib_audacious.sh`

**Purpose**: Audacious Song Change hook for Conky display and scrobble tracking.

**Invocation**:
```bash
musiclib_audacious.sh
```

**Called By**: Audacious Song Change plugin (automatic on track change)

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

**Setup**: Configured during `musiclib-cli setup`, which detects Audacious, provides Song Change plugin instructions, and optionally verifies the integration. See section 2.10.

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

### 2.10 `musiclib-cli setup` → `musiclib_init_config.sh`

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
7. **Detect optional dependencies**:
   a. Check for RSGain installation (`rsgain` command availability)
   b. Detect Kid3 GUI variants (`kid3` for KDE version, `kid3-qt` for standalone Qt version)
   c. Prompt user with installation instructions if optional dependencies are missing
   d. Set configuration flags: `RSGAIN_INSTALLED` (true/false), `KID3_GUI_INSTALLED` ("kid3"/"kid3-qt"/"none")
8. Generate `musiclib.conf` with detected values
9. If Audacious detected:
   a. Display step-by-step Song Change plugin setup instructions
   b. Optionally verify integration (check Audacious running, test hook, validate Conky output)
10. Offer to build initial database via `musiclib_build.sh`
11. Display next-steps summary

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

**Configuration File Generated**:
```bash
# Core paths
MUSICDB="${MUSICLIB_DATA_DIR}/data/musiclib.dsv"
MUSIC_REPO="/mnt/music"
DOWNLOAD_DIR="$HOME/Downloads"

# External dependencies (detected)
EXIFTOOL_CMD="exiftool"
KID3_CMD="kid3-cli"
KDECONNECT_CMD="kdeconnect-cli"

# Optional dependency detection (new in Phase 2)
RSGAIN_INSTALLED=true
KID3_GUI_INSTALLED="kid3-qt"

# Audacious integration
AUDACIOUS_INSTALLED=true
AUDACIOUS_PATH="/usr/bin/audacious"
```

**GUI Impact**: The GUI reads `RSGAIN_INSTALLED` and `KID3_GUI_INSTALLED` from the configuration to gracefully disable features when optional tools are unavailable:
- If `RSGAIN_INSTALLED=false`: Boost Album section in Maintenance panel is grayed out with tooltip explaining RSGain is required
- If `KID3_GUI_INSTALLED="none"`: Kid3 toolbar button is disabled with tooltip explaining which package to install

**Dependency Detection Details**:
- **RSGain**: Checks for `rsgain` command in PATH. Used for album loudness normalization (Boost Album feature).
- **Kid3 GUI**: Checks for `kid3` (KDE-integrated) and `kid3-qt` (standalone Qt) executables. Note that `kid3-common` (CLI) is a required dependency and always checked separately.
- Missing dependencies trigger user-friendly installation prompts with package names for major distributions (Arch, Debian/Ubuntu, Fedora).

---

### 2.11 `musiclib-cli remove-record` → `musiclib_remove_record.sh`

**Purpose**: Remove a single track record from the database by file path. The audio file itself is **not** deleted — only the DSV row is removed.

**Invocation**:
```bash
musiclib_remove_record.sh FILEPATH
```

**Parameters**:
- `FILEPATH`: Absolute path to the audio file whose database record should be removed. The file does not need to exist on disk (allows removal of orphaned records).

**Workflow**:
1. Source `musiclib_utils.sh`, load config
2. Validate argument (non-empty filepath)
3. Acquire database lock via `with_db_lock` (up to 3 attempts, 2 s timeout each)
4. Call `delete_record_by_path()` which:
   - Searches `musiclib.dsv` for exactly one row matching the path
   - If zero matches: returns 1 (track not found)
   - If multiple matches: returns 1 (duplicate safety guard)
   - If exactly one match: rewrites DSV without the target row
5. On lock timeout after all retries: exit 2
6. Log removal and show KDE notification on success

**Side Effects**:
- Removes one row from `musiclib.dsv`
- Logs to `musiclib.log`
- Shows `kdialog` passive popup notification (success or failure)

**Exit Codes**:
- 0: Success (record removed)
- 1: User/validation error — empty argument, track not found in DB, multiple matches (duplicate records)
- 2: System error — config load failure, DB file not found, lock timeout, I/O error during rewrite

**Examples**:
```bash
# Remove a specific track's database record
musiclib-cli remove-record "/mnt/music/Pink Floyd/Dark Side/Money.mp3"

# Remove an orphaned record (file was already deleted from disk)
musiclib_remove_record.sh "/mnt/music/deleted/old_track.mp3"
```

**Equivalent GUI**: Library view → right-click track row → "Remove Record" → confirm dialog

**Safety Notes**:
- `delete_record_by_path()` refuses to act if the path matches more than one row (prevents accidental mass deletion from substring matches). The user must resolve duplicates manually before retrying.
- The audio file is never touched. To also delete the file, the user must do so separately via their file manager.
- The `QFileSystemWatcher` on `musiclib.dsv` will automatically trigger a model refresh in the GUI after the DSV is rewritten, so the removed row disappears from the table view without a manual reload.

**Dependencies**:
- `musiclib_utils.sh` (provides `load_config`, `with_db_lock`, `delete_record_by_path`, `error_exit`, `log_message`)
- `kdialog` (optional, for desktop notifications)

---

## 3. GUI Integration Points

### 3.1 Script Invocation from C++

**Pattern**: Use `QProcess` for async execution, capture stdout/stderr separately.

**Example**:
```cpp
QProcess* process = new QProcess(this);
process->setProgram("/usr/lib/musiclib/bin/musiclib_rate.sh");
process->setArguments({"4", filepath});

connect(process, &QProcess::finished, this, [=](int exitCode, QProcess::ExitStatus status) {
    if (exitCode == 0) {
        // Success - update UI
        reloadCurrentView();
    } else {
        // Error - parse JSON from stderr
        QByteArray errorJson = process->readAllStandardError();
        handleScriptError(errorJson);
    }
    process->deleteLater();
});

process->start();
```

### 3.2 JSON Error Parsing

```cpp
void MainWindow::handleScriptError(const QByteArray& errorJson) {
    QJsonDocument doc = QJsonDocument::fromJson(errorJson);
    QJsonObject obj = doc.object();
    
    QString errorMsg = obj["error"].toString();
    int errorCode = obj["code"].toInt();
    QJsonObject context = obj["context"].toObject();
    
    if (errorCode == 2) {
        // System error - show detailed technical message
        QMessageBox::critical(this, "System Error", errorMsg);
    } else {
        // User error - show friendly message
        QMessageBox::warning(this, "Invalid Input", errorMsg);
    }
}
```

### 3.3 DSV File Monitoring

The GUI watches `musiclib.dsv` for external changes (scripts, concurrent instances):

```cpp
QFileSystemWatcher* watcher = new QFileSystemWatcher(this);
watcher->addPath(configPath("MUSICDB"));

connect(watcher, &QFileSystemWatcher::fileChanged, this, [=]() {
    // File externally modified - reload model
    libraryModel->reload();
});
```

**Caveat**: Watcher fires on lock file changes too. Use debounce timer (500ms) to avoid redundant reloads.

---

## 4. CLI Dispatcher Implementation

### 4.1 Subcommand Routing

The `musiclib-cli` dispatcher maps subcommands to scripts:

```cpp
// musiclib-cli.cpp
int main(int argc, char* argv[]) {
    if (argc < 2) {
        showUsage();
        return 1;
    }
    
    std::string subcommand = argv[1];
    
    if (subcommand == "rate") {
        return execScript("/usr/lib/musiclib/bin/musiclib_rate.sh", argc - 2, argv + 2);
    } else if (subcommand == "mobile") {
        return execScript("/usr/lib/musiclib/bin/musiclib_mobile.sh", argc - 2, argv + 2);
    } else if (subcommand == "setup") {
        return execScript("/usr/lib/musiclib/bin/musiclib_init_config.sh", argc - 2, argv + 2);
    } else if (subcommand == "remove-record") {
        return execScript("/usr/lib/musiclib/bin/musiclib_remove_record.sh", argc - 2, argv + 2);
    } else {
        std::cerr << "Unknown subcommand: " << subcommand << "\n";
        return 1;
    }
}
```

### 4.2 Script Execution Wrapper

```cpp
int execScript(const std::string& scriptPath, int argc, char* argv[]) {
    std::vector<const char*> args;
    args.push_back(scriptPath.c_str());
    for (int i = 0; i < argc; ++i) {
        args.push_back(argv[i]);
    }
    args.push_back(nullptr);
    
    execv(scriptPath.c_str(), const_cast<char* const*>(args.data()));
    
    // execv only returns on error
    std::cerr << "Failed to execute script: " << scriptPath << "\n";
    return 2;
}
```

**Example** (`musiclib-cli rate`):
```cpp
int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: musiclib-cli rate RATING [FILEPATH]\n";
        return 1;
    }

    std::string scriptPath = "/usr/lib/musiclib/bin/musiclib_rate.sh";
    std::vector<std::string> args = {argv[1]};  // RATING
    if (argc >= 3)
        args.push_back(argv[2]);                // optional FILEPATH

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
/usr/lib/musiclib/bin/musiclib_remove_record.sh
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

### 10.2 `conform_musiclib.sh` -- Filename Conformance Tool

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
**Last Updated**: 2026-02-25  
**Status**: Implementation-Ready
