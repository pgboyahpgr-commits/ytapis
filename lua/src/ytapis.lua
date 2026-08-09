-- ytapis.lua – Pure Lua 5.1+ YouTube scraper library
-- No external dependencies required (socket.http for networking)
-- License: MIT

local ytapis = {}
ytapis._VERSION = "2.0.0"

-- ─── Dependencies ───────────────────────────────────────────────────────────

local socket_http
local ok, http = pcall(require, "socket.http")
if ok then
  socket_http = http
else
  -- Fallback: use io.popen with curl
  socket_http = nil
end

local function fetch(url, postdata)
  local body, status, headers
  if socket_http then
    local req = {
      url = url,
      method = "GET",
      headers = {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36",
        ["Accept-Language"] = "en-US,en;q=0.9",
      },
      create = function(t)
        local s, e = socket_http.PROXY or "http.github.com"
        return socket_http.tcp()
      end,
    }
    if postdata then
      req.method = "POST"
      req.source = ltn12.source.string(postdata)
      if not req.headers["Content-Type"] then
        req.headers["Content-Type"] = "application/json"
      end
      req.headers["Content-Length"] = tostring(#postdata)
    end
    body, status = socket_http.request(req)
    if status ~= 200 then
      return nil
    end
    return body
  else
    -- curl fallback
    local cmd = 'curl -s -L --max-time 15 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36"'
    if postdata then
      cmd = cmd .. ' -X POST -H "Content-Type: application/json" -d "' .. postdata:gsub('"', '\\"') .. '"'
    end
    cmd = cmd .. ' "' .. url .. '"'
    local f = io.popen(cmd, "r")
    if not f then return nil end
    body = f:read("*a")
    f:close()
    return body
  end
end

-- ─── Pure Lua JSON Parser (brace-counting + manual decoding) ─────────────────

local json_parser = {}

function json_parser.decode(str)
  if not str or str == "" then return nil end
  str = str:match("^%s*(.-)%s*$")
  if str == "" then return nil end

  local pos = 1
  local len = #str

  local function skip_ws()
    while pos <= len do
      local c = str:sub(pos, pos)
      if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
        break
      end
      pos = pos + 1
    end
  end

  local function parse_value()
    skip_ws()
    if pos > len then return nil end
    local c = str:sub(pos, pos)
    if c == "{" then return parse_object() end
    if c == "[" then return parse_array() end
    if c == '"' then return parse_string() end
    if c == "t" or c == "f" then return parse_bool() end
    if c == "n" then return parse_null() end
    return parse_number()
  end

  local function parse_object()
    pos = pos + 1
    local obj = {}
    skip_ws()
    if str:sub(pos, pos) == "}" then
      pos = pos + 1
      return obj
    end
    while true do
      skip_ws()
      local key = parse_string()
      skip_ws()
      if str:sub(pos, pos) ~= ":" then return nil end
      pos = pos + 1
      local val = parse_value()
      if val == nil then return nil end
      obj[key] = val
      skip_ws()
      local c = str:sub(pos, pos)
      if c == "}" then
        pos = pos + 1
        return obj
      end
      if c ~= "," then return nil end
      pos = pos + 1
    end
  end

  local function parse_array()
    pos = pos + 1
    local arr = {}
    skip_ws()
    if str:sub(pos, pos) == "]" then
      pos = pos + 1
      return arr
    end
    local idx = 1
    while true do
      local val = parse_value()
      if val == nil then return nil end
      arr[idx] = val
      idx = idx + 1
      skip_ws()
      local c = str:sub(pos, pos)
      if c == "]" then
        pos = pos + 1
        return arr
      end
      if c ~= "," then return nil end
      pos = pos + 1
    end
  end

  local function parse_string()
    pos = pos + 1
    local chunks = {}
    while pos <= len do
      local c = str:sub(pos, pos)
      if c == "\\" then
        pos = pos + 1
        c = str:sub(pos, pos)
        if c == '"' then
          chunks[#chunks + 1] = '"'
        elseif c == "\\" then
          chunks[#chunks + 1] = "\\"
        elseif c == "/" then
          chunks[#chunks + 1] = "/"
        elseif c == "b" then
          chunks[#chunks + 1] = "\b"
        elseif c == "f" then
          chunks[#chunks + 1] = "\f"
        elseif c == "n" then
          chunks[#chunks + 1] = "\n"
        elseif c == "r" then
          chunks[#chunks + 1] = "\r"
        elseif c == "t" then
          chunks[#chunks + 1] = "\t"
        elseif c == "u" then
          local hex = str:sub(pos + 1, pos + 4)
          local codepoint = tonumber(hex, 16)
          if codepoint and codepoint < 0x80 then
            chunks[#chunks + 1] = string.char(codepoint)
          else
            chunks[#chunks + 1] = "?"
          end
          pos = pos + 4
        end
        pos = pos + 1
      elseif c == '"' then
        pos = pos + 1
        return table.concat(chunks)
      else
        chunks[#chunks + 1] = c
        pos = pos + 1
      end
    end
    return nil
  end

  local function parse_bool()
    if str:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif str:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    end
    return nil
  end

  local function parse_null()
    if str:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return json_parser.null
    end
    return nil
  end

  local function parse_number()
    local start = pos
    if str:sub(pos, pos) == "-" then pos = pos + 1 end
    while pos <= len and str:sub(pos, pos):match("[0-9]") do pos = pos + 1 end
    if pos <= len and str:sub(pos, pos) == "." then
      pos = pos + 1
      while pos <= len and str:sub(pos, pos):match("[0-9]") do pos = pos + 1 end
    end
    if pos <= len and str:sub(pos, pos):lower() == "e" then
      pos = pos + 1
      if pos <= len and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then
        pos = pos + 1
      end
      while pos <= len and str:sub(pos, pos):match("[0-9]") do pos = pos + 1 end
    end
    local numstr = str:sub(start, pos - 1)
    return tonumber(numstr)
  end

  json_parser.null = {}
  local result = parse_value()
  return result
end

function json_parser.encode(obj)
  if type(obj) == "nil" then
    return "null"
  elseif type(obj) == "boolean" then
    return obj and "true" or "false"
  elseif type(obj) == "number" then
    return tostring(obj)
  elseif type(obj) == "string" then
    return '"' .. obj:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
  elseif type(obj) == "table" then
    if obj == json_parser.null then
      return "null"
    end
    local is_array = true
    local max_idx = 0
    for k in pairs(obj) do
      if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
        is_array = false
        break
      end
      if k > max_idx then max_idx = k end
    end
    if max_idx == 0 and next(obj) == nil then
      is_array = true
    end
    if is_array and max_idx > 0 then
      local parts = {}
      for i = 1, max_idx do
        parts[i] = json_parser.encode(obj[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, v in pairs(obj) do
      parts[#parts + 1] = json_parser.encode(tostring(k)) .. ":" .. json_parser.encode(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

json = json_parser

-- ─── URL Encoding ───────────────────────────────────────────────────────────

local function urlencode(s)
  if not s then return "" end
  s = s:gsub("\n", "\r\n")
  s = s:gsub("([^%w _%.%\\%-])", function(c)
    return string.format("%%%02X", string.byte(c, 1))
  end)
  s = s:gsub(" ", "+")
  return s
end

-- ─── ytInitialData Extraction ───────────────────────────────────────────────

local function extract_json(html, prefix)
  local idx = html:find(prefix, 1, true)
  if not idx then return nil end
  local start = html:find("{", idx, true)
  if not start then return nil end
  local depth = 0
  local in_string = false
  local escaped = false
  for i = start, #html do
    local ch = html:sub(i, i)
    if escaped then
      escaped = false
    elseif ch == "\\" then
      escaped = true
    elseif ch == '"' then
      in_string = not in_string
    elseif not in_string then
      if ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then
          local json_str = html:sub(start, i)
          local ok, result = pcall(function() return json.decode(json_str) end)
          if ok and result then return result end
        end
      end
    end
  end
  return nil
end

-- ─── Text Extraction from Runs ──────────────────────────────────────────────

local function extract_runs(runs)
  if not runs or type(runs) ~= "table" then return "" end
  local parts = {}
  for _, r in ipairs(runs) do
    if r and type(r) == "table" and r.text then
      parts[#parts + 1] = r.text
    end
  end
  return table.concat(parts)
end

-- ─── Duration Parsing ───────────────────────────────────────────────────────

local function parse_duration(text)
  if not text or text == "" then return "", 0 end
  local parts = {}
  for part in text:gmatch("([%d]+)") do
    parts[#parts + 1] = tonumber(part)
  end
  if #parts == 0 then return text, 0 end
  if #parts == 3 then
    return text, parts[1] * 3600 + parts[2] * 60 + parts[3]
  elseif #parts == 2 then
    return text, parts[1] * 60 + parts[2]
  else
    return text, parts[1]
  end
end

-- ─── View Count Parsing ─────────────────────────────────────────────────────

local function parse_view_count(text)
  if not text or text == "" then return "", 0 end
  local cleaned = text:match("[0-9.KMBkmb]+")
  if not cleaned then cleaned = text end
  local num = tonumber(cleaned:gsub("[KMBkmb]", ""))
  if not num then return text, 0 end
  local upper = cleaned:upper()
  local mult = 1
  if upper:find("B", 1, true) then
    mult = 1000000000
  elseif upper:find("M", 1, true) then
    mult = 1000000
  elseif upper:find("K", 1, true) then
    mult = 1000
  end
  local raw = math.floor(num * mult + 0.5)
  return text, raw
end

-- ─── Thumbnail Quality Scoring ──────────────────────────────────────────────

local function thumbnail_quality_score(url)
  if not url or url == "" then return 0 end
  if url:find("maxresdefault", 1, true) then return 1280 end
  if url:find("sddefault", 1, true) then return 640 end
  if url:find("hqdefault", 1, true) then return 480 end
  if url:find("mqdefault", 1, true) then return 320 end
  if url:find("default", 1, true) then return 120 end
  return 0
end

local function best_thumbnail(thumbnails)
  if not thumbnails or #thumbnails == 0 then return "" end
  local best = thumbnails[1]
  local best_score = thumbnail_quality_score(best.url or "")
  for _, t in ipairs(thumbnails) do
    local score
    if t.width and t.width > 0 then
      score = t.width
    else
      score = thumbnail_quality_score(t.url or "")
    end
    if score > best_score then
      best = t
      best_score = score
    end
  end
  return best.url or ""
end

-- ─── Badge Checks ────────────────────────────────────────────────────────────

local function badge_contains(badges, needle)
  if not badges then return false end
  local upper = needle:upper()
  for _, b in ipairs(badges) do
    if type(b) == "table" then
      local style = (b.metadataBadgeRenderer or {}).style or ""
      local label = (b.metadataBadgeRenderer or {}).label or ""
      if style:upper():find(upper, 1, true) or label:upper():find(upper, 1, true) then
        return true
      end
    end
  end
  return false
end

-- ─── Fallback VideoResult ────────────────────────────────────────────────────

local function fallback_result(id)
  return {
    id = id,
    title = "Video " .. id,
    author = "Unknown Author",
    channel_url = "",
    thumbnail = "https://i.ytimg.com/vi/" .. id .. "/hqdefault.jpg",
    thumbnails = { { url = "https://i.ytimg.com/vi/" .. id .. "/hqdefault.jpg", width = 480, height = 360 } },
    full_url = "https://www.youtube.com/watch?v=" .. id,
    embed_url = "https://www.youtube.com/embed/" .. id .. "?rel=0",
    duration = "",
    duration_seconds = 0,
    view_count = "",
    view_count_raw = 0,
    published_time = "",
    description = "",
    channel_avatar = "",
    is_live = false,
    is_upcoming = false,
    is_verified = false,
  }
end

-- ─── Video Renderer Parser (19 fields) ──────────────────────────────────────

local function parse_video_renderer(vr)
  if not vr or type(vr) ~= "table" then return nil end
  local vid = vr.videoId
  if not vid or type(vid) ~= "string" or vid == "" then return nil end

  local ok, result = pcall(function()
    local title = extract_runs((vr.title or {}).runs)
    local author = extract_runs((vr.ownerText or {}).runs)
    local channel_url = ""
    local owner_runs = (vr.ownerText or {}).runs or {}
    if #owner_runs > 0 and owner_runs[1] then
      local ep = (owner_runs[1].navigationEndpoint or {}).browseEndpoint or {}
      channel_url = ep.canonicalBaseUrl or ""
    end

    local raw_thumbs = (vr.thumbnail or {}).thumbnails or {}
    local thumbs = {}
    for _, t in ipairs(raw_thumbs) do
      thumbs[#thumbs + 1] = {
        url = t.url or "",
        width = t.width or 0,
        height = t.height or 0,
      }
    end
    local thumbnail = best_thumbnail(raw_thumbs)

    local len = vr.lengthText or {}
    local dur_text = len.simpleText or extract_runs(len.runs) or ""
    local duration_str, duration_sec = parse_duration(dur_text)

    local vc = vr.viewCountText or {}
    local vc_text = vc.simpleText or extract_runs(vc.runs) or ""
    local view_str, view_raw = parse_view_count(vc_text)

    local published = (vr.publishedTimeText or {}).simpleText or ""

    local desc_runs = nil
    local dms = vr.detailedMetadataSnippets or {}
    if #dms > 0 and dms[1] then
      desc_runs = (dms[1].snippetText or {}).runs
    end
    if not desc_runs then
      desc_runs = (vr.descriptionSnippet or {}).runs
    end
    local description = extract_runs(desc_runs)

    local ct_renderer = vr.channelThumbnailSupportedRenderers or {}
    local ct_link = ct_renderer.channelThumbnailWithLinkRenderer or {}
    local ch_thumbs = (ct_link.thumbnail or {}).thumbnails
    local channel_avatar = ""
    if ch_thumbs then
      channel_avatar = best_thumbnail(ch_thumbs)
    end

    local badges = vr.badges or {}

    local fb = fallback_result(vid)

    return {
      id = vid,
      title = (title and title ~= "") and title or fb.title,
      author = (author and author ~= "") and author or fb.author,
      channel_url = channel_url,
      thumbnail = (thumbnail and thumbnail ~= "") and thumbnail or fb.thumbnail,
      thumbnails = (#thumbs > 0) and thumbs or fb.thumbnails,
      full_url = fb.full_url,
      embed_url = fb.embed_url,
      duration = duration_str,
      duration_seconds = duration_sec,
      view_count = view_str,
      view_count_raw = view_raw,
      published_time = published,
      description = description,
      channel_avatar = channel_avatar,
      is_live = badge_contains(badges, "LIVE"),
      is_upcoming = badge_contains(badges, "UPCOMING"),
      is_verified = badge_contains(badges, "VERIFIED"),
    }
  end)

  if ok and result then return result end
  return nil
end

-- ─── OEmbed Enrichment ──────────────────────────────────────────────────────

local function enrich_oembed(vid)
  local ok, result = pcall(function()
    local url = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=" .. vid .. "&format=json"
    local body = fetch(url)
    if not body then return {} end
    local data = json.decode(body)
    return {
      title = (data or {}).title or "",
      author = (data or {}).author_name or "",
      thumbnail = (data or {}).thumbnail_url or "",
    }
  end)
  if ok and result then return result end
  return { title = "", author = "", thumbnail = "" }
end

-- ─── Search Result Parsing ──────────────────────────────────────────────────

local function parse_search_results(data, limit)
  local results = {}
  local continuation = nil
  local ok, _ = pcall(function()
    local contents = (((((data or {}).contents or {}).twoColumnSearchResultsRenderer or {}).primaryContents or {}).sectionListRenderer or {}).contents or {})
    for _, section in ipairs(contents) do
      if #results >= limit then break end
      if section.itemSectionRenderer then
        for _, item in ipairs(section.itemSectionRenderer.contents or {}) do
          if #results >= limit then break end
          if item.videoRenderer then
            local vr = parse_video_renderer(item.videoRenderer)
            if vr then
              results[#results + 1] = vr
            end
          end
        end
      end
      if section.continuationItemRenderer then
        local ep = (section.continuationItemRenderer.continuationEndpoint or {}).continuationCommand or {}
        continuation = ep.token
      end
    end
  end)
  return results, continuation
end

-- ─── Trending Result Parsing ─────────────────────────────────────────────────

local function parse_trending_results(data, limit)
  local results = {}
  local continuation = nil
  pcall(function()
    local tabs = (((data or {}).contents or {}).twoColumnBrowseResultsRenderer or {}).tabs or {}
    for _, tab in ipairs(tabs) do
      local contents = ((((tab or {}).tabRenderer or {}).content or {}).sectionListRenderer or {}).contents or {}
      if #contents > 0 then
        for _, section in ipairs(contents) do
          if #results >= limit then break end
          if section.itemSectionRenderer then
            for _, item in ipairs(section.itemSectionRenderer.contents or {}) do
              if #results >= limit then break end
              if item.videoRenderer then
                local vr = parse_video_renderer(item.videoRenderer)
                if vr then results[#results + 1] = vr end
              end
            end
          end
          if section.shelfRenderer then
            local shelf_items = (((section.shelfRenderer.content or {}).expandedShelfContentsRenderer or {}).items)
            if not shelf_items or #shelf_items == 0 then
              shelf_items = (((section.shelfRenderer.content or {}).horizontalListRenderer or {}).items or {})
            end
            for _, item in ipairs(shelf_items) do
              if #results >= limit then break end
              if item.videoRenderer then
                local vr = parse_video_renderer(item.videoRenderer)
                if vr then results[#results + 1] = vr end
              end
            end
          end
          if section.continuationItemRenderer then
            local ep = (section.continuationItemRenderer.continuationEndpoint or {}).continuationCommand or {}
            continuation = ep.token
          end
        end
        if #results > 0 then break end
      end
    end
  end)
  return results, continuation
end

-- ─── Channel Result Parsing ─────────────────────────────────────────────────

local function parse_channel_results(data, limit)
  local results = {}
  local continuation = nil
  pcall(function()
    local tabs = (((data or {}).contents or {}).twoColumnBrowseResultsRenderer or {}).tabs or {}
    for _, tab in ipairs(tabs) do
      local content = (tab.tabRenderer or {}).content or {}
      local items = (content.richGridRenderer or {}).contents or (content.sectionListRenderer or {}).contents or {}
      if #items > 0 then
        for _, item in ipairs(items) do
          if #results >= limit then break end
          if item.continuationItemRenderer then
            local ep = (item.continuationItemRenderer.continuationEndpoint or {}).continuationCommand or {}
            continuation = ep.token
          end
          if item.richItemRenderer then
            local vr = parse_video_renderer((item.richItemRenderer.content or {}).videoRenderer)
            if vr then results[#results + 1] = vr end
          end
          if item.videoRenderer then
            local vr = parse_video_renderer(item.videoRenderer)
            if vr then results[#results + 1] = vr end
          end
        end
        if #results > 0 then break end
      end
    end
  end)
  return results, continuation
end

-- ─── Playlist Result Parsing ────────────────────────────────────────────────

local function parse_playlist_results(data, limit)
  local results = {}
  local continuation = nil
  pcall(function()
    local contents = (((((((((data or {}).contents or {}).twoColumnBrowseResultsRenderer or {}).tabs or {})[1] or {}).tabRenderer or {}).content or {}).sectionListRenderer or {}).contents or {})[1] or {}).itemSectionRenderer or {}
    contents = contents.contents or {}

    local playlist_contents = {}
    if #contents > 0 and contents[1].playlistVideoListRenderer then
      playlist_contents = contents[1].playlistVideoListRenderer.contents or {}
    end

    if #playlist_contents == 0 then
      local alt = ((((data or {}).contents or {}).twoColumnWatchNextResults or {}).playlist or {}).playlist or {}
      playlist_contents = alt.contents or {}
      if #playlist_contents == 0 then return end

      for _, item in ipairs(playlist_contents) do
        if #results >= limit then break end
        if item.continuationItemRenderer then
          local ep = (item.continuationItemRenderer.continuationEndpoint or {}).continuationCommand or {}
          continuation = ep.token
        end
        if item.playlistVideoRenderer then
          local pvr = item.playlistVideoRenderer
          local vid = pvr.videoId
          if vid then
            local title = extract_runs((pvr.title or {}).runs)
            local author = extract_runs((pvr.shortBylineText or {}).runs)
            local dur_raw = pvr.lengthText or {}
            local dur_text = dur_raw.simpleText or extract_runs(dur_raw.runs) or ""
            local duration_str, duration_sec = parse_duration(dur_text)
            local raw_thumbs = (pvr.thumbnail or {}).thumbnails or {}
            local fb = fallback_result(vid)
            results[#results + 1] = {
              id = vid,
              title = (title and title ~= "") and title or fb.title,
              author = (author and author ~= "") and author or fb.author,
              channel_url = "",
              thumbnail = best_thumbnail(raw_thumbs) ~= "" and best_thumbnail(raw_thumbs) or fb.thumbnail,
              thumbnails = fb.thumbnails,
              full_url = fb.full_url,
              embed_url = fb.embed_url,
              duration = duration_str,
              duration_seconds = duration_sec,
              view_count = "",
              view_count_raw = 0,
              published_time = "",
              description = "",
              channel_avatar = "",
              is_live = false,
              is_upcoming = false,
              is_verified = false,
            }
          end
        end
      end
      return
    end

    for _, item in ipairs(playlist_contents) do
      if #results >= limit then break end
      if item.continuationItemRenderer then
        local ep = (item.continuationItemRenderer.continuationEndpoint or {}).continuationCommand or {}
        continuation = ep.token
      end
      if item.playlistVideoRenderer then
        local pvr = item.playlistVideoRenderer
        local vid = pvr.videoId
        if vid then
          local title = extract_runs((pvr.title or {}).runs)
          local author = extract_runs((pvr.shortBylineText or {}).runs)
          local dur_raw = pvr.lengthText or {}
          local dur_text = dur_raw.simpleText or extract_runs(dur_raw.runs) or ""
          local duration_str, duration_sec = parse_duration(dur_text)
          local raw_thumbs = (pvr.thumbnail or {}).thumbnails or {}
          local fb = fallback_result(vid)
          results[#results + 1] = {
            id = vid,
            title = (title and title ~= "") and title or fb.title,
            author = (author and author ~= "") and author or fb.author,
            channel_url = "",
            thumbnail = best_thumbnail(raw_thumbs) ~= "" and best_thumbnail(raw_thumbs) or fb.thumbnail,
            thumbnails = fb.thumbnails,
            full_url = fb.full_url,
            embed_url = fb.embed_url,
            duration = duration_str,
            duration_seconds = duration_sec,
            view_count = "",
            view_count_raw = 0,
            published_time = "",
            description = "",
            channel_avatar = "",
            is_live = false,
            is_upcoming = false,
            is_verified = false,
          }
        end
      end
    end
  end)
  return results, continuation
end

-- ─── Enrich Results with OEmbed ─────────────────────────────────────────────

local function enrich_results(results)
  for _, r in ipairs(results) do
    if not r.title or r.title == "" or r.title == "Video " .. r.id or r.author == "Unknown Author" then
      local enriched = enrich_oembed(r.id)
      if enriched.title and enriched.title ~= "" then r.title = enriched.title end
      if enriched.author and enriched.author ~= "" then r.author = enriched.author end
      if enriched.thumbnail and enriched.thumbnail ~= "" and enriched.thumbnail ~= r.thumbnail then
        r.thumbnail = enriched.thumbnail
      end
    end
  end
end

-- ─── Public API Functions ───────────────────────────────────────────────────

function ytapis.get_video(video_id)
  local fb = fallback_result(video_id)
  local ok, result = pcall(function()
    local html = fetch("https://www.youtube.com/watch?v=" .. video_id)
    if not html then return fb end
    local data = extract_json(html, "var ytInitialPlayerResponse") or extract_json(html, "var ytInitialData")
    if not data then return fb end

    local vd = data.videoDetails
    if vd then
      local dur = tonumber(vd.lengthSeconds) or 0
      local hrs = math.floor(dur / 3600)
      local mins = math.floor((dur % 3600) / 60)
      local secs = dur % 60
      local dur_str
      if hrs > 0 then
        dur_str = string.format("%d:%02d:%02d", hrs, mins, secs)
      else
        dur_str = string.format("%d:%02d", mins, secs)
      end

      local raw_thumbs = (vd.thumbnail or {}).thumbnails or {}
      local thumbs = {}
      for _, t in ipairs(raw_thumbs) do
        thumbs[#thumbs + 1] = { url = t.url or "", width = t.width or 0, height = t.height or 0 }
      end

      local view_count_raw = tonumber(vd.viewCount) or 0
      local view_count_str = ""
      if view_count_raw > 0 then
        view_count_str = tostring(math.floor(view_count_raw / 1000)) .. "K views"
      end

      return {
        id = video_id,
        title = vd.title or fb.title,
        author = vd.author or fb.author,
        channel_url = vd.channelId and ("https://www.youtube.com/" .. vd.channelId) or fb.channel_url,
        thumbnail = best_thumbnail(raw_thumbs) ~= "" and best_thumbnail(raw_thumbs) or fb.thumbnail,
        thumbnails = (#thumbs > 0) and thumbs or fb.thumbnails,
        full_url = fb.full_url,
        embed_url = fb.embed_url,
        duration = dur_str,
        duration_seconds = dur,
        view_count = view_count_str,
        view_count_raw = view_count_raw,
        published_time = "",
        description = vd.shortDescription or "",
        channel_avatar = (vd.authorThumbnails or {})[1] and ((vd.authorThumbnails or {})[1] or {}).url or "",
        is_live = vd.isLive or false,
        is_upcoming = vd.isUpcoming or false,
        is_verified = false,
      }
    end
    return fb
  end)
  if ok and result then return result end
  return fb
end

function ytapis.search(query, limit, gl, hl)
  limit = math.max(1, math.min(limit or 15, 50))
  local url = "https://www.youtube.com/results?search_query=" .. urlencode(query)
  if gl then url = url .. "&gl=" .. gl end
  if hl then url = url .. "&hl=" .. hl end
  local html = fetch(url)
  if not html then return {} end
  local data = extract_json(html, "var ytInitialData")
  if not data then return {} end
  local results, _ = parse_search_results(data, limit)
  enrich_results(results)
  return results
end

function ytapis.search_trending(limit, gl, hl)
  limit = math.max(1, math.min(limit or 15, 50))
  local url = "https://www.youtube.com/feed/trending"
  local params = {}
  if gl then params[#params + 1] = "gl=" .. gl end
  if hl then params[#params + 1] = "hl=" .. hl end
  if #params > 0 then url = url .. "?" .. table.concat(params, "&") end
  local html = fetch(url)
  if not html then return {} end
  local data = extract_json(html, "var ytInitialData")
  if not data then return {} end
  local results, _ = parse_trending_results(data, limit)
  enrich_results(results)
  return results
end

function ytapis.search_channel(channel_id, limit, gl, hl)
  limit = math.max(1, math.min(limit or 15, 50))
  local url = "https://www.youtube.com/channel/" .. channel_id .. "/videos"
  local params = {}
  if gl then params[#params + 1] = "gl=" .. gl end
  if hl then params[#params + 1] = "hl=" .. hl end
  if #params > 0 then url = url .. "?" .. table.concat(params, "&") end
  local html = fetch(url)
  if not html then return {} end
  local data = extract_json(html, "var ytInitialData")
  if not data then return {} end
  local results, _ = parse_channel_results(data, limit)
  enrich_results(results)
  return results
end

function ytapis.search_playlist(playlist_id, limit, gl, hl)
  limit = math.max(1, math.min(limit or 15, 50))
  local url = "https://www.youtube.com/playlist?list=" .. playlist_id
  if gl then url = url .. "&gl=" .. gl end
  if hl then url = url .. "&hl=" .. hl end
  local html = fetch(url)
  if not html then return {} end
  local data = extract_json(html, "var ytInitialData")
  if not data then return {} end
  local results, _ = parse_playlist_results(data, limit)
  enrich_results(results)
  return results
end

-- ─── Client Factory ─────────────────────────────────────────────────────────

function ytapis.create_client(cache_lib, use_retry, max_retries)
  use_retry = use_retry or true
  max_retries = max_retries or 3

  local client = {
    search = function(q, l) return ytapis.search(q, l) end,
    search_trending = function(l) return ytapis.search_trending(l) end,
    search_channel = function(cid, l) return ytapis.search_channel(cid, l) end,
    search_playlist = function(pid, l) return ytapis.search_playlist(pid, l) end,
    get_video = function(vid) return ytapis.get_video(vid) end,
    _VERSION = ytapis._VERSION,
  }
  return client
end

-- ─── Module Export ──────────────────────────────────────────────────────────

return ytapis
