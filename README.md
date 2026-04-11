# MusicLib

**KDE-native or console-based music library control for Linux users.**

MusicLib orchestrates Audacious, kid3-cli, rsgain, exiftool, k3b, and KDE Connect into a cohesive system for music library management, ratings, mobile sync, CD Ripping, and data elements for desktop use (like conky).

See [MUSICLIB_USER_MANUAL.md](docs/MUSICLIB_USER_MANUAL.md) or the Github wiki for detailed features and information.

---

## Architecture

MusicLib uses a hybrid architecture:
- **Shell script backend** (`/usr/lib/musiclib/bin/`) – authoritative for all write operations
- **Qt/KDE GUI** (`musiclib`) – smart client for library browsing, rating, maintenance
- **C++ CLI dispatcher** (`musiclib-cli`) – thin wrapper for command-line access
- **Flat-file database** (`musiclib.dsv`) – ^-delimited, human-readable, easily backed up

```
User Interfaces (GUI/CLI) → Shell Scripts → External Tools (kid3-cli, audtool, etc.)
                                          ↓
                                    musiclib.dsv + File Tags
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed component diagrams.

---

## Installation

### AUR Packages 

- musiclib (KDE GUI)
- musiclib-cli (console only)


### Manual Build

**Dependencies**:
- Qt 6.5+, KDE Frameworks 6 (KConfig, KNotifications, KIO, KGlobalAccel, KXmlGui)
- kid3-common, exiftool, audacious, kdeconnect-cli, bc
- CMake 3.20+, GCC 11+ or Clang 14+

**Optional and recommended**:
rsgain, kid3 (KDE) or kid3-qt

**Build**:
```bash
git clone https://github.com/Harpo3/musiclib.git
cd musiclib
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/usr
make
sudo make install
```

---

## Quick Start

### REQUIRED: First-Run Setup - both GUI and CLI versions

**Console**:
```bash
musiclib-cli setup  # This command also completes setup for the GUI version.
```
The setup wizard detects your system (Audacious, music directories, KDE Connect, Kid3, K3b, and rsgain), creates the local configuration file, configures Audacious integration, and prompts to build the library database if one is not detected. Can be re-run. 

---

## License

GPLv3 or later 

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
- KDE K3b team for CD Ripping
