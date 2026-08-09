# ytapis API Reference v2.0

Built and managed by **geethudinoyt** and **geethudino (Ruthvik)**.

---

## Data Types

### VideoResult

Represents a YouTube video with full metadata.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | 11-character YouTube video ID (e.g. `"dQw4w9WgXcQ"`) |
| `title` | `string` | Video title as displayed on YouTube |
| `author` | `string` | Channel name of the uploader |
| `channelUrl` | `string` | Full channel URL on YouTube (e.g. `"https://www.youtube.com/@channel"`) |
| `thumbnail` | `string` | URL of the highest-quality available thumbnail |
| `thumbnails` | `Thumbnail[]` | Array of all available thumbnail sizes and their URLs |
| `fullUrl` | `string` | Full watch URL (e.g. `"https://www.youtube.com/watch?v=dQw4w9WgXcQ"`) |
| `embedUrl` | `string` | Embeddable iframe URL (e.g. `"https://www.youtube.com/embed/dQw4w9WgXcQ"`) |
| `duration` | `string` | Human-readable duration formatted as `"M:SS"` or `"H:MM:SS"` (e.g. `"12:34"`) |
| `durationSeconds` | `number` | Duration in seconds as a raw integer |
| `viewCount` | `string` | Formatted view count string (e.g. `"1.2M views"`, `"532K views"`) |
| `viewCountRaw` | `number` | Raw numeric view count (e.g. `1234567`) |
| `publishedTime` | `string` | Relative time since publication (e.g. `"2 weeks ago"`, `"3 months ago"`) |
| `description` | `string` | First 200 characters of the video description snippet |
| `channelAvatar` | `string` | URL of the channel's profile picture / avatar image |
| `isLive` | `boolean` | `true` if the video is currently live streaming |
| `isUpcoming` | `boolean` | `true` if the video is a scheduled premiere / upcoming live stream |
| `isVerified` | `boolean` | `true` if the channel has a verified badge from YouTube |

### Thumbnail

| Field | Type | Description |
|-------|------|-------------|
| `url` | `string` | Full thumbnail image URL |
| `width` | `number` | Width in pixels |
| `height` | `number` | Height in pixels |

### SearchResponse

Returned by search functions. Contains results and optional pagination token.

| Field | Type | Description |
|-------|------|-------------|
| `results` | `VideoResult[]` | Array of video results for the current page |
| `continuation` | `string \| null` | Token for fetching the next page of results, or `null` if no more pages |
| `estimatedResults` | `number \| null` | Approximate total number of results for the query (when available) |
| `query` | `string \| null` | The original search query that produced these results |
| `params` | `object \| null` | Internal parameters required for continuation (language, region, etc.) |

### RelatedVideo

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | 11-character YouTube video ID |
| `title` | `string` | Video title |
| `author` | `string` | Channel name |
| `thumbnail` | `string` | Thumbnail URL |
| `duration` | `string` | Formatted duration (e.g. `"5:21"`) |
| `viewCount` | `string` | Formatted view count |
| `viewCountRaw` | `number` | Raw view count |
| `isLive` | `boolean` | Whether the recommended video is a live stream |

### ChannelMetadata

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Channel ID |
| `name` | `string` | Channel display name |
| `handle` | `string \| null` | Channel @handle (e.g. `"@channelname"`) |
| `url` | `string` | Full channel URL |
| `avatar` | `string` | Channel profile picture URL |
| `banner` | `string \| null` | Channel banner image URL |
| `description` | `string \| null` | Channel about/description text |
| `subscriberCount` | `string` | Formatted subscriber count (e.g. `"1.2M subscribers"`) |
| `subscriberCountRaw` | `number \| null` | Raw subscriber count number |
| `videoCount` | `number \| null` | Total number of videos on the channel |
| `isVerified` | `boolean` | Whether the channel is verified |
| `socialLinks` | `object[]` | Array of external links (platform, url) |
| `keywords` | `string[]` | Channel tags/keywords |

### TranscriptEntry

| Field | Type | Description |
|-------|------|-------------|
| `text` | `string` | The caption/transcript text segment |
| `start` | `number` | Start time in seconds |
| `duration` | `number` | Duration of this segment in seconds |
| `offset` | `number` | Offset from video start in milliseconds |

### LiveStreamInfo

