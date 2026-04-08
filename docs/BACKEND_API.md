# MusicLib Backend API Contract v1.6

## Document Purpose

Canonical specification of the interface between `musiclib` GUI, `musiclib-cli` dispatcher, and shell scripts. All backend scripts must conform to this contract to ensure reliable integration.

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

**Current Status**: Exit code 3 (deferred operations) is **implemented** via `musiclib_process_pending.sh`. When `musiclib_rate.sh` encounters a lock timeout, it writes the pending operation to `.pending_operations` and exits 3. The process pending script retries these automatically.

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

**Status**: Deferred operations queue (exit code 3) is **implemented** via `musiclib_process_pending.sh`. Lock timeouts in `musiclib_rate.sh` write to `.pending_operations` and exit 3; the pending processor retries them automatically.

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
- On timeout: exit 3, write operation to `.pending_operations`, auto-retry via `musiclib_process_pending.sh`
- Both `rate` and `add_track` operations are fully retried by the processor (see §1.6 for operation type details)

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

**K3b-specific paths** (written by the GUI, not by shell scripts):

| File | Purpose |
|---|---|
| `~/.config/musiclib/k3brc` | MusicLib's managed K3b configuration. Written by `generate_k3brc` at setup; patched on every panel control change. |
| `~/.config/k3brc` | K3b's live config. Deployed from `~/.config/musiclib/k3brc` by `deployK3brc()` before each K3b launch. Never written by setup directly. |
| `~/.config/musiclib/k3b.pid` | PID of the K3b process last launched by MusicLib. Written at launch, cleared on exit detection or PID mismatch at startup. |
| `~/.config/musiclib/backups/k3brc_bak_MMDDYYYY_N` | Dated backups of `~/.config/musiclib/k3brc` created on setup re-run. |

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
DEFAULT_GROUP_DESC   # Default group descriptor index for new tracks (0-5)
BACKUP_RETENTION     # Backup retention period (days)
BACKUP_AGE_DAYS      # Maximum age for tag backups before pruning (days)
TAG_BACKUP_DIR       # Directory for tag backups before modifications
LOCK_TIMEOUT         # Lock timeout (seconds)
LOGFILE              # Main log file path
AUDACIOUS_PLAYLISTS_DIR  # Audacious playlists directory (~/.config/audacious/playlists)
SCROBBLE_THRESHOLD_PCT   # Percent of track played before scrobbling (default: 50)
MOBILE_WINDOW_DAYS       # Maximum mobile accounting window in days (default: 40)
MIN_PLAY_WINDOW          # Minimum accounting window in seconds (default: 3600)
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
K3B_INSTALLED        # true/false - K3b CD ripper availability
```

**CD Ripping Settings** (K3b integration; managed by the CD Ripping panel and setup wizard):
```bash
K3B_CMD              # k3b command/path (default: "k3b")
K3B_ENCODER_FORMAT   # "mp3"/"ogg"/"flac" - rip output format (auto-detected from library; omitted when mp3, the system default)
K3B_MP3_MODE         # "cbr"/"vbr"/"abr" - MP3 encoding mode (default: cbr)
K3B_MP3_BITRATE      # CBR bitrate in kbps (default: 320; used when K3B_MP3_MODE=cbr)
K3B_MP3_VBR_QUALITY  # VBR quality 0-9, 0=best (default: 2; used when K3B_MP3_MODE=vbr)
K3B_MP3_ABR_TARGET   # ABR target bitrate in kbps (default: 192; used when K3B_MP3_MODE=abr)
K3B_OGG_QUALITY      # Ogg Vorbis quality 0-10, 10=best (default: 6; used when K3B_ENCODER_FORMAT=ogg)
K3B_PARANOIA_MODE    # cdparanoia mode: 0=off, 1=overlap, 2=never skip, 3=full paranoia (default: 0)
K3B_READ_RETRIES     # Sector read retry count before giving up (default: 5)
```

These keys are written to `~/.config/musiclib/musiclib.conf` (user overrides layer) by the CD Ripping panel when controls change. System defaults live in `/usr/lib/musiclib/config/musiclib.conf`. Shell scripts do not read or write these keys directly — they are read by `patch_k3brc()` in `musiclib_init_config.sh` and by the C++ `CDRippingPanel` class.

**Note**: GUI-only preferences (poll interval, system tray close/minimize behavior, start minimized) are stored in KConfig (`~/.config/musiclibrc`) rather than `musiclib.conf`, since they have no meaning to shell scripts.

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

### 1.6 Pending Operations File Format

`~/.local/share/musiclib/data/.pending_operations` is a plain-text queue used to defer operations that fail due to a database lock timeout. It is written by individual scripts on lock failure and consumed by `musiclib_process_pending.sh` on the next retry cycle.

**Wire format** — one operation per line, pipe-delimited:

```
TIMESTAMP|script|operation|remaining_args
```

| Field | Type | Description |
|-------|------|-------------|
| `TIMESTAMP` | Unix epoch (integer) | Time the operation was queued (`date +%s`) |
| `script` | string | Originating script filename, e.g. `musiclib_rate.sh` |
| `operation` | string | Operation type key; see table below |
| `remaining_args` | string | Operation-specific payload; itself pipe-delimited |

**Defined operation types and their `remaining_args` layouts**:

| `operation` | `remaining_args` layout | Writer | Handled by processor? |
|-------------|------------------------|--------|-----------------------|
| `rate` | `filepath\|star_rating` | `musiclib_rate.sh` | Yes |
| `add_track` | `filepath\|lastplayed` | `musiclib_new_tracks.sh` | Yes |

**All operation types are handled.** Both `rate` and `add_track` operations are retried by the processor. Unknown operation types are logged and removed (not re-queued).

**Constraints**:
- The `|` character is the field delimiter. A filepath containing a literal `|` would corrupt the record; no current validation guards against this.
- Lines are removed by `musiclib_process_pending.sh` after successful retry via `grep -xvFf` exact-line matching — the full raw line must round-trip identically.
- Unknown `operation` values are logged and removed (not re-queued).

**Writers**: `musiclib_rate.sh`, `musiclib_new_tracks.sh`
**Reader**: `musiclib_process_pending.sh`

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

**POPM Mapping**:
The exact POPM byte written for each star level is driven by `POPM_STAR1`–`POPM_STAR5` in `musiclib.conf` (system defaults: `1, 64, 128, 196, 255`). These can be overridden in the user config layer (`~/.config/musiclib/musiclib.conf`). The script falls back to the same defaults if the variables are unset. Note: `RatingGroup1`–`RatingGroup5` define POPM *range boundaries* for smart playlist eligibility logic and are independent of these write values.

**Side Effects**:
- Updates `musiclib.dsv` (Rating and GroupDesc columns)
- Updates POPM tag in file (via `kid3-cli`) using the `POPM_STAR*` mapped value
- Updates Work/TIT1 tag to match GroupDesc
- Writes `user.baloo.rating` filesystem extended attribute (`GroupDesc × 2`, range 0–10) so Dolphin's Rating column stays in sync without a Baloo indexing sweep
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

### 2.1.1 `musiclib_baloo_sync.sh` (standalone utility)

**Purpose**: One-shot back-fill of Dolphin/Baloo star ratings from the MusicLib database. Run this once after installing the Baloo integration, or any time ratings written before the integration was added need to be synced to the filesystem.

**Background**: Dolphin reads its Rating column from the `user.baloo.rating` filesystem extended attribute. Baloo does not natively map ID3 POPM frames to this attribute. `musiclib_rate.sh` now writes the attribute on every new rating, but existing rated tracks must be back-filled. This script reads `GroupDesc` from every row in `musiclib.dsv` and writes `user.baloo.rating = GroupDesc × 2` to the corresponding file, mapping MusicLib's 0–5 scale to Baloo's 0–10 scale.

**Invocation**:
```bash
musiclib_baloo_sync.sh [--dry-run] [--verbose]
```

**Flags**:
- `--dry-run`: Show what would be written without touching any files
- `--verbose`: Print a status line (`SET` / `SKIP` / `MISSING`) for every track

**Rating Scale Mapping**:

| GroupDesc | Stars | Baloo value (`user.baloo.rating`) |
|-----------|-------|----------------------------------|
| 0 | Unrated | 0 |
| 1 | ★☆☆☆☆ | 2 |
| 2 | ★★☆☆☆ | 4 |
| 3 | ★★★☆☆ | 6 |
| 4 | ★★★★☆ | 8 |
| 5 | ★★★★★ | 10 |

**Side Effects**:
- Writes `user.baloo.rating` extended attribute to audio files via `setfattr`
- Calls `balooctl check` after processing to nudge the indexer (non-fatal if unavailable)
- Logs summary to `musiclib.log`

**Dependencies**: `setfattr` / `getfattr` (from the `attr` package)

**Exit Codes**:
- 0: Success (all files processed)
- 1: Invalid arguments
- 2: `setfattr` not installed, database not found, or one or more files could not be written

**Examples**:
```bash
# Preview what would change (safe, no writes)
musiclib_baloo_sync.sh --dry-run --verbose

