#!/bin/bash
#
# temp_diagnose_kconfigxt.sh — Run this from your musiclib project root.
# It checks KConfigXT prerequisites and attempts a cmake configure
# to capture the exact error output.
#
# Usage:  cd ~/musiclib && bash temp_diagnose_kconfigxt.sh
#

echo "═══════════════════════════════════════════════════"
echo " MusicLib KConfigXT Diagnostic"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Check required packages ──
echo "── Step 1: Package Check ──"
echo ""

check_pkg() {
    local pkg="$1"
    if pacman -Qi "$pkg" &>/dev/null; then
        local ver=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Version" | awk '{print $3}')
        echo "  [OK] $pkg  ($ver)"
    else
        echo "  [MISSING] $pkg"
    fi
}

echo "KDE Frameworks 6 packages:"
check_pkg "kconfig"
check_pkg "kconfigwidgets"
check_pkg "kio"
check_pkg "ki18n"
check_pkg "kcoreaddons"
check_pkg "kxmlgui"
check_pkg "kwidgetsaddons"
check_pkg "kwindowsystem"
check_pkg "extra-cmake-modules"

echo ""
echo "Build tools:"
check_pkg "cmake"
check_pkg "qt6-base"
check_pkg "qt6-tools"

echo ""

# ── 2. Check kconfig_compiler binary ──
echo "── Step 2: kconfig_compiler_kf6 Binary ──"
echo ""

COMPILER_PATHS=(
    "/usr/lib/kf6/kconfig_compiler_kf6"
    "/usr/lib/libexec/kf6/kconfig_compiler_kf6"
    "/usr/bin/kconfig_compiler_kf6"
)

FOUND_COMPILER=""
for p in "${COMPILER_PATHS[@]}"; do
    if [ -x "$p" ]; then
        echo "  [OK] Found: $p"
        FOUND_COMPILER="$p"
        break
    fi
done

if [ -z "$FOUND_COMPILER" ]; then
    echo "  [MISSING] kconfig_compiler_kf6 not found in standard locations"
    echo "  Searching system-wide..."
    FOUND=$(find /usr -name "kconfig_compiler_kf6" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        echo "  [OK] Found at: $FOUND"
        FOUND_COMPILER="$FOUND"
    else
        echo "  [FAIL] kconfig_compiler_kf6 is not installed."
        echo "         Install with: sudo pacman -S kconfig"
    fi
fi

echo ""

# ── 3. Check CMake module files ──
echo "── Step 3: KF6Config CMake Modules ──"
echo ""

CMAKE_SEARCH_DIRS=(
    "/usr/lib/cmake/KF6Config"
    "/usr/lib64/cmake/KF6Config"
    "/usr/share/cmake/Modules"
)

for d in "${CMAKE_SEARCH_DIRS[@]}"; do
    if [ -d "$d" ]; then
        echo "  [OK] Found: $d"
        echo "  Contents:"
        ls -1 "$d"/*.cmake 2>/dev/null | sed 's/^/    /'
        
        # Check specifically for the macros file
        if [ -f "$d/KF6ConfigMacros.cmake" ]; then
            echo ""
            echo "  Checking for kconfig_target_kcfg_file in macros..."
            if grep -q "kconfig_target_kcfg_file" "$d/KF6ConfigMacros.cmake"; then
                echo "  [OK] kconfig_target_kcfg_file() is available"
            else
                echo "  [INFO] kconfig_target_kcfg_file() NOT found"
                echo "         Your KF6Config version only supports kconfig_add_kcfg_files()"
            fi

            echo ""
            echo "  Checking for kconfig_add_kcfg_files in macros..."
            if grep -q "kconfig_add_kcfg_files" "$d/KF6ConfigMacros.cmake"; then
                echo "  [OK] kconfig_add_kcfg_files() is available"
            else
                echo "  [WARN] kconfig_add_kcfg_files() NOT found either"
            fi
        fi
        break
    fi
done

echo ""

# ── 4. Check KF6ConfigWidgets CMake modules ──
echo "── Step 4: KF6ConfigWidgets CMake Modules ──"
echo ""

for d in "/usr/lib/cmake/KF6ConfigWidgets" "/usr/lib64/cmake/KF6ConfigWidgets"; do
    if [ -d "$d" ]; then
        echo "  [OK] Found: $d"
        break
    fi
done

# ── 5. Check KF6KIO CMake modules ──
echo ""
echo "── Step 5: KF6KIO CMake Modules ──"
echo ""

for d in "/usr/lib/cmake/KF6KIO" "/usr/lib64/cmake/KF6KIO"; do
    if [ -d "$d" ]; then
        echo "  [OK] Found: $d"
        break
    fi
done

echo ""

# ── 6. Attempt cmake configure ──
echo "── Step 6: CMake Configure Test ──"
echo ""

if [ ! -f "CMakeLists.txt" ]; then
    echo "  [SKIP] Not in musiclib project root (no CMakeLists.txt found)"
    echo "  Run this script from ~/musiclib"
    exit 1
fi

# Clean build attempt
BUILD_DIR="build_diag_test"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "  Running cmake configure with -DBUILD_GUI=ON ..."
echo "  Build directory: $BUILD_DIR"
echo ""

cmake -S . -B "$BUILD_DIR" \
    -DBUILD_GUI=ON \
    -DENABLE_TESTING=OFF \
    -DENABLE_WARNINGS_AS_ERRORS=OFF \
    2>&1 | tee "$BUILD_DIR/cmake_output.log"

CMAKE_EXIT=$?
echo ""

if [ $CMAKE_EXIT -ne 0 ]; then
    echo "  [FAIL] CMake configure failed (exit code $CMAKE_EXIT)"
    echo "  Full output saved to: $BUILD_DIR/cmake_output.log"
else
    echo "  [OK] CMake configure succeeded"
    echo ""
    echo "  Attempting build..."
    echo ""
    
    cmake --build "$BUILD_DIR" -- -j$(nproc) 2>&1 | tee "$BUILD_DIR/build_output.log"
    BUILD_EXIT=$?
    
    echo ""
    if [ $BUILD_EXIT -ne 0 ]; then
        echo "  [FAIL] Build failed (exit code $BUILD_EXIT)"
        echo "  Full output saved to: $BUILD_DIR/build_output.log"
        
        # Show the specific error
        echo ""
        echo "  ── Last 30 lines of build output: ──"
        tail -30 "$BUILD_DIR/build_output.log"
    else
        echo "  [OK] Build succeeded!"
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo " Diagnostic Complete"
echo " Log files in: $BUILD_DIR/"
echo "═══════════════════════════════════════════════════"
