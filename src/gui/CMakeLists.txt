set(GUI_SOURCES
    main.cpp
    mainwindow.cpp
    librarymodel.cpp
    libraryview.cpp
    ratingdelegate.cpp
    scriptrunner.cpp
    maintenancepanel.cpp
    albumwindow.cpp
    settingsdialog.cpp
    confwriter.cpp
    mobile_panel.cpp
)

qt_add_executable(musiclib-qt ${GUI_SOURCES})

# ── KConfigXT code generation ──
# Reads musiclib.kcfg at build time and generates musiclibsettings.h/.cpp
# with the MusicLibSettings singleton class.
# This replaces the older .kcfgc file approach with the CMake-native API.
kconfig_target_kcfg_file(musiclib-qt
    FILE        musiclib.kcfg
    CLASS_NAME  MusicLibSettings
    MUTATORS
    DEFAULT_VALUE_GETTERS
    SINGLETON
)

set_source_files_properties(${CMAKE_SOURCE_DIR}/musiclib.png
    PROPERTIES QT_RESOURCE_ALIAS musiclib.png
)

qt_add_resources(musiclib-qt "app_icons"
    PREFIX "/icons"
    FILES
        ${CMAKE_SOURCE_DIR}/musiclib.png
)

target_link_libraries(musiclib-qt
    PRIVATE
        musiclib_common
        Qt6::Widgets
        Qt6::DBus
        KF6::CoreAddons
        KF6::XmlGui
        KF6::WidgetsAddons
        KF6::I18n
        KF6::WindowSystem
        KF6::ConfigWidgets      # KConfigDialog, KUrlRequester
        KF6::ConfigGui          # KConfigSkeleton (generated settings)
        KF6::KIOWidgets         # KUrlRequester KIO integration (Places, bookmarks)
)

# The KConfigXT generator puts musiclibsettings.h in the build dir.
# We need this on the include path so other sources can #include it.
target_include_directories(musiclib-qt
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_BINARY_DIR}
)

install(TARGETS musiclib-qt
    RUNTIME DESTINATION bin
)

# Install the .kcfg schema so KDE system settings can find it.
install(FILES musiclib.kcfg
    DESTINATION share/config.kcfg
)
