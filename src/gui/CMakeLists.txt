set(GUI_SOURCES
    main.cpp
    mainwindow.cpp
    librarymodel.cpp
    libraryview.cpp
    ratingdelegate.cpp
    scriptrunner.cpp
    maintenancepanel.cpp
    albumwindow.cpp
)

add_executable(musiclib-qt ${GUI_SOURCES})

target_link_libraries(musiclib-qt
    PRIVATE
        musiclib_common
        Qt6::Widgets
        KF6::CoreAddons
        KF6::XmlGui
        KF6::WidgetsAddons
        KF6::I18n
)

target_include_directories(musiclib-qt
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
)

install(TARGETS musiclib-qt
    RUNTIME DESTINATION bin
)
