# ytapis (Lua)

Pure Lua 5.1+ YouTube scraper – no API key required.

## Quick Start

### Install via LuaRocks

```bash
luarocks install ytapis
```

### Manual Install

```bash
# Clone and require from LUA_PATH
git clone https://github.com/geethudino/ytapis.git
export LUA_PATH="$(pwd)/ytapis/lua/src/?.lua;;"
```

## Usage

### Library

```lua
local ytapis = require("ytapis")

-- Search
local results = ytapis.search("lofi hip hop", 10)
for _, v in ipairs(results) do
  print(v.id, v.title, v.author)
end

-- Trending
local trending = ytapis.search_trending(15, "US", "en")

-- Channel videos
local channel = ytapis.search_channel("UCXuqSBlHAE6Xw-yeJA0Tunw", 10)

-- Playlist
local playlist = ytapis.search_playlist("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")

-- Single video
local video = ytapis.get_video("dQw4w9WgXcQ")
```

### CLI

```bash
lua bin/ytapis.lua search "lofi hip hop" --limit 5
lua bin/ytapis.lua trending --gl US
lua bin/ytapis.lua channel UCXuqSBlHAE6Xw-yeJA0Tunw --limit 10
lua bin/ytapis.lua playlist PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf
lua bin/ytapis.lua video dQw4w9WgXcQ
```

## Result Schema

Each video result contains 19 fields:

| Field | Type | Description |
|-------|------|-------------|
| id | string | Video ID |
| title | string | Video title |
| author | string | Channel name |
| channel_url | string | Channel URL |
| thumbnail | string | Best quality thumbnail URL |
| thumbnails | table | Array of {url, width, height} |
| full_url | string | Full YouTube watch URL |
| embed_url | string | Embeddable iframe URL |
| duration | string | Formatted duration (e.g. "3:45") |
| duration_seconds | number | Duration in seconds |
| view_count | string | Formatted view count |
| view_count_raw | number | Raw view count |
| published_time | string | Relative time (e.g. "2 years ago") |
| description | string | Video description snippet |
| channel_avatar | string | Channel avatar URL |
| is_live | boolean | Currently live |
| is_upcoming | boolean | Scheduled for live |
| is_verified | boolean | Channel is verified |

## Dependencies

- **socket.http** (recommended) – via `luasocket`
- **curl** (fallback) – automatically used if luasocket is unavailable

## License

MIT
