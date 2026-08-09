// ytapis v2.0.0 — YouTube search engine in Rust
// Built by geethudinoyt & geethudino (Ruthvik). MIT License.

use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36";
const INNERTUBE_KEY: &str = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";

fn http_client() -> Client {
    Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent(UA)
        .build()
        .unwrap_or_default()
}

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
    #[serde(rename = "channelUrl")]
    pub channel_url: String,
    pub thumbnail: String,
    pub thumbnails: Vec<Thumbnail>,
    #[serde(rename = "fullUrl")]
    pub full_url: String,
    #[serde(rename = "embedUrl")]
    pub embed_url: String,
    pub duration: String,
    #[serde(rename = "durationSeconds")]
    pub duration_seconds: u64,
    #[serde(rename = "viewCount")]
    pub view_count: String,
    #[serde(rename = "viewCountRaw")]
    pub view_count_raw: u64,
    #[serde(rename = "publishedTime")]
    pub published_time: String,
    pub description: String,
    #[serde(rename = "channelAvatar")]
    pub channel_avatar: String,
    #[serde(rename = "isLive")]
    pub is_live: bool,
    #[serde(rename = "isUpcoming")]
    pub is_upcoming: bool,
    #[serde(rename = "isVerified")]
    pub is_verified: bool,
}