# Run the back-fill
musiclib_baloo_sync.sh

# Check progress verbosely
musiclib_baloo_sync.sh --verbose
```

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

**stdout format (GUI-parsed)**:

All progress lines are written to stdout, one per newline. The GUI (`mobile_panel.cpp :: parseProgressLine()`) identifies lines by prefix and ignores all others for progress purposes (they are still displayed verbatim in the log area with color-coding by prefix).

Two line patterns drive the progress bar:

```
ACCOUNTING: Track N/M: <message>
UPLOAD: [N/M] <filename>
```

Where `N` is the current track number and `M` is the total. These are parsed via the regexes `ACCOUNTING:\s*Track\s+(\d+)/(\d+):` and `UPLOAD:\s*\[(\d+)/(\d+)\]`.

One additional pattern signals upload completion:

```
UPLOAD: Complete — N files transferred (X.X MB)
```

The GUI matches this by string prefix (`UPLOAD: Complete`) to set the progress bar label to "Complete". Any change to these prefix spellings, bracket style `[N/M]`, or the `Track N/M:` substring will silently break the GUI's progress bar without a compile error.

**Recovery file formats** (written by this subcommand, read by `retry` — see §2.2.3):

`.pending_tracks` — tracks that were not found in the database during accounting:
```
filepath^synthetic_sql^synthetic_human
```
Three caret-delimited fields. `synthetic_sql` is the SQL-serial timestamp string written to the DSV; `synthetic_human` is the human-readable equivalent for display. No field may contain a literal `^`.

`.failed` — tracks where the DB write or tag write failed:
```
filepath^synthetic_sql^synthetic_human^failure_reason
```
Four caret-delimited fields. `failure_reason` is one of `db_write_failed` or `tag_write_failed`. This is the same layout as `.pending_tracks` with one appended field — do not conflate the two schemas.

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

**Recovery file formats consumed** (written by `upload` — see §2.2.1 for authoritative format spec):

`.pending_tracks`: `filepath^synthetic_sql^synthetic_human` (3 caret-delimited fields)
`.failed`: `filepath^synthetic_sql^synthetic_human^failure_reason` (4 caret-delimited fields)

If `upload` ever changes either format, `retry` must be updated in the same commit or accounting data will be silently misread.

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
- Invokes `musiclib_baloo_sync.sh` after the database is replaced to stamp `user.baloo.rating` extended attributes on all audio files (skipped silently if `setfattr` is absent, or in test/dry-run mode)
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
- `--keep-backup`: Retain the per-file backup after a successful run (default: backup is removed on success)
- `-r`, `--recursive`: Process directories recursively
- `-n`, `--dry-run`: Preview changes without modifying files
- `-v`, `--verbose`: Show detailed processing information

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
- `FILEPATH` (or `DIRECTORY`): Target MP3 file or directory
- `-r`, `--recursive`: Process directories recursively
- `-n`, `--dry-run`: Preview changes without modifying files
- `-v`, `--verbose`: Show detailed processing information
- `--keep-backup`: Retain the per-file backup after a successful run (default: backup is removed on success)
- `-b DIR`, `--backup-dir DIR`: Override the backup directory

**Workflow**:
1. Look up track in `musiclib.dsv` by path (skips files not in DB non-fatally)
2. Create a timestamped binary backup of the file in `TAG_BACKUP_DIR`
3. Read Artist, Album, AlbumArtist, Title, Genre, Rating, GroupDesc, LastTimePlayed, Custom2 from DB
4. Extract non-DB fields (ReplayGain, album art, track number, year, lyrics) from the file before stripping
5. Strip all existing tags from file
6. Write DB-authoritative tags + preserved file metadata via `kid3-cli` and `exiftool`
7. On success: backup is **removed** automatically (unless `--keep-backup` was passed)
8. On failure: backup is **restored** over the original file and an error is reported

**Note**: `musiclib_tagrebuild.sh` reads from `musiclib.dsv` but **never writes back to it**. It is a tag-to-file direction tool only. Running it after a `kid3-cli` manual edit would overwrite those changes with stale DB values. Use it for frame normalization when the DB already reflects the correct intent.

**Side Effects**:
- Overwrites file tags in place
- Creates a timestamped backup (`<file>.backup.YYYYMMDD_HHMMSS`) in `TAG_BACKUP_DIR`; removed on success by default, or retained when `--keep-backup` is used. Backups older than `MAX_BACKUP_AGE_DAYS` (default 30) are purged at the start of each run.
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

### 2.5.1 `musiclib-cli tagrestore` → `musiclib_tagrestore.sh`

**Purpose**: Restore an MP3 file's tags from the most recent backup created by `musiclib_tagrebuild.sh` or `musiclib_tagclean.sh` when run with `--keep-backup`.

**Invocation**:
```bash
musiclib_tagrestore.sh FILEPATH [options]
```

**Parameters**:
- `FILEPATH`: Absolute path to the MP3 file to restore
- `-n`, `--dry-run`: Show what would be restored without overwriting the file
- `-v`, `--verbose`: List all available backups and show extra detail
- `-l`, `--list`: List all available backups for the file and exit without restoring

**Workflow**:
1. Resolve `BACKUP_DIR` from `TAG_BACKUP_DIR` config variable (default: `$(get_data_dir)/data/tag_backups`)
2. Find all files matching `${BACKUP_DIR}/<basename>.backup.*` for the given file
3. If none found: exit 1 with a clear message
4. Sort candidates lexicographically (timestamp suffix `YYYYMMDD_HHMMSS` sorts chronologically); select the most recent
5. Copy the backup over the original file; verify with `cmp`
6. Exit 0; backup file is **not** removed after restore (user retains the ability to restore again or clean up manually)

**Side Effects**:
- Overwrites the target file's contents with the backup copy
- Does **not** modify the backup file
- Does **not** update `musiclib.dsv`
- Logs to stderr only (no `musiclib.log` write)

**Exit Codes**:
- 0: Restore successful (or dry-run/list completed)
- 1: No backup found, file does not exist, or invalid arguments
- 2: Backup found but restore failed (copy or verification error)

**Prerequisite**: Backups only exist if `--keep-backup` was passed to a prior `tagrebuild` or `tagclean` run on the same file.

**Example**:
```bash
# Dry-run to confirm which backup will be used
musiclib-cli tagrestore "/mnt/music/corrupted/song.mp3" -n

