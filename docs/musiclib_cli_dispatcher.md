# MusicLib-CLI Dispatcher: Command Reference

**Document Purpose**: Canonical CLI command reference for the `musiclib-cli` dispatcher.

**Status**: Final
**Date**: 2026-02-14
**Version**: 2.0

**Supersedes**: `musiclib_cli_dispatcher.md` v1.0 and `musiclib_cli_dispatcher_UPDATED.md` v1.1. Both prior versions should be removed from the project tree.

---

## Overall Architecture

```
User Input
    ↓
musiclib-cli dispatcher (C++ router)
    ↓
Routes to appropriate shell script
    ↓
Script acquires lock, performs operation
    ↓
Returns exit code + JSON error (if any)
```

The dispatcher pattern follows this general structure:
```bash
musiclib-cli <command> [subcommand] [arguments] [options]
```

---

## Command Overview

### Available Commands

**Setup & Configuration**:
- `setup` - First-run configuration wizard (includes Audacious detection and plugin setup)

**Library Management**:
- `build` - Build/rebuild music database
- `new-tracks` - Import new music downloads
- `tagclean` - Clean and normalize ID3 tags
- `tagrebuild` - Repair tags from database values

**Rating**:
- `rate` - Rate current or specified track

**Playback Integration**:
- `audacious-hook` - Song change hook (automatic, not for manual use)

**Mobile Sync**:
- `mobile upload` - Send playlist to mobile device
- `mobile sync` - Sync playback timestamps
- `mobile status` - Show mobile sync status

**Maintenance**:
- `boost` - Apply ReplayGain loudness targeting
- `scan` - Scan playlists for cross-references

**Deferred Operations**:
- `process-pending` - Retry queued operations from lock contention

**Help & Information**:
- `help` - Show command help
- `version` - Show version information

---

## Detailed Command Reference

### **Setup & Configuration**

#### `musiclib-cli setup`

**Maps to**: `musiclib_init_config.sh`

**Purpose**: Interactive first-run configuration wizard

**Usage**:
```bash
musiclib-cli setup [--force]
```

**Options**:
- `--force` - Overwrite existing configuration

**What it does**:
1. Detects Audacious installation and `audtool` availability
2. Scans filesystem for music directories
3. Prompts for download directory
4. Creates XDG directory structure
5. Generates `musiclib.conf` with detected values
6. If Audacious detected, provides step-by-step Song Change plugin setup instructions
7. Optionally verifies Audacious integration (checks running instance, tests hook, validates Conky output)
8. Offers to build initial database

**Example**:
```bash
# First-time setup
musiclib-cli setup

# Reconfigure existing installation
musiclib-cli setup --force
```

**Auto-triggered**: When configuration is missing or invalid and the user runs any other command.

**Exit Codes**: 0 (configuration created), 1 (user cancelled), 2 (system error)

---

### **Library Management**

#### `musiclib-cli build`

**Maps to**: `musiclib_build.sh`

**Purpose**: Build or rebuild music database from repository

**Usage**:
```bash
musiclib-cli build [target_directory] [options]
```

**Positional Arguments**:
- `target_directory` - Music repository path (optional, uses config default)

**Option Flags**:
- `--dry-run` - Preview mode, don't write database
- `-b, --backup` - Backup existing database before rebuild
- `--output FILE` - Write to alternate database file
- `-v, --verbose` - Detailed output

**Examples**:
```bash
# Build database from configured repository
musiclib-cli build

# Build from specific directory
musiclib-cli build /mnt/music/Music

# Dry run to preview
musiclib-cli build --dry-run

# Build with backup
musiclib-cli build -b

# Build to alternate file
musiclib-cli build --output /tmp/musiclib_test.dsv
```

**Interactive Prompt**: If existing database found, prompts for action:
1. Overwrite existing DB
2. Rename existing to `.backup.TIMESTAMP`
3. Save as alternate file
4. Cancel

**What it does**:
1. Scans music repository for audio files
2. Extracts tag metadata via `exiftool` and `kid3-cli`
3. Generates sequential track and album IDs
4. Writes `^`-delimited records to `musiclib.dsv`
5. Logs progress with ETA

