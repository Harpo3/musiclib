#include "mainwindow.h"

#include <QLabel>
#include <QStatusBar>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
{
    setWindowTitle("MusicLib");
    setMinimumSize(900, 600);

    // Placeholder until Phase 2 panels are implemented
    QLabel *placeholder = new QLabel("MusicLib \u2014 Phase 2 in progress", this);
    placeholder->setAlignment(Qt::AlignCenter);
    setCentralWidget(placeholder);

    statusBar()->showMessage("Ready");
}

MainWindow::~MainWindow() = default;