# Restore
musiclib-cli tagrestore "/mnt/music/corrupted/song.mp3"

# List all available backups
musiclib-cli tagrestore "/mnt/music/corrupted/song.mp3" -l
```

**Equivalent GUI**: Maintenance panel → Tag Operations → Rebuild Tags → Restore Last Backup *(Tasking 6, not yet implemented)*

---

### 2.6 `musiclib-cli boost` → `musiclib_boost.sh`

**Purpose**: Apply ReplayGain loudness targeting to album (via `rsgain`).

**Invocation**:
```bash
musiclib_boost.sh ALBUM_DIR LOUDNESS
```

**Parameters**:
- `ALBUM_DIR`: Directory containing album `.mp3` files
- `LOUDNESS`: Target loudness as a positive integer (e.g. `16` = -16 LUFS). Higher = quieter, lower = louder. Do not pass a negative value.

**Workflow**:
1. Remove existing ReplayGain tags from all `.mp3` files in `ALBUM_DIR` via `kid3-cli`
2. Re-scan and re-tag with `rsgain` at the requested target loudness (album + track level)

**Side Effects**:
- Rewrites ReplayGain tags in all `.mp3` files directly inside `ALBUM_DIR` (non-recursive)

**Exit Codes**:
- 0: Success
- 1: Missing arguments or `kid3-cli`/`rsgain` not found

**Example**:
```bash
musiclib-cli boost "/mnt/music/Pink Floyd/The Wall" 16
```

**Equivalent GUI**: Maintenance panel → Boost Album → Select directory

**Optional Dependency**: This command requires `rsgain` to be installed. If `RSGAIN_INSTALLED=false` in `musiclib.conf`, both the GUI Boost Album section and the CLI `boost` command are disabled. See Section 1.5 and Section 2.10 for dependency detection.

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
   a. Check for RSGain installation (`rsgain` command availability) → sets `RSGAIN_INSTALLED`
   b. Detect Kid3 GUI variants (`kid3` for KDE version, `kid3-qt` for standalone Qt version) → sets `KID3_GUI_INSTALLED`
   c. Check for K3b installation (`k3b` command availability) → sets `K3B_INSTALLED`
   d. If K3b detected: scan `MUSIC_REPO` for predominant audio format (mp3/ogg/flac) → sets `K3B_ENCODER_FORMAT` if non-default
   e. Set all detected flags in `musiclib.conf`
8. Generate `musiclib.conf` with detected values
8a. If K3b detected: generate `~/.config/musiclib/k3brc` via `generate_k3brc` — prompts user whether to use existing `~/.config/k3brc` as baseline or system template, then patches all musiclib-managed keys via `patch_k3brc`
9. If Audacious detected:
   a. Display step-by-step Song Change plugin setup instructions
   b. Optionally verify integration (check Audacious running, test hook, validate Conky output)
10. Offer to build initial database via `musiclib_build.sh`
11. Display next-steps summary

**Side Effects**:
- Creates `~/.config/musiclib/musiclib.conf`
- Creates `~/.local/share/musiclib/` directory tree (data, logs, playlists)
- If K3b detected: creates `~/.config/musiclib/k3brc` (musiclib's managed K3b config); backs up any pre-existing copy to `~/.config/musiclib/backups/k3brc_bak_MMDDYYYY_N`
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

**Equivalent GUI**: Settings dialog → Advanced tab → re-run setup, or launch `musiclib` for the first time with no config present

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

# Optional dependency detection
RSGAIN_INSTALLED=true
KID3_GUI_INSTALLED="kid3-qt"
K3B_INSTALLED=true
K3B_ENCODER_FORMAT=flac    # written only when non-default (library was predominantly FLAC)

# CD Ripping settings — written only when changed from system defaults by the panel
# (System defaults in /usr/lib/musiclib/config/musiclib.conf take effect if absent here)
# K3B_MP3_MODE=cbr
# K3B_MP3_BITRATE=320
# K3B_MP3_VBR_QUALITY=2
# K3B_MP3_ABR_TARGET=192
# K3B_OGG_QUALITY=6
# K3B_PARANOIA_MODE=0
# K3B_READ_RETRIES=5

# Audacious integration
AUDACIOUS_INSTALLED=true
AUDACIOUS_PATH="/usr/bin/audacious"
```

