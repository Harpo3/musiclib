# Common library CMakeLists.txt
# Purpose: Build shared utility code used by both CLI and future GUI

# Create static library target
add_library(musiclib_common STATIC
    config_loader.cpp
    db_reader.cpp
    script_executor.cpp
    json_parser.cpp
    utils.cpp
)

# Set include directories
target_include_directories(musiclib_common
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include/musiclib>
)

# Link required libraries
target_link_libraries(musiclib_common
    PUBLIC
        Qt${QT_VERSION_MAJOR}::Core
)

# Set compiler warnings and flags
target_compile_options(musiclib_common PRIVATE
    -Wall -Wextra -Wpedantic -Werror
)

# Optional: Set library properties
set_target_properties(musiclib_common PROPERTIES
    VERSION ${PROJECT_VERSION}
    SOVERSION 1
)

# Installation rules for headers (optional - for external library consumers)
# install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/
#     DESTINATION include/musiclib
#     FILES_MATCHING PATTERN "*.h"
# )

install(TARGETS musiclib_common
    EXPORT MusicLibTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)