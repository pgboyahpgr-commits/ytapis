import re
import json
from dataclasses import dataclass, field, asdict
from typing import Optional
from urllib.request import urlopen
from urllib.parse import quote


@dataclass
class VideoResult:
    id: str
    title: str = "Untitled"
    author: str = "Unknown Author"
    thumbnail: str = ""
    fullUrl: str = ""
    embedUrl: str = ""

    def __post_init__(self):
        if not self.thumbnail:
            self.thumbnail = f"https://i.ytimg.com/vi/{self.id}/hqdefault.jpg"
        if not self.fullUrl:
            self.fullUrl = f"https://www.youtube.com/watch?v={self.id}"
        if not self.embedUrl:
            self.embedUrl = f"https://www.youtube.com/embed/{self.id}?rel=0"


def _fetch(url: str) -> str:
    with urlopen(url, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def _fetch_oembed(video_id: str) -> VideoResult:
    fallback = VideoResult(id=video_id)
    try:
        url = f"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={video_id}&format=json"
        data = json.loads(_fetch(url))
        return VideoResult(
            id=video_id,
            title=data.get("title", fallback.title),
            author=data.get("author_name", fallback.author),
            thumbnail=data.get("thumbnail_url", fallback.thumbnail),
            fullUrl=fallback.fullUrl,
            embedUrl=fallback.embedUrl,
        )
    except Exception:
        return fallback


def search(query: str, limit: int = 15) -> list[dict]:
    url = f"https://www.youtube.com/results?search_query={quote(query)}"
    html = _fetch(url)

    ids = re.findall(r'"videoId":"([^"]{11})"', html)
    unique_ids = list(dict.fromkeys(ids))[:limit]

    results = [_fetch_oembed(vid) for vid in unique_ids]
    return [asdict(r) for r in results]
