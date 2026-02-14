# MusicLib KDE Control Plane — Feature Evaluation & KDE Integration Proposals

## 1. Current Codebase Summary

The MusicLib project consists of a shell-script backend (11 scripts plus 2 config files) orchestrating Audacious, kid3-cli, rsgain, exiftool, and KDE Connect around a flat-file DSV database. The planned GUI is a C++/Qt 6/KDE Frameworks 6 application that acts as a "smart client" — it reads the database directly but delegates all writes to the shell scripts.

**Currently implemented backend scripts:**

| Script | Role | GUI Coverage (per Project Plan) |
|--------|------|-------------------------------|
| `musiclib_utils.sh` | Shared library (config, DB helpers, logging, locking) | Consumed internally |
| `musiclib_utils_tag_functions.sh` | Tag repair/normalization layer | Consumed internally |
| `musiclib_audacious.sh` | Song-change hook → Conky assets, scrobble tracking, last-played | Planned (via PlayerBackend) |
| `musiclib_rate.sh` | Star rating → POPM/Grouping/DB/Conky/notifications | Planned (Rate button) |
| `musiclib_mobile.sh` | KDE Connect playlist push + synthetic last-played | Planned (Mobile panel) |
| `musiclib_new_tracks.sh` | Import pipeline (ZIP/MP3 → normalize → DB) | Planned (Add track dialog) |
| `musiclib_rebuild.sh` | Full DB rebuild from filesystem scan | **Not in GUI plan** |
| `musiclib_tagrebuild.sh` | Repair corrupted tags from DB values | **Not in GUI plan** |
| `musiclib_tagclean.sh` | ID3v1→v2 merge, APE removal, art embedding | **Not in GUI plan** |
| `boost_album.sh` | ReplayGain loudness targeting per album | **Not in GUI plan** |
| `audpl_scanner.sh` | Playlist scanning + cross-reference CSV generation | **Not in GUI plan** |

The project plan covers library view, rating, Conky panel, and mobile panel for Phase 2, with batch operations and MPRIS deferred to Phase 4. Five scripts have no planned GUI surface at all.

---

## 2. Proposed New Features (Not Currently in Project Plan)

These proposals are ordered by value relative to implementation complexity, and they all leverage capabilities already present in the KDE/Plasma ecosystem.

### 2.1 Maintenance Operations Panel

**What it is:** A dedicated GUI panel that wraps the five "orphaned" scripts — `musiclib_rebuild.sh`, `musiclib_tagrebuild.sh`, `musiclib_tagclean.sh`, `boost_album.sh`, and `audpl_scanner.sh` — into a unified maintenance console.

**Why it matters:** These scripts represent significant functionality you already wrote and maintain. Without GUI integration they remain CLI-only, which fragments your workflow and means the GUI is an incomplete picture of what MusicLib can do.

**KDE leverage:**
- **KIO Workers (formerly KIO Slaves):** Use KIO's file dialog integration so the user can browse to a target directory or file using Plasma's native file picker, complete with Places panel bookmarks for your music directories.
- **KJob framework:** Qt/KDE's `KJob` class is designed exactly for long-running operations with progress reporting. Wrapping each script invocation in a `KJob` subclass gives you automatic progress bars, cancellation support, and notification on completion — all native Plasma behavior.
- **KNotifications:** Emit Plasma desktop notifications on completion, especially for operations like full DB rebuild that might take several minutes.

**Implementation approach:** Each script already supports `--dry-run` and `--verbose`. The GUI would call `--dry-run` first to populate a preview, then execute on confirmation. Script stdout could be parsed line-by-line for live progress updates.

---

### 2.2 System Tray Integration (KStatusNotifierItem)

**What it is:** A persistent system tray icon that shows current playback state and provides quick actions without opening the full GUI window.

**Why it matters:** As a "control plane" app, MusicLib should be ambient — always available but not always in the way. KDE Plasma's system tray is the natural home for this, and it's where KDE Connect, Bluetooth, and other always-on services live.

**What it would show:**
- Current track info (artist — title) as a tooltip.
- Album art as the tray icon (or a fallback music icon when nothing is playing).
- Left-click: toggle main window visibility.
- Right-click context menu: Play/Pause/Next/Prev, quick-rate (submenu of 0–5 stars), open in Audacious.
- Middle-click: rate current track (cycle through ratings or pop up a quick star selector).

