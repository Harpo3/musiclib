# MusicLib-CLI Dispatcher: Practical Implementation

The **musiclib-cli dispatcher** is a thin C++ command-line router that delegates all actual operations to the shell script backend. It's not a reimplementation—it's a convenience wrapper that makes it easier to call the underlying scripts from both the Qt GUI and the command line.

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

## Available Commands & All Options by Script

Here's a practical walkthrough of every major script and how the dispatcher would invoke it:

### **1. Rating Tracks: `musiclib-cli rate`**

**Maps to**: `musiclib_rate.sh`

**Usage Pattern**:
```bash
musiclib-cli rate /path/to/song.mp3 <star_rating>
```

**Parameters**:
- `filepath`: Absolute path to audio file (must exist in DB)
- `rating`: Integer 0–5 (0=unrated, 5=highest)

**Example Invocations**:
```bash
# Rate current track in Audacious with 5 stars
musiclib-cli rate "/mnt/music/music/pink_floyd/dark_side/01_-_pink_floyd_-_speak_to_me_breathe.mp3" 5

# Unrate a track
musiclib-cli rate "/mnt/music/music/radiohead/ok_computer/02_-_radiohead_-_paranoid_android.mp3" 0

# Rate with 3 stars
musiclib-cli rate "/mnt/music/music/the_beatles/abbey_road/17_-_the_beatles_-_come_together.mp3" 3
```

**Side Effects** (all atomic via lock):
- Updates `musiclib.dsv` (Rating column)
- Writes POPM tag (ID3 popularimeter)
- Updates Grouping tag (star symbols: ★★★★★)
- Regenerates Conky assets (starrating.png, detail.txt)
- Logs to musiclib.log
- Sends KNotification

**Exit Codes**:
- 0: Success
- 1: Invalid rating (not 0-5), file not in DB, file not found
- 2: kid3-cli unavailable, tag write failure, DB lock timeout
- 3: Deferred (proposed future feature)

---

### **2. Tag Cleaning: `musiclib-cli tagclean`**

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

# Only remove ReplayGain
musiclib-cli tagclean /mnt/music/music -r --rg-only -v

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

### **3. Database Build: `musiclib-cli build`**

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

# Dry run with no progress bar
musiclib-cli build /mnt/music/music --dry-run --no-progress

# Test on jazz subdirectory before full build
musiclib-cli build /mnt/music/music/jazz -t
```

**What It Does**:
1. Walks directory tree, finds all MP3s
2. Extracts metadata using kid3-cli
3. Generates sequential track IDs and album IDs
4. Creates new DSV database from scratch
5. Computes song lengths in milliseconds
6. Optional: sorts by column, backs up old DB

**Important Notes**:
- **Destructive**: Replaces existing database (use -t or --dry-run first, or responds to prompt)
- **Time**: Takes 10+ minutes for 10,000+ tracks
- **Reset**: LastTimePlayed set to 0, all ratings reset

**Exit Codes**: 0 (success), 1 (dry-run complete / user error), 2 (system failure)

---

### **4. Mobile Sync: `musiclib-cli mobile`**

**Maps to**: `musiclib_mobile.sh`

**Usage Pattern**:
```bash
musiclib-cli mobile <subcommand> [arguments] [options]
```

**Subcommands**:

#### **4a. Upload Playlist**
```bash
musiclib-cli mobile upload <playlist.audpl> [device_id]
```

**Arguments**:
- `playlist`: Path to .audpl file (Audacious playlist)
- `device_id`: KDE Connect device ID (optional, uses config default)

**Example Invocations**:
```bash
# Upload playlist to default device
musiclib-cli mobile upload ~/musiclib/playlists/summer.audpl

# Upload to specific device
musiclib-cli mobile upload ~/musiclib/playlists/rock.audpl "e1234567890abcdef"

