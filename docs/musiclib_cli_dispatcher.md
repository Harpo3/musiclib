# MusicLib-CLI Dispatcher: Command Reference

**Document Purpose**: Canonical CLI command reference for the musiclib-cli dispatcher.  
**Status**: Final  
**Date**: 2026-02-16  
**Version**: 2.1

---

## Overview

The **musiclib-cli dispatcher** is a thin C++ command-line router that delegates all actual operations to the shell script backend. It's not a reimplementation—it's a convenience wrapper that makes it easier to call the underlying scripts from both the Qt GUI and the command line.

### Architecture

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

### Command Pattern

```bash
musiclib-cli <command> [subcommand] [arguments] [options]
```

---

## Available Commands

### Setup & Configuration
- `setup` — First-run configuration wizard

### Library Management
- `build` — Build/rebuild music database
- `new-tracks` — Import new music downloads
- `tagclean` — Clean and normalize ID3 tags
- `tagrebuild` — Repair tags from database values
- `boost` — Apply ReplayGain loudness targeting

### Rating
- `rate` — Rate current or specified track

### Playback Integration
- `audacious-hook` — Song change hook (automatic, not for manual use)

### Mobile Sync
- `mobile upload` — Send playlist to mobile device
- `mobile sync` — Sync playback timestamps
- `mobile status` — Show mobile sync status

### Deferred Operations
- `process-pending` — Retry queued operations from lock contention

### Help & Information
- `help` — Show command help
- `version` — Show version information

---

## Command Reference

### 1. Setup: `musiclib-cli setup`

**Maps to**: `musiclib_init_config.sh`

**Usage Pattern**:
```bash
musiclib-cli setup
```

**What It Does**:
1. Detects Audacious installation
2. Displays steps for Audacious' Song-Change-plugin configuration
3. Scans filesystem for music directories
4. Prompts for download directory
5. Offers to build initial database
6. Creates XDG directory structure
7. Generates `~/.config/musiclib/musiclib.conf`

**Example Session**:
```
MusicLib First-Run Setup
=========================

[1/5] Checking Audacious...
✓ Audacious installed: /usr/bin/audacious

[2/5] Locating music repository...

Found potential music locations:
  1) /home/user/Music (234 files)
  2) /mnt/music/Music (15,847 files)
  3) Enter custom path

Select music repository [1-3]: 2
✓ Music repository: /mnt/music/Music

[3/5] Setting download directory...
New music download location [/home/user/Downloads]: 
✓ Download directory: /home/user/Downloads

[4/5] Checking database...
No existing database found.

Build initial database from music repository? [Y/n] y
Building database... (this may take several minutes)
✓ Database created: ~/.local/share/musiclib/data/musiclib.dsv

[5/5] Audacious Integration...
See 'musiclib-cli help audacious-hook' for setup instructions.

Setup Complete!
===============

Next steps:
  1. Configure Audacious song-change hook
  2. Rate some tracks: musiclib-cli rate 4
  3. Import new music: musiclib-cli new-tracks ~/Downloads
```

**Exit Codes**:
- 0: Configuration created successfully
- 1: User cancelled setup
- 2: System error (cannot create directories, etc.)

---

### 2. Build Database: `musiclib-cli build`

**Maps to**: `musiclib_build.sh`

**Usage Pattern**:
```bash
musiclib-cli build [music_directory] [options]
```

**Positional Arguments**:
- `music_directory`: Root of library (default: $MUSIC_REPO from config)

**Option Flags**:
- `-d, --dry-run`: Preview mode—show what would be processed, no changes
- `-o FILE`: Output file path (default: $MUSICDB)
- `-m DEPTH`: Minimum subdirectory depth (default: 1)
- `--no-header`: Suppress database header
- `-q, --quiet`: Minimal output
- `-s COLUMN`: Sort output by column number
- `-b, --backup`: Create backup of existing database
- `-t, --test`: Output to temporary file for testing
- `--no-progress`: Disable progress indicators