**KDE leverage:**
- **KStatusNotifierItem:** The standard KDE class for system tray presence. Unlike raw `QSystemTrayIcon`, it integrates with Plasma's SNI protocol, meaning it works correctly across Wayland, X11, and respects the user's panel configuration.
- Tooltip support includes rich HTML, so you could show album art + track info in the hover tooltip.

---

### 2.3 KDE Global Shortcuts (KGlobalAccel)

**What it is:** System-wide keyboard shortcuts for rating, play control, and other frequent actions, even when the MusicLib window isn't focused.

**Why it matters:** You already use `kdialog` for notifications in the shell scripts. Global shortcuts eliminate the need to switch windows just to rate a track or skip to the next one — which is exactly the "control plane" philosophy.

**Proposed default shortcuts:**
- `Meta+R, 1` through `Meta+R, 5`: Rate current track 1–5 stars
- `Meta+R, 0`: Clear rating
- `Meta+Shift+N`: Quick "what's playing now?" notification popup
- `Media keys` (Play/Pause/Next/Prev): Route through PlayerBackend if Audacious doesn't claim them

**KDE leverage:**
- **KGlobalAccel:** Registers shortcuts that work system-wide, persist across sessions, and appear in Plasma's System Settings → Shortcuts, where users can customize them alongside all their other app shortcuts. This is a big UX win — your app's shortcuts become first-class citizens in the desktop.

---

### 2.4 Dolphin Service Menus (KDE Context Menu Integration)