**Exit Codes**: 0 (success), 1 (user error/cancel), 2 (system error)

---

#### `musiclib-cli new-tracks`

**Maps to**: `musiclib_new_tracks.sh`

**Purpose**: Import new music downloads into library

**Usage**:
```bash
musiclib-cli new-tracks [artist_name] [options]
```

**Positional Arguments**:
- `artist_name` - Artist folder name (optional, prompts if omitted)

**Option Flags**:
- `--source DIR` - Override download directory
- `--source-dialog` - Show interactive directory picker
- `--no-loudness` - Skip rsgain loudness normalization
- `--no-art` - Skip album art extraction
- `--dry-run` - Preview mode only
- `-v, --verbose` - Detailed output

**Examples**:
```bash
# Import new downloads for Radiohead
musiclib-cli new-tracks "radiohead"

# Prompt for artist name
musiclib-cli new-tracks

# Override download directory
musiclib-cli new-tracks "radiohead" --source /mnt/external/new_music

# Use interactive directory picker
musiclib-cli new-tracks "radiohead" --source-dialog

# Skip loudness normalization
musiclib-cli new-tracks "the_beatles" --no-loudness

# Dry run to preview
musiclib-cli new-tracks "pink_floyd" --dry-run

# Combined options
musiclib-cli new-tracks "metallica" --no-loudness --no-art --dry-run -v
```

**What it does**:
1. Scans download directory for ZIP or MP3 files
2. Extracts ZIP if present
3. Pauses for manual tag cleanup in kid3-qt
4. Renames files: `track_-_artist_-_title`
5. Normalizes filenames (lowercase, safe characters)
6. Optional: rsgain loudness normalization
7. Creates artist/album directory structure
8. Appends records to musiclib.dsv
9. Syncs tags via kid3-cli

**Exit Codes**: 0 (success), 1 (no files/user error), 2 (system error)

---

#### `musiclib-cli tagclean`

**Maps to**: `musiclib_tagclean.sh`

**Purpose**: Clean and normalize ID3 tags

**Usage**:
```bash
musiclib-cli tagclean [target] [options]
```

**Positional Arguments**:
- `target` - File path, directory, or artist name

**Option Flags**:
- `--dry-run` - Preview changes
- `--backup` - Create tag backups
- `-v, --verbose` - Detailed output

**Examples**:
```bash
# Clean single file
musiclib-cli tagclean "/mnt/music/music/radiohead/ok_computer/01_-_radiohead_-_airbag.mp3"

# Clean entire directory
musiclib-cli tagclean "/mnt/music/music/radiohead/ok_computer"

# Clean all tracks for artist
musiclib-cli tagclean "radiohead"

# Dry run
musiclib-cli tagclean "radiohead" --dry-run --verbose
```

**What it does**:
- Converts ID3v1 → ID3v2.3
- Removes APE tags
- Embeds album art
- Normalizes frame structure
- Removes junk frames

**Exit Codes**: 0 (success), 1 (target not found), 2 (system error)

---

#### `musiclib-cli tagrebuild`

**Maps to**: `musiclib_tagrebuild.sh`

**Purpose**: Repair tags from database canonical values

**Usage**:
```bash
musiclib-cli tagrebuild [target] [options]
```

**Positional Arguments**:
- `target` - File path, directory, or artist name (optional, prompts if omitted)

**Option Flags**:
- `--dry-run` - Preview changes without applying
- `--force` - Overwrite all tags (even if already correct)
- `--verify` - Verify tags after rebuild
- `-v, --verbose` - Detailed output

**Examples**:
```bash
# Rebuild single file
musiclib-cli tagrebuild "/mnt/music/music/radiohead/ok_computer/01_-_radiohead_-_airbag.mp3"

# Rebuild entire directory
musiclib-cli tagrebuild "/mnt/music/music/radiohead/ok_computer"

# Rebuild all tracks for artist
musiclib-cli tagrebuild "radiohead"

# Dry run to preview
musiclib-cli tagrebuild "radiohead" --dry-run

# Force overwrite with verification
musiclib-cli tagrebuild "radiohead" --force --verify -v
```

