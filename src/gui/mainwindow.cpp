#include "mainwindow.h"
#include "libraryview.h"

#include <KStandardAction>
#include <KActionCollection>
#include <KLocalizedString>

#include <QTabWidget>
#include <QLabel>
#include <QStatusBar>
#include <QApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QIcon>

MainWindow::MainWindow(QWidget *parent)
    : KXmlGuiWindow(parent)
{
    setWindowTitle(i18n("MusicLib"));
    setMinimumSize(900, 600);

    setupTabs();
    setupStatusBar();
    setupActions();
    loadDatabase();
}

MainWindow::~MainWindow() = default;

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void MainWindow::setupTabs()
{
    m_tabWidget = new QTabWidget(this);
    m_tabWidget->setTabPosition(QTabWidget::North);
    m_tabWidget->setDocumentMode(true);  // cleaner look, tabs blend with content

    // --- Tab 0: Library ---
    m_libraryView = new LibraryView(this);
    m_tabWidget->addTab(m_libraryView,
                        QIcon::fromTheme("view-media-playlist"),
                        i18n("Library"));

    // Future tabs will be added here, e.g.:
    //   m_tabWidget->addTab(m_maintenancePanel, QIcon::fromTheme("configure"), i18n("Maintenance"));
    //   m_tabWidget->addTab(m_mobilePanel,      QIcon::fromTheme("smartphone"), i18n("Mobile"));

    setCentralWidget(m_tabWidget);

    // Forward status messages from the library view to the status bar
    connect(m_libraryView, &LibraryView::statusMessage,
            this, [this](const QString &msg) {
                statusBar()->showMessage(msg, 5000);  // transient, 5 sec
            });
}

void MainWindow::setupStatusBar()
{
    // Permanent widgets sit at the right side of the status bar
    // and are never hidden by transient showMessage() calls.
    m_trackCountLabel = new QLabel(this);
    m_trackCountLabel->setFrameStyle(QFrame::NoFrame);
    statusBar()->addPermanentWidget(m_trackCountLabel);

    m_dbPathLabel = new QLabel(this);
    m_dbPathLabel->setFrameStyle(QFrame::NoFrame);
    m_dbPathLabel->setStyleSheet("color: gray; padding-left: 12px;");
    statusBar()->addPermanentWidget(m_dbPathLabel);
}

void MainWindow::setupActions()
{
    // Standard Quit action (Ctrl+Q) — required for KXmlGuiWindow.
    // Connect to the window's close() rather than QApplication::quit()
    // so that KXmlGuiWindow completes its cleanup (save window size,
    // release resources) before the application exits.
    KStandardAction::quit(this, &QWidget::close, actionCollection());

    // setupGUI() creates the menu bar, toolbar, and wires up KStandardActions.
    // Use CreateDefault minus the ToolBar flag since we have no toolbar actions yet,
    // and skip the .rc file lookup — KDE will auto-generate menus from the
    // action collection (File > Quit, Help > About, etc.)
    setupGUI(StatusBar | Keys | Save | Create);
}

// ---------------------------------------------------------------------------
// Database loading
// ---------------------------------------------------------------------------

void MainWindow::loadDatabase()
{
    QString dsvPath = resolveDatabasePath();

    if (dsvPath.isEmpty() || !QFileInfo::exists(dsvPath)) {
        QString tried = dsvPath.isEmpty() ? "(no path configured)" : dsvPath;
        statusBar()->showMessage(
            i18n("Database not found: %1 — run musiclib-cli setup first", tried));
        m_trackCountLabel->setText(i18n("No database"));
        return;
    }

    bool ok = m_libraryView->loadDatabase(dsvPath);

    if (ok) {
        m_trackCountLabel->setText(i18n("%1 tracks", m_libraryView->trackCount()));
        m_dbPathLabel->setText(dsvPath);
    } else {
        m_trackCountLabel->setText(i18n("Load failed"));
        m_dbPathLabel->setText(dsvPath);
    }
}

QString MainWindow::resolveDatabasePath() const
{
    // 1. Try sourcing musiclib.conf through bash to resolve the
    //    full path, including conditionals and ${VAR:-default} syntax.
    QString fromConfig = configValue("MUSICDB");
    if (!fromConfig.isEmpty() && QFileInfo::exists(fromConfig))
        return fromConfig;

    // 2. Fall back to well-known default locations
    //    Try dev/legacy layout first, then XDG standard
    QString devPath = QDir::homePath() + "/musiclib/data/musiclib.dsv";
    if (QFileInfo::exists(devPath))
        return devPath;

    QString xdgPath = QDir::homePath() + "/.local/share/musiclib/data/musiclib.dsv";
    if (QFileInfo::exists(xdgPath))
        return xdgPath;

    // Return the dev path even if it doesn't exist — loadDatabase()
    // will show the "not found" message with this path.
    return devPath;
}

QString MainWindow::configValue(const QString &key) const
{
    // Source musiclib.conf through bash so that all variable expansion,
    // conditionals, and ${VAR:-default} syntax is evaluated exactly
    // the way the shell scripts see it.  One-shot process, ~10ms.
    static const QStringList configPaths = {
        QDir::homePath() + "/musiclib/config/musiclib.conf",
        QDir::homePath() + "/.config/musiclib/musiclib.conf",
    };

    for (const QString &path : configPaths) {
        if (!QFileInfo::exists(path))
            continue;

        QProcess proc;
        proc.setProcessChannelMode(QProcess::MergedChannels);

        // source the config, then echo the requested variable
        QString cmd = QStringLiteral("source \"%1\" 2>/dev/null && echo \"$%2\"")
                          .arg(path, key);
        proc.start("bash", QStringList() << "-c" << cmd);

        if (!proc.waitForFinished(3000))  // 3 sec timeout
            continue;

        if (proc.exitCode() != 0)
            continue;

        QString value = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        if (!value.isEmpty())
            return value;
    }

    return QString();
}
