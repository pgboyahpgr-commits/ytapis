import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const snapshotsDir = resolve(__dirname, '__snapshots__');

function load(name: string): Record<string, unknown> {
  return JSON.parse(readFileSync(resolve(snapshotsDir, name), 'utf-8'));
}

describe('snapshots', () => {
  describe('search_cats.json', () => {
    it('has results array with video objects', () => {
      const data = load('search_cats.json');
      if (data._note) return;
      assert.ok(Array.isArray(data.results));
      assert.ok(data.results.length > 0);
      const v = data.results[0] as any;
      assert.equal(typeof v.id, 'string');
      assert.equal(typeof v.title, 'string');
      assert.equal(typeof v.author, 'string');
      assert.ok(v.id.length > 0);
      assert.ok(v.title.length > 0);
    });

    it('results have thumbnails array', () => {
      const data = load('search_cats.json');
      if (data._note) return;
      const v = data.results[0] as any;
      assert.ok(Array.isArray(v.thumbnails));
      assert.ok(v.thumbnails.length > 0);
      assert.equal(typeof v.thumbnails[0].url, 'string');
      assert.equal(typeof v.thumbnails[0].width, 'number');
    });
  });

  describe('trending.json', () => {
    it('has results array', () => {
      const data = load('trending.json');
      if (data._note) return;
      assert.ok(Array.isArray(data.results));
    });
  });

  describe('comments.json', () => {
    it('has comments array with author data', () => {
      const data = load('comments.json');
      if (data._note) return;
      assert.ok(Array.isArray(data.comments));
      if (data.comments.length === 0) return;
      const c = data.comments[0] as any;
      assert.equal(typeof c.id, 'string');
      assert.equal(typeof c.text, 'string');
      assert.ok(c.author);
      assert.equal(typeof c.author.name, 'string');
    });
  });

  describe('related.json', () => {
    it('is an array of related videos', () => {
      const data = load('related.json');
      if (data._note) return;
      assert.ok(Array.isArray(data));
      if (data.length === 0) return;
      const r = data[0] as any;
      assert.equal(typeof r.id, 'string');
      assert.equal(typeof r.title, 'string');
    });
  });

  describe('video.json', () => {
    it('has expected video metadata', () => {
      const data = load('video.json');
      if (data._note) return;
      assert.equal(typeof data.id, 'string');
      assert.equal(typeof data.title, 'string');
      assert.equal(typeof data.author, 'string');
      assert.equal(typeof data.duration, 'string');
      assert.equal(typeof data.durationSeconds, 'number');
    });
  });
});
