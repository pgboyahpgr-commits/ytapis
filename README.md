# ytapis

Search YouTube and get video metadata ??? **no API key required**.

**What you get:** Video ID, title, author, thumbnail, and URLs ??? from any search query.

## Packages

| Platform | Package | Install | Usage |
|----------|---------|---------|-------|
| **TypeScript** | `ytapis-core` | `npm i ytapis-core` | `search("cats")` |
| **CLI** | `ytapis-cli` | `npx ytapis search cats` | Terminal |
| **MCP Server** | `ytapis-mcp` | `npx ytapis-mcp` | AI assistants |
| **Python** | `ytapis` | `pip install ytapis` | `from ytapis import search` |
| **Go** | `github.com/pgboyahpgr-commits/ytapis/go` | `go get` | `ytapi.Search("cats")` |
| **Dart** | `ytapis` | `dart pub add ytapis` | `search("cats")` |

## Quick examples

### TypeScript

```ts
import { search } from 'ytapis-core'
const videos = await search('cats', { limit: 5 })
console.log(videos[0].title, videos[0].author)
```

### Python

```py
from ytapis import search
results = search("cats", limit=5)
for v in results:
    print(v["title"], "-", v["author"])
```

### Go

```go
import "github.com/pgboyahpgr-commits/ytapis/go"
results, _ := ytapi.Search("cats", 5)
```

### Dart

```dart
import 'package:ytapis/ytapis.dart';
final results = await search('cats', limit: 5);
```

### CLI

```bash
ytapis search cats --limit 5
```

### API Demo (Cloudflare Worker)

```
https://ytapis-demo.yourname.workers.dev/?q=cats&limit=5
```

## How it works

1. Searches YouTube using standard `youtube.com/results?search_query=...`
2. Extracts video IDs from the page
3. Fetches metadata via YouTube's official oEmbed API

## License

MIT

