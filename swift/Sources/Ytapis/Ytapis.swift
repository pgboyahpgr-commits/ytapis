import Foundation

public enum Ytapis {
    public enum Error: Swift.Error {
        case invalidURL
        case httpError(Int)
        case invalidResponse
        case missingData
    }

    // MARK: - Constants

    private static let searchURL = "https://www.youtube.com/results?search_query="
    private static let watchBase = "https://www.youtube.com/watch?v="
    private static let embedBase = "https://www.youtube.com/embed/"
    private static let oembedURL = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch="
    private static let innerTubeURL = "https://www.youtube.com/youtubei/v1/search"
    private static let defaultAPIKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    private static let userAgent = "Mozilla/5.0 (compatible; ytapis/1.0)"
    private static let acceptLanguage = "en-US,en;q=0.9"

    private static let defaultContextDict: [String: Any] = [
        "client": [
            "hl": "en",
            "gl": "US",
            "clientName": "WEB",
            "clientVersion": "2.20240801.00.00"
        ] as [String: Any]
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    public static func search(query: String, limit: Int = 15) async throws -> SearchResponse {
        let capped = min(max(1, limit), 50)
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw Error.invalidURL
        }

        let html = try await httpGet(searchURL + encoded)

        guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
            return SearchResponse(results: [], continuation: nil, apiKey: nil)
        }

        let (rawResults, continuationToken) = parseSearchResults(data, limit: capped)

        let needsEnrichment = rawResults.filter {
            $0.title.isEmpty || $0.title == "Video \($0.id)" || $0.author == "YouTube"
        }

        if needsEnrichment.isEmpty {
            let key = extractApiKey(from: html)
            return SearchResponse(results: rawResults, continuation: continuationToken, apiKey: key)
        }

        let enrichedMap = await withTaskGroup(
            of: (String, String, String, String).self,
            returning: [String: (String, String, String)].self
        ) { group in
            for video in needsEnrichment {
                group.addTask {
                    let (title, author, thumbnail) = await fetchOembed(id: video.id)
                    return (video.id, title, author, thumbnail)
                }
            }
            var result: [String: (String, String, String)] = [:]
            for await (id, title, author, thumbnail) in group {
                result[id] = (title, author, thumbnail)
            }
            return result
        }

        let results = rawResults.map { video -> VideoResult in
            guard let (title, author, thumbnail) = enrichedMap[video.id] else { return video }
            return VideoResult(
                id: video.id,
                title: title.isEmpty ? video.title : title,
                author: author.isEmpty ? video.author : author,
                channelUrl: video.channelUrl,
                thumbnail: (!thumbnail.isEmpty && thumbnail != video.thumbnail) ? thumbnail : video.thumbnail,
                thumbnails: video.thumbnails,
                fullUrl: video.fullUrl,
                embedUrl: video.embedUrl,
                duration: video.duration,
                durationSeconds: video.durationSeconds,
                viewCount: video.viewCount,
                viewCountRaw: video.viewCountRaw,
                publishedTime: video.publishedTime,
                description: video.description,
                channelAvatar: video.channelAvatar,
                isLive: video.isLive,
                isUpcoming: video.isUpcoming,
                isVerified: video.isVerified
            )
        }

