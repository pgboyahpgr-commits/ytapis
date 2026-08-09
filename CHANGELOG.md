# Changelog

## 2.0.0 (2026-08-09)

### Breaking

- `search()` now returns `SearchResponse` with `results` + `continuation`
- `VideoResult` has 19 fields (was 6)
- Python `search()` returns `VideoResult` objects, use `search_dicts()` for dicts

### Added

- 11 language support (TS, Python, Go, Dart, C#, PHP, Kotlin, C++, Lua)
- YouTube Shorts search
- Channel metadata (subscribers, banner, description, links)
- Video comments with threaded replies
- Related video recommendations
- Live stream viewer count + status
- Transcript/caption extraction
- LRU cache with TTL
- Smart retry with exponential backoff
- Multi-region search (gl/hl params)
- REST API server (`npx ytapis serve`)
- MCP server with 5 tools
- Cloudflare Worker demo
- Docker deployment
- GitHub Pages demo
- Browser extension
- Benchmark suite
- gRPC protobuf definition

### Fixed

- Dart VideoResult constructor defaults
- Go concurrent oEmbed fetching
- MCP server name typo
- Node.js server.js path
- Flutter counter app test artifact
- Thumbnail quality now prefers `maxresdefault`
