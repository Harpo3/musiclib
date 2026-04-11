# Testing
find_package(Qt${QT_VERSION_MAJOR} COMPONENTS Test REQUIRED)
# Helper function to add tests
function(add_musiclib_test TEST_NAME)
    add_executable(${TEST_NAME} ${TEST_NAME}.cpp)
    target_link_libraries(${TEST_NAME}
        PRIVATE
            Qt${QT_VERSION_MAJOR}::Test
    )
    add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endfunction()

# Individual tests — add here as they are written
# add_musiclib_test(test_utils)
