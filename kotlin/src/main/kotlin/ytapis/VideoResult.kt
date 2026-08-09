package ytapis

data class Thumbnail(val url: String, val width: Int, val height: Int)

data class VideoResult(
    val id: String,
    val title: String,
    val author: String,
    val channelUrl: String,
    val thumbnail: String,
    val thumbnails: List<Thumbnail>,
    val fullUrl: String,
    val embedUrl: String,
    val duration: String,
    val durationSeconds: Int,
    val viewCount: String,
    val viewCountRaw: Long,
    val publishedTime: String,
    val description: String,
    val channelAvatar: String,
    val isLive: Boolean,
    val isUpcoming: Boolean,
    val isVerified: Boolean
)

data class SearchResponse(
    val results: List<VideoResult>,
    val continuation: String?,
    val apiKey: String?
)
