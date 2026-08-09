import Foundation

public struct Thumbnail: Codable, Sendable {
    public let url: String
    public let width: Int
    public let height: Int

    public init(url: String, width: Int, height: Int) {
        self.url = url
        self.width = width
        self.height = height
    }
}

public struct VideoResult: Codable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let channelUrl: String
    public let thumbnail: String
    public let thumbnails: [Thumbnail]
    public let fullUrl: String
    public let embedUrl: String
    public let duration: String
    public let durationSeconds: Int
    public let viewCount: String
    public let viewCountRaw: Int
    public let publishedTime: String
    public let description: String
    public let channelAvatar: String
    public let isLive: Bool
    public let isUpcoming: Bool
    public let isVerified: Bool

    public init(
        id: String,
        title: String,
        author: String,
        channelUrl: String,
        thumbnail: String,
        thumbnails: [Thumbnail],
        fullUrl: String,
        embedUrl: String,
        duration: String,
        durationSeconds: Int,
        viewCount: String,
        viewCountRaw: Int,
        publishedTime: String,
        description: String,
        channelAvatar: String,
        isLive: Bool,
        isUpcoming: Bool,
        isVerified: Bool
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.channelUrl = channelUrl
        self.thumbnail = thumbnail
        self.thumbnails = thumbnails
        self.fullUrl = fullUrl
        self.embedUrl = embedUrl
        self.duration = duration
        self.durationSeconds = durationSeconds
        self.viewCount = viewCount
        self.viewCountRaw = viewCountRaw
        self.publishedTime = publishedTime
        self.description = description
        self.channelAvatar = channelAvatar
        self.isLive = isLive
        self.isUpcoming = isUpcoming
        self.isVerified = isVerified
    }
}

public struct SearchResponse: Codable, Sendable {
    public let results: [VideoResult]
    public let continuation: String?
    public let apiKey: String?

    public init(results: [VideoResult], continuation: String?, apiKey: String?) {
        self.results = results
        self.continuation = continuation
        self.apiKey = apiKey
    }
}
