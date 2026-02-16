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
