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
https://ytapis.djalokyt27.workers.dev/?q=cats&limit=5
```

## Mini UI Apps

| App | Description |
|-----|-------------|
| [Search UI](/apps/search/) | Search YouTube and browse results as cards |
| [Video Info](/apps/video-info/) | Look up video metadata and preview via embed |
| [Apps Home](/apps/) | Landing page linking all mini apps |

## How it works

1. Searches YouTube using standard `youtube.com/results?search_query=...`
2. Extracts video IDs from the page
3. Fetches metadata via YouTube's official oEmbed API

## Mini UI Apps

Each app is a self-contained local web server that uses its respective ytapis package directly.
Open `http://localhost:PORT` in your browser after starting.

| Language | Run from source | Build .exe |
|----------|----------------|------------|
| **Python** | `cd apps/python && pip install -r requirements.txt && python app.py` (port 5000) | `cd apps/python && build.bat` (16 MB) |
| **Node.js** | `cd apps/node && npm install && npm start` (port 3000) | `cd apps/node && build.bat` (36 MB) |
| **Go** | `cd apps/go && go run main.go` (port 8080) | `cd apps/go && build.bat` (7 MB) |
| **Dart** | `cd apps/dart && dart pub get && dart run server.dart` (port 8080) | `cd apps/dart && build.bat` (6 MB) |

## License

MIT

