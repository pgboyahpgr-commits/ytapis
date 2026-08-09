# ytapis (C++17)

Header-only C++17 YouTube search engine. Uses **libcurl** for HTTP and **nlohmann/json** for JSON parsing.

## Dependencies

- C++17 compiler
- libcurl (with dev headers)
- nlohmann/json (fetched automatically via CMake)

## Build & Install

```cmake
# CMakeLists.txt in your project
add_subdirectory(path/to/ytapis/cpp)
target_link_libraries(your_target PRIVATE ytapis)
```

## Quick Start

```cpp
#include <ytapis/ytapis.hpp>
#include <iostream>

int main() {
    auto resp = ytapis::search("c++ tutorial", 5);
    for (const auto& v : resp.results) {
        std::cout << v.title << " - " << v.author << "\n";
    }

    if (!resp.continuation.empty()) {
        auto next = ytapis::search_continue(
            resp.continuation, 5, resp.api_key);
        for (const auto& v : next.results) {
            std::cout << v.title << " (page 2)\n";
        }
    }

    auto vid = ytapis::get_video("dQw4w9WgXcQ");
    std::cout << vid.description << "\n";
}
```

## API

### `ytapis::search(query, limit=15) -> SearchResponse`

Scrapes youtube.com/results. Extracts `var ytInitialData` via brace counting and parses `videoRenderer` objects. Falls back to oEmbed for enrichment when metadata is thin.

### `ytapis::get_video(id) -> VideoResult`

Fetches a watch page, extracts `ytInitialPlayerResponse`/`ytInitialData`. Falls back to oEmbed.

### `ytapis::search_continue(continuation, limit=15, api_key="", context_json="") -> SearchResponse`

Posts to the InnerTube API (`youtubei/v1/search`) with the continuation token from a previous search response. Requires a valid api_key (a default fallback is provided).

## Structures

- **Thumbnail** — `url`, `width`, `height`
- **VideoResult** — 17 fields including `id`, `title`, `author`, `duration_seconds`, `view_count_raw`, `is_live`, `is_upcoming`, `is_verified`, `thumbnails`, etc.
- **SearchResponse** — `results`, `continuation`, `api_key`

All three support `NLOHMANN_DEFINE_TYPE_INTRUSIVE` for easy JSON round-tripping.

## Error Handling

All network/parse errors throw `std::runtime_error`. Results that cannot be fully parsed are silently skipped; `get_video` always returns a fallback result with at least the thumbnail and URL populated.
