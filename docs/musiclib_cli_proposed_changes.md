# MusicLib-CLI Dispatcher: Proposed Implementation Changes

**Document Purpose**: Detailed implementation guidance for dispatcher enhancements and script updates.

**Status**: Ready for implementation

---

## Change 1: Database Build – User Prompt for Existing DB

### Issue
When user runs `musiclib-cli build` with an existing `musiclib.dsv`, the operation silently overwrites it (or errors if locked), risking data loss.

### Solution
Add interactive prompt when existing database is detected, giving user four options.

### Implementation Flow

```
User runs: musiclib-cli build /mnt/music/music

Dispatcher checks: Does musiclib.dsv already exist?
  ├─ If NO → proceed with build
  └─ If YES → prompt user:

    ╔═════════════════════════════════════════╗
    ║  Existing database found:               ║
    ║  ~/.local/share/musiclib/data/          ║
    ║  musiclib.dsv (2,847 tracks)            ║
    ║                                         ║
    ║  What would you like to do?             ║
    ║                                         ║
    ║  [1] Overwrite existing DB              ║
    ║  [2] Rename existing DB to .backup      ║
    ║  [3] Save as alternate file             ║
    ║  [4] Cancel (no changes made)           ║
    ║                                         ║
    ║  Choice (1-4): _                        ║
    ╚═════════════════════════════════════════╝
```

### Dispatcher Implementation (C++)

```cpp
// In musiclib-cli main dispatcher

int handleBuildCommand(const QStringList& args) {
    QString targetDir = args.isEmpty() ? 
        configValue("MUSIC_REPO") : args.at(0);
    
    QStringList scriptArgs = {targetDir};
    
    // Add remaining args (--dry-run, -b, etc.)
    for (int i = 1; i < args.size(); ++i) {
        scriptArgs << args.at(i);
    }
    
    // Check if database exists
    QString dbPath = configValue("MUSICDB");
    if (QFile::exists(dbPath)) {
        int trackCount = getTrackCountFromDB(dbPath);
        
        // Prompt user
        int choice = promptUserForDBAction(dbPath, trackCount);
        
        if (choice == 1) {
            // Overwrite - proceed as normal
        } else if (choice == 2) {
            // Rename to .backup.TIMESTAMP
            QString timestamp = QDateTime::currentDateTime()
                .toString("yyyyMMdd_hhmmss");
            QString backupPath = dbPath + ".backup." + timestamp;
            QFile::rename(dbPath, backupPath);
            std::cerr << "Previous database saved to: " 
                      << backupPath.toStdString() << std::endl;
        } else if (choice == 3) {
            // Alternate file location
            QString newPath = promptUserForNewDBPath();
            scriptArgs << "-o" << newPath;
        } else {
            // Cancel
            std::cerr << "Build cancelled. No changes made." << std::endl;
            return 1;
        }
    }
    
    return executeScript("/usr/lib/musiclib/bin/musiclib_build.sh", 
                         scriptArgs);
}

int promptUserForDBAction(const QString& dbPath, int trackCount) {
    std::cerr << "Existing database found: " << dbPath.toStdString() 
              << " (" << trackCount << " tracks)" << std::endl;
    std::cerr << std::endl;
    std::cerr << "1) Overwrite existing DB" << std::endl;
    std::cerr << "2) Rename existing to .backup.TIMESTAMP" << std::endl;
    std::cerr << "3) Save as alternate file" << std::endl;
    std::cerr << "4) Cancel" << std::endl;
    std::cerr << "Choice (1-4): ";
    std::cerr.flush();
    
    std::string input;
    std::getline(std::cin, input);
    
    try {
        int choice = std::stoi(input);
        if (choice >= 1 && choice <= 4) {
            return choice;
        }
    } catch (...) {}
    
    std::cerr << "Invalid choice." << std::endl;
    return 4;  // Default to cancel
}

QString promptUserForNewDBPath() {
    std::cerr << "Enter new database filename: ";
    std::cerr.flush();
    
    std::string input;
    std::getline(std::cin, input);
    
    QString newPath = QString::fromStdString(input);
    
    // If relative path, prepend home directory
    if (!newPath.startsWith("/")) {
        newPath = QDir::homePath() + "/" + newPath;
    }
    
    return newPath;
}
```

