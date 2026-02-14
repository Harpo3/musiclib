cmake_minimum_required(VERSION 3.21)
project(MusicLib VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake")

# Output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Qt Configuration
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

# Try Qt6 first, fallback to Qt5
find_package(Qt6 COMPONENTS Core QUIET)
if(Qt6_FOUND)
    set(QT_VERSION_MAJOR 6)
    message(STATUS "Using Qt6")
else()
    find_package(Qt5 5.15 REQUIRED COMPONENTS Core)
    set(QT_VERSION_MAJOR 5)
    message(STATUS "Using Qt5")
endif()

# Build options
option(ENABLE_WARNINGS_AS_ERRORS "Treat warnings as errors" ON)
option(ENABLE_ASAN "Enable AddressSanitizer" OFF)
option(ENABLE_TESTING "Enable testing" ON)

# Compiler flags
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wall -Wextra -Wpedantic)
    
    if(ENABLE_WARNINGS_AS_ERRORS)
        add_compile_options(-Werror)
    endif()
    
    if(ENABLE_ASAN)
        add_compile_options(-fsanitize=address -fno-omit-frame-pointer)
        add_link_options(-fsanitize=address)
    endif()
endif()

# Release optimizations
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON) # LTO
endif()

add_subdirectory(src/common)
add_subdirectory(src/cli)

# Testing
if(ENABLE_TESTING)
    enable_testing()
    add_subdirectory(tests)
endif()

# Installation configuration
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Install prefix" FORCE)
endif()

# Install shell scripts
install(DIRECTORY ${CMAKE_SOURCE_DIR}/bin/
    DESTINATION lib/musiclib/bin
    FILES_MATCHING PATTERN "*.sh"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE
)

# Install config files
install(DIRECTORY ${CMAKE_SOURCE_DIR}/config/
    DESTINATION lib/musiclib/config
    FILES_MATCHING PATTERN "*.conf" PATTERN "*.txt"
    PERMISSIONS OWNER_READ OWNER_WRITE
                GROUP_READ
                WORLD_READ
)

# Install data files
install(FILES 
    ${CMAKE_SOURCE_DIR}/musiclib_example.csv
    DESTINATION share/musiclib
)

# Man page installation
find_program(GZIP gzip)
if(GZIP)
    install(FILES ${CMAKE_SOURCE_DIR}/man/musiclib-cli.1
        DESTINATION share/man/man1
        PERMISSIONS OWNER_READ GROUP_READ WORLD_READ
    )
endif()

# CMake package configuration
include(CMakePackageConfigHelpers)

configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/MusicLibConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfig.cmake
    INSTALL_DESTINATION lib/cmake/MusicLib
)

write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)

install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfigVersion.cmake
    DESTINATION lib/cmake/MusicLib
)

install(EXPORT MusicLibTargets
    FILE MusicLibTargets.cmake
    NAMESPACE MusicLib::
    DESTINATION lib/cmake/MusicLib
)

# Uninstall target
configure_file(
    "${CMAKE_SOURCE_DIR}/cmake/cmake_uninstall.cmake.in"
    "${CMAKE_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY
)
add_custom_target(uninstall
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_BINARY_DIR}/cmake_uninstall.cmake
)