fn fallback(id: &str) -> VideoResult {
    let thumb = format!("https://i.ytimg.com/vi/{}/hqdefault.jpg", id);
    VideoResult {
        id: id.to_string(),
        title: format!("Video {}", id),
        author: "YouTube".into(),
        channel_url: String::new(),
        thumbnail: thumb.clone(),
        thumbnails: vec![Thumbnail { url: thumb, width: 480, height: 360 }],
        full_url: format!("https://www.youtube.com/watch?v={}", id),
        embed_url: format!("https://www.youtube.com/embed/{}?rel=0", id),
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

fn extract_runs(obj: &Value) -> String {
    obj.get("runs")
        .and_then(|r| r.as_array())
        .map(|runs| {
            runs.iter()
                .filter_map(|r| r.get("text").and_then(|t| t.as_str()))
                .collect::<Vec<_>>()
                .join("")
        })
        .unwrap_or_default()
}

fn simple_text(obj: &Value) -> String {
    obj.get("simpleText")
        .and_then(|s| s.as_str())
        .unwrap_or_default()
        .to_string()
}

fn best_thumbnail(thumbs: &[Value]) -> String {
    if thumbs.is_empty() { return String::new(); }
    let mut best = &thumbs[0];
    let mut best_score = quality_score(best.get("url").and_then(|u| u.as_str()).unwrap_or(""));
    for t in thumbs.iter().skip(1) {
        let url = t.get("url").and_then(|u| u.as_str()).unwrap_or("");
        let score = t.get("width").and_then(|w| w.as_u64()).unwrap_or(0) as i64;
        let qs = quality_score(url);
        let s = if score > 0 { score } else { qs };
        if s > best_score { best = t; best_score = s; }
    }
    best.get("url").and_then(|u| u.as_str()).unwrap_or("").to_string()
}

fn quality_score(url: &str) -> i64 {
    if url.contains("maxresdefault") { return 1280; }
    if url.contains("sddefault") { return 640; }
    if url.contains("hqdefault") { return 480; }
    if url.contains("mqdefault") { return 320; }
    120
}

fn parse_thumbs(thumbs: &Value) -> Vec<Thumbnail> {
    thumbs.as_array().map(|arr| {
        arr.iter().map(|t| Thumbnail {
            url: t.get("url").and_then(|u| u.as_str()).unwrap_or("").to_string(),
            width: t.get("width").and_then(|w| w.as_u64()).unwrap_or(0) as u32,
            height: t.get("height").and_then(|h| h.as_u64()).unwrap_or(0) as u32,
        }).collect()
    }).unwrap_or_default()
}

fn parse_duration(text: &str) -> (String, u64) {
    if text.is_empty() { return (String::new(), 0); }
    let parts: Vec<u64> = text.split(':').filter_map(|p| p.parse().ok()).collect();
    match parts.len() {
        3 => (text.to_string(), parts[0] * 3600 + parts[1] * 60 + parts[2]),
        2 => (text.to_string(), parts[0] * 60 + parts[1]),
        1 => (text.to_string(), parts[0]),
        _ => (text.to_string(), 0),
    }
}

fn parse_view_count(text: &str) -> (String, u64) {
    if text.is_empty() { return (String::new(), 0); }
    let cleaned: String = text.chars().filter(|c| c.is_ascii_digit() || *c == '.' || "KMBkmb".contains(*c)).collect();
    let num_str: String = cleaned.chars().filter(|c| c.is_ascii_digit() || *c == '.').collect();
    let num: f64 = num_str.parse().unwrap_or(0.0);
    let mult = if cleaned.to_uppercase().contains('B') { 1_000_000_000.0 }
    else if cleaned.to_uppercase().contains('M') { 1_000_000.0 }
    else if cleaned.to_uppercase().contains('K') { 1_000.0 }
    else { 1.0 };
    (text.to_string(), (num * mult).round() as u64)
}

fn text_or(obj: &Value, key: &str) -> String {
    let val = extract_runs(&obj[key]);
    if val.is_empty() { simple_text(&obj[key]) } else { val }
}

fn parse_video_renderer(vr: &Value) -> Option<VideoResult> {
    let id = vr.get("videoId")?.as_str()?;
    let title = text_or(vr, "title");
    let author = text_or(vr, "ownerText");
    let channel_url = vr["ownerText"]["runs"][0]["navigationEndpoint"]["browseEndpoint"]["canonicalBaseUrl"]
        .as_str().unwrap_or("").to_string();

    let raw_thumbs = &vr["thumbnail"]["thumbnails"];
    let thumbnails = parse_thumbs(raw_thumbs);
    let thumbnail = best_thumbnail(raw_thumbs.as_array().unwrap_or(&vec![]));

    let dur_raw = text_or(vr, "lengthText");
    let (duration, dur_sec) = parse_duration(&dur_raw);

    let vc_text = text_or(vr, "viewCountText");
    let (view_count, vc_raw) = parse_view_count(&vc_text);

    let published = simple_text(&vr["publishedTimeText"]);

    let desc_runs = extract_runs(&vr["detailedMetadataSnippets"][0]["snippetText"]);
    let desc_snippet = extract_runs(&vr["descriptionSnippet"]);
    let desc = if desc_runs.is_empty() { desc_snippet } else { desc_runs };

    let ch_thumb = best_thumbnail(
        vr["channelThumbnailSupportedRenderers"]["channelThumbnailWithLinkRenderer"]["thumbnail"]["thumbnails"]
            .as_array().unwrap_or(&vec![])
    );

    let badges: Vec<&str> = vr["badges"].as_array().map(|arr| {
        arr.iter().filter_map(|b| b["metadataBadgeRenderer"]["style"].as_str()).collect()
    }).unwrap_or_default();

    let fb = fallback(id);
    Some(VideoResult {
        id: id.to_string(),
        title: if title.is_empty() { fb.title } else { title.to_string() },
        author: if author.is_empty() { fb.author } else { author.to_string() },
        channel_url,
        thumbnail: if thumbnail.is_empty() { fb.thumbnail } else { thumbnail },
        thumbnails: if thumbnails.is_empty() { fb.thumbnails } else { thumbnails },
        full_url: fb.full_url, embed_url: fb.embed_url,
        duration: duration.clone(), duration_seconds: dur_sec,
        view_count: view_count.clone(), view_count_raw: vc_raw,
        published_time: published,
        description: desc,
        channel_avatar: ch_thumb,
        is_live: badges.iter().any(|b| b.to_uppercase().contains("LIVE")),
        is_upcoming: badges.iter().any(|b| b.to_uppercase().contains("UPCOMING")),
        is_verified: badges.iter().any(|b| b.to_uppercase().contains("VERIFIED")),
    })
}

fn extract_json(html: &str, prefix: &str) -> Option<Value> {
    let idx = html.find(prefix)?;
    let start = html[idx..].find('{')? + idx;
    let mut depth = 0i32;
    let mut in_string = false;
    let mut escaped = false;
    for (i, ch) in html[start..].char_indices() {
        if escaped { escaped = false; continue; }
        if ch == '\\' { escaped = true; continue; }
        if ch == '"' { in_string = !in_string; continue; }
        if in_string { continue; }
        if ch == '{' { depth += 1; }
        if ch == '}' { depth -= 1; if depth == 0 {
            return serde_json::from_str(&html[start..start + i + 1]).ok();
        }}
    }
    None
}

fn fetch_html(url: &str) -> Result<String, Box<dyn std::error::Error>> {
    let body = http_client().get(url).send()?.text()?;
    Ok(body)
}

fn extract_videos(contents: &[Value], limit: usize) -> Vec<VideoResult> {
    let mut results = Vec::new();
    for section in contents {
        if results.len() >= limit { break; }
        if let Some(items) = section["itemSectionRenderer"]["contents"].as_array() {
            for item in items {
                if results.len() >= limit { break; }
                if let Some(vr) = item.get("videoRenderer").and_then(parse_video_renderer) {
                    results.push(vr);
                }
            }
        }
        if let Some(shelf_items) = section["shelfRenderer"]["content"]["expandedShelfContentsRenderer"]["items"].as_array()
            .or_else(|| section["shelfRenderer"]["content"]["horizontalListRenderer"]["items"].as_array())
        {
            for item in shelf_items {
                if results.len() >= limit { break; }
                if let Some(vr) = item.get("videoRenderer").and_then(parse_video_renderer) {
                    results.push(vr);
                }
            }
        }
    }
    results
}

// ─── Public API ──────────────────────────────────────────────────

pub fn search(query: &str, limit: Option<usize>, gl: Option<&str>, hl: Option<&str>) -> Result<Vec<VideoResult>, Box<dyn std::error::Error>> {
    let limit = limit.unwrap_or(15).min(50).max(1);
    let mut url = format!("https://www.youtube.com/results?search_query={}", urlencoding(query));
    if let Some(g) = gl { url.push_str(&format!("&gl={}", g)); }
    if let Some(h) = hl { url.push_str(&format!("&hl={}", h)); }

    let html = fetch_html(&url)?;
    let data = extract_json(&html, "var ytInitialData").ok_or("could not extract ytInitialData")?;
    let contents = data["contents"]["twoColumnSearchResultsRenderer"]["primaryContents"]["sectionListRenderer"]["contents"]
        .as_array().ok_or("no contents")?;
    Ok(extract_videos(contents, limit))
}

pub fn search_trending(limit: Option<usize>) -> Result<Vec<VideoResult>, Box<dyn std::error::Error>> {
    let limit = limit.unwrap_or(15).min(50).max(1);
    let html = fetch_html("https://www.youtube.com/feed/trending")?;
    let data = extract_json(&html, "var ytInitialData").ok_or("could not extract ytInitialData")?;
    for tab in data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"].as_array().unwrap_or(&vec![]) {
        if let Some(contents) = tab["tabRenderer"]["content"]["sectionListRenderer"]["contents"].as_array() {
            return Ok(extract_videos(contents, limit));
        }
    }
    Ok(vec![])
}

pub fn search_channel(channel_id: &str, limit: Option<usize>) -> Result<Vec<VideoResult>, Box<dyn std::error::Error>> {
    let limit = limit.unwrap_or(15).min(50).max(1);
    let html = fetch_html(&format!("https://www.youtube.com/channel/{}/videos", channel_id))?;
    let data = extract_json(&html, "var ytInitialData").ok_or("no data")?;
    let mut results = Vec::new();
    for tab in data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"].as_array().unwrap_or(&vec![]) {
        if let Some(items) = tab["tabRenderer"]["content"]["richGridRenderer"]["contents"].as_array() {
            for item in items {
                if results.len() >= limit { break; }
                if let Some(vr) = item["richItemRenderer"]["content"]["videoRenderer"].as_object()
                    .or_else(|| item.get("videoRenderer").and_then(|v| v.as_object()))
                {
                    if let Some(v) = parse_video_renderer(&Value::Object(vr.clone())) {
                        results.push(v);
                    }
                }
            }
            if !results.is_empty() { break; }
        }
    }
    Ok(results)
}

