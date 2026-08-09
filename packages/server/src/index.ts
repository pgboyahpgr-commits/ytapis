import { createServer, IncomingMessage, ServerResponse } from 'http';
import { createClient, getComments, getRelatedVideos } from 'ytapis-core';

const PORT = parseInt(process.env.PORT || '3000', 10);
const VERSION = '1.0.0';
const startTime = Date.now();

const client = createClient();

const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 60;
const RATE_LIMIT_WINDOW = 60_000;

setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of rateLimitMap) {
    if (now > entry.resetAt) rateLimitMap.delete(key);
  }
}, 60_000).unref();

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW });
    return true;
  }
  if (entry.count >= RATE_LIMIT_MAX) return false;
  entry.count++;
  return true;
}

function logRequest(method: string, path: string, status: number, ms: number) {
  console.log(`${method} ${path} -> ${status} (${ms}ms)`);
}

function sendJSON(res: ServerResponse, status: number, data: unknown) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Length': Buffer.byteLength(body).toString(),
    'X-Powered-By': 'ytapis',
  });
  res.end(body);
}

function sendHTML(res: ServerResponse, status: number, html: string) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Content-Length': Buffer.byteLength(html).toString(),
    'X-Powered-By': 'ytapis',
  });
  res.end(html);
}

function sendError(res: ServerResponse, status: number, message: string) {
  sendJSON(res, status, { error: message, status });
}

function parseURL(req: IncomingMessage) {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const params = Object.fromEntries(url.searchParams.entries());
  return { path, params };
}

function parseLimit(raw: string | undefined, def: number, max: number): number {
  if (!raw) return def;
  const n = parseInt(raw, 10);
  if (isNaN(n) || n < 1) return def;
  return Math.min(n, max);
}

