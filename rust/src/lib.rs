use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::error::Error;
use std::fmt;
use std::time::Duration;

// ── Constants ────────────────────────────────────────────────────────────────

const USER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

const YT_SEARCH_URL: &str = "https://www.youtube.com/results";
const YT_WATCH_URL: &str = "https://www.youtube.com/watch";
const YT_OEMBED_URL: &str = "https://www.youtube.com/oembed";
const YT_INNERTUBE_URL: &str = "https://www.youtube.com/youtubei/v1/search";

const DEFAULT_INNERTUBE_CLIENT: &str = r#"{"client":{"hl":"en","gl":"US","clientName":"WEB","clientVersion":"2.20241219.00.00","utcOffsetMinutes":0}}"#;

const INVALID_CHARS: &[char] = &[
    '\0', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', '\x08',
    '\x0B', '\x0C', '\x0E', '\x0F', '\x10', '\x11', '\x12', '\x13', '\x14',
    '\x15', '\x16', '\x17', '\x18', '\x19', '\x1A', '\x1B', '\x1C', '\x1D',
    '\x1E', '\x1F',
];

// ── Error type ──────────────────────────────────────────────────────────────

#[derive(Debug)]
pub struct YtError {
    pub message: String,
}

impl fmt::Display for YtError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl Error for YtError {}

impl YtError {
    fn new(msg: impl Into<String>) -> Self {
        YtError {
            message: msg.into(),
        }
    }
}

macro_rules! yterr {
    ($($arg:tt)*) => { Box::new(YtError::new(format!($($arg)*))) as Box<dyn Error> };
}

type YtResult<T> = Result<T, Box<dyn Error>>;

// ── Structs ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Thumbnail {
    pub url: String,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoResult {
    pub id: String,
    pub title: String,
    pub author: String,
    pub channel_url: String,
    pub thumbnail: String,
    pub thumbnails: Vec<Thumbnail>,
    pub full_url: String,
    pub embed_url: String,
    pub duration: String,
    pub duration_seconds: u64,
    pub view_count: String,
    pub view_count_raw: u64,
    pub published_time: String,
    pub description: String,
    pub channel_avatar: String,
    pub is_live: bool,
    pub is_upcoming: bool,
    pub is_verified: bool,
}

impl Default for VideoResult {
    fn default() -> Self {
        VideoResult {
            id: String::new(),
            title: String::new(),
            author: String::new(),
            channel_url: String::new(),
            thumbnail: String::new(),
            thumbnails: Vec::new(),
            full_url: String::new(),
            embed_url: String::new(),
            duration: String::new(),
            duration_seconds: 0,
            view_count: String::new(),
            view_count_raw: 0,
            published_time: String::new(),
            description: String::new(),
            channel_avatar: String::new(),
            is_live: false,
            is_upcoming: false,
            is_verified: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResponse {
    pub results: Vec<VideoResult>,
    pub continuation: Option<String>,
    pub api_key: Option<String>,
}

// ── Helpers ─────────────────────────────────────────────────────────────────

fn build_client() -> YtResult<reqwest::blocking::Client> {
    reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent(USER_AGENT)
        .cookie_store(true)
        .build()
        .map_err(|e| yterr!("Failed to build HTTP client: {}", e))
}

/// Sanitise a text node by stripping control characters.
fn sanitise(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        if !INVALID_CHARS.contains(&ch) {
            out.push(ch);
        }
    }
    out
}

/// Get a string from a JSON value that could be `"text"` or `{"simpleText":"text"}` or `[{"text":"a"},{"text":"b"}]`.
fn val_str(v: &Value) -> String {
    match v {
        Value::String(s) => sanitise(s),
        Value::Object(map) => {
            if let Some(simple) = map.get("simpleText").and_then(|v| v.as_str()) {
                sanitise(simple)
            } else if let Some(runs) = map.get("runs").and_then(|v| v.as_array()) {
                let joined: String = runs
                    .iter()
                    .filter_map(|r| r.get("text").and_then(|t| t.as_str()))
                    .collect();
                sanitise(&joined)
            } else {
                String::new()
            }
        }
        Value::Array(arr) => {
            let mut out = String::new();
            for item in arr {
                out.push_str(&val_str(item));
            }
            sanitise(&out)
        }
        _ => String::new(),
    }
}

/// Get a string from a key that may be a string or rich text object.
fn get_text(obj: &Value, key: &str) -> String {
    obj.get(key).map(val_str).unwrap_or_default()
}

/// Get a nested string via dot-path: `"a.b.c"`.
fn deep_str(obj: &Value, path: &str) -> String {
    let mut cur = obj;
    for seg in path.split('.') {
        match cur.get(seg) {
            Some(v) => cur = v,
            None => return String::new(),
        }
    }
    val_str(cur)
}

fn deep_val<'a>(obj: &'a Value, path: &str) -> Option<&'a Value> {
    let mut cur = obj;
    for seg in path.split('.') {
        cur = cur.get(seg)?;
    }
    Some(cur)
}

// ── JSON extraction (brace counting) ────────────────────────────────────────

/// Extract a JSON object from HTML by finding `prefix`, then the opening `{`,
/// then walking characters counting brace depth until depth returns to 0.
/// Respects string literals and escape sequences.
pub fn extract_json(html: &str, prefix: &str) -> Option<String> {
    let start_idx = html.find(prefix)?;
    let after_prefix = &html[start_idx + prefix.len()..];

    // Find opening brace
    let brace_pos = after_prefix.find('{')?;
    let chars: Vec<char> = after_prefix[brace_pos..].chars().collect();

    let mut depth: i32 = 0;
    let mut in_string = false;
    let mut escape_next = false;
    let mut end_idx: usize = 0;

    for (i, &ch) in chars.iter().enumerate() {
        if escape_next {
            escape_next = false;
            continue;
        }
        if in_string {
            if ch == '\\' {
                escape_next = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }
        match ch {
            '"' => in_string = true,
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    end_idx = i + 1;
                    break;
                }
            }
            _ => {}
        }
    }

    if depth != 0 {
        return None;
    }

    Some(chars[..end_idx].iter().collect())
}

// ── Parsing helpers ─────────────────────────────────────────────────────────

/// Parse a YouTube duration string like "12:34" or "1:02:34" into (display, total_seconds).
pub fn parse_duration(s: &str) -> (String, u64) {
    let cleaned = s.trim();
    if cleaned.is_empty() {
        return (String::new(), 0);
    }
    let parts: Vec<&str> = cleaned.split(':').collect();
    let total: u64 = match parts.len() {
        3 => {
            let h: u64 = parts[0].parse().unwrap_or(0);
            let m: u64 = parts[1].parse().unwrap_or(0);
            let s: u64 = parts[2].parse().unwrap_or(0);
            h * 3600 + m * 60 + s
        }
        2 => {
            let m: u64 = parts[0].parse().unwrap_or(0);
            let s: u64 = parts[1].parse().unwrap_or(0);
            m * 60 + s
        }
        1 => parts[0].parse().unwrap_or(0),
        _ => 0,
    };
    (cleaned.to_string(), total)
}

/// Parse a view-count string such as "1.2M views" → 1_200_000 or "53K views" → 53_000.
pub fn parse_view_count(s: &str) -> u64 {
    let s = s.trim();
    if s.is_empty() || s.eq_ignore_ascii_case("no views") {
        return 0;
    }
    // Remove "views" / "view" suffix
    let num_part = s
        .replace(" views", "")
        .replace(" view", "")
        .replace("Views", "")
        .replace("View", "")
        .trim()
        .to_string();

    if num_part.is_empty() {
        return 0;
    }

    let (base, multiplier): (f64, f64) = if num_part.ends_with('B') || num_part.ends_with('b') {
        (num_part[..num_part.len() - 1].trim().parse().unwrap_or(0.0), 1_000_000_000.0)
    } else if num_part.ends_with('M') || num_part.ends_with('m') {
        (num_part[..num_part.len() - 1].trim().parse().unwrap_or(0.0), 1_000_000.0)
    } else if num_part.ends_with('K') || num_part.ends_with('k') {
        (num_part[..num_part.len() - 1].trim().parse().unwrap_or(0.0), 1_000.0)
    } else {
        let cleaned = num_part.replace(',', "");
        (cleaned.parse().unwrap_or(0.0), 1.0)
    };

    (base * multiplier) as u64
}

fn parse_thumbnails(arr: &[Value]) -> Vec<Thumbnail> {
    arr.iter()
        .map(|t| Thumbnail {
            url: t.get("url").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            width: t.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
            height: t.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as u32,
        })
        .filter(|t| !t.url.is_empty())
        .collect()
}

fn thumbnail_quality_score(url: &str) -> u32 {
    if url.is_empty() { return 0; }
    if url.contains("maxresdefault") { return 1280; }
    if url.contains("sddefault") { return 640; }
    if url.contains("hqdefault") { return 480; }
    if url.contains("mqdefault") { return 320; }
    if url.contains("default") { return 120; }
    0
}

fn best_thumbnail(thumbs: &[Thumbnail]) -> String {
    if thumbs.is_empty() { return String::new(); }
    let mut best = &thumbs[0];
    let mut best_score = thumbnail_quality_score(&best.url);
    for t in thumbs.iter().skip(1) {
        let score = if t.width > 0 { t.width } else { thumbnail_quality_score(&t.url) };
        if score > best_score {
            best = t;
            best_score = score;
        }
    }
    best.url.clone()
}

// ── API key extraction ──────────────────────────────────────────────────────

fn extract_api_key(html: &str) -> Option<String> {
    // Pattern: "INNERTUBE_API_KEY":"XXXX" or 'INNERTUBE_API_KEY':'XXXX'
    for pat in &["\"INNERTUBE_API_KEY\":\"", "'INNERTUBE_API_KEY':'"] {
        if let Some(pos) = html.find(pat) {
            let rest = &html[pos + pat.len()..];
            if let Some(end) = rest.find(['"', '\'']) {
                return Some(rest[..end].to_string());
            }
        }
    }
    None
}

fn extract_api_key_from_json(data: &Value) -> Option<String> {
    data.get("responseContext")
        .and_then(|rc| rc.get("serviceTrackingParams"))
        .and_then(|stp| stp.as_array())
        .and_then(|arr| {
            arr.iter().find_map(|p| {
                p.get("params").and_then(|params| {
                    params.as_array().and_then(|pa| {
                        pa.iter().find_map(|item| {
                            if item.get("key").and_then(|k| k.as_str()) == Some("api_key") {
                                item.get("value").and_then(|v| v.as_str()).map(String::from)
                            } else {
                                None
                            }
                        })
                    })
                })
            })
        })
}

// ── Video renderer parser ───────────────────────────────────────────────────