| Field | Type | Description |
|-------|------|-------------|
| `id` | `string` | Video ID of the live stream |
| `title` | `string` | Stream title |
| `isLive` | `boolean` | Whether the stream is currently live |
| `isUpcoming` | `boolean` | Whether the stream is scheduled/upcoming |
| `viewerCount` | `number` | Current concurrent viewer count |
| `startTimestamp` | `number \| null` | Unix timestamp when the stream started |
| `scheduledStartTime` | `number \| null` | Unix timestamp for scheduled start (for upcoming streams) |
| `channelName` | `string` | Channel name hosting the stream |
| `channelAvatar` | `string` | Channel avatar URL |

### VideoStats

| Field | Type | Description |
|-------|------|-------------|
| `views` | `number` | Total view count |
| `likes` | `number \| null` | Like count (may be hidden) |
| `comments` | `number \| null` | Comment count |
| `isLive` | `boolean` | Whether the video is currently live |
| `viewerCount` | `number \| null` | Concurrent viewers if live |

---

## Functions

### `search(query, limit?, gl?, hl?)` → `Promise<SearchResponse>`

Search YouTube for videos matching a query string.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `query` | `string` | *(required)* | Search query string |
| `limit` | `number` | `20` | Maximum number of results to return |
| `gl` | `string` | `"US"` | ISO 3166-1 alpha-2 country code for regional results (e.g. `"GB"`, `"IN"`, `"JP"`) |
| `hl` | `string` | `"en"` | ISO 639-1 language code for UI text/hints (e.g. `"fr"`, `"de"`, `"es"`) |

**Returns:** `SearchResponse` with `results` array and `continuation` token for pagination.

**Errors:** Throws on network failure. Returns empty `results` with `continuation: null` if YouTube blocks the request.

**Examples:**

*TypeScript:*
```ts
import { search } from 'ytapis';

const { results, continuation } = await search('javascript tutorial', 10, 'US', 'en');
console.log(results[0].title); // "JavaScript Tutorial for Beginners"
```

*Python:*
```python
from ytapis import search

response = search("javascript tutorial", limit=10, gl="US", hl="en")
print(response.results[0].title)
```

*Go:*
```go
import "github.com/pgboyahpgr-commits/ytapis/go"

response, err := ytapis.Search("javascript tutorial", 10, "US", "en")
if err != nil {
    log.Fatal(err)
}
fmt.Println(response.Results[0].Title)
```

*Dart:*
```dart
import 'package:ytapis/ytapis.dart';

final response = await search('javascript tutorial', limit: 10, gl: 'US', hl: 'en');
print(response.results.first.title);
```

*C#:*
```csharp
using Ytapis;

var response = await YtapisClient.SearchAsync("javascript tutorial", limit: 10, gl: "US", hl: "en");
Console.WriteLine(response.Results[0].Title);
```

*PHP:*
```php
use GeethuDino\Ytapis\Ytapis;

$response = Ytapis::search("javascript tutorial", limit: 10, gl: "US", hl: "en");
echo $response['results'][0]['title'];
```

*Kotlin:*
```kotlin
import ytapis.Ytapis

val response = Ytapis.search("javascript tutorial", limit = 10, gl = "US", hl = "en")
println(response.results[0].title)
```

*Rust:*
```rust
use ytapis;

let response = ytapis::search("javascript tutorial", Some(10), Some("US"), Some("en"))?;
println!("{}", response.results[0].title);
```

*Swift:*
```swift
import Ytapis

let response = try await Ytapis.search("javascript tutorial", limit: 10, gl: "US", hl: "en")
print(response.results[0].title)
```

*C++:*
```cpp
#include <ytapis/ytapis.h>

auto response = ytapis::search("javascript tutorial", 10, "US", "en");
std::cout << response.results[0].title << std::endl;
```

---

### `searchTrending(limit?, gl?, hl?)` → `Promise<SearchResponse>`

Get trending/popular videos from YouTube's trending page.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `limit` | `number` | `20` | Maximum number of results |
| `gl` | `string` | `"US"` | Country code for region-specific trending |
| `hl` | `string` | `"en"` | Language code |

**Returns:** `SearchResponse` with trending videos.

**Examples:**

```ts
const { results } = await searchTrending(15, 'GB', 'en');
results.forEach(v => console.log(`${v.title} — ${v.viewCount}`));
```

```python
from ytapis import search_trending
response = search_trending(limit=15, gl="GB", hl="en")
for v in response.results:
    print(f"{v.title} — {v.viewCount}")
```