### GUI Implementation (musiclib-qt)

```cpp
// In musiclib-qt main window

void MainWindow::onBuildDatabase() {
    QString targetDir = getSelectedDirectory();
    if (targetDir.isEmpty()) return;
    
    QString dbPath = configValue("MUSICDB");
    
    if (QFile::exists(dbPath)) {
        int trackCount = getTrackCountFromDB(dbPath);
        
        QMessageBox::StandardButton reply = QMessageBox::question(
            this,
            "Existing Database Found",
            QString("Found existing musiclib.dsv with %1 tracks.\n\n"
                    "What would you like to do?")
                .arg(trackCount),
            QMessageBox::StandardButtons(
                QMessageBox::Yes |      // Overwrite
                QMessageBox::Discard |  // Rename to .backup
                QMessageBox::Save |     // Alternate file
                QMessageBox::Cancel
            )
        );
        
        QString scriptArg = targetDir;
        
        switch(reply) {
            case QMessageBox::Yes:
                // Overwrite - proceed
                break;
                
            case QMessageBox::Discard: {
                // Rename to .backup.TIMESTAMP
                QString timestamp = QDateTime::currentDateTime()
                    .toString("yyyyMMdd_hhmmss");
                QString backupPath = dbPath + ".backup." + timestamp;
                QFile::rename(dbPath, backupPath);
                statusBar()->showMessage(
                    QString("Previous database saved to: %1").arg(backupPath)
                );
                break;
            }
            
            case QMessageBox::Save: {
                // File dialog for alternate location
                QString newPath = QFileDialog::getSaveFileName(
                    this, 
                    "Save Database As", 
                    QDir::homePath(), 
                    "Database Files (*.dsv)"
                );
                if (newPath.isEmpty()) return;
                scriptArg = targetDir;
                // Add -o option to script call
                QStringList args;
                args << targetDir << "-o" << newPath;
                executeScript("build", args);
                return;
            }
            
            case QMessageBox::Cancel:
                statusBar()->showMessage("Build cancelled.");
                return;
                
            default:
                return;
        }
    }
    
    // Execute build script
    executeScript("build", QStringList() << targetDir);
}
```

---

## Change 2: New Track Import – Configurable Download Directory

### Issue
Download directory is hardcoded to `$HOME/Downloads/newmusic` in config. Users may need different locations.

### Solution
Add configuration entries for primary and alternate download directories, with CLI override and GUI file dialog support.

### Configuration Changes (musiclib.conf)

```bash
#############################################
# NEW TRACK IMPORT
#############################################

# Primary download directory for new tracks
# Can be overridden per import via GUI file dialog or --source flag
NEW_DOWNLOAD_DIR="$HOME/Downloads/newmusic"

# Alternative download locations (for quick switching)
# Set to empty string to disable
ALTERNATE_DOWNLOAD_DIR_1=""
ALTERNATE_DOWNLOAD_DIR_2=""
ALTERNATE_DOWNLOAD_DIR_3=""

# Example configuration:
# NEW_DOWNLOAD_DIR="$HOME/Downloads/newmusic"
# ALTERNATE_DOWNLOAD_DIR_1="/mnt/external/new_music"
# ALTERNATE_DOWNLOAD_DIR_2="/nas/music_uploads"
# ALTERNATE_DOWNLOAD_DIR_3="$HOME/music/incoming"
```

### Script Changes (musiclib_new_tracks.sh)

Add command-line parameter handling:

