const SEARCH_URL = 'https://www.youtube.com/results?search_query=';
const INNERTUBE_URL = 'https://www.youtube.com/youtubei/v1/search';
const OEMBED_URL = 'https://www.youtube.com/oembed?url=https://www.youtube.com/watch=';
const TRENDING_URL = 'https://www.youtube.com/feed/trending';
const CHANNEL_URL = 'https://www.youtube.com/channel/';

export interface Thumbnail {
  url: string;
  width: number;
  height: number;
}

export interface VideoResult {
  id: string;
  title: string;
  author: string;
  channelUrl: string;
  thumbnail: string;
  thumbnails: Thumbnail[];
  fullUrl: string;
  embedUrl: string;
  duration: string;
  durationSeconds: number;
  viewCount: string;
  viewCountRaw: number;
  publishedTime: string;
  description: string;
  channelAvatar: string;
  isLive: boolean;
  isUpcoming: boolean;
  isVerified: boolean;
}

export interface SearchOptions {
  limit?: number;
  fetch?: typeof globalThis.fetch;
  gl?: string;
  hl?: string;
}

export interface SearchResponse {
  results: VideoResult[];
  continuation?: string;
  apiKey?: string;
  context?: Record<string, unknown>;
}

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

function fallbackResult(id: string): VideoResult {
  return {
    id, title: `Video ${id}`, author: 'YouTube', channelUrl: '',
    thumbnail: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
    thumbnails: [{ url: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`, width: 480, height: 360 }],
    fullUrl: `https://www.youtube.com/watch?v=${id}`, embedUrl: `https://www.youtube.com/embed/${id}?rel=0`,
    duration: '', durationSeconds: 0, viewCount: '', viewCountRaw: 0,
    publishedTime: '', description: '', channelAvatar: '',
    isLive: false, isUpcoming: false, isVerified: false,
  };
}

function parseDuration(text: string): { duration: string; seconds: number } {
  const parts = text.split(':').map(Number);
  if (parts.length === 3) return { duration: text, seconds: parts[0] * 3600 + parts[1] * 60 + parts[2] };
  if (parts.length === 2) return { duration: text, seconds: parts[0] * 60 + parts[1] };
  return { duration: text, seconds: parseInt(text, 10) || 0 };
}

function parseViewCount(text: string): { viewCount: string; raw: number } {
  if (!text) return { viewCount: '', raw: 0 };
  const cleaned = text.replace(/[^0-9.KMBkmb]/g, '');
  const num = parseFloat(cleaned.replace(/[KMBkmb]/g, '')) || 0;
  const multiplier =
    /[bB]/.test(cleaned) ? 1_000_000_000 :
    /[mM]/.test(cleaned) ? 1_000_000 :
    /[kK]/.test(cleaned) ? 1_000 : 1;
  return { viewCount: text, raw: Math.round(num * multiplier) };
}

function thumbnailQualityScore(url: string): number {
  if (!url) return 0;
  if (url.includes('maxresdefault')) return 1280;
  if (url.includes('sddefault')) return 640;
  if (url.includes('hqdefault')) return 480;
  if (url.includes('mqdefault')) return 320;
  if (url.includes('default')) return 120;
  return 0;
}

function extractBestThumbnail(thumbnails: any[]): string {
  if (!thumbnails || !thumbnails.length) return '';
  let best = thumbnails[0];
  let bestScore = thumbnailQualityScore(thumbnails[0].url);
  for (const t of thumbnails) {
    const score = t.width > 0 ? t.width : thumbnailQualityScore(t.url);
    if (score > bestScore) { best = t; bestScore = score; }
  }
  return best.url || '';
}

function extractRuns(runs: any[]): string {
  if (!runs || !runs.length) return '';
  return runs.map((r: any) => r.text || '').join('');
}

function parseVideoRenderer(vr: any): VideoResult | null {
  try {
    const id = vr.videoId;
    if (!id) return null;

    const title = extractRuns(vr.title?.runs);
    const author = extractRuns(vr.ownerText?.runs);
    const channelUrl = vr.ownerText?.runs?.[0]?.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl || '';

    const thumbs = (vr.thumbnail?.thumbnails || []).map((t: any) => ({
      url: t.url || '', width: t.width || 0, height: t.height || 0,
    }));
    const thumbnail = extractBestThumbnail(thumbs);

    const durText = vr.lengthText?.simpleText || extractRuns(vr.lengthText?.runs) || '';
    const { duration, seconds: durationSeconds } = parseDuration(durText);

    const vcText = vr.viewCountText?.simpleText || extractRuns(vr.viewCountText?.runs) || '';
    const { viewCount, raw: viewCountRaw } = parseViewCount(vcText);

    const publishedTime = vr.publishedTimeText?.simpleText || '';
    const descRuns = vr.detailedMetadataSnippets?.[0]?.snippetText?.runs || vr.descriptionSnippet?.runs;
    const description = extractRuns(descRuns);
    const channelThumbs = vr.channelThumbnailSupportedRenderers?.channelThumbnailWithLinkRenderer?.thumbnail?.thumbnails;
    const channelAvatar = extractBestThumbnail(channelThumbs);
    const badges: string[] = (vr.badges || []).map((b: any) => b.metadataBadgeRenderer?.style || '');
    const fb = fallbackResult(id);

    return {
      id, title: title || fb.title, author: author || fb.author, channelUrl,
      thumbnail: thumbnail || fb.thumbnail, thumbnails: thumbs.length ? thumbs : fb.thumbnails,
      fullUrl: fb.fullUrl, embedUrl: fb.embedUrl, duration, durationSeconds,
      viewCount, viewCountRaw, publishedTime, description, channelAvatar,
      isLive: badges.some((b: string) => /LIVE/i.test(b)),
      isUpcoming: badges.some((b: string) => /UPCOMING/i.test(b)),
      isVerified: badges.some((b: string) => /VERIFIED/i.test(b)),
    };
  } catch { return null; }
}

function extractJson(html: string, prefix: string): Record<string, unknown> | null {
  const idx = html.indexOf(prefix);
  if (idx === -1) return null;
  const start = html.indexOf('{', idx);
  if (start === -1) return null;
  let depth = 0, inString = false, escaped = false;
  for (let i = start; i < html.length; i++) {
    const ch = html[i];
    if (escaped) { escaped = false; continue; }
    if (ch === '\\') { escaped = true; continue; }
    if (ch === '"') { inString = !inString; continue; }
    if (inString) continue;
    if (ch === '{') depth++;
    if (ch === '}') { depth--; if (depth === 0) { try { return JSON.parse(html.substring(start, i + 1)); } catch { return null; } } }
  }
  return null;
}

function extractVideosFromRendererContent(rendererContents: any[], limit: number): { results: VideoResult[]; continuation?: string } {
  const results: VideoResult[] = [];
  let continuation: string | undefined;

  for (const section of rendererContents) {
    if (section.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
      continuation = section.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
    }

    if (results.length >= limit) continue;

    if (section.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
      continuation = section.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
    }

    const items = section.itemSectionRenderer?.contents;
    if (items) {
      for (const item of items) {
        if (results.length >= limit) break;
        if (item.videoRenderer) {
          const vr = parseVideoRenderer(item.videoRenderer);
          if (vr) results.push(vr);
        }
      }
    }

    const shelfItems = section.shelfRenderer?.content?.expandedShelfContentsRenderer?.items ||
                        section.shelfRenderer?.content?.horizontalListRenderer?.items;
    if (shelfItems) {
      for (const item of shelfItems) {
        if (results.length >= limit) break;
        if (item.videoRenderer) {
          const vr = parseVideoRenderer(item.videoRenderer);
          if (vr) results.push(vr);
        }
      }
    }
  }

  return { results, continuation };
}

function parseSearchResults(data: Record<string, unknown>, limit: number): { results: VideoResult[]; continuation?: string } {
  try {
    const contents = (data as any)?.contents?.twoColumnSearchResultsRenderer?.primaryContents?.sectionListRenderer?.contents;
    if (!contents) return { results: [] };
    return extractVideosFromRendererContent(contents, limit);
  } catch { return { results: [] }; }
}

function parseTrendingResults(data: Record<string, unknown>, limit: number): { results: VideoResult[]; continuation?: string } {
  try {
    const tabs = (data as any)?.contents?.twoColumnBrowseResultsRenderer?.tabs;
    if (!tabs) return { results: [] };
    for (const tab of tabs) {
      const contents = tab?.tabRenderer?.content?.sectionListRenderer?.contents;
      if (contents) {
        return extractVideosFromRendererContent(contents, limit);
      }
    }
    return { results: [] };
  } catch { return { results: [] }; }
}

function parseChannelResults(data: Record<string, unknown>, limit: number): { results: VideoResult[]; continuation?: string } {
  try {
    const tabs = (data as any)?.contents?.twoColumnBrowseResultsRenderer?.tabs;
    if (!tabs) return { results: [] };

    const videoTabs: string[] = [];
    for (const tab of tabs) {
      const title = tab?.tabRenderer?.title;
      if (title) videoTabs.push(title);
      const contents = tab?.tabRenderer?.content?.richGridRenderer?.contents ||
                       tab?.tabRenderer?.content?.sectionListRenderer?.contents;
      if (contents) {
        const results: VideoResult[] = [];
        let continuation: string | undefined;

        for (const item of contents) {
          if (results.length >= limit) break;

          if (item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
            continuation = item.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
          }

          if (item.richItemRenderer?.content?.videoRenderer) {
            const vr = parseVideoRenderer(item.richItemRenderer.content.videoRenderer);
            if (vr) results.push(vr);
          }
          if (item.videoRenderer) {
            const vr = parseVideoRenderer(item.videoRenderer);
            if (vr) results.push(vr);
          }
        }

        return { results, continuation };
      }
    }
    return { results: [] };
  } catch { return { results: [] }; }
}

function parsePlaylistResults(data: Record<string, unknown>, limit: number): { results: VideoResult[]; continuation?: string } {
  try {
    const contents = (data as any)?.contents?.twoColumnBrowseResultsRenderer?.tabs?.[0]
      ?.tabRenderer?.content?.sectionListRenderer?.contents?.[0]
      ?.itemSectionRenderer?.contents?.[0]
      ?.playlistVideoListRenderer?.contents;
    if (!contents) {
      const alt = (data as any)?.contents?.twoColumnWatchNextResults?.playlist?.playlist?.contents;
      if (!alt) return { results: [] };
      return extractVideosFromRendererContent([{ itemSectionRenderer: { contents: alt } }], limit);
    }

    const results: VideoResult[] = [];
    let continuation: string | undefined;

    for (const item of contents) {
      if (results.length >= limit) break;
      if (item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
        continuation = item.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
      }
      if (item.playlistVideoRenderer) {
        const pvr = item.playlistVideoRenderer;
        const id = pvr.videoId;
        if (!id) continue;
        const title = extractRuns(pvr.title?.runs);
        const author = extractRuns(pvr.shortBylineText?.runs);
        const durText = pvr.lengthText?.simpleText || extractRuns(pvr.lengthText?.runs) || '';
        const { duration, seconds: durationSeconds } = parseDuration(durText);
        const thumbs = (pvr.thumbnail?.thumbnails || []).map((t: any) => ({
          url: t.url || '', width: t.width || 0, height: t.height || 0,
        }));
        const fb = fallbackResult(id);
        results.push({
          ...fb, id, title: title || fb.title, author: author || fb.author,
          thumbnail: extractBestThumbnail(thumbs) || fb.thumbnail,
          thumbnails: thumbs.length ? thumbs : fb.thumbnails,
          duration, durationSeconds,
        });
      }
    }

    return { results, continuation };
  } catch { return { results: [] }; }
}

function parseContinuationResults(data: Record<string, unknown>, limit: number, path: string = 'search'): { results: VideoResult[]; continuation?: string } {
  const results: VideoResult[] = [];
  let continuation: string | undefined;

  try {
    let items: any[];
    if (path === 'channel') {
      items = (data as any)?.onResponseReceivedActions?.[0]?.appendContinuationItemsAction?.continuationItems;
      if (!items) items = (data as any)?.onResponseReceivedEndpoints?.[0]?.appendContinuationItemsAction?.continuationItems;
    } else if (path === 'playlist') {
      items = (data as any)?.onResponseReceivedActions?.[0]?.appendContinuationItemsAction?.continuationItems;
    } else {
      items = (data as any)?.onResponseReceivedEndpoints?.[0]?.appendContinuationItemsAction?.continuationItems;
    }
    if (!items) return { results, continuation };

    for (const item of items) {
      if (results.length >= limit) break;

      if (item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
        continuation = item.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
      }

      if (path === 'playlist' && item.playlistVideoRenderer) {
        const pvr = item.playlistVideoRenderer;
        const id = pvr.videoId;
        if (id) {
          const title = extractRuns(pvr.title?.runs);
          const author = extractRuns(pvr.shortBylineText?.runs);
          const durText = pvr.lengthText?.simpleText || extractRuns(pvr.lengthText?.runs) || '';
          const { duration, seconds: durationSeconds } = parseDuration(durText);
          const fb = fallbackResult(id);
          results.push({
            ...fb, id, title: title || fb.title, author: author || fb.author, duration, durationSeconds,
          });
        }
        continue;
      }

      const vr = item.videoRenderer || item.richItemRenderer?.content?.videoRenderer;
      if (vr) {
        const parsed = parseVideoRenderer(vr);
        if (parsed) results.push(parsed);
      }
    }
  } catch { /* ignore */ }

  return { results, continuation };
}

async function enrichWithOembed(id: string, fetchFn: typeof globalThis.fetch): Promise<Pick<VideoResult, 'title' | 'author' | 'thumbnail'>> {
  try {
    const res = await fetchFn(`${OEMBED_URL}${id}&format=json`);
    if (!res.ok) throw new Error('oembed failed');
    const data = await res.json() as { title?: string; author_name?: string; thumbnail_url?: string };
    return { title: data.title || '', author: data.author_name || '', thumbnail: data.thumbnail_url || '' };
  } catch { return { title: '', author: '', thumbnail: '' }; }
}

async function enrichResults(results: VideoResult[], fetchFn: typeof globalThis.fetch) {
  const needs = results.filter(r => !r.title || r.title === `Video ${r.id}` || r.author === 'YouTube');
  if (needs.length) {
    const enriched = await Promise.all(needs.map(r => enrichWithOembed(r.id, fetchFn)));
    needs.forEach((r, i) => {
      if (enriched[i].title) r.title = enriched[i].title;
      if (enriched[i].author) r.author = enriched[i].author;
      if (enriched[i].thumbnail && enriched[i].thumbnail !== r.thumbnail) r.thumbnail = enriched[i].thumbnail;
    });
  }
}

async function fetchHtml(url: string, fetchFn: typeof globalThis.fetch): Promise<string> {
  const res = await fetchFn(url, { headers: { 'User-Agent': UA } });
  return res.text();
}

function buildUrl(path: string, params: Record<string, string>): string {
  const url = new URL(path);
  for (const [k, v] of Object.entries(params)) {
    if (v) url.searchParams.set(k, v);
  }
  return url.toString();
}

function regionParams(options: SearchOptions): string {
  const parts: string[] = [];
  if (options.gl) parts.push(`gl=${options.gl}`);
  if (options.hl) parts.push(`hl=${options.hl}`);
  return parts.length ? '&' + parts.join('&') : '';
}

function regionContext(options: SearchOptions): Record<string, unknown> {
  const ctx: Record<string, unknown> = { hl: options.hl || 'en', gl: options.gl || 'US', clientName: 'WEB', clientVersion: '2.20240801.00.00' };
  return ctx;
}

function extractApiKeys(html: string): { apiKey?: string; context?: Record<string, unknown> } {
  const apiKeyMatch = html.match(/"INNERTUBE_API_KEY":"(AIza[^"]+)"/);
  return { apiKey: apiKeyMatch?.[1], context: extractJson(html, '"INNERTUBE_CONTEXT"') || undefined };
}

// ─── Public API ──────────────────────────────────────────

export async function getVideo(id: string, options: { fetch?: typeof globalThis.fetch } = {}): Promise<VideoResult> {
  const fetchFn = options.fetch ?? globalThis.fetch;
  const fallback = fallbackResult(id);
  try {
    const html = await fetchHtml(`https://www.youtube.com/watch?v=${id}`, fetchFn);
    const data = extractJson(html, 'var ytInitialPlayerResponse') || extractJson(html, 'var ytInitialData');
    if (data) {
      const vd = (data as any)?.videoDetails;
      if (vd) {
        const durSec = parseInt(vd.lengthSeconds, 10) || 0;
        const mins = Math.floor(durSec / 60);
        const secs = durSec % 60;
        const durStr = durSec > 3600
          ? `${Math.floor(durSec / 3600)}:${String(mins % 60).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
          : `${mins}:${String(secs).padStart(2, '0')}`;
        const thumbs = (vd.thumbnail?.thumbnails || []).map((t: any) => ({
          url: t.url || '', width: t.width || 0, height: t.height || 0,
        }));
        return { ...fallback,
          title: vd.title || fallback.title, author: vd.author || fallback.author,
          channelUrl: `https://www.youtube.com/${vd.channelId || ''}`,
          thumbnail: extractBestThumbnail(thumbs) || fallback.thumbnail,
          thumbnails: thumbs.length ? thumbs : fallback.thumbnails,
          duration: durStr, durationSeconds: durSec,
          viewCount: vd.viewCount ? parseInt(vd.viewCount, 10).toLocaleString() + ' views' : '',
          viewCountRaw: parseInt(vd.viewCount, 10) || 0,
          description: vd.shortDescription || '',
          channelAvatar: vd.authorThumbnails?.[0]?.url || '',
        };
      }
    }
    const enrich = await enrichWithOembed(id, fetchFn);
    return { ...fallback,
      title: enrich.title || fallback.title, author: enrich.author || fallback.author,
      thumbnail: enrich.thumbnail || fallback.thumbnail,
    };
  } catch { return fallback; }
}