**GUI Impact**: The GUI reads `RSGAIN_INSTALLED`, `KID3_GUI_INSTALLED`, and `K3B_INSTALLED` from the configuration to gracefully disable features when optional tools are unavailable:
- If `RSGAIN_INSTALLED=false`: Boost Album section in Maintenance panel is grayed out with tooltip explaining RSGain is required
- If `KID3_GUI_INSTALLED="none"`: Kid3 toolbar button is disabled with tooltip explaining which package to install
- If `K3B_INSTALLED=false`: CD Ripping panel is grayed out and toolbar Rip CD action is disabled with tooltip explaining K3b is required

**Dependency Detection Details**:
- **RSGain**: Checks for `rsgain` command in PATH. Used for album loudness normalization (Boost Album feature).
- **Kid3 GUI**: Checks for `kid3` (KDE-integrated) and `kid3-qt` (standalone Qt) executables. Note that `kid3-common` (CLI) is a required dependency and always checked separately.
- **K3b**: Checks for `k3b` command in PATH. When detected, also scans `MUSIC_REPO` to determine the predominant audio format among mp3/ogg/flac files, writes `K3B_ENCODER_FORMAT` if the result differs from the system default (mp3), and calls `generate_k3brc` to create `~/.config/musiclib/k3brc`. If `~/.config/k3brc` already exists, prompts the user whether to use it as the baseline.
- Missing dependencies trigger user-friendly installation prompts with package names for major distributions (Arch, Debian/Ubuntu, Fedora).

---

### 2.11 `musiclib-cli remove-record` → `musiclib_remove_record.sh`

**Purpose**: Remove a single track record from the database by file path. Optionally deletes the audio file from disk as well.

**Invocation**:
```bash
musiclib_remove_record.sh FILEPATH [--delete-file]
```

**Parameters**:
- `FILEPATH`: Absolute path to the audio file whose database record should be removed. The file does not need to exist on disk (allows removal of orphaned records).

**Flags**:
- `--delete-file`: Also delete the audio file from disk after removing the DB record. Default is DB-only removal.

**Workflow**:
1. Source `musiclib_utils.sh`, load config
2. Validate argument (non-empty filepath)
3. Acquire database lock via `with_db_lock` (up to 3 attempts, 2 s timeout each)
4. Call `delete_record_by_path()` which:
   - Searches `musiclib.dsv` for exactly one row matching the path
   - If zero matches: returns 1 (track not found)
   - If multiple matches: returns 1 (duplicate safety guard)
   - If exactly one match: rewrites DSV without the target row