```bash
#############################################
# Parse Command Line Arguments
#############################################

ARTIST_NAME=""
SOURCE_DIR=""
NO_LOUDNESS=false
NO_ART=false
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --source-dialog)
            # Show interactive file dialog using zenity or kdialog
            if command -v kdialog &>/dev/null; then
                SOURCE_DIR=$(kdialog --getexistingdirectory \
                    "$NEW_DOWNLOAD_DIR" \
                    --title "Select Download Directory")
            elif command -v zenity &>/dev/null; then
                SOURCE_DIR=$(zenity --file-selection --directory \
                    --title="Select Download Directory" \
                    --filename="$NEW_DOWNLOAD_DIR")
            else
                error_exit 2 "No dialog tool available" \
                    "tools" "kdialog or zenity"
                exit 2
            fi
            [ -z "$SOURCE_DIR" ] && exit 1
            shift
            ;;
        --no-loudness)
            NO_LOUDNESS=true
            shift
            ;;
        --no-art)
            NO_ART=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            # First positional arg is artist name
            ARTIST_NAME="$1"
            shift
            ;;
    esac
done

# Default to config value if not specified
SOURCE_DIR="${SOURCE_DIR:-$NEW_DOWNLOAD_DIR}"

# Validate source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    error_exit 1 "Source directory not found" "directory" "$SOURCE_DIR"
    exit 1
fi

# Rest of import process...
```

### CLI Usage Examples

```bash
# Use default from config
musiclib-cli new-tracks "radiohead"

# Override with specific directory
musiclib-cli new-tracks "radiohead" --source /mnt/external/new_music

# Use interactive file dialog
musiclib-cli new-tracks "radiohead" --source-dialog

# Combine with other options
musiclib-cli new-tracks "radiohead" --source /mnt/external/new_music -v --dry-run
```

### GUI Implementation (musiclib-qt)

```cpp
// In musiclib-qt new track import dialog

void MainWindow::onNewTrackImport() {
    QDialog dialog(this);
    dialog.setWindowTitle("New Track Import");
    
    QVBoxLayout layout(&dialog);
    
    // Artist name input
    QHBoxLayout artistLayout;
    artistLayout.addWidget(new QLabel("Artist:"));
    QLineEdit artistInput;
    artistLayout.addWidget(&artistInput);
    layout.addLayout(&artistLayout);
    
    // Source directory selection
    QGroupBox sourceGroup("Source Directory");
    QVBoxLayout sourceLayout;
    
    // Primary option with browse button
    QHBoxLayout primaryLayout;
    primaryLayout.addWidget(new QLabel("Location:"));
    QLineEdit sourceInput;
    sourceInput.setText(configValue("NEW_DOWNLOAD_DIR"));
    primaryLayout.addWidget(&sourceInput);
    QPushButton browseBtn("Browse...");
    primaryLayout.addWidget(&browseBtn);
    sourceLayout.addLayout(&primaryLayout);
    
    // Connect browse button
    connect(&browseBtn, &QPushButton::clicked, [&]() {
        QString dir = QFileDialog::getExistingDirectory(
            this, "Select Download Directory",
            sourceInput.text()
        );
        if (!dir.isEmpty()) {
            sourceInput.setText(dir);
        }
    });
    
    // Alternate locations (radio buttons)
    QStringList alternates = {
        configValue("ALTERNATE_DOWNLOAD_DIR_1"),
        configValue("ALTERNATE_DOWNLOAD_DIR_2"),
        configValue("ALTERNATE_DOWNLOAD_DIR_3")
    };
    
    for (const auto& alt : alternates) {
        if (!alt.isEmpty()) {
            QRadioButton* btn = new QRadioButton(alt);
            sourceLayout.addWidget(btn);
            connect(btn, &QRadioButton::toggled, [&, alt](bool checked) {
                if (checked) sourceInput.setText(alt);
            });
        }
    }
    
    sourceGroup.setLayout(&sourceLayout);
    layout.addWidget(&sourceGroup);
    
    // Import options
    QGroupBox optionsGroup("Options");
    QVBoxLayout optionsLayout;
    
    QCheckBox replaygainCheck("Apply ReplayGain normalization");
    replaygainCheck.setChecked(true);
    optionsLayout.addWidget(&replaygainCheck);
    
    QCheckBox artCheck("Extract album art");
    artCheck.setChecked(true);
    optionsLayout.addWidget(&artCheck);
    
    QCheckBox dryrunCheck("Dry-run (preview only)");
    optionsLayout.addWidget(&dryrunCheck);
    
    QCheckBox verboseCheck("Verbose output");
    optionsLayout.addWidget(&verboseCheck);
    
    optionsGroup.setLayout(&optionsLayout);
    layout.addWidget(&optionsGroup);
    
    // Buttons
    QHBoxLayout buttonLayout;
    QPushButton importBtn("Import");
    QPushButton cancelBtn("Cancel");
    buttonLayout.addStretch();
    buttonLayout.addWidget(&importBtn);
    buttonLayout.addWidget(&cancelBtn);
    layout.addLayout(&buttonLayout);
    
    connect(&importBtn, &QPushButton::clicked, [&]() {
        QStringList args;
        args << artistInput.text();
        args << "--source" << sourceInput.text();
        if (!replaygainCheck.isChecked()) args << "--no-loudness";
        if (!artCheck.isChecked()) args << "--no-art";
        if (dryrunCheck.isChecked()) args << "--dry-run";
        if (verboseCheck.isChecked()) args << "-v";
        
        executeScript("new-tracks", args);
        dialog.accept();
    });
    
    connect(&cancelBtn, &QPushButton::clicked, &dialog, &QDialog::reject);
    
    dialog.exec();
}
```

