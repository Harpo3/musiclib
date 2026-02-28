# MusicLib User Manual

**Version**: 0.1 Alpha  
**Last Updated**: February 2026  
**For**: MusicLib on Linux with KDE Plasma 6

---

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [First-Time Setup](#first-time-setup)
4. [Core Concepts](#core-concepts)
5. [Using the GUI](#using-the-gui)
6. [Common Tasks](#common-tasks)
7. [Mobile Sync with Android](#mobile-sync-with-android)
8. [Desktop Integration](#desktop-integration)
9. [Command-Line Reference](#command-line-reference)
10. [Standalone Utilities](#standalone-utilities)
11. [Troubleshooting](#troubleshooting)
12. [Tips & Tricks](#tips--tricks)

---

## Introduction

MusicLib is a personal music library **management hub** designed for KDE Plasma users who want to organize, track, and manage their local music collections. It works on **any Linux distribution with KDE Plasma 6** — whether you use Arch, Fedora, Ubuntu, openSUSE, or anything in between.

Rather than juggling multiple applications, MusicLib brings everything together in one integrated experience:
- **Rate and organize** your music collection
- **Edit tags** directly (integrated with Kid3)
- **Track playback** across devices
- **Sync to mobile** (Android or iOS)
- **Deep KDE integration** (system tray, shortcuts, file manager)

It sits between you and Audacious (your audio player) and handles all the behind-the-scenes work: organizing metadata, rating songs, tracking what you listen to, and syncing playlists to your **Android or iOS device** via KDE Connect.

### What MusicLib Does

- **Centralizes Your Music**: Maintains a single database of all your songs, albums, and metadata—and expands each file's tag data to store rating and last-played information
- **Rates and Organizes**: Star-rate songs and see your ratings everywhere
- **Tracks Playback**: Records last-played history across devices—desktop (Audacious) and remote (mobile phone)
- **Syncs to Mobile**: Pushes playlists/files to Android or iOS devices via KDE Connect, and captures the last-played data from the old playlist when the new one is replaced. Logs actual played timestamps for tracks played from the desktop, and logs synthesized dates for playlists played on mobile
- **Integrates with KDE**: Works seamlessly with Plasma, Dolphin file manager, and system shortcuts
- **Manages Metadata**: Repairs and normalizes song tags automatically

### What MusicLib Doesn't Do

- Be a music player (that's Audacious)
- Stream from Spotify, Apple Music, etc.
- Auto-fetch metadata from the internet
- Run without **KDE Plasma 6** (it's a Plasma-native application)
- Work on non-Linux systems (Linux/KDE only)
- Log more than one mobile playlist at a time

---

## Compatibility

### Cross-Distro Support

MusicLib is **distro-agnostic**. The shell scripts and GUI work on any Linux distribution with KDE Plasma 6. You don't need Arch Linux — just KDE Plasma 6 and the required dependencies.

**Supported Distributions**:
- Arch Linux (AUR packages available)
- Fedora KDE (dnf packages)
- Ubuntu/Kubuntu (apt packages)
- KDE Neon (apt packages)
- openSUSE (zypper packages)
- Debian (apt packages)
- Any other Plasma 6 capable distro

### Prerequisites

Before installing MusicLib, ensure you have:

1. **KDE Plasma 6** or later (run `plasmashell --version` to check)
2. **Audacious** music player
3. **kid3-common** (command-line tag editor — required)
4. **exiftool** (metadata processor)
5. **KDE Connect** (for mobile sync)
6. Standard Unix tools: `bash`, `bc`, `coreutils`, `grep`, `sed`
7. A **mobile device** (optional, for mobile features):
   - **Android** (any version with KDE Connect support)
   - **iOS/iPhone** (iOS 14 or later with KDE Connect app)

**Optional but Recommended**:
- **kid3 (KDE) or kid3-qt (QT)** (GUI-based tag editor) — Opens directly from MusicLib for detailed metadata editing. Provides a full-featured interface for ID3 tags, album art, and more, and includes kid3-common.
- **rsgain** (ReplayGain analyzer) — Required for the Boost Album feature. May need to be compiled from source on some distros.

## Installation

### Arch Linux (AUR)

```bash
# Install just the backend and CLI
yay -S musiclib-cli

# or

# Install the GUI
yay -S musiclib

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
yay -S kid3
```

All dependencies are automatically resolved.

### Fedora KDE (dnf)

```bash
# Install dependencies
sudo dnf install audacious kid3-common exiftool kdeconnect bc grep sed

# For ReplayGain (optional, for Boost Album feature)
sudo dnf install rsgain

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo dnf install kid3
```

### Ubuntu/Kubuntu/KDE Neon (apt)

```bash
# Install dependencies
sudo apt install audacious kid3-common exiftool kdeconnect bc

# For ReplayGain (if available in your repo)
sudo apt install rsgain
# If not available, you can skip this — Boost Album feature won't work

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo apt install kid3

# Clone and build from source
git clone https://github.com/yourusername/musiclib.git
cd musiclib
mkdir build && cd build
cmake ..
make
sudo make install
```

### openSUSE Plasma (zypper)

```bash
# Install dependencies
sudo zypper install audacious kid3-common exiftool kdeconnect bc grep sed

# For ReplayGain (optional)
sudo zypper install rsgain

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo zypper install kid3

# Clone and build from source
git clone https://github.com/yourusername/musiclib.git
cd musiclib
mkdir build && cd build
cmake ..
make
sudo make install
```

### Debian (apt)

```bash
# Install dependencies
sudo apt install audacious kid3-common exiftool kdeconnect bc

# ReplayGain (if available)
sudo apt install rsgain

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo apt install kid3

# Clone and build from source
git clone https://github.com/yourusername/musiclib.git
cd musiclib
mkdir build && cd build
cmake ..
make
sudo make install
```

### Building from Source (All Distributions)

If you prefer to build from GitHub instead of using pre-made packages:

```bash
# Clone the repository
git clone https://github.com/Harpo3/musiclib.git
cd musiclib

# Create build directory
mkdir build && cd build

# Configure (requires CMake and Qt6 development files)
cmake ..

# Compile
make -j$(nproc)

# Install to system
sudo make install
```

**Build dependencies** (install these if the cmake step fails):
- `cmake` ≥ 3.16
- `qt6-base-dev` (or `qt6-base-devel` on Fedora/openSUSE)
- `kf6-kconfig-dev` (or `kf6-kconfig-devel`)
- `kf6-knotifications-dev` (or `kf6-knotifications-devel`)
- `kf6-kio-dev` (or `kf6-kio-devel`)

### Dependency Mapping by Distribution

This table shows how to find the same packages on different distros:

| Package | Purpose | Arch | Fedora | Ubuntu/Neon | openSUSE | Debian |
|---------|---------|------|--------|------------|----------|--------|
| audacious | Audio player | audacious | audacious | audacious | audacious | audacious |
| kid3-common | Tag editor | kid3-common | kid3-common | kid3-core | kid3? | kid3-core |
| exiftool | Metadata tool | perl-image-exiftool | perl-Image-ExifTool | libimage-exiftool-perl | perl-Image-ExifTool | libimage-exiftool-perl |
| kdeconnect | Mobile sync | kdeconnect | kdeconnect | kdeconnect | kdeconnect | kdeconnect |
| rsgain | ReplayGain analysis | rsgain | rsgain | rsgain (universe) | rsgain | rsgain |
| bc | Math library | bc | bc | bc | bc | bc |
| CMake (build) | Build system | cmake | cmake | cmake | cmake | cmake |
| Qt6 (build) | GUI framework | qt6-base | qt6-base-devel | qt6-base-dev | libqt6-devel | qt6-base-dev |
| KF6 (build) | KDE libraries | kf6-kconfig | kf6-kconfig-devel | kf6-kconfig-dev | kf6-kconfig-devel | kf6-kconfig-dev |

**Note**: Package names can vary slightly. If a package isn't found, try searching your distro's package manager:
```bash
# Fedora
dnf search rsgain

# Ubuntu/Debian
apt search rsgain

# openSUSE
zypper search rsgain
```

## First-Time Setup

The easiest way to set up MusicLib is to run the setup command in your terminal:

```bash
musiclib-cli setup
```
Alternatively, you can modify the musiclib.conf file directly from ~/.config/musiclib/

This interactive script guides you through initial MusicLib configuration. Here's what it does:

### Step 1: Detect Audacious Installation

The setup script checks for an existing Audacious installation on your system. This ensures MusicLib can properly integrate with your audio player and locate its configuration files.

### Step 2: Locate Music Repository Directories

The script scans for common music directories:
- `~/Music`
- `/mnt/music`
- `~/Downloads/Music`
- Any custom directories you specify

It shows you what it finds and lets you select which directories to include in your library.

### Step 3: Set Download Directory

Configure where new music downloads should be placed. This is used when you import new tracks into MusicLib.

### Step 4: Detect Optional Dependencies

The setup wizard detects which optional tools are installed on your system:
- **RSGain** (`rsgain` command) — Required for the Boost Album feature
- **Kid3 GUI** (`kid3` or `kid3-qt` executable) — For integrated tag editing

If these tools are missing, the wizard displays package names for your distribution. The GUI will gracefully disable features when optional tools are unavailable (with helpful tooltips explaining what's needed).

### Step 5: Create XDG Directory Structure

MusicLib creates the standard Linux XDG directory structure for you:
- `~/.config/musiclib/` — Configuration files
- `~/.local/share/musiclib/data/` — Database and subdirs
- `~/.local/share/musiclib/playlists/` — Playlist files and subdirs
- `~/.local/share/musiclib/logs/` — Operation logs and subdirs

No manual folder creation needed—the script handles it all.

### Step 6: Configure Audacious Integration

If Audacious is detected, the the Song Change plugin and script is configured automatically. 

### Step 7: Build Initial Database

The script offers to scan your selected music directories and build the initial `musiclib.dsv` database. This may take a long time to process, especially for large collections. 

### Migration from Legacy Layout

If you have an existing MusicLib installation in `~/musiclib/`, the setup wizard will detect it and offer to migrate your data to the new XDG-compliant locations.

---
### After Installation

Once installed and setup step completed, you can launch MusicLib from:
- **Application menu** → Search "MusicLib"
- **Command line**: `musiclib`
- **System tray** (appears after first launch)

---


## Core Concepts

### The Database File

MusicLib stores all your music metadata in a simple text file called `musiclib.dsv` (Delimiter Separated Values). This file lives at `~/.local/share/musiclib/data/musiclib.dsv` and contains one row per track with fields separated by `^` characters.

Each row includes:
- **ID** — Unique track identifier
- **Artist**, **Album**, **AlbumArtist**, **SongTitle** — Metadata
- **SongPath** — Absolute path to the audio file
- **Genre** — Music genre
- **SongLength** — Track duration
- **Rating** — Your 0-5 star rating
- **GroupDesc** — Visual star symbols (★★★★★)
- **LastTimePlayed** — Timestamp of last playback

### How Rating Works

When you rate a song, MusicLib:
1. Updates the `musiclib.dsv` database
2. Writes the rating to the audio file's ID3 tags (POPM tag)
3. Updates the Grouping/Work tag with star symbols
4. Generates a star rating image for Conky or other display use
5. Logs the change

This means your ratings are preserved in the files themselves, not just in the database.

### Mobile Sync Workflow

Mobile sync is a two-phase operation:

**Phase A (Accounting)**: When you upload a new playlist, MusicLib first processes the *previous* playlist. It calculates how long that playlist was on your phone (time between uploads) and distributes synthetic "last played" timestamps across the tracks using an exponential distribution. This gives you playback history even though your phone can't report what you actually listened to. It uses actual timestamps for the tracks played from your desktop in Audacious.

**Phase B (Upload)**: MusicLib converts the playlist to `.m3u` format and sends it along with all the music files to your device via KDE Connect.

### Playback Tracking

MusicLib tracks when you listen to music in two ways:

**Desktop (Audacious)**: The Audacious Song Change hook monitors playback and updates `LastTimePlayed` when you've listened to at least 50% of a track (bounded between 30 seconds and 4 minutes). This is logged with the exact timestamp.

**Mobile**: Since mobile devices can't report precise playback data, MusicLib uses the "accounting" system described above to synthesize timestamps based on how long the playlist was on your device.

---

## Using the GUI

### Main Window

The MusicLib GUI has three main areas:

1. **Library View** (default main panel) — Browse and filter your music collection
2. **Toolbar with Now Playing Strip** (top) — See what's currently playing in Audacious, rate the current track, access Audacious and Kid3
3. **Side Panel** (left) — Access different features via tabs

### Library View

The library view shows all your tracks in a sortable table. You can:
- **Search** — Filter by artist, album, or title 
- **Filter** - Library-level filter rated only, unrated only, or no filter
- **Sort** — Click column headers to sort

You can select individual entries and:
- **Rate** — Click the stars to directly rate any track, playing or not
- **Play** — Context menu: play or add selected track to Audacious play queue
- **Edit** — Context menu: open the selected track in Kid3 to edit tag
- **Remove** — Remove selected record from the database (does not remove the file)


### Panels

Select from the Side Panel on the left to access the other panels:

**Mobile Panel** — Upload playlists to your phone, view sync status, and manage mobile operations.

**Maintenance Panel** — Perform database and tag maintenance operations like rebuilding the database, cleaning tags, or importing new music.

**Settings** — (Opens new Window) Configure MusicLib paths, device IDs, and behavior options.

### Toolbar Elements (Top)

**Now Playing** - Shows for the currently playing track:
- Artist and track name
- Star rating (click to change)

**Album View** — (Opens new Window) Show album details for currently playing track

**Playlist** — Select and activate a playlist in Audacious

**Audacious** — Launches/activates Audacious

**Kid3** — Launches/activates Kid3 for currently playing track

### Rating Songs

Three ways to rate:

1. **In the library view**: Click the stars in the Rating column
2. **In the now-playing strip**: Click the stars at the top
3. **Keyboard shortcuts**: Set up global shortcuts in System Settings (Ctrl+0 through Ctrl+5)

Ratings appear instantly and are saved to both the database and the audio file tags.

---

## Common Tasks

### Importing New Music

When you download new music:

1. Open the **Maintenance Panel**
2. Find the **Add New Tracks** frame
3. Enter the artist name 
4. Setting/changing the directory used for placing new tracks with this task is done via the Settings menu.
5. Always review/edit the new track info in kid3 to ensure artist/album name consistency before proceeding
6. Click **Execute**

MusicLib will:
- Normalize the file tags
- Rename files, artist directory, album directory to lowercase with underscores
- Move files to your music repository under `artist/album/`
- Add the new tracks to the database

### Rebuilding the Database

If you need to rebuild the database, it is preferred to run `musiclib-cli build` in the console. See the Command-Line Reference Section in this manual for detaled information, or run `musiclib-cli build --help` in the console. Optionally, you can:

1. Open the **Maintenance Panel**
2. Click **Build Library**
3. Optionally use **Dry Run** to preview changes
4. Click **Execute**

This scans your entire music repository and rebuilds `musiclib.dsv`. Your existing ratings are preserved where paths match.

### Cleaning Tags

To normalize ID3 tags across your collection:

1. Open the **Maintenance Panel**
2. Click **Clean Tags**
3. Select a directory or file
4. Choose a mode:
   - **Merge** — Merge ID3v1 into ID3v2, remove APE tags, embed album art
   - **Strip** — Remove ID3v1 and APE tags only
   - **Embed Art** — Embeds `folder.jpg`, if in the album directory, into the tag as album art, if missing
5. Click **Execute**

### Repairing Corrupted Tags

If a file's tags are corrupted, you can easily rebuild it using data from the file's associated database record:

1. Right-click the track in the library view
2. Select **Rebuild Tag**
3. Confirm the operation

MusicLib will look up the track in the database and rewrite tag from stored values.

### Boosting Album Loudness

To normalize loudness across an album using ReplayGain:

1. Open the **Maintenance Panel**
2. Click **Boost Album**
3. Select an album directory
4. Set target LUFS (default: -18)
5. Click **Execute**

**Note**: This requires `rsgain` to be installed. If it's not available, this feature will be disabled.

---

## Mobile Sync with Android

### Setting Up KDE Connect

Before you can sync to mobile:

1. **Install KDE Connect on your phone**:
   - **Android**: Install from Google Play Store
   - **iOS**: Install from Apple App Store (iOS 14 or later)

2. **Pair your devices**:
   - Open KDE Connect on both devices
   - Click "Refresh" to discover devices
   - Click your device name and accept the pairing request on both sides

3. **Configure MusicLib**:
   - Open **Settings** in MusicLib
   - Go to the **Mobile** tab
   - Enter your device ID (shown in KDE Connect)
   - Click **Save**

### Uploading a Playlist

1. Create a playlist in Audacious with the tracks you want on your phone
2. Open the **Mobile Panel** in MusicLib
3. Select the playlist from the dropdown
4. Select your device
5. Click **Upload**

MusicLib will:
- Process the previous playlist's last-played data (if any)
- Convert the playlist to `.m3u` format
- Send all music files to your device
- Record the upload timestamp

### Understanding Last-Played Accounting

When you upload a *new* playlist, MusicLib looks at the *previous* playlist and asks: "How long was that on the phone?" The time between uploads becomes the "accounting window."

MusicLib then distributes synthetic timestamps across the tracks in the old playlist using an exponential distribution (front-loaded—tracks at the beginning get more recent timestamps). This gives you approximate playback history.

### iOS Limitations

Due to Apple's restrictions:
- File access is more limited than Android
- Playback tracking has reduced precision
- Some file transfer operations may be slower

The core functionality (uploading playlists, last-played accounting) works the same, but iOS users may experience longer transfer times.

### Troubleshooting Mobile Sync

**Device not found**:
1. Ensure both devices are on the same Wi-Fi network
2. Open KDE Connect on both devices
3. Click "Refresh" in KDE Connect
4. Check your firewall isn't blocking port 1716

**Transfer fails**:
1. Ensure the phone has enough storage space
2. Check KDE Connect is running on both devices
3. Try restarting KDE Connect on the phone

**Accounting doesn't work**:
1. Make sure you upload playlists in sequence (don't skip)
2. Verify the previous playlist metadata files exist
3. Check the time between uploads is at least 1 hour

---

## Desktop Integration

### System Tray

MusicLib runs in the system tray. Right-click the icon for quick actions:
- **Show Window** — Open the main interface
- **Rate Current Track** — Quick rating menu
- **Mobile Upload** — Fast playlist upload
- **Quit** — Close MusicLib

### Dolphin Context Menu

Right-click any audio file in Dolphin file manager:
- **Rate in MusicLib** — Set star rating
- **Add to MusicLib** — Import the file
- **Edit Tags with Kid3** — Open in tag editor

### Global Shortcuts

Set up keyboard shortcuts in **System Settings** → **Shortcuts** → **Custom Shortcuts**:

- `Ctrl+M` — Open MusicLib window
- `Ctrl+1` through `Ctrl+5` — Quick rate (1-5 stars)
- `Ctrl+0` — Clear rating

These work system-wide without focusing the MusicLib window.

### Conky Integration

MusicLib generates output files for Conky desktop widgets:

**Output directory**: `~/.local/share/musiclib/data/conky_output/`

**Files generated**:
- `detail.txt` — Artist, album, title
- `starrating.png` — Visual star rating image
- `artloc.txt` — Path to album art
- Album art images (copied for display)

Add these to your `.conkyrc` to display now-playing information on your desktop.

---

## Command-Line Reference

MusicLib provides a full command-line interface via `musiclib-cli`. All GUI operations can be performed from the terminal.

### Global Options

These options are handled by the `musiclib-cli` wrapper before any subcommand:
- `-h, --help` — Show help message and available commands
- `-v, --version` — Show version information
- `--config <path>` — Use alternate config file (default: `~/.config/musiclib/musiclib.conf`)

### Available Commands

#### `musiclib-cli setup`

**Purpose**: Interactive first-run configuration wizard.

**Usage**:
```bash
musiclib-cli setup [--force]
```

**Options**:
- `--force` — Overwrite existing configuration

**What it does**:
- Detects Audacious installation
- Scans for music directories
- Creates XDG directory structure
- Detects optional dependencies (RSGain, Kid3 GUI)
- Generates configuration file
- Provides Audacious Song Change plugin setup instructions
- Optionally builds initial database

**Example**:
```bash
# First-time setup
musiclib-cli setup

# Reconfigure (overwrites existing config)
musiclib-cli setup --force
```

---

#### `musiclib-cli rate`

**Purpose**: Set star rating (0–5) for a track.

**Usage**:
```bash
musiclib-cli rate RATING [FILEPATH]
```

**Parameters**:
- `RATING` — Integer 0–5 (0=unrated, 5=highest)
- `FILEPATH` — (Optional) Absolute path to audio file

**Behavior**:
- When `FILEPATH` is provided: Rates that specific file (GUI mode)
- When omitted: Rates the currently playing track in Audacious (keyboard shortcut mode)

**Examples**:
```bash
# Rate a specific file
musiclib-cli rate 4 "/mnt/music/pink_floyd/dark_side/money.mp3"

# Rate currently playing track (requires Audacious)
musiclib-cli rate 5
```

**What changes**:
- Updates database (`musiclib.dsv`)
- Writes POPM tag to file
- Updates Grouping/Work tag
- Regenerates Conky star rating image

---

#### `musiclib-cli build`

**Purpose**: Build or rebuild the music library database from a full filesystem scan.

**Usage**:
```bash
musiclib-cli build [MUSIC_DIR] [options]
```

**Arguments**:
- `MUSIC_DIR` — Root directory of music library (defaults to configured `MUSIC_ROOT_DIR`)

**Options**:
- `-h, --help` — Display this help
- `-d, --dry-run` — Preview mode — show what would be processed without making changes
- `-o FILE` — Output file path (default: configured `MUSICDB`)
- `-m DEPTH` — Minimum subdirectory depth from root (default: 1)
- `--no-header` — Suppress database header in output
- `-q, --quiet` — Quiet mode — minimal output
- `-s COLUMN` — Sort output by column number
- `-b, --backup` — Create a timestamped backup of the existing database before writing
- `-t, --test` — Test mode — write output to a temporary file instead of the real database
- `--no-progress` — Disable progress indicators

**What it does**:
- Scans the music directory recursively for audio files
- Extracts metadata (artist, album, title, duration, etc.) from file tags via `exiftool`
- Generates a fresh database (`musiclib.dsv`) with all discovered tracks
- Resets `LastTimePlayed` to `0` for all tracks (use `-b` to back up existing data first)
- Assigns new sequential track IDs and regenerates album IDs

**Examples**:
```bash
# Preview what would be rebuilt (safe to run anytime)
musiclib-cli build --dry-run

# Rebuild the database, creating a backup first
musiclib-cli build -b

# Write to a temp file to inspect output without touching the live database
musiclib-cli build -t

# Custom output file
musiclib-cli build /mnt/music -o ~/music_backup.dsv

# Rebuild a subdirectory for testing
musiclib-cli build /mnt/music/Rock -t
```

**Exit codes**:
- `0` — Success
- `1` — Dry-run complete (informational) or user error (invalid arguments)
- `2` — System failure (missing directory, tools unavailable, lock timeout, scan failure)

**Note**: This replaces the entire database. It takes 10+ minutes for large libraries (10,000+ tracks). Always use `--dry-run` first, and `-b` to back up before rebuilding.

---

#### `musiclib-cli new-tracks`

**Purpose**: Import new music downloads from the configured download directory into the library.

**Usage**:
```bash
musiclib-cli new-tracks [artist_name]
musiclib-cli new-tracks --help|-h|help
```

**Arguments**:
- `artist_name` — Artist name for folder organization (optional — prompts interactively if omitted). Normalized to lowercase with underscores.

**Options**:
- `--help, -h, help` — Display help message and exit

**What it does**:
1. Extracts any ZIP archives found in the download directory (automatic)
2. Pauses to let you edit tags in kid3-qt — **check the Album tag**, since it determines the destination folder name
3. Normalizes MP3 filenames from their ID3 tags (lowercase, underscores)
4. Standardizes volume levels with `rsgain` (if installed)
5. Organizes files into `MUSIC_REPO/artist/album/` folder structure
6. Adds all imported tracks to the `musiclib.dsv` database

**Required tools**: `kid3-cli`, `exiftool`, `unzip`. `rsgain` is optional (used for volume normalization).

**Examples**:
```bash
# Interactive mode — prompts for artist name
musiclib-cli new-tracks

# Provide artist name upfront
musiclib-cli new-tracks "Pink Floyd"
musiclib-cli new-tracks "the_beatles"
```

**Exit codes**:
- `0` — Success (all tracks imported)
- `1` — User error (invalid input, user cancelled)
- `2` — System error (missing tools, I/O failure, config error)
- `3` — Deferred (database operations queued due to lock contention)

**Note**: New downloads must be placed in the configured `NEW_DOWNLOAD_DIR` before running. The source directory is set in `musiclib.conf` and cannot be overridden from the command line.

---

#### `musiclib-cli mobile`

Mobile playlist operations. Has several subcommands:

##### `musiclib-cli mobile upload`

**Purpose**: Upload a playlist to mobile device via KDE Connect.

**Usage**:
```bash
musiclib-cli mobile upload <playlist.audpl> [device_id] [options]
```

**Arguments**:
- `<playlist.audpl>` — Playlist filename or basename (with or without `.audpl` extension)
- `[device_id]` — KDE Connect device ID (optional — uses configured default if omitted)

**Options**:
- `--end-time "MM/DD/YYYY HH:MM:SS"` — Override the accounting window end time (default: now)
- `--non-interactive` — Skip interactive prompts; auto-refreshes newer Audacious playlists without asking (used by the GUI)

**What it does**:
1. **Accounting**: Processes the previous playlist's last-played data before replacing it
2. **Upload**: Converts the playlist to `.m3u` format and transfers it plus all track files to the device via `kdeconnect-cli --share`

**Example**:
```bash
# Upload with interactive prompts
musiclib-cli mobile upload workout

# Upload using a specific KDE Connect device
musiclib-cli mobile upload workout abc123def456

# Non-interactive upload (for GUI)
musiclib-cli mobile upload workout --non-interactive

# Backdate the accounting window
musiclib-cli mobile upload workout --end-time "02/15/2026 21:00:00"
```

##### `musiclib-cli mobile status`

**Purpose**: Show current mobile playlist status.

**Usage**:
```bash
musiclib-cli mobile status
```

**Output shows**:
- Current active playlist
- Upload timestamp
- Track count
- Recovery file status
- Recent operations

##### `musiclib-cli mobile retry`

**Purpose**: Re-attempt failed last-played updates.

**Usage**:
```bash
musiclib-cli mobile retry <playlist_name>
```

**What it does**:
Processes tracks from `.pending_tracks` and `.failed` recovery files, attempting to update their last-played timestamps.

##### `musiclib-cli mobile update-lastplayed`

**Purpose**: Manually trigger last-played accounting for a playlist.

**Usage**:
```bash
musiclib-cli mobile update-lastplayed <playlist_name> [--end-time "MM/DD/YYYY HH:MM:SS"]
```

**Example**:
```bash
# Process with current time
musiclib-cli mobile update-lastplayed workout

# Backdate the window
musiclib-cli mobile update-lastplayed workout --end-time "02/15/2026 18:00:00"
```

##### `musiclib-cli mobile refresh-audacious-only`

**Purpose**: Copy playlists from Audacious to MusicLib directory.

**Usage**:
```bash
musiclib-cli mobile refresh-audacious-only
```

##### `musiclib-cli mobile logs`

**Purpose**: Display the mobile operations log.

**Usage**:
```bash
musiclib-cli mobile logs [filter]
```

**Arguments**:
- `[filter]` — Optional keyword to narrow output. Recognized values: `errors`, `warnings`, `stats`, `today`

**Example**:
```bash
# Show all log entries
musiclib-cli mobile logs

# Show only errors
musiclib-cli mobile logs errors

# Show only today's entries
musiclib-cli mobile logs today

# Show only stats/summary lines
musiclib-cli mobile logs stats
```

##### `musiclib-cli mobile cleanup`

**Purpose**: Remove orphaned playlist metadata files.

**Usage**:
```bash
musiclib-cli mobile cleanup
```

##### `musiclib-cli mobile check-update`

**Purpose**: Check if Audacious playlist is newer than MusicLib copy.

**Usage**:
```bash
musiclib-cli mobile check-update <playlist_name>
```

**Output**:
- `STATUS:newer` — Audacious version is newer (exit 0)
- `STATUS:new` — Playlist exists in Audacious but not MusicLib (exit 0)
- `STATUS:same` — MusicLib version is current (exit 1)
- `STATUS:not_found` — Playlist not found (exit 1)

---

#### `musiclib-cli tagclean`

**Purpose**: Clean and normalize MP3 ID3 tags for MusicLib compatibility.

**Usage**:
```bash
musiclib-cli tagclean [COMMAND] [TARGET] [options]
```

**Subcommands** (optional — pass instead of a path to get help/info):
- `help` — Show help message (same as `-h`)
- `examples` — Show common usage examples
- `modes` — Explain the three operation modes in detail
- `troubleshoot` — Show troubleshooting tips
- `process TARGET` — Explicitly process a file or directory (default behavior when TARGET looks like a path)

**Arguments**:
- `TARGET` — MP3 file or directory to process

**Options**:
- `-h, --help` — Show help
- `-r, --recursive` — Process directories recursively
- `-a, --remove-ape` — Remove APE tags (default: keep them)
- `-g, --remove-rg` — Remove ReplayGain tags
- `-n, --dry-run` — Show what would be done without making any changes
- `-v, --verbose` — Show detailed processing information per file
- `-b, --backup-dir DIR` — Custom backup directory (default: configured `BACKUP_DIR`)
- `--mode MODE` — Operation mode: `merge` (default), `strip`, or `embed-art`
- `--art-only` — Alias for `--mode embed-art`
- `--ape-only` — Remove APE tags only (legacy mode)
- `--rg-only` — Remove ReplayGain tags only (can be combined with any mode)

**Modes**:
- `merge` — Merge ID3v1 → ID3v2.4, remove ID3v1 tags, optionally remove APE/ReplayGain tags, and embed album art from `folder.jpg`
- `strip` — Remove ID3v1 and APE tags only (no art embedding)
- `embed-art` — Only embed album art from a `folder.jpg` file if art is missing from the tag

**Examples**:
```bash
# Full cleanup with merge mode (the default)
musiclib-cli tagclean /mnt/music/pink_floyd -r

# Merge mode, explicitly stated
musiclib-cli tagclean /mnt/music/pink_floyd -r --mode merge

# Strip mode — remove old tag formats only
musiclib-cli tagclean /mnt/music/radiohead -r --mode strip

# Embed album art only
musiclib-cli tagclean /mnt/music/the_beatles/abbey_road -r --mode embed-art
musiclib-cli tagclean /mnt/music/the_beatles/abbey_road -r --art-only

# Merge mode + remove APE tags + remove ReplayGain tags
musiclib-cli tagclean /mnt/music -r -a -g

# Dry run first to see what would happen
musiclib-cli tagclean /mnt/music -r -n

# Dry run with verbose detail
musiclib-cli tagclean /mnt/music -r -n -v

# Show mode explanations
musiclib-cli tagclean modes

# Get troubleshooting tips
musiclib-cli tagclean troubleshoot
```

---

#### `musiclib-cli tagrebuild`

**Purpose**: Repair corrupted or malformed ID3 tags on MP3 files by restoring values from the MusicLib database.

**Usage**:
```bash
musiclib-cli tagrebuild <TARGET> [<TARGET> ...] [options]
```

**Arguments**:
- `TARGET` — One or more MP3 files or directories to process. Multiple targets can be given in a single call.

**Options**:
- `-r, --recursive` — Process directories recursively
- `-n, --dry-run` — Preview changes without modifying any files
- `-v, --verbose` — Show detailed processing information per file
- `-b, --backup-dir DIR` — Custom backup directory for pre-repair copies
- `-h, --help` — Show help message

**What it does**:
1. Looks up each track in the `musiclib.dsv` database by file path
2. Strips all existing (corrupted) tags from the file
3. Rewrites tags using database-authoritative values: artist, album, title, track number, rating, etc.
4. Restores non-database fields that are preserved during the process: ReplayGain tags and embedded album art

**Examples**:
```bash
# Repair a single file
musiclib-cli tagrebuild /mnt/music/corrupted/song.mp3

# Repair multiple specific files in one call
musiclib-cli tagrebuild /mnt/music/track1.mp3 /mnt/music/track2.mp3

# Preview what would be repaired (no changes made)
musiclib-cli tagrebuild /mnt/music/pink_floyd -r -n -v

# Repair all files in a directory (non-recursive)
musiclib-cli tagrebuild /mnt/music/pink_floyd/the_wall/

# Repair recursively after previewing
musiclib-cli tagrebuild /mnt/music/pink_floyd -r
```

**Recommended workflow**:
```bash
# Step 1: Preview with verbose output
musiclib-cli tagrebuild /path/to/music -r -n -v

# Step 2: Review the output, then apply
musiclib-cli tagrebuild /path/to/music -r
```

---

#### `musiclib-cli boost`

**Purpose**: Apply ReplayGain loudness targeting to an album.

**Usage**:
```bash
musiclib-cli boost ALBUM_DIR LOUDNESS
```

**Arguments**:
- `ALBUM_DIR` — Path to the directory containing the album's MP3 files (required)
- `LOUDNESS` — Target loudness level as a positive integer (required). This is the absolute value of the target in LUFS — e.g., `12` means −12 LUFS, `13` means −13 LUFS. Higher numbers = quieter result; lower numbers = louder result. Values of `12` or `13` are typical.

Both arguments are required. The script exits immediately with a usage error if either is missing.

**What it does**:
1. Removes any existing ReplayGain tags from all `.mp3` files in the directory (via `kid3-cli`)
2. Rescans the album with `rsgain` at the specified target loudness, applying album-level ReplayGain tags

**Examples**:
```bash
# Target -12 LUFS (louder)
musiclib-cli boost /mnt/music/pink_floyd/the_wall 12

# Target -13 LUFS (slightly quieter)
musiclib-cli boost /mnt/music/radiohead/ok_computer 13
```

**Note**: Requires both `rsgain` and `kid3-cli` to be installed. Only processes `.mp3` files directly inside `ALBUM_DIR` (not recursive).

---

#### `musiclib-cli scan`

**Purpose**: Scan playlists and generate cross-reference CSV.

**Usage**:
```bash
musiclib-cli scan [PLAYLIST_DIR]
```

**Parameters**:
- `PLAYLIST_DIR` — Directory to scan (defaults to `~/.local/share/musiclib/playlists/`)

**Output**: CSV to stdout showing which playlists contain which tracks.

**Example**:
```bash
# Scan default directory
musiclib-cli scan > playlist_cross_reference.csv

# Scan specific directory
musiclib-cli scan ~/.config/audacious/playlists > audacious_playlists.csv
```

---

#### `musiclib-cli audacious`

**Purpose**: Audacious Song Change hook (called automatically by Audacious).

**Usage**:
```bash
musiclib-cli audacious
```

**Called by**: Audacious Song Change plugin on every track change

**What it does**:
1. Queries current track from Audacious
2. Updates Conky display files
3. Extracts album art
4. Monitors playback to scrobble threshold (50% of track, 30s–4min)
5. Updates `LastTimePlayed` in database and file tags
6. Logs to playback history

**Note**: You should not call this manually. It's configured in Audacious Settings → Plugins → Song Change.

---

#### `musiclib-cli remove-record`

**Purpose**: Remove a track's database record (doesn't delete the file).

**Usage**:
```bash
musiclib-cli remove-record FILEPATH
```

**Parameters**:
- `FILEPATH` — Absolute path to audio file

**What it does**:
Removes the database row for the specified file. The audio file itself is not deleted from disk.

**Example**:
```bash
# Remove a track's database record
musiclib-cli remove-record "/mnt/music/deleted/old_track.mp3"
```

---

#### `musiclib-cli help`

**Purpose**: Display help information.

**Usage**:
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

---

#### `musiclib-cli version`

**Purpose**: Display version information.

**Usage**:
```bash
musiclib-cli version
musiclib-cli --version
```

---

## Standalone Utilities

MusicLib includes standalone utility scripts that operate outside the normal command-line interface. These tools are for specific pre-setup or maintenance scenarios.

### conform_musiclib.sh — Filename Conformance Tool

**Location**: `~/.local/share/musiclib/utilities/conform_musiclib.sh`

**Purpose**: Rename non-conforming music filenames to MusicLib naming standards **before** database creation.

**When to use**: Before running `musiclib-cli setup`, if your music files have:
- Uppercase letters
- Spaces in filenames
- Accented or special characters
- Inconsistent naming that would cause issues with mobile sync

**How it works**:

The script scans your music directory and applies these naming rules:
- **Lowercase only**: `Track_01.mp3` → `track_01.mp3`
- **Spaces become underscores**: `My Song.mp3` → `my_song.mp3`
- **Non-ASCII transliterated**: `Café.mp3` → `cafe.mp3`
- **Multiple underscores collapsed**: `a__b.mp3` → `a_b.mp3`
- **Safe characters only**: `a-z`, `0-9`, `_`, `-`, `.`

**Usage**:

```bash
# Preview changes (dry-run, default)
~/.local/share/musiclib/utilities/conform_musiclib.sh /path/to/music

# Actually rename files
~/.local/share/musiclib/utilities/conform_musiclib.sh --execute /path/to/music

# Verbose output
~/.local/share/musiclib/utilities/conform_musiclib.sh --verbose /path/to/music

# Combined: verbose execute
~/.local/share/musiclib/utilities/conform_musiclib.sh --verbose --execute /path/to/music
```

**Options**:
- `--execute` — Actually rename files (default is dry-run preview)
- `--dry-run` — Preview changes without renaming (default)
- `-v, --verbose` — Show detailed output for each file
- `-h, --help` — Show help message
- `--version` — Show version information

**Safety Features**:

1. **Dry-run by default**: Requires `--execute` flag to make changes
2. **Copy-verify-delete workflow**: Never moves files; copies to new name, verifies size match, then deletes original
3. **Collision detection**: Skips files if target filename already exists
4. **Detailed logging**: Writes to `~/.local/share/musiclib/logs/conform_YYYYMMDD_HHMMSS.log`
5. **Statistics summary**: Shows counts of scanned, conforming, non-conforming, processed, skipped, and failed files

**Example Output**:

```
========================================
MusicLib Filename Conformance Tool
========================================

MODE: DRY-RUN (preview only, no files will be changed)
      Use --execute to actually rename files

Music Repository: /mnt/music
Log File: ~/.local/share/musiclib/logs/conform_20260225_143022.log

Scanning for music files...

Non-conforming files found:

  Directory: /mnt/music/Pink Floyd/The Wall
    Disc 1/01 - In The Flesh.mp3
      Would rename to: disc_1/01_-_in_the_flesh.mp3

    Disc 2/05 - Comfortably Numb.mp3
      Would rename to: disc_2/05_-_comfortably_numb.mp3

  Directory: /mnt/music/Radiohead/OK Computer
    01 - Airbag.mp3
      Would rename to: 01_-_airbag.mp3

========================================
Summary
========================================
Total files scanned: 1,247
  Conforming files: 1,203
  Non-conforming files: 44

DRY-RUN complete. No files were changed.
Run with --execute to apply these changes.
```

**When the Setup Wizard Needs This**:

During `musiclib-cli setup`, if the library analysis detects non-conforming filenames, you'll see:

```
⚠ WARNING: Non-conforming filenames detected in your music library.

Found 44 files with:
  - Uppercase letters
  - Spaces
  - Special characters

MusicLib requires lowercase filenames with underscores for reliable operation.

Options:
  1. Continue anyway (may cause issues with mobile sync and path matching)
  2. Exit and run conform_musiclib.sh to fix filenames
  3. Cancel setup

Choice [1/2/3]:
```

If you choose option 2, you'll be directed to run:

```bash
~/.local/share/musiclib/utilities/conform_musiclib.sh --execute /your/music/path
```

After the script completes, re-run `musiclib-cli setup`.

**WARNING**: This script modifies your files. **Make backups first**. Use solely at your own risk.

---

## Troubleshooting

### Common Issues

**MusicLib won't start**
1. Check that KDE Plasma 6 is running: `plasmashell --version`
2. Verify dependencies are installed: `kid3-cli --version`, `exiftool -ver`
3. Check logs: `~/.local/share/musiclib/logs/musiclib.log`

**Ratings don't save**
1. Ensure `kid3-cli` is installed: `which kid3-cli`
2. Check file permissions: Files must be writable
3. Verify database isn't corrupted: `musiclib-cli build --dry-run`

**Audacious integration not working**
1. Verify Audacious is running: `pgrep audacious`
2. Check Song Change plugin is enabled: Audacious → Settings → Plugins
3. Verify hook script path: `/usr/lib/musiclib/bin/musiclib_audacious.sh`
4. Test manually: `musiclib-cli audacious`

**Conky not updating**
1. Check Conky output directory exists: `ls ~/.local/share/musiclib/data/conky_output/`
2. Verify Audacious hook is configured (see above)
3. Play a track and check if files are created
4. Check permissions on output directory

**Mobile sync fails**
1. **Device not found**:
   - Ensure both devices on same Wi-Fi network
   - Open KDE Connect on both devices
   - Click "Refresh" in KDE Connect
   - Check firewall (port 1716)
   - Verify device is paired
2. **Transfer fails**:
   - Check phone has enough storage space
   - Restart KDE Connect on phone
   - Try `kdeconnect-cli --ping` to test connection
3. **Accounting doesn't work**:
   - Upload playlists in sequence (don't skip)
   - Check time between uploads is at least 1 hour
   - Verify previous playlist metadata files exist

**Database corruption**
1. Check for backup files: `ls ~/.local/share/musiclib/data/*.backup.*`
2. Restore from backup: `cp musiclib.dsv.backup.YYYYMMDD_HHMMSS musiclib.dsv`
3. If no backup: `musiclib-cli build` to rebuild from filesystem
4. Always make manual backups: `cp musiclib.dsv musiclib.dsv.manual.backup`

**Lock timeout errors**
- Wait a few seconds and try again
- Check if another MusicLib process is running: `ps aux | grep musiclib`
- Kill stuck processes: `pkill -f musiclib`
- Check database lock file: `ls ~/.local/share/musiclib/data/musiclib.dsv.lock`

### KDE Connect Issues

**Devices won't pair**
1. Ensure KDE Connect is the same version on both devices
2. Some distros ship outdated KDE Connect — try updating:
   - **Fedora**: `sudo dnf upgrade kdeconnect`
   - **Ubuntu/Debian**: `sudo apt upgrade kdeconnect`
   - **openSUSE**: `sudo zypper update kdeconnect`
3. Restart both services and try again
4. Check your firewall (KDE Connect uses port 1716)
5. **For iOS users**: Make sure you have iOS 14 or later and the latest KDE Connect app
6. **For Android users**: Update the KDE Connect app from Google Play Store

---

## Tips & Tricks

### Speed Up Search

Long library? Use smart filtering:
- Filter by **Genre** first (narrows the pool)
- Then search within that genre
- Much faster than searching everything

### Backup Your Library

Your database is important. Backup regularly:

```bash
cp ~/.local/share/musiclib/data/musiclib.dsv \
   ~/Backup/musiclib.dsv.$(date +%Y%m%d)
```

Or automate it with a cron job:
```bash
# Add to crontab: backup database daily at 2am
0 2 * * * cp ~/.local/share/musiclib/data/musiclib.dsv ~/Backup/musiclib.dsv.$(date +\%Y\%m\%d)
```

### Export Playlists for Other Apps

MusicLib exports to standard `.m3u` format, readable by any media player:

```bash
ls ~/.local/share/musiclib/playlists/*.m3u
```

Copy these files to USB, upload to your phone, or open in other apps.

### Use Global Shortcuts

Set up keyboard shortcuts for:
- `Ctrl+M` — Open MusicLib window
- `Ctrl+1` through `Ctrl+5` — Quick rate (1-5 stars)
- `Ctrl+0` — Clear rating
- `Ctrl+Shift+M` — Toggle system tray

This speeds up workflow without opening windows.

### Create Smart Filters

Save your favorite filter combinations:

1. Set up a filter (e.g., "Jazz, 4+ stars, added this year")
2. Click **[Save as Smart Filter]**
3. Name it (e.g., "Summer Jazz Favorites")
4. Next time, one click loads it

### Batch Rating

To rate multiple tracks at once:
1. Select multiple rows in the library view (Ctrl+Click or Shift+Click)
2. Right-click → **Set Rating**
3. Choose your rating
4. All selected tracks get the same rating

### Command-Line Batch Operations

Use shell scripts to automate tasks:

```bash
# Rate all tracks in a directory
for file in /mnt/music/radiohead/ok_computer/*.mp3; do
    musiclib-cli rate 5 "$file"
done

# Import multiple artist directories
for artist in "Radiohead" "Pink Floyd" "The Beatles"; do
    musiclib-cli new-tracks "$artist" --source ~/Downloads/new_music
done
```

---

## Glossary

- **Audacious** — The music player MusicLib controls
- **DSV** — Delimited Separated Values (the text format of the database)
- **KDE Connect** — Technology for syncing between your computer and phone
- **KDE Plasma** — The desktop environment
- **Metadata** — Information about songs (artist, title, album, etc.)
- **Rating** — Your personal 1-5 star score for a song
- **Tag** — Information stored inside an audio file (artist, album, etc.)
- **Playback Tracking** — Recording what you listen to and when
- **LUFS** — Loudness Units relative to Full Scale (audio loudness measurement)
- **ReplayGain** — Audio normalization standard that adjusts volume without affecting quality
- **XDG** — XDG Base Directory Specification (Linux standard for config/data locations)

---

## Frequently Asked Questions

**Q: Do I need Arch Linux to use MusicLib?**  
A: No. MusicLib works on any Linux distribution with KDE Plasma 6 — Fedora, Ubuntu, openSUSE, Debian, etc.

**Q: Does MusicLib replace my music player?**  
A: No. It works alongside Audacious. You play music in Audacious; MusicLib manages everything else.

**Q: Can I use MusicLib with Spotify?**  
A: Not yet. MusicLib is for local files only.

**Q: Why do I have to use Audacious?**  
A: MusicLib uses Audacious for two reasons:

**1. Rich Data Access via audtool**: `audtool` provides programmatic access that no other Linux player offers, allowing MusicLib to track with precision, detect changes immediately, and automate complex operations.

**2. Superior Sound Quality**: Audacious offers direct ALSA output (bypasses PulseAudio resampling), floating-point processing, and minimal DSP for bit-perfect audio.

**How MusicLib Complements Audacious**: While Audacious excels at playback, MusicLib fills critical gaps in library management, ratings & organization, last-played tracking, and deep KDE integration.

**Q: What if I don't have an Android phone?**  
A: All core features (organizing, rating, syncing within Linux) still work. If you have an iPhone, MusicLib supports iOS too via KDE Connect.

**Q: Can I use MusicLib with both Android and iOS devices?**  
A: Yes! MusicLib works with both. See the "Mobile Sync with Android" section for setup.

**Q: Are there differences between Android and iOS syncing?**  
A: Yes, due to Apple's restrictions. iOS has limited playback tracking and file access, and transfers may be slower.

**Q: Can multiple people share one library?**  
A: Not yet. Each computer needs its own MusicLib instance.

**Q: Do I lose my ratings if I delete MusicLib?**  
A: No. Ratings are saved in the song files themselves (POPM tag). You can import them into another library tool.

**Q: How much disk space does MusicLib use?**  
A: Very little. The database is text-based and typically <5MB even for huge libraries.

**Q: Is my listening history private?**  
A: Yes. Everything stays on your devices. Nothing is sent to the internet.

**Q: What if rsgain isn't available for my distro?**  
A: You can skip it. MusicLib works fine without rsgain — the Boost Album feature just won't be available.

**Q: Can I edit the database file directly?**  
A: Technically yes (it's plain text), but it's not recommended. Use the GUI or CLI instead to avoid corruption.

**Q: What happens if I move my music files?**  
A: The database stores absolute paths. If you move files, run `musiclib-cli build` to rebuild the database with new paths. Ratings will be preserved where filenames match.

---

## Future Features (Planned)

MusicLib is actively being developed. Here are features planned for future releases:

### Advanced Playlist Creation (Planned for v0.2)

Future versions will include intelligent playlist generation that considers multiple factors:

- **Play History**: Create playlists biased toward songs you haven't played recently
- **Ratings**: Weight songs by your star ratings (prefer 4-5 star songs, avoid 1 star)
- **Artist Rotation**: Avoid repeating the same artist too frequently
- **Smart Mixing**: Combine these factors to generate varied, fresh playlists automatically

**Example use cases**:
- "Show me my favorite songs I haven't heard in a month"
- "Create a playlist from different artists, avoiding those I heard yesterday"
- "Mix my top-rated songs with some new discoveries"

### KRunner Integration (Planned for v0.3)

Quick actions from KRunner (Alt+Space):
- Search and play tracks
- Rate current song
- Upload playlists

### Plasma Widget (Planned for v0.4)

Desktop/panel widget showing now-playing information from Conky output with click-to-rate functionality.

---

## Documentation

- **In-app Help**: Press `F1` in MusicLib
- **Man Pages**: `man musiclib-qt`, `man musiclib-cli`
- **Online**: Visit the MusicLib GitHub wiki

### Reporting Issues

If you find a bug:

1. **Check the logs**: `~/.local/share/musiclib/logs/musiclib.log`
2. **Reproduce the issue**: Try to make it happen again
3. **Report on GitHub**: Include:
   - Steps to reproduce
   - Your MusicLib version (`musiclib-qt --version`)
   - Your KDE Plasma version
   - Any error messages from logs

### Asking Questions

- **Forum**: Arch Linux forums (tag your post `[musiclib]`)
- **IRC**: KDE Plasma IRC channel
- **Reddit**: r/archlinux, r/kde

---

## Version History

- **v0.1 Alpha** (Feb 2026) — Initial release with GUI core, ratings, and mobile sync
- Future versions will add KRunner, Plasma widgets, and advanced features

---

**Questions? Suggestions? Visit the MusicLib project on GitHub or post in the Arch Linux forums.**

Happy listening! 🎵