**Example Invocations**:
```bash
# Preview what would be built (safe)
musiclib-cli build /mnt/music/music --dry-run

# Full build with automatic backup
musiclib-cli build /mnt/music/music -b

# Build subdirectory only
musiclib-cli build /mnt/music/music/rock -t

# Build with minimal output
musiclib-cli build /mnt/music/music -q

# Build and sort by artist (column 2)
musiclib-cli build /mnt/music/music -s 2
```

**What It Does**:
1. Walks directory tree, finds all MP3s
2. Extracts metadata using kid3-cli
3. Generates sequential track IDs and album IDs
4. Creates new DSV database from scratch
5. Computes song lengths in milliseconds
6. Optional: sorts by column, backs up old DB

**Important Notes**:
- **Destructive**: Replaces existing database (use --dry-run first)
- **Time**: Takes 10+ minutes for 10,000+ tracks
- **Reset**: LastTimePlayed set to 0, all ratings reset

**Exit Codes**: 0 (success), 1 (dry-run complete / user error), 2 (system failure)

---

### 3. New Track Import: `musiclib-cli new-tracks`

**Maps to**: `musiclib_new_tracks.sh`

**Usage Pattern**:
```bash
musiclib-cli new-tracks [artist_name] [options]
```

**Positional Arguments**:
- `artist_name`: Artist folder name (optional, prompts if omitted)

**Option Flags**:
- `--no-loudness`: Skip rsgain loudness normalization
- `--no-art`: Skip album art extraction
- `--dry-run`: Preview mode only
- `-v, --verbose`: Detailed output
- `--source DIR`: Use alternate download directory

**Example Invocations**:
```bash
# Import new downloads for Radiohead
musiclib-cli new-tracks "radiohead"

# Import and prompt for artist
musiclib-cli new-tracks

# Skip loudness normalization
musiclib-cli new-tracks "the_beatles" --no-loudness

# Dry run to see what would happen
musiclib-cli new-tracks "pink_floyd" --dry-run

# Full import with verbose logging
musiclib-cli new-tracks "deftones" -v

# Use alternate download directory
musiclib-cli new-tracks "radiohead" --source /mnt/external/new_music
```

**What It Does**:
Imports new music downloads into the library and database.
1. Scans download directory for ZIP or MP3 files
2. Enforces single ZIP or batch of MP3s (no mixed mode)
3. Extracts ZIP if present, pauses for manual tag cleanup in kid3-qt
4. Renames files using kid3-cli: `track_-_artist_-_title`
5. Normalizes filenames (lowercase, safe characters)
6. Optional: rsgain loudness normalization
7. Derives album name from tags (fallback: `unknown_album_yyyymmdd`)
8. Creates artist/album directory under music repo
9. Extracts metadata, computes duration, assigns IDs
10. Appends records to musiclib.dsv
11. Syncs tags via kid3-cli

**Exit Codes**: 0 (success), 1 (user error/no files), 2 (system error)

---

### 4. Tag Cleaning: `musiclib-cli tagclean`

**Maps to**: `musiclib_tagclean.sh`

**Usage Pattern**:
```bash
musiclib-cli tagclean <target> [options]
```

**Positional Arguments**:
- `target`: File or directory to clean

**Option Flags**:
- `-r, --recursive`: Process directories recursively
- `-a, --remove-ape`: Remove APE tags (default: keep)
- `-g, --remove-rg`: Remove ReplayGain tags
- `-n, --dry-run`: Show what would be done without changes
- `-v, --verbose`: Show detailed processing info
- `-b, --backup-dir DIR`: Custom backup directory

**Operation Mode Flags** (mutually exclusive):
- `--art-only`: Only process album art embedding
- `--ape-only`: Only remove APE tags
- `--rg-only`: Only remove ReplayGain tags
- (default `--full`): All operations

**Example Invocations**:
```bash
# Full cleanup of entire music directory
musiclib-cli tagclean /mnt/music/music -r

# Only embed album art
musiclib-cli tagclean /mnt/music/music/radiohead -r --art-only

# Dry run to preview changes
musiclib-cli tagclean /mnt/music/music/radiohead -r -n

# Remove APE and ReplayGain tags
musiclib-cli tagclean /mnt/music/music -r -a -g

# Custom backup location with verbose logging
musiclib-cli tagclean /mnt/music/music/jazz -r -b /home/user/backup_tags -v
```

