package ytapis

import kotlin.system.exitProcess

fun main(args: Array<String>) {
    if (args.isEmpty() || args[0] == "--help" || args[0] == "-h") {
        showHelp()
        if (args.isEmpty()) exitProcess(1) else return
    }
    if (args[0] == "--version" || args[0] == "-v") {
        println("ytapis v$VERSION")
        return
    }
    val cmd = args[0]
    try {
        when (cmd) {
            "search" -> handleSearch(args)
            "trending" -> handleTrending(args)
            "channel" -> handleChannel(args)
            "playlist" -> handlePlaylist(args)
            "video" -> handleVideo(args)
            else -> { System.err.println("Unknown command: $cmd"); showHelp(); exitProcess(1) }
        }
    } catch (e: Exception) {
        System.err.println("Error: ${e.message}")
        exitProcess(1)
    }
}

const val VERSION = "2.0.0"

fun showHelp() {
    System.err.println("""ytapis v$VERSION
  YouTube search engine — no API key required.

Usage:
  ytapis search <query> [--limit N]
  ytapis trending [--limit N]
  ytapis channel <id> [--limit N]
  ytapis playlist <id> [--limit N]
  ytapis video <id>
  ytapis --version | -v
  ytapis --help | -h

Options:
  --limit, -l  <N>   Max results (default 15)""")
}

data class ParsedArgs(val queryParts: List<String>, val limit: Int)

fun parseArgs(args: Array<String>, startIndex: Int): ParsedArgs {
    val parts = mutableListOf<String>()
    var limit = 15
    var i = startIndex
    while (i < args.size) {
        when {
            (args[i] == "--limit" || args[i] == "-l") && i + 1 < args.size -> {
                limit = maxOf(1, (args[i + 1].toIntOrNull() ?: 15)); i++
            }
            !args[i].startsWith("-") -> parts.add(args[i])
        }
        i++
    }
    return ParsedArgs(parts, limit)
}

fun handleSearch(args: Array<String>) {
    val (q, limit) = parseArgs(args, 1)
    if (q.isEmpty()) { System.err.println("Error: search query required"); exitProcess(1) }
    val results = Ytapis.search(q.joinToString(" "), limit)
    println(resultsToJson(results))
}

fun handleTrending(args: Array<String>) {
    val (_, limit) = parseArgs(args, 1)
    val results = Ytapis.searchTrending(limit)
    println(resultsToJson(results))
}

fun handleChannel(args: Array<String>) {
    val (q, limit) = parseArgs(args, 1)
    if (q.isEmpty()) { System.err.println("Error: channel ID required"); exitProcess(1) }
    val results = Ytapis.searchChannel(q[0], limit)
    println(resultsToJson(results))
}

fun handlePlaylist(args: Array<String>) {
    val (q, limit) = parseArgs(args, 1)
    if (q.isEmpty()) { System.err.println("Error: playlist ID required"); exitProcess(1) }
    val results = Ytapis.searchPlaylist(q[0], limit)
    println(resultsToJson(results))
}

fun handleVideo(args: Array<String>) {
    val (q, _) = parseArgs(args, 1)
    if (q.isEmpty()) { System.err.println("Error: video ID required"); exitProcess(1) }
    val result = Ytapis.getVideo(q[0])
    println(videoToJson(result))
}

fun resultsToJson(results: List<VideoResult>): String {
    val arr = org.json.JSONArray()
    results.forEach { arr.put(videoToJsonObject(it)) }
    return arr.toString(2)
}

fun videoToJson(r: VideoResult): String = videoToJsonObject(r).toString(2)

fun videoToJsonObject(r: VideoResult): org.json.JSONObject {
    val thumbs = org.json.JSONArray()
    r.thumbnails.forEach { t ->
        thumbs.put(org.json.JSONObject().apply { put("url", t.url); put("width", t.width); put("height", t.height) })
    }
    return org.json.JSONObject().apply {
        put("id", r.id); put("title", r.title); put("author", r.author)
        put("channelUrl", r.channelUrl); put("thumbnail", r.thumbnail); put("thumbnails", thumbs)
        put("fullUrl", r.fullUrl); put("embedUrl", r.embedUrl)
        put("duration", r.duration); put("durationSeconds", r.durationSeconds)
        put("viewCount", r.viewCount); put("viewCountRaw", r.viewCountRaw)
        put("publishedTime", r.publishedTime); put("description", r.description)
        put("channelAvatar", r.channelAvatar)
        put("isLive", r.isLive); put("isUpcoming", r.isUpcoming); put("isVerified", r.isVerified)
    }
}