**What it does**:
1. Reads canonical data from musiclib.dsv
2. Writes ID3 tags from database values
3. Repairs corrupted or missing tags
4. Ensures tag/database consistency
5. Optionally verifies after rebuild

**Exit Codes**: 0 (success), 1 (target not found), 2 (system error)

---

### **Rating**

#### `musiclib-cli rate`

**Maps to**: `musiclib_rate.sh`

**Purpose**: Rate current or specified track

**Usage**:
```bash
musiclib-cli rate <filepath> <rating>
```

**Positional Arguments**:
- `filepath` - Absolute path to audio file (must exist in DB)
- `rating` - Integer 0-5 (0=unrated, 5=highest)

**Examples**:
```bash
# Rate current Audacious track with 5 stars
musiclib-cli rate "$(audtool --current-song-filename)" 5

# Rate specific file
musiclib-cli rate "/mnt/music/music/radiohead/ok_computer/02_-_radiohead_-_paranoid_android.mp3" 4

# Unrate a track
musiclib-cli rate "/mnt/music/music/the_beatles/abbey_road/17_-_the_beatles_-_come_together.mp3" 0
```

**Side Effects** (all atomic via lock):
- Updates `musiclib.dsv` (Rating column)
- Writes POPM tag (ID3 popularimeter)
- Updates Grouping tag (star symbols: ★★★★★)
- Regenerates Conky assets (starrating.png, detail.txt)
- Logs to musiclib.log
- Sends KNotification

**Exit Codes**: 0 (success), 1 (invalid rating/file not in DB), 2 (tool unavailable/lock timeout)

---

### **Playback Integration**

#### `musiclib-cli audacious-hook`

**Maps to**: `musiclib_audacious.sh`

**Purpose**: Song change hook called automatically by Audacious via the Song Change plugin. Users should not call this manually.

**Usage**:
```bash
musiclib-cli audacious-hook
```

No parameters. Reads current track state from `audtool`.

**What it does**:
1. Queries current track from Audacious via `audtool --current-song-filename`
2. Extracts album art to Conky display directory
3. Writes track metadata to Conky text files (artist, album, title, rating, last played)
4. Monitors playback to scrobble threshold (50% of track, bounded 30s–4min)
5. Updates `LastTimePlayed` in database and file tag once threshold met
6. Appends to `audacioushist.log`

**Configuration**: Set during `musiclib-cli setup`. The wizard provides instructions to configure the Audacious Song Change plugin with the command path to this hook.

**Exit Codes**:
- 0: Success (display updated, scrobble queued)
- 1: Audacious not running or no track playing (not an error — graceful exit)
- 2: System error (tool unavailable, DB lock timeout, I/O failure)

---

### **Mobile Sync (KDE Connect)**

#### `musiclib-cli mobile upload`

**Maps to**: `musiclib_mobile.sh upload`

**Purpose**: Send playlist to mobile device via KDE Connect

**Usage**:
```bash
musiclib-cli mobile upload [playlist_file] [options]
```

**Positional Arguments**:
- `playlist_file` - Playlist to upload (optional, prompts if omitted)

**Option Flags**:
- `--device ID` - Override configured device ID
- `--force` - Skip confirmation prompts
- `-v, --verbose` - Detailed output

**Examples**:
```bash
# Upload default playlist
musiclib-cli mobile upload

# Upload specific playlist
musiclib-cli mobile upload /path/to/playlist.m3u

# Upload to specific device
musiclib-cli mobile upload --device e44edf16df3e4945a660bd76cd9f6f9a

# Force upload without prompts
musiclib-cli mobile upload --force
```

**What it does**:
1. Validates KDE Connect device is available
2. Converts playlist format if needed (.m3u8 for mobile)
3. Uploads via `kdeconnect-cli`
4. Creates `.meta` file with upload timestamp
5. Logs operation

**Exit Codes**: 0 (success), 1 (device unavailable), 2 (upload failed/lock timeout)

