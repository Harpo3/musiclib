# MusicLib

**A KDE-native music library control plane for Arch Linux power users.**

MusicLib orchestrates Audacious, kid3-cli, rsgain, exiftool, and KDE Connect into a cohesive system for music library management, ratings, mobile sync, and desktop telemetry via Conky.

---

## Architecture

MusicLib uses a hybrid architecture:
- **Shell script backend** (`/usr/lib/musiclib/bin/`) — authoritative for all write operations
- **Qt/KDE GUI** (`musiclib-qt`) — smart client for library browsing, rating, maintenance
- **C++ CLI dispatcher** (`musiclib-cli`) — thin wrapper for command-line access
- **Flat-file database** (`musiclib.dsv`) — ^-delimited, human-readable, easily backed up

```
User Interfaces (GUI/CLI) → Shell Scripts → External Tools (kid3-cli, audtool, etc.)
                                          ↓
                                    musiclib.dsv + File Tags
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed component diagrams.

---

## Installation

### AUR Packages (Recommended)

```bash
# Install backend + CLI
yay -S musiclib

# Install GUI (depends on musiclib)
yay -S musiclib-qt
```

### Manual Build

**Dependencies**:
- Qt 6.5+, KDE Frameworks 6 (KConfig, KNotifications, KIO, KGlobalAccel, KXmlGui)
- kid3-cli, exiftool, rsgain, audacious, kdeconnect-cli, bc
- CMake 3.20+, GCC 11+ or Clang 14+

**Build**:
```bash
git clone https://github.com/yourusername/musiclib.git
cd musiclib
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make
sudo make install
```

---

## Quick Start

### First-Run Setup

**GUI**: Launch `musiclib-qt` and follow the setup wizard:
1. Set music directory (`/mnt/music/` or `~/Music/`)
2. Scan library to create initial database
3. (Optional) Detect KDE Connect device for mobile sync
4. Configure Conky output directory

**CLI**: Edit `~/.config/musiclib/musiclib.conf` manually, then run:
```bash
musiclib-cli rebuild
```

---

## Usage

### GUI Interface

**Launch**: `musiclib-qt` or via application menu (MusicLib)

**Features**:
- **Library View**: Browse, filter, sort tracks; inline star rating
- **Maintenance Panel**: Rebuild DB, clean tags, boost loudness, scan playlists
- **Mobile Panel**: Upload playlists to Android via KDE Connect
- **Conky Panel**: Preview Conky config, view generated assets
- **Settings**: Configure paths, device ID, global shortcuts
- **System Tray**: Quick-rate current track (0–5 stars), open to maintenance

**Global Shortcuts** (configurable in Settings):
- `Meta+1` through `Meta+5`: Rate current track
- `Meta+0`: Clear rating

---

### CLI Interface

**Subcommands**:

```bash
# Rate a track (0–5 stars)
musiclib-cli rate "/path/to/song.mp3" 4

# Upload playlist to Android device
musiclib-cli mobile upload abc123def456 "/path/to/playlist.audpl"

# Show mobile sync status
musiclib-cli mobile status

# Rebuild database from filesystem
musiclib-cli rebuild

# Clean tags (merge ID3v1→v2, remove APE)
musiclib-cli tagclean "/mnt/music/Artist/Album/" --mode merge

# Rebuild corrupted tags from database
musiclib-cli tagrebuild "/path/to/corrupted.mp3"

# Apply ReplayGain loudness targeting
musiclib-cli boost "/mnt/music/Artist/Album/" --target -16

# Scan playlists and generate cross-reference CSV
musiclib-cli scan > playlist_report.csv