---

### `searchChannel(channelId, limit?)` → `Promise<SearchResponse>`

Retrieve videos from a specific YouTube channel.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `channelId` | `string` | *(required)* | YouTube channel ID (e.g. `"UC_x5XG1OV2P6uZZ5FSM9Ttw"`) |
| `limit` | `number` | `20` | Maximum number of videos to return |

**Returns:** `SearchResponse` with the channel's uploaded videos.

**Examples:**

```ts
const channelId = 'UC_x5XG1OV2P6uZZ5FSM9Ttw'; // Google Developers
const { results } = await searchChannel(channelId, 30);
```

```php
$response = Ytapis::searchChannel("UC_x5XG1OV2P6uZZ5FSM9Ttw", limit: 30);
```

---

### `searchPlaylist(playlistId, limit?)` → `Promise<SearchResponse>`

Get videos from a public YouTube playlist.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `playlistId` | `string` | *(required)* | YouTube playlist ID (e.g. `"PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"`) |
| `limit` | `number` | `20` | Maximum number of videos to return |

**Returns:** `SearchResponse` with playlist videos in order.

**Examples:**

```ts
const { results } = await searchPlaylist('PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf', 50);
console.log(`Playlist has ${results.length} videos`);
```

```go
response, _ := ytapis.SearchPlaylist("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", 50)
```

---

### `searchShorts(query, limit?, gl?, hl?)` → `Promise<SearchResponse>`

Search specifically for YouTube Shorts (vertical short-form videos).

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `query` | `string` | *(required)* | Search query |
| `limit` | `number` | `20` | Maximum number of Shorts to return |
| `gl` | `string` | `"US"` | Country code |
| `hl` | `string` | `"en"` | Language code |

**Returns:** `SearchResponse` containing only Shorts results.

**Examples:**

```ts
const { results } = await searchShorts('funny cats', 25);
```

```python
from ytapis import search_shorts
response = search_shorts("funny cats", limit=25)
```

---

### `searchContinue(continuation, limit?, apiKey?, context?, path?)` → `Promise<SearchResponse>`

Fetch the next page of search results using a continuation token obtained from a previous `SearchResponse`.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `continuation` | `string` | *(required)* | Continuation token from previous `SearchResponse.continuation` |
| `limit` | `number` | `20` | Max results for this page |
| `apiKey` | `string \| null` | `null` | InnerTube API key (auto-detected if `null`) |
| `context` | `object \| null` | `null` | InnerTube client context object |
| `path` | `string \| null` | `null` | InnerTube API path override |

**Returns:** `SearchResponse` with the next page of results and a new continuation token.

**Examples:**

```ts
let response = await search('nodejs', 10);
while (response.continuation) {
    response = await searchContinue(response.continuation, 10);
    for (const video of response.results) {
        console.log(video.title);
    }
}
```

```dart
var response = await search('nodejs', limit: 10);
while (response.continuation != null) {
    response = await searchContinue(response.continuation!, limit: 10);
    for (final video in response.results) {
        print(video.title);
    }
}
```

---

### `getVideo(videoId)` → `Promise<VideoResult>`

Get complete metadata for a single YouTube video by its ID.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `videoId` | `string` | *(required)* | 11-character YouTube video ID |

**Returns:** `VideoResult` with full video metadata including title, description, stats, channel info, etc.

**Examples:**

```ts
const video = await getVideo('dQw4w9WgXcQ');
console.log(`"${video.title}" by ${video.author} — ${video.viewCount}`);
console.log(`Duration: ${video.duration} (${video.durationSeconds}s)`);
console.log(`Live: ${video.isLive}, Upcoming: ${video.isUpcoming}`);
```

```rust
let video = ytapis::get_video("dQw4w9WgXcQ")?;
println!("{} by {}", video.title, video.author);
```

```kotlin
val video = Ytapis.getVideo("dQw4w9WgXcQ")
println("${video.title} by ${video.author} — ${video.viewCount}")
```

---

### `getComments(videoId, limit?, sortBy?, continuation?)` → `Promise<{ comments, continuation }>`

Retrieve comment threads for a video. Each top-level comment includes nested replies.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `videoId` | `string` | *(required)* | YouTube video ID |
| `limit` | `number` | `20` | Maximum number of top-level comment threads |
| `sortBy` | `string` | `"top"` | Sort order: `"top"` or `"newest"` |
| `continuation` | `string \| null` | `null` | Token from a previous call for pagination |

