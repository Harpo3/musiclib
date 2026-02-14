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
