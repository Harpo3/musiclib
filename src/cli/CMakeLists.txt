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
