# Phase 1 - Task 1: CMake Project Setup for musiclib-cli
## Detailed Subtask Breakdown

**Goal**: Establish CMake build infrastructure for the musiclib-cli C++ dispatcher binary

**Context**: 
- Target: Linux x64 (Arch/KDE Plasma)
- CMake Version: 4.2.3-1
- Development Environment: Code OSS 1.109.0
- Project Structure: Uses `src/cli/`, `src/common/`, `src/gui/` directories

---

## 1.1 Root CMakeLists.txt Creation

**Purpose**: Create top-level build configuration file

**Files to Create**:
- `/home/lpc123/musiclib/CMakeLists.txt`

**Subtasks**:
1. Set minimum CMake version (3.16 for Qt 5 compatibility, or 3.21 for Qt 6)
2. Define project name (`MusicLib`), version (0.1.0), languages (CXX)
3. Set C++ standard (C++17 minimum, C++20 preferred)
4. Configure build types (Debug, Release, RelWithDebInfo)
5. Set default build type to RelWithDebInfo if not specified
6. Enable position-independent code (PIC) for libraries
7. Add CMake module path for custom find modules
8. Set output directories for binaries and libraries
9. Include subdirectories (`src/cli`, `src/common`, later `src/gui`)

**Example Structure**:
```cmake
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

add_subdirectory(src/common)
add_subdirectory(src/cli)
```

**Validation**:
- Run `cmake -B build` from project root
- Verify no errors in configuration phase

---

## 1.2 Common Library CMakeLists.txt

**Purpose**: Build shared utility code used by both CLI and future GUI

**Files to Create**:
- `/home/lpc123/musiclib/src/common/CMakeLists.txt`

**Subtasks**:
1. Create library target (`musiclib_common`)
2. Define library type (STATIC or SHARED - start with STATIC)
3. List common source files (placeholders for now):
   - `config_loader.cpp` - Loads `musiclib.conf`
   - `db_reader.cpp` - Reads musiclib.dsv (DSV parsing)
   - `script_executor.cpp` - Executes shell scripts via QProcess
   - `json_parser.cpp` - Parses JSON error responses
   - `utils.cpp` - General utilities
4. Set include directories (public vs. private)
5. Link required libraries (Qt5/Qt6 Core, filesystem)
6. Set compiler warnings and flags
7. Add header installation rules

**Example Structure**:
```cmake
add_library(musiclib_common STATIC
    config_loader.cpp
    db_reader.cpp
    script_executor.cpp
    json_parser.cpp
    utils.cpp
)

target_include_directories(musiclib_common
    PUBLIC 
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(musiclib_common
    PUBLIC
        Qt${QT_VERSION_MAJOR}::Core
)

target_compile_options(musiclib_common PRIVATE
    -Wall -Wextra -Wpedantic -Werror
)
```

**Validation**:
- Create stub `.cpp` files with minimal content
- Verify library compiles without errors

---

## 1.3 CLI Dispatcher CMakeLists.txt

**Purpose**: Build the `musiclib-cli` executable binary

**Files to Create**:
- `/home/lpc123/musiclib/src/cli/CMakeLists.txt`

**Subtasks**:
1. Create executable target (`musiclib-cli`)
2. List CLI-specific source files:
   - `main.cpp` - Entry point, argument dispatcher
   - `command_handler.cpp` - Routes subcommands to scripts
   - `cli_utils.cpp` - CLI-specific utilities (help text, version)
3. Link against `musiclib_common` library
4. Link required Qt modules (Core for QProcess, etc.)
5. Set executable properties (output name, RPATH)
6. Configure installation rules:
   - Binary → `/usr/bin/musiclib-cli`
   - Set executable permissions
7. Add man page installation (if exists)

**Example Structure**:
```cmake
add_executable(musiclib-cli
    main.cpp
    command_handler.cpp
    cli_utils.cpp
)

target_link_libraries(musiclib-cli
    PRIVATE
        musiclib_common
        Qt${QT_VERSION_MAJOR}::Core
)

set_target_properties(musiclib-cli PROPERTIES
    OUTPUT_NAME musiclib-cli
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
)

# Installation
install(TARGETS musiclib-cli
    RUNTIME DESTINATION bin
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE
)
```

