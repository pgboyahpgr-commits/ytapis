import re
import json
import time
from dataclasses import dataclass, field, asdict
from urllib.request import urlopen, Request
from urllib.parse import quote
from concurrent.futures import ThreadPoolExecutor
from typing import Optional


@dataclass
class Thumbnail:
    url: str = ""
    width: int = 0
    height: int = 0


@dataclass
class VideoResult:
    id: str
    title: str = "Untitled"
    author: str = "Unknown Author"
    channel_url: str = ""
    thumbnail: str = ""
    thumbnails: list = field(default_factory=list)
    full_url: str = ""
    embed_url: str = ""
    duration: str = ""
    duration_seconds: int = 0
    view_count: str = ""
    view_count_raw: int = 0
    published_time: str = ""
    description: str = ""
    channel_avatar: str = ""
    is_live: bool = False
    is_upcoming: bool = False
    is_verified: bool = False

    def __post_init__(self):
        if not self.full_url:
            self.full_url = f"https://www.youtube.com/watch?v={self.id}"
        if not self.embed_url:
            self.embed_url = f"https://www.youtube.com/embed/{self.id}?rel=0"
        if not self.thumbnail:
            self.thumbnail = f"https://i.ytimg.com/vi/{self.id}/hqdefault.jpg"
        if not self.thumbnails:
            self.thumbnails = [{"url": self.thumbnail, "width": 480, "height": 360}]

    def to_dict(self):
        d = asdict(self)
        return d


@dataclass
class SearchResponse:
    results: list
    continuation: Optional[str] = None
    api_key: Optional[str] = None


def _fetch(url: str, data: Optional[bytes] = None) -> str:
    req = Request(url, data=data, headers={
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    })
    with urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _extract_json(html: str, prefix: str):
    idx = html.find(prefix)
    if idx == -1:
        return None
    start = html.find("{", idx)
    if start == -1:
        return None
    depth = 0
    in_string = False
    escaped = False
    for i in range(start, len(html)):
        ch = html[i]
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(html[start:i + 1])
                except (json.JSONDecodeError, ValueError):
                    return None
    return None


def _parse_duration(text: str):
    if not text:
        return "", 0
    parts = text.split(":")
    try:
        nums = [int(p) for p in parts]
    except ValueError:
        return text, 0
    if len(nums) == 3:
        return text, nums[0] * 3600 + nums[1] * 60 + nums[2]
    if len(nums) == 2:
        return text, nums[0] * 60 + nums[1]
    return text, nums[0]


def _parse_view_count(text: str):
    if not text:
        return "", 0
    cleaned = re.sub(r"[^0-9.KMBkmb]", "", text)
    try:
        num = float(re.sub(r"[KMBkmb]", "", cleaned))
    except ValueError:
        return text, 0
    upper = cleaned.upper()
    if "B" in upper:
        mult = 1_000_000_000
    elif "M" in upper:
        mult = 1_000_000
    elif "K" in upper:
        mult = 1_000
    else:
        mult = 1
    return text, round(num * mult)


def _extract_runs(runs):
    if not runs:
        return ""
    return "".join(r.get("text", "") for r in runs)


def _thumbnail_quality_score(url: str) -> int:
    if not url:
        return 0
    if "maxresdefault" in url:
        return 1280
    if "sddefault" in url:
        return 640
    if "hqdefault" in url:
        return 480
    if "mqdefault" in url:
        return 320
    if "default" in url:
        return 120
    return 0


def _best_thumbnail(thumbnails):
    if not thumbnails:
        return ""
    best = thumbnails[0]
    best_score = _thumbnail_quality_score(best.get("url", ""))
    for t in thumbnails:
        score = t.get("width", 0) if t.get("width", 0) > 0 else _thumbnail_quality_score(t.get("url", ""))
        if score > best_score:
            best = t
            best_score = score
    return best.get("url", "")


def _parse_video_renderer(vr: dict):
    try:
        vid = vr.get("videoId")
        if not vid:
            return None

        title = _extract_runs(vr.get("title", {}).get("runs"))
        author = _extract_runs(vr.get("ownerText", {}).get("runs"))
        channel_url = ""
        runs = vr.get("ownerText", {}).get("runs", [])
        if runs:
            ep = runs[0].get("navigationEndpoint", {})
            channel_url = ep.get("browseEndpoint", {}).get("canonicalBaseUrl", "")

        raw_thumbs = vr.get("thumbnail", {}).get("thumbnails", [])
        thumbs = [{"url": t.get("url", ""), "width": t.get("width", 0), "height": t.get("height", 0)} for t in raw_thumbs]
        thumbnail = _best_thumbnail(raw_thumbs)

        dur_raw = vr.get("lengthText", {})
        dur_text = dur_raw.get("simpleText") or _extract_runs(dur_raw.get("runs"))
        duration_str, duration_sec = _parse_duration(dur_text)

        vc_raw = vr.get("viewCountText", {})
        vc_text = vc_raw.get("simpleText") or _extract_runs(vc_raw.get("runs"))
        view_str, view_raw = _parse_view_count(vc_text)

        published = (vr.get("publishedTimeText") or {}).get("simpleText", "")

        desc_runs = vr.get("detailedMetadataSnippets", [{}])[0].get("snippetText", {}).get("runs") or \
                    vr.get("descriptionSnippet", {}).get("runs")
        description = _extract_runs(desc_runs)

        ch_t = (vr.get("channelThumbnailSupportedRenderers", {})
                 .get("channelThumbnailWithLinkRenderer", {})
                 .get("thumbnail", {}).get("thumbnails", []))
        channel_avatar = _best_thumbnail(ch_t)

        badges = []
        for b in vr.get("badges", []):
            mb = b.get("metadataBadgeRenderer", {})
            badges.append(mb.get("style", "") or mb.get("label", ""))

        fallback = VideoResult(id=vid)

        return VideoResult(
            id=vid,
            title=title or fallback.title,
            author=author or fallback.author,
            channel_url=channel_url,
            thumbnail=thumbnail or fallback.thumbnail,
            thumbnails=thumbs or fallback.thumbnails,
            full_url=fallback.full_url,
            embed_url=fallback.embed_url,
            duration=duration_str,
            duration_seconds=duration_sec,
            view_count=view_str,
            view_count_raw=view_raw,
            published_time=published,
            description=description,
            channel_avatar=channel_avatar,
            is_live=any("LIVE" in b.upper() for b in badges),
            is_upcoming=any("UPCOMING" in b.upper() for b in badges),
            is_verified=any("VERIFIED" in b.upper() for b in badges),
        )
    except Exception:
        return None


