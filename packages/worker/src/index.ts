import {
  search,
  searchTrending,
  searchChannel,
  searchPlaylist,
  searchShorts,
  searchContinue,
  getVideo,
  getComments,
  getRelatedVideos,
  getChannelMetadata,
  getVideoStats,
  getLiveStreamInfo,
  getTranscript,
} from 'ytapis-core';

function corsHeaders(): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders() },
  });
}

function param(url: URL, key: string, fallback: string): string {
  return url.searchParams.get(key) || fallback;
}

function homePage(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ytapis — YouTube Search API</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0f0f0f;color:#f1f1f1;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh}
.container{max-width:900px;margin:0 auto;padding:40px 20px}
h1{font-size:2.5rem;background:linear-gradient(135deg,#3ea6ff,#f9d423);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:8px}
.subtitle{color:#888;font-size:1.1rem;margin-bottom:32px}
.search-box{display:flex;gap:12px;margin-bottom:32px}
.search-box input{flex:1;padding:14px 18px;border:1px solid #333;border-radius:10px;background:#1a1a1a;color:#fff;font-size:1rem;outline:none}
.search-box input:focus{border-color:#3ea6ff}
.search-box button{padding:14px 28px;background:#3ea6ff;color:#0f0f0f;border:none;border-radius:10px;font-weight:700;font-size:1rem;cursor:pointer}
.search-box button:hover{background:#65b8ff}
.endpoints{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px;margin-bottom:32px}
.endpoint{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:10px;padding:16px}
.endpoint .method{display:inline-block;background:#3ea6ff;color:#0f0f0f;padding:2px 8px;border-radius:4px;font-size:0.75rem;font-weight:700;margin-bottom:8px}
.endpoint .method.GET{background:#3ea6ff}
.endpoint .path{font-family:monospace;font-size:0.9rem;color:#e0e0e0;word-break:break-all;margin-bottom:4px}
.endpoint .desc{font-size:0.8rem;color:#888}
#results{margin-top:24px}
.card{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:10px;padding:16px;margin-bottom:12px;display:flex;gap:16px}
.card img{width:180px;height:101px;object-fit:cover;border-radius:6px;flex-shrink:0}
.card .info{flex:1}
.card .title{font-weight:600;margin-bottom:4px;font-size:0.95rem}
.card .meta{color:#888;font-size:0.8rem;margin-bottom:2px}
.card .vid{color:#f9d423;font-size:0.75rem}
.loading{text-align:center;color:#888;padding:40px}
.error{color:#ff4d4d;text-align:center;padding:20px}
footer{text-align:center;color:#555;padding:40px 0;font-size:0.85rem}
footer a{color:#3ea6ff}
</style>
</head>
<body>
<div class="container">
<h1>ytapis</h1>
<p class="subtitle">YouTube Search API — no API key required. Built by geethudino (Ruthvik) & geethudinoyt.</p>

<div class="search-box">
  <input type="text" id="q" placeholder="Search YouTube..." onkeydown="if(event.key==='Enter')search()">
  <button onclick="search()">Search</button>
</div>
<div id="results"></div>

<h2 style="font-size:1.3rem;margin-bottom:16px;color:#888">API Endpoints</h2>
<div class="endpoints">
<div class="endpoint"><span class="method GET">GET</span><div class="path">/?q=cats&limit=5</div><div class="desc">Search YouTube videos</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/trending?limit=10</div><div class="desc">Trending videos</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/shorts?q=dance&limit=5</div><div class="desc">YouTube Shorts</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/channel/UC...?limit=10</div><div class="desc">Channel videos</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/channel/UC.../metadata</div><div class="desc">Channel info</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/playlist/PL...</div><div class="desc">Playlist videos</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/video/dQw4w9WgXcQ</div><div class="desc">Video metadata</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/video/X/comments</div><div class="desc">Video comments</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/video/X/related</div><div class="desc">Related videos</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/video/X/stats</div><div class="desc">Views & likes</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/video/X/live</div><div class="desc">Live stream info</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/video/X/transcript?lang=en</div><div class="desc">Captions/transcript</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/continue?token=XXX</div><div class="desc">Pagination</div></div>
<div class="endpoint"><span class="method GET">GET</span><div class="path">/health</div><div class="desc">Health check</div></div>
</div>

<footer>Built & managed by <a href="https://github.com/pgboyahpgr-commits/ytapis">geethudino (Ruthvik)</a> · MIT License · v2.0.0</footer>
</div>
<script>
async function search(){
  const q=document.getElementById('q').value.trim();
  if(!q)return;
  document.getElementById('results').innerHTML='<div class="loading">Searching...</div>';
  try{
    const r=await fetch('/?q='+encodeURIComponent(q)+'&limit=10');
    const d=await r.json();
    if(!d.length){document.getElementById('results').innerHTML='<div class="error">No results found</div>';return}
    document.getElementById('results').innerHTML=d.map(v=>\`
      <div class="card">
        <img src="\${v.thumbnail}" onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22180%22 height=%22101%22><rect fill=%22%23222%22 width=%22180%22 height=%22101%22/><text fill=%22%23555%22 x=%2290%22 y=%2255%22 text-anchor=%22middle%22 font-size=%2214%22>No Image</text></svg>'">
        <div class="info">
          <div class="title">\${esc(v.title)}</div>
          <div class="meta">\${esc(v.author)} · \${v.duration||'?'} · \${v.viewCount||'?'}</div>
          <div class="vid">\${v.id} · \${v.publishedTime||''}</div>
        </div>
      </div>\`).join('')
  }catch(e){document.getElementById('results').innerHTML='<div class="error">'+esc(e.message)+'</div>'}
}
function esc(s){const d=document.createElement('div');d.textContent=s;return d.innerHTML}
</script>
</body>
</html>`;
}

export default {
  async fetch(request: Request): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);
    console.log(`${request.method} ${url.pathname}${url.search}`);

    try {
      const path = url.pathname.replace(/\/+$/, '') || '/';
      const limit = parseInt(param(url, 'limit', '15'), 10);

      // ─── Health ──────────────────────────────────
      if (path === '/health') {
        return json({ status: 'ok', version: '2.0.0' });
      }

      // ─── Root / Home ─────────────────────────────
      if (path === '/') {
        const q = param(url, 'q', '');
        if (!q) {
          return new Response(homePage(), {
            status: 200,
            headers: { 'Content-Type': 'text/html', ...corsHeaders() },
          });
        }
        const { results } = await search(q, { limit });
        return json(results);
      }

      // ─── Trending ────────────────────────────────
      if (path === '/trending') {
        const { results } = await searchTrending({ limit });
        return json(results);
      }

      // ─── Shorts ──────────────────────────────────
      if (path === '/shorts') {
        const q = param(url, 'q', '');
        if (!q) return json({ error: 'Missing query param "q"' }, 400);
        const { results } = await searchShorts(q, { limit });
        return json(results);
      }

      // ─── Continue ────────────────────────────────
      if (path === '/continue') {
        const continuation = param(url, 'token', '');
        if (!continuation) return json({ error: 'Missing "token" param' }, 400);
        const { results } = await searchContinue(continuation, { limit });
        return json(results);
      }

      // ─── Channel ─────────────────────────────────
      const channelMatch = path.match(/^\/channel\/(.+)$/);
      if (channelMatch) {
        const subPath = channelMatch[1];
        if (subPath.endsWith('/metadata')) {
          const cid = subPath.replace('/metadata', '');
          const meta = await getChannelMetadata(cid);
          return json(meta);
        }
        const { results } = await searchChannel(subPath, { limit });
        return json(results);
      }

      // ─── Playlist ────────────────────────────────
      const playlistMatch = path.match(/^\/playlist\/(.+)$/);
      if (playlistMatch) {
        const { results } = await searchPlaylist(playlistMatch[1], { limit });
        return json(results);
      }

      // ─── Video ───────────────────────────────────
      const videoMatch = path.match(/^\/video\/(.+)$/);
      if (videoMatch) {
        const subPath = videoMatch[1];

        if (subPath.endsWith('/comments')) {
          const vid = subPath.replace('/comments', '');
          const sort = param(url, 'sort', 'top') as 'top' | 'newest';
          const { comments } = await getComments(vid, { limit, sortBy: sort });
          return json(comments);
        }

        if (subPath.endsWith('/related')) {
          const vid = subPath.replace('/related', '');
          const related = await getRelatedVideos(vid, { limit });
          return json(related);
        }

        if (subPath.endsWith('/stats')) {
          const vid = subPath.replace('/stats', '');
          const stats = await getVideoStats(vid);
          return json(stats);
        }

        if (subPath.endsWith('/live')) {
          const vid = subPath.replace('/live', '');
          const live = await getLiveStreamInfo(vid);
          return json(live);
        }

        if (subPath.endsWith('/transcript')) {
          const vid = subPath.replace('/transcript', '');
          const lang = param(url, 'lang', '');
          const transcript = await getTranscript(vid, {}, lang || undefined);
          return json(transcript);
        }

        const result = await getVideo(subPath);
        return json(result);
      }

      return json({ error: 'Not found' }, 404);
    } catch (err) {
      return json({ error: (err as Error).message }, 500);
    }
  },
};