---

## Change 3: File Path Normalization

### Issue
Users may pass file paths with spaces or mixed case. Scripts need consistent lowercase, underscore-separated paths.

### Solution
Add `normalize_filepath()` utility function to dispatcher and scripts.

### Dispatcher Implementation (C++)

```cpp
// Helper function in musiclib-cli

QString normalizePath(const QString& path) {
    QString normalized = path.toLower();
    
    // Replace spaces with underscores
    normalized.replace(" ", "_");
    
    // Remove special characters except -._/
    normalized = normalized.replace(
        QRegularExpression("[^a-z0-9._\\/-]"), "_"
    );
    
    // Collapse multiple underscores
    normalized = normalized.replace(
        QRegularExpression("_+"), "_"
    );
    
    // Remove trailing underscores
    normalized = normalized.replace(QRegularExpression("_+$"), "");
    
    return normalized;
}

// Usage in rate command
if (command == "rate") {
    QString filepath = normalizePath(args.at(0));
    int rating = args.at(1).toInt();
    
    QStringList scriptArgs;
    scriptArgs << filepath << QString::number(rating);
    
    return executeScript("musiclib_rate.sh", scriptArgs);
}
```

### Shell Script Implementation (musiclib_utils.sh)

```bash
# Add to musiclib_utils.sh

#############################################
# Normalize File Path
#############################################
# Converts mixed-case and space-separated paths to 
# lowercase, underscore-separated format
# 
# Usage: normalize_filepath "/Path/To/File.mp3"
# Output: /path/to/file.mp3
#
normalize_filepath() {
    local path="$1"
    
    # Convert to lowercase
    path="${path,,}"
    
    # Replace spaces with underscores
    path="${path// /_}"
    
    # Remove special chars except -._/
    path=$(echo "$path" | sed 's/[^a-z0-9._\/-]/_/g')
    
    # Collapse multiple underscores
    path=$(echo "$path" | sed 's/_\+/_/g')
    
    # Remove trailing underscores (but not trailing slashes)
    path=$(echo "$path" | sed 's/_*$//; s#/_*$#/#')
    
    echo "$path"
}

# Export for sourcing scripts
export -f normalize_filepath
```