**Returns:** Object with `comments` array and optional `continuation` token for loading more.

**Comment object structure:**

| Field | Type | Description |
|-------|------|-------------|
| `author` | `string` | Commenter's display name |
| `avatar` | `string` | Commenter's profile picture URL |
| `text` | `string` | Comment text content |
| `likes` | `number` | Number of likes on the comment |
| `publishedTime` | `string` | Relative time (e.g. `"3 days ago"`) |
| `isOwner` | `boolean` | Whether the commenter is the channel owner |
| `replies` | `object[] \| null` | Array of reply comments (each with `author`, `text`, `likes`, `publishedTime`) |
| `replyCount` | `number` | Total number of replies |

**Examples:**

```ts
const { comments, continuation } = await getComments('dQw4w9WgXcQ', 30, 'top');
for (const c of comments) {
    console.log(`${c.author}: ${c.text}`);
    if (c.replies) {
        for (const r of c.replies) {
            console.log(`  ↳ ${r.author}: ${r.text}`);
        }
    }
}
```

```swift
let response = try await Ytapis.getComments("dQw4w9WgXcQ", limit: 30, sortBy: "top")
for comment in response.comments {
    print("\(comment.author): \(comment.text)")
}
```

---

### `getRelatedVideos(videoId, limit?)` → `Promise<RelatedVideo[]>`

Get related/recommended videos for a given video (the sidebar suggestions on YouTube).

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `videoId` | `string` | *(required)* | YouTube video ID |
| `limit` | `number` | `20` | Maximum number of related videos |

**Returns:** Array of `RelatedVideo` objects (lightweight, without full metadata).

**Examples:**

```ts
const related = await getRelatedVideos('dQw4w9WgXcQ', 10);
console.log(`Found ${related.length} related videos`);
```

```php
$related = Ytapis::getRelatedVideos("dQw4w9WgXcQ", limit: 10);
foreach ($related as $v) {
    echo $v['title'] . PHP_EOL;
}
```

---

### `getChannelMetadata(channelId)` → `Promise<ChannelMetadata>`

Get detailed metadata about a YouTube channel.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `channelId` | `string` | *(required)* | YouTube channel ID |

**Returns:** `ChannelMetadata` with subscriber count, banner, avatar, description, social links, and verification status.

**Examples:**

```ts
const channel = await getChannelMetadata('UC_x5XG1OV2P6uZZ5FSM9Ttw');
console.log(`${channel.name} — ${channel.subscriberCount}`);
console.log(`Verified: ${channel.isVerified}`);
console.log(`Total videos: ${channel.videoCount}`);
```

```python
from ytapis import get_channel_metadata
channel = get_channel_metadata("UC_x5XG1OV2P6uZZ5FSM9Ttw")
print(f"{channel.name} — {channel.subscriberCount}")
```

---

### `getVideoStats(videoId)` → `Promise<VideoStats>`

Get real-time statistics for a video including view count, likes, and live status.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `videoId` | `string` | *(required)* | YouTube video ID |

**Returns:** `VideoStats` with `views`, `likes`, `comments`, `isLive`, and `viewerCount`.

**Examples:**

```ts
const stats = await getVideoStats('dQw4w9WgXcQ');
console.log(`Views: ${stats.views.toLocaleString()}`);
console.log(`Likes: ${stats.likes?.toLocaleString() ?? 'hidden'}`);
if (stats.isLive) console.log(`Watching now: ${stats.viewerCount}`);
```

```kotlin
val stats = Ytapis.getVideoStats("dQw4w9WgXcQ")
println("Views: ${stats.views}, Likes: ${stats.likes ?: "hidden"}")
```

---

### `getLiveStreamInfo(videoId)` → `Promise<LiveStreamInfo>`

Get detailed information about a live stream or upcoming premiere.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `videoId` | `string` | *(required)* | YouTube video ID of the live stream |

**Returns:** `LiveStreamInfo` with viewer count, start timestamps, and stream status.

**Examples:**

```ts
const stream = await getLiveStreamInfo('jfKfPfyJRdk');
if (stream.isLive) {
    console.log(`${stream.viewerCount} watching "${stream.title}"`);
} else if (stream.isUpcoming) {
    const start = new Date(stream.scheduledStartTime! * 1000);
    console.log(`Premieres at ${start.toLocaleString()}`);
}
```