**What It Does**:
1. Merges ID3v1 data into ID3v2.3
2. Removes ID3v1 tag entirely
3. Optionally strips APE and ReplayGain metadata
4. Embeds album art from matching JPEG files
5. Creates timestamped backups before modifying
6. Verifies resulting files are intact (restores from backup on failure)
7. Prints summary (files processed, tags merged/removed, art embedded, errors)

**Exit Codes**: 0 (success), 1 (user error), 2 (system error)

---

### 5. Tag Rebuild: `musiclib-cli tagrebuild`

**Maps to**: `musiclib_tagrebuild.sh`

**Usage Pattern**:
```bash
musiclib-cli tagrebuild <target> [options]
```

**Positional Arguments**:
- `target`: File or directory to repair

**Option Flags**:
- `-r, --recursive`: Process recursively
- `-n, --dry-run`: Preview only
- `-v, --verbose`: Detailed output
- `-b, --backup-dir DIR`: Custom backup location

**Example Invocations**:
```bash
# Repair corrupted tags in single file
musiclib-cli tagrebuild /mnt/music/music/radiohead/ok_computer/02_-_radiohead_-_paranoid_android.mp3

# Repair entire artist directory
musiclib-cli tagrebuild /mnt/music/music/the_beatles -r

# Dry run preview
musiclib-cli tagrebuild /mnt/music/music/pink_floyd -r -n

# Verbose repair with custom backups
musiclib-cli tagrebuild /mnt/music/music/jazz -r -v -b /home/user/tag_backups
```

**What It Does**:
1. Processes only files present in musiclib.dsv
2. Extracts authoritative metadata from DB (artist, album, title, rating)
3. Preserves non-DB fields (ReplayGain, album art)
4. Strips all existing ID3/APE tags
5. Rebuilds clean ID3v2.3 tags
6. Creates timestamped backups before modifying
7. Verifies files are intact (restores on failure)
8. Tracks stats: processed, rebuilt, skipped, errors

**Exit Codes**: 0 (success), 1 (user error), 2 (system error)

---

### 6. Boost (ReplayGain): `musiclib-cli boost`

**Maps to**: `boost_album.sh`

**Usage Pattern**:
```bash
musiclib-cli boost <target> [options]
```

**Positional Arguments**:
- `target`: Album directory to process

**Option Flags**:
- `--target LUFS`: Target loudness level (default: -14 LUFS)
- `-n, --dry-run`: Preview only
- `-v, --verbose`: Detailed output

**Example Invocations**:
```bash
# Apply ReplayGain to album
musiclib-cli boost /mnt/music/music/pink_floyd/dark_side

# Target specific loudness
musiclib-cli boost /mnt/music/music/metallica/master --target -12

# Preview changes
musiclib-cli boost /mnt/music/music/radiohead/ok_computer --dry-run
```

**What It Does**:
1. Scans album directory for audio files
2. Calculates album-based ReplayGain values
3. Writes ReplayGain tags using rsgain
4. No database locking needed (tag-only operation)

**Exit Codes**: 0 (success), 1 (user error), 2 (system error)

---

### 7. Rating: `musiclib-cli rate`

**Maps to**: `musiclib_rate.sh`

**Usage Pattern**:
```bash
musiclib-cli rate <rating> [filepath]
```

**Positional Arguments**:
- `rating`: Integer 0–5 (0=unrated, 5=highest)
- `filepath`: Absolute path to audio file (optional—uses currently playing track if omitted)

**Example Invocations**:
```bash
# Rate currently playing track with 4 stars
musiclib-cli rate 4

# Rate specific file with 5 stars
musiclib-cli rate 5 "/mnt/music/music/pink_floyd/dark_side/01_-_pink_floyd_-_speak_to_me_breathe.mp3"

# Unrate a track
musiclib-cli rate 0 "/mnt/music/music/radiohead/ok_computer/02_-_radiohead_-_paranoid_android.mp3"
```

**Side Effects** (all atomic via lock):
- Updates `musiclib.dsv` (Rating column)
- Writes POPM tag (ID3 popularimeter)
- Updates Grouping tag (star symbols: ★★★★★)
- Regenerates Conky assets (starrating.png, detail.txt)
- Logs to musiclib.log
- Sends KNotification when rating is changed