### Usage in Scripts

```bash
# In musiclib_rate.sh
filepath="$1"

# Normalize path before any operations
filepath=$(normalize_filepath "$filepath")

# Continue with normalized path
if [ ! -f "$filepath" ]; then
    error_exit 1 "File not found" "filepath" "$filepath"
    exit 1
fi
```

---

## Change 4: Audacious Integration – Clarity and --process-pending

### Issue
Unclear why users would invoke `musiclib-cli audacious` when Audacious calls the script directly as a hook.

### Solution
Document three legitimate use cases and add explicit `--process-pending` subcommand.

### Use Case 1: Manual Scrobbling

For testing or immediate scrobbling without waiting for playback threshold:

```bash
# Manually scrobble a track (testing)
musiclib-cli audacious "/mnt/music/music/radiohead/ok_computer/01_-_radiohead_-_airbag.mp3"

# Immediately:
# - Extracts album art
# - Records listen timestamp
# - Updates LastTimePlayed in DB
# - Updates Conky display
# - No waiting for 50% playback threshold
```

### Use Case 2: Catch-Up After Misconfiguration

If Audacious hook fails or isn't configured, user can bulk scrobble:

```bash
# After listening to multiple tracks without hook
for track in ~/musiclib/playlists/my_session.audpl; do
    # Parse playlist and extract filepath
    musiclib-cli audacious "$filepath"
done

# Or script a directory:
find /mnt/music/music/radiohead -name "*.mp3" | while read track; do
    musiclib-cli audacious "$track"
done
```

### Use Case 3: Lock-Contention Deferred Operations

**Most important use case**: Handle failed scrobbles due to concurrent access.

When Audacious hook times out acquiring lock:

```
1. Audacious plays track and calls: musiclib_audacious.sh "/path/track.mp3"

2. Script tries to acquire lock, times out after 5s

3. Instead of failing, writes to pending operations queue:
   ~/.local/share/musiclib/data/.pending_operations

4. Script returns exit code 3 (deferred - operation queued)

5. Background process/cron retries:
   musiclib-cli audacious --process-pending
   
   Which retries all queued scrobbles
```

### Dispatcher Implementation

```cpp
// In musiclib-cli dispatcher

if (command == "audacious") {
    QStringList scriptArgs;
    
    // Check for options
    if (args.contains("--current")) {
        scriptArgs << "--current";
    } else if (args.contains("--status")) {
        scriptArgs << "--status";
    } else if (args.contains("--process-pending")) {
        scriptArgs << "--process-pending";
    } else if (!args.isEmpty() && !args.at(0).startsWith("--")) {
        // First non-option argument is track path
        scriptArgs << normalizePath(args.at(0));
    }
    // If no args and no options, let script get current track
    
    return executeScript("musiclib_audacious.sh", scriptArgs);
}
```

### Script Implementation (musiclib_audacious.sh)

Add option handling:

```bash
#############################################
# Parse Command Line Arguments
#############################################

MANUAL_TRACK=""
SHOW_CURRENT=false
SHOW_STATUS=false
PROCESS_PENDING=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --current)
            SHOW_CURRENT=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        --process-pending)
            PROCESS_PENDING=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            # First positional arg is manual track path
            MANUAL_TRACK="$1"
            shift
            ;;
    esac
done

#############################################
# Handle Different Modes
#############################################

if [ "$SHOW_CURRENT" = true ]; then
    # Show current track info
    show_current_track
    exit 0
fi

if [ "$SHOW_STATUS" = true ]; then
    # Show scrobble statistics
    show_scrobble_status
    exit 0
fi

if [ "$PROCESS_PENDING" = true ]; then
    # Process deferred scrobbles
    process_pending_scrobbles
    exit $?
fi

if [ -n "$MANUAL_TRACK" ]; then
    # Manual scrobble - immediate, no threshold
    scrobble_track "$MANUAL_TRACK"
    exit $?
fi

# Default: hook mode - monitor current playback
monitor_audacious_playback
exit $?
```