```go
stream, err := ytapis.GetLiveStreamInfo("jfKfPfyJRdk")
if err == nil && stream.IsLive {
    fmt.Printf("%d watching %q\n", stream.ViewerCount, stream.Title)
}
```

---

### `getTranscript(videoId, lang?)` → `Promise<TranscriptEntry[]>`

Retrieve the captions/transcript for a video with timestamps. Works with auto-generated and manual captions.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `videoId` | `string` | *(required)* | YouTube video ID |
| `lang` | `string \| null` | `null` (auto-detect) | Language code for captions (e.g. `"en"`, `"es"`, `"fr"`). If `null`, picks the first available track. |

**Returns:** Array of `TranscriptEntry` objects containing `text`, `start` (seconds), `duration` (seconds), and `offset` (ms).

**Examples:**

```ts
const transcript = await getTranscript('dQw4w9WgXcQ', 'en');
for (const entry of transcript) {
    const mins = Math.floor(entry.start / 60);
    const secs = Math.floor(entry.start % 60).toString().padStart(2, '0');
    console.log(`[${mins}:${secs}] ${entry.text}`);
}
```

```dart
final transcript = await getTranscript('dQw4w9WgXcQ', lang: 'en');
for (final entry in transcript) {
    final ts = Duration(seconds: entry.start.toInt());
    print('[$ts] ${entry.text}');
}
```

---

### `LRUCache(maxSize?, ttlMs?)`

In-memory cache with Least Recently Used eviction and Time-To-Live support. Reduces duplicate YouTube requests.

**Constructor parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `maxSize` | `number` | `100` | Maximum number of cached entries before eviction |
| `ttlMs` | `number` | `300000` (5 min) | Time-to-live in milliseconds. Entries older than this are discarded on access. |

**Methods:**

| Method | Signature | Description |
|--------|-----------|-------------|
| `get` | `(key: string) => any \| undefined` | Retrieve a cached value by key. Returns `undefined` if expired or not found. |
| `set` | `(key: string, value: any) => void` | Store a value in the cache. Evicts LRU entry if at capacity. |
| `clear` | `() => void` | Remove all entries from the cache. |
| `has` | `(key: string) => boolean` | Check if a valid (non-expired) entry exists for the key. |
| `size` | Getter returns `number` | Current number of entries in the cache. |

**Examples:**

```ts
import { LRUCache } from 'ytapis';

const cache = new LRUCache(200, 60000); // 200 entries, 1 min TTL

cache.set('video:dQw4w9WgXcQ', videoData);
const cached = cache.get('video:dQw4w9WgXcQ'); // returns videoData
console.log(`Cache has ${cache.size} entries`);

// After 61 seconds...
const expired = cache.get('video:dQw4w9WgXcQ'); // undefined (TTL expired)
```

```python
from ytapis import LRUCache

cache = LRUCache(max_size=200, ttl_ms=60000)
cache.set("video:dQw4w9WgXcQ", video_data)
cached = cache.get("video:dQw4w9WgXcQ")
print(f"Cache has {cache.size} entries")
cache.clear()
```

---

### `withRetry(fn, maxRetries?, baseDelay?, maxDelay?)` → `Promise<T>`

Wrap a function with exponential backoff retry logic. Useful for handling transient network failures.

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `fn` | `() => Promise<T>` | *(required)* | Async function to execute and potentially retry |
| `maxRetries` | `number` | `3` | Maximum number of retry attempts |
| `baseDelay` | `number` | `1000` | Initial delay in milliseconds before first retry |
| `maxDelay` | `number` | `10000` | Maximum delay cap in milliseconds |

**Behavior:** On failure, the function is retried with delays following exponential backoff: `baseDelay * 2^attempt`, capped at `maxDelay`.

**Returns:** The resolved value of `fn` if it succeeds within `maxRetries` attempts.

**Throws:** The last error if all retries are exhausted.

**Examples:**

```ts
import { withRetry, search } from 'ytapis';

const response = await withRetry(
    () => search('reliable results', 20),
    5,     // max 5 retries
    500,   // start at 500ms delay
    8000   // cap at 8s
);
```

```python
from ytapis import with_retry, search

response = with_retry(
    lambda: search("reliable results", limit=20),
    max_retries=5,
    base_delay=500,
    max_delay=8000
)
```

