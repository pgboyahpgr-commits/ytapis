# ytapis-kotlin

YouTube search engine for Kotlin/JVM.

## Installation

**build.gradle.kts**
```kotlin
repositories {
    mavenCentral()
}
dependencies {
    implementation("org.json:json:20240303")
}
```

Copy `VideoResult.kt` and `Ytapis.kt` into your project.

## Usage

```kotlin
import ytapis.Ytapis

// Search
val results = Ytapis.search("kotlin tutorial", limit = 10)
for (video in results) {
    println("${video.title} by ${video.author} [${video.duration}]")
    println("  ${video.viewCount}  ${video.publishedTime}")
    println("  ${video.description.take(120)}")
}

// Get single video by ID
val video = Ytapis.getVideo("dQw4w9WgXcQ")
println(video.title)

// Pagination with continuation
val more = Ytapis.searchContinue(continuationToken, apiKey = "AIza...")
for (v in more.results) {
    println(v.title)
}
```

## API

### `Ytapis.search(query: String, limit: Int = 15): List<VideoResult>`
Scrapes youtube.com/results and returns rich metadata for each video.

### `Ytapis.getVideo(id: String): VideoResult`
Gets metadata for a single video by ID via ytInitialPlayerResponse, falling back to oEmbed.

### `Ytapis.searchContinue(continuation: String, limit: Int = 15, apiKey: String? = null, context: String? = null): SearchResponse`
Continues a paginated search via the InnerTube API.

## VideoResult Fields

| Field | Type | Description |
|-------|------|-------------|
| id | String | Video ID (11 chars) |
| title | String | Video title |
| author | String | Channel name |
| channelUrl | String | Channel URL path |
| thumbnail | String | Best thumbnail URL |
| thumbnails | List\<Thumbnail\> | All thumbnail variants |
| fullUrl | String | youtube.com/watch?v= URL |
| embedUrl | String | youtube.com/embed/ URL |
| duration | String | Formatted e.g. `"12:34"` |
| durationSeconds | Int | Duration in seconds |
| viewCount | String | Formatted e.g. `"1.2M views"` |
| viewCountRaw | Long | Raw view count |
| publishedTime | String | e.g. `"2 days ago"` |
| description | String | Video description snippet |
| channelAvatar | String | Channel avatar URL |
| isLive | Boolean | Currently live |
| isUpcoming | Boolean | Upcoming premiere |
| isVerified | Boolean | Verified channel badge |

## Thumbnail

```kotlin
data class Thumbnail(val url: String, val width: Int, val height: Int)
```

## SearchResponse

```kotlin
data class SearchResponse(
    val results: List<VideoResult>,
    val continuation: String?,
    val apiKey: String?
)
```
