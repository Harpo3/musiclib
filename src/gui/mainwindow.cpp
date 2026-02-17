#include "mainwindow.h"
#include "libraryview.h"

#include <QStatusBar>
#include <QDir>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
{
    setWindowTitle("MusicLib");
    setMinimumSize(900, 600);

    // Create library view
    m_libraryView = new LibraryView(this);
    setCentralWidget(m_libraryView);

    // Forward status messages from the view to the status bar
    connect(m_libraryView, &LibraryView::statusMessage,
        this, [this](const QString &msg) {
            statusBar()->showMessage(msg);
        });

    // Locate and load the DSV database
    loadDatabase();
}

MainWindow::~MainWindow() = default;

void MainWindow::loadDatabase()
{
    // Standard location: ~/.local/share/musiclib/data/musiclib.dsv
QString dsvPath = QDir::homePath() + "/musiclib/data/musiclib.dsv";
    if (!QDir().exists(dsvPath)) {
        statusBar()->showMessage(
            tr("Database not found: %1  — run musiclib-cli setup first").arg(dsvPath));
        return;
    }

    m_libraryView->loadDatabase(dsvPath);
}