---

#### `musiclib-cli mobile sync`

**Maps to**: `musiclib_mobile.sh update-lastplayed`

**Purpose**: Sync playback timestamps from mobile device

**Usage**:
```bash
musiclib-cli mobile sync [options]
```

**Option Flags**:
- `--force` - Force sync even if no changes detected
- `-v, --verbose` - Detailed output

**Example**:
```bash
# Sync timestamps from mobile
musiclib-cli mobile sync

# Force sync
musiclib-cli mobile sync --force -v
```

**What it does**:
1. Reads `.meta` timestamp from previous upload
2. Updates `LastTimePlayed` in musiclib.dsv for tracks in playlist
3. Generates synthetic timestamps (proportional to track position and file size within upload window)
4. Syncs timestamps back to file tags

**Exit Codes**: 0 (success), 1 (no upload history), 2 (DB lock timeout)

---

#### `musiclib-cli mobile status`

**Maps to**: `musiclib_mobile.sh status`

**Purpose**: Show mobile sync status

**Usage**:
```bash
musiclib-cli mobile status
```

**Example Output**:
```
Mobile Sync Status
==================

KDE Connect Device: Galaxy S21 (e44edf16df3e4945a660bd76cd9f6f9a)
Status: Connected

Recent Uploads:
  2026-02-14 10:30 AM - mobile_2026-02-14.m3u8 (47 tracks)
  2026-02-10 03:15 PM - mobile_2026-02-10.m3u8 (52 tracks)

Pending Sync: No
```

**Exit Codes**: 0 (success)

---

### **Maintenance**

#### `musiclib-cli boost`

**Maps to**: `boost_album.sh`

**Purpose**: Apply ReplayGain loudness targeting to album

**Usage**:
```bash
musiclib-cli boost <album_directory> [options]
```

**Positional Arguments**:
- `album_directory` - Path to album directory

**Option Flags**:
- `--dry-run` - Preview mode
- `--target DB` - Target loudness in dB (default: -18)
- `-v, --verbose` - Detailed output

**Examples**:
```bash
# Apply ReplayGain to album
musiclib-cli boost "/mnt/music/music/radiohead/ok_computer"

# Dry run
musiclib-cli boost "/mnt/music/music/radiohead/ok_computer" --dry-run

# Custom target loudness
musiclib-cli boost "/mnt/music/music/radiohead/ok_computer" --target -16
```

**What it does**:
1. Analyzes all tracks in album using `rsgain`
2. Calculates album gain to reach target loudness
3. Applies gain tags (non-destructive)
4. Updates database with gain values

**Exit Codes**: 0 (success), 1 (directory not found), 2 (rsgain failed)

---

#### `musiclib-cli scan`

**Maps to**: `audpl_scanner.sh`

**Purpose**: Scan playlists for cross-references

**Usage**:
```bash
musiclib-cli scan [playlist_directory] [options]
```

**Positional Arguments**:
- `playlist_directory` - Directory containing playlists (optional, uses config default)

**Option Flags**:
- `--output FILE` - Write results to file (default: stdout)
- `-v, --verbose` - Detailed output

**Example**:
```bash
# Scan playlists
musiclib-cli scan

# Scan specific directory
musiclib-cli scan /path/to/playlists

# Write to file
musiclib-cli scan --output /tmp/playlist_cross_ref.csv
```

**What it does**:
1. Scans all `.audpl`, `.m3u`, `.pls` files
2. Cross-references tracks across playlists
3. Generates CSV with track→playlists mapping

**Exit Codes**: 0 (success), 1 (no playlists found), 2 (system error)

---

### **Deferred Operations**

#### `musiclib-cli process-pending`

**Maps to**: `musiclib_process_pending.sh`

**Purpose**: Retry queued operations from lock contention

**Usage**:
```bash
musiclib-cli process-pending [options]
```

**Option Flags**:
- `--force` - Force retry even if not due
- `--clear` - Clear pending queue without retrying

**Examples**:
```bash
# Retry pending operations
musiclib-cli process-pending

# Force retry
musiclib-cli process-pending --force

# Clear queue
musiclib-cli process-pending --clear
```