### Cron Job for Automatic Retry

Users can add to crontab for automatic pending operation processing:

```bash
# In crontab -e
# Process pending scrobbles every minute
* * * * * /usr/bin/musiclib-cli audacious --process-pending >/dev/null 2>&1

# Or every 5 minutes for less frequent checking
*/5 * * * * /usr/bin/musiclib-cli audacious --process-pending >/dev/null 2>&1
```

---

## Change 5: Build Script File Rename

### Current State
File is currently named `musiclib_rebuild.sh`

### Proposed Change
Rename to `musiclib_build.sh` to reflect dual purpose (initial build and rebuild)

### Files to Update

1. **Rename file**:
   ```bash
   mv musiclib_rebuild.sh musiclib_build.sh
   ```

2. **Update dispatcher routing**:
   ```cpp
   if (command == "build") {
       return executeScript("musiclib_build.sh", args);
   }
   ```

3. **Update BACKEND_API.md**:
   - Section 2.3: Change title from "`musiclib-cli rebuild`" to "`musiclib-cli build`"
   - Change script reference from `musiclib_rebuild.sh` to `musiclib_build.sh`

4. **Update script header comment**:
   ```bash
   # musiclib_build.sh - Build/rebuild music library database from scratch
   # Usage: musiclib_build.sh [music_directory] [options]
   ```

5. **Update SCRIPTS_SUMMARY.md**:
   - Rename section from "musiclib_rebuild.sh" to "musiclib_build.sh"

---

## Summary of Implementation Tasks

| Task | File | Type | Priority |
|------|------|------|----------|
| Rename rebuild → build | `musiclib_rebuild.sh` → `musiclib_build.sh` | File/Script | High |
| Add DB overwrite prompt | `musiclib-cli` dispatcher | C++ | High |
| Add --source parameter | `musiclib_new_tracks.sh` | Bash | High |
| Add config entries | `musiclib.conf` | Config | High |
| Path normalization | `musiclib_utils.sh` + dispatcher | Bash/C++ | Medium |
| Audacious --process-pending | `musiclib_audacious.sh` + dispatcher | Bash/C++ | Medium |
| Update documentation | BACKEND_API.md, SCRIPTS_SUMMARY.md | Markdown | Medium |

---

## Testing Recommendations

### Test Case 1: Build with Existing DB
```bash
# First build
musiclib-cli build /mnt/music/music

# Rebuild - should prompt for action
musiclib-cli build /mnt/music/music
# Choose option 2 (rename to .backup.TIMESTAMP)
# Verify .backup file created
```

### Test Case 2: New Track Import from Alternate Directory
```bash
# Copy test MP3s to alternate directory
mkdir -p /tmp/test_import
cp /mnt/music/music/radiohead/ok_computer/*.mp3 /tmp/test_import/

# Import from alternate directory
musiclib-cli new-tracks "radiohead" --source /tmp/test_import --dry-run

# Verify correct directory used
```

### Test Case 3: Manual Audacious Scrobble
```bash
# Test manual scrobble (immediate, no threshold)
musiclib-cli audacious "/mnt/music/music/the_beatles/abbey_road/01_-_the_beatles_-_come_together.mp3"

# Verify:
# - Album art extracted
# - DB updated with listen
# - LastTimePlayed recorded
```

### Test Case 4: Process Pending Operations
```bash
# Simulate lock contention (multiple rapid operations)
for i in {1..10}; do
    musiclib-cli rate "/mnt/music/music/song_$i.mp3" $((RANDOM % 6)) &
done
wait

# Some operations may queue due to lock timeout

# Process pending
musiclib-cli audacious --process-pending

# Verify all pending operations completed
```

---

**Implementation Status**: Ready for coding  
**Backward Compatibility**: First release—no legacy concerns
