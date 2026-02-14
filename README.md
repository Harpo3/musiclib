# MusicLib

Personal music library management system with desktop and mobile playback tracking.

## Directory Structure

- **bin/**: Scripts and executables
- **config/**: Configuration files
- **data/**: Database and backups
- **playlists/**: Playlist files and mobile tracking metadata
- **logs/**: Operation logs

## Configuration

Edit `config/musiclib.conf` to customize:
- Database location
- Android device ID
- Default values
- Paths

## Scripts

- `musiclib_add.sh`: Add tracks to database
- `musiclib_mobile.sh`: Mobile playlist management
- `musiclib_utils.sh`: Shared utility functions
- `musiclib_validate.sh`: Database integrity checks

## Usage

Source the configuration in your scripts:
```bash
source "$HOME/musiclib/config/musiclib.conf"
```

Or add to your shell profile for command-line access:
```bash
export MUSICLIB_ROOT="$HOME/musiclib"
export PATH="$MUSICLIB_ROOT/bin:$PATH"
```

## Migration Notes

Original locations:
- Database: `~/.musiclib.dsv`
- Playlists: `/home/lpc123/Documents/playlists`
- Scripts: `/home/lpc123/scripts`

After migration, you may want to update any external scripts or aliases
that reference the old locations.