fn parse_video_renderer(vr: &Value) -> VideoResult {
    let id = vr
        .get("videoId")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let title = deep_str(vr, "title");

    let author = vr
        .get("ownerText")
        .and_then(|o| o.get("runs"))
        .and_then(|runs| runs.as_array())
        .and_then(|runs| runs.first())
        .map(|run| {
            run.get("text")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string()
        })
        .unwrap_or_default();

    let channel_url = vr
        .get("ownerText")
        .and_then(|o| o.get("runs"))
        .and_then(|runs| runs.as_array())
        .and_then(|runs| runs.first())
        .and_then(|run| {
            run.get("navigationEndpoint")
                .and_then(|ne| ne.get("browseEndpoint"))
        })
        .map(|be| {
            if let Some(cbu) = be.get("canonicalBaseUrl").and_then(|v| v.as_str()) {
                format!("https://www.youtube.com{}", cbu)
            } else if let Some(bid) = be.get("browseId").and_then(|v| v.as_str()) {
                format!("https://www.youtube.com/channel/{}", bid)
            } else {
                String::new()
            }
        })
        .unwrap_or_default();

    let thumbnails: Vec<Thumbnail> = vr
        .get("thumbnail")
        .and_then(|t| t.get("thumbnails"))
        .and_then(|t| t.as_array())
        .map(|arr| parse_thumbnails(arr))
        .unwrap_or_default();

    let thumbnail = best_thumbnail(&thumbnails);

    let full_url = if id.is_empty() {
        String::new()
    } else {
        format!("https://www.youtube.com/watch?v={}", id)
    };
    let embed_url = if id.is_empty() {
        String::new()
    } else {
        format!("https://www.youtube.com/embed/{}", id)
    };

    let length_text = get_text(vr, "lengthText");
    let (duration, duration_seconds) = parse_duration(&length_text);

    let view_count = vr
        .get("viewCountText")
        .map(|v| {
            if let Some(simple) = v.get("simpleText").and_then(|s| s.as_str()) {
                sanitise(simple)
            } else if let Some(runs) = v.get("runs").and_then(|r| r.as_array()) {
                let joined: String = runs
                    .iter()
                    .filter_map(|r| r.get("text").and_then(|t| t.as_str()))
                    .collect();
                sanitise(&joined)
            } else {
                String::new()
            }
        })
        .unwrap_or_default();
    let view_count_raw = parse_view_count(&view_count);
    let published_time = get_text(vr, "publishedTimeText");

    // Description from detailedMetadataSnippets
    let description = vr
        .get("detailedMetadataSnippets")
        .and_then(|dms| dms.as_array())
        .and_then(|arr| arr.first())
        .and_then(|snippet| snippet.get("snippetText"))
        .map(|st| {
            if let Some(runs) = st.get("runs").and_then(|r| r.as_array()) {
                let joined: String = runs
                    .iter()
                    .filter_map(|r| r.get("text").and_then(|t| t.as_str()))
                    .collect();
                sanitise(&joined)
            } else {
                String::new()
            }
        })
        .unwrap_or_default();

    // Channel avatar
    let channel_avatar = vr
        .get("channelThumbnailSupportedRenderers")
        .and_then(|ctsr| ctsr.get("channelThumbnailWithLinkRenderer"))
        .and_then(|ctwlr| ctwlr.get("thumbnail"))
        .and_then(|t| t.get("thumbnails"))
        .and_then(|t| t.as_array())
        .map(|arr| {
            arr.last()
                .and_then(|t| t.get("url").and_then(|u| u.as_str()))
                .unwrap_or("")
                .to_string()
        })
        .unwrap_or_default();

    // Badges: is_live, is_upcoming, is_verified
    let mut is_live = false;
    let mut is_upcoming = false;
    let mut is_verified = false;

    // Check thumbnailOverlays for live/upcoming
    if let Some(overlays) = vr
        .get("thumbnailOverlays")
        .and_then(|to| to.as_array())
    {
        for overlay in overlays {
            if let Some(style) = overlay
                .get("thumbnailOverlayTimeStatusRenderer")
                .and_then(|r| r.get("style"))
                .and_then(|s| s.as_str())
            {
                match style {
                    "LIVE" => is_live = true,
                    "UPCOMING" => is_upcoming = true,
                    _ => {}
                }
            }
        }
    }

    // Check badges
    if let Some(badges) = vr.get("badges").and_then(|b| b.as_array()) {
        for badge in badges {
            if let Some(style) = badge
                .get("metadataBadgeRenderer")
                .and_then(|r| r.get("style"))
                .and_then(|s| s.as_str())
            {
                match style {
                    "BADGE_STYLE_TYPE_LIVE_NOW" => is_live = true,
                    "BADGE_STYLE_TYPE_VERIFIED" => is_verified = true,
                    _ => {}
                }
            }
        }
    }

    // Check ownerBadges for verification
    if let Some(owner_badges) = vr
        .get("ownerBadges")
        .and_then(|ob| ob.as_array())
    {
        for badge in owner_badges {
            if let Some(style) = badge
                .get("metadataBadgeRenderer")
                .and_then(|r| r.get("style"))
                .and_then(|s| s.as_str())
            {
                if style == "BADGE_STYLE_TYPE_VERIFIED" {
                    is_verified = true;
                }
            }
        }
    }

    VideoResult {
        id,
        title,
        author,
        channel_url,
        thumbnail,
        thumbnails,
        full_url,
        embed_url,
        duration,
        duration_seconds,
        view_count,
        view_count_raw,
        published_time,
        description,
        channel_avatar,
        is_live,
        is_upcoming,
        is_verified,
    }
}

// ── Content walker ──────────────────────────────────────────────────────────

/// Walk into sectionListRenderer → contents → itemSectionRenderer → contents
/// and collect every `videoRenderer`.
fn walk_section_list(contents: &[Value]) -> Vec<&Value> {
    let mut results = Vec::new();
    for item in contents {
        // Direct videoRenderer
        if let Some(vr) = item.get("videoRenderer") {
            results.push(vr);
        }
        // itemSectionRenderer
        if let Some(isr) = item.get("itemSectionRenderer") {
            if let Some(items) = isr.get("contents").and_then(|c| c.as_array()) {
                for inner in items {
                    if let Some(vr) = inner.get("videoRenderer") {
                        results.push(vr);
                    }
                }
            }
        }
        // richItemRenderer (mobile/web mixed layouts)
        if let Some(rir) = item.get("richItemRenderer") {
            if let Some(content) = rir.get("content") {
                if let Some(vr) = content.get("videoRenderer") {
                    results.push(vr);
                }
            }
        }
        // compactVideoRenderer (related / sidebar)
        if let Some(cvr) = item.get("compactVideoRenderer") {
            results.push(cvr);
        }
    }
    results
}

/// Find continuation token from a list of section contents.
fn find_continuation(contents: &[Value]) -> Option<String> {
    for item in contents {
        if let Some(cir) = item.get("continuationItemRenderer") {
            if let Some(token) = cir
                .get("continuationEndpoint")
                .and_then(|ce| ce.get("continuationCommand"))
                .and_then(|cc| cc.get("token"))
                .and_then(|t| t.as_str())
            {
                return Some(token.to_string());
            }
        }
    }
    None
}

/// Navigate the initial-data JSON to find sectionListRenderer contents.
/// Handles both `twoColumnSearchResultsRenderer` and `tabbedSearchResultsRenderer` layouts.
fn get_section_contents(data: &Value) -> Option<&Vec<Value>> {
    // Path: contents.twoColumnSearchResultsRenderer.primaryContents.sectionListRenderer.contents
    if let Some(tcsr) = deep_val(data, "contents.twoColumnSearchResultsRenderer") {
        if let Some(arr) =
            deep_val(tcsr, "primaryContents.sectionListRenderer.contents").and_then(|v| v.as_array())
        {
            return Some(arr);
        }
    }

    // Path: contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer.contents
    if let Some(ttsr) = deep_val(data, "contents.tabbedSearchResultsRenderer") {
        if let Some(tabs) = ttsr.get("tabs").and_then(|v| v.as_array()) {
            if let Some(first) = tabs.first() {
                if let Some(arr) = deep_val(first, "tabRenderer.content.sectionListRenderer.contents")
                    .and_then(|v| v.as_array())
                {
                    return Some(arr);
                }
            }
        }
    }

    // Path: onResponseReceivedCommands[0].appendContinuationItemsAction.continuationItems
    if let Some(cmds) = data
        .get("onResponseReceivedCommands")
        .and_then(|v| v.as_array())
    {
        for cmd in cmds {
            if let Some(items) = cmd
                .get("appendContinuationItemsAction")
                .and_then(|a| a.get("continuationItems"))
                .and_then(|v| v.as_array())
            {
                return Some(items);
            }
        }
    }

    None
}

// ─── Continuation helpers ────────────────────────────────────────────────

fn get_continuation_contents(data: &Value, path: &str) -> Option<&Vec<Value>> {
    if path == "channel" {
        if let Some(arr) = data
            .get("onResponseReceivedActions")
            .and_then(|v| v.as_array())
            .and_then(|arr| arr.first())
            .and_then(|v| v.get("appendContinuationItemsAction"))
            .and_then(|v| v.get("continuationItems"))
            .and_then(|v| v.as_array())
        {
            return Some(arr);
        }
    }

    if let Some(arr) = data
        .get("onResponseReceivedEndpoints")
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.first())
        .and_then(|v| v.get("appendContinuationItemsAction"))
        .and_then(|v| v.get("continuationItems"))
        .and_then(|v| v.as_array())
    {
        return Some(arr);
    }

    None
}

/// Walk continuation items and parse video/playlist renderers directly.
fn parse_continuation_items_from(contents: &[Value], limit: usize, path: &str) -> Vec<VideoResult> {
    let mut results = Vec::new();
    for item in contents {
        if results.len() >= limit { break; }
        if path == "playlist" {
            if let Some(pvr) = item.get("playlistVideoRenderer") {
                let vid = pvr.get("videoId").and_then(|v| v.as_str()).unwrap_or("").to_string();
                if !vid.is_empty() {
                    let title = pvr.get("title").map(|v| val_str(v)).unwrap_or_default();
                    let author = pvr.get("shortBylineText").map(|v| val_str(v)).unwrap_or_default();
                    let dur_text = pvr.get("lengthText").map(|v| val_str(v)).unwrap_or_default();
                    let (duration, duration_seconds) = parse_duration(&dur_text);
                    let fb = fallback_result_private(&vid);
                    results.push(VideoResult {
                        id: vid,
                        title: if title.is_empty() { fb.title } else { title },
                        author: if author.is_empty() { fb.author } else { author },
                        duration,
                        duration_seconds,
                        thumbnail: fb.thumbnail,
                        thumbnails: fb.thumbnails,
                        full_url: fb.full_url,
                        embed_url: fb.embed_url,
                        ..Default::default()
                    });
                }
            }
        } else {
            let mut vr = item.get("videoRenderer");
            if vr.is_none() {
                vr = item.get("richItemRenderer")
                    .and_then(|rir| rir.get("content"))
                    .and_then(|c| c.get("videoRenderer"));
            }
            if let Some(vr) = vr {
                results.push(parse_video_renderer(vr));
            }
        }
    }
    results
}

// ─── Trending parser ──────────────────────────────────────────────────────

