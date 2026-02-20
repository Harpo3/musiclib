#include "mainwindow.h"

#include <QApplication>
#include <KAboutData>
#include <KLocalizedString>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    // KDE application metadata — used by Help > About, D-Bus registration,
    // desktop file matching, and KDE crash handler.
    KAboutData aboutData(
        QStringLiteral("musiclib-qt"),           // component name (internal)
        i18n("MusicLib"),                         // display name
        QStringLiteral("0.1.0"),                  // version
        i18n("Music library manager for KDE"),    // short description
        KAboutLicense::GPL_V3,                    // license
        i18n("© 2026"),                           // copyright
        QString(),                                // other text (optional)
        QStringLiteral("https://github.com/musiclib/musiclib")  // homepage
    );

    aboutData.setOrganizationDomain("musiclib.org");
    aboutData.setDesktopFileName("org.musiclib.musiclib-qt");

    KAboutData::setApplicationData(aboutData);
    KLocalizedString::setApplicationDomain("musiclib-qt");

    // KXmlGuiWindow sets the WA_DeleteOnClose attribute, which means Qt
    // will call 'delete' on the window when it is closed.  The window
    // must therefore be heap-allocated — a stack object would cause
    // free() on a stack address at shutdown.
    auto *window = new MainWindow();
    window->show();

    return app.exec();
}