5. If `--delete-file` specified and DB removal succeeded: delete the audio file from disk
6. On lock timeout after all retries: exit 2
7. Log removal and show KDE notification on success

**Side Effects**:
- Removes one row from `musiclib.dsv`
- Optionally deletes the audio file from disk (only with `--delete-file`)
- Logs to `musiclib.log`
- Shows `kdialog` passive popup notification (success or failure)
- `QFileSystemWatcher` on `musiclib.dsv` triggers automatic model refresh in the GUI

**Exit Codes**:
- 0: Success (record removed)
- 1: User/validation error — empty argument, track not found in DB, multiple matches (duplicate records)
- 2: System error — config load failure, DB file not found, lock timeout, I/O error during rewrite

**Examples**:
```bash
# Remove only the database record (file stays on disk)
musiclib-cli remove-record "/mnt/music/Pink Floyd/Dark Side/Money.mp3"

# Remove database record and delete the audio file
musiclib-cli remove-record "/mnt/music/Pink Floyd/Dark Side/Money.mp3" --delete-file

# Remove an orphaned record (file was already deleted from disk)
musiclib_remove_record.sh "/mnt/music/deleted/old_track.mp3"
```

**Equivalent GUI**: Library view → right-click track row → "Remove Record" → confirm dialog (with optional "Delete file" checkbox)

**Safety Notes**:
- `delete_record_by_path()` refuses to act if the path matches more than one row (prevents accidental mass deletion from substring matches). The user must resolve duplicates manually before retrying.
- Without `--delete-file`, the audio file is never touched.
- The `QFileSystemWatcher` on `musiclib.dsv` will automatically trigger a model refresh in the GUI after the DSV is rewritten, so the removed row disappears from the table view without a manual reload.

**Dependencies**:
- `musiclib_utils.sh` (provides `load_config`, `with_db_lock`, `delete_record_by_path`, `error_exit`, `log_message`)
- `kdialog` (optional, for desktop notifications)

---

### 2.12 `musiclib-cli edit-field` → `musiclib_edit_field.sh`

**Purpose**: Update a single metadata field in the database for a specified track record. Accepted fields: `Artist`, `Album`, `AlbumArtist`, `SongTitle`, `Genre`, `Custom2`. For all fields except `Custom2`, only the DSV row is changed; audio file tags are not touched. For `Custom2`, the script also writes `Songs-DB_Custom2` to the audio file tag via `kid3-cli`.

**Invocation**:
```bash
musiclib_edit_field.sh RECORD_ID FIELD_NAME NEW_VALUE
```

**Parameters**:
- `RECORD_ID`: The `ID` field value from the DSV row (column 1). Used to identify the exact record to update.
- `FIELD_NAME`: The DSV column name to update. Must be one of: `Artist`, `Album`, `AlbumArtist`, `SongTitle`, `Genre`, `Custom2`.
- `NEW_VALUE`: Replacement text. Must not contain the `^` delimiter character.

**Workflow**:
1. Source `musiclib_utils.sh`, load config
2. Validate arguments (non-empty record ID, allowed field name, caret-free new value)
3. Acquire database lock via `with_db_lock`
4. Locate the row in `musiclib.dsv` where column 1 matches `RECORD_ID`
5. Identify the column index for `FIELD_NAME` from the DSV header
6. Overwrite that cell in-place, rewrite the DSV atomically
7. If `FIELD_NAME == Custom2`: write `Songs-DB_Custom2` to the audio file tag via `kid3-cli`
8. Log the change and show a `kdialog` notification on success

**Side Effects**:
- Updates one field in one row of `musiclib.dsv`
- `Custom2` only: also writes `Songs-DB_Custom2` tag to the audio file (no tagrebuild step needed for this field)
- Logs to `musiclib.log`
- Shows `kdialog` passive popup notification (success or failure)
- `QFileSystemWatcher` on `musiclib.dsv` triggers automatic model refresh in the GUI

**Exit Codes**:
- 0: Success (field updated)
- 1: User/validation error — missing arguments, unsupported field name, new value contains `^`, record ID not found
- 2: System error — config load failure, DB file not found, lock timeout, I/O error during rewrite

**Examples**:
```bash
# Fix a misspelled artist name (record ID 142)
musiclib-cli edit-field 142 Artist "Pink Floyd"

# Update album title for record ID 87
musiclib-cli edit-field 87 Album "The Wall (Remaster)"

# Set a Custom Artist grouping key so both names are treated as one artist
# in the smart playlist exclusion window (effective artist merging)
musiclib-cli edit-field 203 Custom2 "Petty"
musiclib-cli edit-field 204 Custom2 "Petty"
```

**Equivalent GUI**: Library view → double-click a cell in the Artist, Album, AlbumArtist, Title, Genre, or Custom Artist column → inline editor → press Enter to confirm

**Notes**:
- For all fields except `Custom2`: only DSV metadata is updated. Run `musiclib-cli tagrebuild` on the affected file to also sync the change to audio file tags.
- For `Custom2`: the DSV and the file tag are both updated in one step. No separate tagrebuild is needed.
- The `^` delimiter cannot appear in field values; the script exits 1 if `NEW_VALUE` contains one.
- `Custom2` (displayed as **Custom Artist** in the library view) is the field used by the smart playlist engine as the **effective artist** for exclusion-window purposes. See §2.13–2.14 for details.

**Dependencies**:
- `musiclib_utils.sh` (provides `load_config`, `with_db_lock`, `error_exit`, `log_message`)
- `kid3-cli` (required for `Custom2` tag write; optional for other fields)
- `kdialog` (optional, for desktop notifications)

