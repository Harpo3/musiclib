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