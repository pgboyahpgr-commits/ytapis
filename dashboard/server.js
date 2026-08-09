const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 4000;
const DATA_FILE = path.join(__dirname, 'events.json');
const STATIC_DIR = __dirname;

const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
};

function readEvents() {
  try {
    const raw = fs.readFileSync(DATA_FILE, 'utf-8');
    return JSON.parse(raw);
  } catch {
    return [];
  }
}

function writeEvents(events) {
  fs.writeFileSync(DATA_FILE, JSON.stringify(events, null, 2));
}

function getAggregatedStats() {
  const events = readEvents();
  const now = Date.now();
  const last24h = now - 24 * 60 * 60 * 1000;

  const recentEvents = events.filter((e) => e.timestamp > last24h);

  const total_searches = events.length;
  const last_24h_hits = [];

  for (let h = 23; h >= 0; h--) {
    const slot = now - h * 60 * 60 * 1000;
    const label = new Date(slot).toISOString().slice(11, 16);
    const count = recentEvents.filter(
      (e) => e.timestamp >= slot && e.timestamp < slot + 60 * 60 * 1000
    ).length;
    last_24h_hits.push({ time: label, count });
  }

  const queryMap = {};
  const platformBreakdown = {};
  for (const ev of events) {
    const q = (ev.query || '').trim().toLowerCase();
    if (q) queryMap[q] = (queryMap[q] || 0) + 1;
    const p = ev.platform || 'unknown';
    platformBreakdown[p] = (platformBreakdown[p] || 0) + 1;
  }

  const top_queries = Object.entries(queryMap)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 20)
    .map(([q, c]) => ({ query: q, count: c }));

  const channels_tracked = new Set(events.filter((e) => e.channel_id).map((e) => e.channel_id)).size;
  const comments_fetched = events.filter((e) => e.type === 'comment').length;
  const trending = events.filter((e) => e.type === 'trending').length;

  return {
    total_searches,
    trending_videos: trending,
    channels_tracked,
    comments_fetched,
    top_queries,
    last_24h_hits,
    platform_breakdown: platformBreakdown,
  };
}

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  if (req.method === 'POST' && req.url === '/api/event') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      try {
        const event = JSON.parse(body);
        event.timestamp = event.timestamp || Date.now();
        const events = readEvents();
        events.push(event);
        writeEvents(events);
        res.writeHead(201, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
      }
    });
    return;
  }

  if (req.method === 'GET' && req.url === '/api/analytics') {
    const stats = getAggregatedStats();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(stats));
    return;
  }

  let filePath = req.url === '/' ? '/index.html' : req.url.split('?')[0];
  filePath = path.join(STATIC_DIR, filePath);

  if (!filePath.startsWith(STATIC_DIR)) {
    res.writeHead(403);
    return res.end('Forbidden');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not Found');
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(data);
    }
  });
});

server.listen(PORT, () => {
  console.log(`ytapis dashboard running at http://localhost:${PORT}`);
});