export async function search(query: string, options: SearchOptions = {}): Promise<SearchResponse> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;
  const url = `${SEARCH_URL}${encodeURIComponent(query)}`;
  const html = await fetchHtml(url, fetchFn);
  const data = extractJson(html, 'var ytInitialData');
  if (!data) return { results: [] };
  const { apiKey, context } = extractApiKeys(html);
  const { results, continuation } = parseSearchResults(data, limit);
  await enrichResults(results, fetchFn);
  return { results, continuation, apiKey, context };
}

export async function searchTrending(options: SearchOptions = {}): Promise<SearchResponse> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;
  const html = await fetchHtml(TRENDING_URL, fetchFn);
  const data = extractJson(html, 'var ytInitialData');
  if (!data) return { results: [] };
  const { apiKey, context } = extractApiKeys(html);
  const { results, continuation } = parseTrendingResults(data, limit);
  return { results, continuation, apiKey, context };
}

export async function searchChannel(channelId: string, options: SearchOptions = {}): Promise<SearchResponse> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;
  const html = await fetchHtml(`${CHANNEL_URL}${channelId}/videos`, fetchFn);
  const data = extractJson(html, 'var ytInitialData');
  if (!data) return { results: [] };
  const { apiKey, context } = extractApiKeys(html);
  const { results, continuation } = parseChannelResults(data, limit);
  await enrichResults(results, fetchFn);
  return { results, continuation, apiKey, context };
}

