# MusicLib User Manual

**Version**: 1.62
**Last Updated**: April 2026
**For**: MusicLib on Linux with KDE Plasma 6

---

## Table of Contents

1. [Introduction](#introduction)
2. [Compatibility](#compatibility)
3. [Installation](#installation)
4. [First-Time Setup](#first-time-setup)
5. [Quick Start](#quick-start)
6. [Core Concepts](#core-concepts)
7. [Using the GUI](#using-the-gui)
8. [Library Management Tasks](#library-management-tasks)
9. [Mobile Sync](#mobile-sync)
10. [CD Ripping](#cd-ripping)
11. [Desktop Integration](#desktop-integration)
12. [Smart Playlist](#smart-playlist)
13. [Command-Line Reference](#command-line-reference)
14. [Standalone Utilities](#standalone-utilities)
15. [FAQ](#frequently-asked-questions)
16. [Troubleshooting](#troubleshooting)
17. [Tips & Tricks](#tips--tricks)

---

## Introduction

MusicLib is a personal music library **management hub** designed for KDE Plasma users who want to organize, track, and manage their local music collections. It works on **any Linux distribution with KDE Plasma 6** — whether you use Arch, Fedora, Ubuntu, openSUSE, or anything in between.

Rather than juggling multiple applications, MusicLib brings everything together in one integrated experience:

- **Rate and organize** your music collection
- **Play and Queue** tracks/playlists directly via integration with Audacious
- **Create Smart Playlists** using your database to produce real variety
- **Edit tags** via integration with Kid3
- **Remove, Add, and Edit** tracks/database entries
- **Track playback** across devices
- **Sync to mobile** (Android or iOS)
- **Deep KDE integration** (system tray, shortcuts, file manager)

It sits between you and the Audacious audio player, and handles all the behind-the-scenes work: organizing metadata, rating songs, tracking what you listen to, and syncing playlists to your **Android or iOS device** via KDE Connect. It adds significant features not available to the outstanding Audacious media player, yet integrates seamlessly with it and with the Kid3 tag editor.

### What MusicLib Does

- **Centralizes Your Music**: Maintains a single database of all your songs, albums, and metadata—and expands each file's tag data to store rating and last-played information
- **Rates and Organizes**: Star-rate songs and see your ratings everywhere, including Dolphin file manager
- **Tracks Playback**: Records last-played history across devices—desktop (Audacious) and remote (mobile phone)
- **Creates Smart Playlists**: Most smart playlist schemes are pretty crude. This one creates **real variety**
- **Syncs to Mobile**: Pushes playlists/files to Android or iOS devices via KDE Connect, and captures the last-played data from the old playlist when the new one is replaced. Logs actual played timestamps for tracks played from the desktop, and logs synthesized dates for playlists played on mobile
- **Rips CDs**: Manages K3b's rip configuration (format, bitrate, error correction) and deploys it before each session, so K3b is always ready with the settings you want
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

MusicLib is Linux-based, but **distro-agnostic**. The shell scripts and GUI work on any Linux distribution with KDE Plasma 6 and the required dependencies.

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
2. **Audacious** music player (audtool and song change plug-in features)
3. **kid3-common/kid3-core** (command-line tag editor)
4. **exiftool** (metadata processor)
5. **KDE Connect** (for mobile sync)
6. **Standard Unix tools** like `bash`, `bc`, `coreutils`, `grep`, `sed`
7. A **mobile device** (optional, for mobile features):
   - **Android** (any version with KDE Connect support)
   - **iOS/iPhone** (iOS 14 or later with KDE Connect app)

**Optional but Recommended**:

- **kid3 (KDE) or kid3-qt (QT)** (GUI-based tag editor) — Opens directly from MusicLib for detailed metadata editing. Provides a full-featured interface for ID3 tags, album art, and more, and includes kid3-cli/kid3-common.
- **rsgain** (ReplayGain analyzer) — Required for the Boost Album feature. May need to be compiled from source on some distros.
- **k3b** (CD ripper) — Required for the CD Ripping panel and Rip CD toolbar action. When detected by setup, MusicLib manages K3b's rip configuration (output format, bitrate, error correction) and deploys it to K3b before each rip session.

## Installation

### Arch Linux (AUR)

```bash
# Install just the backend and CLI
yay -S musiclib-cli

# or

# Install the GUI
yay -S musiclib

# Optional and strongly recommended: Install GUI tag editor (for integrated tag editing from MusicLib) and ReplayGain (loudness normalizer)
pacman -S kid3
yay -S rsgain

# Optional: Install K3b CD ripper (for CD Ripping panel and Rip CD toolbar action)
pacman -S k3b
```

All dependencies are automatically resolved.

### Fedora KDE (dnf)

```bash
# Install dependencies
sudo dnf install audacious kid3-common exiftool kdeconnect bc grep sed

# For ReplayGain (optional, loudness normalizer)
sudo dnf install rsgain

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo dnf install kid3

# Optional: Install K3b CD ripper (for CD Ripping panel and Rip CD toolbar action)
sudo dnf install k3b
```

### Ubuntu/Kubuntu/KDE Neon (apt)

```bash
# Install dependencies
sudo apt install audacious kid3-common exiftool kdeconnect bc attr

# For ReplayGain (if available in your repo)
sudo apt install rsgain
# If not available, you can skip this — Boost Album feature won't work

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo apt install kid3

# Optional: Install K3b CD ripper (for CD Ripping panel and Rip CD toolbar action)
sudo apt install k3b

# Clone and build from source
git clone https://github.com/yourusername/musiclib.git
cd musiclib
mkdir build && cd build
cmake ..
make
sudo make install
```

> **Ubuntu 25.10 note:** Ubuntu 25.10 is migrating from GNU coreutils to [uutils coreutils](https://github.com/uutils/coreutils), a Rust rewrite. The `attr` package (`setfattr`/`getfattr`) is independent of coreutils and is unaffected by this migration directly, but the overall dependency chain for xattr support has not been fully validated against the uutils runtime. If Dolphin ratings are not displaying after installation on Ubuntu 25.10 or later, verify that `setfattr` is functional by running `setfattr --version` and, if necessary, reinstall the `attr` package manually: `sudo apt install --reinstall attr`.

### openSUSE Plasma (zypper)

```bash
# Install dependencies
sudo zypper install audacious kid3-common exiftool kdeconnect bc grep sed

# For ReplayGain (optional, loudness normalizer)
sudo zypper install rsgain

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo zypper install kid3

# Optional: Install K3b CD ripper (for CD Ripping panel and Rip CD toolbar action)
sudo zypper install k3b

# Clone and build from source
git clone https://github.com/Harpo3/musiclib.git
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

# Optional: ReplayGain (if available, loudness normalizer)
sudo apt install rsgain

# Optional: Install GUI tag editor (for integrated tag editing from MusicLib)
sudo apt install kid3

# Optional: Install K3b CD ripper (for CD Ripping panel and Rip CD toolbar action)
sudo apt install k3b

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

| Package       | Purpose             | Arch                | Fedora              | Ubuntu/Neon            | openSUSE            | Debian                 |
| ------------- | ------------------- | ------------------- | ------------------- | ---------------------- | ------------------- | ---------------------- |
| audacious     | Audio player        | audacious           | audacious           | audacious              | audacious           | audacious              |
| kid3-common   | Tag editor          | kid3-common         | kid3-common         | kid3-core              | kid3-cli            | kid3-core              |
| exiftool      | Metadata tool       | perl-image-exiftool | perl-Image-ExifTool | libimage-exiftool-perl | perl-Image-ExifTool | libimage-exiftool-perl |
| kdeconnect    | Mobile sync         | kdeconnect          | kdeconnect          | kdeconnect             | kdeconnect          | kdeconnect             |
| rsgain        | ReplayGain analysis | rsgain              | rsgain              | rsgain (universe)      | rsgain              | rsgain                 |
| bc            | Math library        | bc                  | bc                  | bc                     | bc                  | bc                     |
| CMake (build) | Build system        | cmake               | cmake               | cmake                  | cmake               | cmake                  |
| Qt6 (build)   | GUI framework       | qt6-base            | qt6-base-devel      | qt6-base-dev           | libqt6-devel        | qt6-base-dev           |
| KF6 (build)   | KDE libraries       | kf6-kconfig         | kf6-kconfig-devel   | kf6-kconfig-dev        | kf6-kconfig-devel   | kf6-kconfig-dev        |

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

The best way to set up MusicLib is to run the setup command in your terminal and build your music database (choice at end of setup):

```bash
musiclib-cli setup
```

Alternatively, you can make a copy of /usr/lib/musiclib/config/musiclib.conf, place it in ~/.config/musiclib/, and edit all settings directly. 

This interactive script guides you through initial MusicLib configuration. Here's what it does:

### Step 1: Detect Audacious Installation

The setup script checks for an existing Audacious installation on your system. This ensures MusicLib can properly integrate with this audio player and locate its configuration files.

### Step 2: Locate Music Repository Directories

The script scans for common music directories:

- `~/Music`
- `/mnt/music`
- Any custom directory you specify

Review the displayed results and select the top level directory for your music  library, which is one level above where all the artist subdirectories appear.

### Step 3: Set Download Directory

Configure where new music downloads should be placed, separate from where your music library is stored. This acts as a staging location to import new tracks simultaneously into the music library and the MusicLib database.

### Step 4: Detect Optional Dependencies

The setup wizard detects which optional tools are installed on your system:

- **RSGain** (`rsgain` command) — Required for the Boost Album feature
- **Kid3 GUI** (`kid3` or `kid3-qt` executable) — For integrated tag editing
- **K3b** (`k3b` command) — Required for the CD Ripping panel and Rip CD toolbar action

When K3b is found, the wizard scans your music library to determine the predominant audio format (MP3, Ogg Vorbis, or FLAC) and seeds the default rip output format accordingly. It then generates `~/.config/musiclib/k3brc` — musiclib's managed copy of K3b's configuration. If you have already configured K3b and run it before, the wizard asks whether to use your existing K3b settings as the starting point or replace them with the musiclib system defaults.

If these tools are missing, the wizard notes it in the summary. The GUI will gracefully disable features when optional tools are unavailable (with helpful tooltips explaining what's needed and how to re-run setup after installing).

### Step 5: Create XDG Directory Structure

MusicLib creates the standard Linux XDG directory structure for you:

- `~/.config/musiclib/` — Configuration files
- `~/.local/share/musiclib/data/` — Database and subdirs
- `~/.local/share/musiclib/playlists/` — Playlist files and subdirs
- `~/.local/share/musiclib/logs/` — Operation logs and subdirs

No manual folder creation needed—the script handles it all.

### Step 6: Configure Audacious Integration

If Audacious is detected, the Song Change plugin and script is configured automatically, and Audacious playlists are imported. 

### Step 7: Build Initial Database

The script offers to scan your selected music directories and build the initial `musiclib.dsv` database. This may take awhile to process, especially for large collections. For my library of 16,000 files, it took around 10 minutes.

If you say yes to building, a second prompt asks whether to **restore last-played data from ID3 tags**. Choose **yes** only if you are rebuilding an existing MusicLib library whose files already have `Songs-DB_Custom1` tags written by MusicLib — this recovers your play history. It adds one extra tag read per file and makes the build noticeably slower. For a brand-new library, or if your play history was not stored by MusicLib (other applications do not write this tag), choose **no**.

You can't really skip this. Without a database file, MusicLib will have little use. Alternatively, you can build it from the GUI. Look for `Build Library` at the top of the `Maintenance` Panel. After the build, restart the GUI and the `Library` Panel will be populated. 

---

### After Installation and Setup

#### Launch MusicLib GUI from:

- **Application menu** → Search "MusicLib"
- **Command line**: `musiclib`

#### Launch Command Line Utilities from:

- **Command line**: `musiclib-cli`
- **Script of your choice**: bash, python, etc.

---

## Quick Start

If you've just finished setup, here's how to get up and running in your first session. This walks through the three things most people want to do first: get their music into MusicLib (if not already done using setup), rate some tracks, and understand what's happening under the hood.

### Step 1: Import Your Existing Music

If your music files are already organized on disk, during setup you choose to have MusicLib scan them and build a database in one step. If you skipped that step, all you need to do is open a terminal and run:

```bash
musiclib-cli build
```

This scans your configured music directory, reads each file's tags, and creates the `musiclib.dsv` database. For large collections this can take a while — it's fine to let it run in the background.

Once it finishes, launch MusicLib (`musiclib` from the terminal, or search for it in your application menu). You should see your tracks listed in the Library View.

#### If Setup Warned You About Non-Conforming Files

During setup, MusicLib scans your library and checks two things for every audio file: that it sits at the correct depth (`MUSIC_REPO/artist/album/track.ext`), and that its filename uses only lowercase letters, digits, underscores, hyphens, and periods — no spaces, no uppercase, no accented characters. Files that fail either check are flagged as non-conforming.

If you saw a warning like this during setup:

```
⚠ WARNING: Non-conforming filenames detected in your music library.
```

you were given three choices:

- **Option 1 — Continue anyway**: Setup proceeded, but the non-conforming files may cause problems later with mobile sync and path matching. The database will still build, but those files might not sync to your phone or may disappear from search results after a rebuild.
- **Option 2 — Exit to fix filenames**: Setup exited with instructions to run `conform_musiclib.sh`. Once you've done that, re-run `musiclib-cli setup` to pick up where you left off.
- **Option 3 — Cancel setup**: Nothing was changed.

A full report listing every non-conforming file and the reason it was flagged is always saved to:

```
~/.local/share/musiclib/data/library_analysis_report.txt
```

**Fixing non-conforming files before building the database** is strongly recommended if you saw a high non-conforming count. If only a handful of files are flagged, a simpler option is to move them out of your music library to a temporary location, proceed with setup and database creation, then add them back properly using the `musiclib-cli new-tracks` utility — which will normalize their filenames and slot them into the correct directory structure automatically.

For a larger number of non-conforming files, here's the full process:

1. Make a backup of your music library — `conform_musiclib.sh` renames files in place, so a backup is your safety net.

2. Run the conformance tool in dry-run mode (the default) to preview exactly what would be renamed:
   ```bash
   ~/.local/share/musiclib/utilities/conform_musiclib.sh /path/to/your/music
   ```

3. Review the output. If the proposed renames look right, apply them:
   ```bash
   ~/.local/share/musiclib/utilities/conform_musiclib.sh --execute /path/to/your/music
   ```

4. Re-run setup:
   ```bash
   musiclib-cli setup
   ```
   Setup will re-scan the library — if all files now pass, the conformance step will clear and setup will continue to the database build prompt.

**If you already built the database with non-conforming files**, you can still fix things. Run `conform_musiclib.sh --execute` on your music directory, then rebuild:

```bash
musiclib-cli build
```

The old database is replaced on rebuild. Your ratings are safe as long as they were embedded in the audio file tags by your previous app (this is stored in the POPM frame). MusicLib will do it going forward by default whenever you rate a track — the rating lives in both the database and the file itself.

For full details on `conform_musiclib.sh` options and safety features, see the [Standalone Utilities](#standalone-utilities) section.

### Step 2: Play and Rate Some Tracks

Open MusicLib (default panel is LibraryView) and play a track in Audacious. You can search for any track in your library, right click and play/queue in Audacious, or select an Audacious playlist from the toolbar. The toolbar has an Audacious button to launch it (or activate if already open), and you will also see the track name (if playing) and a row of stars. Click a star to set the rating — it saves instantly to both the database and the audio file itself.

You can also rate tracks without playing them: find a track's entry using Library View, find the stars field, move your mouse from left to right to highlight number of stars, then click its rating directly to set.

You can also rate tracks directly from Dolphin. Open Dolphin to your music library and right-click on a track you want to rate. Look for the star symbol on the context menu. Select and bring up the sub-menu to select your chosen rating. If you have not already, right-click on any column heading in Dolphin and enable the rating column. MusicLib integrates all ratings and rating changes to Dolphin immediately, and you can view all current ratings from within Dolphin.

If you prefer keyboard shortcuts, set up `META+1` through `META+5` or similar in **KDE** to rate anything playing in Audacious without touching MusicLib's window. You can also right-click any audio file in Dolphin and choose **Rate Track** from the context menu — setup installs this automatically. See [Desktop Integration](#desktop-integration) for details.

### Step 3: Import a New Album

**IMPORTANT:** When you download/rip new music, use the **Add New Tracks** workflow rather than dropping files into your music library manually — this ensures filenames are normalized and the database stays in sync. Use only your chosen download directory from setup for staging each artist's files for the add process.

Before importing, **open the album in Kid3** to ensure the tag data for Artist and Album are correct and consistently named. NOTE: MusicLib uses the Album tag to name the destination folder in your library, so if the album already exists, it should match.

Then, in MusicLib:

1. Open the **Maintenance Panel**
2. Find the **Add New Tracks** frame
3. Enter the artist name and click **Execute**

MusicLib will normalize filenames, move the files into your music repository under `artist/album/`, and add the tracks to the database. So, if your Tag has "Pink Floyd" for artist and "Wish You Were Here" as the album, MusicLib will look for the "pink_floyd" directory and "wish_you_were_here" subdirectory, and if either or both do not exist, it will create them, convert the filenames similarly, place them in your library, and create a database entry for each track.

### What Comes Next

- **Mobile sync** — If you want music on your phone, see the [Mobile Sync](#mobile-sync) section.
- **Tag cleanup** — If your existing files have inconsistent or messy tags, see [Cleaning Tags](#cleaning-tags).
- **Keyboard shortcuts and system tray** — See [Desktop Integration](#desktop-integration) to set up system-wide shortcuts and tray access.
- **Understanding how it all works** — See [Core Concepts](#core-concepts) for a deeper explanation of the database, rating system, and playback tracking.

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
- **Custom Artist** — Sets a common name when you have variants for the same artist, useful for smart playlist variety
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

#### Rating Default Values (POPM)

POPM (Popularimeter) is the ID3v2 frame used to store ratings. The default POPM ranges below align with the star rating/POPM values and ranges used by Kid3, Windows Media Player, and Winamp:

| Stars           | POPM Range | Default write value (`POPM_STAR*`) |
| --------------- | ---------- | ---------------------------------- |
| ★ (1 star)      | 1–32       | 1                                  |
| ★★ (2 stars)    | 33–96      | 64                                 |
| ★★★ (3 stars)   | 97–160     | 128                                |
| ★★★★ (4 stars)  | 161–228    | 196                                |
| ★★★★★ (5 stars) | 229–255    | 255                                |

The exact POPM byte written to a file when you rate a track is controlled by `POPM_STAR1`–`POPM_STAR5` in `musiclib.conf`. You can override these in your user config (`~/.config/musiclib/musiclib.conf`) if you prefer different midpoint values. The POPM ranges in the table above (`RatingGroup1`–`RatingGroup5`) are used separately by the smart playlist system for eligibility logic and are not changed by overriding the write values.

**kid3 config auto-sync**: MusicLib automatically propagates your POPM star-mapping, custom TXXX frame names, and UTF-8 text encoding into the kid3 config file (`KID3_CONFIG_FILE` in `musiclib.conf`, default `~/.config/kid3/kid3rc`). This keeps the kid3 GUI aligned with your MusicLib configuration without manual reconfiguration — it runs at rating time and at install time. If you change POPM values or add custom frames in `musiclib.conf`, the kid3 config updates automatically on the next rating or after re-running `musiclib-cli setup`.

### Mobile Sync Workflow

Mobile sync is a two-phase operation:

**Phase A (Playback logging)**: When you upload a new playlist, MusicLib first processes the *previous* playlist. It calculates how long that playlist was on your phone (time between uploads) and distributes "synthetic" timestamps across the tracks using an exponential distribution. This gives you playback history even though your phone can't report what you actually listened to. It uses only the actual timestamps for those tracks that were played from your desktop in Audacious during the time between uploads.

**Phase B (Upload)**: MusicLib converts the playlist to `.m3u` format and sends it along with all the music files to your device via KDE Connect. **If you have existing tracks on the device**, remove them as space requires, before upload.

### Playback Tracking

MusicLib tracks your play history in two ways:

**Desktop (Audacious)**: The Audacious Song Change hook monitors playback and updates `LastTimePlayed` when you've listened to at least 50% of a track (with the threshold capped at a minimum of 30 seconds and a maximum of 4 minutes). This is logged with the exact timestamp.

**Mobile**: Since mobile devices can't report precise playback data, MusicLib uses the logging approach described in Phase A above to synthesize timestamps based on how long the playlist was on your device.

See the Mobile Sync section for more detail on Last-Played accounting.

---

## Using the GUI

### Main Window

The MusicLib GUI has three main areas:

1. **Library View** (default main panel) — Browse and filter your music collection
2. **Toolbar** (top) — Now Playing with star rating (click to change), Album View, Playlists, Audacious, Kid3, and Dolphin folder
3. **Side Panel** (left) — Access different features via tabs

### Library View

The library view shows all your tracks in a sortable table. You can:

- **Search** — Filter by artist, album, or title 
- **Filter** - Library-level filter rated only, unrated only, or no filter
- **Sort** — Click column headers to sort

You can select individual entries and:

- **Rate** — Click the stars to directly rate any track, playing or not
- **Play** — Context menu: play or add selected track to Audacious play queue
- **Edit** — Context menu: open the selected track in Kid3 to edit tag; if editing fields for Artist, Album, Album Artist, Title, and Genre in kid3, after saving in kid3 you can double-click on the matching MusicLib database field and directly edit the record so it matches the kid3 tag change 
- **Remove** — Context menu: Remove selected record from the database (optionally you can also remove the file)
- **Open Music Library** — Context menu: Launches/activates the associated Dolphin music folder
- **Copy Location** — Context menu: Copy the selected track's file path to the clipboard; the path is also echoed to the status bar for quick reference

### Panels

Select from the Side Panel on the left to access the other panels:

**Mobile Panel** — Upload playlists to your phone, view sync status, and manage mobile operations.

**Maintenance Panel** — Perform database and tag maintenance operations like rebuilding the database, cleaning tags, or importing new music.

**CD Ripping Panel** — Configure K3b CD ripping settings (output format, bitrate/quality, error correction) and manage the ripping profile. Only available when K3b is installed and detected by setup. See the [CD Ripping](#cd-ripping) section for details.

**Smart Playlist Panel** — Generate variety-optimized playlists using rating groups, last-played age thresholds, and artist exclusion. See the [Smart Playlist](#smart-playlist) section for details.

**Settings** — (Opens new Window) Configure MusicLib paths, device IDs, and behavior options.

### Toolbar Elements (Top)

**Now Playing** - Shows for the currently playing track:

- Artist and track name
- Star rating (click to change)

**Album View** — (Opens new Window) Show album details for currently playing track

**Playlist** — Select and activate a playlist in Audacious

**Audacious** — Launches/activates Audacious

**Kid3** — Launches/activates Kid3 for currently playing track

**Rip CD** — Launches K3b to rip a CD using MusicLib's managed rip profile. If K3b is already open, raises its window instead. Disabled when K3b is not installed (tooltip explains how to enable it). See the [CD Ripping](#cd-ripping) section for full behavior.

**Dolphin** — Launches/activates Dolphin music folder for currently playing track

### Rating Songs

Three ways to rate:

1. **In the library view**: Click the stars in the Rating column
2. **In the now-playing strip**: Click the stars at the top
3. **Keyboard shortcuts**: Set up global shortcuts in System Settings (Ctrl+0 through Ctrl+5)

Ratings appear instantly and are saved to both the database and the audio file tags.

---

## Library Management Tasks

### Importing New Music

When you download new music:

1. Open the **Maintenance Panel**
2. Find the **Add New Tracks** frame
3. Enter the artist name 
4. Setting/changing the download directory used for staging new tracks for your library is done via the Settings menu
5. Stage only one artist, one album at a time
6. Always review/edit the new track info in kid3 to ensure artist/album name consistency before proceeding
7. Click **Execute**

MusicLib will:

- Normalize the file tags
- Rename files, artist directory, album directory to lowercase with underscores
- Move files from your downloads folder to your music repository under `artist/album/`
- Add the new tracks to the database

### Rebuilding the Database

If you need to rebuild the database, it is preferred to run `musiclib-cli build` in the console. See the Command-Line Reference Section in this manual for detailed information, or run `musiclib-cli build --help` in the console. Optionally, you can:

1. Open the **Maintenance Panel**
2. Click **Build Library**
3. Optionally use **Dry Run** to preview changes
4. Click **Execute**

This scans your entire music repository and rebuilds `musiclib.dsv`. Your existing ratings are preserved where paths match. This can take a long time, particularly for large collections.

**Note**: The GUI always creates a timestamped backup of the existing database before running. When using the CLI directly, backup is opt-in via the `-b` flag.

### Cleaning Tags

Use **Clean Tags** for format-level tag repair: merging legacy ID3v1 data into ID3v2, removing APE tags, and embedding album art. It is best suited for files that have not yet been imported into the library, or when format corruption is suspected.

1. Open the **Maintenance Panel**
2. In the **Clean Tags** group, browse to a file or directory
3. Choose a mode:
   - **Merge** — Merge ID3v1 into ID3v2, remove APE tags, embed album art (default)
   - **Strip** — Remove ID3v1 and APE tags only
   - **Embed Art** — Embed `folder.jpg` as album art if art is missing from the tag
4. Set options as needed:
   - **Recursive** — Process subdirectories (checked by default)
   - **Verbose** — Show per-file detail in the output log
   - **Keep backup after success** — Retain the pre-operation backup in `TAG_BACKUP_DIR` rather than removing it automatically on success
5. Click **Execute** (or **Preview** to dry-run first)

Alternatively, open the track(s) in Kid3 and edit the tag(s) directly.

### Conforming Tags (Frame Normalization)

**Conform Tags** is the primary day-to-day tag maintenance tool. It normalizes tag frames on in-library files to the MusicLib schema, rewriting field values (artist, album, title, rating, etc.) from `musiclib.dsv`. Use it after bulk edits or whenever tag fields drift out of sync with the database. Files must already exist in `musiclib.dsv` — unregistered files are skipped.

**Quick-repair from the library view:**

1. Right-click one or more tracks in the library view
2. Select **Rebuild Tag / Tags**
3. Confirm — MusicLib rewrites the tag(s) from database-authoritative values immediately

**Full control via the Maintenance Panel:**

1. Open the **Maintenance Panel**
2. In the **Conform Tags** group, browse to a file or directory (the Browse button offers both file and directory picking)
3. Set options as needed:
   - **Recursive** — Process subdirectories
   - **Verbose** — Show per-file detail in the output log
   - **Keep backup after success** — Retain the pre-operation backup in `TAG_BACKUP_DIR`
4. Click **Preview** first to confirm scope, then **Execute**

> **Library-wide warning**: If you set the path to your library root, enable Recursive, and click Execute, MusicLib will show a confirmation dialog. It is strongly recommended to run Preview first before applying a library-wide conform. The dialog also offers a **Run Preview Instead** button as a shortcut.

**Restoring a tag backup**: If you ran a conform with **Keep backup after success** checked and want to roll back a specific file, enter that file's path in the path field and click **Restore Last Backup**. MusicLib will locate the most recent backup for that file and copy it back over the original. The backup is not deleted after restore, so you can restore again if needed.

> **Note**: Conform Tags reads from `musiclib.dsv` but never writes back to it. Running it after a manual kid3 edit would overwrite those changes with stale database values. To sync a kid3 edit into the database, use the Edit Field workflow instead.

### Tag Schema

The tag schema (`~/.config/musiclib/tag_schema.conf`, installed from `/usr/lib/musiclib/config/`) is a declarative allowlist that controls exactly which ID3v2 frames survive a tag rebuild or normalization. Every frame in an MP3 file falls into one of three tiers:

- **`[db_written]`** — Value is sourced from `musiclib.dsv` and written fresh on every rebuild. Standard fields like `Title`, `Artist`, `Album`, and `POPM` live here.
- **`[file_preserved]`** — Value is read from the file *before* the strip step and written back unchanged. MusicLib does not modify these frames. ReplayGain tags, embedded album art, and USLT lyrics fall into this tier.
- **Dropped** — Any frame not listed in either section is silently removed during rebuild. This keeps tags clean and prevents stale or unknown frames from accumulating.

Entries use either kid3 unified names (e.g., `Title`, `Artist`), explicit TXXX descriptions prefixed with `!` (e.g., `!Songs-DB_Custom1`), or raw ID3v2 frame codes prefixed with `!` (e.g., `!RVA2`).

**Customizing the schema**: To preserve a vendor TXXX frame that MusicLib would otherwise drop, add it to `[file_preserved]` in your installed copy. To add a new DB-sourced custom field, add it to `[db_written]` — it will automatically appear as a named field in the kid3 GUI after the next config auto-sync. Edit the file in `/usr/lib/musiclib/config/tag_schema.conf` and re-run `musiclib-cli setup` to redeploy, or edit `~/.config/musiclib/tag_schema.conf` directly.

### Boosting Album Loudness

To normalize loudness across an album using ReplayGain:

1. Open the **Maintenance Panel**
2. Click **Boost Album**
3. Select an album directory
4. Set target LUFS (default: -18)
5. Click **Execute**

**Note**: This requires `rsgain` to be installed. If it's not available, this feature will be disabled.

---

## Mobile Sync

### Setting Up KDE Connect

Before you can sync to mobile:

1. **Install KDE Connect App on your phone/device**:
   
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

If you have non-Audacious playlists, it is simple to import them using Audacious; then from the MusicLib Mobile Panel, you can click "Refresh from Audacious" to import them into Musiclib.

1. Create a playlist in Audacious with the tracks you want on your phone
2. Open the KDE Connect App on your desktop and mobile device and ensure they are paired
3. Open the **Mobile Panel** in MusicLib
4. Select the playlist from the dropdown
5. Select your device
6. Click **Upload**

MusicLib will:

- Process the previous playlist's last-played data (if any)
- Copy the current version of the selected playlist from Audacious to MusicLib unless you specify otherwise
- Convert the playlist to `.m3u` format. 
- Send all music files to your device
- Record the upload timestamp

### Understanding Last-Played Accounting

When you upload a *new* playlist to a mobile device, MusicLib looks at the *previous* playlist, its upload date, and asks: "How long was that on the phone?" The time between uploads becomes the "accounting window."

MusicLib then distributes synthetic timestamps across the tracks in the old playlist using an exponential distribution (tracks at the beginning get earlier timestamps, and tracks that follow them get later timestamps all within the accounting window). This gives you approximate playback history for tracks played on mobile. Playlist tracks played with Audacious from your desktop during the accounting window are logged separately. Those are not assigned synthetic timestamps. 

Log errors are normal if you move or delete associated tracks, or their database entries, during the accounting window.

### iOS Limitations

Due to Apple's restrictions:

- File access is more limited than Android
- Playback tracking has reduced precision
- Some file transfer operations may be slower

The core functionality (uploading playlists, last-played accounting) works the same, but iOS users may experience longer transfer times.

### Troubleshooting Mobile Sync

**Device not found**:

1. Ensure both devices are on the same Wi-Fi network
2. Open KDE Connect on both devices and ensure they are paired
3. Click "Refresh" in KDE Connect
4. Check your firewall isn't blocking port 1716

**Transfer fails**:

1. Ensure the phone has enough storage space
2. Check KDE Connect is running on both devices
3. Try restarting KDE Connect on the phone

**Accounting doesn't work**:

1. Make sure you upload the playlist you intended
2. Verify the previous playlist metadata files exist
3. Check the time between uploads is at least 1 hour

---

## CD Ripping

MusicLib integrates with **K3b** to manage your CD ripping workflow. When K3b is installed and detected during setup, MusicLib takes ownership of K3b's rip configuration — setting the output format, encoder settings, rip directory, and error correction mode — and deploys that profile to K3b before each session. You control everything from within MusicLib, so K3b is ready to rip the moment it opens.

**Supported output formats:** MP3, Ogg Vorbis, and FLAC.

### Setup

K3b must be installed before running `musiclib-cli setup` (or re-run setup with `--force` after installing it). 

During setup, the wizard:

1. Detects the `k3b` command and sets `K3B_INSTALLED=true` in your config.
2. Scans your music library to determine the predominant format (MP3/Ogg/FLAC) and seeds `K3B_ENCODER_FORMAT` accordingly.
3. Generates `~/.config/musiclib/k3brc` — MusicLib's managed copy of K3b's configuration. If you already have K3b settings at `~/.config/k3brc`, the wizard asks whether to use them as the starting point or replace them with the system defaults.

If K3b is not installed, the CD Ripping panel is grayed out and the Rip CD toolbar button is disabled. A tooltip on both explains what to install and how to re-run setup.

### Ripping a CD

1. Insert a CD.
2. Click **Rip CD** in the toolbar (or select it via Configure Toolbars if not visible).
3. MusicLib patches K3b's configuration with your current rip profile and launches K3b.
4. Rip and eject the disc in K3b as normal. Output lands in your configured download directory.
5. Import the ripped files into MusicLib using **Add New Tracks** in the Maintenance Panel.

If K3b is already open (launched by MusicLib or opened separately), clicking Rip CD simply raises its window — no settings are re-deployed while K3b is running.

### CD Ripping Panel

Open the CD Ripping Panel from the Side Panel tab to configure the rip profile. All changes write to your `musiclib.conf` and are immediately applied to `~/.config/musiclib/k3brc`.

**Output format** — Choose MP3, Ogg Vorbis, or FLAC. The secondary controls change depending on your selection:

- **MP3** — Choose CBR (constant bitrate: 128/192/256/320 kbps), VBR (variable quality 0–9, where 0 is best), or ABR (average bitrate in kbps).
- **Ogg Vorbis** — Quality slider 0–10 (10 is best).
- **FLAC** — No sub-controls; FLAC is always lossless.

**Error correction** — Controls `cdparanoia` behavior: Off, Overlap, Never Skip, or Full Paranoia. Higher levels are slower but handle scratched discs better.

**Sector retry count** — How many times K3b retries a failed sector read before giving up.

**Rip output directory** — Shown as a read-only label sourced from your configured download directory. Change it via Settings.

**Reset to defaults** — Removes all CD ripping overrides from your user config so the system defaults take effect immediately.

The panel is dimmed while K3b is running. It re-enables automatically when K3b closes.

### Drift Detection

If you adjust rip settings directly inside K3b (rather than via the MusicLib panel), those changes live in `~/.config/k3brc` but not in MusicLib's managed copy. When MusicLib detects this mismatch — on panel open or when K3b closes — a banner appears with two options:

- **Keep K3b changes** — Imports K3b's settings back into MusicLib so the panel reflects what K3b was using.
- **Restore MusicLib profile** — Overwrites K3b's settings with MusicLib's current profile, discarding the in-K3b changes.

Resolving drift before launching a new rip session ensures K3b always starts with the settings you intend.

---

## Desktop Integration

### System Tray

- MusicLib runs in the system tray. Hovering over it displays the track and rating info. 
- **System Tray Settings:** Go to Settings →  Advanced → GUI Behavior to set system tray behavior.

Right-click the icon for quick actions:

- **Library**— Open MusicLib with the Library Panel
- **Maintenance**— Open MusicLib with the Maintenance Panel
- **Mobile**— Open MusicLib with the Mobile Panel
- **Settings**— Open MusicLib with the Settings Window
- **Quit**— Close MusicLib, including the System Tray instance

Left-click the icon for quick actions:

- **Rate Current Track** — Quick rating menu
- **Edit in Kid3** — Edit the currently playing track's tag in Kid3
- **Copy Filepath** — Copy to clipboard currently playing filepath for console use
- **Library Record** — Open MusicLib with the Artist/Album Window for currently playing track

### Dolphin Context Menu

Right-click any audio file in Dolphin file manager:

- **Rate Track** — A submenu with five star ratings (★☆☆☆☆ through ★★★★★). Selecting one calls `musiclib-cli rate <1-5> <filepath>` directly, updating both the database and the file's embedded tag. Works on any supported audio file (MP3, FLAC, OGG, M4A, WAV) without opening MusicLib. The service menu is installed automatically during `musiclib-cli setup` to `~/.local/share/kio/servicemenus/musiclib-rate.desktop`. If it doesn't appear after setup, restart Dolphin.
- **Add to MusicLib** — Import the file(s) from your downloads folder (coming soon)
- **Edit Tags with Kid3** — Open in tag editor

### Global Shortcuts

For rating tracks, global keyboard shortcuts are configured using a two-step process.

First, using **KDE Menu Editor**, create a menu item such as `Rating 5`. In the **Program** field, enter: `/usr/bin/musiclib-cli`; in the **Command-line Arguments** field, enter: `rate 5`. Using the **Advanced** tab, you can assign keyboard shortcuts, like `META+5`. Create menu entries for each of the other ratings using different command-line arguments `rate 4`, `rate 3`, etc.

Next, under **KDE System Settings**, select **Keyboard** -> **Shortcuts** -> **Add New** -> **Application** and select the menu item for each one added from the previous step.

- `META+1` through `META+5` — Quick rate (1-5 stars)
- `META+0` — Clear rating

The shortcuts will work system-wide when Audacious is playing, without MusicLib open or focused.

### Conky Integration

MusicLib generates output files with music data and images for use with a Conky desktop panel or other panel/widget:

**Output directory**: `~/.local/share/musiclib/data/conky_output/`

**Files generated**:

- `detail.txt` — Artist or album summary (use the track's comment field in kid3 to populate the tag)
- `starrating.png` — Visual star rating image
- `artloc.txt` — Path to album art
- `folder.jpg` — Generated album art image named by MusicLib

Add the paths to your `.conkyrc` to display now-playing information on your desktop or for other display purposes.

---

## Smart Playlist

The Smart Playlist panel generates variety-optimized playlists from your library using **four variables you control**: **track rating** (POPM/stars), **days since last played (see Time Threshold by Rating)**, the size of the **rolling artist exclusion window**, and **Custom Artists** if you set them. The result is a playlist that always surfaces only the artists and tracks you haven't heard in a while, and is weighted with your preferred ratings.

### How the Algorithm Works

MusicLib divides your library into five rating groups (1★ through 5★). For each group it applies an **age threshold**: tracks played more recently than the threshold are excluded from the candidate pool. Tracks that clear the threshold are eligible; the further past the threshold a track is, the higher its **variance** score. For example, assume you set a threshold of 50 days for four-star tracks. A four-star track last played 100 days ago would have a much higher variance than one played 60 days ago, and a track played 40 days ago would ineligible for inclusion because it has not reached the 50 day threshold.

Unrated tracks are excluded from consideration. Rate tracks to include them in the pool.

Variance scores are summed per rating group and used to assign proportional weights to each. Each batch of `sample_size` tracks is drawn from the pool in proportion to those weights, so rating groups with more eligible, long-unplayed tracks contribute more slots. This lets you tune the playlist mix — for example, raising the 1★ threshold makes 1-star tracks more restrictive (fewer eligible), shifting slots toward higher-rated groups.

When an eligible track is selected for playlist entry, its artist is newly added to the rolling **exclusion window**, and the oldest artist in the window is removed. The added artist will then be ineligible for selection for 40 tracks (assuming 40 artists is the **exclusion window** size), while the oldest artist already there for 40 tracks is removed and becomes eligible again. This process guarantees the playlist order doesn't cluster around the same artist. Real variety.

### Tuning the Algorithm

Besides rating each track from zero to five stars, there are three other variables you control that determine how smart playlists will be created.

#### Time Threshold by Rating

Put simply, consider how many days on average should pass before a particular rated track can play again. Generally speaking, you would set lower-rated tracks to a higher value (more days before replay) than higher-rated tracks. Use the **Analyze** section of the Smart Playlist panel to preview how your current thresholds affect each rating group. The table shows eligible track counts, unique artist counts, variance totals, and the resulting sample weights. Adjust the age threshold spinboxes and run another preview to see the effect before generating.

**Good starting points**:
- 1★ tracks would have a long threshold (several hundred days) to keep low-rated music from overwhelming the pool.
- 5★ tracks would have a shorter threshold (30–60 days) so your favorites cycle back quickly.
- Use the **Sample breakdown** in the preview table to check that higher-rated groups hold the slots you want. It will show a breakdown of how many tracks per rating group will be chosen, given an assumed sample size of 20. You can modify the sample size, if desired.

#### Artist Exclusion Window

This setting determines how many unique artist tracks have to play before that same artist can repeat. When you run a **Preview** (see below), you can determine the right count for you after considering the number of unique artists in your library.

#### Custom Artist Field

The **exclusion window** works on not only the **Artist**, but also the **effective artist** - that is, a **Custom Artist**. Whenever you give a track a value in the **Custom Artist** column (Custom2 in the database), that value is used instead of the **Artist** for exclusion purposes.

**This matters when the same artist appears under multiple names.** For example, if you have tracks for both *Tom Petty* and *Tom Petty & The Heartbreakers* as **Artist**, the exclusion window would normally treat them as separate entries — meaning both could end up too close together in the playlist. Setting **Custom Artist** to `Petty` on all his tracks will cause them to share a single exclusion slot, so the exclusion entry of `Petty` will block both, as if the **Artist** name is identical.

To **set a Custom Artist value**, double-click the Custom Artist cell for any track in the library view. Tracks with no Custom Artist value fall back to their  Artist name automatically.

You could create custom artist groups using any scheme you like. For example, you may have 30 tracks by different artists of the same sub-genre and wish to consider them as a single artist like "Rockabilly". Create custom artists however you like.

The Analyze preview displays a **Custom Artist coverage** percentage showing what fraction of your eligible tracks have a Custom Artist value set. If coverage is low, partially-mapped artists will appear under two different effective-artist keys (e.g. `Petty` for tagged tracks and `Tom Petty` or other variant for untagged ones), and the exclusion window will track them independently. The preview will flag this if it affects your pool.

### Using the Smart Playlist Panel

**Configuration section** — Set age thresholds for each rating group, artist **exclusion window** size, and playlist size. Changes are saved immediately to both the settings store and `musiclib.conf`. Use **Reset to defaults** to restore system default values.

**Analyze section** — Click **Preview** to run a full analysis. Carefully review the results. The table shows per-group statistics including eligible track counts, unique artist counts (raw and after Custom Artist merging), and the expected sample breakdown at your current settings. Groups with fewer than 10 eligible tracks are highlighted and excluded from sampling.

**Generate section** — Enter a playlist name, optionally check **Load into Audacious after generating**, then click **Generate Playlist**. Progress is shown in the log area. On success, the `.m3u` file is written to your playlists directory and (if selected) loaded directly into Audacious. **Note:** the playlist name can be duplicated in Audacious if you never change the default name "Smart Playlist" in MusicLib. You can always rename or delete the old one in Audacious so you won't end up with duplicate playlist tabs.

### Settings Dialog — Smart Playlist Page

All threshold and generation parameters are also accessible from **Settings → Smart Playlist**, letting you adjust values without opening the panel. Changes here sync to `musiclib.conf` on Apply, so the backend scripts pick them up immediately. The Smart Playlist panel reads from the same settings store, so values stay consistent between the two locations.

### New Libraries Without Play History

If your library has no play history yet, the Smart Playlist will still generate successfully. Tracks with no play record are treated as maximally overdue — each receives the highest possible variance score — so every rated track is eligible and all are weighted equally. The playlist will be **rating-weighted but play-history-blind**: higher-rated groups will still receive more slots proportional to their size, but within each group the ordering carries no "most overdue" signal until real play history accumulates.

This is expected behavior. Run Generate normally and the playlist will improve on its own as play timestamps are written after each listening session.

---

## Command-Line Reference

MusicLib provides a full, scriptable command-line interface: `musiclib-cli`.

### Global Options

These options are handled by the `musiclib-cli` wrapper before any subcommand:

- `-h, --help` — Show help message and available commands
- `-v, --version` — Show version information
- `--config <path>` — Use alternate config file (default: `~/.config/musiclib/musiclib.conf`)

### Available Commands

| Command | Description |
|---------|-------------|
| `setup` | Interactive first-run configuration wizard |
| `build` | Full database build/rebuild from filesystem scan |
| `new-tracks` | Import new music downloads into the library and database |
| `tagclean` | Clean and normalize audio file tags |
| `tagrebuild` | Rewrite audio file tags from database values; use after database edits to sync tags to files |
| `tagrestore` | Restore audio file tags from the most recent backup created by `tagrebuild` or `tagclean` |
| `boost` | Apply ReplayGain loudness targeting to an album |
| `rate` | Set star rating (0–5) for the currently playing or specified track |
| `mobile` | Mobile sync and Audacious playlist management |
| `smart-playlist` | Analyze pool composition or generate a variety-optimized playlist |
| `process-pending` | Retry deferred operations queued during lock contention |

Full details for each command follow below. Run `musiclib-cli <command> --help` at any time for a quick reference from the terminal.

---

#### `musiclib-cli setup`

**Purpose**: Interactive first-run configuration wizard.

**Usage**:

```bash
musiclib-cli setup [--force]
```

**Options**:

- `--force` — Overwrite existing configuration

**What it does**:

- Detects Audacious installation and configures its integration
- Scans for music directories
- Creates XDG directory structure
- Detects optional dependencies (RSGain, Kid3 GUI, k3b)
- Generates configuration file
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

- When `FILEPATH` is provided: Rates that specific file
- When omitted: Rates track currently playing in Audacious

**Examples**:

```bash
# Rate a specific file four stars 
musiclib-cli rate 4 "/mnt/music/pink_floyd/dark_side/money.mp3"

# Rate track four stars currently playing in Audacious
musiclib-cli rate 4
```

**What changes**:

- Updates database (`musiclib.dsv`)
- Writes POPM tag to file
- Updates Grouping/Work tag (0-5)
- Regenerates star rating image (for desktop elements)

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
- `--restore-lastplayed` — Read `LastTimePlayed` from each file's `Songs-DB_Custom1` tag via `kid3-cli`. Use this when rebuilding an existing library to preserve play history. Omit for new libraries or when speed matters (adds one `kid3-cli` call per file).

**What it does**:

- Scans the music directory recursively for audio files
- Extracts metadata (artist, album, title, duration, etc.) from file tags via `exiftool`
- Generates a fresh database (`musiclib.dsv`) with all discovered tracks
- Sets `LastTimePlayed` to `0` for all tracks by default; with `--restore-lastplayed`, reads the value from each file's `Songs-DB_Custom1` tag instead
- Assigns new sequential track IDs and regenerates album IDs
- Indexes all tracks so that ratings can also be viewed from Dolphin file manager

**Examples**:

```bash
# Preview what would be rebuilt (safe to run anytime)
musiclib-cli build --dry-run

# Rebuild the database (new library — no play history to preserve)
musiclib-cli build

# Rebuild with backup and include restoring play history
musiclib-cli build -b --restore-lastplayed

# Write to a temp file to inspect output without touching the live database
musiclib-cli build -t

# Custom output file
musiclib-cli build /mnt/music -o ~/music_backup.dsv

# Rebuild a subdirectory for testing
musiclib-cli build /mnt/music/Rock -t
```

**Exit codes**:

- `0` — Success
- `1` — User error (invalid arguments)
- `2` — System failure (missing directory, tools unavailable, lock timeout, scan failure)

**Note**: This replaces the entire database. It takes a long time for large libraries (10,000+ tracks). Always use `--dry-run` first, and `-b` to back up before rebuilding.

---

#### `musiclib-cli new-tracks`

**Purpose**: Import new music downloads from the configured download directory into the library.

**Usage**:

```bash
musiclib-cli new-tracks [artist_name]
musiclib-cli new-tracks --help|-h|help
```

**Arguments**:

- `artist_name` — Artist name to use for folder organization (optional — prompts interactively if omitted). Normalized to lowercase with underscores.

**Options**:

- `--help, -h, help` — Display help message and exit

**What it does**:

1. Extracts any ZIP archive found in the download directory (automatic)
2. Pauses to let you edit tags in GUI (kid3, kid3-qt) — **check the Album tag**, since it determines the destination folder name
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
- `--non-interactive` — Skip interactive prompts; auto-refreshes Musiclib playlists with any newer Audacious playlists or modified versions without asking (used by the GUI)

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
- `--keep-backup` — Retain the per-file backup after a successful run (default: removed on success)
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

**Purpose**: Normalize ID3 tag frames on MP3 files to the MusicLib schema, rewriting field values (artist, album, title, rating, etc.) from the MusicLib database. Use for in-library files whose tags have drifted out of sync with `musiclib.dsv`. Files not present in the database are skipped non-fatally.

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
- `-b, --backup-dir DIR` — Custom backup directory for pre-operation copies
- `--keep-backup` — Retain the per-file backup after a successful run (default: removed on success)
- `-h, --help` — Show help message

**What it does**:

1. Looks up each track in the `musiclib.dsv` database by file path
2. Creates a timestamped binary backup of the file before making any changes
3. Strips all existing (corrupted) tags from the file
4. Rewrites tags using database-authoritative values: artist, album, title, track number, rating, etc.
5. Restores non-database fields that are preserved during the process: ReplayGain tags and embedded album art
6. On success: removes the backup automatically (default); pass `--keep-backup` to retain it in `TAG_BACKUP_DIR` (default: `~/.local/share/musiclib/data/tag_backups/`). Backups older than `MAX_BACKUP_AGE_DAYS` (default 30) are purged at the start of each run.
7. On failure: automatically restores the backup over the file, leaving it unchanged

> **Note**: `musiclib_tagrebuild.sh` reads from `musiclib.dsv` but never writes back to it. Running it after a manual kid3 edit would overwrite those changes with stale database values.

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

#### `musiclib-cli tagrestore`

**Purpose**: Restore an MP3 file's tags from the most recent backup created by `musiclib_tagrebuild.sh` or `musiclib_tagclean.sh` when either was run with `--keep-backup`.

**Usage**:

```bash
musiclib-cli tagrestore FILEPATH [options]
```

**Arguments**:

- `FILEPATH` — Path to the MP3 file whose tags should be restored (required)

**Options**:

- `-n, --dry-run` — Show what would be restored without writing anything
- `-v, --verbose` — List all available backups with modification times
- `-l, --list` — Enumerate all backups for the file and exit without restoring
- `-h, --help` — Show help message

**Exit codes**:

| Code | Meaning |
|---|---|
| 0 | Restore successful (or dry-run / list with no error) |
| 1 | No backup found, file not found, or invalid arguments |
| 2 | Backup found but restore failed (copy error or verification mismatch) |

**What it does**:

1. Resolves `TAG_BACKUP_DIR` from config (default: `~/.local/share/musiclib/data/tag_backups/`)
2. Finds all backup files matching `<basename>.backup.*` in that directory
3. Selects the most recent by lexicographic sort of the `YYYYMMDD_HHMMSS` timestamp suffix
4. Copies the backup over the original with `cp` and verifies with `cmp`
5. Leaves the backup in place after restore (so you can restore again or clean up manually)
6. Does not modify `musiclib.dsv`

**Prerequisite**: Backups only exist if `--keep-backup` was passed to a prior `tagrebuild` or `tagclean` run on the same file.

**Examples**:

```bash
# Preview what would be restored (no changes made)
musiclib-cli tagrestore "/mnt/music/pink_floyd/the_wall/01_in_the_flesh.mp3" -n

# Restore the most recent backup
musiclib-cli tagrestore "/mnt/music/pink_floyd/the_wall/01_in_the_flesh.mp3"

# List all available backups for a file
musiclib-cli tagrestore "/mnt/music/pink_floyd/the_wall/01_in_the_flesh.mp3" -l
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
- `LOUDNESS` — Target loudness level as a positive integer (required). This is the absolute value of the target in LUFS — e.g., `12` means −12 LUFS, `18` means −18 LUFS. Higher numbers = quieter result; lower numbers = louder result. Default value is `18`.

> **Note**: The CLI takes a positive integer, but most audio tools (including the MusicLib GUI) display LUFS as a negative number. Do not enter a negative value or the command will fail. To match a GUI target of −18 LUFS, pass `18` on the command line.

Both arguments are required. The script exits immediately with a usage error if either is missing.

**What it does**:

1. Removes any existing ReplayGain tags from all `.mp3` files in the directory (via `kid3-cli`)
2. Rescans the album with `rsgain` at the specified target loudness, applying album-level ReplayGain tags

**Examples**:

```bash
# Target -12 LUFS (louder)
musiclib-cli boost /mnt/music/pink_floyd/the_wall 12

# Target -19 LUFS (slightly quieter)
musiclib-cli boost /mnt/music/radiohead/ok_computer 19
```

**Note**: Requires both `rsgain` and `kid3-cli` to be installed. Only processes `.mp3` files directly inside `ALBUM_DIR` (not recursive).

---

#### `musiclib-cli smart-playlist`

**Purpose**: Analyze the candidate pool or generate a variety-optimized playlist from your library.

**Usage**:

```bash
musiclib-cli smart-playlist analyze [options]
musiclib-cli smart-playlist generate [options]
```

##### `smart-playlist analyze`

Reads `musiclib.dsv`, applies per-group POPM rating filters and last-played age thresholds, and reports pool statistics. Use this to tune thresholds before generating. All output is JSON to stdout.

**Options**:

- `-m counts|preview|file` — Output mode (default: `preview`)
  - `counts` — Fast path: per-group eligible track and unique artist counts only
  - `preview` — Full analysis with variance totals, sample weights, and per-group breakdown
  - `file` — Write variance-annotated pool to `~/.local/share/musiclib/data/sp_pool.csv`
- `-g G1,G2,G3,G4,G5` — Comma-separated age thresholds in days per rating group (1★–5★)
- `-s <n>` — Sample size used in per-group breakdown. Default: from `SP_SAMPLE_SIZE` in config.
- `-u L1,L2,L3,L4,L5` — POPM low bounds per rating group. Default: from `RatingGroup1-5` in config.
- `-v H1,H2,H3,H4,H5` — POPM high bounds per rating group. Default: from `RatingGroup1-5` in config.

**Examples**:

```bash
# Full preview with current config defaults
musiclib-cli smart-playlist analyze

# Quick count check to see how many tracks are eligible
musiclib-cli smart-playlist analyze -m counts

# Preview with custom age thresholds
musiclib-cli smart-playlist analyze -g 720,360,180,90,45
```

##### `smart-playlist generate`

Generates a variety-optimized M3U playlist. Delegates pool building to the analyze script, then runs the variance-proportional selection loop with a rolling artist-exclusion window.

**Options**:

- `-n <name>` — Playlist name without `.m3u` extension. Default: `Smart Playlist`.
- `-o <file>` — Full output file path (overrides `-n` and default playlists directory).
- `-p <n>` — Target playlist size. Default: from `SP_PLAYLIST_SIZE` in config.
- `-s <n>` — Sample size per selection round. Default: from `SP_SAMPLE_SIZE` in config.
- `-e <n>` — Recent unique effective artists to exclude per round. Default: from `SP_ARTIST_EXCLUSION_COUNT` in config.
- `-g G1,G2,G3,G4,G5` — Age thresholds in days per rating group.
- `-u L1,L2,L3,L4,L5` — POPM low bounds per rating group.
- `-v H1,H2,H3,H4,H5` — POPM high bounds per rating group.
- `--load-audacious` — Load the generated playlist into Audacious after writing. Audacious must be running.

**Examples**:

```bash
# Generate a default playlist using all config settings
musiclib-cli smart-playlist generate

# Generate and load directly into Audacious
musiclib-cli smart-playlist generate --load-audacious

# 100-track playlist with a custom name and tighter age thresholds
musiclib-cli smart-playlist generate -p 100 -n "Evening Mix" -g 180,90,45,30,14

# Write to a specific output path
musiclib-cli smart-playlist generate -o ~/Music/saturday.m3u
```

**Notes**:

- All threshold and size defaults come from `musiclib.conf` (`SP_AGE_GROUP*`, `SP_PLAYLIST_SIZE`, `SP_SAMPLE_SIZE`, `SP_ARTIST_EXCLUSION_COUNT`, `RatingGroup1-5`). Adjust them in **Settings → Smart Playlist** or directly in the config file.
- The artist exclusion window uses the **Custom Artist** field (`Custom2`) as the effective artist identity when it is set, falling back to `AlbumArtist`. See the [Smart Playlist](#smart-playlist) section for details on setting Custom Artist values.
- The command-line flags override config values for the current run only; they do not persist to `musiclib.conf`.

---

#### `musiclib-cli remove-record`

**Purpose**: Remove a track's database record (includes a flag to also delete the file).

**Usage**:

```bash
musiclib-cli remove-record FILEPATH [options]
```

**Parameters**:

- `FILEPATH` — Absolute path to audio file

**Options**:

- `--help` — Display this help
- `--delete-file` - also removes the audio file at FILEPATH 

**What it does**:
Removes the database row for the specified file. The audio file itself is not deleted from disk unless the delete-file parameter is used.

**Examples**:

```bash
# Remove a track's database record
musiclib-cli remove-record "/mnt/music/deleted/old_track.mp3"
# Remove a track's database record and underlying audio file
musiclib-cli remove-record "/mnt/music/deleted/old_track.mp3" --delete-file
```

---

#### `musiclib-cli --help`

**Purpose**: Display help information.

**Usage**:

```bash
musiclib-cli --help
musiclib-cli <command> --help
```

---

#### `musiclib-cli --version`

**Purpose**: Display version information.

**Usage**:

```bash
musiclib-cli --version
```

---

## Standalone Utilities

MusicLib includes standalone utility scripts that operate outside the normal command-line interface. These tools are for specific pre-setup or maintenance scenarios.

### conform_musiclib.sh — Filename Conformance Tool

**Location**: `/usr/lib/musiclib/bin/conform_musiclib.sh`

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
/usr/lib/musiclib/bin/conform_musiclib.sh /path/to/music

# Actually rename files
/usr/lib/musiclib/bin/conform_musiclib.sh --execute /path/to/music

# Verbose output
/usr/lib/musiclib/bin/conform_musiclib.sh --verbose /path/to/music

# Combined: verbose execute
/usr/lib/musiclib/bin/conform_musiclib.sh --verbose --execute /path/to/music
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
A: Yes! MusicLib works with both. See the "Mobile Sync" section for setup.

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
2. Check Song Change plugin is enabled: Services → Plugins in Audacious
3. Verify hook script path: `/usr/lib/musiclib/bin/musiclib_audacious.sh`
4. Test manually: `musiclib-cli audacious`

**Conky not updating**

1. Check Conky output directory exists: `ls ~/.local/share/musiclib/data/conky_output/`
2. Verify Audacious hook is configured (see Services → Plugins → SongChange → Settings in Audacious)
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
2. Restore backup. `cd ~/.local/share/musiclib/data` then `cp musiclib.dsv.backup.YYYYMMDD_HHMMSS musiclib.dsv`
3. If no backup: `musiclib-cli build` to rebuild from filesystem
4. Always make manual backups: `cp musiclib.dsv musiclib.dsv.manual.backup`

**Lock timeout errors**

- Wait a few seconds and try again
- Check if another MusicLib process is running: `ps aux | grep musiclib`
- Kill stuck processes: `pkill -f musiclib`
- Check database lock file: `ls ~/.local/share/musiclib/data/musiclib.dsv.lock`

**Rip CD button is disabled**

1. Verify K3b is installed: `which k3b`
2. If not installed, install it (see Installation section) then re-run `musiclib-cli setup`
3. Confirm `K3B_INSTALLED=true` is in your config: `grep K3B_INSTALLED ~/.config/musiclib/musiclib.conf`

**CD Ripping panel shows "K3b is not installed"**

Re-run setup after installing K3b: `musiclib-cli setup --force` (your existing config settings are preserved where possible).

**K3b opens with wrong rip settings**

MusicLib deploys its managed profile to `~/.config/k3brc` before each launch. If K3b shows unexpected settings on first open, close K3b, then check the CD Ripping panel for a drift banner. Use "Restore MusicLib profile" to push MusicLib's settings back to K3b, then try again.

**CD Ripping panel shows drift banner**

Settings were changed in K3b directly. Use **Keep K3b changes** to import them into MusicLib, or **Restore MusicLib profile** to discard the K3b changes and re-apply MusicLib's profile.

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

### Use Global Shortcuts

Set up keyboard shortcuts for:

- `Ctrl+M` — Open MusicLib window
- `Ctrl+1` through `Ctrl+5` — Quick rate (1-5 stars)
- `Ctrl+0` — Clear rating

This speeds up workflow without opening windows.

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
    musiclib-cli new-tracks "$artist" 
done
```

---

## Glossary

- **Audacious** — The music player MusicLib controls
- **DSV** — Delimiter Separated Values (the text format of the database)
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

## Future Features (Planned)

MusicLib is actively being developed. Here are features planned for future releases:

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
- **Man Pages**: `man musiclib`, `man musiclib-cli`
- **Online**: Visit the MusicLib GitHub wiki

### Reporting Issues

If you find a bug:

1. **Check the logs**: `~/.local/share/musiclib/logs/musiclib.log`
2. **Reproduce the issue**: Try to make it happen again
3. **Report on GitHub**: Include:
   - Steps to reproduce
   - Your MusicLib version (`musiclib --version`)
   - Your KDE Plasma version
   - Any error messages from logs

---

**Questions? Suggestions? Version History? Visit the MusicLib project on GitHub or post in the Arch Linux forums.**

Happy listening! 🎵