**Exit Codes**:
- 0: Success
- 1: Invalid rating (not 0-5), file not in DB, file not found
- 2: kid3-cli unavailable, tag write failure, DB lock timeout
- 3: Deferred (operation queued for retry)

---

### 8. Audacious Hook: `musiclib-cli audacious-hook`

**Maps to**: `musiclib_audacious.sh`

**Usage Pattern**:
```bash
musiclib-cli audacious-hook
```

**IMPORTANT**: This command is called automatically by Audacious via its Song Change plugin. It is not intended for manual use.

**Setup** (one-time):
1. Open Audacious → Services → Plugins → General
2. Enable "Song Change" plugin
3. Click "Settings" icon next to Song Change
4. Find this entry under Commands: "Command to run when starting a new song:"
5. Set command to: `/usr/bin/musiclib-cli audacious-hook`

**What It Does**:
1. Extracts current track metadata via `audtool`
2. Updates Conky display files (album art, track info, rating stars)
3. Updates "last played" timestamp in database
4. Queues scrobble tracking (if threshold met)
5. Sends KNotification if track has no rating or if conky is restarted

**Exit Codes**:
- 0: Success (display updated, scrobble queued)
- 1: Audacious not running or no track playing (not an error)
- 2: System error (tag write failed, DB lock timeout)
- 3: Deferred (operation queued for retry)

---

### 9. Mobile Sync: `musiclib-cli mobile`

**Maps to**: `musiclib_mobile.sh`

**Usage Pattern**:
```bash
musiclib-cli mobile <subcommand> [arguments] [options]
```

#### 9a. Upload Playlist

```bash
musiclib-cli mobile upload <playlist.audpl> [device_id]
```

**Arguments**:
- `playlist`: playlist_name.audpl (Audacious playlist obtained from default PLAYLISTS_DIR) or a full path to the .audpl file 
- - `device_id`: KDE Connect device ID (optional, uses config default)

**Option Flags**:
- `--dry-run`: Show what would transfer without sending

**Example Invocations**:
```bash
# Upload playlist to default device
musiclib-cli mobile upload ~/musiclib/playlists/summer.audpl

# Upload using just the playlist name
musiclib-cli mobile upload summer.audpl

# Upload to specific device
musiclib-cli mobile upload ~/musiclib/playlists/rock.audpl "e1234567890abcdef"
```

**What It Does**:
1. **Checks if Audacious version is newer** than Musiclib copy:
   - If newer: prompts "Audacious version of 'X' is newer than Musiclib copy. Refresh from Audacious? [y/N]"
   - If refreshed: prompts "Continue with upload? [Y/n]" (allows refresh-only)
   - If new playlist (not in Musiclib): prompts "This is a new Audacious playlist. Copy now and proceed with upload? [y/N]"
   - If same/older or not found in Audacious: proceeds directly to upload
2. Validates KDE Connect device connectivity
3. Requires manual deletion of old phone downloads (prompts user)
4. URL-decodes file:// URIs from playlist
5. Sends .m3u to phone
6. Streams each audio file via kdeconnect-cli
7. Logs metadata (track count, MB transferred)
8. Stores `.meta` (timestamp) and `.tracks` (file list) under mobile directory

**Configuration**:
- `AUDACIOUS_PLAYLISTS_DIR`: Location of Audacious playlists (default: `~/.config/audacious/playlists`)

#### 9b. Refresh Audacious Playlists Only
```bash
musiclib-cli mobile refresh-audacious-only
```

**What It Does**:
1. Scans all `.audpl` files in `AUDACIOUS_PLAYLISTS_DIR`
2. Extracts playlist title from first line (`title=...`)
3. URL-decodes and sanitizes title to create safe filename
4. Copies each playlist to `PLAYLISTS_DIR` with sanitized name
5. Reports count of playlists processed

**Example**:
```bash
# Refresh all Audacious playlists to Musiclib directory
musiclib-cli mobile refresh-audacious-only
```

