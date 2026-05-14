# Invoked via: cmake -DSOURCE_DIR=<path> -P check_dsv_schema.cmake
# Fails with FATAL_ERROR if config/dsv_schema.conf and the TrackColumn enum are out of sync.

if(NOT DEFINED SOURCE_DIR)
    message(FATAL_ERROR "SOURCE_DIR must be defined. Pass -DSOURCE_DIR=<project-root>.")
endif()

file(STRINGS "${SOURCE_DIR}/config/dsv_schema.conf" DSV_COLUMNS)

file(READ "${SOURCE_DIR}/src/gui/librarymodel.h" HEADER_CONTENT)

string(REGEX MATCH "enum class TrackColumn : int \\{([^}]*)\\}" _MATCH "${HEADER_CONTENT}")
set(ENUM_BODY "${CMAKE_MATCH_1}")

string(REGEX MATCHALL "([A-Za-z][A-Za-z0-9]*)[ \t]*=[ \t]*[0-9]+" ENUM_ENTRIES "${ENUM_BODY}")

set(ENUM_COLUMNS "")
foreach(ENTRY ${ENUM_ENTRIES})
    string(REGEX REPLACE "[ \t]*=[ \t]*[0-9]+" "" COL_NAME "${ENTRY}")
    string(STRIP "${COL_NAME}" COL_NAME)
    if(NOT COL_NAME STREQUAL "COUNT")
        list(APPEND ENUM_COLUMNS "${COL_NAME}")
    endif()
endforeach()

list(LENGTH DSV_COLUMNS DSV_COUNT)
list(LENGTH ENUM_COLUMNS ENUM_COUNT)

if(NOT DSV_COUNT EQUAL ENUM_COUNT)
    message(FATAL_ERROR
        "DSV schema / TrackColumn mismatch: "
        "dsv_schema.conf has ${DSV_COUNT} column(s), TrackColumn enum has ${ENUM_COUNT}.")
endif()

set(_MISMATCH FALSE)
math(EXPR _LAST "${DSV_COUNT} - 1")
foreach(I RANGE 0 ${_LAST})
    list(GET DSV_COLUMNS ${I} DSV_COL)
    list(GET ENUM_COLUMNS ${I} ENUM_COL)
    if(NOT DSV_COL STREQUAL ENUM_COL)
        message(STATUS "  [${I}] dsv_schema.conf='${DSV_COL}'  TrackColumn='${ENUM_COL}'")
        set(_MISMATCH TRUE)
    endif()
endforeach()

if(_MISMATCH)
    message(FATAL_ERROR "dsv_schema.conf and TrackColumn enum are out of sync (see above).")
endif()

message(STATUS "DSV schema check passed: ${DSV_COUNT} columns match TrackColumn enum.")
