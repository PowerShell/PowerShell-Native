cmake_minimum_required(VERSION 2.8.11)
project(PSL-NATIVE)

# Can't use add_compile_options with 2.8.11
set(CMAKE_BUILD_TYPE "Release")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11 -Wall -Werror -fstack-protector-strong -fpie -D_FORTIFY_SOURCE=2 -gdwarf-5")

if (${CMAKE_SYSTEM_NAME} MATCHES "Linux" OR "FreeBSD")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,relro,-z,now")
elseif (${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl")
endif()

set(LIBRARY_OUTPUT_PATH "${PROJECT_SOURCE_DIR}/../powershell-unix")

if (CMAKE_SYSTEM_PROCESSOR MATCHES "arm*")
    message(STATUS "Building for ARM, no tests")
    add_subdirectory(src)
else ()
    # test in BUILD_DIR
    message(STATUS "Tests enabled")
    enable_testing()
    add_subdirectory(src)
    add_subdirectory(test)
endif ()