const PAGE_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ytapis-server</title>
<style>
  :root { color-scheme: dark; }
  body { font-family: system-ui, sans-serif; max-width: 900px; margin: 0 auto; padding: 2rem; background: #0d1117; color: #c9d1d9; }
  h1 { color: #58a6ff; font-size: 1.8rem; margin-bottom: 0.5rem; }
  h2 { color: #f0883e; margin-top: 2rem; font-size: 1.2rem; }
  a { color: #58a6ff; text-decoration: none; }
  a:hover { text-decoration: underline; }
  .search-box { display: flex; gap: 0.5rem; margin: 1.5rem 0; }
  .search-box input { flex: 1; padding: 0.7rem 1rem; border: 1px solid #30363d; border-radius: 6px; background: #161b22; color: #c9d1d9; font-size: 1rem; }
  .search-box button { padding: 0.7rem 1.5rem; border: none; border-radius: 6px; background: #238636; color: #fff; font-size: 1rem; cursor: pointer; }
  .search-box button:hover { background: #2ea043; }
  code { background: #161b22; padding: 0.15em 0.4em; border-radius: 4px; font-size: 0.9em; color: #f0883e; }
  pre { background: #161b22; padding: 1rem; border-radius: 6px; overflow-x: auto; font-size: 0.85rem; }
  .endpoint { margin: 0.75rem 0; padding: 0.6rem 0.8rem; border-left: 3px solid #30363d; background: #161b22; border-radius: 0 6px 6px 0; }
  .endpoint .method { color: #7ee787; font-weight: bold; }
  .endpoint .path { color: #d2a8ff; }
  .result { margin-top: 1.5rem; max-height: 500px; overflow-y: auto; }
  .result pre { margin: 0; }
  .status { color: #7ee787; margin-bottom: 0.5rem; font-size: 0.85rem; }
  table { border-collapse: collapse; width: 100%; }
  td { padding: 0.3rem 0.6rem; border-bottom: 1px solid #21262d; }
  td:first-child { white-space: nowrap; color: #8b949e; }
</style>
</head>
<body>
<h1>ytapis-server <span style="font-size:0.9rem;color:#8b949e">v${VERSION}</span></h1>

<div class="search-box">
  <input id="q" type="text" placeholder="Search YouTube..." onkeydown="if(event.key==='Enter')doSearch()" />
  <button onclick="doSearch()">Search</button>
</div>

<div id="result" class="result"></div>

<h2>API Endpoints</h2>
<div class="endpoint"><span class="method">GET</span> <span class="path">/search?q=QUERY&limit=N</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/trending?limit=N</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/channel/:id/videos?limit=N</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/playlist/:id?limit=N</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/video/:id</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/video/:id/comments?limit=N&sort=top|newest</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/video/:id/related?limit=N</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/video/:id/stats</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/video/:id/live</span></div>
<div class="endpoint"><span class="method">GET</span> <span class="path">/health</span></div>

<script>
async function doSearch() {
  const q = document.getElementById('q').value.trim();
  if (!q) return;
  const res = document.getElementById('result');
  res.innerHTML = '<pre>Loading...</pre>';
  try {
    const r = await fetch('/search?q=' + encodeURIComponent(q) + '&limit=10');
    const data = await r.json();
    const elapsed = r.headers.get('X-Response-Time') || '';
    let html = '<div class="status">' + data.results.length + ' results in ' + elapsed + '</div>';
    html += '<table>';
    data.results.forEach(v => {
      html += '<tr><td><a href="' + v.fullUrl + '" target="_blank"><img src="' + v.thumbnail + '" width="120" style="border-radius:8px" /></a></td>';
      html += '<td><strong>' + esc(v.title) + '</strong><br/>' + esc(v.author) + ' &middot; ' + esc(v.viewCount);
      if (v.duration) html += ' &middot; ' + esc(v.duration);
      html += '<br/><small>' + esc(v.publishedTime) + '</small></td></tr>';
    });
    html += '</table>';
    if (data.results.length === 0) html = '<div class="status">No results found.</div>';
    res.innerHTML = html;
  } catch(e) {
    document.getElementById('result').innerHTML = '<pre style="color:#f85149">Error: ' + esc(e.message) + '</pre>';
  }
}
function esc(s) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
</script>
</body>
</html>`;

async function handleRequest(req: IncomingMessage, res: ServerResponse) {
  const start = Date.now();

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'X-Powered-By': 'ytapis',
    });
    res.end();
    logRequest('OPTIONS', parseURL(req).path, 204, Date.now() - start);
    return;
  }

  if (req.method !== 'GET') {
    sendError(res, 405, 'Method not allowed');
    logRequest(req.method!, parseURL(req).path, 405, Date.now() - start);
    return;
  }

  const { path, params } = parseURL(req);
  const elapsed = () => { const ms = Date.now() - start; return ms + 'ms'; };

  const ip = (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() || req.socket.remoteAddress || 'unknown';
  if (!checkRateLimit(ip)) {
    sendError(res, 429, 'Too many requests');
    logRequest('GET', path, 429, Date.now() - start);
    return;
  }

  try {
    // GET /health
    if (path === '/health') {
      sendJSON(res, 200, { status: 'ok', version: VERSION, uptime: Math.floor((Date.now() - startTime) / 1000) });
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /
    if (path === '/') {
      sendHTML(res, 200, PAGE_HTML);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /search?q=QUERY&limit=N
    if (path === '/search') {
      const q = params.q;
      if (!q) { sendError(res, 400, 'Missing query parameter: q'); logRequest('GET', path, 400, Date.now() - start); return; }
      const limit = parseLimit(params.limit, 15, 50);
      const data = await client.search(q, limit);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /trending?limit=N
    if (path === '/trending') {
      const limit = parseLimit(params.limit, 15, 50);
      const data = await client.searchTrending(limit);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /channel/:id/videos?limit=N
    const channelMatch = path.match(/^\/channel\/([^\/]+)\/videos$/);
    if (channelMatch) {
      const limit = parseLimit(params.limit, 15, 50);
      const data = await client.searchChannel(channelMatch[1], limit);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /playlist/:id?limit=N
    const playlistMatch = path.match(/^\/playlist\/([^\/?]+)$/);
    if (playlistMatch) {
      const limit = parseLimit(params.limit, 15, 50);
      const data = await client.searchPlaylist(playlistMatch[1], limit);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /video/:id (exact match, no trailing segments)
    const videoExact = path.match(/^\/video\/([^\/]+)$/);
    if (videoExact) {
      const data = await client.getVideo(videoExact[1]);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /video/:id/comments?limit=N&sort=top|newest
    const commentsMatch = path.match(/^\/video\/([^\/]+)\/comments$/);
    if (commentsMatch) {
      const limit = parseLimit(params.limit, 20, 100);
      const sort = (params.sort === 'top' || params.sort === 'newest') ? params.sort : 'top';
      const data = await getComments(commentsMatch[1], { limit, sortBy: sort as 'top' | 'newest' });
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /video/:id/related?limit=N
    const relatedMatch = path.match(/^\/video\/([^\/]+)\/related$/);
    if (relatedMatch) {
      const limit = parseLimit(params.limit, 15, 50);
      const data = await getRelatedVideos(relatedMatch[1], { limit });
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /video/:id/stats
    const statsMatch = path.match(/^\/video\/([^\/]+)\/stats$/);
    if (statsMatch) {
      const data = await client.getVideoStats(statsMatch[1]);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    // GET /video/:id/live
    const liveMatch = path.match(/^\/video\/([^\/]+)\/live$/);
    if (liveMatch) {
      const data = await client.getLiveStreamInfo(liveMatch[1]);
      res.setHeader('X-Response-Time', elapsed());
      sendJSON(res, 200, data);
      logRequest('GET', path, 200, Date.now() - start);
      return;
    }

    sendError(res, 404, 'Not found');
    logRequest('GET', path, 404, Date.now() - start);
  } catch (err: any) {
    sendError(res, 500, err.message || 'Internal server error');
    logRequest('GET', path, 500, Date.now() - start);
  }
}

const server = createServer(handleRequest);

const entryUrl = import.meta.url;
const argvUrl = process.argv[1] ? `file:///${process.argv[1].replace(/\\/g, '/')}` : '';
const isMain = argvUrl && entryUrl === argvUrl;

if (isMain) {
  server.listen(PORT, () => {
    console.log(`ytapis-server v${VERSION} running on http://localhost:${PORT}`);
    console.log(`API docs: http://localhost:${PORT}/`);
    console.log(`Health:   http://localhost:${PORT}/health`);
  });

  function shutdown(signal: string) {
    console.log(`\nReceived ${signal}, shutting down...`);
    server.close(() => {
      console.log('Server closed.');
      process.exit(0);
    });
    setTimeout(() => { process.exit(1); }, 10_000).unref();
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

export { server, handleRequest };