---

### 2.13 `musiclib-cli smart-playlist analyze` → `musiclib_smartplaylist_analyze.sh`

**Purpose**: Analyze the smart playlist candidate pool. Reads `musiclib.dsv`, applies per-group POPM rating filters and last-played age thresholds, and computes variance weights. Available as a `musiclib-cli` subcommand and called directly by `SmartPlaylistPanel`.

**CLI Invocation**:
```bash
musiclib-cli smart-playlist analyze [options]
```

**Direct Script Invocation**:
```bash
musiclib_smartplaylist_analyze.sh [options]
```

**Options**:

| Flag | Argument | Default | Description |
|------|----------|---------|-------------|
| `-d` | `<delim>` | `^` | Field delimiter for the DSV database |
| `-g` | `G1,G2,G3,G4,G5` | from `SP_AGE_GROUP*` in conf | Comma-separated age thresholds in days per rating group (group 1 = 1★ … group 5 = 5★) |
| `-m` | `counts\|preview\|file` | `preview` | Output mode (see below) |
| `-p` | `<value>` | from `RatingGroup1` low | Minimum POPM value to include |
| `-r` | `<value>` | from `RatingGroup5` high | Maximum POPM value to include |
| `-s` | `<n>` | from `SP_SAMPLE_SIZE` | Sample size for the per-group breakdown |
| `-u` | `L1,L2,L3,L4,L5` | from `RatingGroup1-5` in conf | Comma-separated POPM low bounds for each group |
| `-v` | `H1,H2,H3,H4,H5` | from `RatingGroup1-5` in conf | Comma-separated POPM high bounds for each group |

**Modes**:

- **`counts`** — Fast path. Per-group eligible track count and unique artist count only. No variance computation. Used by the panel's live constraint display (triggered after every threshold change via 500 ms debounce).
- **`preview`** — Full analysis. Per-group eligible count, unique artist count (raw and effective), variance total, sample weight percentage, sample quantity, and Custom2 coverage. Used by the **Preview** button in `SmartPlaylistPanel`.
- **`file`** — Writes the variance-annotated intermediate pool to `~/.local/share/musiclib/data/sp_pool.csv`. Emits a brief JSON status object to stdout. Called internally by `musiclib_smartplaylist.sh` as its first step.

**Effective Artist**: For artist counting and uniqueness, the script uses `Custom2` (the **Custom Artist** field) as the artist identity when it is non-blank. If `Custom2` is blank, `AlbumArtist` is used as the fallback. This is called the *effective artist* throughout. Both column indices are detected dynamically from the DSV header; if `Custom2` is absent from the schema, `AlbumArtist` is used unconditionally.

**JSON output — `-m preview`**:
```json
{
  "status": "ok",
  "total_eligible": 1243,
  "unique_artists_effective": 287,
  "unique_artists_raw": 304,
  "custom2_coverage_pct": 72,
  "groups": [
    {
      "group": 1,
      "stars": 1,
      "popm_low": 1,
      "popm_high": 32,
      "threshold_days": 360,
      "eligible_tracks": 287,
      "unique_artists_effective": 87,
      "unique_artists_raw": 92,
      "custom2_coverage_pct": 68,
      "variance_total": 14.72,
      "sample_weight_pct": 28.4,
      "sample_qty": 6
    }
  ]
}
```

Groups with fewer than 10 eligible tracks include an additional `"warning"` field instead of variance/sample fields:
```json
{ "group": 2, "eligible_tracks": 7, "warning": "below minimum floor of 10; excluded from sampling" }
```

**JSON output — `-m counts`**:
```json
{
  "status": "ok",
  "total_eligible": 1243,
  "unique_artists_effective": 287,
  "unique_artists_raw": 304,
  "custom2_coverage_pct": 72,
  "groups": [
    { "group": 1, "eligible_tracks": 287, "unique_artists_effective": 87, "unique_artists_raw": 92 }
  ]
}
```

**JSON output — `-m file`**:
```json
{ "status": "ok", "pool_file": "/home/user/.local/share/musiclib/data/sp_pool.csv", "pool_size": 1243 }
```

**Error schema** (stderr, any mode, exit 1 or 2):
```json
{"status": "error", "code": 1, "message": "Database not found: /path/to/musiclib.dsv"}
```

**Output files**:
- `-m file` only: `~/.local/share/musiclib/data/sp_pool.csv` — variance-annotated pool, consumed by `musiclib_smartplaylist.sh`

**Exit Codes**:
- 0: Success
- 1: User/validation error — bad flag value, insufficient eligible tracks (pool smaller than `SP_PLAYLIST_SIZE`), database header missing required columns
- 2: System error — config load failure, database unreadable, I/O error writing pool file

**Examples**:
```bash
# Via musiclib-cli (recommended)
musiclib-cli smart-playlist analyze                      # Full preview with defaults
musiclib-cli smart-playlist analyze -m counts            # Fast counts
musiclib-cli smart-playlist analyze -g 720,360,180,90,45 # Custom thresholds
musiclib-cli smart-playlist analyze -m file -g 360,180,90,60,30  # Write pool file

# Direct script invocation (advanced / GUI use)
musiclib_smartplaylist_analyze.sh -m counts
musiclib_smartplaylist_analyze.sh -g 720,360,180,90,45
```

**Dependencies**:
- `musiclib_utils.sh` (provides `load_config`, `error_exit`, `log_message`, `get_data_dir`)
- `awk`, `sort`, `shuf` (coreutils)