# Import new track(s)
musiclib-cli add-track "/tmp/new_album.zip" --auto-rate 3
```

**Help**:
```bash
musiclib-cli --help
musiclib-cli rate --help
```

---

## Configuration

**Location**: `~/.config/musiclib/musiclib.conf`

**Key Variables**:
```bash
MUSICDB="~/.local/share/musiclib/data/musiclib.dsv"
MUSIC_REPO="/mnt/music"
CONKY_OUTPUT_DIR="~/.local/share/musiclib/data/conky_output"
DEVICE_ID="abc123def456"  # KDE Connect device (from kdeconnect-cli -l)
DEFAULT_RATING=3
LOCK_TIMEOUT=5
```

**Audacious Hook** (for Conky updates):
1. Open Audacious → Preferences → Plugins → Song Change
2. Command: `/usr/lib/musiclib/bin/musiclib_audacious.sh`

**Conky Integration**:
- Point Conky config to `~/.local/share/musiclib/data/conky_output/`
- Example: `${cat ~/.local/share/musiclib/data/conky_output/artist.txt}`
- See `conky_example.conf` in `/usr/share/musiclib/`

---

## Data Layout

**User Data** (XDG conventions):
```
~/.config/musiclib/
  musiclib.conf

~/.local/share/musiclib/
  data/
    musiclib.dsv                    # Main database
    conky_output/                   # Conky text files + images
    tag_backups/                    # Tag backups before operations
  playlists/
    *.audpl                         # Audacious playlists
    mobile/
      *.tracks, *.meta              # Mobile sync metadata
  logs/
    musiclib.log                    # Main operation log
    audacious/audacioushist.log     # Playback history
    mobile/                         # Mobile upload logs
```

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| "Database lock timeout" error | Another MusicLib process is writing. Wait 5 seconds or `pkill -f musiclib`. |
| Conky not updating | Verify Audacious song-change hook is configured (see Configuration). |
| Mobile upload fails | Check device connection: `kdeconnect-cli -l`. Ensure device is paired and reachable. |
| Tag write fails | Check file permissions: `chmod 644 /path/to/file.mp3`. |
| Rating not appearing in Audacious | MusicLib writes to file tags and DB; Audacious may cache tags. Restart Audacious or reload library. |

### Logs

- Main log: `~/.local/share/musiclib/logs/musiclib.log`
- Playback history: `~/.local/share/musiclib/logs/audacious/audacioushist.log`
- Mobile uploads: `~/.local/share/musiclib/logs/mobile/upload_YYYYMMDD.log`

### Database Corruption

If `musiclib.dsv` becomes corrupted:
```bash
# Restore from automatic backup
cp ~/.local/share/musiclib/data/musiclib.dsv.backup.YYYYMMDD_HHMMSS \
   ~/.local/share/musiclib/data/musiclib.dsv

# Or rebuild from filesystem (preserves ratings where possible)
musiclib-cli rebuild
```

---

## Development

See [DEVELOPMENT.md](docs/DEVELOPMENT.md) for:
- Build instructions
- Code style guidelines
- Testing (unit, integration, smoke tests)
- Contribution workflow

---

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — Component diagrams, data flow, technology stack
- [Backend API](docs/BACKEND_API.md) — Script invocation reference, exit codes, JSON errors
- [Project Plan](docs/PROJECT_PLAN.md) — Roadmap, phased execution, milestones
- [User Guide](docs/USER_GUIDE.md) — Screenshots, walkthroughs
- [Glossary](docs/GLOSSARY.md) — Conky, POPM, audtool, KDE Connect, DSV, flock

---

## License

GPLv3 or later (to be determined)

---

## Contributing

Contributions welcome! Please open an issue before submitting large PRs.

**Areas needing help**:
- KRunner plugin implementation
- Plasma widget (QML)
- Additional playlist format support (.xspf, .cue)
- Translations (German, French, Spanish)

---

## Acknowledgments

- KDE Community for Frameworks and Plasma
- Audacious developers for `audtool`
- kid3 developers for `kid3-cli`
- ExifTool author Phil Harvey
- rsgain developers for ReplayGain tools
- KDE Connect team for mobile integration