**Validation**:
- Create stub source files
- Verify executable builds
- Test manual invocation: `./build/bin/musiclib-cli --version`

---

## 1.4 Qt Dependency Configuration

**Purpose**: Detect and configure Qt framework (5 or 6)

**Files to Create/Modify**:
- `/home/lpc123/musiclib/cmake/FindQt.cmake` (optional helper)
- Modify root `CMakeLists.txt`

**Subtasks**:
1. Add Qt package finding logic (try Qt6 first, fallback to Qt5)
2. Detect Qt version available on system
3. Find required Qt components:
   - `Core` (QProcess, QFile, QFileInfo, QString, etc.)
   - `Network` (future - for remote features)
4. Set Qt-specific CMake options:
   - Enable automoc (Meta-Object Compiler)
   - Enable autouic (if UI files exist)
   - Enable autorcc (if resource files exist)
5. Define QT_VERSION_MAJOR variable for conditional compilation
6. Add Qt include directories globally or per-target
7. Handle Qt not found gracefully (error with helpful message)

**Example Addition to Root CMakeLists.txt**:
```cmake
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
```

**Validation**:
- Run `cmake -B build` and check Qt detection output
- Verify correct Qt version is found
- Test fallback mechanism by temporarily hiding Qt6

---

## 1.5 Compiler Flags and Build Options

**Purpose**: Set project-wide compilation standards and warnings

**Files to Modify**:
- Root `CMakeLists.txt`

**Subtasks**:
1. Define custom CMake options for user configuration:
   - `ENABLE_WARNINGS_AS_ERRORS` (default: ON for dev, OFF for release)
   - `ENABLE_ASAN` (Address Sanitizer for debugging)
   - `ENABLE_TESTING` (default: ON)
   - `BUILD_SHARED_LIBS` (default: OFF)
2. Set compiler-specific warning flags:
   - GCC/Clang: `-Wall -Wextra -Wpedantic`
   - MSVC: `/W4` (future cross-platform support)
3. Add debug-specific flags:
   - `-g` for debug symbols
   - `-O0` for no optimization
4. Add release-specific flags:
   - `-O3` for optimization
   - `-DNDEBUG` to disable assertions
5. Configure sanitizers (optional, for development):
   - AddressSanitizer: `-fsanitize=address`
   - UndefinedBehaviorSanitizer: `-fsanitize=undefined`
6. Set link-time optimization (LTO) for release builds

**Example Code**:
```cmake
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
```

**Validation**:
- Build in Debug mode: `cmake -B build -DCMAKE_BUILD_TYPE=Debug`
- Build in Release mode: `cmake -B build -DCMAKE_BUILD_TYPE=Release`
- Verify appropriate flags are applied (check compile commands)
- Intentionally introduce a warning, verify build fails with -Werror

---

## 1.6 Installation Rules

**Purpose**: Define how/where project files are installed system-wide

**Files to Modify**:
- Root `CMakeLists.txt`
- `src/cli/CMakeLists.txt` (already partially done in 1.3)

**Subtasks**:
1. Set installation prefix defaults:
   - Default: `/usr` for system install
   - Configurable via `-DCMAKE_INSTALL_PREFIX`
2. Define binary installation:
   - `musiclib-cli` → `/usr/bin/`
   - Future: `musiclib-qt` → `/usr/bin/`
3. Define library installation (if building shared libs):
   - `libmusiclib_common.so` → `/usr/lib/musiclib/`
4. Define script installation:
   - Shell scripts → `/usr/lib/musiclib/bin/`
   - Config files → `/usr/lib/musiclib/config/`
5. Define data file installation:
   - Example configs → `/usr/share/musiclib/`
   - Desktop files → `/usr/share/applications/`
   - Man pages → `/usr/share/man/man1/`
6. Set file permissions appropriately:
   - Binaries: 755 (executable)
   - Scripts: 755 (executable)
   - Config/data: 644 (readable)
7. Create uninstall target (custom CMake script)

**Example Code**:
```cmake
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

# Uninstall target
configure_file(
    "${CMAKE_SOURCE_DIR}/cmake/cmake_uninstall.cmake.in"
    "${CMAKE_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY
)
add_custom_target(uninstall
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_BINARY_DIR}/cmake_uninstall.cmake
)
```