---

### `createClient(options?)` → `Promise<Client>`

Create a pre-configured client instance with built-in retry logic and an internal cache. All functions are available as methods on the client, sharing a single cache and retry configuration.

**Parameters (options object):**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache` | `boolean \| LRUCache` | `true` | `false` to disable caching, or pass a custom `LRUCache` instance |
| `cacheSize` | `number` | `100` | Cache capacity (only used if `cache: true`) |
| `cacheTtlMs` | `number` | `300000` | Cache TTL in ms (only used if `cache: true`) |
| `maxRetries` | `number` | `3` | Default max retries for all client calls |
| `baseDelay` | `number` | `1000` | Default base delay for retry backoff |
| `maxDelay` | `number` | `10000` | Default max delay for retry backoff |
| `defaultGl` | `string` | `"US"` | Default country code for search functions |
| `defaultHl` | `string` | `"en"` | Default language code for search functions |

**Returns:** A `Client` object with the following methods (all pre-configured with the client's cache and retry settings):

- `client.search(query, limit?)` — `SearchResponse`
- `client.searchTrending(limit?)` — `SearchResponse`
- `client.searchChannel(channelId, limit?)` — `SearchResponse`
- `client.searchPlaylist(playlistId, limit?)` — `SearchResponse`
- `client.searchShorts(query, limit?)` — `SearchResponse`
- `client.searchContinue(continuation, limit?)` — `SearchResponse`
- `client.getVideo(videoId)` — `VideoResult`
- `client.getComments(videoId, limit?, sortBy?, continuation?)` — `{ comments, continuation }`
- `client.getRelatedVideos(videoId, limit?)` — `RelatedVideo[]`
- `client.getChannelMetadata(channelId)` — `ChannelMetadata`
- `client.getVideoStats(videoId)` — `VideoStats`
- `client.getLiveStreamInfo(videoId)` — `LiveStreamInfo`
- `client.getTranscript(videoId, lang?)` — `TranscriptEntry[]`
- `client.cache.clear()` — Clear the client's cache
- `client.cache.size` — Current cache entry count

**Examples:**

```ts
import { createClient } from 'ytapis';

const yt = await createClient({
    cache: true,
    cacheSize: 500,
    cacheTtlMs: 600000,    // 10 minutes
    maxRetries: 5,
    baseDelay: 200,
    defaultGl: 'IN',
    defaultHl: 'hi'
});

// All calls share cache and retry config
const video = await yt.getVideo('dQw4w9WgXcQ');
const { results } = await yt.search('tutorial');
const stats = await yt.getVideoStats('dQw4w9WgXcQ'); // cached
```

```python
from ytapis import create_client

yt = create_client(
    cache=True,
    cache_size=500,
    cache_ttl_ms=600000,
    max_retries=5,
    default_gl="IN",
    default_hl="hi"
)

video = yt.get_video("dQw4w9WgXcQ")
results = yt.search("tutorial")
```

---

## Multi-Language Quick Start

### TypeScript / JavaScript

```ts
// npm install ytapis
import { search, getVideo, createClient } from 'ytapis';

// Single function call
const { results } = await search('nodejs crash course', 5);
console.log(results[0].title);

// Or use a client with cache + retry
const yt = await createClient({ cache: true });
const video = await yt.getVideo('dQw4w9WgXcQ');
console.log(`"${video.title}" — ${video.duration}`);
```

### Python

```python
# pip install ytapis
from ytapis import search, get_video, create_client

response = search("python tutorial", limit=5)
print(response.results[0].title)

yt = create_client(cache=True)
video = yt.get_video("dQw4w9WgXcQ")
print(f'"{video.title}" — {video.duration}')
```

### Go

```go
// go get github.com/pgboyahpgr-commits/ytapis/go
import (
    "fmt"
    "github.com/pgboyahpgr-commits/ytapis/go"
)

func main() {
    resp, _ := ytapis.Search("golang tutorial", 5, "US", "en")
    for _, v := range resp.Results {
        fmt.Println(v.Title)
    }

    video, _ := ytapis.GetVideo("dQw4w9WgXcQ")
    fmt.Printf("\"%s\" — %s\n", video.Title, video.Duration)
}
```

### Dart

```dart
// dart pub add ytapis
import 'package:ytapis/ytapis.dart';

