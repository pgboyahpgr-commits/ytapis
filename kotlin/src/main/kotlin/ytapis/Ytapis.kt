package ytapis

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

object Ytapis {
    private const val SEARCH_URL = "https://www.youtube.com/results?search_query="
    private const val INNERTUBE_URL = "https://www.youtube.com/youtubei/v1/search"
    private const val OEMBED_URL = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch="
    private const val DEFAULT_API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    private const val DEFAULT_CONTEXT =
        """{"client":{"hl":"en","gl":"US","clientName":"WEB","clientVersion":"2.20240801.00.00"}}"""
    private const val TIMEOUT_MS = 15000

    private fun httpGet(url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = TIMEOUT_MS
        conn.readTimeout = TIMEOUT_MS
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (compatible; ytapis/1.0)")
        conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9")
        return try {
            val code = conn.responseCode
            if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                val err = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                throw RuntimeException("HTTP $code: $err")
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun httpPost(url: String, body: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = TIMEOUT_MS
        conn.readTimeout = TIMEOUT_MS
        conn.requestMethod = "POST"
        conn.setRequestProperty("Content-Type", "application/json")
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (compatible; ytapis/1.0)")
        conn.setRequestProperty("Accept-Language", "en-US,en;q=0.9")
        conn.doOutput = true
        return try {
            conn.outputStream.bufferedWriter().use { it.write(body) }
            val code = conn.responseCode
            if (code in 200..299) {
                conn.inputStream.bufferedReader().use { it.readText() }
            } else {
                val err = conn.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                throw RuntimeException("HTTP $code: $err")
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun extractJson(html: String, prefix: String): JSONObject? {
        val idx = html.indexOf(prefix)
        if (idx == -1) return null
        val start = html.indexOf('{', idx)
        if (start == -1) return null
        var depth = 0
        var inString = false
        var escaped = false
        for (i in start until html.length) {
            val ch = html[i]
            if (escaped) {
                escaped = false
                continue
            }
            if (ch == '\\') {
                escaped = true
                continue
            }
            if (ch == '"') {
                inString = !inString
                continue
            }
            if (inString) continue
            if (ch == '{') depth++
            if (ch == '}') {
                depth--
                if (depth == 0) {
                    return try {
                        JSONObject(html.substring(start, i + 1))
                    } catch (_: Exception) {
                        null
                    }
                }
            }
        }
        return null
    }

    private fun extractRuns(runs: Any?): String {
        if (runs !is JSONArray) return ""
        val sb = StringBuilder()
        for (i in 0 until runs.length()) {
            sb.append(runs.optJSONObject(i)?.optString("text", "") ?: "")
        }
        return sb.toString()
    }

    private fun extractThumbnails(thumbs: Any?): List<Thumbnail> {
        if (thumbs !is JSONArray) return emptyList()
        val result = mutableListOf<Thumbnail>()
        for (i in 0 until thumbs.length()) {
            val t = thumbs.optJSONObject(i) ?: continue
            result.add(
                Thumbnail(
                    url = t.optString("url", ""),
                    width = t.optInt("width", 0),
                    height = t.optInt("height", 0)
                )
            )
        }
        return result
    }

    private fun thumbnailQualityScore(url: String): Int {
        if (url.isEmpty()) return 0
        return when {
            "maxresdefault" in url -> 1280
            "sddefault" in url -> 640
            "hqdefault" in url -> 480
            "mqdefault" in url -> 320
            "default" in url -> 120
            else -> 0
        }
    }

    private fun extractBestThumbnail(thumbnails: List<Thumbnail>): String {
        if (thumbnails.isEmpty()) return ""
        var best = thumbnails[0]
        var bestScore = thumbnailQualityScore(best.url)
        for (t in thumbnails) {
            val score = if (t.width > 0) t.width else thumbnailQualityScore(t.url)
            if (score > bestScore) {
                best = t
                bestScore = score
            }
        }
        return best.url
    }

    private fun fallbackResult(id: String): VideoResult {
        val thumb = "https://i.ytimg.com/vi/$id/hqdefault.jpg"
        return VideoResult(
            id = id,
            title = "Video $id",
            author = "YouTube",
            channelUrl = "",
            thumbnail = thumb,
            thumbnails = listOf(Thumbnail(thumb, 480, 360)),
            fullUrl = "https://www.youtube.com/watch?v=$id",
            embedUrl = "https://www.youtube.com/embed/$id?rel=0",
            duration = "",
            durationSeconds = 0,
            viewCount = "",
            viewCountRaw = 0,
            publishedTime = "",
            description = "",
            channelAvatar = "",
            isLive = false,
            isUpcoming = false,
            isVerified = false
        )
    }

    fun parseDuration(text: String): Pair<String, Int> {
        if (text.isEmpty()) return Pair("", 0)
        val parts = text.split(":").map { it.toIntOrNull() ?: 0 }
        return when (parts.size) {
            3 -> Pair(text, parts[0] * 3600 + parts[1] * 60 + parts[2])
            2 -> Pair(text, parts[0] * 60 + parts[1])
            else -> Pair(text, text.toIntOrNull() ?: 0)
        }
    }

    fun parseViewCount(text: String): Pair<String, Long> {
        if (text.isEmpty()) return Pair("", 0)
        val cleaned = text.replace(Regex("[^0-9.KMBkmb]"), "")
        if (cleaned.isEmpty()) return Pair(text, 0)
        val num = cleaned.replace(Regex("[KMBkmb]"), "").toDoubleOrNull() ?: 0.0
        val multiplier = when {
            cleaned.contains('B') || cleaned.contains('b') -> 1_000_000_000L
            cleaned.contains('M') || cleaned.contains('m') -> 1_000_000L
            cleaned.contains('K') || cleaned.contains('k') -> 1_000L
            else -> 1L
        }
        return Pair(text, Math.round(num * multiplier))
    }

    private fun parseVideoRenderer(vr: JSONObject): VideoResult? {
        try {
            val id = vr.optString("videoId", "")
            if (id.isEmpty()) return null

            val title = extractRuns(vr.optJSONObject("title")?.optJSONArray("runs"))
            val author = extractRuns(vr.optJSONObject("ownerText")?.optJSONArray("runs"))
            val channelUrl = vr.optJSONObject("ownerText")
                ?.optJSONArray("runs")
                ?.optJSONObject(0)
                ?.optJSONObject("navigationEndpoint")
                ?.optJSONObject("browseEndpoint")
                ?.optString("canonicalBaseUrl", "") ?: ""

            val thumbnails = extractThumbnails(
                vr.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
            )
            val thumbnail = extractBestThumbnail(thumbnails)

            val lengthText = vr.optJSONObject("lengthText")
            val durText = lengthText?.optString("simpleText", "")
                ?: extractRuns(lengthText?.optJSONArray("runs"))
            val (duration, durationSeconds) = parseDuration(durText)

            val viewCountObj = vr.optJSONObject("viewCountText")
            val vcText = viewCountObj?.optString("simpleText", "")
                ?: extractRuns(viewCountObj?.optJSONArray("runs"))
            val (viewCount, viewCountRaw) = parseViewCount(vcText)

            val publishedTime = vr.optJSONObject("publishedTimeText")
                ?.optString("simpleText", "") ?: ""

            val descRuns = vr.optJSONArray("detailedMetadataSnippets")
                ?.optJSONObject(0)
                ?.optJSONObject("snippetText")
                ?.optJSONArray("runs")
                ?: vr.optJSONObject("descriptionSnippet")?.optJSONArray("runs")
            val description = extractRuns(descRuns)

            val channelThumbs = vr.optJSONObject("channelThumbnailSupportedRenderers")
                ?.optJSONObject("channelThumbnailWithLinkRenderer")
                ?.optJSONObject("thumbnail")
                ?.optJSONArray("thumbnails")
            val channelAvatar = extractBestThumbnail(extractThumbnails(channelThumbs))

            val badges = vr.optJSONArray("badges")?.let { arr ->
                (0 until arr.length()).map { i ->
                    val badge = arr.optJSONObject(i)?.optJSONObject("metadataBadgeRenderer")
                    badge?.optString("style", "") ?: badge?.optString("label", "") ?: ""
                }
            } ?: emptyList()

            val fallback = fallbackResult(id)

            return VideoResult(
                id = id,
                title = title.ifEmpty { fallback.title },
                author = author.ifEmpty { fallback.author },
                channelUrl = channelUrl,
                thumbnail = thumbnail.ifEmpty { fallback.thumbnail },
                thumbnails = thumbnails.ifEmpty { fallback.thumbnails },
                fullUrl = "https://www.youtube.com/watch?v=$id",
                embedUrl = "https://www.youtube.com/embed/$id?rel=0",
                duration = duration,
                durationSeconds = durationSeconds,
                viewCount = viewCount,
                viewCountRaw = viewCountRaw,
                publishedTime = publishedTime,
                description = description,
                channelAvatar = channelAvatar,
                isLive = badges.any { it.contains("LIVE") },
                isUpcoming = badges.any { it.contains("UPCOMING") },
                isVerified = badges.any { it.contains("VERIFIED") }
            )
        } catch (_: Exception) {
            return null
        }
    }

    private fun parseSearchResults(
        data: JSONObject,
        limit: Int
    ): Pair<List<VideoResult>, String?> {
        val results = mutableListOf<VideoResult>()
        var continuation: String? = null

        try {
            val contents = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnSearchResultsRenderer")
                ?.optJSONObject("primaryContents")
                ?.optJSONObject("sectionListRenderer")
                ?.optJSONArray("contents") ?: return Pair(results, continuation)

            for (si in 0 until contents.length()) {
                if (results.size >= limit) break
                val section = contents.optJSONObject(si) ?: continue

                val itemContents =
                    section.optJSONObject("itemSectionRenderer")?.optJSONArray("contents")
                if (itemContents != null) {
                    for (ii in 0 until itemContents.length()) {
                        if (results.size >= limit) break
                        val item = itemContents.optJSONObject(ii) ?: continue
                        val vr = item.optJSONObject("videoRenderer")
                        if (vr != null) {
                            val parsed = parseVideoRenderer(vr)
                            if (parsed != null) results.add(parsed)
                        }
                    }
                }

                val token = section.optJSONObject("continuationItemRenderer")
                    ?.optJSONObject("continuationEndpoint")
                    ?.optJSONObject("continuationCommand")
                    ?.optString("token")
                if (!token.isNullOrEmpty()) {
                    continuation = token
                }
            }
        } catch (_: Exception) {
        }

        return Pair(results, continuation)
    }

    private fun parseContinuationResults(
        data: JSONObject,
        limit: Int,
        path: String = "search"
    ): Pair<List<VideoResult>, String?> {
        val results = mutableListOf<VideoResult>()
        var continuation: String? = null

        try {
            val items: JSONArray? = when (path) {
                "channel" -> {
                    var arr = data.optJSONArray("onResponseReceivedActions")
                        ?.optJSONObject(0)
                        ?.optJSONObject("appendContinuationItemsAction")
                        ?.optJSONArray("continuationItems")
                    if (arr == null) {
                        arr = data.optJSONArray("onResponseReceivedEndpoints")
                            ?.optJSONObject(0)
                            ?.optJSONObject("appendContinuationItemsAction")
                            ?.optJSONArray("continuationItems")
                    }
                    arr
                }
                "playlist" -> data.optJSONArray("onResponseReceivedActions")
                    ?.optJSONObject(0)
                    ?.optJSONObject("appendContinuationItemsAction")
                    ?.optJSONArray("continuationItems")
                else -> data.optJSONArray("onResponseReceivedEndpoints")
                    ?.optJSONObject(0)
                    ?.optJSONObject("appendContinuationItemsAction")
                    ?.optJSONArray("continuationItems")
            } ?: return Pair(results, continuation)

            for (i in 0 until items!!.length()) {
                if (results.size >= limit) break
                val item = items!!.optJSONObject(i) ?: continue

                val token = item.optJSONObject("continuationItemRenderer")
                    ?.optJSONObject("continuationEndpoint")
                    ?.optJSONObject("continuationCommand")
                    ?.optString("token")
                if (!token.isNullOrEmpty()) {
                    continuation = token
                }

                if (path == "playlist") {
                    val pvr = item.optJSONObject("playlistVideoRenderer")
                    if (pvr != null) {
                        val vid = pvr.optString("videoId", "")
                        if (vid.isNotEmpty()) {
                            val title = extractRuns(pvr.optJSONObject("title")?.optJSONArray("runs"))
                            val author = extractRuns(pvr.optJSONObject("shortBylineText")?.optJSONArray("runs"))
                            val durText = pvr.optJSONObject("lengthText")?.optString("simpleText", "")
                                ?: extractRuns(pvr.optJSONObject("lengthText")?.optJSONArray("runs"))
                            val (duration, durationSeconds) = parseDuration(durText)
                            val fb = fallbackResult(vid)
                            results.add(fb.copy(
                                title = title.ifEmpty { fb.title },
                                author = author.ifEmpty { fb.author },
                                duration = duration,
                                durationSeconds = durationSeconds
                            ))
                        }
                        continue
                    }
                }

                var vr = item.optJSONObject("videoRenderer")
                if (vr == null) {
                    vr = item.optJSONObject("richItemRenderer")
                        ?.optJSONObject("content")
                        ?.optJSONObject("videoRenderer")
                }
                if (vr != null) {
                    val parsed = parseVideoRenderer(vr)
                    if (parsed != null) results.add(parsed)
                }
            }
        } catch (_: Exception) {
        }

        return Pair(results, continuation)
    }

    private fun fetchOembed(id: String): Triple<String, String, String> {
        return try {
            val json = JSONObject(httpGet("${OEMBED_URL}${id}&format=json"))
            Triple(
                json.optString("title", ""),
                json.optString("author_name", ""),
                json.optString("thumbnail_url", "")
            )
        } catch (_: Exception) {
            Triple("", "", "")
        }
    }
    fun getVideo(id: String): VideoResult {
        val fallback = fallbackResult(id)

        try {
            val html = httpGet("https://www.youtube.com/watch?v=$id")

            val data = extractJson(html, "var ytInitialPlayerResponse")
                ?: extractJson(html, "var ytInitialData")

            if (data != null) {
                val vd = data.optJSONObject("videoDetails")
                if (vd != null) {
                    val durSec = vd.optInt("lengthSeconds", 0)
                    val mins = durSec / 60
                    val secs = durSec % 60
                    val durStr = if (durSec > 3600) {
                        val hrs = durSec / 3600
                        "$hrs:${(mins % 60).toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}"
                    } else {
                        "$mins:${secs.toString().padStart(2, '0')}"
                    }

                    val thumbs = extractThumbnails(
                        vd.optJSONObject("thumbnail")?.optJSONArray("thumbnails")
                    )

                    val rawViews = vd.optLong("viewCount", 0)

                    return fallback.copy(
                        title = vd.optString("title", fallback.title),
                        author = vd.optString("author", fallback.author),
                        channelUrl = "https://www.youtube.com/${vd.optString("channelId", "")}",
                        thumbnail = extractBestThumbnail(thumbs).ifEmpty { fallback.thumbnail },
                        thumbnails = thumbs.ifEmpty { fallback.thumbnails },
                        duration = durStr,
                        durationSeconds = durSec,
                        viewCount = if (rawViews > 0) "%,d views".format(rawViews) else "",
                        viewCountRaw = rawViews,
                        description = vd.optString("shortDescription", ""),
                        channelAvatar = vd.optJSONArray("authorThumbnails")
                            ?.optJSONObject(0)
                            ?.optString("url", "") ?: ""
                    )
                }
            }

            val (title, author, thumbnail) = fetchOembed(id)
            return fallback.copy(
                title = title.ifEmpty { fallback.title },
                author = author.ifEmpty { fallback.author },
                thumbnail = thumbnail.ifEmpty { fallback.thumbnail },
                thumbnails = if (thumbnail.isNotEmpty() && thumbnail != fallback.thumbnail)
                    listOf(Thumbnail(thumbnail, 480, 360)) else fallback.thumbnails
            )
        } catch (_: Exception) {
            return fallback
        }
    }
    fun search(query: String, limit: Int = 15): List<VideoResult> {
        val capped = limit.coerceIn(1, 50)

        try {
            val url = SEARCH_URL + URLEncoder.encode(query, "UTF-8")
            val html = httpGet(url)
            val data = extractJson(html, "var ytInitialData") ?: return emptyList()

            val (rawResults, _) = parseSearchResults(data, capped)

            val needsEnrichment = rawResults.filter {
                it.title.isEmpty() || it.title == "Video ${it.id}" || it.author == "YouTube"
            }

            if (needsEnrichment.isEmpty()) return rawResults

            val enrichedData = needsEnrichment.associate { it.id to fetchOembed(it.id) }

            return rawResults.map { r ->
                val enrich = enrichedData[r.id]
                if (enrich != null) {
                    val (title, author, thumbnail) = enrich
                    r.copy(
                        title = title.ifEmpty { r.title },
                        author = author.ifEmpty { r.author },
                        thumbnail = if (thumbnail.isNotEmpty() && thumbnail != r.thumbnail)
                            thumbnail else r.thumbnail
                    )
                } else {
                    r
                }
            }
        } catch (_: Exception) {
            return emptyList()
        }
    }
    fun searchContinue(
        continuation: String,
        limit: Int = 15,
        apiKey: String? = null,
        context: String? = null,
        path: String = "search"
    ): SearchResponse {
        val capped = limit.coerceIn(1, 50)
        val key = apiKey ?: DEFAULT_API_KEY

        val contextObj = if (context != null) {
            try {
                JSONObject(context)
            } catch (_: Exception) {
                JSONObject(DEFAULT_CONTEXT)
            }
        } else {
            JSONObject(DEFAULT_CONTEXT)
        }

        val body = JSONObject().apply {
            put("context", contextObj)
            put("continuation", continuation)
        }

        try {
            val responseText = httpPost("$INNERTUBE_URL?key=$key", body.toString())
            val data = JSONObject(responseText)
            val (rawResults, nextContinuation) = parseContinuationResults(data, capped, path)

            val needsEnrichment = rawResults.filter {
                it.title.isEmpty() || it.title == "Video ${it.id}" || it.author == "YouTube"
            }

            val results = if (needsEnrichment.isEmpty()) {
                rawResults
            } else {
                val enrichedData = needsEnrichment.associate { it.id to fetchOembed(it.id) }
                rawResults.map { r ->
                    val enrich = enrichedData[r.id]
                    if (enrich != null) {
                        val (title, author, thumbnail) = enrich
                        r.copy(
                            title = title.ifEmpty { r.title },
                            author = author.ifEmpty { r.author },
                            thumbnail = if (thumbnail.isNotEmpty() && thumbnail != r.thumbnail)
                                thumbnail else r.thumbnail
                        )
                    } else {
                        r
                    }
                }
            }

            return SearchResponse(results, nextContinuation, apiKey)
        } catch (_: Exception) {
            return SearchResponse(emptyList(), null, null)
        }
    }

    // ─── Trending / Channel / Playlist parsers ─────────────────────────────────

    private fun parseTrendingResults(
        data: JSONObject,
        limit: Int
    ): Pair<List<VideoResult>, String?> {
        val results = mutableListOf<VideoResult>()
        var continuation: String? = null

        try {
            val tabs = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnBrowseResultsRenderer")
                ?.optJSONArray("tabs") ?: return Pair(results, continuation)

            for (ti in 0 until tabs.length()) {
                val tab = tabs.optJSONObject(ti) ?: continue
                val contents = tab.optJSONObject("tabRenderer")
                    ?.optJSONObject("content")
                    ?.optJSONObject("sectionListRenderer")
                    ?.optJSONArray("contents") ?: continue

                for (si in 0 until contents.length()) {
                    if (results.size >= limit) break
                    val section = contents.optJSONObject(si) ?: continue

                    val itemContents = section.optJSONObject("itemSectionRenderer")
                        ?.optJSONArray("contents")
                    if (itemContents != null) {
                        for (ii in 0 until itemContents.length()) {
                            if (results.size >= limit) break
                            val item = itemContents.optJSONObject(ii) ?: continue
                            val vr = item.optJSONObject("videoRenderer")
                            if (vr != null) {
                                val parsed = parseVideoRenderer(vr)
                                if (parsed != null) results.add(parsed)
                            }
                        }
                    }

                    val shelfRenderer = section.optJSONObject("shelfRenderer")
                    if (shelfRenderer != null) {
                        val shelfContent = shelfRenderer.optJSONObject("content")
                        val shelfItems = shelfContent?.optJSONObject("expandedShelfContentsRenderer")?.optJSONArray("items")
                            ?: shelfContent?.optJSONObject("horizontalListRenderer")?.optJSONArray("items")
                        if (shelfItems != null) {
                            for (ii in 0 until shelfItems!!.length()) {
                                if (results.size >= limit) break
                                val item = shelfItems.optJSONObject(ii) ?: continue
                                val vr = item.optJSONObject("videoRenderer")
                                if (vr != null) {
                                    val parsed = parseVideoRenderer(vr)
                                    if (parsed != null) results.add(parsed)
                                }
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) { /* ignore */ }
        return Pair(results, continuation)
    }

    // ─── New Types ──────────────────────────────────────────────────────────

    data class CommentAuthor(
        val name: String,
        val channelId: String,
        val avatar: String,
        val isVerified: Boolean,
        val isOwner: Boolean
    )

    data class CommentReply(
        val id: String,
        val author: CommentAuthor,
        val text: String,
        val likeCount: Int,
        val likeCountRaw: Int,
        val publishedTime: String,
        val isLikedByCreator: Boolean
    )

    data class VideoComment(
        val id: String,
        val author: CommentAuthor,
        val text: String,
        val likeCount: Int,
        val likeCountRaw: Int,
        val publishedTime: String,
        val replyCount: Int,
        val isLikedByCreator: Boolean,
        val isPinned: Boolean,
        val replies: List<CommentReply>,
        val replyContinuation: String?
    )

    data class RelatedVideo(
        val id: String,
        val title: String,
        val author: String,
        val channelUrl: String,
        val duration: String,
        val durationSeconds: Int,
        val viewCount: String,
        val viewCountRaw: Long,
        val publishedTime: String,
        val thumbnail: String,
        val isLive: Boolean
    )

    data class LiveStreamInfo(
        val isLive: Boolean,
        val isUpcoming: Boolean,
        val viewerCount: Long,
        val viewerCountStr: String,
        val startTime: String,
        val scheduledStartTime: String,
        val likesCount: Long,
        val dislikesCount: Long
    )

    // ─── LRU Cache ──────────────────────────────────────────────────────────

    class LruCache<V>(private val maxSize: Int = 500, private val ttlMs: Long = 300_000) {
        class CacheEntry<V>(val value: V, val expires: Long)

        private val map = LinkedHashMap<String, CacheEntry<V>>(maxSize, 0.75f, true)

        @Volatile private var _size = 0

        val size: Int get() = _size

        fun get(key: String): V? {
            val entry = map[key] ?: return null
            if (System.currentTimeMillis() > entry.expires) {
                map.remove(key)
                _size = map.size
                return null
            }
            map.remove(key)
            map[key] = entry
            return entry.value
        }

        fun set(key: String, value: V) {
            if (map.containsKey(key)) {
                map.remove(key)
            } else if (map.size >= maxSize) {
                val it = map.entries.iterator()
                if (it.hasNext()) { it.next(); it.remove() }
            }
            map[key] = CacheEntry(value, System.currentTimeMillis() + ttlMs)
            _size = map.size
        }

        fun clear() {
            map.clear()
            _size = 0
        }
    }

    // ─── Retry ──────────────────────────────────────────────────────────────

    suspend fun <T> withRetry(
        maxRetries: Int = 3,
        baseDelay: Long = 500,
        maxDelay: Long = 5000,
        block: suspend () -> T
    ): T {
        var lastErr: Throwable? = null
        for (a in 0..maxRetries) {
            try {
                return block()
            } catch (err: Throwable) {
                lastErr = err
                if (a >= maxRetries) throw err
                val delay = minOf(baseDelay * (1L shl a) + (Math.random() * 500).toLong(), maxDelay)
                Thread.sleep(delay)
            }
        }
        throw lastErr!!
    }

    // ─── Comment Parser ─────────────────────────────────────────────────────

    private fun parseCommentRenderer(cr: JSONObject): VideoComment {
        val id = cr.optString("commentId", "").ifEmpty {
            cr.optJSONObject("properties")?.optString("commentId", "") ?: ""
        }
        val authorName = extractRuns(cr.optJSONObject("authorText")?.optJSONArray("runs")).ifEmpty {
            cr.optJSONObject("authorText")?.optString("simpleText", "") ?: ""
        }
        val authorChannel = cr.optJSONObject("authorEndpoint")?.optJSONObject("browseEndpoint")
            ?.optString("browseId", "") ?: ""
        val authorThumbs = cr.optJSONObject("authorThumbnail")?.optJSONArray("thumbnails")
        val authorAvatar = if (authorThumbs != null && authorThumbs.length() > 0)
            authorThumbs.optJSONObject(authorThumbs.length() - 1)?.optString("url", "") ?: "" else ""
        val isVerified = cr.optJSONObject("authorCommentBadge")
            ?.optJSONObject("authorCommentBadgeRenderer")
            ?.optJSONObject("icon")
            ?.optString("iconType", "") == "CHECK"
        val isOwner = cr.optBoolean("authorIsChannelOwner", false)
        val text = cr.optJSONObject("contentText")?.optString("simpleText", "")
            ?: extractRuns(cr.optJSONObject("contentText")?.optJSONArray("runs"))
        val likeCount = cr.optJSONObject("voteCount")?.optString("simpleText")?.toIntOrNull()
            ?: cr.optString("likeCount", "0").toIntOrNull() ?: 0
        val publishedTime = cr.optJSONObject("publishedTimeText")?.optJSONArray("runs")
            ?.optJSONObject(0)?.optString("text", "") ?: ""
        val replyCount = cr.optInt("replyCount", 0)
        val isLiked = cr.optBoolean("isLiked", false)
        val isPinned = cr.optJSONObject("pinnedCommentBadge")?.optJSONObject("pinnedCommentBadgeRenderer") != null

        val replies = mutableListOf<CommentReply>()
        var replyContinuation: String? = null
        val replyItems = cr.optJSONObject("replies")?.optJSONObject("commentRepliesRenderer")
            ?.optJSONArray("contents")
        if (replyItems != null) {
            for (ri in 0 until replyItems!!.length()) {
                val riObj = replyItems.optJSONObject(ri) ?: continue
                if (riObj.optJSONObject("continuationItemRenderer") != null) {
                    replyContinuation = riObj.optJSONObject("continuationItemRenderer")
                        ?.optJSONObject("continuationEndpoint")
                        ?.optJSONObject("continuationCommand")
                        ?.optString("token")
                    continue
                }
                val rr = riObj.optJSONObject("commentRenderer") ?: continue
                val rrid = rr.optString("commentId", "")
                val rrName = extractRuns(rr.optJSONObject("authorText")?.optJSONArray("runs")).ifEmpty {
                    rr.optJSONObject("authorText")?.optString("simpleText", "") ?: ""
                }
                val rrChannel = rr.optJSONObject("authorEndpoint")?.optJSONObject("browseEndpoint")
                    ?.optString("browseId", "") ?: ""
                val rrThumbs = rr.optJSONObject("authorThumbnail")?.optJSONArray("thumbnails")
                val rrAvatar = if (rrThumbs != null && rrThumbs.length() > 0)
                    rrThumbs.optJSONObject(rrThumbs.length() - 1)?.optString("url", "") ?: "" else ""
                val rrText = rr.optJSONObject("contentText")?.optString("simpleText", "")
                    ?: extractRuns(rr.optJSONObject("contentText")?.optJSONArray("runs"))
                val rrLikes = rr.optJSONObject("voteCount")?.optString("simpleText")?.toIntOrNull() ?: 0
                val rrTime = rr.optJSONObject("publishedTimeText")?.optJSONArray("runs")
                    ?.optJSONObject(0)?.optString("text", "") ?: ""
                val rrHearted = rr.optJSONObject("actionButtons")
                    ?.optJSONObject("commentActionButtonsRenderer")
                    ?.optJSONObject("creatorHeart")
                    ?.optJSONObject("creatorHeartRenderer")
                    ?.optBoolean("isHearted", false) ?: false
                replies.add(CommentReply(
                    id = rrid,
                    author = CommentAuthor(name = rrName, channelId = rrChannel, avatar = rrAvatar,
                        isVerified = false, isOwner = rr.optBoolean("authorIsChannelOwner", false)),
                    text = rrText,
                    likeCount = rrLikes,
                    likeCountRaw = rrLikes,
                    publishedTime = rrTime,
                    isLikedByCreator = rrHearted
                ))
            }
        }

        return VideoComment(
            id = id,
            author = CommentAuthor(name = authorName, channelId = authorChannel, avatar = authorAvatar,
                isVerified = isVerified, isOwner = isOwner),
            text = text,
            likeCount = likeCount,
            likeCountRaw = likeCount,
            publishedTime = publishedTime,
            replyCount = replyCount,
            isLikedByCreator = isLiked,
            isPinned = isPinned,
            replies = replies,
            replyContinuation = replyContinuation
        )
    }

    // ─── Public: Comments ────────────────────────────────────────────────────
    fun getComments(
        videoId: String,
        limit: Int = 20,
        continuation: String? = null
    ): Pair<List<VideoComment>, String?> {
        val capped = limit.coerceIn(1, 100)
        try {
            val html = httpGet("https://www.youtube.com/watch?v=$videoId")

            if (continuation != null) {
                val pattern = Regex("\"INNERTUBE_API_KEY\":\"(AIza[^\"]+)\"")
                val apiKey = pattern.find(html)?.groupValues?.getOrNull(1) ?: DEFAULT_API_KEY
                val ctx = extractJson(html, "\"INNERTUBE_CONTEXT\"")
                val body = JSONObject().apply {
                    put("context", ctx ?: JSONObject(DEFAULT_CONTEXT))
                    put("continuation", continuation)
                }
                val respText = httpPost("https://www.youtube.com/youtubei/v1/next?key=$apiKey", body.toString())
                val data = JSONObject(respText)

                val items = (data.optJSONArray("onResponseReceivedEndpoints")?.optJSONObject(0)
                    ?.optJSONObject("reloadContinuationItemsCommand")?.optJSONArray("continuationItems"))
                    ?: (data.optJSONArray("onResponseReceivedEndpoints")?.optJSONObject(0)
                        ?.optJSONObject("appendContinuationItemsAction")?.optJSONArray("continuationItems"))
                if (items == null) return Pair(emptyList(), null)

                return parseCommentThreads(items, capped)
            }

            val data = extractJson(html, "var ytInitialData")
            if (data == null) return Pair(emptyList(), null)

            val pattern = Regex("\"INNERTUBE_API_KEY\":\"(AIza[^\"]+)\"")
            val apiKey = pattern.find(html)?.groupValues?.getOrNull(1) ?: DEFAULT_API_KEY
            val ctx = extractJson(html, "\"INNERTUBE_CONTEXT\"")

            val allResults = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnWatchNextResults")
                ?.optJSONObject("results")
                ?.optJSONObject("results")
                ?.optJSONArray("contents") ?: return Pair(emptyList(), null)

            var token: String? = null
            for (i in 0 until allResults.length()) {
                val items = allResults.optJSONObject(i)?.optJSONObject("itemSectionRenderer")
                    ?.optJSONArray("contents") ?: continue
                for (j in 0 until items!!.length()) {
                    val item = items.optJSONObject(j) ?: continue
                    token = item.optJSONObject("continuationItemRenderer")
                        ?.optJSONObject("continuationEndpoint")
                        ?.optJSONObject("continuationCommand")
                        ?.optString("token")
                    if (!token.isNullOrEmpty()) break
                    token = item.optJSONObject("commentsEntryPointHeaderRenderer")?.optJSONArray("contents")
                        ?.optJSONObject(0)?.optJSONObject("continuationItemRenderer")
                        ?.optJSONObject("continuationEndpoint")
                        ?.optJSONObject("continuationCommand")
                        ?.optString("token")
                    if (!token.isNullOrEmpty()) break
                }
                if (!token.isNullOrEmpty()) break
            }
            if (token.isNullOrEmpty()) return Pair(emptyList(), null)

            val body = JSONObject().apply {
                put("context", ctx ?: JSONObject(DEFAULT_CONTEXT))
                put("continuation", token)
            }
            val respText = httpPost("https://www.youtube.com/youtubei/v1/next?key=$apiKey", body.toString())
            val nd = JSONObject(respText)

            val nItems = (nd.optJSONArray("onResponseReceivedEndpoints")?.optJSONObject(0)
                ?.optJSONObject("reloadContinuationItemsCommand")?.optJSONArray("continuationItems"))
                ?: (nd.optJSONArray("onResponseReceivedEndpoints")?.optJSONObject(0)
                    ?.optJSONObject("appendContinuationItemsAction")?.optJSONArray("continuationItems"))
                ?: (nd.optJSONArray("onResponseReceivedEndpoints")?.optJSONObject(1)
                    ?.optJSONObject("reloadContinuationItemsCommand")?.optJSONArray("continuationItems"))
                ?: (nd.optJSONArray("onResponseReceivedEndpoints")?.optJSONObject(1)
                    ?.optJSONObject("appendContinuationItemsAction")?.optJSONArray("continuationItems"))
            if (nItems == null) return Pair(emptyList(), null)

            return parseCommentThreads(nItems, capped)
        } catch (_: Exception) {
            return Pair(emptyList(), null)
        }
    }

    private fun parseCommentThreads(items: JSONArray, limit: Int): Pair<List<VideoComment>, String?> {
        val comments = mutableListOf<VideoComment>()
        var nc: String? = null
        for (i in 0 until items!!.length()) {
            if (comments.size >= limit) break
            val item = items!!.optJSONObject(i) ?: continue
            val token = item.optJSONObject("continuationItemRenderer")
                ?.optJSONObject("continuationEndpoint")
                ?.optJSONObject("continuationCommand")
                ?.optString("token")
            if (!token.isNullOrEmpty()) nc = token
            val ctr = item.optJSONObject("commentThreadRenderer") ?: continue
            val cr = ctr.optJSONObject("comment")?.optJSONObject("commentRenderer") ?: continue
            if (ctr.optJSONObject("replies") != null) {
                cr.put("replies", ctr.optJSONObject("replies"))
            }
            comments.add(parseCommentRenderer(cr))
        }
        return Pair(comments, nc)
    }

    // ─── Public: Related Videos ──────────────────────────────────────────────
    fun getRelatedVideos(videoId: String, limit: Int = 15): List<RelatedVideo> {
        val capped = limit.coerceIn(1, 50)
        try {
            val html = httpGet("https://www.youtube.com/watch?v=$videoId")
            val data = extractJson(html, "var ytInitialData") ?: return emptyList()

            val watchNext = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnWatchNextResults")
                ?.optJSONObject("secondaryResults")
                ?.optJSONObject("secondaryResults")
                ?.optJSONArray("results") ?: return emptyList()

            val results = mutableListOf<RelatedVideo>()
            for (i in 0 until watchNext.length()) {
                if (results.size >= capped) break
                val item = watchNext.optJSONObject(i) ?: continue
                val vr = item.optJSONObject("compactVideoRenderer")
                    ?: item.optJSONObject("compactRadioRenderer") ?: continue
                val vid = vr.optString("videoId", "")
                if (vid.isEmpty()) continue

                val title = extractRuns(vr.optJSONObject("title")?.optJSONArray("runs")).ifEmpty {
                    vr.optJSONObject("title")?.optString("simpleText", "") ?: ""
                }
                val author = extractRuns(vr.optJSONObject("shortBylineText")?.optJSONArray("runs")).ifEmpty {
                    vr.optJSONObject("shortBylineText")?.optString("simpleText", "") ?: ""
                }
                val durText = vr.optJSONObject("lengthText")?.optString("simpleText", "")
                    ?: extractRuns(vr.optJSONObject("lengthText")?.optJSONArray("runs"))
                val (duration, durationSeconds) = parseDuration(durText)

                val viewsText = vr.optJSONObject("viewCountText")?.optString("simpleText", "")
                    ?: extractRuns(vr.optJSONObject("viewCountText")?.optJSONArray("runs"))
                val (viewCount, vcr) = parseViewCount(viewsText)

                val publishedTime = vr.optJSONObject("publishedTimeText")?.optString("simpleText", "") ?: ""
                val thumbnails = extractThumbnails(vr.optJSONObject("thumbnail")?.optJSONArray("thumbnails"))
                val thumbnail = extractBestThumbnail(thumbnails).ifEmpty {
                    "https://i.ytimg.com/vi/$vid/hqdefault.jpg"
                }
                val badge = vr.optJSONArray("badges")?.optJSONObject(0)
                    ?.optJSONObject("metadataBadgeRenderer")
                    ?.optString("style", "") ?: ""

                results.add(RelatedVideo(
                    id = vid, title = title, author = author,
                    channelUrl = vr.optJSONObject("shortBylineText")?.optJSONArray("runs")?.optJSONObject(0)
                        ?.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint")
                        ?.optString("canonicalBaseUrl", "") ?: "",
                    duration = duration, durationSeconds = durationSeconds,
                    viewCount = viewCount, viewCountRaw = vcr, publishedTime = publishedTime,
                    thumbnail = thumbnail,
                    isLive = badge.contains("LIVE", ignoreCase = true)
                ))
            }
            return results
        } catch (_: Exception) {
            return emptyList()
        }
    }

    // ─── Public: Live Stream Info + Stats ────────────────────────────────────
    fun getVideoStats(videoId: String): Map<String, Any> {
        try {
            val html = httpGet("https://www.youtube.com/watch?v=$videoId")
            val data = extractJson(html, "var ytInitialData")
            if (data == null) return mapOf("views" to 0L, "likes" to 0L, "comments" to 0L, "isLive" to false, "viewerCount" to 0L)

            val contents = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnWatchNextResults")
                ?.optJSONObject("results")
                ?.optJSONObject("results")
                ?.optJSONArray("contents")

            var primary: JSONObject? = null
            contents?.let { arr ->
                for (i in 0 until arr.length()) {
                    val c = arr.optJSONObject(i)
                    if (c?.optJSONObject("videoPrimaryInfoRenderer") != null) {
                        primary = c.optJSONObject("videoPrimaryInfoRenderer")
                        break
                    }
                }
            }

            val vcr = primary?.optJSONObject("viewCount")?.optJSONObject("videoViewCountRenderer")
            val viewsText = vcr?.optJSONObject("shortViewCount")?.optString("simpleText", "")
                ?: vcr?.optJSONObject("viewCount")?.optString("simpleText", "") ?: ""
            val (_, views) = parseViewCount(viewsText)

            val likesStr = primary?.optJSONObject("videoActions")
                ?.optJSONObject("menuRenderer")
                ?.optJSONArray("topLevelButtons")
                ?.optJSONObject(0)
                ?.optJSONObject("segmentedLikeDislikeButtonViewModel")
                ?.optJSONObject("likeButtonViewModel")
                ?.optJSONObject("likeButtonViewModel")
                ?.optJSONObject("toggleButtonViewModel")
                ?.optJSONObject("toggleButtonViewModel")
                ?.optJSONObject("defaultButtonViewModel")
                ?.optJSONObject("buttonViewModel")
                ?.optString("accessibilityText", "") ?: ""
            val (_, likes) = parseViewCount(likesStr.replace(Regex("[^0-9.KMBkmb]"), ""))

            val isLive = html.contains("\"isLive\":true")
            val vcm = Regex("\"viewCount\":\\{\"videoViewCountRenderer\":\\{\"isLive\":true,\"viewCount\":\\{\"simpleText\":\"([^\"]+)\"").find(html)
            val viewerCount = if (vcm != null) parseViewCount(vcm.groupValues[1]).second else 0L

            return mapOf(
                "views" to views,
                "likes" to likes,
                "comments" to 0L,
                "isLive" to isLive,
                "viewerCount" to viewerCount
            )
        } catch (_: Exception) {
            return mapOf("views" to 0L, "likes" to 0L, "comments" to 0L, "isLive" to false, "viewerCount" to 0L)
        }
    }
    fun getLiveStreamInfo(videoId: String): LiveStreamInfo {
        val stats = getVideoStats(videoId)
        val isLive = stats["isLive"] as Boolean
        val viewerCount = stats["viewerCount"] as Long
        val likes = stats["likes"] as Long

        try {
            val html = httpGet("https://www.youtube.com/watch?v=$videoId")
            val data = extractJson(html, "var ytInitialData")
            var startTime = ""
            var scheduledStartTime = ""
            if (data != null) {
                val contents = data.optJSONObject("contents")
                    ?.optJSONObject("twoColumnWatchNextResults")
                    ?.optJSONObject("results")
                    ?.optJSONObject("results")
                    ?.optJSONArray("contents")
                contents?.let { arr ->
                    for (i in 0 until arr.length()) {
                        val c = arr.optJSONObject(i)
                        val primary = c?.optJSONObject("videoPrimaryInfoRenderer")
                        if (primary != null) {
                            startTime = primary.optJSONObject("dateText")?.optString("simpleText", "") ?: ""
                            scheduledStartTime = primary.optJSONObject("upcomingEventData")
                                ?.optString("startTime", "") ?: ""
                            break
                        }
                    }
                }
            }
            return LiveStreamInfo(
                isLive = isLive,
                isUpcoming = !isLive && viewerCount == 0L,
                viewerCount = viewerCount,
                viewerCountStr = "%,d".format(viewerCount),
                startTime = startTime,
                scheduledStartTime = scheduledStartTime,
                likesCount = likes,
                dislikesCount = 0
            )
        } catch (_: Exception) {
            return LiveStreamInfo(
                isLive = isLive, isUpcoming = false, viewerCount = viewerCount,
                viewerCountStr = "%,d".format(viewerCount), startTime = "", scheduledStartTime = "",
                likesCount = likes, dislikesCount = 0
            )
        }
    }

    // ─── Channel Metadata ──────────────────────────────────────────────────────

    data class SocialLink(
        val title: String,
        val url: String,
        val icon: String
    )

    data class ChannelMetadata(
        val id: String,
        val name: String,
        val handle: String,
        val description: String,
        val subscriberCount: String,
        val subscriberCountRaw: Long,
        val videoCount: String,
        val videoCountRaw: Long,
        val avatar: String,
        val banner: String,
        val isVerified: Boolean,
        val socialLinks: List<SocialLink>,
        val url: String
    )

    data class TranscriptEntry(
        val text: String,
        val start: Double,
        val duration: Double
    )

    // ─── Public: Channel Metadata ─────────────────────────────────────────────
    fun getChannelMetadata(channelId: String): ChannelMetadata {
        val empty = ChannelMetadata(
            id = channelId, name = "", handle = "", description = "",
            subscriberCount = "", subscriberCountRaw = 0, videoCount = "", videoCountRaw = 0,
            avatar = "", banner = "", isVerified = false, socialLinks = emptyList(),
            url = "https://www.youtube.com/channel/$channelId"
        )

        try {
            val html = httpGet("https://www.youtube.com/channel/${URLEncoder.encode(channelId, "UTF-8")}/about")
            val data = extractJson(html, "var ytInitialData") ?: return empty

            val metadata = data.optJSONObject("metadata")?.optJSONObject("channelMetadataRenderer")

            val header = data.optJSONObject("header")?.optJSONObject("c4TabbedHeaderRenderer")

            var aboutRenderer: JSONObject? = null
            val tabs = data.optJSONObject("contents")?.optJSONObject("twoColumnBrowseResultsRenderer")?.optJSONArray("tabs")
            if (tabs != null) {
                for (i in 0 until tabs.length()) {
                    val tab = tabs.optJSONObject(i)
                    if (tab?.optJSONObject("tabRenderer")?.optBoolean("selected", false) == true) {
                        aboutRenderer = tab.optJSONObject("tabRenderer")?.optJSONObject("content")
                            ?.optJSONObject("sectionListRenderer")?.optJSONArray("contents")?.optJSONObject(0)
                            ?.optJSONObject("itemSectionRenderer")?.optJSONArray("contents")?.optJSONObject(0)
                            ?.optJSONObject("channelAboutFullMetadataRenderer")
                        break
                    }
                }
            }

            val subText = header?.optJSONObject("subscriberCountText")?.optString("simpleText", "") ?: ""
            val (_, subsRaw) = parseViewCount(subText)

            val videoText = aboutRenderer?.optJSONObject("videoCountText")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text", "") ?: ""
            val vcMatch = Regex("([\\d,]+)").find(videoText)
            val vcRaw = vcMatch?.groupValues?.getOrNull(1)?.replace(",", "")?.toLongOrNull() ?: 0

            val links = mutableListOf<SocialLink>()
            aboutRenderer?.optJSONArray("primaryLinks")?.let { primaryLinks ->
                for (li in 0 until primaryLinks.length()) {
                    val l = primaryLinks.optJSONObject(li) ?: continue
                    val nav = l.optJSONObject("navigationEndpoint")?.optJSONObject("urlEndpoint")
                    links.add(SocialLink(
                        title = l.optJSONObject("title")?.optString("simpleText", "")
                            ?: l.optJSONObject("title")?.optJSONArray("runs")?.optJSONObject(0)?.optString("text", "") ?: "",
                        url = nav?.optString("url", "") ?: "",
                        icon = l.optJSONObject("icon")?.optJSONArray("thumbnails")?.optJSONObject(0)?.optString("url", "") ?: ""
                    ))
                }
            }

            val name = metadata?.optString("title", "")?.ifEmpty { header?.optString("title", "") ?: "" } ?: ""
            val vanityUrl = metadata?.optString("vanityChannelUrl", "") ?: ""
            val handle = vanityUrl.replace("http://www.youtube.com/", "").replace("https://www.youtube.com/", "")

            val desc = metadata?.optString("description", "")
                ?: aboutRenderer?.optJSONObject("description")?.optString("simpleText", "")
                ?: extractRuns(aboutRenderer?.optJSONObject("description")?.optJSONArray("runs"))
                ?: ""

            val avatarThumbs = metadata?.optJSONObject("avatar")?.optJSONArray("thumbnails")
                ?: header?.optJSONObject("avatar")?.optJSONArray("thumbnails")
            val avatar = if (avatarThumbs != null) extractBestThumbnail(extractThumbnails(avatarThumbs)) else ""

            val bannerThumbs = metadata?.optJSONObject("banner")?.optJSONArray("thumbnails")
                ?: header?.optJSONObject("banner")?.optJSONArray("thumbnails")
            val banner = if (bannerThumbs != null) extractBestThumbnail(extractThumbnails(bannerThumbs)) else ""

            var isVerified = false
            header?.optJSONArray("badges")?.let { badges ->
                for (bi in 0 until badges.length()) {
                    val style = badges.optJSONObject(bi)?.optJSONObject("metadataBadgeRenderer")?.optString("style", "")
                    if (style?.contains("VERIFIED") == true) {
                        isVerified = true
                        break
                    }
                }
            }

            return ChannelMetadata(
                id = channelId, name = name, handle = handle, description = desc,
                subscriberCount = subText, subscriberCountRaw = subsRaw,
                videoCount = videoText, videoCountRaw = vcRaw,
                avatar = avatar, banner = banner, isVerified = isVerified,
                socialLinks = links, url = "https://www.youtube.com/channel/$channelId"
            )
        } catch (_: Exception) {
            return empty
        }
    }

    // ─── Public: Transcript ──────────────────────────────────────────────────
    fun getTranscript(videoId: String, lang: String? = null): List<TranscriptEntry> {
        try {
            val html = httpGet("https://www.youtube.com/watch?v=$videoId")

            val tracksStr: String?
            val capsMatch = Regex(""""captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])""")
                .find(html)
            if (capsMatch != null) {
                tracksStr = capsMatch.groupValues[1]
            } else {
                val playerMatch = Regex(""""captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])""")
                    .find(html)
                if (playerMatch == null) return emptyList()
                tracksStr = playerMatch.groupValues[1]
            }

            val tracksArr = JSONArray(tracksStr)
            val tracks = (0 until tracksArr.length()).mapNotNull { i -> tracksArr.optJSONObject(i) }

            var trackUrl = ""
            if (lang != null) {
                for (track in tracks) {
                    val lc = track.optString("languageCode", "")
                    val tn = track.optJSONObject("name")?.optString("simpleText", "") ?: ""
                    if (lc == lang || tn.contains(lang, ignoreCase = true)) {
                        trackUrl = track.optString("baseUrl", "")
                        break
                    }
                }
            }
            if (trackUrl.isEmpty()) {
                trackUrl = tracks.find { it.optString("languageCode", "") == "en" }?.optString("baseUrl", "")
                    ?: tracks.firstOrNull()?.optString("baseUrl", "") ?: ""
            }
            if (trackUrl.isEmpty()) return emptyList()

            val xml = httpGet(trackUrl)
            val entries = mutableListOf<TranscriptEntry>()
            val textRegex = Regex("""<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:</text>)?$""", RegexOption.MULTILINE)

            textRegex.findAll(xml).forEach { m ->
                val rawText = m.groupValues[3]
                    .replace(Regex("<[^>]+>"), "")
                    .replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
                    .replace("&quot;", "\"").replace("&#39;", "'")
                val trimmed = rawText.trim()
                if (trimmed.isNotEmpty()) {
                    entries.add(TranscriptEntry(
                        text = trimmed,
                        start = m.groupValues[1].toDouble(),
                        duration = m.groupValues[2].toDouble()
                    ))
                }
            }
            return entries
        } catch (_: Exception) {
            return emptyList()
        }
    }

    // ─── Public: Shorts Search ───────────────────────────────────────────────
    fun searchShorts(query: String, limit: Int = 15, gl: String? = null, hl: String? = null): List<VideoResult> {
        val capped = limit.coerceIn(1, 50)
        val region = buildString {
            if (gl != null) append("&gl=$gl")
            if (hl != null) append("&hl=$hl")
        }

        try {
            val url = SEARCH_URL + URLEncoder.encode(query, "UTF-8") + "&sp=EgIYAQ%3D%3D" + region
            val html = httpGet(url)
            val data = extractJson(html, "var ytInitialData") ?: return emptyList()

            val contents = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnSearchResultsRenderer")
                ?.optJSONObject("primaryContents")
                ?.optJSONObject("sectionListRenderer")
                ?.optJSONArray("contents")

            var reelItems: JSONArray? = null
            if (contents != null) {
                for (i in 0 until contents.length()) {
                    val section = contents.optJSONObject(i)
                    val firstItem = section?.optJSONObject("itemSectionRenderer")?.optJSONArray("contents")?.optJSONObject(0)
                    if (firstItem?.optJSONObject("reelShelfRenderer") != null) {
                        reelItems = firstItem.optJSONObject("reelShelfRenderer")?.optJSONArray("items")
                        break
                    }
                }
            }

            if (reelItems != null) {
                val shortResults = mutableListOf<VideoResult>()
                for (i in 0 until reelItems!!.length()) {
                    if (shortResults.size >= capped) break
                    val item = reelItems.optJSONObject(i) ?: continue
                    val ri = item.optJSONObject("reelItemRenderer")
                        ?: item.optJSONObject("shortsLockupViewModel")
                    val vid = ri?.optString("videoId", "")
                        ?: item.optJSONObject("reelItemRenderer")?.optString("videoId", "")
                        ?: continue
                    if (vid.isEmpty()) continue

                    val title = ri?.optJSONObject("headline")?.optString("simpleText", "")
                        ?: extractRuns(ri?.optJSONObject("headline")?.optJSONArray("runs"))
                        ?: ""
                    val durSec = ri?.optJSONObject("lengthText")?.optString("simpleText")?.toIntOrNull() ?: 0

                    val fb = fallbackResult(vid)
                    shortResults.add(fb.copy(
                        title = title.ifEmpty { "Shorts $vid" },
                        duration = "${durSec}s",
                        durationSeconds = durSec,
                        isLive = false,
                        isUpcoming = false,
                        isVerified = false
                    ))
                }

                val (allResults, _) = parseSearchResults(data, capped)
                val seen = mutableSetOf<String>()
                val combined = mutableListOf<VideoResult>()
                for (r in shortResults) {
                    if (seen.add(r.id)) combined.add(r)
                }
                for (r in allResults) {
                    if (seen.add(r.id) && combined.size < capped) combined.add(r)
                }
                return combined
            }

            val (results, _) = parseSearchResults(data, capped)
            return results
        } catch (_: Exception) {
            return emptyList()
        }
    }

    // ─── Region-aware search helpers ─────────────────────────────────────────

    private fun buildRegionQuery(gl: String?, hl: String?): String = buildString {
        if (gl != null) append("&gl=$gl")
        if (hl != null) append("&hl=$hl")
    }

    // ─── Global Cache ────────────────────────────────────────────────────

    val globalCache = LruCache<String>(500, 300_000)

    // ─── Client Factory ────────────────────────────────────────────────────

    data class YtapisClient(
        val search: (String, Int) -> List<VideoResult>,
        val searchTrending: (Int) -> List<VideoResult>,
        val searchChannel: (String, Int) -> List<VideoResult>,
        val searchPlaylist: (String, Int) -> List<VideoResult>,
        val searchContinue: (String, Int, String?, String?, String) -> SearchResponse,
        val getVideo: (String) -> VideoResult,
        val getComments: (String, Int, String?) -> Pair<List<VideoComment>, String?>,
        val getRelatedVideos: (String, Int) -> List<RelatedVideo>,
        val getVideoStats: (String) -> Map<String, Any>,
        val getLiveStreamInfo: (String) -> LiveStreamInfo,
        val getChannelMetadata: (String) -> ChannelMetadata,
        val getTranscript: (String, String?) -> List<TranscriptEntry>,
        val searchShorts: (String, Int) -> List<VideoResult>,
        val cache: LruCache<String>
    )
    fun createClient(
        cache: LruCache<String>? = null,
        retry: Boolean = true,
        maxRetries: Int = 3
    ): YtapisClient {
        return YtapisClient(
            search = { q, l -> search(q, l) },
            searchTrending = { l -> searchTrending(l) },
            searchChannel = { cid, l -> searchChannel(cid, l) },
            searchPlaylist = { pid, l -> searchPlaylist(pid, l) },
            searchContinue = { cont, l, ak, ctx, p -> searchContinue(cont, l, ak, ctx, p) },
            getVideo = { id -> getVideo(id) },
            getComments = { vid, l, c -> getComments(vid, l, c) },
            getRelatedVideos = { vid, l -> getRelatedVideos(vid, l) },
            getVideoStats = { vid -> getVideoStats(vid) },
            getLiveStreamInfo = { vid -> getLiveStreamInfo(vid) },
            getChannelMetadata = { cid -> getChannelMetadata(cid) },
            getTranscript = { vid, lang -> getTranscript(vid, lang) },
            searchShorts = { q, l -> searchShorts(q, l) },
            cache = cache ?: globalCache
        )
    }

    private fun parseChannelResults(
        data: JSONObject,
        limit: Int
    ): Pair<List<VideoResult>, String?> {
        val results = mutableListOf<VideoResult>()
        var continuation: String? = null

        try {
            val tabs = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnBrowseResultsRenderer")
                ?.optJSONArray("tabs") ?: return Pair(results, continuation)

            for (ti in 0 until tabs.length()) {
                val tab = tabs.optJSONObject(ti) ?: continue
                val content = tab.optJSONObject("tabRenderer")?.optJSONObject("content") ?: continue

                val items = content.optJSONObject("richGridRenderer")?.optJSONArray("contents")
                    ?: content.optJSONObject("sectionListRenderer")?.optJSONArray("contents")
                    ?: continue

                for (ii in 0 until items!!.length()) {
                    if (results.size >= limit) break
                    val item = items.optJSONObject(ii) ?: continue

                    val token = item.optJSONObject("continuationItemRenderer")
                        ?.optJSONObject("continuationEndpoint")
                        ?.optJSONObject("continuationCommand")
                        ?.optString("token")
                    if (!token.isNullOrEmpty()) {
                        continuation = token
                    }

                    var vr = item.optJSONObject("videoRenderer")
                    if (vr == null) {
                        vr = item.optJSONObject("richItemRenderer")
                            ?.optJSONObject("content")
                            ?.optJSONObject("videoRenderer")
                    }
                    if (vr != null) {
                        val parsed = parseVideoRenderer(vr)
                        if (parsed != null) results.add(parsed)
                    }
                }

                if (results.isNotEmpty()) break
            }
        } catch (_: Exception) {
        }

        return Pair(results, continuation)
    }

    private fun parsePlaylistResults(
        data: JSONObject,
        limit: Int
    ): Pair<List<VideoResult>, String?> {
        val results = mutableListOf<VideoResult>()
        var continuation: String? = null

        try {
            var contents = data.optJSONObject("contents")
                ?.optJSONObject("twoColumnBrowseResultsRenderer")
                ?.optJSONArray("tabs")
                ?.optJSONObject(0)
                ?.optJSONObject("tabRenderer")
                ?.optJSONObject("content")
                ?.optJSONObject("sectionListRenderer")
                ?.optJSONArray("contents")
                ?.optJSONObject(0)
                ?.optJSONObject("itemSectionRenderer")
                ?.optJSONArray("contents")
                ?.optJSONObject(0)
                ?.optJSONObject("playlistVideoListRenderer")
                ?.optJSONArray("contents")

            if (contents == null) {
                contents = data.optJSONObject("contents")
                    ?.optJSONObject("twoColumnWatchNextResults")
                    ?.optJSONObject("playlist")
                    ?.optJSONObject("playlist")
                    ?.optJSONArray("contents")
            }
            if (contents == null) return Pair(results, continuation)

            for (i in 0 until contents.length()) {
                if (results.size >= limit) break
                val item = contents.optJSONObject(i) ?: continue

                val token = item.optJSONObject("continuationItemRenderer")
                    ?.optJSONObject("continuationEndpoint")
                    ?.optJSONObject("continuationCommand")
                    ?.optString("token")
                if (!token.isNullOrEmpty()) {
                    continuation = token
                }

                val pvr = item.optJSONObject("playlistVideoRenderer") ?: continue
                val vid = pvr.optString("videoId", "")
                if (vid.isEmpty()) continue

                val title = extractRuns(pvr.optJSONObject("title")?.optJSONArray("runs"))
                val author = extractRuns(pvr.optJSONObject("shortBylineText")?.optJSONArray("runs"))
                val durText = pvr.optJSONObject("lengthText")?.optString("simpleText", "")
                    ?: extractRuns(pvr.optJSONObject("lengthText")?.optJSONArray("runs"))
                val (duration, durationSeconds) = parseDuration(durText)

                val fb = fallbackResult(vid)
                results.add(fb.copy(
                    title = title.ifEmpty { fb.title },
                    author = author.ifEmpty { fb.author },
                    duration = duration,
                    durationSeconds = durationSeconds
                ))
            }
        } catch (_: Exception) {
        }

        return Pair(results, continuation)
    }

    // ─── Public API: trending / channel / playlist ────────────────────────────
    fun searchTrending(limit: Int = 15): List<VideoResult> {
        val capped = limit.coerceIn(1, 50)
        try {
            val html = httpGet("https://www.youtube.com/feed/trending")
            val data = extractJson(html, "var ytInitialData") ?: return emptyList()
            val (rawResults, _) = parseTrendingResults(data, capped)
            return rawResults
        } catch (_: Exception) {
            return emptyList()
        }
    }
    fun searchChannel(channelId: String, limit: Int = 15): List<VideoResult> {
        val capped = limit.coerceIn(1, 50)
        try {
            val url = "https://www.youtube.com/channel/${URLEncoder.encode(channelId, "UTF-8")}/videos"
            val html = httpGet(url)
            val data = extractJson(html, "var ytInitialData") ?: return emptyList()
            val (rawResults, _) = parseChannelResults(data, capped)

            val needsEnrichment = rawResults.filter {
                it.title.isEmpty() || it.title == "Video ${it.id}" || it.author == "YouTube"
            }
            if (needsEnrichment.isEmpty()) return rawResults

            val enrichedData = needsEnrichment.associate { it.id to fetchOembed(it.id) }
            return rawResults.map { r ->
                val enrich = enrichedData[r.id]
                if (enrich != null) {
                    val (title, author, thumbnail) = enrich
                    r.copy(
                        title = title.ifEmpty { r.title },
                        author = author.ifEmpty { r.author },
                        thumbnail = if (thumbnail.isNotEmpty() && thumbnail != r.thumbnail)
                            thumbnail else r.thumbnail
                    )
                } else r
            }
        } catch (_: Exception) {
            return emptyList()
        }
    }
    fun searchPlaylist(playlistId: String, limit: Int = 15): List<VideoResult> {
        val capped = limit.coerceIn(1, 50)
        try {
            val url = "https://www.youtube.com/playlist?list=${URLEncoder.encode(playlistId, "UTF-8")}"
            val html = httpGet(url)
            val data = extractJson(html, "var ytInitialData") ?: return emptyList()
            val (rawResults, _) = parsePlaylistResults(data, capped)

            val needsEnrichment = rawResults.filter {
                it.title.isEmpty() || it.title == "Video ${it.id}" || it.author == "YouTube"
            }
            if (needsEnrichment.isEmpty()) return rawResults

            val enrichedData = needsEnrichment.associate { it.id to fetchOembed(it.id) }
            return rawResults.map { r ->
                val enrich = enrichedData[r.id]
                if (enrich != null) {
                    val (title, author, thumbnail) = enrich
                    r.copy(
                        title = title.ifEmpty { r.title },
                        author = author.ifEmpty { r.author },
                        thumbnail = if (thumbnail.isNotEmpty() && thumbnail != r.thumbnail)
                            thumbnail else r.thumbnail
                    )
                } else r
            }
        } catch (_: Exception) {
            return emptyList()
        }
    }
}