**Validation**:
- Test local install: `cmake --build build --target install -- DESTDIR=/tmp/musiclib-test`
- Verify all files installed to correct locations
- Check file permissions
- Test uninstall target: `cmake --build build --target uninstall`

---

## 1.7 Build Script Configuration Files

**Purpose**: Create helper files for common build operations

**Files to Create**:
- `/home/lpc123/musiclib/scripts/build.sh` - Full rebuild script
- `/home/lpc123/musiclib/scripts/clean.sh` - Clean build artifacts
- `/home/lpc123/musiclib/scripts/install-deps.sh` - Install dependencies
- `/home/lpc123/musiclib/.gitignore` - Exclude build artifacts

**Subtasks**:

### build.sh
1. Create script that:
   - Removes old build directory
   - Runs CMake configuration
   - Builds all targets
   - Optionally runs tests
   - Shows summary of build status
2. Accept arguments: `--debug`, `--release`, `--clean`, `--install`, `--test`

### clean.sh
1. Create script that:
   - Removes `build/` directory
   - Cleans CMake cache
   - Removes generated files

### install-deps.sh
1. Create script that:
   - Detects package manager (pacman for Arch)
   - Installs Qt development packages
   - Installs CMake, GCC/Clang
   - Installs musiclib dependencies (kid3-cli, exiftool, etc.)
   - Lists optional dependencies

### .gitignore
1. Exclude build artifacts:
   - `build/`
   - `*.o`, `*.so`, `*.a`
   - CMake generated files
   - IDE metadata (.vscode/, .idea/)
   - Temporary files

**Example build.sh**:
```bash
#!/bin/bash
set -e

BUILD_TYPE="RelWithDebInfo"
CLEAN_BUILD=false
RUN_TESTS=false
INSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug) BUILD_TYPE="Debug"; shift ;;
        --release) BUILD_TYPE="Release"; shift ;;
        --clean) CLEAN_BUILD=true; shift ;;
        --test) RUN_TESTS=true; shift ;;
        --install) INSTALL=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$CLEAN_BUILD" = true ]; then
    rm -rf build/
fi

mkdir -p build
cd build

cmake .. -DCMAKE_BUILD_TYPE=$BUILD_TYPE
cmake --build . -j$(nproc)

if [ "$RUN_TESTS" = true ]; then
    ctest --output-on-failure
fi

if [ "$INSTALL" = true ]; then
    sudo cmake --install .
fi

echo "Build complete: $BUILD_TYPE"
```

**Validation**:
- Run each script manually
- Verify build directory is created/removed appropriately
- Test all script options

---

## 1.8 Testing Framework Integration

**Purpose**: Set up CTest for unit and integration testing

**Files to Create**:
- `/home/lpc123/musiclib/tests/CMakeLists.txt`
- `/home/lpc123/musiclib/tests/test_config_loader.cpp` (stub)
- `/home/lpc123/musiclib/tests/test_db_reader.cpp` (stub)

**Subtasks**:
1. Enable CTest in root CMakeLists.txt: `enable_testing()`
2. Add `tests/` subdirectory
3. Create test CMakeLists.txt that:
   - Links test executables against `musiclib_common`
   - Uses Qt Test framework or Catch2/GoogleTest
   - Registers tests with CTest
4. Create stub test files with basic structure
5. Add test data files (example musiclib.conf, musiclib.dsv)
6. Configure test environment (set LD_LIBRARY_PATH, etc.)
7. Add coverage reporting option (optional - gcov/lcov)

**Example tests/CMakeLists.txt**:
```cmake
# Testing
find_package(Qt${QT_VERSION_MAJOR} COMPONENTS Test REQUIRED)

# Helper function to add tests
function(add_musiclib_test TEST_NAME)
    add_executable(${TEST_NAME} ${TEST_NAME}.cpp)
    target_link_libraries(${TEST_NAME}
        PRIVATE
            musiclib_common
            Qt${QT_VERSION_MAJOR}::Test
    )
    add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endfunction()

# Individual tests
add_musiclib_test(test_config_loader)
add_musiclib_test(test_db_reader)
add_musiclib_test(test_script_executor)

# Copy test data
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/data/test_musiclib.conf
    ${CMAKE_CURRENT_BINARY_DIR}/test_musiclib.conf
    COPYONLY
)
```