export async function searchPlaylist(playlistId: string, options: SearchOptions = {}): Promise<SearchResponse> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;
  const html = await fetchHtml(`https://www.youtube.com/playlist?list=${playlistId}`, fetchFn);
  const data = extractJson(html, 'var ytInitialData');
  if (!data) return { results: [] };
  const { apiKey, context } = extractApiKeys(html);
  const { results, continuation } = parsePlaylistResults(data, limit);
  await enrichResults(results, fetchFn);
  return { results, continuation, apiKey, context };
}

export async function searchContinue(
  continuation: string,
  options: SearchOptions & { apiKey?: string; context?: Record<string, unknown>; path?: string } = {},
): Promise<SearchResponse> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;
  const key = options.apiKey || 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  const body = {
    context: options.context || {
      client: { hl: 'en', gl: 'US', clientName: 'WEB', clientVersion: '2.20240801.00.00' },
    },
    continuation,
  };
  const res = await fetchFn(`${INNERTUBE_URL}?key=${key}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  const data = await res.json() as Record<string, unknown>;
  const { results, continuation: nextContinuation } = parseContinuationResults(data, limit, options.path);
  await enrichResults(results, fetchFn);
  return { results, continuation: nextContinuation, apiKey: options.apiKey, context: options.context };
}

// ─── New Types ──────────────────────────────────────────

export interface CommentAuthor {
  name: string;
  channelId: string;
  avatar: string;
  isVerified: boolean;
  isOwner: boolean;
}

export interface CommentReply {
  id: string;
  author: CommentAuthor;
  text: string;
  likeCount: number;
  likeCountRaw: number;
  publishedTime: string;
  isLikedByCreator: boolean;
}

export interface VideoComment {
  id: string;
  author: CommentAuthor;
  text: string;
  likeCount: number;
  likeCountRaw: number;
  publishedTime: string;
  replyCount: number;
  isLikedByCreator: boolean;
  isPinned: boolean;
  replies: CommentReply[];
  replyContinuation?: string;
}

export interface LiveStreamInfo {
  isLive: boolean;
  isUpcoming: boolean;
  viewerCount: number;
  viewerCountStr: string;
  startTime: string;
  scheduledStartTime: string;
  likesCount: number;
  dislikesCount: number;
}

export interface RelatedVideo {
  id: string;
  title: string;
  author: string;
  channelUrl: string;
  duration: string;
  durationSeconds: number;
  viewCount: string;
  viewCountRaw: number;
  publishedTime: string;
  thumbnail: string;
  isLive: boolean;
}

// ─── Comments Engine ────────────────────────────────────

function parseCommentRenderer(cr: any): VideoComment {
  const id = cr.commentId || cr.properties?.commentId || '';
  const authorName = extractRuns(cr.authorText?.runs) || cr.authorText?.simpleText || '';
  const authorChannel = cr.authorEndpoint?.browseEndpoint?.browseId || '';
  const authorAvatar = (cr.authorThumbnail?.thumbnails || []).map((t: any) => t.url || '').pop() || '';
  const isVerified = cr.authorCommentBadge?.authorCommentBadgeRenderer?.icon?.iconType === 'CHECK' || false;
  const isOwner = cr.authorIsChannelOwner || false;
  const text = extractRuns(cr.contentText?.runs) || cr.contentText?.simpleText || '';
  const likeCount = parseInt(cr.voteCount?.simpleText || cr.likeCount || '0', 10) || 0;
  const publishedTime = cr.publishedTimeText?.runs?.[0]?.text || '';
  const replyCount = cr.replyCount || 0;
  const isLiked = cr.isLiked || false;
  const isPinned = !!(cr.pinnedCommentBadge?.pinnedCommentBadgeRenderer);

  const replies: CommentReply[] = [];
  let replyContinuation: string | undefined;
  const replyItems = cr.replies?.commentRepliesRenderer?.contents;
  if (replyItems) {
    for (const item of replyItems) {
      if (item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
        replyContinuation = item.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
        continue;
      }
      if (item.commentRenderer) {
        const rr = item.commentRenderer;
        replies.push({
          id: rr.commentId || '',
          author: {
            name: extractRuns(rr.authorText?.runs) || rr.authorText?.simpleText || '',
            channelId: rr.authorEndpoint?.browseEndpoint?.browseId || '',
            avatar: (rr.authorThumbnail?.thumbnails || []).map((t: any) => t.url || '').pop() || '',
            isVerified: false, isOwner: rr.authorIsChannelOwner || false,
          },
          text: extractRuns(rr.contentText?.runs) || rr.contentText?.simpleText || '',
          likeCount: parseInt(rr.voteCount?.simpleText || '0', 10) || 0,
          likeCountRaw: parseInt(rr.voteCount?.simpleText || '0', 10) || 0,
          publishedTime: rr.publishedTimeText?.runs?.[0]?.text || '',
          isLikedByCreator: rr.actionButtons?.commentActionButtonsRenderer?.creatorHeart?.creatorHeartRenderer?.isHearted || false,
        });
      }
    }
  }

  return {
    id, text, likeCount, likeCountRaw: likeCount, publishedTime, replyCount,
    isLikedByCreator: isLiked, isPinned, replies, replyContinuation,
    author: { name: authorName, channelId: authorChannel, avatar: authorAvatar, isVerified, isOwner },
  };
}

// ─── LRU Cache ─────────────────────────────────────────

export class LRUCache<V> {
  private map = new Map<string, { value: V; expires: number }>();
  constructor(private maxSize: number = 500, private ttlMs: number = 300_000) {}
  get(key: string): V | undefined {
    const entry = this.map.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expires) { this.map.delete(key); return undefined; }
    this.map.delete(key); this.map.set(key, entry);
    return entry.value;
  }
  set(key: string, value: V): void {
    if (this.map.has(key)) this.map.delete(key);
    else if (this.map.size >= this.maxSize) this.map.delete(this.map.keys().next().value!);
    this.map.set(key, { value, expires: Date.now() + this.ttlMs });
  }
  clear(): void { this.map.clear(); }
  get size(): number { return this.map.size; }
}

// ─── Retry ─────────────────────────────────────────────

export async function withRetry<T>(
  fn: () => Promise<T>, options: { maxRetries?: number; baseDelay?: number; maxDelay?: number } = {},
): Promise<T> {
  const maxRetries = options.maxRetries ?? 3;
  const baseDelay = options.baseDelay ?? 500;
  const maxDelay = options.maxDelay ?? 5000;
  let lastErr: unknown;
  for (let a = 0; a <= maxRetries; a++) {
    try { return await fn(); } catch (err: any) {
      lastErr = err;
      if (a >= maxRetries) throw err;
      const d = Math.min(baseDelay * Math.pow(2, a) + Math.random() * 500, maxDelay);
      await new Promise(r => setTimeout(r, d));
    }
  }
  throw lastErr;
}

// ─── Public: Comments ───────────────────────────────────

export async function getComments(
  videoId: string, options: SearchOptions & { sortBy?: 'top' | 'newest'; continuation?: string } = {},
): Promise<{ comments: VideoComment[]; continuation?: string }> {
  const limit = Math.max(1, Math.min(options.limit ?? 20, 100));
  const fetchFn = options.fetch ?? globalThis.fetch;

  try {
    if (options.continuation) {
      const html = await fetchHtml(`https://www.youtube.com/watch?v=${videoId}`, fetchFn);
      const apiKey = html.match(/"INNERTUBE_API_KEY":"(AIza[^"]+)"/)?.[1] || 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
      const ctx = extractJson(html, '"INNERTUBE_CONTEXT"');
      const data = await (await fetchFn(`https://www.youtube.com/youtubei/v1/next?key=${apiKey}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ context: ctx || { client: { hl: 'en', gl: 'US', clientName: 'WEB', clientVersion: '2.20240801.00.00' } }, continuation: options.continuation }),
      })).json() as Record<string, unknown>;

      const items = (data as any)?.onResponseReceivedEndpoints?.[0]?.reloadContinuationItemsCommand?.continuationItems ||
                     (data as any)?.onResponseReceivedEndpoints?.[0]?.appendContinuationItemsAction?.continuationItems;
      if (!items) return { comments: [] };

      const comments: VideoComment[] = [];
      let nc: string | undefined;
      for (const item of items) {
        if (comments.length >= limit) break;
        if (item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
          nc = item.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
        }
        if (item.commentThreadRenderer?.comment?.commentRenderer) {
          const cr = item.commentThreadRenderer.comment.commentRenderer;
          if (item.commentThreadRenderer.replies) cr.replies = item.commentThreadRenderer.replies;
          comments.push(parseCommentRenderer(cr));
        }
      }
      return { comments, continuation: nc };
    }

    const html = await fetchHtml(`https://www.youtube.com/watch?v=${videoId}`, fetchFn);
    const data = extractJson(html, 'var ytInitialData');
    if (!data) return { comments: [] };

    const apiKey = html.match(/"INNERTUBE_API_KEY":"(AIza[^"]+)"/)?.[1] || 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
    const ctx = extractJson(html, '"INNERTUBE_CONTEXT"');

    const allResults = (data as any)?.contents?.twoColumnWatchNextResults?.results?.results?.contents;
    let token = '';
    for (const c of allResults || []) {
      const items = c?.itemSectionRenderer?.contents || [];
      for (const item of items) {
        token = item?.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token;
        if (token) break;
        token = item?.commentsEntryPointHeaderRenderer?.contents?.[0]?.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token;
        if (token) break;
      }
      if (token) break;
    }
    if (!token) return { comments: [] };

    const nb = { context: ctx || { client: { hl: 'en', gl: 'US', clientName: 'WEB', clientVersion: '2.20240801.00.00' } }, continuation: token };
    const nd = await (await fetchFn(`https://www.youtube.com/youtubei/v1/next?key=${apiKey}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(nb),
    })).json() as Record<string, unknown>;

    const items = (nd as any)?.onResponseReceivedEndpoints?.[0]?.reloadContinuationItemsCommand?.continuationItems ||
                   (nd as any)?.onResponseReceivedEndpoints?.[0]?.appendContinuationItemsAction?.continuationItems ||
                   (nd as any)?.onResponseReceivedEndpoints?.[1]?.reloadContinuationItemsCommand?.continuationItems ||
                   (nd as any)?.onResponseReceivedEndpoints?.[1]?.appendContinuationItemsAction?.continuationItems;
    if (!items) return { comments: [] };

    const comments: VideoComment[] = [];
    let nc: string | undefined;
    for (const item of items) {
      if (comments.length >= limit) break;
      if (item.continuationItemRenderer?.continuationEndpoint?.continuationCommand?.token) {
        nc = item.continuationItemRenderer.continuationEndpoint.continuationCommand.token;
      }
      if (item.commentThreadRenderer?.comment?.commentRenderer) {
        const cr = item.commentThreadRenderer.comment.commentRenderer;
        if (item.commentThreadRenderer.replies) cr.replies = item.commentThreadRenderer.replies;
        comments.push(parseCommentRenderer(cr));
      }
    }
    return { comments, continuation: nc };
  } catch {
    return { comments: [] };
  }
}

// ─── Public: Related Videos ─────────────────────────────

export async function getRelatedVideos(videoId: string, options: SearchOptions = {}): Promise<RelatedVideo[]> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;

  try {
    const html = await fetchHtml(`https://www.youtube.com/watch?v=${videoId}`, fetchFn);
    const data = extractJson(html, 'var ytInitialData');
    if (!data) return [];

    const watchNext = (data as any)?.contents?.twoColumnWatchNextResults?.secondaryResults?.secondaryResults?.results;
    if (!watchNext) return [];

    const results: RelatedVideo[] = [];
    for (const item of watchNext) {
      if (results.length >= limit) break;
      const vr = item.compactVideoRenderer || item.compactRadioRenderer;
      if (!vr) continue;
      const id = vr.videoId;
      if (!id) continue;
      const title = extractRuns(vr.title?.runs) || vr.title?.simpleText || '';
      const author = extractRuns(vr.shortBylineText?.runs) || vr.shortBylineText?.simpleText || '';
      const durText = vr.lengthText?.simpleText || extractRuns(vr.lengthText?.runs) || '';
      const { duration, seconds: durationSeconds } = parseDuration(durText);
      const viewsText = vr.viewCountText?.simpleText || extractRuns(vr.viewCountText?.runs) || '';
      const { viewCount, raw: vcr } = parseViewCount(viewsText);
      const publishedTime = vr.publishedTimeText?.simpleText || '';
      const thumbnail = extractBestThumbnail(vr.thumbnail?.thumbnails || []);
      const badge = vr.badges?.[0]?.metadataBadgeRenderer?.style || '';
      results.push({
        id, title, author,
        channelUrl: vr.shortBylineText?.runs?.[0]?.navigationEndpoint?.browseEndpoint?.canonicalBaseUrl || '',
        duration, durationSeconds, viewCount, viewCountRaw: Math.round(vcr), publishedTime,
        thumbnail: thumbnail || `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
        isLive: /LIVE/i.test(badge),
      });
    }
    return results;
  } catch { return []; }
}

// ─── Public: Live Stream + Stats ────────────────────────

export async function getVideoStats(
  videoId: string, options?: { fetch?: typeof globalThis.fetch },
): Promise<{ views: number; likes: number; comments: number; isLive: boolean; viewerCount: number }> {
  const fetchFn = options?.fetch ?? globalThis.fetch;
  try {
    const html = await fetchHtml(`https://www.youtube.com/watch?v=${videoId}`, fetchFn);
    const data = extractJson(html, 'var ytInitialData');
    if (!data) return { views: 0, likes: 0, comments: 0, isLive: false, viewerCount: 0 };

    const primary = (data as any)?.contents?.twoColumnWatchNextResults?.results?.results?.contents
      ?.find((c: any) => c.videoPrimaryInfoRenderer)?.videoPrimaryInfoRenderer;
    const viewsText = primary?.viewCount?.videoViewCountRenderer?.shortViewCount?.simpleText || primary?.viewCount?.videoViewCountRenderer?.viewCount?.simpleText || '';
    const { raw: views } = parseViewCount(viewsText);

    const likesStr = primary?.videoActions?.menuRenderer?.topLevelButtons?.[0]
      ?.segmentedLikeDislikeButtonViewModel?.likeButtonViewModel?.likeButtonViewModel
      ?.toggleButtonViewModel?.toggleButtonViewModel?.defaultButtonViewModel?.buttonViewModel?.accessibilityText || '';
    const { raw: likes } = parseViewCount(likesStr.replace(/[^0-9.KMBkmb]/g, ''));

    const isLive = /"isLive":\s*true/.test(html);
    const vcm = html.match(/"viewCount":{"videoViewCountRenderer":{"isLive":true,"viewCount":{"simpleText":"([^"]+)"/);
    const viewerCount = vcm ? parseViewCount(vcm[1]).raw : 0;

    return { views, likes: Math.round(likes), comments: 0, isLive, viewerCount };
  } catch { return { views: 0, likes: 0, comments: 0, isLive: false, viewerCount: 0 }; }
}

export async function getLiveStreamInfo(
  videoId: string, options?: { fetch?: typeof globalThis.fetch },
): Promise<LiveStreamInfo> {
  const fetchFn = options?.fetch ?? globalThis.fetch;
  const stats = await getVideoStats(videoId, options);
  try {
    const html = await fetchHtml(`https://www.youtube.com/watch?v=${videoId}`, fetchFn);
    const data = extractJson(html, 'var ytInitialData');
    const primary = data ? (data as any)?.contents?.twoColumnWatchNextResults?.results?.results?.contents
      ?.find((c: any) => c.videoPrimaryInfoRenderer)?.videoPrimaryInfoRenderer : null;

    return {
      isLive: stats.isLive, isUpcoming: stats.isLive === false && stats.viewerCount === 0,
      viewerCount: stats.viewerCount, viewerCountStr: stats.viewerCount.toLocaleString(),
      startTime: primary?.dateText?.simpleText || '',
      scheduledStartTime: primary?.upcomingEventData?.startTime || '',
      likesCount: stats.likes, dislikesCount: 0,
    };
  } catch { return { isLive: stats.isLive, isUpcoming: false, viewerCount: stats.viewerCount, viewerCountStr: stats.viewerCount.toLocaleString(), startTime: '', scheduledStartTime: '', likesCount: stats.likes, dislikesCount: 0 }; }
}

// ─── HTTP Client with Retry + Cache ─────────────────────

export const globalCache = new LRUCache<string>(500, 300_000);

export function createClient(options: {
  cache?: LRUCache<string>; retry?: boolean; maxRetries?: number; fetch?: typeof globalThis.fetch;
} = {}) {
  const cache = options.cache || globalCache;
  const baseFetch = options.fetch || globalThis.fetch;
  const shouldRetry = options.retry !== false;
  const maxRetries = options.maxRetries ?? 3;

  const cachedFetch = async (url: string, init?: RequestInit) => {
    const cacheKey = url + (init?.body?.toString() || '');
    if (!init?.method || init.method === 'GET') {
      const cached = cache.get(cacheKey);
      if (cached) return { ok: true, json: () => Promise.resolve(cached), text: () => Promise.resolve(JSON.stringify(cached)) } as Response;
    }
    const response = await baseFetch(url, init);
    try {
      const cloned = await response.clone().text();
      try { cache.set(cacheKey, JSON.parse(cloned)); } catch { /* ignore */ }
    } catch { /* ignore */ }
    return response;
  };

  const ff = (shouldRetry
    ? (url: string, init?: RequestInit) => withRetry(() => cachedFetch(url, init), { maxRetries, baseDelay: 300, maxDelay: 3000 })
    : cachedFetch) as unknown as typeof globalThis.fetch;

  return {
    search: (q: string, l?: number) => search(q, { limit: l, fetch: ff }),
    searchTrending: (l?: number) => searchTrending({ limit: l, fetch: ff }),
    searchChannel: (cid: string, l?: number) => searchChannel(cid, { limit: l, fetch: ff }),
    searchPlaylist: (pid: string, l?: number) => searchPlaylist(pid, { limit: l, fetch: ff }),
    searchContinue: (cont: string, l?: number, path?: string, apikey?: string, ctx?: Record<string, unknown>) =>
      searchContinue(cont, { limit: l, fetch: ff, apiKey: apikey, context: ctx, path }),
    getVideo: (id: string) => getVideo(id, { fetch: ff }),
    getComments: (vid: string, l?: number, sort?: 'top' | 'newest') => getComments(vid, { limit: l, fetch: ff, sortBy: sort }),
    getRelatedVideos: (vid: string, l?: number) => getRelatedVideos(vid, { limit: l, fetch: ff }),
    getVideoStats: (vid: string) => getVideoStats(vid, { fetch: ff }),
    getLiveStreamInfo: (vid: string) => getLiveStreamInfo(vid, { fetch: ff }),
    getChannelMetadata: (cid: string) => getChannelMetadata(cid, { fetch: ff }),
    searchShorts: (q: string, l?: number) => searchShorts(q, { limit: l, fetch: ff }),
    getTranscript: (vid: string, lang?: string) => getTranscript(vid, { fetch: ff }, lang),
    cache,
  };
}

// ─── Channel Metadata ───────────────────────────────────

export interface ChannelMetadata {
  id: string;
  name: string;
  handle: string;
  description: string;
  subscriberCount: string;
  subscriberCountRaw: number;
  videoCount: string;
  videoCountRaw: number;
  avatar: string;
  banner: string;
  isVerified: boolean;
  socialLinks: { title: string; url: string; icon: string }[];
  url: string;
}

export async function getChannelMetadata(
  channelId: string, options?: { fetch?: typeof globalThis.fetch },
): Promise<ChannelMetadata> {
  const fetchFn = options?.fetch ?? globalThis.fetch;
  const empty = { id: channelId, name: '', handle: '', description: '', subscriberCount: '', subscriberCountRaw: 0, videoCount: '', videoCountRaw: 0, avatar: '', banner: '', isVerified: false, socialLinks: [], url: `https://www.youtube.com/channel/${channelId}` };
  try {
    const html = await fetchHtml(`https://www.youtube.com/channel/${channelId}/about`, fetchFn);
    const data = extractJson(html, 'var ytInitialData');
    if (!data) return empty;

    const header = extractJson(html, 'var ytInitialData') as any;
    const metadata = header?.metadata?.channelMetadataRenderer;
    if (!metadata) return empty;

    const about = (header as any)?.contents?.twoColumnBrowseResultsRenderer?.tabs
      ?.find((t: any) => t.tabRenderer?.selected)?.tabRenderer?.content?.sectionListRenderer?.contents?.[0]
      ?.itemSectionRenderer?.contents?.[0]?.channelAboutFullMetadataRenderer;

    const headerC4 = (header as any)?.header?.c4TabbedHeaderRenderer;
    const subscriberText = headerC4?.subscriberCountText?.simpleText || '';
    const { viewCount: subs, raw: subsRaw } = parseViewCount(subscriberText);

    const videoText = about?.videoCountText?.runs?.[0]?.text || '';
    const vcMatch = videoText.match(/([\d,]+)/);
    const vcRaw = vcMatch ? parseInt(vcMatch[1].replace(/,/g, ''), 10) : 0;

    const links: { title: string; url: string; icon: string }[] = [];
    for (const l of about?.primaryLinks || []) {
      const nav = l.navigationEndpoint?.urlEndpoint;
      links.push({
        title: l.title?.simpleText || l.title?.runs?.[0]?.text || '',
        url: nav?.url || '',
        icon: l.icon?.thumbnails?.[0]?.url || '',
      });
    }

    return {
      id: channelId,
      name: metadata.title || headerC4?.title || '',
      handle: metadata.vanityChannelUrl ? metadata.vanityChannelUrl.replace('http://www.youtube.com/', '').replace('https://www.youtube.com/', '') : '',
      description: metadata.description || about?.description?.simpleText || extractRuns(about?.description?.runs) || '',
      subscriberCount: subs || '',
      subscriberCountRaw: Math.round(subsRaw),
      videoCount: videoText,
      videoCountRaw: vcRaw,
      avatar: extractBestThumbnail(metadata.avatar?.thumbnails || headerC4?.avatar?.thumbnails || []),
      banner: extractBestThumbnail(metadata.banner?.thumbnails || headerC4?.banner?.thumbnails || []),
      isVerified: headerC4?.badges?.some((b: any) => b.metadataBadgeRenderer?.style?.includes('VERIFIED')) || false,
      socialLinks: links,
      url: `https://www.youtube.com/channel/${channelId}`,
    };
  } catch { return empty; }
}

// ─── Shorts ─────────────────────────────────────────────

export async function searchShorts(query: string, options: SearchOptions = {}): Promise<SearchResponse> {
  const limit = Math.max(1, Math.min(options.limit ?? 15, 50));
  const fetchFn = options.fetch ?? globalThis.fetch;
  const region = regionParams(options);
  const url = `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}&sp=EgIYAQ%3D%3D${region}`;
  const html = await fetchHtml(url, fetchFn);
  const data = extractJson(html, 'var ytInitialData');
  if (!data) return { results: [] };
  const { apiKey, context } = extractApiKeys(html);

  const shortsRenderer = (data as any)?.contents?.twoColumnSearchResultsRenderer?.primaryContents
    ?.sectionListRenderer?.contents?.find((c: any) => c.itemSectionRenderer?.contents?.[0]?.reelShelfRenderer);
  if (!shortsRenderer) {
    const { results, continuation } = parseSearchResults(data, limit);
    return { results, continuation, apiKey, context };
  }

  const reelItems = shortsRenderer.itemSectionRenderer.contents[0].reelShelfRenderer.items;
  const { results: allResults } = parseSearchResults(data, limit);

  const shortResults: VideoResult[] = [];
  for (const item of reelItems || []) {
    if (shortResults.length >= limit) break;
    const vr = item.reelItemRenderer || item.shortsLockupViewModel;
    const id = vr?.videoId || item.reelItemRenderer?.videoId;
    if (!id) continue;
    const title = extractRuns(vr?.headline?.runs) || vr?.headline?.simpleText || '';
    const duration = parseInt(vr?.lengthText?.simpleText || '0', 10);
    shortResults.push({
      ...fallbackResult(id),
      title: title || `Shorts ${id}`,
      duration: `${duration}s`,
      durationSeconds: duration,
      isLive: false,
      isUpcoming: false,
      isVerified: false,
    });
  }

  const combined = [...new Map([...shortResults, ...allResults].map(r => [r.id, r])).values()].slice(0, limit);
  await enrichResults(combined, fetchFn);
  return { results: combined, continuation: (parseSearchResults(data, limit) as any).continuation, apiKey, context };
}

// ─── Transcript / Captions ──────────────────────────────

export interface TranscriptEntry {
  text: string;
  start: number;
  duration: number;
}

export async function getTranscript(
  videoId: string, options?: { fetch?: typeof globalThis.fetch }, lang?: string,
): Promise<TranscriptEntry[]> {
  const fetchFn = options?.fetch ?? globalThis.fetch;
  try {
    const html = await fetchHtml(`https://www.youtube.com/watch?v=${videoId}`, fetchFn);
    const captionsMatch = html.match(/"captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])/);
    if (!captionsMatch) {
      const playerMatch = html.match(/"captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])/);
      if (!playerMatch) return [];
    }

    const tracksStr = captionsMatch?.[1] || html.match(/"captionTracks":(\[[^\]]*\{[^}]*\}[^\]]*\])/)?.[1];
    if (!tracksStr) return [];

    let tracks: any[];
    try { tracks = JSON.parse(tracksStr); } catch { return []; }

    let trackUrl = '';
    if (lang) {
      const track = tracks.find((t: any) => t.languageCode === lang || t.name?.simpleText?.toLowerCase().includes(lang.toLowerCase()));
      if (track) trackUrl = track.baseUrl;
    }
    if (!trackUrl) {
      trackUrl = tracks.find((t: any) => t.languageCode === 'en')?.baseUrl || tracks[0]?.baseUrl || '';
    }
    if (!trackUrl) return [];

    const xmlRes = await fetchFn(trackUrl);
    const xml = await xmlRes.text();
    const entries: TranscriptEntry[] = [];

    const textRegex = /<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:<\/text>)?$/gm;
    let m: RegExpExecArray | null;
    while ((m = textRegex.exec(xml)) !== null) {
      const rawText = m[3].replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
      if (rawText.trim()) {
        entries.push({ text: rawText.trim(), start: parseFloat(m[1]), duration: parseFloat(m[2]) });
      }
    }
    return entries;
  } catch { return []; }
}
