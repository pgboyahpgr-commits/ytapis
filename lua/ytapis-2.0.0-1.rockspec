package = "ytapis"
version = "2.0.0-1"

source = {
  url = "git+https://github.com/geethudino/ytapis.git",
  branch = "master",
}

description = {
  summary = "Pure Lua YouTube scraper – search, trending, channels, playlists, and video metadata",
  detailed = [[
ytapis is a zero-dependency YouTube data scraper written in pure Lua 5.1+.
It parses YouTube's ytInitialData JSON from HTML pages to extract video
metadata without any API key.

Features:
  - Search YouTube videos
  - Get trending videos
  - List channel videos
  - Extract playlist contents
  - Get single video metadata
  - Pure Lua JSON parser (no external JSON dependency)
  - HTTP via socket.http with curl fallback
  - CLI tool with subcommands
  - Thumbnail quality scoring
  - OEmbed enrichment fallback
  ]],
  homepage = "https://github.com/geethudino/ytapis",
  license = "MIT",
  maintainer = "Geethu Dino <geethudino@users.noreply.github.com>",
}

dependencies = {
  "lua >= 5.1",
}

supported_platforms = { "linux", "macosx", "mingw32", "win32", "windows" }

build = {
  type = "builtin",
  modules = {
    ytapis = "src/ytapis.lua",
  },
  install = {
    bin = {
      ytapis = "bin/ytapis.lua",
    },
  },
}