void main() async {
    final response = await search('flutter tutorial', limit: 5);
    print(response.results.first.title);

    final video = await getVideo('dQw4w9WgXcQ');
    print('"${video.title}" — ${video.duration}');
}
```

### C&#35;

```csharp
// dotnet add package ytapis
using Ytapis;

var results = await YtapisClient.SearchAsync("dotnet tutorial", limit: 5);
Console.WriteLine(results.Results[0].Title);

var video = await YtapisClient.GetVideoAsync("dQw4w9WgXcQ");
Console.WriteLine($"\"{video.Title}\" — {video.Duration}");
```

### PHP

```php
// composer require geethudinoyt/ytapis
use GeethuDino\Ytapis\Ytapis;

$response = Ytapis::search("php tutorial", limit: 5);
echo $response['results'][0]['title'] . PHP_EOL;

$video = Ytapis::getVideo("dQw4w9WgXcQ");
echo '"' . $video['title'] . '" — ' . $video['duration'] . PHP_EOL;
```

### Kotlin

```kotlin
// Add to build.gradle.kts:
//   implementation("ytapis:ytapis:2.0.0")
import ytapis.Ytapis

fun main() {
    val response = Ytapis.search("kotlin tutorial", limit = 5)
    println(response.results[0].title)

    val video = Ytapis.getVideo("dQw4w9WgXcQ")
    println("\"${video.title}\" — ${video.duration}")
}
```

### Rust

```rust
// Cargo.toml: ytapis = "1.0"
use ytapis;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resp = ytapis::search("rust tutorial", Some(5), None, None)?;
    println!("{}", resp.results[0].title);

    let video = ytapis::get_video("dQw4w9WgXcQ")?;
    println!("\"{}\" — {}", video.title, video.duration);
    Ok(())
}
```

### Swift

```swift
// Package.swift: .package(url: "https://github.com/pgboyahpgr-commits/ytapis", ...)
import Ytapis

let response = try await Ytapis.search("swift tutorial", limit: 5, gl: "US", hl: "en")
print(response.results[0].title)

let video = try await Ytapis.getVideo("dQw4w9WgXcQ")
print("\"\(video.title)\" — \(video.duration)")
```

### C++

```cpp
// CMake: find_package(ytapis REQUIRED)
#include <ytapis/ytapis.h>
#include <iostream>

int main() {
    auto response = ytapis::search("c++ tutorial", 5, "US", "en");
    std::cout << response.results[0].title << std::endl;

    auto video = ytapis::get_video("dQw4w9WgXcQ");
    std::cout << '"' << video.title << '"' << " — " << video.duration << std::endl;
    return 0;
}
```

---

## Errors

All functions throw/reject on network errors (DNS failure, connection refused, timeout). When YouTube's servers block or return incomplete data, functions return fallback/default values rather than throwing:

- Search functions return empty `results` with `continuation: null`
- `getVideo` returns a `VideoResult` with empty strings for missing fields
- `getComments` returns an empty `comments` array
- `getRelatedVideos` returns an empty array
- Stats/stream functions return `null` for unavailable numeric fields

Errors from `withRetry` surface the error from the last failed attempt after all retries are exhausted.

### Common error scenarios

| Scenario | Behavior |
|----------|----------|
| No internet connection | `withRetry` exhausts retries → throws |
| YouTube rate limit (429 / CAPTCHA) | Returns fallback/empty data |
| Invalid video ID | Returns fallback `VideoResult` with empty fields |
| Private/deleted video | Returns fallback with partial data if available via oEmbed |
| Invalid channel/playlist ID | Returns empty search response |

---

## Rate Limiting

No official rate limit is documented for the internal YouTube APIs used by ytapis. However, aggressive usage may trigger CAPTCHAs, IP blocks, or temporary 429 responses.

**Recommendations:**

- Use the built-in `LRUCache` to avoid duplicate requests for the same video ID, channel, or query
- Use `createClient()` which shares a single cache across all calls
- Add artificial delays between rapid requests (e.g. 200-500ms)
- For bulk operations, spread requests over time rather than firing concurrently
- The `withRetry` wrapper naturally adds backoff between retries on failure

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 2.0.0 | 2025-08 | Rewrite with InnerTube continuation, oEmbed fallback, multi-language SDKs, LRU cache, retry logic |
| 1.0.0 | 2024-06 | Initial release — YouTube search and basic metadata extraction |
