#!/usr/bin/env lua
-- ytapis CLI – YouTube search from the command line (pure Lua 5.1+)
-- Usage: lua ytapis.lua <subcommand> [options]

local ytapis = require("ytapis")
local json_encode = require("ytapis.json").encode or require("json").encode

local function json_encode_safe(obj)
  if json_encode then return json_encode(obj) end
  -- Fallback manual JSON encoder
  local function encode(val)
    if type(val) == "nil" then return "null"
    elseif type(val) == "boolean" then return val and "true" or "false"
    elseif type(val) == "number" then return tostring(val)
    elseif type(val) == "string" then
      return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    elseif type(val) == "table" then
      local parts = {}
      for k, v in pairs(val) do
        parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(v)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
  end
  return encode(obj)
end

local function print_help()
  io.stderr:write([[
ytapis – YouTube search via pure Lua scraping

USAGE:
  lua ytapis.lua <subcommand> [options]

SUBCOMMANDS:
  search <query>        Search YouTube for videos
  trending              Get trending videos
  channel <channel_id>  Get videos from a channel
  playlist <playlist_id> Get videos from a playlist
  video <video_id>      Get metadata for a single video

OPTIONS:
  --limit, -l <n>       Max results (default: 15, max: 50)
  --gl <country_code>   Set geographic location (e.g. US, GB)
  --hl <language_code>  Set host language (e.g. en, fr)
  --version, -v         Show version
  --help, -h            Show this help

EXAMPLES:
  lua ytapis.lua search "lofi hip hop" --limit 5
  lua ytapis.lua trending --gl US
  lua ytapis.lua channel UCXuqSBlHAE6Xw-yeJA0Tunw --limit 10
  lua ytapis.lua playlist PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf
  lua ytapis.lua video dQw4w9WgXcQ
]])
  os.exit(0)
end

local function print_version()
  print("ytapis v2.0.0 (Lua)")
  os.exit(0)
end

-- Parse arguments
local args = {}
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "--help" or a == "-h" then
    print_help()
  elseif a == "--version" or a == "-v" then
    print_version()
  elseif a == "--limit" or a == "-l" then
    i = i + 1
    args.limit = tonumber(arg[i]) or 15
  elseif a == "--gl" then
    i = i + 1
    args.gl = arg[i]
  elseif a == "--hl" then
    i = i + 1
    args.hl = arg[i]
  elseif not args.subcommand then
    args.subcommand = a
  elseif not args.query then
    args.query = a
  else
    args.query = args.query .. " " .. a
  end
  i = i + 1
end

if not args.subcommand then
  io.stderr:write("Error: No subcommand specified. Use --help for usage.\n")
  os.exit(1)
end

local subcommand = args.subcommand:lower()
local limit = args.limit or 15
local gl = args.gl
local hl = args.hl

local ok, results = pcall(function()
  if subcommand == "search" then
    if not args.query or args.query == "" then
      io.stderr:write("Error: search requires a query string\n")
      os.exit(1)
    end
    return ytapis.search(args.query, limit, gl, hl)
  elseif subcommand == "trending" then
    return ytapis.search_trending(limit, gl, hl)
  elseif subcommand == "channel" then
    if not args.query or args.query == "" then
      io.stderr:write("Error: channel requires a channel ID\n")
      os.exit(1)
    end
    return ytapis.search_channel(args.query, limit, gl, hl)
  elseif subcommand == "playlist" then
    if not args.query or args.query == "" then
      io.stderr:write("Error: playlist requires a playlist ID\n")
      os.exit(1)
    end
    return ytapis.search_playlist(args.query, limit, gl, hl)
  elseif subcommand == "video" then
    if not args.query or args.query == "" then
      io.stderr:write("Error: video requires a video ID\n")
      os.exit(1)
    end
    local video = ytapis.get_video(args.query)
    return video and { video } or {}
  else
    io.stderr:write("Error: Unknown subcommand '" .. args.subcommand .. "'. Use --help for usage.\n")
    os.exit(1)
  end
end)

if not ok then
  io.stderr:write("Search failed: " .. tostring(results) .. "\n")
  os.exit(1)
end

print(json_encode_safe(results))
