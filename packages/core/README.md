# ytapis-core

TypeScript library to search YouTube and get video metadata &mdash; **no API key required**.

Part of the [ytapis](https://github.com/pgboyahpgr-commits/ytapis) monorepo. Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Install

```bash
npm i ytapis-core
```

## Usage

```ts
import { search } from 'ytapis-core'

const videos = await search('cats', { limit: 5 })
for (const v of videos) {
  console.log(v.title, '-', v.author)
}
```

## API

### `search(query, options?)`

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `query` | `string` | — | YouTube search query |
| `options.limit` | `number` | `15` | Max results to return |

Returns `Promise<VideoResult[]>` where each result:

```ts
{
  id: string        // YouTube video ID (11 chars)
  title: string     // Video title
  author: string    // Channel / uploader name
  thumbnail: string // Thumbnail URL (hqdefault)
  fullUrl: string   // https://www.youtube.com/watch?v=...
  embedUrl: string  // https://www.youtube.com/embed/...?rel=0
}
```

## License

MIT