pub fn search_playlist(playlist_id: &str, limit: Option<usize>) -> Result<Vec<VideoResult>, Box<dyn std::error::Error>> {
    let limit = limit.unwrap_or(15).min(50).max(1);
    let html = fetch_html(&format!("https://www.youtube.com/playlist?list={}", playlist_id))?;
    let data = extract_json(&html, "var ytInitialData").ok_or("no data")?;
    let mut results = Vec::new();
    let tabs = data["contents"]["twoColumnBrowseResultsRenderer"]["tabs"].as_array();
    if let Some(contents) = tabs.and_then(|t| t.get(0))
        .and_then(|t| t["tabRenderer"]["content"]["sectionListRenderer"]["contents"].as_array())
        .and_then(|c| c.get(0))
        .and_then(|c| c["itemSectionRenderer"]["contents"].as_array())
        .and_then(|c| c.get(0))
        .and_then(|c| c["playlistVideoListRenderer"]["contents"].as_array())
    {
        for item in contents {
            if results.len() >= limit { break; }
            if let Some(pvr) = item["playlistVideoRenderer"].as_object() {
                if let Some(id) = pvr.get("videoId").and_then(|v| v.as_str()) {
                    let title = extract_runs(&item["playlistVideoRenderer"]["title"]);
                    let author = extract_runs(&item["playlistVideoRenderer"]["shortBylineText"]);
                    let dur = text_or(&item["playlistVideoRenderer"], "lengthText");
                    let (duration, dur_sec) = parse_duration(&dur);
                    let mut fb = fallback(id);
                    if !title.is_empty() { fb.title = title; }
                    if !author.is_empty() { fb.author = author; }
                    fb.duration = duration;
                    fb.duration_seconds = dur_sec;
                    results.push(fb);
                }
            }
        }
    }
    Ok(results)
}