---

### 2.14 `musiclib-cli smart-playlist generate` → `musiclib_smartplaylist.sh`

**Purpose**: Generate a variety-optimized M3U playlist from the musiclib database. Delegates pool building to `musiclib_smartplaylist_analyze.sh -m file`, then runs the variance-proportional selection loop with a rolling artist-exclusion window. Optionally loads the result into Audacious. Available as a `musiclib-cli` subcommand and called directly by `SmartPlaylistPanel`.

**CLI Invocation**:
```bash
musiclib-cli smart-playlist generate [options]
```

**Direct Script Invocation**:
```bash
musiclib_smartplaylist.sh [options]
```

**Options**:

| Flag | Argument | Default | Description |
|------|----------|---------|-------------|
| `-e` | `<n>` | from `SP_ARTIST_EXCLUSION_COUNT` | Number of recent unique effective artists to exclude per selection round |
| `-g` | `G1,G2,G3,G4,G5` | from `SP_AGE_GROUP*` | Comma-separated age thresholds in days for groups 1–5 |
| `-n` | `<name>` | `"Smart Playlist"` | Playlist name (without `.m3u` extension); used as the Audacious playlist title |
| `-o` | `<file>` | `${PLAYLISTS_DIR}/<name>.m3u` | Full output file path (overrides `-n` and default directory) |
| `-p` | `<n>` | from `SP_PLAYLIST_SIZE` | Target playlist size (number of tracks) |
| `-s` | `<n>` | from `SP_SAMPLE_SIZE` | Sample size — tracks considered per selection round |
| `-u` | `L1,…,L5` | from `RatingGroup1-5` | POPM low bounds for each group |
| `-v` | `H1,…,H5` | from `RatingGroup1-5` | POPM high bounds for each group |
| `--load-audacious` | (flag) | false | Load the playlist into Audacious after writing |

**Processing steps**:
1. Call `musiclib_smartplaylist_analyze.sh -m file` (with the same `-g`/`-u`/`-v`/`-s` flags) to produce the variance-annotated pool at `~/.local/share/musiclib/data/sp_pool.csv`.
2. Run the main playlist-building loop: variance-proportional batch sampling with a rolling effective-artist exclusion window of size `-e`.
3. Write output `.m3u` to `${PLAYLISTS_DIR}/<name>.m3u` (or the path specified by `-o`).
4. If `--load-audacious`: verify Audacious is running (`pgrep -x audacious`). Search for an existing playlist with the same name; if found, select and clear it; if not found, create a new one. Load each track via `audtool --playlist-addurl`.
5. Emit JSON success object to stdout.

**Progress output** (stdout, during step 2):
The panel's log area receives free-form text lines. Progress bar updates use the prefix:
```
PROGRESS:n:total
```
where `n` is the number of tracks selected so far and `total` is the target playlist size.

**JSON success output** (stdout, on exit 0):
```json
{
  "status": "ok",
  "playlist": "Smart Playlist",
  "tracks": 50,
  "output": "/home/user/.local/share/musiclib/playlists/smart_playlist.m3u"
}
```

**Error schema** (stderr, exit 1 or 2):
```json
{"status": "error", "code": 2, "message": "Audacious is not running"}
```

**Output files**:
- `${PLAYLISTS_DIR}/<name>.m3u` — the generated playlist (always written)
- `~/.local/share/musiclib/data/sp_pool.csv` — intermediate pool (written by analyze script, overwritten on each run)

**Exit Codes**:
- 0: Success — playlist written (and loaded into Audacious if `--load-audacious` was set)
- 1: User/validation error — bad flag values, playlist size larger than eligible pool
- 2: System error — config load failure, analyze script failed, Audacious not running when `--load-audacious` requested, I/O error writing `.m3u`

**Examples**:
```bash
# Via musiclib-cli (recommended)
musiclib-cli smart-playlist generate --load-audacious              # Default playlist, load into Audacious
musiclib-cli smart-playlist generate -p 100 -n "Evening Mix" -g 180,90,45,30,14
musiclib-cli smart-playlist generate -o ~/Music/playlist.m3u

# Direct script invocation (advanced / GUI use)
musiclib_smartplaylist.sh --load-audacious
musiclib_smartplaylist.sh -p 100 -g 180,90,45,30,14 -n "Evening Mix"
```

**Dependencies**:
- `musiclib_smartplaylist_analyze.sh` (pool building)
- `musiclib_utils.sh` (provides `load_config`, `error_exit`, `log_message`, `get_data_dir`)
- `audtool` (required only for `--load-audacious`)
- `pgrep` (required only for `--load-audacious`)
- `awk`, `shuf` (coreutils)

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

### 3.4 CDRippingPanel Public Interface

`CDRippingPanel` exposes three members used by `MainWindow` for the Rip CD toolbar action:

| Member | Type | Purpose |
|---|---|---|
| `runDriftDetection()` | `bool` (public slot) | Compares managed keys between `~/.config/k3brc` and `~/.config/musiclib/k3brc`. Returns `true` if drift was detected (banner shown). Called by MainWindow before deciding whether to launch K3b. |
| `patchAndDeployK3brc()` | `void` (public method) | Patches `~/.config/musiclib/k3brc` with current ConfWriter values, then copies it to `~/.config/k3brc`. Called by MainWindow immediately before launching K3b (Scenario A: no drift). |
| `k3bExited()` | `Q_SIGNAL` | Emitted when the poll timer detects the K3b running→not-running transition. MainWindow connects to this to call `clearK3bPid()` and clean up `~/.config/musiclib/k3b.pid`. |

