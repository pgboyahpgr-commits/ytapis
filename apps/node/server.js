const http = require('http');
const fs = require('fs');
const path = require('path');
const net = require('net');
const { exec } = require('child_process');
const { search } = require('ytapis-core');

function getPort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.listen(0, () => { const p = s.address().port; s.close(() => resolve(p)); });
    s.on('error', reject);
  });
}

function openBrowser(url) {
  const cmd = process.platform === 'win32' ? `start "" "${url}"`
    : process.platform === 'darwin' ? `open "${url}"`
    : `xdg-open "${url}"`;
  exec(cmd, () => {});
}

let indexHtml = '';
const htmlPath = path.join(__dirname, 'public', 'index.html');
try { indexHtml = fs.readFileSync(htmlPath, 'utf-8'); } catch (_) {}

async function main() {
  const port = await getPort();

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://localhost:${port}`);
    const pathname = url.pathname;

    if (pathname === '/' || pathname === '/index.html') {
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(indexHtml);
      return;
    }

    if (pathname === '/search') {
      const q = url.searchParams.get('q');
      const limit = parseInt(url.searchParams.get('limit')) || 15;
      if (!q) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'missing query param "q"' }));
        return;
      }
      try {
        const results = await search(q, { limit });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(results));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: err.message }));
      }
      return;
    }

    res.writeHead(404);
    res.end('Not found');
  });

  const urlStr = `http://localhost:${port}`;
  server.listen(port, '0.0.0.0', () => {
    console.log(`\n  ytapis Node app running at ${urlStr}`);
    console.log('  Close this window or press Ctrl+C to stop.\n');
    openBrowser(urlStr);
  });
}

main().catch(err => { console.error(err); process.exit(1); });
