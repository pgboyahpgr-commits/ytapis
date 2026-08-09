# ytapis-swift

YouTube search engine for Swift 5.9+. Zero dependencies (Foundation only).

## Installation

**Package.swift**
```swift
.package(path: "../ytapis/swift")
```

Or add to your target dependencies:
```swift
.product(name: "Ytapis", package: "swift")
```

## Usage

```swift
import Ytapis

// Search
let response = try await Ytapis.search(query: "swift tutorial", limit: 10)
for video in response.results {
    print("\(video.title) by \(video.author) [\(video.duration)]")
    print("  \(video.viewCount)  \(video.publishedTime)")
    print("  \(video.description.prefix(120))")
}

// Get single video by ID
let video = try await Ytapis.getVideo(id: "dQw4w9WgXcQ")
print(video.title)

// Pagination with continuation
if let token = response.continuation {
    let more = try await Ytapis.searchContinue(
        continuation: token,
        apiKey: response.apiKey
    )
    for v in more.results {
        print(v.title)
    }
}

// Utility parsers
let dur = Ytapis.parseDuration("12:34")          // ("12:34", 754)
let views = Ytapis.parseViewCount("1.2M views")  // 1200000
```

## API

### `Ytapis.search(query:limit:) -> SearchResponse`
Scrapes youtube.com/results, parses `ytInitialData` JSON, and returns rich metadata.

### `Ytapis.getVideo(id:) -> VideoResult`
Gets metadata for a single video via `ytInitialPlayerResponse`, falling back to oEmbed.

### `Ytapis.searchContinue(continuation:limit:apiKey:context:) -> SearchResponse`
Continues a paginated search via the InnerTube API.

### `Ytapis.parseDuration(_:) -> (String, Int)`
Parses a duration string like `"12:34"` into `("12:34", 754)`.

### `Ytapis.parseViewCount(_:) -> Int`
Parses a view count string like `"1.2M views"` into `1200000`.

## VideoResult Fields

| Field | Type | Description |
|-------|------|-------------|
| id | String | Video ID (11 chars) |
| title | String | Video title |
| author | String | Channel name |
| channelUrl | String | Channel URL |
| thumbnail | String | Best thumbnail URL |
| thumbnails | [Thumbnail] | All thumbnail variants |
| fullUrl | String | youtube.com/watch?v= URL |
| embedUrl | String | youtube.com/embed/ URL |
| duration | String | Formatted e.g. `"12:34"` |
| durationSeconds | Int | Duration in seconds |
| viewCount | String | Formatted e.g. `"1.2M views"` |
| viewCountRaw | Int | Raw view count |
| publishedTime | String | e.g. `"2 days ago"` |
| description | String | Video description snippet |
| channelAvatar | String | Channel avatar URL |
| isLive | Bool | Currently live |
| isUpcoming | Bool | Upcoming premiere |
| isVerified | Bool | Verified channel badge |

## Thumbnail

```swift
struct Thumbnail {
    let url: String
    let width: Int
    let height: Int
}
```

## SearchResponse

```swift
struct SearchResponse {
    let results: [VideoResult]
    let continuation: String?
    let apiKey: String?
}
```
