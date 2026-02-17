#include "mainwindow.h"

#include <QApplication>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    app.setApplicationName("MusicLib");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("MusicLib");

    MainWindow window;
    window.show();

    return app.exec();
}
