#!/bin/bash

# Clean build artifacts
echo "Cleaning build artifacts..."
rm -rf build/

echo "Removing CMake cache files..."
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "CMakeCache.txt" -delete 2>/dev/null || true
find . -name "cmake_install.cmake" -delete 2>/dev/null || true

echo "Clean complete."