def _enrich_oembed(vid: str):
    try:
        u = f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={vid}&format=json"
        data = json.loads(_fetch(u))
        return {
            "title": data.get("title", ""),
            "author": data.get("author_name", ""),
            "thumbnail": data.get("thumbnail_url", ""),
        }
    except Exception:
        return {"title": "", "author": "", "thumbnail": ""}


def _parse_search_results(data: dict, limit: int):
    results = []
    continuation = None
    try:
        contents = (data.get("contents", {})
                    .get("twoColumnSearchResultsRenderer", {})
                    .get("primaryContents", {})
                    .get("sectionListRenderer", {})
                    .get("contents", []))
        for section in contents:
            if len(results) >= limit:
                break
            if "itemSectionRenderer" in section:
                for item in section["itemSectionRenderer"].get("contents", []):
                    if len(results) >= limit:
                        break
                    if "videoRenderer" in item:
                        vr = _parse_video_renderer(item["videoRenderer"])
                        if vr:
                            results.append(vr)
            if "continuationItemRenderer" in section:
                ep = section["continuationItemRenderer"].get("continuationEndpoint", {})
                continuation = ep.get("continuationCommand", {}).get("token")
    except Exception:
        pass
    return results, continuation


def get_video(video_id: str) -> VideoResult:
    fallback = VideoResult(id=video_id)
    try:
        html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
        data = _extract_json(html, "var ytInitialPlayerResponse") or \
               _extract_json(html, "var ytInitialData")

        if data:
            vd = data.get("videoDetails")
            if vd:
                dur = int(vd.get("lengthSeconds", 0))
                mins, secs = divmod(dur, 60)
                hrs, mins = divmod(mins, 60)
                dur_str = f"{hrs}:{mins:02d}:{secs:02d}" if hrs else f"{mins}:{secs:02d}"

                raw_thumbs = (vd.get("thumbnail", {}) or {}).get("thumbnails", [])
                thumbs = [{"url": t.get("url", ""), "width": t.get("width", 0), "height": t.get("height", 0)} for t in raw_thumbs]

                return VideoResult(
                    id=video_id,
                    title=vd.get("title", fallback.title),
                    author=vd.get("author", fallback.author),
                    channel_url=f"https://www.youtube.com/{vd.get('channelId', '')}",
                    thumbnail=_best_thumbnail(raw_thumbs) or fallback.thumbnail,
                    thumbnails=thumbs or [{"url": fallback.thumbnail, "width": 480, "height": 360}],
                    full_url=fallback.full_url,
                    embed_url=fallback.embed_url,
                    duration=dur_str,
                    duration_seconds=dur,
                    view_count=f"{int(vd.get('viewCount', 0)):,} views" if vd.get("viewCount") else "",
                    view_count_raw=int(vd.get("viewCount", 0)),
                    description=vd.get("shortDescription", ""),
                    channel_avatar=(vd.get("authorThumbnails", [{}])[0] or {}).get("url", ""),
                )

        enrich = _enrich_oembed(video_id)
        return VideoResult(
            id=video_id,
            title=enrich["title"] or fallback.title,
            author=enrich["author"] or fallback.author,
            thumbnail=enrich["thumbnail"] or fallback.thumbnail,
            full_url=fallback.full_url,
            embed_url=fallback.embed_url,
        )
    except Exception:
        return fallback


def search(query: str, limit: int = 15, gl: Optional[str] = None, hl: Optional[str] = None) -> list[VideoResult]:
    limit = max(1, min(limit, 50))
    url = f"https://www.youtube.com/results?search_query={quote(query)}"
    if gl:
        url += f"&gl={gl}"
    if hl:
        url += f"&hl={hl}"
    html = _fetch(url)

    data = _extract_json(html, "var ytInitialData")
    if not data:
        return []

    results, _ = _parse_search_results(data, limit)

    needs = [r for r in results if not r.title or r.title == f"Video {r.id}" or r.author == "Unknown Author"]
    if needs:
        with ThreadPoolExecutor(max_workers=min(len(needs), 10)) as pool:
            enriched = list(pool.map(lambda r: _enrich_oembed(r.id), needs))
        for r, e in zip(needs, enriched):
            if e["title"]:
                r.title = e["title"]
            if e["author"]:
                r.author = e["author"]
            if e["thumbnail"] and e["thumbnail"] != r.thumbnail:
                r.thumbnail = e["thumbnail"]

    return results