**What it is:** Right-click menu entries in Dolphin (KDE's file manager) that appear when you right-click on MP3 files or music directories.

**Why it matters:** Power users often work from the file manager. Being able to right-click an album folder and say "Add to MusicLib" or "Clean Tags" or "Boost Loudness" without opening the GUI at all is a natural extension of the CLI-first philosophy.

**Proposed service menu actions:**
- On MP3 files: "Rate in MusicLib...", "Rebuild Tags", "View in MusicLib"
- On directories: "Add to MusicLib", "Tag Cleanup...", "Boost Album Loudness...", "Rebuild Tags (Recursive)"
- On `.audpl` files: "Upload to Phone via MusicLib", "Scan Playlist"

**KDE leverage:**
- **ServiceMenu `.desktop` files:** These are simple `.desktop` file entries placed in `~/.local/share/kio/servicemenus/`. No C++ needed — they just invoke your shell scripts (or the GUI with a `--command` flag). KDE handles the rest, including showing them only for the right MIME types.

---

### 2.5 Plasma Widget (Plasmoid) for Desktop

**What it is:** A small Plasma desktop/panel widget that shows now-playing info, album art, and star rating directly on the desktop — essentially a native replacement for the Conky output.

**Why it matters:** The project already generates Conky text files and images for desktop display. A Plasma widget would be the "native KDE" way to achieve the same result, with the advantage that it respects Plasma themes, can be placed on any panel or the desktop, supports mouse interaction (click to rate, click to open GUI), and doesn't require a separate Conky process.

**This doesn't replace Conky** — some users prefer Conky's flexibility. But it provides a native alternative for users who want a pure-Plasma setup.

**KDE leverage:**
- **Plasma QML Widgets:** Written in QML with a `metadata.json` manifest. Can read the same Conky output text files your scripts already produce, or can be pointed directly at the DSV database.
- **Plasma DataEngines / MPRIS DataEngine:** Could subscribe to the MPRIS data engine for live playback state once MPRIS support lands in Phase 4.

---

### 2.6 KActivities Integration

**What it is:** Automatic behavior changes based on which KDE Activity is active (e.g., "Work" vs. "Music" vs. "Chill").

**Why it matters:** If you use KDE Activities (which power users on Plasma often do), MusicLib could automatically load different playlists, adjust default rating behavior, or change which Conky layout is active based on the current Activity.

**KDE leverage:**
- **KActivities API:** Provides signals when the current Activity changes. MusicLib could store per-Activity preferences in KConfig and switch behavior accordingly.
- Practical example: On switching to a "Focus" activity, MusicLib could auto-pause or switch to a low-energy playlist.

---

### 2.7 KRunner Plugin

**What it is:** A plugin for KRunner (the `Alt+Space` launcher) that lets you search your music library, rate tracks, or trigger operations by typing.

**Why it matters:** KRunner is one of Plasma's most powerful features, and power users use it constantly. Being able to type `ml:rate 4` or `ml:play Artist Name` from anywhere on the desktop is extremely fast.

**Example queries:**
- `ml: Dark Side` → search library for matching tracks, click to play
- `ml:rate 5` → rate current track 5 stars
- `ml:mobile upload` → trigger mobile sync
- `ml:status` → show current playback + rating inline

**KDE leverage:**
- **KRunner AbstractRunner plugin:** C++ plugin with a standard API. Results appear inline in the launcher with icons and descriptions.

---

### 2.8 D-Bus Service for External Automation

**What it is:** A lightweight D-Bus interface exposed by the GUI (or a small daemon) so that other tools, scripts, or desktop automation can query and control MusicLib programmatically.

**Why it matters:** This is the foundation that makes features 2.2–2.7 much easier to implement, and it opens MusicLib up to integration with tools you haven't thought of yet — shell scripts, KWin rules, custom Plasma widgets, etc. It also aligns with the `musiclibd` daemon mentioned in Section 4.4 of the project plan.

**Proposed interface:**
- `org.musiclib.Library`: `Search(query)`, `GetTrackInfo(id)`, `GetStats()`
- `org.musiclib.Player`: `GetCurrentTrack()`, `Rate(stars)`, `Control(command)`
- `org.musiclib.Mobile`: `Upload(playlist)`, `GetDeviceStatus()`
- `org.musiclib.Maintenance`: `TagClean(path, options)`, `Rebuild(options)`

**KDE leverage:**
- **Qt D-Bus (QDBusAbstractAdaptor):** Built into Qt, no extra dependencies. Define your interface, register on session bus, done. Other KDE apps and your own scripts can call it with `qdbus` or `dbus-send`.

---

## 3. GUI Design Recommendations

These recommendations apply to both the currently planned panels and the proposed new features.

### 3.1 Overall Layout: Sidebar + Stacked Panels

The project plan mentions three panels (library view, Conky panel, mobile panel). With the maintenance features proposed above, you'd have five or six panels. A **sidebar navigation** pattern works best here:

```
┌──────────────────────────────────────────────────┐
│  [System Tray Icon]           MusicLib v0.1      │
├──────────┬───────────────────────────────────────┤
│          │                                       │
│ 🎵 Library │  [ Currently Playing Strip ]        │
│ ⭐ Ratings │  ┌─────────────────────────────┐    │
│ 📱 Mobile  │  │                             │    │
│ 🎨 Conky   │  │   Active Panel Content      │    │
│ 🔧 Maint.  │  │                             │    │
│ 📊 Stats   │  │                             │    │
│          │  └─────────────────────────────┘    │
│          │                                       │
│ ⚙ Settings │  [ Status Bar: DB info, lock ]     │
├──────────┴───────────────────────────────────────┤
│  ▶ Artist — Title      ⭐⭐⭐⭐☆    [1:23/3:45] │
└──────────────────────────────────────────────────┘
```

The "Currently Playing" strip should be persistent across all panels — always visible at the bottom. It shows track info, album art thumbnail, star rating (clickable), and a position indicator. This is the one piece of UI that ties everything together.

**KDE leverage:** Use `KXmlGuiWindow` as the main window class — it automatically gives you configurable toolbars, the standard KDE HamburgerMenu, and a status bar. Sidebar navigation can be done with `QToolBox` or a custom `QListWidget` with icons.

### 3.2 Library View — Key UX Decisions

**Use `QTreeView` with a custom model, not `QTableView`.** A tree view lets you group by Artist → Album → Track naturally, which is how people think about music libraries. But make it collapsible — users should be able to switch between flat table mode and tree mode with a toggle.

**Column visibility presets:** Don't show all DSV columns by default. Offer presets like "Essential" (Artist, Album, Title, Rating, Last Played), "Full" (all columns), and "Custom" (user picks). KDE's `KColumnResizer` or right-click-on-header pattern is the standard way to handle this.

**Inline star rating widget:** Render ratings as clickable stars directly in the table cells using a custom `QStyledItemDelegate`. Click to change rating — no dialog needed. This is the highest-value UX feature for the library view.

**Quick filter bar:** A single text field at the top that filters across artist, album, and title simultaneously. More advanced filtering (by rating range, by genre, by date range) can be behind an "Advanced" toggle. Use `QSortFilterProxyModel` for this.

**Color-coded rows for track health:** Tracks with missing tags, no rating, or very old last-played dates could get a subtle background tint so you can spot tracks that need attention at a glance.

### 3.3 Rating UX

Rating is the most frequent interactive operation, so it needs to be the fastest and most satisfying interaction in the app.

**Three ways to rate (all should work):**
1. Click stars inline in the library view or now-playing strip (visual, intuitive).
2. Global keyboard shortcut (fastest, works without focusing the window).
3. Right-click context menu on any track (works for bulk selection too).

**Instant visual feedback:** When a rating is applied, the star display should update immediately (optimistic UI), even before the shell script finishes. If the script fails, revert and show a notification. This makes rating feel snappy instead of waiting for kid3-cli to finish writing tags.

**KDE leverage:** `KRatingWidget` is a ready-made KDE widget that renders interactive star ratings in the standard Plasma style. Use it everywhere ratings appear.

### 3.4 Conky Panel Design

The Conky panel should have two modes:

**Preview mode:** Read-only display of what Conky is currently showing, pulled from the output text files. Include the album art image, star rating image, and all text fields. This lets you verify the Conky output without alt-tabbing to your desktop.

**Configuration mode:** Toggle individual outputs on/off, set the output directory, and generate `.conkyrc` snippets. A "Copy Snippet" button that puts the relevant Conky config on the clipboard via `QClipboard` is all you need.

### 3.5 Mobile Panel Design

The mobile sync is the most anxiety-inducing operation (it modifies data based on time estimates), so the GUI should provide maximum transparency.

**Three-stage workflow:**
1. **Select:** Choose playlist from a dropdown populated by scanning the playlists directory. Show track count, total size, estimated transfer time.
2. **Preview:** Run `--dry-run` and display the synthetic last-played calculations in a table. Highlight any tracks that would be skipped and why.
3. **Execute:** Confirm and run. Show real-time transfer progress (bytes sent / total, current file).

**Device status indicator:** Show KDE Connect device status (connected/disconnected, battery level, device name) at the top of the mobile panel. Use `kdeconnect-cli -l` output, parsed and displayed with a green/red indicator.

### 3.6 Maintenance Panel Design

Use a **card-based layout** where each maintenance operation is a card showing:
- Operation name and one-line description
- Target selector (file picker or directory browser via KIO)
- Options checkboxes matching the CLI flags (recursive, dry-run, verbose, etc.)
- "Preview" button → "Execute" button pattern
- A collapsible log output area that streams script stdout in real time

All maintenance operations should be non-blocking (run in `QThread` or use `QProcess` async) with a shared progress area at the bottom of the panel.

### 3.7 Settings — Use KConfig Properly

**Don't reinvent settings storage.** KConfig is already how KDE apps store preferences, and `KConfigXT` lets you define settings in an XML schema that auto-generates the C++ accessor code. Your `musiclib.conf` values would be mirrored into KConfig, with the shell scripts' config file remaining the authoritative source (the GUI writes to `musiclib.conf` when settings change).

Settings to expose in the GUI:
- Music directory, DB path, Conky output directory
- KDE Connect device ID (with a "Detect Devices" button)
- Default rating for new tracks
- Backup retention period
- Global shortcut assignments (via `KShortcutsDialog`)
- Which Conky outputs are enabled
- System tray behavior (show/hide, minimize-to-tray)

---

## 4. Implementation Priority

If I were to suggest a phased approach for the new features, roughly ordered by impact per effort:

**Add to Phase 2 (low-cost, high-value):**
- System tray icon (KStatusNotifierItem) — a few hours of work for major daily-use value.
- Global shortcuts for rating (KGlobalAccel) — similarly small effort, huge workflow improvement.
- Dolphin service menus — just `.desktop` files, no C++ at all.

**Add to Phase 3 or early Phase 4:**
- Maintenance panel wrapping the five orphaned scripts.
- D-Bus interface (lays groundwork for everything else).

**Phase 4+ (after core is stable):**
- KRunner plugin (depends on D-Bus interface).
- Plasma widget (depends on D-Bus or stable file-based output).
- KActivities integration (nice-to-have, low priority).

---

## 5. Summary

The current project plan is architecturally sound and covers the core daily-use features well. The main gaps are the five maintenance scripts that have no GUI surface, and several KDE-native integration points that would elevate MusicLib from "a GUI that wraps shell scripts" to "a native Plasma citizen that feels like it belongs on the desktop."

The KDE ecosystem provides ready-made components for almost everything proposed here — system tray, global shortcuts, file manager integration, D-Bus, KRunner, Plasma widgets, KConfig, KJobs, KNotifications. The project is uniquely well-positioned to leverage these because it's already committed to KDE-only and Arch-only, meaning you don't need to worry about portability trade-offs.

The biggest UX wins for the least effort are the system tray icon, global rating shortcuts, and Dolphin service menus. These three alone would make MusicLib feel significantly more integrated into the Plasma desktop experience.