**Use Case**: Bulk sync of all Audacious playlists without uploading to mobile device.

#### 9c. Sync Playback Timestamps

```bash
musiclib-cli mobile sync <playlist_name>
```

**Arguments**:
- `playlist_name`: Name of playlist (without .audpl extension)

**Example**:
```bash
musiclib-cli mobile sync summer
```

**What It Does**:
1. Reads `.meta` timestamp from previous upload
2. Updates LastTimePlayed in musiclib.dsv for all tracks in that playlist
3. Syncs timestamp back to track tags

#### 9d. Update Last-Played
```bash
musiclib-cli mobile update-lastplayed <playlist_name>
```

**Arguments**:
- `playlist_name`: Name of playlist (without .audpl extension)

**Example**:
```bash
musiclib-cli mobile update-lastplayed summer
```

**What It Does**:
1. Reads `.meta` timestamp from previous upload
2. Updates LastTimePlayed in musiclib.dsv for all tracks in that playlist
3. Syncs timestamp back to track tags

#### 9e. Status

```bash
musiclib-cli mobile status
```

**Shows**:
- Available KDE Connect devices
- Current mobile playlist tracking
- Recent mobile operations log

**Exit Codes**: 0 (success), 1 (validation error), 2 (device unreachable, lock timeout)


#### 9f. Logs
```bash
musiclib-cli mobile logs [filter]
```

**Filters**:
- (none): Show last 50 log lines
- `errors`: Show recent errors only
- `warnings`: Show recent warnings only
- `stats`: Show recent statistics
- `today`: Show today's operations only

**Example**:
```bash
musiclib-cli mobile logs errors
```

#### 9g. Cleanup
```bash
musiclib-cli mobile cleanup
```

**What It Does**:
- Removes orphaned `.meta` and `.tracks` files from mobile directory
- Preserves files for current active playlist

**Exit Codes**: 0 (success), 1 (validation error), 2 (device unreachable, lock timeout)

---

### 10. Process Pending: `musiclib-cli process-pending`

**Maps to**: `musiclib_process_pending.sh`

**Usage Pattern**:
```bash
musiclib-cli process-pending [options]
```

**Option Flags**:
- `--force`: Retry all pending operations immediately
- `--clear`: Delete pending queue without retrying

**Example Invocations**:
```bash
# Process pending operations
musiclib-cli process-pending

# Force retry even if not due
musiclib-cli process-pending --force

# Clear pending queue without retrying
musiclib-cli process-pending --clear
```

**What It Does**:
1. Runs automatically after lock-contention operations
2. Iterates through queued operations (JSON file)
3. Retries failed DB writes from rating/tagging operations
4. Sends delayed KNotifications on success
5. Removes successful operations from queue
6. Leaves failed operations for next retry cycle

**Exit Codes**: 0 (all done), 1 (some failed), 2 (system error)

---

### 11. Help & Version

#### Help

```bash
musiclib-cli help [command]
musiclib-cli --help
musiclib-cli <command> --help
```

**Examples**:
```bash
# Show all commands
musiclib-cli help

# Show help for specific command
musiclib-cli help rate
musiclib-cli rate --help
```

#### Version

```bash
musiclib-cli version
musiclib-cli --version
```

**Output**:
```
musiclib-cli 0.1.0
```

---

## Global Options

Most commands support these global options:

- `-h, --help`: Show command-specific help
- `--config FILE`: Use alternate config file
- `--no-notify`: Suppress KNotifications
- `--timeout SECONDS`: Custom lock timeout (overrides config)

**Example**:
```bash
musiclib-cli rate 5 "/mnt/music/song.mp3" --no-notify --timeout 10
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

## Error Handling

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
  "timestamp": "2026-02-16T15:45:23Z"
}
```

The C++ dispatcher parses this JSON and presents it to the user or GUI in a human-friendly format.

---

## Exit Code Reference

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Operation completed |
| 1 | User error | Invalid arguments, file not found, validation failed |
| 2 | System error | Tool unavailable, permission denied, DB corruption |
| 3 | Deferred | Operation queued due to lock contention |

---

**Document Version**: 2.1  
**Last Updated**: 2026-02-16  
**Status**: Final