# Dry run first (shows what would transfer)
musiclib-cli mobile upload ~/musiclib/playlists/jazz.audpl --dry-run
```

**What It Does**:
1. Validates KDE Connect device connectivity
2. Requires manual deletion of old phone downloads (prompts user)
3. URL-decodes file:// URIs from playlist
4. Sends .m3u to phone
5. Streams each audio file via kdeconnect-cli
6. Logs metadata (track count, MB transferred)
7. Stores `.meta` (timestamp) and `.tracks` (file list) under mobile directory

#### **4b. Update Last-Played**
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

#### **4c. Status**
```bash
musiclib-cli mobile status
```

**Shows**:
- Available KDE Connect devices
- Recent mobile operations log
- Pending upload history

**Exit Codes**: 0 (success), 1 (validation error), 2 (device unreachable, lock timeout)

---

### **5. New Track Import: `musiclib-cli new-tracks`**

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

# Skip both loudness and art extraction
musiclib-cli new-tracks "metallica" --no-loudness --no-art

# Use alternate download directory
musiclib-cli new-tracks "radiohead" --source /mnt/external/new_music
```

**What It Does**:
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

### **6. Tag Rebuild: `musiclib-cli tagrebuild`**

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

### **7. Audacious Integration: `musiclib-cli audacious`**

**Maps to**: `musiclib_audacious.sh`

**Usage Pattern**:
```bash
musiclib-cli audacious [track_path] [options]
```

**Typically invoked by Audacious as a song-change hook**, but also supports manual invocation:

**Option Flags**:
- `--current`: Show metadata for currently playing track
- `--status`: Show scrobble statistics and pending operations
- `--process-pending`: Retry deferred scrobbles from lock timeouts

**Example Invocations**:
```bash
# Called by Audacious on song change (automatic)
musiclib-cli audacious

# Manual scrobble for testing or catch-up
musiclib-cli audacious "/mnt/music/music/radiohead/ok_computer/01_-_radiohead_-_airbag.mp3"

# Get current track info
musiclib-cli audacious --current

# Show scrobble statistics
musiclib-cli audacious --status

# Retry deferred scrobbles from lock timeouts
musiclib-cli audacious --process-pending
```

**What It Does**:
1. Monitors currently playing track in Audacious
2. Extracts album art to display directory
3. Writes metadata to Conky-friendly text files
4. Computes scrobble point (30s to 4 min of playback)
5. Records listen timestamp to DB when threshold reached
6. Updates LastTimePlayed in both DB and tags
7. Refreshes Conky display (artist, album, rating)
8. Manages star-rating PNG selection
9. Prompts for rating via kdialog if unrated

**Exit Codes**: 0 (scrobbled), 1 (not eligible/paused), 2 (system error), 3 (deferred - operation queued)

---

### **8. Process Pending Operations: `musiclib-cli process-pending`**

**Maps to**: `musiclib_process_pending.sh`

**Usage Pattern**:
```bash
musiclib-cli process-pending [--force] [--clear]
```

**Option Flags**:
- `--force`: Retry all pending operations
- `--clear`: Delete pending queue without retrying

**What It Does**:
1. Runs automatically after lock-contention operations
2. Iterates through queued operations (JSON file)
3. Retries failed DB writes from rating/tagging operations
4. Sends delayed KNotifications on success
5. Removes successful operations from queue
6. Leaves failed operations for next retry cycle
7. Returns 0 (all done), 1 (some failed), 2 (system error)

**Example**:
```bash
# Manual retry of pending operations
musiclib-cli process-pending

# Force retry even if not due
musiclib-cli process-pending --force

# Clear pending queue without retrying
musiclib-cli process-pending --clear
```

---

### **9. Auxiliary: `musiclib-cli playlist-scan` & `musiclib-cli boost-album`**

#### **Playlist Scanner**
```bash
musiclib-cli playlist-scan [scan|create]
```

- `scan`: Copy Audacious playlists and sanitize names
- `create`: Generate CSV with ratings from playlists

#### **Boost Album**
```bash
musiclib-cli boost-album <album_name>
```

Increases rating of all tracks in an album (utility function)

---

## Global Options (All Commands)

Most dispatcher commands support:
- `-h, --help`: Show command-specific help
- `--config FILE`: Use alternate config file
- `--log FILE`: Redirect output to log file
- `--no-notify`: Suppress KNotifications
- `--timeout SECONDS`: Custom lock timeout (overrides config)

**Example**:
```bash
musiclib-cli rate "/mnt/music/music/song.mp3" 5 --no-notify --timeout 10
```

---

## Configuration Flow

Every command follows this initialization:
```
1. Load ~/MUSICLIB_ROOT/musiclib.conf (or override with --config)
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

The C++ dispatcher would parse this JSON and present it to the user or GUI in a human-friendly format.

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