        let key = extractApiKey(from: html)
        return SearchResponse(results: results, continuation: continuationToken, apiKey: key)
    }

    public static func getVideo(id: String) async throws -> VideoResult {
        let fallback = fallbackResult(id: id)

        do {
            let html = try await httpGet(watchBase + id)

            let playerData = extractJson(from: html, prefix: "var ytInitialPlayerResponse")
                ?? extractJson(from: html, prefix: "var ytInitialData")

            if let data = playerData {
                if let vd = data["videoDetails"] as? [String: Any] {
                    let durSec = vd["lengthSeconds"] as? Int ?? Int(vd["lengthSeconds"] as? String ?? "") ?? 0
                    let durStr = formatDuration(durSec)

                    let thumbs = parseThumbnails(
                        (vd["thumbnail"] as? [String: Any])?["thumbnails"]
                    )
                    let bestThumb = extractBestThumbnail(thumbs)

                    let rawViews = vd["viewCount"] as? Int ?? Int(vd["viewCount"] as? String ?? "") ?? 0
                    let viewLabel = rawViews > 0 ? formatViewCount(rawViews) : ""

                    return VideoResult(
                        id: vd["videoId"] as? String ?? fallback.id,
                        title: (vd["title"] as? String) ?? fallback.title,
                        author: (vd["author"] as? String) ?? fallback.author,
                        channelUrl: "https://www.youtube.com/channel/\(vd["channelId"] as? String ?? "")",
                        thumbnail: bestThumb.isEmpty ? fallback.thumbnail : bestThumb,
                        thumbnails: thumbs.isEmpty ? fallback.thumbnails : thumbs,
                        fullUrl: fallback.fullUrl,
                        embedUrl: fallback.embedUrl,
                        duration: durStr,
                        durationSeconds: durSec,
                        viewCount: viewLabel,
                        viewCountRaw: rawViews,
                        publishedTime: "",
                        description: vd["shortDescription"] as? String ?? "",
                        channelAvatar: parseChannelAvatar(from: vd),
                        isLive: vd["isLive"] as? Bool ?? false,
                        isUpcoming: vd["isUpcoming"] as? Bool ?? false,
                        isVerified: false
                    )
                }
            }

            let (title, author, thumbnail) = await fetchOembed(id: id)
            return VideoResult(
                id: fallback.id,
                title: title.isEmpty ? fallback.title : title,
                author: author.isEmpty ? fallback.author : author,
                channelUrl: fallback.channelUrl,
                thumbnail: thumbnail.isEmpty ? fallback.thumbnail : thumbnail,
                thumbnails: (!thumbnail.isEmpty && thumbnail != fallback.thumbnail)
                    ? [Thumbnail(url: thumbnail, width: 480, height: 360)]
                    : fallback.thumbnails,
                fullUrl: fallback.fullUrl,
                embedUrl: fallback.embedUrl,
                duration: fallback.duration,
                durationSeconds: fallback.durationSeconds,
                viewCount: fallback.viewCount,
                viewCountRaw: fallback.viewCountRaw,
                publishedTime: fallback.publishedTime,
                description: fallback.description,
                channelAvatar: fallback.channelAvatar,
                isLive: fallback.isLive,
                isUpcoming: fallback.isUpcoming,
                isVerified: fallback.isVerified
            )
        } catch {
            return fallback
        }
    }

    public static func searchContinue(
        continuation: String,
        limit: Int = 15,
        apiKey: String? = nil,
        context: [String: Any]? = nil,
        path: String = "search"
    ) async throws -> SearchResponse {
        let capped = min(max(1, limit), 50)
        let key = apiKey ?? defaultAPIKey
        let ctx = context ?? defaultContextDict

        let bodyDict: [String: Any] = [
            "context": ctx,
            "continuation": continuation
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        guard let bodyStr = String(data: bodyData, encoding: .utf8) else {
            throw Error.missingData
        }

        let responseText = try await httpPost("\(innerTubeURL)?key=\(key)", body: bodyStr)

        guard let respData = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            return SearchResponse(results: [], continuation: nil, apiKey: nil)
        }

        let (rawResults, nextToken) = parseContinuationResults(json, limit: capped, path: path)

        let needsEnrichment = rawResults.filter {
            $0.title.isEmpty || $0.title == "Video \($0.id)" || $0.author == "YouTube"
        }

        if needsEnrichment.isEmpty {
            return SearchResponse(results: rawResults, continuation: nextToken, apiKey: key)
        }

        let enrichedMap = await withTaskGroup(
            of: (String, String, String, String).self,
            returning: [String: (String, String, String)].self
        ) { group in
            for video in needsEnrichment {
                group.addTask {
                    let (title, author, thumbnail) = await fetchOembed(id: video.id)
                    return (video.id, title, author, thumbnail)
                }
            }
            var result: [String: (String, String, String)] = [:]
            for await (id, title, author, thumbnail) in group {
                result[id] = (title, author, thumbnail)
            }
            return result
        }

        let results = rawResults.map { video -> VideoResult in
            guard let (title, author, thumbnail) = enrichedMap[video.id] else { return video }
            return VideoResult(
                id: video.id,
                title: title.isEmpty ? video.title : title,
                author: author.isEmpty ? video.author : author,
                channelUrl: video.channelUrl,
                thumbnail: (!thumbnail.isEmpty && thumbnail != video.thumbnail) ? thumbnail : video.thumbnail,
                thumbnails: video.thumbnails,
                fullUrl: video.fullUrl,
                embedUrl: video.embedUrl,
                duration: video.duration,
                durationSeconds: video.durationSeconds,
                viewCount: video.viewCount,
                viewCountRaw: video.viewCountRaw,
                publishedTime: video.publishedTime,
                description: video.description,
                channelAvatar: video.channelAvatar,
                isLive: video.isLive,
                isUpcoming: video.isUpcoming,
                isVerified: video.isVerified
            )
        }

        return SearchResponse(results: results, continuation: nextToken, apiKey: key)
    }

    // MARK: - Public Parsers

    public static func parseDuration(_ text: String) -> (String, Int) {
        guard !text.isEmpty else { return ("", 0) }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let seconds: Int
        switch parts.count {
        case 3: seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: seconds = parts[0] * 60 + parts[1]
        case 1: seconds = parts[0]
        default: return ("", 0)
        }
        return (text, seconds)
    }

    public static func parseViewCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let allowed = CharacterSet(charactersIn: "0123456789.KMBkmb")
        let cleaned = String(text.unicodeScalars.filter { allowed.contains($0) })
        guard !cleaned.isEmpty else { return 0 }

        let upper = cleaned.uppercased()
        let numStr = String(upper.filter { "0123456789.".contains($0) })
        guard let num = Double(numStr) else { return 0 }

        let multiplier: Double
        if upper.contains("B") { multiplier = 1_000_000_000 }
        else if upper.contains("M") { multiplier = 1_000_000 }
        else if upper.contains("K") { multiplier = 1_000 }
        else { multiplier = 1 }

        return Int((num * multiplier).rounded())
    }

    public static func extractJson(from html: String, prefix: String) -> [String: Any]? {
        let nsHtml = html as NSString
        let prefixRange = nsHtml.range(of: prefix)
        guard prefixRange.location != NSNotFound else { return nil }

        var idx = prefixRange.location + prefixRange.length

        while idx < nsHtml.length {
            if nsHtml.character(at: idx) == 0x7B { break }
            idx += 1
        }
        guard idx < nsHtml.length else { return nil }

        let startIdx = idx
        var depth = 0
        var inString = false
        var escaped = false

        while idx < nsHtml.length {
            let ch = nsHtml.character(at: idx)

            if escaped {
                escaped = false
                idx += 1
                continue
            }
            if ch == 0x5C {
                escaped = true
                idx += 1
                continue
            }
            if ch == 0x22 {
                inString = !inString
                idx += 1
                continue
            }
            if inString {
                idx += 1
                continue
            }
            if ch == 0x7B { depth += 1 }
            if ch == 0x7D {
                depth -= 1
                if depth == 0 {
                    let jsonStr = nsHtml.substring(with: NSRange(location: startIdx, length: idx - startIdx + 1))
                    guard let data = jsonStr.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return nil
    // MARK: - Trending / Channel / Playlist

    private static func parseTrendingResults(
        _ data: [String: Any],
        limit: Int
    ) -> (results: [VideoResult], continuation: String?) {
        var results = [VideoResult]()
        var continuation: String?

        guard let tabs = (data["contents"] as? [String: Any])
                .flatMap({ $0["twoColumnBrowseResultsRenderer"] as? [String: Any] })
                .flatMap({ $0["tabs"] as? [Any] })
        else { return (results, continuation) }

        for tab in tabs {
            guard let tabDict = tab as? [String: Any],
                  let contents = (tabDict["tabRenderer"] as? [String: Any])
                    .flatMap({ $0["content"] as? [String: Any] })
                    .flatMap({ $0["sectionListRenderer"] as? [String: Any] })
                    .flatMap({ $0["contents"] as? [Any] })
            else { continue }

            for section in contents {
                if results.count >= limit { break }
                guard let sectionDict = section as? [String: Any] else { continue }

                if let items = (sectionDict["itemSectionRenderer"] as? [String: Any])?["contents"] as? [Any] {
                    for item in items {
                        if results.count >= limit { break }
                        guard let itemDict = item as? [String: Any],
                              let vr = itemDict["videoRenderer"] as? [String: Any],
                              let parsed = parseVideoRenderer(vr)
                        else { continue }
                        results.append(parsed)
                    }
                }

                if let shelf = sectionDict["shelfRenderer"] as? [String: Any],
                   let shelfContent = shelf["content"] as? [String: Any] {
                    let shelfItems = (shelfContent["expandedShelfContentsRenderer"] as? [String: Any])?["items"] as? [Any]
                        ?? (shelfContent["horizontalListRenderer"] as? [String: Any])?["items"] as? [Any]
                    if let shelfItems = shelfItems {
                        for item in shelfItems {
                            if results.count >= limit { break }
                            guard let itemDict = item as? [String: Any],
                                  let vr = itemDict["videoRenderer"] as? [String: Any],
                                  let parsed = parseVideoRenderer(vr)
                            else { continue }
                            results.append(parsed)
    // MARK: - New Types

    public struct CommentAuthor: Codable {
        public var name: String
        public var channelId: String
        public var avatar: String
        public var isVerified: Bool
        public var isOwner: Bool
    }

    public struct CommentReply: Codable {
        public var id: String
        public var author: CommentAuthor
        public var text: String
        public var likeCount: Int
        public var likeCountRaw: Int
        public var publishedTime: String
        public var isLikedByCreator: Bool
    }

    public struct VideoComment: Codable {
        public var id: String
        public var author: CommentAuthor
        public var text: String
        public var likeCount: Int
        public var likeCountRaw: Int
        public var publishedTime: String
        public var replyCount: Int
        public var isLikedByCreator: Bool
        public var isPinned: Bool
        public var replies: [CommentReply]
        public var replyContinuation: String?
    }

    public struct RelatedVideo: Codable {
        public var id: String
        public var title: String
        public var author: String
        public var channelUrl: String
        public var duration: String
        public var durationSeconds: Int
        public var viewCount: String
        public var viewCountRaw: Int
        public var publishedTime: String
        public var thumbnail: String
        public var isLive: Bool
    }

    public struct LiveStreamInfo: Codable {
        public var isLive: Bool
        public var isUpcoming: Bool
        public var viewerCount: Int
        public var viewerCountStr: String
        public var startTime: String
        public var scheduledStartTime: String
        public var likesCount: Int
        public var dislikesCount: Int
    }

    // MARK: - LRU Cache

    public class LRUCache<V> {
        private let maxSize: Int
        private let ttlMs: Int64
        private var map: [String: (value: V, expires: Int64)] = [:]
        private var order: [String] = []

        public init(maxSize: Int = 500, ttlMs: Int64 = 300_000) {
            self.maxSize = maxSize
            self.ttlMs = ttlMs
        }

        public func get(_ key: String) -> V? {
            guard let entry = map[key] else { return nil }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if now > entry.expires {
                map.removeValue(forKey: key)
                order.removeAll { $0 == key }
                return nil
            }
            order.removeAll { $0 == key }
            order.append(key)
            return entry.value
        }

        public func set(_ key: String, _ value: V) {
            if map[key] != nil {
                order.removeAll { $0 == key }
            } else if map.count >= maxSize {
                if let oldest = order.first {
                    map.removeValue(forKey: oldest)
                    order.removeFirst()
                }
            }
            order.append(key)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            map[key] = (value, now + ttlMs)
        }

        public func clear() {
            map.removeAll()
            order.removeAll()
        }

        public var size: Int { map.count }
    }

    // MARK: - Retry

    public static func withRetry<T>(_ maxRetries: Int = 3, baseDelay: Int64 = 500, maxDelay: Int64 = 5000, _ block: () async throws -> T) async throws -> T {
        var lastErr: Swift.Error?
        for a in 0...maxRetries {
            do {
                return try await block()
            } catch {
                lastErr = error
                if a >= maxRetries { throw error }
                let delay = min(baseDelay * Int64(pow(2.0, Double(a))) + Int64.random(in: 0...500), maxDelay)
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
        }
        throw lastErr ?? Error.missingData
    }

    // MARK: - Comment Parser

    private static func parseCommentRenderer(_ cr: [String: Any]) -> VideoComment {
        let id = (cr["commentId"] as? String) ?? ((cr["properties"] as? [String: Any])?["commentId"] as? String) ?? ""
        let authorName = extractRuns((cr["authorText"] as? [String: Any])?["runs"])
            .ifEmpty(or: (cr["authorText"] as? [String: Any])?["simpleText"] as? String ?? "")
        let authorChannel = (cr["authorEndpoint"] as? [String: Any])
            .flatMap { $0["browseEndpoint"] as? [String: Any] }
            .flatMap { $0["browseId"] as? String } ?? ""
        let authorThumbs = (cr["authorThumbnail"] as? [String: Any])?["thumbnails"]
        let authorAvatar = extractBestThumbnail(parseThumbnails(authorThumbs))
        let isVerified = ((cr["authorCommentBadge"] as? [String: Any])
            .flatMap { $0["authorCommentBadgeRenderer"] as? [String: Any] }
            .flatMap { $0["icon"] as? [String: Any] }
            .flatMap { $0["iconType"] as? String }) == "CHECK"
        let isOwner = cr["authorIsChannelOwner"] as? Bool ?? false
        let text = extractSimpleOrRuns(cr["contentText"] as? [String: Any])
        let likeCount = Int((cr["voteCount"] as? [String: Any])?["simpleText"] as? String ?? cr["likeCount"] as? String ?? "0") ?? 0
        let publishedTime = ((cr["publishedTimeText"] as? [String: Any])?["runs"] as? [Any])?.first
            .flatMap { ($0 as? [String: Any])?["text"] as? String } ?? ""
        let replyCount = cr["replyCount"] as? Int ?? 0
        let isLiked = cr["isLiked"] as? Bool ?? false
        let isPinned = (cr["pinnedCommentBadge"] as? [String: Any])?["pinnedCommentBadgeRenderer"] != nil

        var replies = [CommentReply]()
        var replyContinuation: String? = nil
        if let replyItems = ((cr["replies"] as? [String: Any])?["commentRepliesRenderer"] as? [String: Any])?["contents"] as? [Any] {
            for ri in replyItems {
                guard let riDict = ri as? [String: Any] else { continue }
                if let token = (riDict["continuationItemRenderer"] as? [String: Any])
                    .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                    .flatMap({ $0["continuationCommand"] as? [String: Any] })
                    .flatMap({ $0["token"] as? String }) {
                    replyContinuation = token
                    continue
                }
                guard let rr = riDict["commentRenderer"] as? [String: Any] else { continue }
                let rrid = rr["commentId"] as? String ?? ""
                let rrName = extractRuns((rr["authorText"] as? [String: Any])?["runs"])
                    .ifEmpty(or: (rr["authorText"] as? [String: Any])?["simpleText"] as? String ?? "")
                let rrChannel = (rr["authorEndpoint"] as? [String: Any])
                    .flatMap { $0["browseEndpoint"] as? [String: Any] }
                    .flatMap { $0["browseId"] as? String } ?? ""
                let rrThumbs = (rr["authorThumbnail"] as? [String: Any])?["thumbnails"]
                let rrAvatar = extractBestThumbnail(parseThumbnails(rrThumbs))
                let rrText = extractSimpleOrRuns(rr["contentText"] as? [String: Any])
                let rrLikes = Int((rr["voteCount"] as? [String: Any])?["simpleText"] as? String ?? "0") ?? 0
                let rrTime = ((rr["publishedTimeText"] as? [String: Any])?["runs"] as? [Any])?.first
                    .flatMap { ($0 as? [String: Any])?["text"] as? String } ?? ""
                let rrHearted = (rr["actionButtons"] as? [String: Any])
                    .flatMap { $0["commentActionButtonsRenderer"] as? [String: Any] }
                    .flatMap { $0["creatorHeart"] as? [String: Any] }
                    .flatMap { $0["creatorHeartRenderer"] as? [String: Any] }
                    .flatMap { $0["isHearted"] as? Bool } ?? false
                let rrOwner = rr["authorIsChannelOwner"] as? Bool ?? false
                replies.append(CommentReply(
                    id: rrid,
                    author: CommentAuthor(name: rrName, channelId: rrChannel, avatar: rrAvatar,
                                          isVerified: false, isOwner: rrOwner),
                    text: rrText, likeCount: rrLikes, likeCountRaw: rrLikes,
                    publishedTime: rrTime, isLikedByCreator: rrHearted
                ))
            }
        }

        return VideoComment(
            id: id,
            author: CommentAuthor(name: authorName, channelId: authorChannel, avatar: authorAvatar,
                                   isVerified: isVerified, isOwner: isOwner),
            text: text, likeCount: likeCount, likeCountRaw: likeCount,
            publishedTime: publishedTime, replyCount: replyCount,
            isLikedByCreator: isLiked, isPinned: isPinned,
            replies: replies, replyContinuation: replyContinuation
        )
    }

    private static func parseCommentThreads(_ items: [Any], limit: Int) -> (comments: [VideoComment], continuation: String?) {
        var comments = [VideoComment]()
        var continuation: String? = nil
        for item in items {
            if comments.count >= limit { break }
            guard let itemDict = item as? [String: Any] else { continue }
            if let token = (itemDict["continuationItemRenderer"] as? [String: Any])
                .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                .flatMap({ $0["continuationCommand"] as? [String: Any] })
                .flatMap({ $0["token"] as? String }) {
                continuation = token
            }
            guard let ctr = itemDict["commentThreadRenderer"] as? [String: Any],
                  let cr = (ctr["comment"] as? [String: Any])?["commentRenderer"] as? [String: Any] else { continue }
            comments.append(parseCommentRenderer(cr))
        }
        return (comments, continuation)
    }

    // MARK: - Public: Comments

    public static func getComments(videoId: String, limit: Int = 20, continuation: String? = nil) async throws -> (comments: [VideoComment], continuation: String?) {
        let capped = min(max(1, limit), 100)
        let html = try await httpGet("\(watchBase)\(videoId)")
        let apiKey = extractApiKey(from: html) ?? defaultAPIKey
        let ctx = extractJson(from: html, prefix: "\"INNERTUBE_CONTEXT\"") ?? defaultContextDict

        if let cont = continuation {
            let bodyDict: [String: Any] = ["context": ctx, "continuation": cont]
            let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
            guard let bodyStr = String(data: bodyData, encoding: .utf8) else { throw Error.missingData }
            let respText = try await httpPost("https://www.youtube.com/youtubei/v1/next?key=\(apiKey)", body: bodyStr)
            guard let respData = respText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
                return ([], nil)
            }
            let items = ((json["onResponseReceivedEndpoints"] as? [Any])?.first as? [String: Any])
                .flatMap { ($0["reloadContinuationItemsCommand"] as? [String: Any])?["continuationItems"] }
                ?? ((json["onResponseReceivedEndpoints"] as? [Any])?.first as? [String: Any])
                    .flatMap { ($0["appendContinuationItemsAction"] as? [String: Any])?["continuationItems"] }
            guard let items = items as? [Any] else { return ([], nil) }
            return parseCommentThreads(items, limit: capped)
        }

        guard let data = extractJson(from: html, prefix: "var ytInitialData") else { return ([], nil) }

        let allResults = (data["contents"] as? [String: Any])
            .flatMap { $0["twoColumnWatchNextResults"] as? [String: Any] }
            .flatMap { $0["results"] as? [String: Any] }
            .flatMap { $0["results"] as? [String: Any] }
            .flatMap { $0["contents"] as? [Any] }

        var token: String? = nil
        if let allResults = allResults {
            for c in allResults {
                guard let cDict = c as? [String: Any],
                      let ic = (cDict["itemSectionRenderer"] as? [String: Any])?["contents"] as? [Any] else { continue }
                for item in ic {
                    guard let itemDict = item as? [String: Any] else { continue }
                    token = (itemDict["continuationItemRenderer"] as? [String: Any])
                        .flatMap { $0["continuationEndpoint"] as? [String: Any] }
                        .flatMap { $0["continuationCommand"] as? [String: Any] }
                        .flatMap { $0["token"] as? String }
                    if token != nil { break }
                    token = ((itemDict["commentsEntryPointHeaderRenderer"] as? [String: Any])?["contents"] as? [Any])?.first
                        .flatMap { ($0 as? [String: Any])?["continuationItemRenderer"] as? [String: Any] }
                        .flatMap { $0["continuationEndpoint"] as? [String: Any] }
                        .flatMap { $0["continuationCommand"] as? [String: Any] }
                        .flatMap { $0["token"] as? String }
                    if token != nil { break }
                }
                if token != nil { break }
            }
        }
        guard let token = token else { return ([], nil) }

        let bodyDict: [String: Any] = ["context": ctx, "continuation": token]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        guard let bodyStr = String(data: bodyData, encoding: .utf8) else { throw Error.missingData }
        let respText = try await httpPost("https://www.youtube.com/youtubei/v1/next?key=\(apiKey)", body: bodyStr)
        guard let respData = respText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            return ([], nil)
        }

        let nItems: [Any]? = {
            let eps = json["onResponseReceivedEndpoints"] as? [Any]
            let first = eps?.first as? [String: Any]
            let second = eps?.dropFirst().first as? [String: Any]
            if let items = (first?["reloadContinuationItemsCommand"] as? [String: Any])?["continuationItems"] as? [Any] { return items }
            if let items = (first?["appendContinuationItemsAction"] as? [String: Any])?["continuationItems"] as? [Any] { return items }
            if let items = (second?["reloadContinuationItemsCommand"] as? [String: Any])?["continuationItems"] as? [Any] { return items }
            if let items = (second?["appendContinuationItemsAction"] as? [String: Any])?["continuationItems"] as? [Any] { return items }
            return nil
        }()
        guard let nItems = nItems else { return ([], nil) }
        return parseCommentThreads(nItems, limit: capped)
    }

    // MARK: - Public: Related Videos

    public static func getRelatedVideos(_ videoId: String, limit: Int = 15) async throws -> [RelatedVideo] {
        let capped = min(max(1, limit), 50)
        let html = try await httpGet("\(watchBase)\(videoId)")
        guard let data = extractJson(from: html, prefix: "var ytInitialData") else { return [] }

        let watchNext = (data["contents"] as? [String: Any])
            .flatMap { $0["twoColumnWatchNextResults"] as? [String: Any] }
            .flatMap { $0["secondaryResults"] as? [String: Any] }
            .flatMap { $0["secondaryResults"] as? [String: Any] }
            .flatMap { $0["results"] as? [Any] }
        guard let watchNext = watchNext else { return [] }

        var results = [RelatedVideo]()
        for item in watchNext {
            if results.count >= capped { break }
            guard let itemDict = item as? [String: Any],
                  let vr = (itemDict["compactVideoRenderer"] as? [String: Any])
                    ?? (itemDict["compactRadioRenderer"] as? [String: Any]),
                  let vid = vr["videoId"] as? String, !vid.isEmpty else { continue }

            let title = extractRuns((vr["title"] as? [String: Any])?["runs"])
                .ifEmpty(or: (vr["title"] as? [String: Any])?["simpleText"] as? String ?? "")
            let author = extractRuns((vr["shortBylineText"] as? [String: Any])?["runs"])
                .ifEmpty(or: (vr["shortBylineText"] as? [String: Any])?["simpleText"] as? String ?? "")
            let durText = extractSimpleOrRuns(vr["lengthText"] as? [String: Any])
            let (duration, durationSeconds) = parseDuration(durText)
            let viewsText = extractSimpleOrRuns(vr["viewCountText"] as? [String: Any])
            let viewCountRaw = parseViewCount(viewsText)
            let publishedTime = (vr["publishedTimeText"] as? [String: Any])?["simpleText"] as? String ?? ""
            let thumbnail = extractBestThumbnail(parseThumbnails((vr["thumbnail"] as? [String: Any])?["thumbnails"]))
                .ifEmpty(or: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg")
            let badge = ((vr["badges"] as? [Any])?.first as? [String: Any])
                .flatMap { $0["metadataBadgeRenderer"] as? [String: Any] }
                .flatMap { $0["style"] as? String } ?? ""

            results.append(RelatedVideo(
                id: vid, title: title, author: author,
                channelUrl: ((vr["shortBylineText"] as? [String: Any])?["runs"] as? [Any])?.first
                    .flatMap { ($0 as? [String: Any])?["navigationEndpoint"] as? [String: Any] }
                    .flatMap { ($0["browseEndpoint"] as? [String: Any])?["canonicalBaseUrl"] as? String } ?? "",
                duration: duration, durationSeconds: durationSeconds,
                viewCount: viewsText, viewCountRaw: viewCountRaw,
                publishedTime: publishedTime, thumbnail: thumbnail,
                isLive: badge.lowercased().contains("live")
            ))
        }
        return results
    }

    // MARK: - Public: Video Stats

    public static func getVideoStats(_ videoId: String) async throws -> (views: Int, likes: Int, comments: Int, isLive: Bool, viewerCount: Int) {
        let html = try await httpGet("\(watchBase)\(videoId)")
        guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
            return (0, 0, 0, false, 0)
        }

        let contents = (data["contents"] as? [String: Any])
            .flatMap { $0["twoColumnWatchNextResults"] as? [String: Any] }
            .flatMap { $0["results"] as? [String: Any] }
            .flatMap { $0["results"] as? [String: Any] }
            .flatMap { $0["contents"] as? [Any] }

        var primary: [String: Any]?
        for c in contents ?? [] {
            guard let cDict = c as? [String: Any],
                  let p = cDict["videoPrimaryInfoRenderer"] as? [String: Any] else { continue }
            primary = p
            break
        }

        let vcr = (primary?["viewCount"] as? [String: Any])?["videoViewCountRenderer"] as? [String: Any]
        let viewsText = (vcr?["shortViewCount"] as? [String: Any])?["simpleText"] as? String
            ?? (vcr?["viewCount"] as? [String: Any])?["simpleText"] as? String ?? ""
        let views = parseViewCount(viewsText)

        let likesStr = ((((((((primary?["videoActions"] as? [String: Any])?["menuRenderer"] as? [String: Any])?["topLevelButtons"] as? [Any])?.first as? [String: Any])?["segmentedLikeDislikeButtonViewModel"] as? [String: Any])?["likeButtonViewModel"] as? [String: Any])?["likeButtonViewModel"] as? [String: Any])?["toggleButtonViewModel"] as? [String: Any])?["toggleButtonViewModel"] as? [String: Any])?["defaultButtonViewModel"] as? [String: Any])?["buttonViewModel"] as? [String: Any])?["accessibilityText"] as? String ?? ""
        let allowed = CharacterSet(charactersIn: "0123456789.KMBkmb")
        let likes = parseViewCount(String(likesStr.unicodeScalars.filter { allowed.contains($0) }))

        let isLive = html.contains("\"isLive\":true")
        var viewerCount = 0
        if let range = html.range(of: "\"viewCount\":{\"videoViewCountRenderer\":{\"isLive\":true,\"viewCount\":{\"simpleText\":\""),
           let after = html[range.upperBound...].split(separator: "\"").first {
            viewerCount = parseViewCount(String(after))
        }

        return (views, Int(likes), 0, isLive, Int(viewerCount))
    }

    public static func getLiveStreamInfo(_ videoId: String) async throws -> LiveStreamInfo {
        let (_, likes, _, isLive, viewerCount) = try await getVideoStats(videoId)
        do {
            let html = try await httpGet("\(watchBase)\(videoId)")
            guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
                return LiveStreamInfo(isLive: isLive, isUpcoming: false, viewerCount: viewerCount,
                                       viewerCountStr: "\(viewerCount)", startTime: "", scheduledStartTime: "",
                                       likesCount: likes, dislikesCount: 0)
            }
            let contents = (data["contents"] as? [String: Any])
                .flatMap { $0["twoColumnWatchNextResults"] as? [String: Any] }
                .flatMap { $0["results"] as? [String: Any] }
                .flatMap { $0["results"] as? [String: Any] }
                .flatMap { $0["contents"] as? [Any] }
            var primary: [String: Any]?
            for c in contents ?? [] {
                guard let cDict = c as? [String: Any],
                      let p = cDict["videoPrimaryInfoRenderer"] as? [String: Any] else { continue }
                primary = p
                break
            }
            return LiveStreamInfo(
                isLive: isLive,
                isUpcoming: !isLive && viewerCount == 0,
                viewerCount: viewerCount,
                viewerCountStr: "\(viewerCount)",
                startTime: (primary?["dateText"] as? [String: Any])?["simpleText"] as? String ?? "",
                scheduledStartTime: (primary?["upcomingEventData"] as? [String: Any])?["startTime"] as? String ?? "",
                likesCount: likes,
                dislikesCount: 0
            )
        } catch {
            return LiveStreamInfo(isLive: isLive, isUpcoming: false, viewerCount: viewerCount,
                                   viewerCountStr: "\(viewerCount)", startTime: "", scheduledStartTime: "",
                                   likesCount: likes, dislikesCount: 0)
        }
    }

    // MARK: - Channel Metadata

    public struct SocialLink: Codable {
        public var title: String
        public var url: String
        public var icon: String
    }

    public struct ChannelMetadata: Codable {
        public var id: String
        public var name: String
        public var handle: String
        public var description: String
        public var subscriberCount: String
        public var subscriberCountRaw: Int
        public var videoCount: String
        public var videoCountRaw: Int
        public var avatar: String
        public var banner: String
        public var isVerified: Bool
        public var socialLinks: [SocialLink]
        public var url: String
    }

    public static func getChannelMetadata(_ channelId: String) async throws -> ChannelMetadata {
        let empty = ChannelMetadata(
            id: channelId, name: "", handle: "", description: "",
            subscriberCount: "", subscriberCountRaw: 0, videoCount: "", videoCountRaw: 0,
            avatar: "", banner: "", isVerified: false, socialLinks: [],
            url: "https://www.youtube.com/channel/\(channelId)"
        )

        do {
            guard let encoded = channelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return empty
            }
            let html = try await httpGet("https://www.youtube.com/channel/\(encoded)/about")
            guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
                return empty
            }

            let metadata = (data["metadata"] as? [String: Any])?["channelMetadataRenderer"] as? [String: Any]
            let header = (data["header"] as? [String: Any])?["c4TabbedHeaderRenderer"] as? [String: Any]

            var aboutRenderer: [String: Any]?
            if let tabs = ((data["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any])?["tabs"] as? [Any] {
                for tab in tabs {
                    guard let tabDict = tab as? [String: Any],
                          let tabRenderer = tabDict["tabRenderer"] as? [String: Any],
                          let selected = tabRenderer["selected"] as? Bool, selected else { continue }
                    aboutRenderer = (tabRenderer["content"] as? [String: Any])
                        .flatMap { $0["sectionListRenderer"] as? [String: Any] }
                        .flatMap { $0["contents"] as? [Any] }?.first as? [String: Any]
                        .flatMap { $0["itemSectionRenderer"] as? [String: Any] }
                        .flatMap { $0["contents"] as? [Any] }?.first as? [String: Any]
                        .flatMap { $0["channelAboutFullMetadataRenderer"] as? [String: Any] }
                    break
                }
            }

            let subText = (header?["subscriberCountText"] as? [String: Any])?["simpleText"] as? String ?? ""
            let subsRaw = parseViewCount(subText)

            let videoText = ((aboutRenderer?["videoCountText"] as? [String: Any])?["runs"] as? [Any])?.first
                .flatMap { ($0 as? [String: Any])?["text"] as? String } ?? ""
            var vcRaw = 0
            if let match = videoText.firstMatch(of: try! Regex("([\\d,]+)")) {
                vcRaw = Int(match.output.1?.replacing(",", with: "") ?? "") ?? 0
            }

            var links = [SocialLink]()
            if let primaryLinks = aboutRenderer?["primaryLinks"] as? [Any] {
                for l in primaryLinks {
                    guard let lDict = l as? [String: Any] else { continue }
                    let nav = (lDict["navigationEndpoint"] as? [String: Any])?["urlEndpoint"] as? [String: Any]
                    links.append(SocialLink(
                        title: ((lDict["title"] as? [String: Any])?["simpleText"] as? String)
                            ?? ((lDict["title"] as? [String: Any])?["runs"] as? [Any])?.first
                                .flatMap { ($0 as? [String: Any])?["text"] as? String } ?? "",
                        url: nav?["url"] as? String ?? "",
                        icon: (((lDict["icon"] as? [String: Any])?["thumbnails"] as? [Any])?.first as? [String: Any])?["url"] as? String ?? ""
                    ))
                }
            }

            let name = (metadata?["title"] as? String) ?? (header?["title"] as? String) ?? ""
            let vanityUrl = metadata?["vanityChannelUrl"] as? String ?? ""
            let handle = vanityUrl
                .replacingOccurrences(of: "http://www.youtube.com/", with: "")
                .replacingOccurrences(of: "https://www.youtube.com/", with: "")

            let desc = (metadata?["description"] as? String)
                ?? ((aboutRenderer?["description"] as? [String: Any])?["simpleText"] as? String)
                ?? extractRuns((aboutRenderer?["description"] as? [String: Any])?["runs"])

            let avatarThumbs = (metadata?["avatar"] as? [String: Any])?["thumbnails"]
                ?? (header?["avatar"] as? [String: Any])?["thumbnails"]
            let avatar = extractBestThumbnail(parseThumbnails(avatarThumbs))

            let bannerThumbs = (metadata?["banner"] as? [String: Any])?["thumbnails"]
                ?? (header?["banner"] as? [String: Any])?["thumbnails"]
            let banner = extractBestThumbnail(parseThumbnails(bannerThumbs))

            var isVerified = false
            if let badges = header?["badges"] as? [Any] {
                for badge in badges {
                    guard let bDict = badge as? [String: Any],
                          let renderer = bDict["metadataBadgeRenderer"] as? [String: Any],
                          let style = renderer["style"] as? String,
                          style.contains("VERIFIED") else { continue }
                    isVerified = true
                    break
                }
            }

            return ChannelMetadata(
                id: channelId, name: name, handle: handle, description: desc,
                subscriberCount: subText, subscriberCountRaw: Int(subsRaw),
                videoCount: videoText, videoCountRaw: vcRaw,
                avatar: avatar, banner: banner, isVerified: isVerified,
                socialLinks: links,
                url: "https://www.youtube.com/channel/\(channelId)"
            )
        } catch {
            return empty
        }
    }

    // MARK: - Transcript

    public struct TranscriptEntry: Codable {
        public var text: String
        public var start: Double
        public var duration: Double
    }

    public static func getTranscript(_ videoId: String, lang: String? = nil) async throws -> [TranscriptEntry] {
        do {
            let html = try await httpGet("\(watchBase)\(videoId)")

            let tracksStr: String?
            if let pattern = try? Regex("\"captionTracks\":\\s*(\\[[^\\]]*\\{[^}]*\"baseUrl\":\"([^\"]+)\"[^}]*\\}[^\\]]*\\])"),
               let match = html.firstMatch(of: pattern) {
                tracksStr = String(html[match.range])
            } else if let pattern = try? Regex("\"captions\":\\{[^}]*\"playerCaptionsTracklistRenderer\":\\{[^}]*\"captionTracks\":(\\[[^\\]]*\\])"),
                      match = html.firstMatch(of: pattern) {
                tracksStr = String(html[match.range])
            } else {
                return []
            }

            guard let tracksStr = tracksStr,
                  let data = tracksStr.data(using: .utf8),
                  let tracks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }

            var trackUrl = ""
            if let lang = lang {
                for track in tracks {
                    let lc = track["languageCode"] as? String ?? ""
                    let tn = (track["name"] as? [String: Any])?["simpleText"] as? String ?? ""
                    if lc == lang || tn.lowercased().contains(lang.lowercased()) {
                        trackUrl = track["baseUrl"] as? String ?? ""
                        break
                    }
                }
            }
            if trackUrl.isEmpty {
                trackUrl = tracks.first(where: { ($0["languageCode"] as? String) == "en" })?["baseUrl"] as? String
                    ?? tracks.first?["baseUrl"] as? String ?? ""
            }
            if trackUrl.isEmpty { return [] }

            let xml = try await httpGet(trackUrl)
            var entries = [TranscriptEntry]()

            if let pattern = try? Regex("<text start=\"([\\d.]+)\" dur=\"([\\d.]+)\"[^>]*>(.*?)(?:</text>)?$"),
               let _ = try? pattern as Regex<AnyRegexOutput> {
                let lines = xml.components(separatedBy: "\n")
                for line in lines {
                    guard let match = line.firstMatch(of: pattern) else { continue }
                    let captures = match.output
                    let startStr = String(describing: captures[1].value ?? "")
                    let durStr = String(describing: captures[2].value ?? "")
                    var text = String(describing: captures[3].value ?? "")
                    text = text.replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&#39;", with: "'")
                    text = text.replacing(try! Regex("<[^>]+>"), with: "")
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    entries.append(TranscriptEntry(
                        text: trimmed,
                        start: Double(startStr) ?? 0,
                        duration: Double(durStr) ?? 0
                    ))
                }
            }
            return entries
        } catch {
            return []
        }
    }

    // MARK: - Shorts Search

    public static func searchShorts(_ query: String, limit: Int = 15, gl: String? = nil, hl: String? = nil) async throws -> SearchResponse {
        let capped = min(max(1, limit), 50)
        var region = ""
        if let gl = gl { region += "&gl=\(gl)" }
        if let hl = hl { region += "&hl=\(hl)" }

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw Error.invalidURL
        }

        let html = try await httpGet("\(searchURL)\(encoded)&sp=EgIYAQ%3D%3D\(region)")
        guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
            return SearchResponse(results: [], continuation: nil, apiKey: nil)
        }

        let key = extractApiKey(from: html)

        let contents = ((data["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"] as? [String: Any])
            .flatMap { $0["primaryContents"] as? [String: Any] }
            .flatMap { $0["sectionListRenderer"] as? [String: Any] }
            .flatMap { $0["contents"] as? [Any] }

        var reelItems: [Any]?
        if let contents = contents {
            for section in contents {
                guard let sectionDict = section as? [String: Any],
                      let isContents = (sectionDict["itemSectionRenderer"] as? [String: Any])?["contents"] as? [Any],
                      let firstItem = isContents.first as? [String: Any],
                      let reelShelf = firstItem["reelShelfRenderer"] as? [String: Any] else { continue }
                reelItems = reelShelf["items"] as? [Any]
                break
            }
        }

        if let reelItems = reelItems {
            var shortResults = [VideoResult]()
            for item in reelItems {
                if shortResults.count >= capped { break }
                guard let itemDict = item as? [String: Any] else { continue }
                let ri = (itemDict["reelItemRenderer"] as? [String: Any])
                    ?? (itemDict["shortsLockupViewModel"] as? [String: Any])
                let vid = (ri?["videoId"] as? String)
                    ?? ((itemDict["reelItemRenderer"] as? [String: Any])?["videoId"] as? String)
                guard let vid = vid, !vid.isEmpty else { continue }

                let title = ((ri?["headline"] as? [String: Any])?["simpleText"] as? String)
                    ?? extractRuns((ri?["headline"] as? [String: Any])?["runs"])
                let durSec = Int(((ri?["lengthText"] as? [String: Any])?["simpleText"] as? String) ?? "0") ?? 0

                let fb = fallbackResult(id: vid)
                shortResults.append(VideoResult(
                    id: vid,
                    title: (title ?? "").isEmpty ? "Shorts \(vid)" : (title ?? ""),
                    author: fb.author, channelUrl: fb.channelUrl,
                    thumbnail: fb.thumbnail, thumbnails: fb.thumbnails,
                    fullUrl: fb.fullUrl, embedUrl: fb.embedUrl,
                    duration: "\(durSec)s", durationSeconds: durSec,
                    viewCount: fb.viewCount, viewCountRaw: fb.viewCountRaw,
                    publishedTime: fb.publishedTime, description: fb.description,
                    channelAvatar: fb.channelAvatar,
                    isLive: false, isUpcoming: false, isVerified: false
                ))
            }

            let (allResults, continuation) = parseSearchResults(data, limit: capped)
            var seen = Set<String>()
            var combined = [VideoResult]()
            for r in shortResults {
                if seen.insert(r.id).inserted { combined.append(r) }
            }
            for r in allResults {
                if seen.insert(r.id).inserted, combined.count < capped { combined.append(r) }
            }
            return SearchResponse(results: combined, continuation: continuation, apiKey: key)
        }

        let (rawResults, continuation) = parseSearchResults(data, limit: capped)
        return SearchResponse(results: rawResults, continuation: continuation, apiKey: key)
    }

    // MARK: - Global Cache

    public static let globalCache = LRUCache<String>(maxSize: 500, ttlMs: 300_000)

    // MARK: - Client Factory

    public struct Client {
        public let search: (String, Int) async throws -> SearchResponse
        public let searchTrending: (Int) async throws -> [VideoResult]
        public let searchChannel: (String, Int) async throws -> [VideoResult]
        public let searchPlaylist: (String, Int) async throws -> [VideoResult]
        public let searchContinue: (String, Int, String?, [String: Any]?, String) async throws -> SearchResponse
        public let getVideo: (String) async throws -> VideoResult
        public let getComments: (String, Int, String?) async throws -> (comments: [VideoComment], continuation: String?)
        public let getRelatedVideos: (String, Int) async throws -> [RelatedVideo]
        public let getVideoStats: (String) async throws -> (views: Int, likes: Int, comments: Int, isLive: Bool, viewerCount: Int)
        public let getLiveStreamInfo: (String) async throws -> LiveStreamInfo
        public let getChannelMetadata: (String) async throws -> ChannelMetadata
        public let getTranscript: (String, String?) async throws -> [TranscriptEntry]
        public let searchShorts: (String, Int) async throws -> SearchResponse
        public let cache: LRUCache<String>
    }

    public static func createClient(cache: LRUCache<String>? = nil, retry: Bool = true, maxRetries: Int = 3) -> Client {
        return Client(
            search: { q, l in try await search(query: q, limit: l) },
            searchTrending: { l in try await searchTrending(limit: l) },
            searchChannel: { cid, l in try await searchChannel(cid, limit: l) },
            searchPlaylist: { pid, l in try await searchPlaylist(pid, limit: l) },
            searchContinue: { cont, l, ak, ctx, p in try await searchContinue(continuation: cont, limit: l, apiKey: ak, context: ctx, path: p) },
            getVideo: { id in try await getVideo(id: id) },
            getComments: { vid, l, c in try await getComments(videoId: vid, limit: l, continuation: c) },
            getRelatedVideos: { vid, l in try await getRelatedVideos(vid, limit: l) },
            getVideoStats: { vid in try await getVideoStats(vid) },
            getLiveStreamInfo: { vid in try await getLiveStreamInfo(vid) },
            getChannelMetadata: { cid in try await getChannelMetadata(cid) },
            getTranscript: { vid, lang in try await getTranscript(vid, lang: lang) },
            searchShorts: { q, l in try await searchShorts(q, limit: l) },
            cache: cache ?? globalCache
        )
    }
}

private extension String {
    func ifEmpty(or default: String) -> String {
        isEmpty ? `default` : self
    }
}
                    }
                }

                if let token = (sectionDict["continuationItemRenderer"] as? [String: Any])
                    .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                    .flatMap({ $0["continuationCommand"] as? [String: Any] })
                    .flatMap({ $0["token"] as? String }),
                    !token.isEmpty
                {
                    continuation = token
                }
            }

            if !results.isEmpty { break }
        }

        return (results, continuation)
    }

    private static func parseChannelResults(
        _ data: [String: Any],
        limit: Int
    ) -> (results: [VideoResult], continuation: String?) {
        var results = [VideoResult]()
        var continuation: String?

        guard let tabs = (data["contents"] as? [String: Any])
                .flatMap({ $0["twoColumnBrowseResultsRenderer"] as? [String: Any] })
                .flatMap({ $0["tabs"] as? [Any] })
        else { return (results, continuation) }

        for tab in tabs {
            guard let tabDict = tab as? [String: Any],
                  let content = (tabDict["tabRenderer"] as? [String: Any])?["content"] as? [String: Any]
            else { continue }

            let items = (content["richGridRenderer"] as? [String: Any])?["contents"] as? [Any]
                ?? (content["sectionListRenderer"] as? [String: Any])?["contents"] as? [Any]
            guard let items = items else { continue }

            for item in items {
                if results.count >= limit { break }
                guard let itemDict = item as? [String: Any] else { continue }

                if let token = (itemDict["continuationItemRenderer"] as? [String: Any])
                    .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                    .flatMap({ $0["continuationCommand"] as? [String: Any] })
                    .flatMap({ $0["token"] as? String }),
                    !token.isEmpty
                {
                    continuation = token
                }

                var vrMap = itemDict["videoRenderer"] as? [String: Any]
                if vrMap == nil, let rir = itemDict["richItemRenderer"] as? [String: Any],
                   let riContent = rir["content"] as? [String: Any] {
                    vrMap = riContent["videoRenderer"] as? [String: Any]
                }
                if let vrMap = vrMap, let parsed = parseVideoRenderer(vrMap) {
                    results.append(parsed)
                }
            }

            if !results.isEmpty { break }
        }

        return (results, continuation)
    }

    private static func parsePlaylistResults(
        _ data: [String: Any],
        limit: Int
    ) -> (results: [VideoResult], continuation: String?) {
        var results = [VideoResult]()
        var continuation: String?

        var contents = (data["contents"] as? [String: Any])
            .flatMap({ $0["twoColumnBrowseResultsRenderer"] as? [String: Any] })
            .flatMap({ $0["tabs"] as? [Any] })?.first as? [String: Any]
            .flatMap({ $0["tabRenderer"] as? [String: Any] })
            .flatMap({ $0["content"] as? [String: Any] })
            .flatMap({ $0["sectionListRenderer"] as? [String: Any] })
            .flatMap({ $0["contents"] as? [Any] })?.first as? [String: Any]
            .flatMap({ $0["itemSectionRenderer"] as? [String: Any] })
            .flatMap({ $0["contents"] as? [Any] })?.first as? [String: Any]
            .flatMap({ $0["playlistVideoListRenderer"] as? [String: Any] })
            .flatMap({ $0["contents"] as? [Any] })

        if contents == nil {
            contents = (data["contents"] as? [String: Any])
                .flatMap({ $0["twoColumnWatchNextResults"] as? [String: Any] })
                .flatMap({ $0["playlist"] as? [String: Any] })
                .flatMap({ $0["playlist"] as? [String: Any] })
                .flatMap({ $0["contents"] as? [Any] })
        }

        guard let items = contents else { return (results, continuation) }

        for item in items {
            if results.count >= limit { break }
            guard let itemDict = item as? [String: Any] else { continue }

            if let token = (itemDict["continuationItemRenderer"] as? [String: Any])
                .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                .flatMap({ $0["continuationCommand"] as? [String: Any] })
                .flatMap({ $0["token"] as? String }),
                !token.isEmpty
            {
                continuation = token
            }

            guard let pvr = itemDict["playlistVideoRenderer"] as? [String: Any],
                  let vid = pvr["videoId"] as? String, !vid.isEmpty
            else { continue }

            let title = extractRuns((pvr["title"] as? [String: Any])?["runs"])
            let author = extractRuns((pvr["shortBylineText"] as? [String: Any])?["runs"])
            let durText = extractSimpleOrRuns(pvr["lengthText"] as? [String: Any])
            let (duration, durationSeconds) = parseDuration(durText)
            let fb = fallbackResult(id: vid)

            results.append(VideoResult(
                id: vid,
                title: title.isEmpty ? fb.title : title,
                author: author.isEmpty ? fb.author : author,
                duration: duration,
                durationSeconds: durationSeconds,
                thumbnail: fb.thumbnail,
                thumbnails: fb.thumbnails,
                fullUrl: fb.fullUrl,
                embedUrl: fb.embedUrl
            ))
        }

        return (results, continuation)
    }

    // MARK: - Public API: Trending / Channel / Playlist

    public static func searchTrending(limit: Int = 15) async throws -> [VideoResult] {
        let capped = min(max(1, limit), 50)
        let html = try await httpGet("https://www.youtube.com/feed/trending")
        guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
            return []
        }
        let (rawResults, _) = parseTrendingResults(data, limit: capped)
        return rawResults
    }

    public static func searchChannel(_ channelId: String, limit: Int = 15) async throws -> [VideoResult] {
        let capped = min(max(1, limit), 50)
        guard let encoded = channelId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw Error.invalidURL
        }
        let html = try await httpGet("https://www.youtube.com/channel/\(encoded)/videos")
        guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
            return []
        }
        let (rawResults, _) = parseChannelResults(data, limit: capped)

        let needsEnrichment = rawResults.filter {
            $0.title.isEmpty || $0.title == "Video \($0.id)" || $0.author == "YouTube"
        }
        if needsEnrichment.isEmpty { return rawResults }

        let enrichedMap = await withTaskGroup(
            of: (String, String, String, String).self,
            returning: [String: (String, String, String)].self
        ) { group in
            for video in needsEnrichment {
                group.addTask {
                    let (title, author, thumbnail) = await fetchOembed(id: video.id)
                    return (video.id, title, author, thumbnail)
                }
            }
            var result: [String: (String, String, String)] = [:]
            for await (id, title, author, thumbnail) in group {
                result[id] = (title, author, thumbnail)
            }
            return result
        }

        return rawResults.map { video in
            guard let (title, author, thumbnail) = enrichedMap[video.id] else { return video }
            return VideoResult(
                id: video.id,
                title: title.isEmpty ? video.title : title,
                author: author.isEmpty ? video.author : author,
                channelUrl: video.channelUrl,
                thumbnail: (!thumbnail.isEmpty && thumbnail != video.thumbnail) ? thumbnail : video.thumbnail,
                thumbnails: video.thumbnails,
                fullUrl: video.fullUrl, embedUrl: video.embedUrl,
                duration: video.duration, durationSeconds: video.durationSeconds,
                viewCount: video.viewCount, viewCountRaw: video.viewCountRaw,
                publishedTime: video.publishedTime, description: video.description,
                channelAvatar: video.channelAvatar,
                isLive: video.isLive, isUpcoming: video.isUpcoming, isVerified: video.isVerified
            )
        }
    }

    public static func searchPlaylist(_ playlistId: String, limit: Int = 15) async throws -> [VideoResult] {
        let capped = min(max(1, limit), 50)
        guard let encoded = playlistId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw Error.invalidURL
        }
        let html = try await httpGet("https://www.youtube.com/playlist?list=\(encoded)")
        guard let data = extractJson(from: html, prefix: "var ytInitialData") else {
            return []
        }
        let (rawResults, _) = parsePlaylistResults(data, limit: capped)

        let needsEnrichment = rawResults.filter {
            $0.title.isEmpty || $0.title == "Video \($0.id)" || $0.author == "YouTube"
        }
        if needsEnrichment.isEmpty { return rawResults }

        let enrichedMap = await withTaskGroup(
            of: (String, String, String, String).self,
            returning: [String: (String, String, String)].self
        ) { group in
            for video in needsEnrichment {
                group.addTask {
                    let (title, author, thumbnail) = await fetchOembed(id: video.id)
                    return (video.id, title, author, thumbnail)
                }
            }
            var result: [String: (String, String, String)] = [:]
            for await (id, title, author, thumbnail) in group {
                result[id] = (title, author, thumbnail)
            }
            return result
        }

        return rawResults.map { video in
            guard let (title, author, thumbnail) = enrichedMap[video.id] else { return video }
            return VideoResult(
                id: video.id,
                title: title.isEmpty ? video.title : title,
                author: author.isEmpty ? video.author : author,
                channelUrl: video.channelUrl,
                thumbnail: (!thumbnail.isEmpty && thumbnail != video.thumbnail) ? thumbnail : video.thumbnail,
                thumbnails: video.thumbnails,
                fullUrl: video.fullUrl, embedUrl: video.embedUrl,
                duration: video.duration, durationSeconds: video.durationSeconds,
                viewCount: video.viewCount, viewCountRaw: video.viewCountRaw,
                publishedTime: video.publishedTime, description: video.description,
                channelAvatar: video.channelAvatar,
                isLive: video.isLive, isUpcoming: video.isUpcoming, isVerified: video.isVerified
            )
        }
    }
}
                    return obj
                }
            }
            idx += 1
        }
        return nil
    }

    // MARK: - Private Helpers

    private static func httpGet(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else { throw Error.httpError(httpResponse.statusCode) }
        guard let str = String(data: data, encoding: .utf8) else { throw Error.missingData }
        return str
    }

    private static func httpPost(_ urlString: String, body: String) async throws -> String {
        guard let url = URL(string: urlString) else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else { throw Error.httpError(httpResponse.statusCode) }
        guard let str = String(data: data, encoding: .utf8) else { throw Error.missingData }
        return str
    }

    private static func fallbackResult(id: String) -> VideoResult {
        let thumb = "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
        return VideoResult(
            id: id,
            title: "Video \(id)",
            author: "YouTube",
            channelUrl: "",
            thumbnail: thumb,
            thumbnails: [Thumbnail(url: thumb, width: 480, height: 360)],
            fullUrl: "\(watchBase)\(id)",
            embedUrl: "\(embedBase)\(id)?rel=0",
            duration: "",
            durationSeconds: 0,
            viewCount: "",
            viewCountRaw: 0,
            publishedTime: "",
            description: "",
            channelAvatar: "",
            isLive: false,
            isUpcoming: false,
            isVerified: false
        )
    }

    private static func fetchOembed(id: String) async -> (title: String, author: String, thumbnail: String) {
        let url = "\(oembedURL)\(id)&format=json"
        do {
            let jsonStr = try await httpGet(url)
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (
                    json["title"] as? String ?? "",
                    json["author_name"] as? String ?? "",
                    json["thumbnail_url"] as? String ?? ""
                )
            }
        } catch {}
        return ("", "", "")
    }

    private static func parseVideoRenderer(_ vr: [String: Any]) -> VideoResult? {
        guard let id = vr["videoId"] as? String, !id.isEmpty else { return nil }

        let title = extractRuns((vr["title"] as? [String: Any])?["runs"])
        let byline = vr["longBylineText"] as? [String: Any] ?? vr["shortBylineText"] as? [String: Any]
        let author = extractRuns(byline?["runs"])

        let channelUrl = extractChannelUrl(byline?["runs"])

        let thumbnails = parseThumbnails((vr["thumbnail"] as? [String: Any])?["thumbnails"])
        let bestThumb = extractBestThumbnail(thumbnails)

        let durText = extractSimpleOrRuns(vr["lengthText"] as? [String: Any])
        let (duration, durationSeconds) = parseDuration(durText)

        let viewCountText = extractSimpleOrRuns(vr["viewCountText"] as? [String: Any])
        let viewCountRaw = parseViewCount(viewCountText)
        let viewCount = viewCountText.isEmpty ? "" : viewCountText

        let publishedTime = (vr["publishedTimeText"] as? [String: Any])?["simpleText"] as? String ?? ""

        let description: String
        if let detailedSnippets = vr["detailedMetadataSnippets"] as? [Any],
           let firstSnip = detailedSnippets.first as? [String: Any],
           let snippetText = firstSnip["snippetText"] as? [String: Any] {
            description = extractRuns(snippetText["runs"])
        } else if let descSnippet = vr["descriptionSnippet"] as? [String: Any] {
            description = extractRuns(descSnippet["runs"])
        } else {
            description = ""
        }

        let channelThumbs = (vr["channelThumbnailSupportedRenderers"] as? [String: Any])
            .flatMap { $0["channelThumbnailWithLinkRenderer"] as? [String: Any] }
            .flatMap { $0["thumbnail"] as? [String: Any] }
            .flatMap { $0["thumbnails"] as? [Any] }
        let channelAvatar = extractBestThumbnail(parseThumbnails(channelThumbs))

        let badges = parseBadges(vr["badges"] as? [Any])
        let isLive = badges.contains("LIVE")
        let isUpcoming = badges.contains("UPCOMING")
        let isVerified = parseVerified(vr["ownerBadges"] as? [Any])

        let fb = fallbackResult(id: id)

        return VideoResult(
            id: id,
            title: title.isEmpty ? fb.title : title,
            author: author.isEmpty ? fb.author : author,
            channelUrl: channelUrl.isEmpty ? fb.channelUrl : channelUrl,
            thumbnail: bestThumb.isEmpty ? fb.thumbnail : bestThumb,
            thumbnails: thumbnails.isEmpty ? fb.thumbnails : thumbnails,
            fullUrl: fb.fullUrl,
            embedUrl: fb.embedUrl,
            duration: duration,
            durationSeconds: durationSeconds,
            viewCount: viewCount,
            viewCountRaw: viewCountRaw,
            publishedTime: publishedTime,
            description: description,
            channelAvatar: channelAvatar,
            isLive: isLive,
            isUpcoming: isUpcoming,
            isVerified: isVerified
        )
    }

    private static func parseSearchResults(
        _ data: [String: Any],
        limit: Int
    ) -> (results: [VideoResult], continuation: String?) {
        var results = [VideoResult]()
        var continuation: String?

        guard let contents = (data["contents"] as? [String: Any])
                .flatMap({ $0["twoColumnSearchResultsRenderer"] as? [String: Any] })
                .flatMap({ $0["primaryContents"] as? [String: Any] })
                .flatMap({ $0["sectionListRenderer"] as? [String: Any] })
                .flatMap({ $0["contents"] as? [Any] })
        else { return (results, continuation) }

        for section in contents {
            if results.count >= limit { break }
            guard let sectionDict = section as? [String: Any] else { continue }

            if let items = (sectionDict["itemSectionRenderer"] as? [String: Any])?["contents"] as? [Any] {
                for item in items {
                    if results.count >= limit { break }
                    guard let itemDict = item as? [String: Any],
                          let vr = itemDict["videoRenderer"] as? [String: Any],
                          let parsed = parseVideoRenderer(vr)
                    else { continue }
                    results.append(parsed)
                }
            }

            if let token = (sectionDict["continuationItemRenderer"] as? [String: Any])
                .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                .flatMap({ $0["continuationCommand"] as? [String: Any] })
                .flatMap({ $0["token"] as? String }),
                !token.isEmpty
            {
                continuation = token
            }
        }

        return (results, continuation)
    }

    private static func parseContinuationResults(
        _ data: [String: Any],
        limit: Int,
        path: String = "search"
    ) -> (results: [VideoResult], continuation: String?) {
        var results = [VideoResult]()
        var continuation: String?

        let items: [Any]?
        if path == "channel" {
            if let actions = data["onResponseReceivedActions"] as? [Any],
               let first = actions.first as? [String: Any],
               let action = first["appendContinuationItemsAction"] as? [String: Any] {
                items = action["continuationItems"] as? [Any]
            } else if let endpoints = data["onResponseReceivedEndpoints"] as? [Any],
                      let first = endpoints.first as? [String: Any],
                      let action = first["appendContinuationItemsAction"] as? [String: Any] {
                items = action["continuationItems"] as? [Any]
            } else {
                items = nil
            }
        } else if path == "playlist" {
            if let actions = data["onResponseReceivedActions"] as? [Any],
               let first = actions.first as? [String: Any],
               let action = first["appendContinuationItemsAction"] as? [String: Any] {
                items = action["continuationItems"] as? [Any]
            } else {
                items = nil
            }
        } else {
            if let endpoints = data["onResponseReceivedEndpoints"] as? [Any],
               let first = endpoints.first as? [String: Any],
               let action = first["appendContinuationItemsAction"] as? [String: Any] {
                items = action["continuationItems"] as? [Any]
            } else if let commands = data["onResponseReceivedCommands"] as? [Any],
                      let first = commands.first as? [String: Any],
                      let action = first["appendContinuationItemsAction"] as? [String: Any] {
                items = action["continuationItems"] as? [Any]
            } else {
                items = nil
            }
        }

        guard let continuationItems = items else { return (results, continuation) }

        for item in continuationItems {
            if results.count >= limit { break }
            guard let itemDict = item as? [String: Any] else { continue }

            if let token = (itemDict["continuationItemRenderer"] as? [String: Any])
                .flatMap({ $0["continuationEndpoint"] as? [String: Any] })
                .flatMap({ $0["continuationCommand"] as? [String: Any] })
                .flatMap({ $0["token"] as? String }),
                !token.isEmpty
            {
                continuation = token
            }

            if path == "playlist" {
                if let pvr = itemDict["playlistVideoRenderer"] as? [String: Any],
                   let vid = pvr["videoId"] as? String, !vid.isEmpty {
                    let title = extractRuns((pvr["title"] as? [String: Any])?["runs"])
                    let author = extractRuns((pvr["shortBylineText"] as? [String: Any])?["runs"])
                    let durText = extractSimpleOrRuns(pvr["lengthText"] as? [String: Any])
                    let (duration, durationSeconds) = parseDuration(durText)
                    let fb = fallbackResult(id: vid)
                    results.append(VideoResult(
                        id: vid, title: title.isEmpty ? fb.title : title,
                        author: author.isEmpty ? fb.author : author,
                        duration: duration, durationSeconds: durationSeconds,
                        thumbnail: fb.thumbnail, thumbnails: fb.thumbnails,
                        fullUrl: fb.fullUrl, embedUrl: fb.embedUrl
                    ))
                }
                continue
            }

            var vr = itemDict["videoRenderer"] as? [String: Any]
            if vr == nil, let rir = itemDict["richItemRenderer"] as? [String: Any],
               let content = rir["content"] as? [String: Any] {
                vr = content["videoRenderer"] as? [String: Any]
            }
            if let vr = vr, let parsed = parseVideoRenderer(vr) {
                results.append(parsed)
            }
        }

        return (results, continuation)
    }

    // MARK: - JSON Traversal Helpers

    private static func extractRuns(_ runs: Any?) -> String {
        guard let runs = runs as? [Any] else { return "" }
        var result = ""
        for run in runs {
            if let dict = run as? [String: Any], let text = dict["text"] as? String {
                result += text
            }
        }
        return result
    }

    private static func extractSimpleOrRuns(_ obj: [String: Any]?) -> String {
        guard let obj = obj else { return "" }
        if let simple = obj["simpleText"] as? String { return simple }
        return extractRuns(obj["runs"])
    }

    private static func parseThumbnails(_ thumbs: Any?) -> [Thumbnail] {
        guard let thumbs = thumbs as? [Any] else { return [] }
        return thumbs.compactMap { item in
            guard let dict = item as? [String: Any],
                  let url = dict["url"] as? String else { return nil }
            return Thumbnail(
                url: url,
                width: dict["width"] as? Int ?? 0,
                height: dict["height"] as? Int ?? 0
            )
        }
    }

    private static func thumbnailQualityScore(_ url: String) -> Int {
        if url.isEmpty { return 0 }
        if url.contains("maxresdefault") { return 1280 }
        if url.contains("sddefault") { return 640 }
        if url.contains("hqdefault") { return 480 }
        if url.contains("mqdefault") { return 320 }
        if url.contains("default") { return 120 }
        return 0
    }

    private static func extractBestThumbnail(_ thumbnails: [Thumbnail]) -> String {
        guard !thumbnails.isEmpty else { return "" }
        var best = thumbnails[0]
        var bestScore = thumbnailQualityScore(best.url)
        for t in thumbnails.dropFirst() {
            let score = t.width > 0 ? t.width : thumbnailQualityScore(t.url)
            if score > bestScore {
                best = t
                bestScore = score
            }
        }
        return best.url
    }

    private static func extractChannelUrl(_ runs: Any?) -> String {
        guard let runs = runs as? [Any] else { return "" }
        for run in runs {
            guard let dict = run as? [String: Any],
                  let nav = dict["navigationEndpoint"] as? [String: Any],
                  let browse = nav["browseEndpoint"] as? [String: Any],
                  let baseUrl = browse["canonicalBaseUrl"] as? String else { continue }
            return "https://www.youtube.com\(baseUrl)"
        }
        return ""
    }

    private static func parseBadges(_ badges: [Any]?) -> [String] {
        guard let badges = badges else { return [] }
        return badges.compactMap { badge in
            guard let dict = badge as? [String: Any],
                  let renderer = dict["metadataBadgeRenderer"] as? [String: Any] else { return nil }
            return (renderer["style"] as? String) ?? (renderer["label"] as? String)
        }
    }

    private static func parseVerified(_ badges: [Any]?) -> Bool {
        guard let badges = badges else { return false }
        for badge in badges {
            guard let dict = badge as? [String: Any],
                  let renderer = dict["metadataBadgeRenderer"] as? [String: Any],
                  let style = renderer["style"] as? String else { continue }
            if style == "BADGE_STYLE_TYPE_VERIFIED" || style == "BADGE_STYLE_TYPE_VERIFIED_ARTIST" {
                return true
            }
        }
        return false
    }

    private static func parseChannelAvatar(from videoDetails: [String: Any]) -> String {
        guard let thumbs = videoDetails["authorThumbnails"] as? [Any] else { return "" }
        let parsed = parseThumbnails(thumbs)
        return extractBestThumbnail(parsed)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private static func formatViewCount(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            let b = Double(count) / 1_000_000_000.0
            let fmt = b.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fB views" : "%.1fB views"
            return String(format: fmt, b)
        }
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000.0
            let fmt = m.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fM views" : "%.1fM views"
            return String(format: fmt, m)
        }
        if count >= 1_000 {
            let k = Double(count) / 1_000.0
            let fmt = k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fK views" : "%.1fK views"
            return String(format: fmt, k)
        }
        return "\(count) views"
    }

    private static func extractApiKey(from html: String) -> String? {
        let markers = ["\"INNERTUBE_API_KEY\":\"", "INNERTUBE_API_KEY\":\""]
        for marker in markers {
            guard let range = html.range(of: marker) else { continue }
            let start = range.upperBound
            let rest = html[start...]
            if let end = rest.firstIndex(of: "\"") {
                return String(rest[..<end])
            }
        }
        return nil
    }
}