fn parse_trending_results(data: &Value, limit: usize) -> (Vec<VideoResult>, Option<String>) {
    let tabs = deep_val(data, "contents.twoColumnBrowseResultsRenderer.tabs")
        .and_then(|v| v.as_array());

    let mut results = Vec::new();
    let mut continuation = None;

    if let Some(tabs) = tabs {
        for tab in tabs {
            let contents = deep_val(tab, "tabRenderer.content.sectionListRenderer.contents")
                .and_then(|v| v.as_array());
            if let Some(contents) = contents {
                for section in contents {
                    if results.len() >= limit { break; }
                    if let Some(isr) = section.get("itemSectionRenderer") {
                        if let Some(items) = isr.get("contents").and_then(|c| c.as_array()) {
                            for inner in items {
                                if results.len() >= limit { break; }
                                if let Some(vr) = inner.get("videoRenderer") {
                                    results.push(parse_video_renderer(vr));
                                }
                            }
                        }
                    }
                    if let Some(shelf) = section.get("shelfRenderer") {
                        if let Some(shelf_content) = shelf.get("content") {
                            let shelf_items = shelf_content
                                .get("expandedShelfContentsRenderer")
                                .and_then(|v| v.get("items"))
                                .or_else(|| shelf_content.get("horizontalListRenderer").and_then(|v| v.get("items")))
                                .and_then(|v| v.as_array());
                            if let Some(shelf_items) = shelf_items {
                                for item in shelf_items {
                                    if results.len() >= limit { break; }
                                    if let Some(vr) = item.get("videoRenderer") {
                                        results.push(parse_video_renderer(vr));
                                    }
                                }
                            }
                        }
                    }
                    if results.len() < limit {
                        if let Some(token) = find_continuation_content(section) {
                            continuation = Some(token);
                        }
                    }
                }
            }
            if !results.is_empty() { break; }
        }
    }

    (results, continuation)
}

// ─── Channel parser ───────────────────────────────────────────────────────

fn parse_channel_results(data: &Value, limit: usize) -> (Vec<VideoResult>, Option<String>) {
    let tabs = deep_val(data, "contents.twoColumnBrowseResultsRenderer.tabs")
        .and_then(|v| v.as_array());

    let mut results = Vec::new();
    let mut continuation = None;

    if let Some(tabs) = tabs {
        for tab in tabs {
            let content = tab.get("tabRenderer").and_then(|v| v.get("content"));
            if let Some(content) = content {
                let items = content
                    .get("richGridRenderer").and_then(|v| v.get("contents"))
                    .or_else(|| content.get("sectionListRenderer").and_then(|v| v.get("contents")))
                    .and_then(|v| v.as_array());

                if let Some(items) = items {
                    for item in items {
                        if results.len() >= limit { break; }
                        if let Some(vr) = item.get("videoRenderer") {
                            results.push(parse_video_renderer(vr));
                        }
                        if let Some(rir) = item.get("richItemRenderer") {
                            if let Some(content) = rir.get("content") {
                                if let Some(vr) = content.get("videoRenderer") {
                                    results.push(parse_video_renderer(vr));
                                }
                            }
                        }
                        if results.len() < limit {
                            if let Some(token) = find_continuation_content(item) {
                                continuation = Some(token);
                            }
                        }
                    }
                }
            }
            if !results.is_empty() { break; }
        }
    }

    (results, continuation)
}

// ─── Playlist parser ──────────────────────────────────────────────────────

fn parse_playlist_results(data: &Value, limit: usize) -> (Vec<VideoResult>, Option<String>) {
    let mut results = Vec::new();
    let mut continuation = None;

    let contents = deep_val(
        data,
        "contents.twoColumnBrowseResultsRenderer.tabs"
    )
    .and_then(|v| v.as_array())
    .and_then(|arr| arr.first())
    .and_then(|v| deep_val(v, "tabRenderer.content.sectionListRenderer.contents"))
    .and_then(|v| v.as_array())
    .and_then(|arr| arr.first())
    .and_then(|v| v.get("itemSectionRenderer"))
    .and_then(|v| v.get("contents"))
    .and_then(|v| v.as_array())
    .and_then(|arr| arr.first())
    .and_then(|v| v.get("playlistVideoListRenderer"))
    .and_then(|v| v.get("contents"))
    .and_then(|v| v.as_array());

    let contents = contents.or_else(|| {
        deep_val(data, "contents.twoColumnWatchNextResults.playlist.playlist.contents")
            .and_then(|v| v.as_array())
    });

    if let Some(contents) = contents {
        for item in contents {
            if results.len() >= limit { break; }
            if let Some(pvr) = item.get("playlistVideoRenderer") {
                let vid = pvr.get("videoId").and_then(|v| v.as_str()).unwrap_or("").to_string();
                if !vid.is_empty() {
                    let title = pvr.get("title").map(|v| val_str(v)).unwrap_or_default();
                    let author = pvr.get("shortBylineText").map(|v| val_str(v)).unwrap_or_default();
                    let dur_text = pvr.get("lengthText").map(|v| val_str(v)).unwrap_or_default();
                    let (duration, duration_seconds) = parse_duration(&dur_text);
                    let fb = fallback_result_private(&vid);
                    results.push(VideoResult {
                        id: vid,
                        title: if title.is_empty() { fb.title } else { title },
                        author: if author.is_empty() { fb.author } else { author },
                        duration,
                        duration_seconds,
                        thumbnail: fb.thumbnail,
                        thumbnails: fb.thumbnails,
                        full_url: fb.full_url,
                        embed_url: fb.embed_url,
                        ..Default::default()
                    });
                }
            }
            if results.len() < limit {
                if let Some(token) = find_continuation_content(item) {
                    continuation = Some(token);
                }
            }
        }
    }

    (results, continuation)
}

fn find_continuation_content(item: &Value) -> Option<String> {
    item.get("continuationItemRenderer")
        .and_then(|cir| cir.get("continuationEndpoint"))
        .and_then(|ce| ce.get("continuationCommand"))
        .and_then(|cc| cc.get("token"))
        .and_then(|t| t.as_str())
        .map(|s| s.to_string())
}

fn fallback_result_private(id: &str) -> VideoResult {
    let thumb = format!("https://i.ytimg.com/vi/{}/hqdefault.jpg", id);
    VideoResult {
        id: id.to_string(),
        title: format!("Video {}", id),
        author: "YouTube".to_string(),
        channel_url: String::new(),
        thumbnail: thumb.clone(),
        thumbnails: vec![Thumbnail { url: thumb, width: 480, height: 360 }],
        full_url: format!("https://www.youtube.com/watch?v={}", id),
        embed_url: format!("https://www.youtube.com/embed/{}?rel=0", id),
        ..Default::default()
    }
}

// ── Trending / Channel / Playlist public API ──────────────────────────────

/// Search YouTube trending feed.
pub fn search_trending(limit: usize) -> YtResult<SearchResponse> {
    let client = build_client()?;
    let resp = client
        .get("https://www.youtube.com/feed/trending")
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(yterr!("HTTP {} from YouTube", resp.status()));
    }

    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;
    let api_key = extract_api_key(&html);

    let json_text = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .or_else(|| extract_json(&html, "ytInitialData = "))
        .ok_or_else(|| yterr!("Could not find ytInitialData in page HTML"))?;

    let data: Value = serde_json::from_str(&json_text)
        .map_err(|e| yterr!("Failed to parse ytInitialData: {}", e))?;

    let api_key_from_json = extract_api_key_from_json(&data);
    let final_api_key = api_key.or(api_key_from_json);

    let (results, continuation) = parse_trending_results(&data, limit);

    Ok(SearchResponse {
        results,
        continuation,
        api_key: final_api_key,
    })
}

/// Search a YouTube channel's video tab.
pub fn search_channel(channel_id: &str, limit: usize) -> YtResult<SearchResponse> {
    let client = build_client()?;
    let url = format!("https://www.youtube.com/channel/{}/videos", channel_id);

    let resp = client
        .get(&url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(yterr!("HTTP {} from YouTube", resp.status()));
    }

    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;
    let api_key = extract_api_key(&html);

    let json_text = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .or_else(|| extract_json(&html, "ytInitialData = "))
        .ok_or_else(|| yterr!("Could not find ytInitialData in page HTML"))?;

    let data: Value = serde_json::from_str(&json_text)
        .map_err(|e| yterr!("Failed to parse ytInitialData: {}", e))?;

    let api_key_from_json = extract_api_key_from_json(&data);
    let final_api_key = api_key.or(api_key_from_json);

    let (results, continuation) = parse_channel_results(&data, limit);

    Ok(SearchResponse {
        results,
        continuation,
        api_key: final_api_key,
    })
}

/// Search a YouTube playlist.
pub fn search_playlist(playlist_id: &str, limit: usize) -> YtResult<SearchResponse> {
    let client = build_client()?;
    let url = format!("https://www.youtube.com/playlist?list={}", playlist_id);

    let resp = client
        .get(&url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(yterr!("HTTP {} from YouTube", resp.status()));
    }

    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;
    let api_key = extract_api_key(&html);

    let json_text = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .or_else(|| extract_json(&html, "ytInitialData = "))
        .ok_or_else(|| yterr!("Could not find ytInitialData in page HTML"))?;

    let data: Value = serde_json::from_str(&json_text)
        .map_err(|e| yterr!("Failed to parse ytInitialData: {}", e))?;

    let api_key_from_json = extract_api_key_from_json(&data);
    let final_api_key = api_key.or(api_key_from_json);

    let (results, continuation) = parse_playlist_results(&data, limit);

    Ok(SearchResponse {
        results,
        continuation,
        api_key: final_api_key,
    })
}

// ── Public search API ─────────────────────────────────────────────────────

/// Search YouTube for `query` and return up to `limit` results.
pub fn search(query: &str, limit: usize) -> YtResult<SearchResponse> {
    let client = build_client()?;
    let url = format!(
        "{}?search_query={}",
        YT_SEARCH_URL,
        urlencoding(query)
    );

    let resp = client
        .get(&url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(yterr!("HTTP {} from YouTube", resp.status()));
    }

    let html = resp
        .text()
        .map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let api_key = extract_api_key(&html);

    let json_text = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .or_else(|| extract_json(&html, "ytInitialData = "))
        .ok_or_else(|| yterr!("Could not find ytInitialData in page HTML"))?;

    let data: Value =
        serde_json::from_str(&json_text).map_err(|e| yterr!("Failed to parse ytInitialData: {}", e))?;

    let api_key_from_json = extract_api_key_from_json(&data);
    let final_api_key = api_key.or(api_key_from_json);

    let section_contents = get_section_contents(&data)
        .ok_or_else(|| yterr!("Could not find section contents in ytInitialData"))?;

    let video_renderers = walk_section_list(section_contents);

    let results: Vec<VideoResult> = video_renderers
        .iter()
        .take(limit)
        .map(|vr| parse_video_renderer(vr))
        .collect();

    let continuation = find_continuation(section_contents);

    Ok(SearchResponse {
        results,
        continuation,
        api_key: final_api_key,
    })
}

