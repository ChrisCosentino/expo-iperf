cmake_minimum_required(VERSION 3.10)
project(iperf3)

# Set C++ standard
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_C_STANDARD 99)

# Define Android-specific flags
add_definitions(-DHAVE_PTHREAD)

# Add iperf3 source files
set(IPERF3_SOURCES
        iperf3/src/iperf_api.c
        iperf3/src/iperf_error.c
        iperf3/src/iperf_auth.c
        iperf3/src/iperf_client_api.c
        iperf3/src/iperf_server_api.c
        iperf3/src/iperf_tcp.c
        iperf3/src/iperf_udp.c
        iperf3/src/iperf_sctp.c
        iperf3/src/iperf_util.c
        iperf3/src/iperf_locale.c
        iperf3/src/iperf_time.c
        iperf3/src/iperf_pthread.c
        iperf3/src/dscp.c
        iperf3/src/net.c
        iperf3/src/tcp_info.c
        iperf3/src/timer.c
        iperf3/src/units.c
        iperf3/src/cjson.c
)

# Create shared library
add_library(iperf3 SHARED
        ${IPERF3_SOURCES}
        iperf_jni.cpp
)

# Include directories
target_include_directories(iperf3 PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/iperf3/src
)

# Link libraries
target_link_libraries(iperf3
        log
        android
        atomic
        m
)