pub fn get_video(id: &str) -> Result<VideoResult, Box<dyn std::error::Error>> {
    let fb = fallback(id);
    let html = fetch_html(&format!("https://www.youtube.com/watch?v={}", id))?;
    let data = extract_json(&html, "var ytInitialPlayerResponse")
        .or_else(|| extract_json(&html, "var ytInitialData"));

    if let Some(data) = data {
        if let Some(vd) = data["videoDetails"].as_object() {
            let dur_sec = vd.get("lengthSeconds").and_then(|s| s.as_str()).unwrap_or("0").parse().unwrap_or(0);
            let mins = dur_sec / 60;
            let secs = dur_sec % 60;
            let hrs = mins / 60;
            let mins = mins % 60;
            let dur_str = if hrs > 0 {
                format!("{}:{:02}:{:02}", hrs, mins, secs)
            } else {
                format!("{}:{:02}", mins, secs)
            };
            let vc = vd.get("viewCount").and_then(|v| v.as_str()).unwrap_or("0").parse().unwrap_or(0);
            return Ok(VideoResult {
                id: id.to_string(),
                title: vd.get("title").and_then(|t| t.as_str()).unwrap_or(&fb.title).to_string(),
                author: vd.get("author").and_then(|a| a.as_str()).unwrap_or(&fb.author).to_string(),
                channel_url: format!("https://www.youtube.com/{}", vd.get("channelId").and_then(|c| c.as_str()).unwrap_or("")),
                thumbnail: best_thumbnail(vd["thumbnail"]["thumbnails"].as_array().unwrap_or(&vec![])),
                thumbnails: parse_thumbs(&vd["thumbnail"]),
                duration: dur_str, duration_seconds: dur_sec,
                view_count: if vc > 0 { format!("{} views", vc) } else { String::new() },
                view_count_raw: vc,
                description: vd.get("shortDescription").and_then(|d| d.as_str()).unwrap_or("").to_string(),
                channel_avatar: vd["authorThumbnails"][0]["url"].as_str().unwrap_or("").to_string(),
                ..fb
            });
        }
    }
    Ok(fb)
}

fn urlencoding(s: &str) -> String {
    s.chars().map(|c| {
        if c.is_ascii_alphanumeric() || "-_.~".contains(c) {
            c.to_string()
        } else {
            format!("%{:02X}", c as u8)
        }
    }).collect()
}

// ─── LRU Cache ────────────────────────────────────────────

pub struct LruCache<V> {
    map: Mutex<HashMap<String, (V, u128)>>,
    max_size: usize,
    ttl_ms: u128,
}

impl<V: Clone> LruCache<V> {
    pub fn new(max_size: usize, ttl_ms: u128) -> Self {
        Self { map: Mutex::new(HashMap::new()), max_size, ttl_ms }
    }

    pub fn get(&self, key: &str) -> Option<V> {
        let mut map = self.map.lock().ok()?;
        if let Some((val, expires)) = map.remove(key) {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
            if now > expires { return None; }
            map.insert(key.to_string(), (val.clone(), expires));
            Some(val)
        } else { None }
    }

    pub fn set(&self, key: &str, value: V) {
        if let Ok(mut map) = self.map.lock() {
            let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis();
            if map.len() >= self.max_size && !map.contains_key(key) {
                if let Some(k) = map.keys().next().cloned() { map.remove(&k); }
            }
            map.insert(key.to_string(), (value, now + self.ttl_ms));
        }
    }

    pub fn clear(&self) { if let Ok(mut m) = self.map.lock() { m.clear(); } }

    pub fn len(&self) -> usize { self.map.lock().map(|m| m.len()).unwrap_or(0) }
}
