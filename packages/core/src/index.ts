const VIDEO_ID_REGEX = /"videoId":"([^"]{11})"/g;
const OEMBED_BASE = 'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=';
const SEARCH_URL = 'https://www.youtube.com/results?search_query=';

export interface VideoResult {
  id: string;
  title: string;
  author: string;
  thumbnail: string;
  fullUrl: string;
  embedUrl: string;
}

export interface SearchOptions {
  limit?: number;
  fetch?: typeof globalThis.fetch;
}

async function fetchOembed(id: string, fetchFn: typeof globalThis.fetch): Promise<VideoResult> {
  const fallback: VideoResult = {
    id,
    title: `Video ${id}`,
    author: 'YouTube',
    thumbnail: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
    fullUrl: `https://www.youtube.com/watch?v=${id}`,
    embedUrl: `https://www.youtube.com/embed/${id}?rel=0`,
  };
  try {
    const res = await fetchFn(`${OEMBED_BASE}${id}&format=json`);
    if (!res.ok) return fallback;
    const data = await res.json() as { title?: string; author_name?: string; thumbnail_url?: string };
    return {
      id,
      title: data.title || fallback.title,
      author: data.author_name || fallback.author,
      thumbnail: data.thumbnail_url || fallback.thumbnail,
      fullUrl: fallback.fullUrl,
      embedUrl: fallback.embedUrl,
    };
  } catch {
    return fallback;
  }
}

export async function search(query: string, options: SearchOptions = {}): Promise<VideoResult[]> {
  const limit = options.limit ?? 15;
  const fetchFn = options.fetch ?? globalThis.fetch;

  const url = `${SEARCH_URL}${encodeURIComponent(query)}`;
  const res = await fetchFn(url);
  const html = await res.text();

  const ids: string[] = [];
  let match: RegExpExecArray | null;
  while ((match = VIDEO_ID_REGEX.exec(html)) !== null) {
    ids.push(match[1]);
  }

  const uniqueIds = [...new Set(ids)].slice(0, limit);
  return Promise.all(uniqueIds.map((id) => fetchOembed(id, fetchFn)));
}