**Toolbar action launch scenarios:**

| Scenario | Condition | Behaviour |
|---|---|---|
| A — Fresh launch | K3b not running | Run drift check. If drift: show banner, return (user resolves via panel). If no drift: `patchAndDeployK3brc()`, launch K3b, write PID file. |
| B — Already running (ours) | PID file exists and matches running process | Raise K3b window via `raiseWindowByClass("k3b")`. No deploy. |
| C — Already running (external) | No PID file or PID mismatch | Raise K3b window. No deploy. Panel shows dimmed state via its own poll timer. |
| D — Startup with K3b open | Detected at MainWindow init | PID match: treat as Scenario B. PID mismatch: clear stale PID file, no dialog. |

---

### 3.5 SmartPlaylistPanel Script Interface

`SmartPlaylistPanel` calls two scripts directly via `QProcess`. Both are invoked with the scripts directory resolved from `ConfWriter` (key `SCRIPTS_DIR`, default `/usr/lib/musiclib/bin`).

**Script calls and triggers**:

| Trigger | Script | Flags |
|---------|--------|-------|
| Threshold spinbox change (500 ms debounce) | `musiclib_smartplaylist_analyze.sh` | `-m counts -g G1,G2,G3,G4,G5` |
| **Preview** button | `musiclib_smartplaylist_analyze.sh` | `-m preview -g G1,G2,G3,G4,G5 -s S` |
| **Generate** button | `musiclib_smartplaylist.sh` | `-p P -e E -g G1,G2,G3,G4,G5 -s S -n "Name" [--load-audacious]` |

Where `G1–G5` are the current age threshold spinbox values, `S` is the sample size, `P` is the playlist size, and `E` is the artist exclusion count.

**stdout parsing — generate script**:
The generate script writes two kinds of lines to stdout during execution:
- `PROGRESS:n:total` — parsed by the panel to advance `m_generateProgress` (value `n`, maximum `total`)
- All other lines — appended verbatim to the `m_generateLog` `QTextEdit`

On process exit, the panel reads the accumulated `m_generateBuffer` and parses the terminal JSON object. Exit 0 with a valid `{"status":"ok",...}` object triggers `playlistGenerated(outputPath)` and a success message. Any other exit code causes the JSON `"message"` field (or the raw stderr) to appear in the log in red.

**stdout parsing — analyze script**:
The panel accumulates all stdout into `m_analyzeBuffer` and parses the complete JSON object on `QProcess::finished`. It does not attempt incremental parsing. The JSON is used to populate `m_cachedStats` and, for `-m preview`, to populate `m_previewTable`.

**Mutual exclusion**: Both the Preview and Generate buttons are disabled (`setBusy(true)`) while any `QProcess` is running. The counts debounce timer is also suppressed while a generate process is active to avoid interfering with the pool file.

**Signal emitted by panel**:

| Signal | Type | Purpose |
|--------|------|---------|
| `playlistGenerated(const QString &path)` | `Q_SIGNAL` | Emitted on successful generation; `MainWindow` connects to this to update the status bar with the output path |

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
    } else if (subcommand == "edit-field") {
        return execScript("/usr/lib/musiclib/bin/musiclib_edit_field.sh", argc - 2, argv + 2);
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
BACKEND_API_VERSION="1.2"
```

GUI/CLI check this on startup:
```cpp
QString apiVersion = getScriptVersion("/usr/lib/musiclib/bin/musiclib_utils.sh");
if (apiVersion != "1.2") {
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

### 8.1 Exit Code 3 — Deferred Operations (Implementation Status)

**Status**: Fully implemented. Queuing and retry are wired for all defined operation types (`rate` and `add_track`).

**What is implemented**:
- `musiclib_rate.sh`: on lock timeout after 3 retries, writes a `rate` record to `.pending_operations` and exits 3. After any successful DB write, it auto-triggers `musiclib_process_pending.sh` in the background.
- `musiclib_new_tracks.sh`: on lock timeout in `add_track_to_database()`, writes an `add_track` record to `.pending_operations` and returns 3. When deferred count > 0, it auto-triggers `musiclib_process_pending.sh` in the background.
- `musiclib_process_pending.sh`: fully handles both `rate` and `add_track` operations. For `add_track`: re-extracts metadata from the file via `kid3-cli`, acquires DB lock, appends the DSV entry, updates file tags, sends a kdialog passive popup, and removes the line from the queue. Stale entries (file no longer exists, track already in database) are removed without error.

**Pending file format**: plain text, pipe-delimited — see §1.6 for full specification.

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
/usr/lib/musiclib/bin/musiclib_boost.sh
/usr/lib/musiclib/bin/audpl_scanner.sh
/usr/lib/musiclib/bin/musiclib_new_tracks.sh
/usr/lib/musiclib/bin/musiclib_audacious.sh
/usr/lib/musiclib/bin/musiclib_remove_record.sh
/usr/lib/musiclib/bin/musiclib_edit_field.sh
/usr/lib/musiclib/bin/musiclib_utils.sh
/usr/lib/musiclib/bin/musiclib_utils_tag_functions.sh
/usr/lib/musiclib/bin/musiclib_smartplaylist_analyze.sh
/usr/lib/musiclib/bin/musiclib_smartplaylist.sh
```

### Config File

```
~/.config/musiclib/musiclib.conf
```

### User Data

```
~/.local/share/musiclib/data/musiclib.dsv
~/.local/share/musiclib/data/sp_pool.csv
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

**Document Version**: 1.2
**Last Updated**: 2026-03-05
**Status**: Current — reflects MusicLib v1.2