**Validation**:
- Run tests: `ctest` or `cmake --build build --target test`
- Verify test discovery and execution
- Check test output for failures

---

## 1.9 Documentation Generation Setup

**Purpose**: Configure man page generation and API docs

**Files to Create**:
- `/home/lpc123/musiclib/man/musiclib-cli.1` - Man page source
- `/home/lpc123/musiclib/docs/Doxyfile.in` (optional - for API docs)

**Subtasks**:

### Man Page Setup
1. Create man page for `musiclib-cli` in groff format
2. Document all subcommands (rate, mobile, build, etc.)
3. Include examples and exit codes
4. Add man page installation rule to CMake
5. Test rendering: `man ./man/musiclib-cli.1`

### Doxygen Setup (Optional)
1. Find Doxygen package in CMake
2. Create Doxyfile.in template
3. Configure Doxygen to generate HTML/PDF docs
4. Add `make docs` target
5. Exclude build artifacts from doc generation

**Example Man Page Installation**:
```cmake
# Man page installation
find_program(GZIP gzip)
if(GZIP)
    install(FILES ${CMAKE_SOURCE_DIR}/man/musiclib-cli.1
        DESTINATION share/man/man1
        RENAME musiclib-cli.1.gz
        PERMISSIONS OWNER_READ GROUP_READ WORLD_READ
    )
endif()
```

**Validation**:
- Install man page locally
- Test: `man musiclib-cli`
- Verify formatting and content

---

## 1.10 Package Configuration

**Purpose**: Create CMake package config for other projects to use musiclib

**Files to Create**:
- `/home/lpc123/musiclib/cmake/MusicLibConfig.cmake.in`
- `/home/lpc123/musiclib/cmake/MusicLibConfigVersion.cmake.in`

**Subtasks**:
1. Create package config template
2. Export library targets (musiclib_common)
3. Define version compatibility rules
4. Install package config files to:
   - `/usr/lib/cmake/MusicLib/`
5. Test importing from another CMake project

**Example MusicLibConfig.cmake.in**:
```cmake
@PACKAGE_INIT@

include("${CMAKE_CURRENT_LIST_DIR}/MusicLibTargets.cmake")

check_required_components(MusicLib)
```

**Installation**:
```cmake
include(CMakePackageConfigHelpers)

# Generate config file
configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/MusicLibConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfig.cmake
    INSTALL_DESTINATION lib/cmake/MusicLib
)

# Generate version file
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)

# Install config files
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/MusicLibConfigVersion.cmake
    DESTINATION lib/cmake/MusicLib
)

# Export targets
install(EXPORT MusicLibTargets
    FILE MusicLibTargets.cmake
    NAMESPACE MusicLib::
    DESTINATION lib/cmake/MusicLib
)
```

**Validation**:
- Create test project that uses `find_package(MusicLib)`
- Verify it can link against musiclib_common

---

## Summary Checklist

**Core Infrastructure**:
- [ ] 1.1 - Root CMakeLists.txt created
- [ ] 1.2 - Common library CMakeLists.txt created
- [ ] 1.3 - CLI dispatcher CMakeLists.txt created
- [ ] 1.4 - Qt dependency detection configured
- [ ] 1.5 - Compiler flags and options set

**Build & Install**:
- [ ] 1.6 - Installation rules defined
- [ ] 1.7 - Build helper scripts created
- [ ] 1.8 - Testing framework integrated

**Documentation & Packaging**:
- [ ] 1.9 - Man page setup complete
- [ ] 1.10 - CMake package config created

**Validation Steps**:
1. Fresh clone builds successfully: `./scripts/build.sh`
2. Tests pass: `./scripts/build.sh --test`
3. Installation works: `./scripts/build.sh --install`
4. Man page accessible: `man musiclib-cli`
5. Uninstall works: `cd build && sudo cmake --build . --target uninstall`

---

## Next Task Preview

**Task 2: Argument Parser** will build on this foundation by implementing:
- Subcommand routing (rate, mobile, build, tagclean, etc.)
- Option parsing (--help, --version, --config, etc.)
- Positional argument validation
- Help text generation

This CMake infrastructure provides the build foundation for all future development.
