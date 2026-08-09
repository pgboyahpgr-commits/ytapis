import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'http';
import type { AddressInfo } from 'net';

let server: ReturnType<typeof createServer>;
let baseURL: string;

async function fetchJSON(path: string, opts?: { method?: string }) {
  const res = await fetch(`${baseURL}${path}`, { method: opts?.method || 'GET' });
  const body = await res.text();
  let json: unknown = null;
  try { json = JSON.parse(body); } catch { /* not json */ }
  return { status: res.status, headers: res.headers, body, json };
}

before(async () => {
  const { handleRequest } = await import('../packages/server/src/index.ts');
  server = createServer(handleRequest);
  await new Promise<void>((resolve) => server.listen(0, resolve));
  const addr = server.address() as AddressInfo;
  baseURL = `http://localhost:${addr.port}`;
});

after(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

describe('server integration', () => {
  it('GET /health returns 200 with status:ok', async () => {
    const { status, json } = await fetchJSON('/health');
    assert.equal(status, 200);
    assert.ok(typeof json === 'object' && json !== null);
    assert.equal((json as any).status, 'ok');
  });

  it('GET /search?q=cats returns JSON array with results', async () => {
    const { status, json } = await fetchJSON('/search?q=cats');
    assert.equal(status, 200);
    assert.ok(typeof json === 'object' && json !== null);
    assert.ok(Array.isArray((json as any).results));
    assert.ok((json as any).results.length > 0);
  });

  it('GET /video/dQw4w9WgXcQ returns single video object', async () => {
    const { status, json } = await fetchJSON('/video/dQw4w9WgXcQ');
    assert.equal(status, 200);
    assert.ok(typeof json === 'object' && json !== null);
    assert.equal(typeof (json as any).id, 'string');
    assert.equal(typeof (json as any).title, 'string');
  });

  it('OPTIONS returns CORS headers', async () => {
    const res = await fetch(`${baseURL}/health`, { method: 'OPTIONS' });
    assert.equal(res.status, 204);
    assert.equal(res.headers.get('access-control-allow-origin'), '*');
    assert.equal(res.headers.get('access-control-allow-methods'), 'GET, OPTIONS');
  });

  it('GET /nonexistent returns 404 error', async () => {
    const { status, json } = await fetchJSON('/nonexistent');
    assert.equal(status, 404);
    assert.ok(typeof json === 'object' && json !== null);
    assert.equal((json as any).error, 'Not found');
    assert.equal((json as any).status, 404);
  });

  it('responds with X-Powered-By: ytapis header', async () => {
    const res = await fetch(`${baseURL}/health`);
    assert.equal(res.headers.get('x-powered-by'), 'ytapis');
  });
});
