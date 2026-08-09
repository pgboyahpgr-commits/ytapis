namespace Ytapis;

public sealed class ThumbnailInfo
{
    public string Url { get; init; } = string.Empty;
    public int Width { get; init; }
    public int Height { get; init; }
}

public sealed class VideoResult
{
    public string Id { get; init; } = string.Empty;
    public string Title { get; init; } = string.Empty;
    public string Author { get; init; } = string.Empty;
    public string ChannelUrl { get; init; } = string.Empty;
    public string Thumbnail { get; init; } = string.Empty;
    public List<ThumbnailInfo> Thumbnails { get; init; } = [];
    public string FullUrl { get; init; } = string.Empty;
    public string EmbedUrl { get; init; } = string.Empty;
    public string Duration { get; init; } = string.Empty;
    public int DurationSeconds { get; init; }
    public string ViewCount { get; init; } = string.Empty;
    public long ViewCountRaw { get; init; }
    public string PublishedTime { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
    public string ChannelAvatar { get; init; } = string.Empty;
    public bool IsLive { get; init; }
    public bool IsUpcoming { get; init; }
    public bool IsVerified { get; init; }
}