/// Search continuation / pagination using the InnerTube API.
pub fn search_continue(
    continuation: &str,
    limit: usize,
    api_key: Option<&str>,
    context: Option<Value>,
    path: Option<&str>,
) -> YtResult<SearchResponse> {
    let client = build_client()?;

    let key = match api_key {
        Some(k) if !k.is_empty() => k.to_string(),
        _ => {
            // We need a key; attempt to fetch one by doing a dummy search
            let dummy = search("test", 1)?;
            dummy
                .api_key
                .ok_or_else(|| yterr!("No API key available for continuation request"))?
        }
    };

    let ctx: Value = context.unwrap_or_else(|| {
        serde_json::from_str(DEFAULT_INNERTUBE_CLIENT).unwrap_or(Value::Null)
    });

    let body = serde_json::json!({
        "context": ctx,
        "continuation": continuation,
    });

    let url = format!("{}?key={}", YT_INNERTUBE_URL, key);

    let resp = client
        .post(&url)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header("Accept-Language", "en-US,en;q=0.9")
        .json(&body)
        .send()
        .map_err(|e| yterr!("InnerTube request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(yterr!("InnerTube HTTP {}: {}", resp.status(), resp.status()));
    }

    let data: Value = resp
        .json()
        .map_err(|e| yterr!("Failed to parse InnerTube response: {}", e))?;

    let section_contents = get_continuation_contents(&data, path.unwrap_or("search"))
        .ok_or_else(|| yterr!("Could not find continuationItems in InnerTube response"))?;

    let p = path.unwrap_or("search");
    let results: Vec<VideoResult> = parse_continuation_items_from(section_contents, limit, p);

    let next_continuation = find_continuation(section_contents);

    Ok(SearchResponse {
        results,
        continuation: next_continuation,
        api_key: Some(key),
    })
}

/// Get video metadata by ID. Scrapes the watch page for
/// `ytInitialPlayerResponse`, falls back to oEmbed.
pub fn get_video(id: &str) -> YtResult<VideoResult> {
    let client = build_client()?;

    // ── Attempt 1: scrape the watch page ─────────────────────────────────
    let watch_url = format!("{}?v={}", YT_WATCH_URL, id);
    if let Ok(resp) = client
        .get(&watch_url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
    {
        if resp.status().is_success() {
            if let Ok(html) = resp.text() {
                if let Some(json_text) = extract_json(&html, "var ytInitialPlayerResponse = ")
                    .or_else(|| extract_json(&html, "window[\"ytInitialPlayerResponse\"] = "))
                {
                    if let Ok(data) = serde_json::from_str::<Value>(&json_text) {
                        let vd = data.get("videoDetails");
                        let mf = data
                            .get("microformat")
                            .and_then(|m| m.get("playerMicroformatRenderer"));

                        let video_id = vd
                            .and_then(|v| v.get("videoId"))
                            .and_then(|v| v.as_str())
                            .unwrap_or(id)
                            .to_string();

                        let title = vd
                            .and_then(|v| v.get("title"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        let author = vd
                            .and_then(|v| v.get("author"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        let channel_id = vd
                            .and_then(|v| v.get("channelId"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");

                        let channel_url = if channel_id.is_empty() {
                            String::new()
                        } else {
                            format!("https://www.youtube.com/channel/{}", channel_id)
                        };

                        let length_secs: u64 = vd
                            .and_then(|v| v.get("lengthSeconds"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("0")
                            .parse()
                            .unwrap_or(0);

                        let dur = seconds_to_display(length_secs);

                        let view_count_raw: u64 = vd
                            .and_then(|v| v.get("viewCount"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("0")
                            .parse()
                            .unwrap_or(0);

                        let view_count = format_view_count(view_count_raw);

                        let short_desc = vd
                            .and_then(|v| v.get("shortDescription"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");

                        let published_time = mf
                            .and_then(|m| m.get("publishDate"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        let description = mf
                            .and_then(|m| m.get("description"))
                            .and_then(|v| v.as_str())
                            .map(|s| sanitise(s))
                            .unwrap_or_else(|| sanitise(short_desc));

                        let thumbnails: Vec<Thumbnail> = vd
                            .and_then(|v| v.get("thumbnail"))
                            .and_then(|t| t.get("thumbnails"))
                            .and_then(|t| t.as_array())
                            .map(|arr| parse_thumbnails(arr))
                            .unwrap_or_default();

                        let thumbnail = best_thumbnail(&thumbnails);

                        let channel_avatar = mf
                            .and_then(|m| m.get("ownerProfileUrl"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();

                        let is_live = vd
                            .and_then(|v| v.get("isLive"))
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false)
                            || vd
                                .and_then(|v| v.get("isLiveContent"))
                                .and_then(|v| v.as_bool())
                                .unwrap_or(false);

                        let is_upcoming = vd
                            .and_then(|v| v.get("isUpcoming"))
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false);

                        let is_verified = vd
                            .and_then(|v| v.get("isVerified"))
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false);

                        let full_url = format!("https://www.youtube.com/watch?v={}", video_id);
                        let embed_url = format!("https://www.youtube.com/embed/{}", video_id);

                        return Ok(VideoResult {
                            id: video_id,
                            title,
                            author,
                            channel_url,
                            thumbnail,
                            thumbnails,
                            full_url,
                            embed_url,
                            duration: dur.clone(),
                            duration_seconds: length_secs,
                            view_count,
                            view_count_raw,
                            published_time,
                            description,
                            channel_avatar,
                            is_live,
                            is_upcoming,
                            is_verified,
                        });
                    }
                }
            }
        }
    }

    // ── Attempt 2: oEmbed fallback ───────────────────────────────────────
    let oembed_url = format!(
        "{}?url={}&format=json",
        YT_OEMBED_URL,
        urlencoding(&format!("https://www.youtube.com/watch?v={}", id))
    );

    let resp = client
        .get(&oembed_url)
        .header("Accept", "application/json")
        .send()
        .map_err(|e| yterr!("oEmbed request failed: {}", e))?;

    if !resp.status().is_success() {
        return Err(yterr!("oEmbed HTTP {}: video may not exist or be inaccessible", resp.status()));
    }

    let data: Value = resp
        .json()
        .map_err(|e| yterr!("Failed to parse oEmbed response: {}", e))?;

    let oembed_title = data
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let oembed_author = data
        .get("author_name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let oembed_author_url = data
        .get("author_url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let oembed_thumbnail = data
        .get("thumbnail_url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let full_url = format!("https://www.youtube.com/watch?v={}", id);
    let embed_url = format!("https://www.youtube.com/embed/{}", id);

    Ok(VideoResult {
        id: id.to_string(),
        title: oembed_title,
        author: oembed_author,
        channel_url: oembed_author_url,
        thumbnail: oembed_thumbnail.clone(),
        thumbnails: if oembed_thumbnail.is_empty() {
            vec![]
        } else {
            vec![Thumbnail {
                url: oembed_thumbnail,
                width: 480,
                height: 360,
            }]
        },
        full_url,
        embed_url,
        ..Default::default()
    })
}

// ── Internal helpers ────────────────────────────────────────────────────────

fn urlencoding(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            b' ' => out.push('+'),
            _ => {
                out.push('%');
                out.push(hex_upper(b >> 4));
                out.push(hex_upper(b & 0xF));
            }
        }
    }
    out
}

fn hex_upper(n: u8) -> char {
    match n {
        0..=9 => (b'0' + n) as char,
        10..=15 => (b'A' + (n - 10)) as char,
        _ => '0',
    }
}

fn seconds_to_display(total: u64) -> String {
    let h = total / 3600;
    let m = (total % 3600) / 60;
    let s = total % 60;
    if h > 0 {
        format!("{}:{:02}:{:02}", h, m, s)
    } else {
        format!("{}:{:02}", m, s)
    }
}

fn format_view_count(n: u64) -> String {
    if n == 0 {
        return "No views".to_string();
    }
    if n >= 1_000_000_000 {
        format!("{:.1}B views", n as f64 / 1_000_000_000.0)
    } else if n >= 1_000_000 {
        format!("{:.1}M views", n as f64 / 1_000_000.0)
    } else if n >= 1_000 {
        format!("{:.1}K views", n as f64 / 1_000.0)
    } else {
        format!("{} views", n)
    }
}

// ── New Types ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentAuthor {
    pub name: String,
    pub channel_id: String,
    pub avatar: String,
    pub is_verified: bool,
    pub is_owner: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentReply {
    pub id: String,
    pub author: CommentAuthor,
    pub text: String,
    pub like_count: u64,
    pub like_count_raw: u64,
    pub published_time: String,
    pub is_liked_by_creator: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoComment {
    pub id: String,
    pub author: CommentAuthor,
    pub text: String,
    pub like_count: u64,
    pub like_count_raw: u64,
    pub published_time: String,
    pub reply_count: u64,
    pub is_liked_by_creator: bool,
    pub is_pinned: bool,
    pub replies: Vec<CommentReply>,
    pub reply_continuation: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelatedVideo {
    pub id: String,
    pub title: String,
    pub author: String,
    pub channel_url: String,
    pub duration: String,
    pub duration_seconds: u64,
    pub view_count: String,
    pub view_count_raw: u64,
    pub published_time: String,
    pub thumbnail: String,
    pub is_live: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiveStreamInfo {
    pub is_live: bool,
    pub is_upcoming: bool,
    pub viewer_count: u64,
    pub viewer_count_str: String,
    pub start_time: String,
    pub scheduled_start_time: String,
    pub likes_count: u64,
    pub dislikes_count: u64,
}

// ── LRU Cache ─────────────────────────────────────────────────────────────────

pub struct LruCache<V> {
    map: std::collections::HashMap<String, (V, u64)>,
    order: std::collections::VecDeque<String>,
    max_size: usize,
    ttl_ms: u64,
}

impl<V> LruCache<V> {
    pub fn new(max_size: usize, ttl_ms: u64) -> Self {
        LruCache {
            map: std::collections::HashMap::new(),
            order: std::collections::VecDeque::new(),
            max_size,
            ttl_ms,
        }
    }

    pub fn get(&mut self, key: &str) -> Option<&V> {
        if let Some((val, expires)) = self.map.get(key) {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64;
            if now > *expires {
                self.map.remove(key);
                self.order.retain(|k| k != key);
                return None;
            }
            self.order.retain(|k| k != key);
            self.order.push_back(key.to_string());
            return self.map.get(key).map(|(v, _)| v);
        }
        None
    }

    pub fn set(&mut self, key: String, value: V) {
        if self.map.contains_key(&key) {
            self.order.retain(|k| k != &key);
        } else if self.map.len() >= self.max_size {
            if let Some(oldest) = self.order.pop_front() {
                self.map.remove(&oldest);
            }
        }
        let expires = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64 + self.ttl_ms;
        self.order.push_back(key.clone());
        self.map.insert(key, (value, expires));
    }

    pub fn clear(&mut self) {
        self.map.clear();
        self.order.clear();
    }

    pub fn size(&self) -> usize {
        self.map.len()
    }
}

// ── Retry ─────────────────────────────────────────────────────────────────────

pub async fn with_retry<T, F, E>(
    mut f: F,
    max_retries: u32,
    base_delay: u64,
    max_delay: u64,
) -> Result<T, E>
where
    F: FnMut() -> Result<T, E>,
{
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let mut last_err = None;
    for a in 0..=max_retries {
        match f() {
            Ok(v) => return Ok(v),
            Err(e) => {
                last_err = Some(e);
                if a >= max_retries {
                    return Err(last_err.unwrap());
                }
                let delay = std::cmp::min(
                    base_delay * 2u64.pow(a) + rng.gen_range(0..500),
                    max_delay,
                );
                tokio::time::sleep(tokio::time::Duration::from_millis(delay)).await;
            }
        }
    }
    Err(last_err.unwrap())
}

// ── Comment Parser ────────────────────────────────────────────────────────────

fn parse_comment_renderer(cr: &Value) -> VideoComment {
    let id = cr
        .get("commentId")
        .and_then(|v| v.as_str())
        .or_else(|| cr.get("properties").and_then(|p| p.get("commentId")).and_then(|v| v.as_str()))
        .unwrap_or("")
        .to_string();

    let author_name = cr
        .get("authorText")
        .map(|v| {
            if let Some(simple) = v.get("simpleText").and_then(|s| s.as_str()) {
                sanitise(simple)
            } else if let Some(runs) = v.get("runs").and_then(|r| r.as_array()) {
                let joined: String = runs.iter().filter_map(|r| r.get("text").and_then(|t| t.as_str())).collect();
                sanitise(&joined)
            } else {
                String::new()
            }
        })
        .unwrap_or_default();

    let author_channel = cr
        .get("authorEndpoint")
        .and_then(|ae| ae.get("browseEndpoint"))
        .and_then(|be| be.get("browseId"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let author_avatar = cr
        .get("authorThumbnail")
        .and_then(|v| v.get("thumbnails"))
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.last())
        .and_then(|t| t.get("url").and_then(|u| u.as_str()))
        .unwrap_or("")
        .to_string();

    let is_verified = cr
        .get("authorCommentBadge")
        .and_then(|b| b.get("authorCommentBadgeRenderer"))
        .and_then(|r| r.get("icon"))
        .and_then(|i| i.get("iconType"))
        .and_then(|v| v.as_str())
        .map(|s| s == "CHECK")
        .unwrap_or(false);

    let is_owner = cr
        .get("authorIsChannelOwner")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let text = cr
        .get("contentText")
        .map(|v| {
            if let Some(simple) = v.get("simpleText").and_then(|s| s.as_str()) {
                sanitise(simple)
            } else if let Some(runs) = v.get("runs").and_then(|r| r.as_array()) {
                let joined: String = runs.iter().filter_map(|r| r.get("text").and_then(|t| t.as_str())).collect();
                sanitise(&joined)
            } else {
                String::new()
            }
        })
        .unwrap_or_default();

    let like_count = cr
        .get("voteCount")
        .and_then(|v| v.get("simpleText"))
        .and_then(|v| v.as_str())
        .map(|s| s.parse::<u64>().unwrap_or(0))
        .or_else(|| cr.get("likeCount").and_then(|v| v.as_u64()))
        .unwrap_or(0);

    let published_time = cr
        .get("publishedTimeText")
        .and_then(|v| v.get("runs"))
        .and_then(|r| r.as_array())
        .and_then(|arr| arr.first())
        .and_then(|r| r.get("text").and_then(|t| t.as_str()))
        .unwrap_or("")
        .to_string();

    let reply_count = cr.get("replyCount").and_then(|v| v.as_u64()).unwrap_or(0);
    let is_liked = cr.get("isLiked").and_then(|v| v.as_bool()).unwrap_or(false);
    let is_pinned = cr.get("pinnedCommentBadge").and_then(|v| v.get("pinnedCommentBadgeRenderer")).is_some();

    let mut replies = Vec::new();
    let mut reply_continuation = None;

    if let Some(reply_items) = cr
        .get("replies")
        .and_then(|r| r.get("commentRepliesRenderer"))
        .and_then(|r| r.get("contents"))
        .and_then(|c| c.as_array())
    {
        for ri in reply_items {
            if let Some(token) = ri
                .get("continuationItemRenderer")
                .and_then(|cir| cir.get("continuationEndpoint"))
                .and_then(|ce| ce.get("continuationCommand"))
                .and_then(|cc| cc.get("token"))
                .and_then(|t| t.as_str())
            {
                reply_continuation = Some(token.to_string());
                continue;
            }
            if let Some(rr) = ri.get("commentRenderer") {
                let rrid = rr.get("commentId").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let rr_name = rr
                    .get("authorText")
                    .map(|v| {
                        if let Some(simple) = v.get("simpleText").and_then(|s| s.as_str()) {
                            sanitise(simple)
                        } else if let Some(runs) = v.get("runs").and_then(|r| r.as_array()) {
                            let joined: String = runs.iter().filter_map(|r| r.get("text").and_then(|t| t.as_str())).collect();
                            sanitise(&joined)
                        } else {
                            String::new()
                        }
                    })
                    .unwrap_or_default();
                let rr_channel = rr.get("authorEndpoint").and_then(|ae| ae.get("browseEndpoint")).and_then(|be| be.get("browseId")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                let rr_avatar = rr.get("authorThumbnail").and_then(|v| v.get("thumbnails")).and_then(|v| v.as_array()).and_then(|arr| arr.last()).and_then(|t| t.get("url").and_then(|u| u.as_str())).unwrap_or("").to_string();
                let rr_text = rr.get("contentText").map(|v| {
                    if let Some(simple) = v.get("simpleText").and_then(|s| s.as_str()) { sanitise(simple) }
                    else if let Some(runs) = v.get("runs").and_then(|r| r.as_array()) {
                        let joined: String = runs.iter().filter_map(|r| r.get("text").and_then(|t| t.as_str())).collect(); sanitise(&joined)
                    } else { String::new() }
                }).unwrap_or_default();
                let rr_likes = rr.get("voteCount").and_then(|v| v.get("simpleText")).and_then(|v| v.as_str()).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
                let rr_time = rr.get("publishedTimeText").and_then(|v| v.get("runs")).and_then(|r| r.as_array()).and_then(|arr| arr.first()).and_then(|r| r.get("text").and_then(|t| t.as_str())).unwrap_or("").to_string();
                let rr_hearted = rr.get("actionButtons").and_then(|ab| ab.get("commentActionButtonsRenderer")).and_then(|car| car.get("creatorHeart")).and_then(|ch| ch.get("creatorHeartRenderer")).and_then(|chr| chr.get("isHearted")).and_then(|v| v.as_bool()).unwrap_or(false);
                let rr_owner = rr.get("authorIsChannelOwner").and_then(|v| v.as_bool()).unwrap_or(false);

                replies.push(CommentReply {
                    id: rrid,
                    author: CommentAuthor { name: rr_name, channel_id: rr_channel, avatar: rr_avatar, is_verified: false, is_owner: rr_owner },
                    text: rr_text,
                    like_count: rr_likes,
                    like_count_raw: rr_likes,
                    published_time: rr_time,
                    is_liked_by_creator: rr_hearted,
                });
            }
        }
    }

    VideoComment {
        id,
        author: CommentAuthor { name: author_name, channel_id: author_channel, avatar: author_avatar, is_verified, is_owner },
        text,
        like_count,
        like_count_raw: like_count,
        published_time,
        reply_count,
        is_liked_by_creator: is_liked,
        is_pinned,
        replies,
        reply_continuation,
    }
}

fn parse_comment_threads(items: &[Value], limit: usize) -> (Vec<VideoComment>, Option<String>) {
    let mut comments = Vec::new();
    let mut nc = None;

    for item in items {
        if comments.len() >= limit { break; }

        if let Some(token) = item
            .get("continuationItemRenderer")
            .and_then(|cir| cir.get("continuationEndpoint"))
            .and_then(|ce| ce.get("continuationCommand"))
            .and_then(|cc| cc.get("token"))
            .and_then(|t| t.as_str())
        {
            nc = Some(token.to_string());
        }

        if let Some(ctr) = item.get("commentThreadRenderer") {
            if let Some(cr) = ctr.get("comment").and_then(|c| c.get("commentRenderer")) {
                comments.push(parse_comment_renderer(cr));
            }
        }
    }

    (comments, nc)
}

// ─── Public: Comments ─────────────────────────────────────────────────────────

pub fn get_comments(
    video_id: &str,
    limit: usize,
    continuation: Option<&str>,
) -> YtResult<(Vec<VideoComment>, Option<String>)> {
    let client = build_client()?;
    let limit = std::cmp::min(std::cmp::max(1, limit), 100);

    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let resp = client.get(&watch_url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;
    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    if let Some(cont) = continuation {
        let api_key = extract_api_key(&html)
            .unwrap_or_else(|| "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8".to_string());
        let ctx = extract_json(&html, "\"INNERTUBE_CONTEXT\"")
            .and_then(|s| serde_json::from_str::<Value>(&s).ok())
            .unwrap_or_else(|| serde_json::from_str(DEFAULT_INNERTUBE_CLIENT).unwrap());

        let body = serde_json::json!({
            "context": ctx,
            "continuation": cont,
        });

        let url = format!("https://www.youtube.com/youtubei/v1/next?key={}", api_key);
        let resp = client.post(&url)
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .map_err(|e| yterr!("InnerTube request failed: {}", e))?;
        let data: Value = resp.json().map_err(|e| yterr!("Failed to parse response: {}", e))?;

        let items = data
            .get("onResponseReceivedEndpoints")
            .and_then(|v| v.as_array())
            .and_then(|arr| arr.first())
            .and_then(|v| v.get("reloadContinuationItemsCommand"))
            .and_then(|v| v.get("continuationItems"))
            .or_else(|| {
                data.get("onResponseReceivedEndpoints")
                    .and_then(|v| v.as_array())
                    .and_then(|arr| arr.first())
                    .and_then(|v| v.get("appendContinuationItemsAction"))
                    .and_then(|v| v.get("continuationItems"))
            })
            .and_then(|v| v.as_array());

        if let Some(items) = items {
            let (comments, nc) = parse_comment_threads(items, limit);
            return Ok((comments, nc));
        }
        return Ok((vec![], None));
    }

    let data = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .and_then(|s| serde_json::from_str::<Value>(&s).ok());

    let data = match data {
        Some(d) => d,
        None => return Ok((vec![], None)),
    };

    let api_key = extract_api_key(&html)
        .unwrap_or_else(|| "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8".to_string());
    let ctx = extract_json(&html, "\"INNERTUBE_CONTEXT\"")
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .unwrap_or_else(|| serde_json::from_str(DEFAULT_INNERTUBE_CLIENT).unwrap());

    let all_results = data
        .get("contents")
        .and_then(|c| c.get("twoColumnWatchNextResults"))
        .and_then(|t| t.get("results"))
        .and_then(|r| r.get("results"))
        .and_then(|r| r.get("contents"))
        .and_then(|c| c.as_array());

    let mut token: Option<String> = None;
    if let Some(contents) = all_results {
        'outer: for c in contents {
            if let Some(items) = c.get("itemSectionRenderer").and_then(|isr| isr.get("contents")).and_then(|v| v.as_array()) {
                for item in items {
                    token = item
                        .get("continuationItemRenderer")
                        .and_then(|cir| cir.get("continuationEndpoint"))
                        .and_then(|ce| ce.get("continuationCommand"))
                        .and_then(|cc| cc.get("token"))
                        .and_then(|t| t.as_str())
                        .map(|s| s.to_string());
                    if token.is_some() { break 'outer; }
                    token = item
                        .get("commentsEntryPointHeaderRenderer")
                        .and_then(|v| v.get("contents"))
                        .and_then(|v| v.as_array())
                        .and_then(|arr| arr.first())
                        .and_then(|v| v.get("continuationItemRenderer"))
                        .and_then(|cir| cir.get("continuationEndpoint"))
                        .and_then(|ce| ce.get("continuationCommand"))
                        .and_then(|cc| cc.get("token"))
                        .and_then(|t| t.as_str())
                        .map(|s| s.to_string());
                    if token.is_some() { break 'outer; }
                }
            }
        }
    }

    let token = match token {
        Some(t) => t,
        None => return Ok((vec![], None)),
    };

    let body = serde_json::json!({
        "context": ctx,
        "continuation": token,
    });

    let url = format!("https://www.youtube.com/youtubei/v1/next?key={}", api_key);
    let resp = client.post(&url)
        .header("Content-Type", "application/json")
        .json(&body)
        .send()
        .map_err(|e| yterr!("InnerTube request failed: {}", e))?;
    let nd: Value = resp.json().map_err(|e| yterr!("Failed to parse response: {}", e))?;

    let n_items = nd
        .get("onResponseReceivedEndpoints")
        .and_then(|v| v.as_array())
        .and_then(|arr| arr.first())
        .and_then(|v| v.get("reloadContinuationItemsCommand"))
        .and_then(|v| v.get("continuationItems"))
        .or_else(|| {
            nd.get("onResponseReceivedEndpoints")
                .and_then(|v| v.as_array())
                .and_then(|arr| arr.first())
                .and_then(|v| v.get("appendContinuationItemsAction"))
                .and_then(|v| v.get("continuationItems"))
        })
        .or_else(|| {
            nd.get("onResponseReceivedEndpoints")
                .and_then(|v| v.as_array())
                .and_then(|arr| arr.get(1))
                .and_then(|v| v.get("reloadContinuationItemsCommand"))
                .and_then(|v| v.get("continuationItems"))
        })
        .or_else(|| {
            nd.get("onResponseReceivedEndpoints")
                .and_then(|v| v.as_array())
                .and_then(|arr| arr.get(1))
                .and_then(|v| v.get("appendContinuationItemsAction"))
                .and_then(|v| v.get("continuationItems"))
        })
        .and_then(|v| v.as_array());

    if let Some(items) = n_items {
        let (comments, nc) = parse_comment_threads(items, limit);
        return Ok((comments, nc));
    }

    Ok((vec![], None))
}

// ─── Public: Related Videos ───────────────────────────────────────────────────

pub fn get_related_videos(video_id: &str, limit: usize) -> YtResult<Vec<RelatedVideo>> {
    let client = build_client()?;
    let limit = std::cmp::min(std::cmp::max(1, limit), 50);

    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let resp = client.get(&watch_url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;
    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let data = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .and_then(|s| serde_json::from_str::<Value>(&s).ok());

    let data = match data {
        Some(d) => d,
        None => return Ok(vec![]),
    };

    let watch_next = data
        .get("contents")
        .and_then(|c| c.get("twoColumnWatchNextResults"))
        .and_then(|t| t.get("secondaryResults"))
        .and_then(|s| s.get("secondaryResults"))
        .and_then(|s| s.get("results"))
        .and_then(|r| r.as_array());

    let watch_next = match watch_next {
        Some(w) => w,
        None => return Ok(vec![]),
    };

    let mut results = Vec::new();
    for item in watch_next {
        if results.len() >= limit { break; }
        let vr = item.get("compactVideoRenderer").or_else(|| item.get("compactRadioRenderer"));
        let vr = match vr {
            Some(v) => v,
            None => continue,
        };

        let vid = vr.get("videoId").and_then(|v| v.as_str()).unwrap_or("");
        if vid.is_empty() { continue; }

        let title = vr.get("title").map(|v| val_str(v)).unwrap_or_default();
        let author = vr.get("shortBylineText").map(|v| val_str(v)).unwrap_or_default();
        let dur_text = vr.get("lengthText").map(|v| val_str(v)).unwrap_or_default();
        let (duration, duration_seconds) = parse_duration(&dur_text);

        let views_text = vr.get("viewCountText").map(|v| val_str(v)).unwrap_or_default();
        let view_count = views_text.clone();
        let view_count_raw = parse_view_count(&views_text);

        let published_time = vr.get("publishedTimeText").and_then(|v| v.get("simpleText")).and_then(|v| v.as_str()).unwrap_or("").to_string();

        let thumbs: Vec<Thumbnail> = vr.get("thumbnail").and_then(|t| t.get("thumbnails")).and_then(|t| t.as_array()).map(|arr| parse_thumbnails(arr)).unwrap_or_default();
        let thumbnail = best_thumbnail(&thumbs);
        let thumbnail = if thumbnail.is_empty() { format!("https://i.ytimg.com/vi/{}/hqdefault.jpg", vid) } else { thumbnail };

        let channel_url = vr
            .get("shortBylineText")
            .and_then(|s| s.get("runs"))
            .and_then(|r| r.as_array())
            .and_then(|arr| arr.first())
            .and_then(|r| r.get("navigationEndpoint"))
            .and_then(|ne| ne.get("browseEndpoint"))
            .and_then(|be| be.get("canonicalBaseUrl"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        let badge = vr
            .get("badges")
            .and_then(|b| b.as_array())
            .and_then(|arr| arr.first())
            .and_then(|b| b.get("metadataBadgeRenderer"))
            .and_then(|r| r.get("style"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        results.push(RelatedVideo {
            id: vid.to_string(),
            title,
            author,
            channel_url,
            duration,
            duration_seconds,
            view_count,
            view_count_raw,
            published_time,
            thumbnail,
            is_live: badge.to_uppercase().contains("LIVE"),
        });
    }

    Ok(results)
}

// ─── Public: Live Stream Info + Stats ─────────────────────────────────────────

pub fn get_video_stats(video_id: &str) -> YtResult<(u64, u64, u64, bool, u64)> {
    let client = build_client()?;
    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let resp = client.get(&watch_url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;
    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let data = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .and_then(|s| serde_json::from_str::<Value>(&s).ok());

    let data = match data {
        Some(d) => d,
        None => return Ok((0, 0, 0, false, 0)),
    };

    let primary = data
        .get("contents")
        .and_then(|c| c.get("twoColumnWatchNextResults"))
        .and_then(|t| t.get("results"))
        .and_then(|r| r.get("results"))
        .and_then(|r| r.get("contents"))
        .and_then(|c| c.as_array())
        .and_then(|arr| {
            arr.iter().find_map(|c| c.get("videoPrimaryInfoRenderer"))
        });

    let vcr = primary.and_then(|p| p.get("viewCount")).and_then(|v| v.get("videoViewCountRenderer"));
    let views_text = vcr
        .and_then(|v| v.get("shortViewCount"))
        .and_then(|v| v.get("simpleText"))
        .and_then(|v| v.as_str())
        .or_else(|| vcr.and_then(|v| v.get("viewCount")).and_then(|v| v.get("simpleText")).and_then(|v| v.as_str()))
        .unwrap_or("");
    let views = parse_view_count(views_text);

    let likes_str = primary
        .and_then(|p| p.get("videoActions"))
        .and_then(|v| v.get("menuRenderer"))
        .and_then(|m| m.get("topLevelButtons"))
        .and_then(|t| t.as_array())
        .and_then(|arr| arr.first())
        .and_then(|b| b.get("segmentedLikeDislikeButtonViewModel"))
        .and_then(|s| s.get("likeButtonViewModel"))
        .and_then(|l| l.get("likeButtonViewModel"))
        .and_then(|l| l.get("toggleButtonViewModel"))
        .and_then(|l| l.get("toggleButtonViewModel"))
        .and_then(|l| l.get("defaultButtonViewModel"))
        .and_then(|l| l.get("buttonViewModel"))
        .and_then(|l| l.get("accessibilityText"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let cleaned_likes = likes_str.chars().filter(|c| c.is_ascii_digit() || *c == '.' || *c == 'K' || *c == 'k' || *c == 'M' || *c == 'm' || *c == 'B' || *c == 'b').collect::<String>();
    let likes = parse_view_count(&cleaned_likes);

    let is_live = html.contains("\"isLive\":true");
    let viewer_count = if is_live {
        if let Some(cap) = regex_lite::Regex::new(r#""viewCount":\{"videoViewCountRenderer":\{"isLive":true,"viewCount":\{"simpleText":"([^"]+)""#).ok().and_then(|re| re.captures(&html)).flatten() {
            cap.get(1).map(|m| parse_view_count(m.as_str())).unwrap_or(0)
        } else { 0 }
    } else { 0 };

    Ok((views, likes, 0, is_live, viewer_count))
}

pub fn get_live_stream_info(video_id: &str) -> YtResult<LiveStreamInfo> {
    let (_, likes, _, is_live, viewer_count) = get_video_stats(video_id)?;

    let client = build_client()?;
    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let resp = client.get(&watch_url)
        .header("Accept", "text/html,application/xhtml+xml")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;
    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let (start_time, scheduled_start_time) = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
        .and_then(|data| {
            data.get("contents")
                .and_then(|c| c.get("twoColumnWatchNextResults"))
                .and_then(|t| t.get("results"))
                .and_then(|r| r.get("results"))
                .and_then(|r| r.get("contents"))
                .and_then(|c| c.as_array())
                .and_then(|arr| arr.iter().find_map(|c| c.get("videoPrimaryInfoRenderer")))
                .map(|primary| {
                    let st = primary.get("dateText").and_then(|d| d.get("simpleText")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                    let sst = primary.get("upcomingEventData").and_then(|u| u.get("startTime")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                    (st, sst)
                })
        })
        .unwrap_or((String::new(), String::new()));

    Ok(LiveStreamInfo {
        is_live,
        is_upcoming: !is_live && viewer_count == 0,
        viewer_count,
        viewer_count_str: format!("{}", viewer_count),
        start_time,
        scheduled_start_time,
        likes_count: likes,
        dislikes_count: 0,
    })
}

// ── Channel Metadata ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SocialLink {
    pub title: String,
    pub url: String,
    pub icon: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelMetadata {
    pub id: String,
    pub name: String,
    pub handle: String,
    pub description: String,
    pub subscriber_count: String,
    pub subscriber_count_raw: u64,
    pub video_count: String,
    pub video_count_raw: u64,
    pub avatar: String,
    pub banner: String,
    pub is_verified: bool,
    pub social_links: Vec<SocialLink>,
    pub url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptEntry {
    pub text: String,
    pub start: f64,
    pub duration: f64,
}

pub fn get_channel_metadata(channel_id: &str) -> YtResult<ChannelMetadata> {
    let client = build_client()?;
    let url = format!("https://www.youtube.com/channel/{}/about", channel_id);
    let resp = client.get(&url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;

    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let json_text = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .or_else(|| extract_json(&html, "ytInitialData = "));

    let empty = ChannelMetadata {
        id: channel_id.to_string(),
        name: String::new(),
        handle: String::new(),
        description: String::new(),
        subscriber_count: String::new(),
        subscriber_count_raw: 0,
        video_count: String::new(),
        video_count_raw: 0,
        avatar: String::new(),
        banner: String::new(),
        is_verified: false,
        social_links: Vec::new(),
        url: format!("https://www.youtube.com/channel/{}", channel_id),
    };

    let json_text = match json_text {
        Some(j) => j,
        None => return Ok(empty),
    };

    let data: Value = match serde_json::from_str(&json_text) {
        Ok(d) => d,
        Err(_) => return Ok(empty),
    };

    let metadata = data.get("metadata").and_then(|m| m.get("channelMetadataRenderer"));
    let header = data.get("header").and_then(|h| h.get("c4TabbedHeaderRenderer"));

    let mut about_renderer: Option<&Value> = None;
    if let Some(tabs) = data.get("contents")
        .and_then(|c| c.get("twoColumnBrowseResultsRenderer"))
        .and_then(|r| r.get("tabs"))
        .and_then(|t| t.as_array())
    {
        for tab in tabs {
            if tab.get("tabRenderer").and_then(|t| t.get("selected")).and_then(|s| s.as_bool()).unwrap_or(false) {
                about_renderer = tab.get("tabRenderer")
                    .and_then(|t| t.get("content"))
                    .and_then(|c| c.get("sectionListRenderer"))
                    .and_then(|s| s.get("contents"))
                    .and_then(|c| c.as_array())
                    .and_then(|arr| arr.first())
                    .and_then(|c| c.get("itemSectionRenderer"))
                    .and_then(|i| i.get("contents"))
                    .and_then(|c| c.as_array())
                    .and_then(|arr| arr.first())
                    .and_then(|c| c.get("channelAboutFullMetadataRenderer"));
                break;
            }
        }
    }

    let sub_text = header
        .and_then(|h| h.get("subscriberCountText"))
        .and_then(|s| s.get("simpleText"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let subs_raw = parse_view_count(&sub_text);

    let video_text = about_renderer
        .and_then(|a| a.get("videoCountText"))
        .and_then(|v| v.get("runs"))
        .and_then(|r| r.as_array())
        .and_then(|arr| arr.first())
        .and_then(|r| r.get("text"))
        .and_then(|t| t.as_str())
        .unwrap_or("")
        .to_string();
    let vc_raw = {
        let re = regex_lite::Regex::new(r"([\d,]+)").ok();
        re.and_then(|re| re.captures(&video_text).flatten())
            .and_then(|caps| caps.get(1))
            .map(|m| m.as_str().replace(',', "").parse::<u64>().unwrap_or(0))
            .unwrap_or(0)
    };

    let mut social_links = Vec::new();
    if let Some(primary_links) = about_renderer
        .and_then(|a| a.get("primaryLinks"))
        .and_then(|p| p.as_array())
    {
        for link in primary_links {
            let nav = link.get("navigationEndpoint").and_then(|n| n.get("urlEndpoint"));
            social_links.push(SocialLink {
                title: link.get("title")
                    .and_then(|t| t.get("simpleText"))
                    .and_then(|v| v.as_str())
                    .or_else(|| {
                        link.get("title")
                            .and_then(|t| t.get("runs"))
                            .and_then(|r| r.as_array())
                            .and_then(|arr| arr.first())
                            .and_then(|r| r.get("text"))
                            .and_then(|t| t.as_str())
                    })
                    .unwrap_or("")
                    .to_string(),
                url: nav.and_then(|n| n.get("url")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
                icon: link.get("icon")
                    .and_then(|i| i.get("thumbnails"))
                    .and_then(|t| t.as_array())
                    .and_then(|arr| arr.first())
                    .and_then(|t| t.get("url"))
                    .and_then(|u| u.as_str())
                    .unwrap_or("")
                    .to_string(),
            });
        }
    }

    let name = metadata
        .and_then(|m| m.get("title"))
        .and_then(|v| v.as_str())
        .or_else(|| header.and_then(|h| h.get("title")).and_then(|v| v.as_str()))
        .unwrap_or("")
        .to_string();

    let vanity_url = metadata
        .and_then(|m| m.get("vanityChannelUrl"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let handle = vanity_url
        .replace("http://www.youtube.com/", "")
        .replace("https://www.youtube.com/", "");

    let description = metadata
        .and_then(|m| m.get("description"))
        .and_then(|v| v.as_str())
        .or_else(|| {
            about_renderer
                .and_then(|a| a.get("description"))
                .and_then(|d| d.get("simpleText"))
                .and_then(|v| v.as_str())
        })
        .or_else(|| {
            about_renderer
                .and_then(|a| a.get("description"))
                .map(|d| val_str(d).as_str().to_owned())
                .as_deref()
                .filter(|s| !s.is_empty())
        })
        .unwrap_or("")
        .to_string();

    let avatar_thumbs = metadata
        .and_then(|m| m.get("avatar"))
        .and_then(|a| a.get("thumbnails"))
        .and_then(|t| t.as_array())
        .or_else(|| {
            header
                .and_then(|h| h.get("avatar"))
                .and_then(|a| a.get("thumbnails"))
                .and_then(|t| t.as_array())
        });
    let avatar = avatar_thumbs.map(|arr| {
        let thumbs: Vec<Thumbnail> = parse_thumbnails(arr);
        best_thumbnail(&thumbs)
    }).unwrap_or_default();

    let banner_thumbs = metadata
        .and_then(|m| m.get("banner"))
        .and_then(|b| b.get("thumbnails"))
        .and_then(|t| t.as_array())
        .or_else(|| {
            header
                .and_then(|h| h.get("banner"))
                .and_then(|b| b.get("thumbnails"))
                .and_then(|t| t.as_array())
        });
    let banner = banner_thumbs.map(|arr| {
        let thumbs: Vec<Thumbnail> = parse_thumbnails(arr);
        best_thumbnail(&thumbs)
    }).unwrap_or_default();

    let is_verified = header
        .and_then(|h| h.get("badges"))
        .and_then(|b| b.as_array())
        .map(|badges| {
            badges.iter().any(|badge| {
                badge.get("metadataBadgeRenderer")
                    .and_then(|r| r.get("style"))
                    .and_then(|s| s.as_str())
                    .map(|style| style.contains("VERIFIED"))
                    .unwrap_or(false)
            })
        })
        .unwrap_or(false);

    Ok(ChannelMetadata {
        id: channel_id.to_string(),
        name,
        handle,
        description,
        subscriber_count: sub_text,
        subscriber_count_raw: subs_raw,
        video_count: video_text,
        video_count_raw: vc_raw,
        avatar,
        banner,
        is_verified,
        social_links,
        url: format!("https://www.youtube.com/channel/{}", channel_id),
    })
}

// ── Transcripts ────────────────────────────────────────────────────────────────

pub fn get_transcript(video_id: &str, lang: Option<&str>) -> YtResult<Vec<TranscriptEntry>> {
    let client = build_client()?;
    let watch_url = format!("https://www.youtube.com/watch?v={}", video_id);
    let resp = client.get(&watch_url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;
    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let tracks_str = {
        let re = regex_lite::Regex::new(r#""captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])"#).ok();
        re.and_then(|re| re.captures(&html).flatten())
            .and_then(|caps| caps.get(1))
            .map(|m| m.as_str().to_string())
    };

    let tracks_str = tracks_str.or_else(|| {
        let re = regex_lite::Regex::new(r#""captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])"#).ok();
        re.and_then(|re| re.captures(&html).flatten())
            .and_then(|caps| caps.get(1))
            .map(|m| m.as_str().to_string())
    });

    let tracks_str = match tracks_str {
        Some(s) => s,
        None => return Ok(vec![]),
    };

    let tracks: Vec<Value> = match serde_json::from_str(&tracks_str) {
        Ok(v) => v,
        Err(_) => return Ok(vec![]),
    };

    let mut track_url = String::new();
    if let Some(lang) = lang {
        for track in &tracks {
            let lc = track.get("languageCode").and_then(|v| v.as_str()).unwrap_or("");
            let tn = track.get("name").and_then(|n| n.get("simpleText")).and_then(|v| v.as_str()).unwrap_or("");
            if lc == lang || tn.to_lowercase().contains(&lang.to_lowercase()) {
                track_url = track.get("baseUrl").and_then(|v| v.as_str()).unwrap_or("").to_string();
                break;
            }
        }
    }
    if track_url.is_empty() {
        track_url = tracks.iter()
            .find(|t| t.get("languageCode").and_then(|v| v.as_str()) == Some("en"))
            .or_else(|| tracks.first())
            .and_then(|t| t.get("baseUrl").and_then(|v| v.as_str()))
            .unwrap_or("")
            .to_string();
    }
    if track_url.is_empty() {
        return Ok(vec![]);
    }

    let xml_resp = client.get(&track_url)
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;
    let xml = xml_resp.text().map_err(|e| yterr!("Failed to read XML: {}", e))?;

    let mut entries = Vec::new();
    let re = regex_lite::Regex::new(r#"<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:</text>)?$"#).ok();
    if let Some(re) = re {
        for caps in re.captures_iter(&xml) {
            if let Some(raw_text) = caps.get(3) {
                let text = raw_text.as_str()
                    .replace(Regex::new(r"<[^>]+>").ok().as_ref().map_or("", |_| ""), "");
                let text = text.replace("&amp;", "&").replace("&lt;", "<")
                    .replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'");
                let text = text.trim().to_string();
                if !text.is_empty() {
                    if let (Some(start), Some(duration)) = (caps.get(1), caps.get(2)) {
                        entries.push(TranscriptEntry {
                            text,
                            start: start.as_str().parse().unwrap_or(0.0),
                            duration: duration.as_str().parse().unwrap_or(0.0),
                        });
                    }
                }
            }
        }
    }

    Ok(entries)
}

// ── Shorts Search ──────────────────────────────────────────────────────────────

pub fn search_shorts(query: &str, limit: usize, gl: Option<&str>, hl: Option<&str>) -> YtResult<SearchResponse> {
    let client = build_client()?;
    let mut region = String::new();
    if let Some(gl_val) = gl { region.push_str(&format!("&gl={}", gl_val)); }
    if let Some(hl_val) = hl { region.push_str(&format!("&hl={}", hl_val)); }

    let url = format!(
        "{}?search_query={}&sp=EgIYAQ%3D%3D{}",
        YT_SEARCH_URL,
        urlencoding(query),
        region
    );

    let resp = client.get(&url)
        .header("Accept", "text/html,application/xhtml+xml")
        .header("Accept-Language", "en-US,en;q=0.9")
        .send()
        .map_err(|e| yterr!("HTTP request failed: {}", e))?;

    let html = resp.text().map_err(|e| yterr!("Failed to read response body: {}", e))?;

    let json_text = extract_json(&html, "var ytInitialData = ")
        .or_else(|| extract_json(&html, "window[\"ytInitialData\"] = "))
        .or_else(|| extract_json(&html, "ytInitialData = "));

    let json_text = match json_text {
        Some(j) => j,
        None => return Ok(SearchResponse { results: vec![], continuation: None, api_key: None }),
    };

    let data: Value = match serde_json::from_str(&json_text) {
        Ok(d) => d,
        Err(_) => return Ok(SearchResponse { results: vec![], continuation: None, api_key: None }),
    };

    let api_key = extract_api_key(&html);

    let contents = data.get("contents")
        .and_then(|c| c.get("twoColumnSearchResultsRenderer"))
        .and_then(|r| r.get("primaryContents"))
        .and_then(|p| p.get("sectionListRenderer"))
        .and_then(|s| s.get("contents"))
        .and_then(|c| c.as_array());

    let reel_items = contents.and_then(|contents| {
        contents.iter().find_map(|section| {
            section.get("itemSectionRenderer")
                .and_then(|isr| isr.get("contents"))
                .and_then(|c| c.as_array())
                .and_then(|arr| arr.first())
                .and_then(|item| item.get("reelShelfRenderer"))
                .and_then(|rsr| rsr.get("items"))
                .and_then(|i| i.as_array())
        })
    });

    if let Some(reel_items) = reel_items {
        let mut results = Vec::new();
        for item in reel_items {
            if results.len() >= limit { break; }
            let ri = item.get("reelItemRenderer").or_else(|| item.get("shortsLockupViewModel"));
            let vid = ri.and_then(|r| r.get("videoId").and_then(|v| v.as_str()))
                .or_else(|| item.get("reelItemRenderer").and_then(|r| r.get("videoId")).and_then(|v| v.as_str()))
                .unwrap_or("");

            if vid.is_empty() { continue; }

            let title = ri.and_then(|r| r.get("headline"))
                .map(|h| {
                    h.get("simpleText").and_then(|v| v.as_str())
                        .or_else(|| {
                            h.get("runs").and_then(|r| r.as_array()).map(|runs| {
                                runs.iter().filter_map(|r| r.get("text").and_then(|t| t.as_str())).collect::<String>()
                            }).as_deref()
                        })
                        .unwrap_or("")
                })
                .unwrap_or("")
                .to_string();

            let dur_sec = ri.and_then(|r| r.get("lengthText"))
                .and_then(|l| l.get("simpleText"))
                .and_then(|v| v.as_str())
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(0);

            let fb = fallback_result_private(vid);
            results.push(VideoResult {
                id: vid.to_string(),
                title: if title.is_empty() { format!("Shorts {}", vid) } else { title },
                duration: format!("{}s", dur_sec),
                duration_seconds: dur_sec,
                is_live: false,
                is_upcoming: false,
                is_verified: false,
                thumbnail: fb.thumbnail,
                thumbnails: fb.thumbnails,
                full_url: fb.full_url,
                embed_url: fb.embed_url,
                ..Default::default()
            });
        }

        let (all_results, _) = parse_search_results_plain(&data, limit);
        let mut seen = std::collections::HashSet::new();
        let mut combined = Vec::new();
        for r in results {
            if seen.insert(r.id.clone()) { combined.push(r); }
        }
        for r in all_results {
            if seen.insert(r.id.clone()) && combined.len() < limit { combined.push(r); }
        }

        Ok(SearchResponse {
            results: combined,
            continuation: None,
            api_key,
        })
    } else {
        let (results, continuation) = parse_search_results_plain(&data, limit);
        Ok(SearchResponse { results, continuation, api_key })
    }
}

fn parse_search_results_plain(data: &Value, limit: usize) -> (Vec<VideoResult>, Option<String>) {
    let section_contents = get_section_contents(data);
    let section_contents = match section_contents {
        Some(c) => c,
        None => return (vec![], None),
    };
    let video_renderers = walk_section_list(section_contents);
    let results: Vec<VideoResult> = video_renderers.iter().take(limit).map(|vr| parse_video_renderer(vr)).collect();
    let continuation = find_continuation(section_contents);
    (results, continuation)
}

// ── Region-aware search helpers ────────────────────────────────────────────────

fn build_region_params(gl: Option<&str>, hl: Option<&str>) -> String {
    let mut parts = Vec::new();
    if let Some(gl) = gl { parts.push(format!("gl={}", gl)); }
    if let Some(hl) = hl { parts.push(format!("hl={}", hl)); }
    if parts.is_empty() { String::new() } else { format!("&{}", parts.join("&")) }
}

// ── Global Cache ──────────────────────────────────────────────────────────────

lazy_static::lazy_static! {
    static ref GLOBAL_CACHE: std::sync::Mutex<LruCache<String>> = std::sync::Mutex::new(LruCache::new(500, 300_000));
}

// ── Client Factory ────────────────────────────────────────────────────────────

pub struct YtapisClient {
    pub search: Box<dyn Fn(&str, usize) -> YtResult<SearchResponse>>,
    pub search_trending: Box<dyn Fn(usize) -> YtResult<SearchResponse>>,
    pub search_channel: Box<dyn Fn(&str, usize) -> YtResult<SearchResponse>>,
    pub search_playlist: Box<dyn Fn(&str, usize) -> YtResult<SearchResponse>>,
    pub search_continue: Box<dyn Fn(&str, usize, Option<&str>, Option<Value>, Option<&str>) -> YtResult<SearchResponse>>,
    pub get_video: Box<dyn Fn(&str) -> YtResult<VideoResult>>,
    pub get_comments: Box<dyn Fn(&str, usize, Option<&str>) -> YtResult<(Vec<VideoComment>, Option<String>)>>,
    pub get_related_videos: Box<dyn Fn(&str, usize) -> YtResult<Vec<RelatedVideo>>>,
    pub get_video_stats: Box<dyn Fn(&str) -> YtResult<(u64, u64, u64, bool, u64)>>,
    pub get_live_stream_info: Box<dyn Fn(&str) -> YtResult<LiveStreamInfo>>,
    pub get_channel_metadata: Box<dyn Fn(&str) -> YtResult<ChannelMetadata>>,
    pub get_transcript: Box<dyn Fn(&str, Option<&str>) -> YtResult<Vec<TranscriptEntry>>>,
    pub search_shorts: Box<dyn Fn(&str, usize, Option<&str>, Option<&str>) -> YtResult<SearchResponse>>,
}

pub fn create_client() -> YtapisClient {
    YtapisClient {
        search: Box::new(|q, l| search(q, l)),
        search_trending: Box::new(|l| search_trending(l)),
        search_channel: Box::new(|cid, l| search_channel(cid, l)),
        search_playlist: Box::new(|pid, l| search_playlist(pid, l)),
        search_continue: Box::new(|c, l, ak, ctx, p| search_continue(c, l, ak, ctx, p)),
        get_video: Box::new(|id| get_video(id)),
        get_comments: Box::new(|vid, l, c| get_comments(vid, l, c)),
        get_related_videos: Box::new(|vid, l| get_related_videos(vid, l)),
        get_video_stats: Box::new(|vid| get_video_stats(vid)),
        get_live_stream_info: Box::new(|vid| get_live_stream_info(vid)),
        get_channel_metadata: Box::new(|cid| get_channel_metadata(cid)),
        get_transcript: Box::new(|vid, lang| get_transcript(vid, lang)),
        search_shorts: Box::new(|q, l, gl, hl| search_shorts(q, l, gl, hl)),
    }
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_duration_colon_mm_ss() {
        let (disp, secs) = parse_duration("12:34");
        assert_eq!(disp, "12:34");
        assert_eq!(secs, 754);
    }

    #[test]
    fn test_parse_duration_colon_hh_mm_ss() {
        let (disp, secs) = parse_duration("1:02:34");
        assert_eq!(disp, "1:02:34");
        assert_eq!(secs, 3754);
    }

    #[test]
    fn test_parse_duration_empty() {
        let (disp, secs) = parse_duration("");
        assert_eq!(disp, "");
        assert_eq!(secs, 0);
    }

    #[test]
    fn test_parse_view_count_millions() {
        assert_eq!(parse_view_count("1.2M views"), 1_200_000);
    }

    #[test]
    fn test_parse_view_count_thousands() {
        assert_eq!(parse_view_count("53K views"), 53_000);
    }

    #[test]
    fn test_parse_view_count_billions() {
        assert_eq!(parse_view_count("2.5B views"), 2_500_000_000);
    }

    #[test]
    fn test_parse_view_count_plain() {
        assert_eq!(parse_view_count("12345 views"), 12_345);
    }

    #[test]
    fn test_parse_view_count_no_views() {
        assert_eq!(parse_view_count("No views"), 0);
    }

    #[test]
    fn test_parse_view_count_with_commas() {
        assert_eq!(parse_view_count("1,234,567 views"), 1_234_567);
    }

    #[test]
    fn test_extract_json_basic() {
        let html = r#"<html>var ytInitialData = {"hello":"world"};</html>"#;
        let json = extract_json(html, "var ytInitialData = ");
        assert_eq!(json, Some(r#"{"hello":"world"}"#.to_string()));
    }

    #[test]
    fn test_extract_json_nested_braces() {
        let html = r#"var ytInitialData = {"a":{"b":{"c":3}}};"#;
        let json = extract_json(html, "var ytInitialData = ");
        assert_eq!(json, Some(r#"{"a":{"b":{"c":3}}}"#.to_string()));
    }

    #[test]
    fn test_extract_json_with_strings() {
        let html = r#"var ytInitialData = {"key":"val{ue}with\"braces"};"#;
        let json = extract_json(html, "var ytInitialData = ");
        assert_eq!(json, Some(r#"{"key":"val{ue}with\"braces"}"#.to_string()));
    }

    #[test]
    fn test_extract_json_not_found() {
        let html = r#"<html>nothing here</html>"#;
        let json = extract_json(html, "var ytInitialData = ");
        assert_eq!(json, None);
    }

    #[test]
    fn test_seconds_to_display_hours() {
        assert_eq!(seconds_to_display(3754), "1:02:34");
    }

    #[test]
    fn test_seconds_to_display_minutes() {
        assert_eq!(seconds_to_display(754), "12:34");
    }

    #[test]
    fn test_seconds_to_display_zero() {
        assert_eq!(seconds_to_display(0), "0:00");
    }

    #[test]
    fn test_format_view_count() {
        assert_eq!(format_view_count(1_200_000), "1.2M views");
        assert_eq!(format_view_count(53_000), "53.0K views");
        assert_eq!(format_view_count(123), "123 views");
        assert_eq!(format_view_count(0), "No views");
    }

    #[test]
    fn test_extract_api_key() {
        let html = r#"blah"INNERTUBE_API_KEY":"AIzaSyTest123"moreblah"#;
        assert_eq!(extract_api_key(html), Some("AIzaSyTest123".to_string()));
    }

    #[test]
    fn test_extract_json_window_assignment() {
        let html = r#"window["ytInitialData"] = {"x":1};"#;
        let json = extract_json(html, r#"window["ytInitialData"] = "#);
        assert_eq!(json, Some(r#"{"x":1}"#.to_string()));
    }

    #[test]
    fn test_extract_json_malformed_unclosed() {
        let html = r#"var ytInitialData = {"a":1;"#;
        let json = extract_json(html, "var ytInitialData = ");
        assert_eq!(json, None);
    }
}
