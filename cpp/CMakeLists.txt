cmake_minimum_required(VERSION 3.14)
project(ytapis VERSION 1.0.0 LANGUAGES CXX
  DESCRIPTION "Search YouTube and get video metadata — no API key required"
)
# Maintainer: geethudino (Ruthvik)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- libcurl ----------------------------------------------------------
find_package(CURL REQUIRED)

# --- nlohmann/json ----------------------------------------------------
include(FetchContent)
FetchContent_Declare(
    json
    URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz
)
FetchContent_MakeAvailable(json)

# --- header-only library ----------------------------------------------
add_library(ytapis INTERFACE)
target_include_directories(ytapis INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_link_libraries(ytapis INTERFACE
    CURL::libcurl
    nlohmann_json::nlohmann_json
)

# --- executable ----------------------------------------------------------
add_executable(ytapis src/main.cpp)
target_link_libraries(ytapis PRIVATE ytapis)
