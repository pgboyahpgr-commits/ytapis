import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';

const originalFetch = globalThis.fetch;

after(() => {
  globalThis.fetch = originalFetch;
});

const ytInitialData = {
  contents: {
    twoColumnSearchResultsRenderer: {
      primaryContents: {
        sectionListRenderer: {
          contents: [
            {
              itemSectionRenderer: {
                contents: [
                  {
                    videoRenderer: {
                      videoId: 'dQw4w9WgXcQ',
                      title: { runs: [{ text: 'Test Video 1' }] },
                      ownerText: { runs: [{ text: 'Test Channel' }] },
                      lengthText: { simpleText: '3:45' },
                      viewCountText: { simpleText: '1.2M views' },
                      publishedTimeText: { simpleText: '2 weeks ago' },
                      thumbnail: { thumbnails: [{ url: 'https://i.ytimg.com/vi/dQw/hq.jpg', width: 480, height: 360 }] },
                    },
                  },
                  {
                    videoRenderer: {
                      videoId: 'abcdefghijk',
                      title: { runs: [{ text: 'Test Video 2' }] },
                      ownerText: { runs: [{ text: 'Another Channel' }] },
                      lengthText: { simpleText: '10:30' },
                      viewCountText: { simpleText: '53K views' },
                      publishedTimeText: { simpleText: '1 month ago' },
                      thumbnail: { thumbnails: [{ url: 'https://i.ytimg.com/vi/abc/hq.jpg', width: 480, height: 360 }] },
                    },
                  },
                ],
              },
            },
            {
              continuationItemRenderer: {
                continuationEndpoint: {
                  continuationCommand: { token: 'test-token' },
                },
              },
            },
          ],
        },
      },
    },
  },
};

describe('ytapis-core', () => {
  describe('getVideo', () => {
    it('returns fallback on fetch error', async () => {
      const { getVideo } = await import('../index');
      globalThis.fetch = (_url: string, _init?: any) => Promise.reject(new Error('network error'));
      const result = await getVideo('dQw4w9WgXcQ');
      assert.ok(result);
      assert.equal(result.id, 'dQw4w9WgXcQ');
    });

    it('returns oembed data when watch page has no videoDetails', async () => {
      const { getVideo } = await import('../index');
      let call = 0;
      globalThis.fetch = ((_url: string, _init?: any) => {
        call++;
        if (call === 1) {
          return Promise.resolve({
            ok: true,
            text: () => Promise.resolve('<html>no ytInitialPlayerResponse here</html>'),
          } as any);
        }
        return Promise.resolve({
          ok: true,
          json: () =>
            Promise.resolve({
              title: 'Rick Astley',
              author_name: 'Rick Astley',
              thumbnail_url: 'https://i.ytimg.com/vi/dQw/hq.jpg',
            }),
        } as any);
      }) as any;
      const result = await getVideo('dQw4w9WgXcQ');
      assert.equal(result.title, 'Rick Astley');
      assert.equal(result.author, 'Rick Astley');
    });
  });

  describe('search', () => {
    it('returns parsed results with rich metadata', async () => {
      const { search } = await import('../index');
      globalThis.fetch = ((_url: string, _init?: any) =>
        Promise.resolve({
          ok: true,
          text: () =>
            Promise.resolve(
              `<script>var ytInitialData = ${JSON.stringify(ytInitialData)};</script>`,
            ),
        } as any)) as any;

      const response = await search('test', { limit: 2 });
      assert.equal(response.results.length, 2);
      assert.equal(response.continuation, 'test-token');
      assert.equal(response.results[0].title, 'Test Video 1');
      assert.equal(response.results[0].duration, '3:45');
      assert.equal(response.results[0].durationSeconds, 225);
      assert.equal(response.results[0].viewCountRaw, 1200000);
      assert.equal(response.results[1].viewCountRaw, 53000);
    });
  });
});
