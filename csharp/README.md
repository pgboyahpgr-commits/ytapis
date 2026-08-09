# ytapis

YouTube search engine library for .NET 8. Zero external dependencies.

## Installation

```bash
dotnet add package ytapis
```

## Usage

```csharp
using Ytapis;

// Search YouTube
var results = Ytapis.Search("csharp tutorial", limit: 10);
foreach (var v in results)
    Console.WriteLine($"{v.Title} - {v.Duration} - {v.ViewCount}");

// Get single video metadata
var video = Ytapis.GetVideo("dQw4w9WgXcQ");
Console.WriteLine(video?.Title);

// Paginated search with continuation
var initial = Ytapis.Search("music", limit: 5);
// Use the continuation token from initial results
// (extracted internally; use SearchContinue directly)
var (more, nextToken, apiKey) = Ytapis.SearchContinue(
    continuation: "EP4...",
    limit: 5
);
```

## API

### `List<VideoResult> Search(string query, int limit = 15)`

Searches YouTube and returns parsed video results.

### `VideoResult? GetVideo(string id)`

Fetches metadata for a single video by ID. Falls back to oEmbed API.

### `(List<VideoResult>, string?, string?) SearchContinue(string continuation, int limit = 15, string? apiKey = null, string? context = null)`

Continues a paginated search using InnerTube API continuation tokens.

## `VideoResult` fields

| Field | Type | Description |
|-------|------|-------------|
| Id | string | YouTube video ID |
| Title | string | Video title |
| Author | string | Channel name |
| ChannelUrl | string | Full channel URL |
| Thumbnail | string | Best available thumbnail URL |
| Thumbnails | List\<ThumbnailInfo\> | All thumbnail resolutions |
| FullUrl | string | Video watch URL |
| EmbedUrl | string | Embeddable URL |
| Duration | string | Formatted (e.g. "12:34") |
| DurationSeconds | int | Duration in seconds |
| ViewCount | string | Formatted (e.g. "1.2M views") |
| ViewCountRaw | long | Raw view count |
| PublishedTime | string | Relative time (e.g. "3 days ago") |
| Description | string | Video description snippet |
| ChannelAvatar | string | Channel avatar URL |
| IsLive | bool | Currently live |
| IsUpcoming | bool | Scheduled premiere |
| IsVerified | bool | Verified channel badge |