def _parse_trending_results(data: dict, limit: int):
    results = []
    continuation = None
    try:
        tabs = (data.get("contents", {}).get("twoColumnBrowseResultsRenderer", {}).get("tabs", []))
        for tab in tabs:
            contents = (tab.get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", []))
            if contents:
                for section in contents:
                    if len(results) >= limit:
                        break
                    if "itemSectionRenderer" in section:
                        for item in section["itemSectionRenderer"].get("contents", []):
                            if len(results) >= limit:
                                break
                            if "videoRenderer" in item:
                                vr = _parse_video_renderer(item["videoRenderer"])
                                if vr:
                                    results.append(vr)
                    if "shelfRenderer" in section:
                        shelf_items = (section["shelfRenderer"].get("content", {}).get("expandedShelfContentsRenderer", {}).get("items")
                                       or section["shelfRenderer"].get("content", {}).get("horizontalListRenderer", {}).get("items", []))
                        for item in shelf_items:
                            if len(results) >= limit:
                                break
                            if "videoRenderer" in item:
                                vr = _parse_video_renderer(item["videoRenderer"])
                                if vr:
                                    results.append(vr)
                    if "continuationItemRenderer" in section:
                        ep = section["continuationItemRenderer"].get("continuationEndpoint", {})
                        continuation = ep.get("continuationCommand", {}).get("token")
                if results:
                    break
    except Exception:
        pass
    return results, continuation


def _parse_channel_results(data: dict, limit: int):
    results = []
    continuation = None
    try:
        tabs = (data.get("contents", {}).get("twoColumnBrowseResultsRenderer", {}).get("tabs", []))
        for tab in tabs:
            contents = (tab.get("tabRenderer", {}).get("content", {}).get("richGridRenderer", {}).get("contents")
                        or tab.get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", []))
            if contents:
                for item in contents:
                    if len(results) >= limit:
                        break
                    if "continuationItemRenderer" in item:
                        ep = item["continuationItemRenderer"].get("continuationEndpoint", {})
                        continuation = ep.get("continuationCommand", {}).get("token")
                    if "richItemRenderer" in item:
                        vr = _parse_video_renderer(item["richItemRenderer"].get("content", {}).get("videoRenderer", {}))
                        if vr:
                            results.append(vr)
                    if "videoRenderer" in item:
                        vr = _parse_video_renderer(item["videoRenderer"])
                        if vr:
                            results.append(vr)
                if results:
                    break
    except Exception:
        pass
    return results, continuation


def _parse_playlist_results(data: dict, limit: int):
    results = []
    continuation = None
    try:
        contents = (data.get("contents", {}).get("twoColumnBrowseResultsRenderer", {}).get("tabs", [{}])[0]
                    .get("tabRenderer", {}).get("content", {}).get("sectionListRenderer", {}).get("contents", [{}])[0]
                    .get("itemSectionRenderer", {}).get("contents", [{}])[0]
                    .get("playlistVideoListRenderer", {}).get("contents", []))
        if not contents:
            alt = (data.get("contents", {}).get("twoColumnWatchNextResults", {}).get("playlist", {}).get("playlist", {}).get("contents", []))
            if not alt:
                return results, continuation
            for item in alt:
                if len(results) >= limit:
                    break
                if "continuationItemRenderer" in item:
                    ep = item["continuationItemRenderer"].get("continuationEndpoint", {})
                    continuation = ep.get("continuationCommand", {}).get("token")
                if "playlistVideoRenderer" in item:
                    pvr = item["playlistVideoRenderer"]
                    vid = pvr.get("videoId")
                    if not vid:
                        continue
                    title = _extract_runs(pvr.get("title", {}).get("runs"))
                    author = _extract_runs(pvr.get("shortBylineText", {}).get("runs"))
                    dur_raw = pvr.get("lengthText", {})
                    dur_text = dur_raw.get("simpleText") or _extract_runs(dur_raw.get("runs"))
                    duration_str, duration_sec = _parse_duration(dur_text)
                    raw_thumbs = pvr.get("thumbnail", {}).get("thumbnails", [])
                    fb = VideoResult(id=vid)
                    results.append(VideoResult(
                        id=vid, title=title or fb.title, author=author or fb.author,
                        thumbnail=_best_thumbnail(raw_thumbs) or fb.thumbnail,
                        duration=duration_str, duration_seconds=duration_sec,
                    ))
            return results, continuation

        for item in contents:
            if len(results) >= limit:
                break
            if "continuationItemRenderer" in item:
                ep = item["continuationItemRenderer"].get("continuationEndpoint", {})
                continuation = ep.get("continuationCommand", {}).get("token")
            if "playlistVideoRenderer" in item:
                pvr = item["playlistVideoRenderer"]
                vid = pvr.get("videoId")
                if not vid:
                    continue
                title = _extract_runs(pvr.get("title", {}).get("runs"))
                author = _extract_runs(pvr.get("shortBylineText", {}).get("runs"))
                dur_raw = pvr.get("lengthText", {})
                dur_text = dur_raw.get("simpleText") or _extract_runs(dur_raw.get("runs"))
                duration_str, duration_sec = _parse_duration(dur_text)
                raw_thumbs = pvr.get("thumbnail", {}).get("thumbnails", [])
                fb = VideoResult(id=vid)
                results.append(VideoResult(
                    id=vid, title=title or fb.title, author=author or fb.author,
                    thumbnail=_best_thumbnail(raw_thumbs) or fb.thumbnail,
                    duration=duration_str, duration_seconds=duration_sec,
                ))
    except Exception:
        pass
    return results, continuation


def _parse_continuation_results(data: dict, limit: int, path: str = "search"):
    results = []
    continuation = None
    try:
        items = None
        if path == "channel":
            items = (data.get("onResponseReceivedActions", [{}])[0].get("appendContinuationItemsAction", {}).get("continuationItems"))
            if not items:
                items = (data.get("onResponseReceivedEndpoints", [{}])[0].get("appendContinuationItemsAction", {}).get("continuationItems"))
        elif path == "playlist":
            items = (data.get("onResponseReceivedActions", [{}])[0].get("appendContinuationItemsAction", {}).get("continuationItems"))
        else:
            items = (data.get("onResponseReceivedEndpoints", [{}])[0].get("appendContinuationItemsAction", {}).get("continuationItems"))
        if not items:
            return results, continuation

        for item in items:
            if len(results) >= limit:
                break
            if "continuationItemRenderer" in item:
                ep = item["continuationItemRenderer"].get("continuationEndpoint", {})
                continuation = ep.get("continuationCommand", {}).get("token")
            if path == "playlist" and "playlistVideoRenderer" in item:
                pvr = item["playlistVideoRenderer"]
                vid = pvr.get("videoId")
                if vid:
                    title = _extract_runs(pvr.get("title", {}).get("runs"))
                    author = _extract_runs(pvr.get("shortBylineText", {}).get("runs"))
                    dur_raw = pvr.get("lengthText", {})
                    dur_text = dur_raw.get("simpleText") or _extract_runs(dur_raw.get("runs"))
                    duration_str, duration_sec = _parse_duration(dur_text)
                    fb = VideoResult(id=vid)
                    results.append(VideoResult(
                        id=vid, title=title or fb.title, author=author or fb.author,
                        duration=duration_str, duration_seconds=duration_sec,
                    ))
                continue
            vr = item.get("videoRenderer") or item.get("richItemRenderer", {}).get("content", {}).get("videoRenderer")
            if vr:
                parsed = _parse_video_renderer(vr)
                if parsed:
                    results.append(parsed)
    except Exception:
        pass
    return results, continuation


def _extract_api_keys(html: str):
    import re as _re
    match = _re.search(r'"INNERTUBE_API_KEY":"(AIza[^"]+)"', html)
    api_key = match.group(1) if match else None
    ctx = _extract_json(html, '"INNERTUBE_CONTEXT"')
    return api_key, ctx


def search_trending(limit: int = 15, gl: Optional[str] = None, hl: Optional[str] = None) -> list[VideoResult]:
    limit = max(1, min(limit, 50))
    url = "https://www.youtube.com/feed/trending"
    params = []
    if gl:
        params.append(f"gl={gl}")
    if hl:
        params.append(f"hl={hl}")
    if params:
        url += "?" + "&".join(params)
    html = _fetch(url)
    data = _extract_json(html, "var ytInitialData")
    if not data:
        return []
    results, _ = _parse_trending_results(data, limit)
    return results


def search_channel(channel_id: str, limit: int = 15, gl: Optional[str] = None, hl: Optional[str] = None) -> list[VideoResult]:
    limit = max(1, min(limit, 50))
    url = f"https://www.youtube.com/channel/{channel_id}/videos"
    params = []
    if gl:
        params.append(f"gl={gl}")
    if hl:
        params.append(f"hl={hl}")
    if params:
        url += "?" + "&".join(params)
    html = _fetch(url)
    data = _extract_json(html, "var ytInitialData")
    if not data:
        return []
    results, _ = _parse_channel_results(data, limit)
    needs = [r for r in results if not r.title or r.title == f"Video {r.id}" or r.author == "Unknown Author"]
    if needs:
        with ThreadPoolExecutor(max_workers=min(len(needs), 10)) as pool:
            enriched = list(pool.map(lambda r: _enrich_oembed(r.id), needs))
        for r, e in zip(needs, enriched):
            if e["title"]:
                r.title = e["title"]
            if e["author"]:
                r.author = e["author"]
            if e["thumbnail"] and e["thumbnail"] != r.thumbnail:
                r.thumbnail = e["thumbnail"]
    return results


def search_playlist(playlist_id: str, limit: int = 15, gl: Optional[str] = None, hl: Optional[str] = None) -> list[VideoResult]:
    limit = max(1, min(limit, 50))
    url = f"https://www.youtube.com/playlist?list={playlist_id}"
    if gl:
        url += f"&gl={gl}"
    if hl:
        url += f"&hl={hl}"
    html = _fetch(url)
    data = _extract_json(html, "var ytInitialData")
    if not data:
        return []
    results, _ = _parse_playlist_results(data, limit)
    needs = [r for r in results if not r.title or r.title == f"Video {r.id}" or r.author == "Unknown Author"]
    if needs:
        with ThreadPoolExecutor(max_workers=min(len(needs), 10)) as pool:
            enriched = list(pool.map(lambda r: _enrich_oembed(r.id), needs))
        for r, e in zip(needs, enriched):
            if e["title"]:
                r.title = e["title"]
            if e["author"]:
                r.author = e["author"]
            if e["thumbnail"] and e["thumbnail"] != r.thumbnail:
                r.thumbnail = e["thumbnail"]
    return results


def search_continue(continuation: str, limit: int = 15, api_key: Optional[str] = None, context: Optional[dict] = None, path: str = "search") -> SearchResponse:
    limit = max(1, min(limit, 50))
    key = api_key or "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    ctx = context or {"client": {"hl": "en", "gl": "US", "clientName": "WEB", "clientVersion": "2.20240801.00.00"}}
    body = json.dumps({"context": ctx, "continuation": continuation}).encode("utf-8")
    raw = _fetch(f"https://www.youtube.com/youtubei/v1/search?key={key}", data=body)
    data = json.loads(raw) if raw else {}
    results, next_continuation = _parse_continuation_results(data, limit, path)
    needs = [r for r in results if not r.title or r.title == f"Video {r.id}" or r.author == "Unknown Author"]
    if needs:
        with ThreadPoolExecutor(max_workers=min(len(needs), 10)) as pool:
            enriched = list(pool.map(lambda r: _enrich_oembed(r.id), needs))
        for r, e in zip(needs, enriched):
            if e["title"]:
                r.title = e["title"]
            if e["author"]:
                r.author = e["author"]
            if e["thumbnail"] and e["thumbnail"] != r.thumbnail:
                r.thumbnail = e["thumbnail"]
    return SearchResponse(results=results, continuation=next_continuation, api_key=api_key, context=context)


def search_dicts(query: str, limit: int = 15) -> list[dict]:
    return [r.to_dict() for r in search(query, limit)]


# ─── Comment Types ───────────────────────────────────────

@dataclass
class CommentAuthor:
    name: str = ""
    channel_id: str = ""
    avatar: str = ""
    is_verified: bool = False
    is_owner: bool = False


@dataclass
class CommentReply:
    id: str = ""
    author: Optional[CommentAuthor] = None
    text: str = ""
    like_count: int = 0
    like_count_raw: int = 0
    published_time: str = ""
    is_liked_by_creator: bool = False


@dataclass
class VideoComment:
    id: str = ""
    author: Optional[CommentAuthor] = None
    text: str = ""
    like_count: int = 0
    like_count_raw: int = 0
    published_time: str = ""
    reply_count: int = 0
    is_liked_by_creator: bool = False
    is_pinned: bool = False
    replies: list = field(default_factory=list)
    reply_continuation: Optional[str] = None


@dataclass
class RelatedVideo:
    id: str = ""
    title: str = ""
    author: str = ""
    channel_url: str = ""
    duration: str = ""
    duration_seconds: int = 0
    view_count: str = ""
    view_count_raw: int = 0
    published_time: str = ""
    thumbnail: str = ""
    is_live: bool = False


@dataclass
class LiveStreamInfo:
    is_live: bool = False
    is_upcoming: bool = False
    viewer_count: int = 0
    viewer_count_str: str = "0"
    start_time: str = ""
    scheduled_start_time: str = ""
    likes_count: int = 0
    dislikes_count: int = 0


# ─── LRU Cache ─────────────────────────────────────────

class LRUCache:
    def __init__(self, max_size: int = 500, ttl_ms: int = 300_000):
        self._max_size = max_size
        self._ttl_ms = ttl_ms
        self._map = {}

    def get(self, key: str):
        entry = self._map.get(key)
        if not entry:
            return None
        if time.time() * 1000 > entry[1]:
            del self._map[key]
            return None
        del self._map[key]
        self._map[key] = entry
        return entry[0]

    def set(self, key: str, value):
        if key in self._map:
            del self._map[key]
        elif len(self._map) >= self._max_size:
            del self._map[next(iter(self._map))]
        self._map[key] = (value, time.time() * 1000 + self._ttl_ms)

    def clear(self):
        self._map.clear()

    @property
    def size(self):
        return len(self._map)


# ─── Retry ─────────────────────────────────────────────

def with_retry(func, max_retries: int = 3, base_delay: float = 0.5, max_delay: float = 5.0):
    import random
    last_err = None
    for attempt in range(max_retries + 1):
        try:
            return func()
        except Exception as e:
            last_err = e
            if attempt >= max_retries:
                raise last_err
            delay = min(base_delay * (2 ** attempt) + random.random() * 0.5, max_delay)
            time.sleep(delay)


# ─── Comments ───────────────────────────────────────────

def _parse_comment_renderer(cr: dict) -> VideoComment:
    rid = cr.get("commentId") or cr.get("comment_id", "")
    name = _extract_runs(cr.get("authorText", {}).get("runs")) or cr.get("authorText", {}).get("simpleText", "")
    channel = (cr.get("authorEndpoint", {}).get("browseEndpoint", {}) or {}).get("browseId", "")
    avatar = ""
    thumbs = (cr.get("authorThumbnail", {}) or {}).get("thumbnails", [])
    if thumbs:
        avatar = thumbs[-1].get("url", "")
    is_verified = "CHECK" in str(cr.get("authorCommentBadge", {}).get("authorCommentBadgeRenderer", {}).get("icon", {}).get("iconType", ""))
    is_owner = cr.get("authorIsChannelOwner", False)
    text = _extract_runs(cr.get("contentText", {}).get("runs")) or cr.get("contentText", {}).get("simpleText", "")
    likes = int((cr.get("voteCount", {}) or {}).get("simpleText", "0") or "0")
    published = (cr.get("publishedTimeText", {}) or {}).get("runs", [{}])[0].get("text", "")
    reply_count = cr.get("replyCount", 0)
    is_pinned = "pinnedCommentBadge" in cr

    replies = []
    reply_cont = None
    reply_contents = (cr.get("replies", {}) or {}).get("commentRepliesRenderer", {}).get("contents", [])
    for item in reply_contents or []:
        tok = item.get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token")
        if tok:
            reply_cont = tok
            continue
        if "commentRenderer" in item:
            rr = item["commentRenderer"]
            replies.append(CommentReply(
                id=rr.get("commentId", ""),
                author=CommentAuthor(
                    name=_extract_runs(rr.get("authorText", {}).get("runs")) or rr.get("authorText", {}).get("simpleText", ""),
                    channel_id=(rr.get("authorEndpoint", {}).get("browseEndpoint", {}) or {}).get("browseId", ""),
                    avatar=((rr.get("authorThumbnail", {}) or {}).get("thumbnails", [{}])[-1] or {}).get("url", ""),
                    is_owner=rr.get("authorIsChannelOwner", False),
                ),
                text=_extract_runs(rr.get("contentText", {}).get("runs")) or rr.get("contentText", {}).get("simpleText", ""),
                like_count=int((rr.get("voteCount", {}) or {}).get("simpleText", "0") or "0"),
                like_count_raw=int((rr.get("voteCount", {}) or {}).get("simpleText", "0") or "0"),
                published_time=(rr.get("publishedTimeText", {}) or {}).get("runs", [{}])[0].get("text", ""),
                is_liked_by_creator=(rr.get("actionButtons", {}).get("commentActionButtonsRenderer", {}).get("creatorHeart", {}).get("creatorHeartRenderer", {}) or {}).get("isHearted", False),
            ))

    return VideoComment(
        id=rid, text=text, like_count=likes, like_count_raw=likes,
        published_time=published, reply_count=reply_count,
        is_liked_by_creator=cr.get("isLiked", False), is_pinned=is_pinned,
        replies=replies, reply_continuation=reply_cont,
        author=CommentAuthor(name=name, channel_id=channel, avatar=avatar, is_verified=is_verified, is_owner=is_owner),
    )


def get_comments(video_id: str, limit: int = 20, sort_by: str = "top", continuation: Optional[str] = None):
    limit = max(1, min(limit, 100))
    try:
        if continuation:
            html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
            api_key = re.search(r'"INNERTUBE_API_KEY":"(AIza[^"]+)"', html)
            key = api_key.group(1) if api_key else "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
            ctx = _extract_json(html, '"INNERTUBE_CONTEXT"')
            body = json.dumps({"context": ctx or {"client": {"hl": "en", "gl": "US", "clientName": "WEB", "clientVersion": "2.20240801.00.00"}}, "continuation": continuation}).encode()
            raw = _fetch(f"https://www.youtube.com/youtubei/v1/next?key={key}", data=body)
            data = json.loads(raw) if raw else {}
            eps = data.get("onResponseReceivedEndpoints", [{}])
            items = eps[0].get("reloadContinuationItemsCommand", {}).get("continuationItems") or \
                    eps[0].get("appendContinuationItemsAction", {}).get("continuationItems")
            if not items:
                return [], None
            comments = []
            nc = None
            for item in items:
                if len(comments) >= limit:
                    break
                tok = item.get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token")
                if tok:
                    nc = tok
                if "commentThreadRenderer" in item:
                    ctr = item["commentThreadRenderer"]
                    cr = (ctr.get("comment", {}) or {}).get("commentRenderer", {})
                    if ctr.get("replies"):
                        cr["replies"] = ctr["replies"]
                    comments.append(_parse_comment_renderer(cr))
            return comments, nc

        html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
        data = _extract_json(html, "var ytInitialData")
        if not data:
            return [], None

        api_key = re.search(r'"INNERTUBE_API_KEY":"(AIza[^"]+)"', html)
        key = api_key.group(1) if api_key else "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
        ctx = _extract_json(html, '"INNERTUBE_CONTEXT"')

        token = ""
        for c in (data.get("contents", {}).get("twoColumnWatchNextResults", {}).get("results", {}).get("results", {}).get("contents", []) or []):
            for item in (c.get("itemSectionRenderer", {}).get("contents", []) or []):
                token = item.get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token", "")
                if token:
                    break
                ep = item.get("commentsEntryPointHeaderRenderer", {}).get("contents", [{}])
                token = ep[0].get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token", "") if ep else ""
                if token:
                    break
            if token:
                break
        if not token:
            return [], None

        body = json.dumps({"context": ctx or {"client": {"hl": "en", "gl": "US", "clientName": "WEB", "clientVersion": "2.20240801.00.00"}}, "continuation": token}).encode()
        raw = _fetch(f"https://www.youtube.com/youtubei/v1/next?key={key}", data=body)
        nd = json.loads(raw) if raw else {}
        eps = nd.get("onResponseReceivedEndpoints", [{}])
        items = eps[0].get("reloadContinuationItemsCommand", {}).get("continuationItems") or \
                eps[0].get("appendContinuationItemsAction", {}).get("continuationItems") or \
                (eps[1] if len(eps) > 1 else {}).get("reloadContinuationItemsCommand", {}).get("continuationItems") or \
                (eps[1] if len(eps) > 1 else {}).get("appendContinuationItemsAction", {}).get("continuationItems")
        if not items:
            return [], None

        comments = []
        nc = None
        for item in items:
            if len(comments) >= limit:
                break
            tok = item.get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token")
            if tok:
                nc = tok
            if "commentThreadRenderer" in item:
                ctr = item["commentThreadRenderer"]
                cr = (ctr.get("comment", {}) or {}).get("commentRenderer", {})
                if ctr.get("replies"):
                    cr["replies"] = ctr["replies"]
                comments.append(_parse_comment_renderer(cr))
        return comments, nc
    except Exception:
        return [], None


# ─── Related Videos ─────────────────────────────────────

def get_related_videos(video_id: str, limit: int = 15):
    limit = max(1, min(limit, 50))
    try:
        html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
        data = _extract_json(html, "var ytInitialData")
        if not data:
            return []

        watch_next = (data.get("contents", {})
                      .get("twoColumnWatchNextResults", {})
                      .get("secondaryResults", {})
                      .get("secondaryResults", {})
                      .get("results", []))
        if not watch_next:
            return []

        results = []
        for item in watch_next:
            if len(results) >= limit:
                break
            vr = item.get("compactVideoRenderer") or item.get("compactRadioRenderer")
            if not vr:
                continue
            vid = vr.get("videoId")
            if not vid:
                continue
            title = _extract_runs(vr.get("title", {}).get("runs")) or vr.get("title", {}).get("simpleText", "")
            author = _extract_runs(vr.get("shortBylineText", {}).get("runs")) or vr.get("shortBylineText", {}).get("simpleText", "")
            dur_text = vr.get("lengthText", {}).get("simpleText", "") or _extract_runs(vr.get("lengthText", {}).get("runs"))
            dur_str, dur_sec = _parse_duration(dur_text)
            views_text = vr.get("viewCountText", {}).get("simpleText", "") or _extract_runs(vr.get("viewCountText", {}).get("runs"))
            view_str, view_raw = _parse_view_count(views_text)
            published = (vr.get("publishedTimeText", {}) or {}).get("simpleText", "")
            thumbnail = _best_thumbnail(vr.get("thumbnail", {}).get("thumbnails", []))
            badge = (vr.get("badges", [{}])[0].get("metadataBadgeRenderer", {}) or {}).get("style", "")

            results.append(RelatedVideo(
                id=vid, title=title, author=author, duration=dur_str, duration_seconds=dur_sec,
                view_count=view_str, view_count_raw=round(view_raw), published_time=published,
                thumbnail=thumbnail or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
                is_live="LIVE" in badge.upper(),
                channel_url=(vr.get("shortBylineText", {}).get("runs", [{}])[0].get("navigationEndpoint", {}).get("browseEndpoint", {}) or {}).get("canonicalBaseUrl", ""),
            ))
        return results
    except Exception:
        return []


# ─── Live Stream + Stats ────────────────────────────────

def get_video_stats(video_id: str):
    try:
        html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
        data = _extract_json(html, "var ytInitialData")
        if not data:
            return {"views": 0, "likes": 0, "comments": 0, "is_live": False, "viewer_count": 0}

        contents = (data.get("contents", {}).get("twoColumnWatchNextResults", {}).get("results", {}).get("results", {}).get("contents", []) or [])
        primary = None
        for c in contents:
            if "videoPrimaryInfoRenderer" in c:
                primary = c["videoPrimaryInfoRenderer"]
                break

        views_text = ""
        if primary:
            vcr = primary.get("viewCount", {}).get("videoViewCountRenderer", {})
            views_text = vcr.get("shortViewCount", {}).get("simpleText", "") or vcr.get("viewCount", {}).get("simpleText", "")
        _, views = _parse_view_count(views_text)

        likes = 0
        if primary:
            tb = primary.get("videoActions", {}).get("menuRenderer", {}).get("topLevelButtons", [{}])
            like_text = ""
            if tb:
                like_text = (tb[0].get("segmentedLikeDislikeButtonViewModel", {}).get("likeButtonViewModel", {}).get("likeButtonViewModel", {})
                             .get("toggleButtonViewModel", {}).get("toggleButtonViewModel", {}).get("defaultButtonViewModel", {}).get("buttonViewModel", {})
                             .get("accessibilityText", ""))
            likes = _parse_view_count(re.sub(r"[^0-9.KMBkmb]", "", like_text))[1]

        is_live = '"isLive": true' in html or '"isLive":true' in html
        vcm = re.search(r'"viewCount":{"videoViewCountRenderer":{"isLive":true,"viewCount":{"simpleText":"([^"]+)"', html)
        viewer_count = _parse_view_count(vcm.group(1))[1] if vcm else 0

        return {"views": int(views), "likes": int(likes), "comments": 0, "is_live": is_live, "viewer_count": viewer_count}
    except Exception:
        return {"views": 0, "likes": 0, "comments": 0, "is_live": False, "viewer_count": 0}


def get_live_stream_info(video_id: str):
    stats = get_video_stats(video_id)
    try:
        html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
        data = _extract_json(html, "var ytInitialData")
        contents = []
        if data:
            contents = (data.get("contents", {}).get("twoColumnWatchNextResults", {}).get("results", {}).get("results", {}).get("contents", []) or [])
        primary = None
        for c in contents:
            if "videoPrimaryInfoRenderer" in c:
                primary = c["videoPrimaryInfoRenderer"]
                break
        return LiveStreamInfo(
            is_live=stats["is_live"],
            is_upcoming=(not stats["is_live"] and stats["viewer_count"] == 0),
            viewer_count=stats["viewer_count"],
            viewer_count_str=f'{stats["viewer_count"]:,}',
            start_time=(primary or {}).get("dateText", {}).get("simpleText", ""),
            scheduled_start_time=(primary or {}).get("upcomingEventData", {}).get("startTime", ""),
            likes_count=stats["likes"],
        )
    except Exception:
        return LiveStreamInfo(is_live=stats["is_live"], viewer_count=stats["viewer_count"], viewer_count_str=f'{stats["viewer_count"]:,}', likes_count=stats["likes"])


# ─── Client Factory ─────────────────────────────────────

_global_cache = LRUCache(500, 300_000)


def create_client(cache=None, retry=True, max_retries=3):
    cache = cache or _global_cache

    def cached_fetch(url, data=None):
        cache_key = url + (data.decode() if data else "")
        if not data:
            cached = cache.get(cache_key)
            if cached:
                return cached
        result = _fetch(url, data)
        if not data and isinstance(result, str):
            try:
                cache.set(cache_key, json.loads(result))
            except Exception:
                pass
        return result

    def do_search(q, limit=15):
        return search(q, limit)

    def do_trending(limit=15):
        return search_trending(limit)

    def do_channel(cid, limit=15):
        return search_channel(cid, limit)

    def do_playlist(pid, limit=15):
        return search_playlist(pid, limit)

    def do_get_video(vid):
        return get_video(vid)

    def do_get_comments(vid, limit=20, sort_by="top"):
        return get_comments(vid, limit, sort_by)

    def do_get_related(vid, limit=15):
        return get_related_videos(vid, limit)

    def do_get_stats(vid):
        return get_video_stats(vid)

    def do_get_live(vid):
        return get_live_stream_info(vid)

    def do_get_channel_metadata(cid):
        return get_channel_metadata(cid)

    def do_search_shorts(q, limit=15):
        return search_shorts(q, limit)

    def do_get_transcript(vid, lang=None):
        return get_transcript(vid, lang)

    return type("YtapisClient", (), {
        "search": staticmethod(do_search),
        "search_trending": staticmethod(do_trending),
        "search_channel": staticmethod(do_channel),
        "search_playlist": staticmethod(do_playlist),
        "get_video": staticmethod(do_get_video),
        "get_comments": staticmethod(do_get_comments),
        "get_related_videos": staticmethod(do_get_related),
        "get_video_stats": staticmethod(do_get_stats),
        "get_live_stream_info": staticmethod(do_get_live),
        "get_channel_metadata": staticmethod(do_get_channel_metadata),
        "search_shorts": staticmethod(do_search_shorts),
        "get_transcript": staticmethod(do_get_transcript),
        "cache": cache,
    })()


# ─── Channel Metadata ───────────────────────────────────

@dataclass
class ChannelMetadata:
    id: str = ""
    name: str = ""
    handle: str = ""
    description: str = ""
    subscriber_count: str = ""
    subscriber_count_raw: int = 0
    video_count: str = ""
    video_count_raw: int = 0
    avatar: str = ""
    banner: str = ""
    is_verified: bool = False
    social_links: list = field(default_factory=list)
    url: str = ""


def get_channel_metadata(channel_id: str):
    empty = ChannelMetadata(
        id=channel_id,
        url=f"https://www.youtube.com/channel/{channel_id}",
    )
    try:
        html = _fetch(f"https://www.youtube.com/channel/{channel_id}/about")
        data = _extract_json(html, "var ytInitialData")
        if not data:
            return empty

        header = data
        metadata = (header.get("metadata", {}) or {}).get("channelMetadataRenderer", {})
        if not metadata:
            return empty

        tabs = (header.get("contents", {}).get("twoColumnBrowseResultsRenderer", {}) or {}).get("tabs", [])
        about = None
        for t in tabs:
            tr = t.get("tabRenderer", {})
            if tr.get("selected"):
                contents = (tr.get("content", {}).get("sectionListRenderer", {}) or {}).get("contents", [])
                if contents:
                    isr = contents[0].get("itemSectionRenderer", {}) or {}
                    isr_contents = isr.get("contents", [])
                    if isr_contents:
                        about = isr_contents[0].get("channelAboutFullMetadataRenderer")
                break

        header_c4 = header.get("header", {}).get("c4TabbedHeaderRenderer", {})
        subscriber_text = (header_c4.get("subscriberCountText", {}) or {}).get("simpleText", "")
        subs = _parse_view_count(subscriber_text)

        video_text = ""
        vc_raw = 0
        if about:
            runs = (about.get("videoCountText", {}) or {}).get("runs", [])
            if runs:
                video_text = runs[0].get("text", "")
            match = re.search(r"([\d,]+)", video_text)
            if match:
                vc_raw = int(match.group(1).replace(",", ""))

        links = []
        for l in (about or {}).get("primaryLinks", []) or []:
            nav = l.get("navigationEndpoint", {}).get("urlEndpoint", {})
            title_text = (l.get("title", {}) or {}).get("simpleText", "")
            if not title_text:
                title_runs = (l.get("title", {}) or {}).get("runs", [])
                if title_runs:
                    title_text = title_runs[0].get("text", "")
            links.append({
                "title": title_text,
                "url": nav.get("url", ""),
                "icon": ((l.get("icon", {}).get("thumbnails", [{}]) or [{}])[0] or {}).get("url", ""),
            })

        handle = ""
        if metadata.get("vanityChannelUrl"):
            handle = metadata["vanityChannelUrl"].replace("http://www.youtube.com/", "").replace("https://www.youtube.com/", "")

        return ChannelMetadata(
            id=channel_id,
            name=metadata.get("title") or header_c4.get("title", ""),
            handle=handle,
            description=metadata.get("description") or (about or {}).get("description", {}).get("simpleText", "") or _extract_runs((about or {}).get("description", {}).get("runs")),
            subscriber_count=subs[0],
            subscriber_count_raw=round(subs[1]),
            video_count=video_text,
            video_count_raw=vc_raw,
            avatar=_best_thumbnail(metadata.get("avatar", {}).get("thumbnails", []) or (header_c4.get("avatar", {}) or {}).get("thumbnails", [])),
            banner=_best_thumbnail(metadata.get("banner", {}).get("thumbnails", []) or (header_c4.get("banner", {}) or {}).get("thumbnails", [])),
            is_verified=any("VERIFIED" in (b.get("metadataBadgeRenderer", {}).get("style", "") or "").upper() for b in (header_c4.get("badges", []) or [])),
            social_links=links,
            url=f"https://www.youtube.com/channel/{channel_id}",
        )
    except Exception:
        return empty


# ─── Shorts ─────────────────────────────────────────────

def search_shorts(query: str, limit: int = 15, gl: Optional[str] = None, hl: Optional[str] = None):
    limit = max(1, min(limit, 50))
    url = f"https://www.youtube.com/results?search_query={quote(query)}&sp=EgIYAQ%3D%3D"
    if gl:
        url += f"&gl={gl}"
    if hl:
        url += f"&hl={hl}"
    html = _fetch(url)

    data = _extract_json(html, "var ytInitialData")
    if not data:
        return []

    shorts_section = None
    contents = (data.get("contents", {}).get("twoColumnSearchResultsRenderer", {}).get("primaryContents", {}).get("sectionListRenderer", {}).get("contents", []) or [])
    for c in contents:
        items = (c.get("itemSectionRenderer", {}) or {}).get("contents", [])
        if items and items[0].get("reelShelfRenderer"):
            shorts_section = items[0].get("reelShelfRenderer", {})
            break

    if not shorts_section:
        results, _ = _parse_search_results(data, limit)
        return results

    reel_items = shorts_section.get("items", []) or []
    all_results, _ = _parse_search_results(data, limit)

    short_results = []
    for item in reel_items:
        if len(short_results) >= limit:
            break
        vr = item.get("reelItemRenderer") or item.get("shortsLockupViewModel") or {}
        vid = vr.get("videoId")
        if not vid:
            continue
        title = _extract_runs(vr.get("headline", {}).get("runs")) or (vr.get("headline", {}) or {}).get("simpleText", "")
        duration = 0
        dur_text = (vr.get("lengthText", {}) or {}).get("simpleText", "")
        try:
            duration = int(dur_text)
        except (ValueError, TypeError):
            pass
        fb = VideoResult(id=vid)
        short_results.append(VideoResult(
            id=vid,
            title=title or f"Shorts {vid}",
            author=fb.author,
            duration=f"{duration}s",
            duration_seconds=duration,
            is_live=False,
            is_upcoming=False,
            is_verified=False,
        ))

    seen = {r.id for r in short_results}
    for r in all_results:
        if r.id not in seen:
            seen.add(r.id)
            short_results.append(r)

    combined = short_results[:limit]
    needs = [r for r in combined if not r.title or r.title == f"Video {r.id}" or r.author == "Unknown Author"]
    if needs:
        with ThreadPoolExecutor(max_workers=min(len(needs), 10)) as pool:
            enriched = list(pool.map(lambda r: _enrich_oembed(r.id), needs))
        for r, e in zip(needs, enriched):
            if e["title"]:
                r.title = e["title"]
            if e["author"]:
                r.author = e["author"]
    return combined


# ─── Transcript / Captions ──────────────────────────────

@dataclass
class TranscriptEntry:
    text: str = ""
    start: float = 0.0
    duration: float = 0.0


def get_transcript(video_id: str, lang: Optional[str] = None):
    try:
        html = _fetch(f"https://www.youtube.com/watch?v={video_id}")
        captions_match = re.search(r'"captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])', html)
        if not captions_match:
            player_match = re.search(r'"captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])', html)
            if not player_match:
                return []

        tracks_str = captions_match.group(1) if captions_match else re.search(r'"captionTracks":(\[[^\]]*\{[^}]*\}[^\]]*\])', html)
        if not tracks_str:
            return []
        tracks_raw = tracks_str.group(1) if hasattr(tracks_str, 'group') else str(tracks_str)
        if isinstance(tracks_str, re.Match):
            tracks_raw = tracks_str.group(1)
        tracks = json.loads(tracks_raw) if tracks_raw else []

        track_url = ""
        if lang:
            for t in tracks:
                if t.get("languageCode") == lang or lang.lower() in (t.get("name", {}).get("simpleText", "") or "").lower():
                    track_url = t.get("baseUrl", "")
                    break
        if not track_url:
            for t in tracks:
                if t.get("languageCode") == "en":
                    track_url = t.get("baseUrl", "")
                    break
        if not track_url and tracks:
            track_url = tracks[0].get("baseUrl", "")
        if not track_url:
            return []

        xml_text = _fetch(track_url)
        entries = []
        for m in re.finditer(r'<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:</text>)?', xml_text, re.MULTILINE):
            raw_text = m.group(3)
            raw_text = re.sub(r"<[^>]+>", "", raw_text)
            raw_text = raw_text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&#39;", "'")
            if raw_text.strip():
                entries.append(TranscriptEntry(
                    text=raw_text.strip(),
                    start=float(m.group(1)),
                    duration=float(m.group(2)),
                ))
        return entries
    except Exception:
        return []

