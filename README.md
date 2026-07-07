# ytapis

> Search YouTube and get video metadata &mdash; **no API key required**.

ytapis is a multi-platform toolkit that scrapes YouTube search results and enriches them via the oEmbed API. No Google API key, no OAuth, no sign-up needed.

Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

---

## Packages

| Platform | Package | Registry | Install |
|----------|---------|----------|---------|
| **TypeScript** | `ytapis-core` | [npm](https://www.npmjs.com/package/ytapis-core) | `npm i ytapis-core` |
| **CLI** | `ytapis-cli` | [npm](https://www.npmjs.com/package/ytapis-cli) | `npx ytapis search cats` |
| **MCP Server** | `ytapis-mcp` | [npm](https://www.npmjs.com/package/ytapis-mcp) | `npx ytapis-mcp` |
| **Python** | `ytapis` | [PyPI](https://pypi.org/project/ytapis/) | `pip install ytapis` |
| **Go** | `ytapis/go` | Go module | `import "github.com/pgboyahpgr-commits/ytapis/go"` |
| **Dart** | `ytapis` | [pub.dev](https://pub.dev/packages/ytapis) | `dart pub add ytapis` |

## Quick Start

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
npx ytapis search cats --limit 5
# or if installed globally:
ytapis search cats --limit 5
```

### MCP Server (AI Assistants)
```bash
npx ytapis-mcp
# Configure in Claude Desktop / Cline / Continue etc.
```

---

## API Demo (Cloudflare Worker)

```
https://ytapis.djalokyt27.workers.dev/?q=cats&limit=5
```

---

## Desktop Apps

Native Windows GUI apps that use the ytapis packages directly &mdash; no web server required.

| App | Directory | Framework | Package | Size |
|-----|-----------|-----------|---------|------|
| **Python** | [`apps/python/`](apps/python/) | tkinter | `ytapis` (PyPI) | 11 MB |
| **Node.js** | [`apps/node/`](apps/node/) | Electron | `ytapis-core` (npm) | 188 MB |
| **Flutter** | [`apps/flutter/`](apps/flutter/) | Flutter Desktop | `ytapis` (pub.dev) | 80 KB + DLLs |

### Run from source

```bash
# Python
cd apps/python
pip install -r requirements.txt
python app.py

# Node.js (Electron)
cd apps/node
npm install
npm start

# Flutter
cd apps/flutter
flutter pub get
flutter run
```

### Build standalone .exe

```bash
# Each app has a build.bat
cd apps/python && build.bat
cd apps/node   && build.bat
cd apps/flutter && flutter build windows
```

### Downloads

Pre-built `.exe` files are available on the [Releases](https://github.com/pgboyahpgr-commits/ytapis/releases) page.

---

## Repository Structure

```
ytapis/
├── packages/
│   ├── core/          # ytapis-core — TypeScript library (npm)
│   ├── cli/           # ytapis-cli — CLI tool (npm)
│   ├── mcp/           # ytapis-mcp — MCP server for AI (npm)
│   └── worker/        # Cloudflare Worker — API demo
├── python/            # ytapis — Python library (PyPI)
├── dart/              # ytapis — Dart library (pub.dev)
├── go/                # ytapis/go — Go library
├── apps/
│   ├── python/        # Python tkinter desktop app
│   ├── node/          # Electron desktop app
│   └── flutter/       # Flutter desktop app
└── .github/workflows/ # CI/CD publishing pipelines
```

---

## How It Works

1. **Search** &mdash; Fetches `youtube.com/results?search_query=...` and extracts video IDs via regex
2. **Enrich** &mdash; Calls YouTube's oEmbed API (`youtube.com/oembed`) for each video to get title, author, thumbnail
3. **Return** &mdash; Returns structured results with `id`, `title`, `author`, `thumbnail`, `fullUrl`, `embedUrl`

No authentication, no API keys, no rate limits from Google &mdash; just publicly available YouTube data.

---

## License

MIT &mdash; see [LICENSE](LICENSE).

Built and managed by [geethudinoyt](https://github.com/geethudinoyt).
