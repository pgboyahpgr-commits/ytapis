# ytapis

Search YouTube and get video metadata — **no API key required**.

**What you get:** Video ID, title, author, thumbnail, and URLs — from any search query.

## Packages

| Platform | Package | Install | Usage |
|----------|---------|---------|-------|
| **TypeScript** | `@ytapi/core` | `npm i @ytapi/core` | `search("cats")` |
| **CLI** | `@ytapi/cli` | `npx @ytapi search cats` | Terminal |
| **MCP Server** | `@ytapi/mcp` | `npx @ytapi-mcp` | AI assistants |
| **Python** | `ytapi` | `pip install ytapi` | `from ytapi import search` |
| **Go** | `ytapi-go` | `go get` | `ytapi.Search("cats")` |
| **Dart** | `ytapi` | `dart pub add ytapi` | `search("cats")` |

## Quick examples

### TypeScript

```ts
import { search } from '@ytapi/core'
const videos = await search('cats', { limit: 5 })
console.log(videos[0].title, videos[0].author)
```

### Python

```py
from ytapi import search
results = search("cats", limit=5)
for v in results:
    print(v["title"], "-", v["author"])
```

### Go

```go
import "github.com/ytapis/ytapis/go"
results, _ := ytapi.Search("cats", 5)
```

### Dart

```dart
import 'package:ytapi/ytapi.dart';
final results = await search('cats', limit: 5);
```

### CLI

```bash
ytapi search cats --limit 5
```

### API Demo (Cloudflare Worker)

```
https://ytapi-demo.yourname.workers.dev/?q=cats&limit=5
```

## How it works

1. Searches YouTube using standard `youtube.com/results?search_query=...`
2. Extracts video IDs from the page
3. Fetches metadata via YouTube's official oEmbed API

## License

MIT
