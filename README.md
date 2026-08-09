# ytapis



> **11 languages. 17 functions. Zero API key.** Search YouTube and get rich video metadata — no Google account, no OAuth, no sign-up required.

**[Live Demo](https://ytapis.djalokyt27.workers.dev)** | **[Full API Docs](API.md)** | **[Desktop Apps](#desktop-apps)**

---

## Packages

| # | Language | Package | Registry | Install |
|---|----------|---------|----------|---------|
| 1 | **TypeScript** | `ytapis-core` | [npm](https://www.npmjs.com/package/ytapis-core) | `npm i ytapis-core` |
| 2 | **CLI** | `ytapis-cli` | [npm](https://www.npmjs.com/package/ytapis-cli) | `npx ytapis search cats` |
| 3 | **MCP Server** | `ytapis-mcp` | [npm](https://www.npmjs.com/package/ytapis-mcp) | `npx ytapis-mcp` |
| 4 | **Python** | `ytapis` | [PyPI](https://pypi.org/project/ytapis/) | `pip install ytapis` |
| 5 | **Go** | `ytapi` | Go module | `go get github.com/pgboyahpgr-commits/ytapis/go` |
| 6 | **Dart** | `ytapis` | [pub.dev](https://pub.dev/packages/ytapis) | `dart pub add ytapis` |
| 7 | **C#** | `Ytapis` | [NuGet](https://www.nuget.org/packages/ytapis) | `dotnet add package Ytapis` |
| 8 | **PHP** | `geethudinoyt/ytapis` | [Packagist](https://packagist.org/) | `composer require geethudinoyt/ytapis` |
| 9 | **Kotlin** | `ytapis` | Maven Central | `implementation("ytapis:ytapis:2.0.0")` |
| 10 | **C++** | `ytapis` | Header-only | `#include <ytapis/ytapis.hpp>` |
| 11 | **Lua** | `ytapis` | [LuaRocks](https://luarocks.org/) | `luarocks install ytapis` |

## VideoResult Schema

All 11 languages return a unified `VideoResult` with 19 fields:

| Field | Type | Example |
|-------|------|---------|
| `id` | string | `"dQw4w9WgXcQ"` |
| `title` | string | `"Rick Astley - Never Gonna Give You Up"` |
| `author` | string | `"Rick Astley"` |
| `channelUrl` | string | `"/channel/UCuAXFkgsw1L7xaCfnd5JJOw"` |
| `thumbnail` | string | `https://i.ytimg.com/vi/.../maxresdefault.jpg` |
| `thumbnails` | array | `[{url, width, height}, ...]` (all qualities) |
| `fullUrl` | string | `"https://www.youtube.com/watch?v=..."` |
| `embedUrl` | string | `"https://www.youtube.com/embed/..."` |
| `duration` | string | `"3:34"` |
| `durationSeconds` | int | `214` |
| `viewCount` | string | `"1.8B views"` |
| `viewCountRaw` | number | `1802331071` |
| `publishedTime` | string | `"3 years ago"` |
| `description` | string | Snippet of the video description |
| `channelAvatar` | string | URL of the channel's profile picture |
| `isLive` | bool | `false` |
| `isUpcoming` | bool | `false` |
| `isVerified` | bool | `true` |

---

## Quick Start

### TypeScript
```ts
import { search, getVideo, getComments, getChannelMetadata, getTranscript } from 'ytapis-core'

const { results } = await search('cats', { limit: 5 });
console.log(results[0].title, results[0].viewCount, results[0].duration);

const video = await getVideo('dQw4w9WgXcQ');
console.log(video.title, video.isVerified, video.channelAvatar);

const { comments } = await getComments('dQw4w9WgXcQ', { limit: 3 });
console.log(comments[0].author.name, ':', comments[0].text);

const channel = await getChannelMetadata('UCuAXFkgsw1L7xaCfnd5JJOw');
console.log(channel.subscriberCount, channel.banner);

const transcript = await getTranscript('dQw4w9WgXcQ');
console.log(transcript[0].text, transcript[0].start);
```

### Python
```py
from ytapis import search, get_video, get_comments, get_channel_metadata, get_transcript

results = search("cats", limit=5)
for v in results:
    print(f"{v.title} — {v.view_count} — {v.duration}")

video = get_video("dQw4w9WgXcQ")
print(video.title, video.is_verified)

comments, _ = get_comments("dQw4w9WgXcQ", limit=3)
for c in comments:
    print(f"{c.author.name}: {c.text}")

channel = get_channel_metadata("UCuAXFkgsw1L7xaCfnd5JJOw")
print(channel.subscriber_count, channel.banner)

transcript = get_transcript("dQw4w9WgXcQ")
print(transcript[0].text)
```

### Go
```go
import ytapi "github.com/pgboyahpgr-commits/ytapis/go"

results, _ := ytapi.Search("cats", "", "", 5)
fmt.Println(results[0].Title, results[0].ViewCount)

video := ytapi.GetVideo("dQw4w9WgXcQ")
fmt.Println(video.Title, video.Duration)

comments, _, _ := ytapi.GetComments("dQw4w9WgXcQ", 3)
fmt.Println(comments[0].Text, comments[0].LikeCount)
```

### Dart

```dart
import 'package:ytapis/ytapis.dart';

final results = await search('cats', limit: 5);
final video = await getVideo('dQw4w9WgXcQ');
print(video.title);
```

### C\#

```csharp
using Ytapis;

var results = Ytapis.Search("cats", 5);
var video = Ytapis.GetVideo("dQw4w9WgXcQ");
var channel = Ytapis.GetChannelMetadata("UCuAXFkgsw1L7xaCfnd5JJOw");
Console.WriteLine($"{video.Title} - {video.ViewCount}");
```

### PHP

```php
require 'vendor/autoload.php';
use GeethuDino\Ytapis\Ytapis;

$results = Ytapis::search("cats", 5);
$video = Ytapis::getVideo("dQw4w9WgXcQ");
echo $video->title;
```

### Kotlin

```kotlin
import ytapis.Ytapis

val results = Ytapis.search("cats", 5)
val video = Ytapis.getVideo("dQw4w9WgXcQ")
println("${video.title} - ${video.viewCount}")
```

### C++

```cpp
#include <ytapis/ytapis.hpp>
auto results = ytapis::search("cats", 5);
std::cout << results.results[0].title << std::endl;
```

### Lua

```lua
local ytapis = require("ytapis")
local results = ytapis.search("cats", 5)
for _, v in ipairs(results) do
  print(v.title .. " - " .. v.author)
end
```

### CLI

```bash
npx ytapis search cats --limit 5
npx ytapis trending --limit 10
npx ytapis video dQw4w9WgXcQ
npx ytapis channel UC-lHJZR3Gqxm24_Vd_AJ5Yw --limit 10
```

### MCP Server (for AI assistants)

```bash
npx ytapis-mcp
# Configure in Claude Desktop, Cline, Continue, or any MCP-compatible client
```

---

## Full API Surface

| # | Function | Description |
|---|----------|-------------|
| 1 | `search(query, limit, gl?, hl?)` | Search YouTube |
| 2 | `searchTrending(limit, gl?, hl?)` | Trending feed |
| 3 | `searchChannel(channelId, limit)` | Channel videos |
| 4 | `searchPlaylist(playlistId, limit)` | Playlist videos |
| 5 | `searchShorts(query, limit, gl?, hl?)` | YouTube Shorts |
| 6 | `searchContinue(token, limit)` | Pagination |
| 7 | `getVideo(id)` | Single video metadata |
| 8 | `getComments(videoId, limit, sortBy?)` | Comment threads + replies |
| 9 | `getRelatedVideos(videoId, limit)` | Sidebar recommendations |
| 10 | `getChannelMetadata(channelId)` | Banner, subscribers, links |
| 11 | `getVideoStats(videoId)` | Views, likes, live status |
| 12 | `getLiveStreamInfo(videoId)` | Viewer count, start time |
| 13 | `getTranscript(videoId, lang?)` | Captions with timestamps |

---

## Tools & Infrastructure

| Tool | Command / Link | Description |
|------|---------------|-------------|
| **Demo API** | [ytapis.djalokyt27.workers.dev](https://ytapis.djalokyt27.workers.dev) | Live Cloudflare Worker with 14 endpoints |
| **REST Server** | `npm run serve` | Local HTTP server on port 3000 |
| **GitHub Pages** | `demo/` | Browser-based YouTube search |
| **Browser Extension** | `extension/` | Right-click any video → metadata popup |
| **Docker** | `docker compose up` | Full stack in one command |
| **Benchmarks** | `npm run bench` | Performance tests |
| **Scaffolding** | `npx create-ytapis-app` | Project generator for any language |
| **Analytics** | `npm run dashboard` | Self-hosted usage dashboard on :4000 |

---

## Desktop Apps

| App | Framework | Size |
|-----|-----------|------|
| **Python** tkinter | `apps/python/` | ~11 MB |
| **Electron** | `apps/node/` | ~188 MB |
| **Flutter** | `apps/flutter/` | ~80 KB + DLLs |

```bash
cd apps/python && pip install -r requirements.txt && python app.py
cd apps/node && npm install && npm start
cd apps/flutter && flutter pub get && flutter run
```

---

## How It Works

1. **Fetch** — HTTP GET `youtube.com/results?search_query=...` from YouTube
2. **Extract** — Brace-counting JSON parser extracts `ytInitialData` (no fragile regex)
3. **Parse** — Walk `videoRenderer` tree for all 19 fields including durations, view counts, badges, thumbnails, channel info
4. **Paginate** — InnerTube continuation tokens for infinite scroll
5. **Cache** — LRU cache with 5-min TTL eliminates duplicate requests
6. **Retry** — Exponential backoff with jitter on 429/503 responses

No API keys. No auth. Just publicly available YouTube data. Prefers `maxresdefault` thumbnails (1280px).

---

## Repository Structure

```
ytapis/
├── packages/         # TypeScript: core, cli, mcp, server, worker, create
├── python/           # Python library (PyPI) + tests
├── go/               # Go library + CLI + benchmark
├── dart/             # Dart library (pub.dev) + CLI + tests
├── csharp/           # C# library (NuGet) + CLI
├── php/              # PHP library (Packagist) + CLI
├── kotlin/           # Kotlin library (Maven) + CLI
├── cpp/              # C++ header-only library + CLI
├── lua/              # Lua library (LuaRocks) + CLI
├── apps/             # Desktop apps (tkinter, Electron, Flutter)
├── extension/        # Chrome/Firefox browser extension
├── demo/             # GitHub Pages live search demo
├── dashboard/        # Self-hosted analytics dashboard
├── tests/            # Integration tests + snapshots
├── proto/            # gRPC protobuf definitions
└── .github/          # CI/CD + 9 publish workflows
```

---


---

## License

MIT — see [LICENSE](LICENSE). Built by the community, for the community.
