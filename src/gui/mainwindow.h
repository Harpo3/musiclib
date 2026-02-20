#pragma once

#include <KXmlGuiWindow>

class QTabWidget;
class QLabel;
class LibraryView;
class ScriptRunner;
class MaintenancePanel;

/**
 * Main application window for MusicLib.
 *
 * Inherits KXmlGuiWindow for native KDE integration:
 *   - Standard menus (File, Settings, Help) via setupGUI()
 *   - Configurable toolbar
 *   - Window size/position saved automatically via KConfig
 *   - Status bar
 *
 * The central widget is a QTabWidget. Phase 2 panels plug in
 * via addTab():
 *   Tab 0: Library   (this file)
 *   Tab 1: Maintenance  (this file)
 *   Tab 2: Mobile       (future)
 *   Tab 3: Settings     (future, or as a dialog)
 */
class MainWindow : public KXmlGuiWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

private:
    void setupTabs();
    void setupStatusBar();
    void setupActions();
    void loadDatabase();

    /**
     * Read musiclib.conf and return the value for a given key.
     * Config search order:
     *   1. ~/musiclib/config/musiclib.conf  (dev / legacy layout)
     *   2. ~/.config/musiclib/musiclib.conf (XDG standard)
     * Returns empty string if key not found.
     */
    QString configValue(const QString &key) const;

    /**
     * Resolve the database path from config or fall back to
     * the well-known default location.
     */
    QString resolveDatabasePath() const;

    // --- Widgets ---
    QTabWidget   *m_tabWidget       = nullptr;
    LibraryView  *m_libraryView     = nullptr;
    ScriptRunner      *m_scriptRunner      = nullptr;
    MaintenancePanel  *m_maintenancePanel  = nullptr;

    // --- Status bar widgets (permanent) ---
    QLabel       *m_trackCountLabel = nullptr;
    QLabel       *m_dbPathLabel     = nullptr;
};