**What it does**:
1. Runs automatically after lock-contention operations
2. Iterates through queued operations in `.pending_operations`
3. Retries failed DB writes from rating/tagging operations
4. Sends delayed KNotifications on success
5. Removes successful operations from queue
6. Leaves failed operations for next retry cycle

**Exit Codes**: 0 (all done/no pending), 2 (system error)

---

### **Help & Information**

#### `musiclib-cli help`

**Purpose**: Show command help

**Usage**:
```bash
musiclib-cli help [command]
```

**Examples**:
```bash
# Show all commands
musiclib-cli help

# Show help for specific command
musiclib-cli help rate
```

---

#### `musiclib-cli version`

**Purpose**: Show version information

**Usage**:
```bash
musiclib-cli version
```

**Example Output**:
```
MusicLib CLI Dispatcher v1.0.0
Backend API Version: 1.0
Configuration: /home/user/.config/musiclib/musiclib.conf
Database: /home/user/.local/share/musiclib/data/musiclib.dsv (15,847 tracks)
```

---

## Auto-Configuration Behavior

### First-Run Detection

When `musiclib-cli` is invoked without a configuration file:

```bash
$ musiclib-cli build

Configuration not found.

Run first-time setup? [Y/n] y

[Launches setup wizard]
```

If user declines:
```
Run 'musiclib-cli setup' to configure MusicLib.
```

### Invalid Configuration Detection

When critical configuration is missing or invalid:

```bash
$ musiclib-cli build

Configuration validation failed:
  ✗ Music repository not found: /mnt/music/Music

Run 'musiclib-cli setup --force' to reconfigure.
```

---

## Global Options

These options work with all commands:

```bash
--config FILE    # Use alternate configuration file
--help           # Show command help
--version        # Show version information
--quiet          # Suppress non-error output
--debug          # Enable debug logging
```

**Examples**:
```bash
# Use alternate config
musiclib-cli --config /tmp/test.conf build

# Debug mode
musiclib-cli --debug rate "/path/to/file.mp3" 5
```

---

## Configuration Flow

Every command follows this initialization:
```
1. Load ~/.config/musiclib/musiclib.conf (or override with --config)
2. Verify required tools (kid3-cli, exiftool, etc.)
3. Validate database path and permissions
4. Acquire lock if write operation
5. Execute operation
6. Release lock
7. Return JSON error (if failed) + exit code
```

---

## Error Handling Pattern

All commands return JSON on stderr if exit code ≠ 0:

```json
{
  "error": "Invalid star rating - must be 0-5",
  "script": "musiclib_rate.sh",
  "code": 1,
  "context": {
    "provided": "6",
    "filepath": "/mnt/music/music/song.mp3"
  },
  "timestamp": "2026-02-11T15:45:23Z"
}
```

The C++ dispatcher parses this JSON and presents it to the user or GUI in a human-friendly format.

---

## Exit Code Summary

All commands follow the standardized exit code contract:

| Code | Meaning | Examples |
|------|---------|----------|
| **0** | Success | Operation completed, all side effects applied |
| **1** | User/Validation Error | Invalid input, missing preconditions, user cancellation |
| **2** | System/Operational Error | Config missing, tool unavailable, I/O failure, lock timeout |
| **3** | Deferred (Future) | Operation queued for retry due to lock contention |

**Note**: Exit code 3 is proposed design, not yet implemented. Lock timeouts currently return exit code 2.

---

## Summary: Dispatcher as a Routing Layer

The dispatcher doesn't reinvent functionality—it **orchestrates**:

- **Argument validation**: Ensures correct # and type of args
- **Path resolution**: Converts relative to absolute paths
- **Error translation**: Converts JSON stderr → UI notifications
- **Lock coordination**: Ensures exclusive DB access across concurrent calls
- **Configuration management**: Centralizes config loading
- **Logging**: Aggregates logs from all scripts

This design keeps the shell scripts thin, testable, and independent while providing a polished CLI and GUI interface on top.
