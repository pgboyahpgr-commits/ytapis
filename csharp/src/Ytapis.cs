using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json;

namespace Ytapis;

public static class Ytapis
{
    private static readonly HttpClient _http = new()
    {
        Timeout = TimeSpan.FromSeconds(15)
    };

    private static string? _cachedApiKey;
    private static readonly object _apiKeyLock = new();

    static Ytapis()
    {
        _http.DefaultRequestHeaders.Add("User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36");
        _http.DefaultRequestHeaders.Add("Accept-Language", "en-US,en;q=0.9");
    }

    public static List<VideoResult> Search(string query, int limit = 15)
    {
        ArgumentNullException.ThrowIfNull(query);
        if (limit < 1) limit = 1;

        var encoded = Uri.EscapeDataString(query);
        var html = _http.GetStringAsync($"https://www.youtube.com/results?search_query={encoded}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null)
            return [];

        using var doc = JsonDocument.Parse(json);
        var results = ParseSearchResults(doc.RootElement, limit);
        return results;
    }

    public static VideoResult? GetVideo(string id)
    {
        ArgumentNullException.ThrowIfNull(id);

        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/watch?v={Uri.EscapeDataString(id)}")
                .GetAwaiter().GetResult();

            var playerJson = ExtractJson(html, "var ytInitialPlayerResponse");
            var dataJson = ExtractJson(html, "var ytInitialData");

            if (playerJson is not null)
            {
                using var playerDoc = JsonDocument.Parse(playerJson);
                var videoDetails = playerDoc.RootElement.TryGet("videoDetails");
                if (videoDetails is not null)
                    return BuildFromPlayerResponse(videoDetails.Value, dataJson, id);
            }
        }
        catch
        {
            // fall through to oEmbed
        }

        return GetVideoFallback(id);
    }

    public static (List<VideoResult> results, string? continuation, string? apiKey) SearchContinue(
        string continuation, int limit = 15, string? apiKey = null, string? context = null, string path = "search")
    {
        ArgumentNullException.ThrowIfNull(continuation);
        if (limit < 1) limit = 1;

        apiKey ??= GetApiKey();
        if (apiKey is null)
            return ([], null, null);

        var ctx = context ?? GetDefaultContext();
        var body = $$"""{"context":{{ctx}},"continuation":"{{continuation}}"}""";

        var content = new StringContent(body, Encoding.UTF8, "application/json");
        var response = _http.PostAsync(
            $"https://www.youtube.com/youtubei/v1/search?key={apiKey}", content)
            .GetAwaiter().GetResult();

        response.EnsureSuccessStatusCode();
        var responseJson = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();

        using var doc = JsonDocument.Parse(responseJson);
        var root = doc.RootElement;

        var items = GetContinuationItems(root, path);

        if (items is null)
            return ([], null, apiKey);

        var results = new List<VideoResult>();
        string? nextToken = null;

        foreach (var item in items.Value.EnumerateArray())
        {
            if (results.Count >= limit)
                break;

            if (path == "playlist")
            {
                var pvr = item.TryGet("playlistVideoRenderer");
                if (pvr is not null)
                {
                    var vid = pvr.Value.TryGet("videoId")?.GetString();
                    if (!string.IsNullOrEmpty(vid))
                    {
                        var pvrTitle = GetRunText(pvr.Value.TryGet("title")?.TryGet("runs")) ?? "";
                        var pvrAuthor = GetRunText(pvr.Value.TryGet("shortBylineText")?.TryGet("runs")) ?? "";
                        var pvrLen = pvr.Value.TryGet("lengthText")?.TryGet("simpleText")?.GetString()
                            ?? GetRunText(pvr.Value.TryGet("lengthText")?.TryGet("runs")) ?? "";
                        var (pvrDur, pvrDurSec) = ParseDuration(pvrLen);
                        results.Add(new VideoResult
                        {
                            Id = vid,
                            Title = WebUtility.HtmlDecode(string.IsNullOrEmpty(pvrTitle) ? $"Video {vid}" : pvrTitle),
                            Author = string.IsNullOrEmpty(pvrAuthor) ? "YouTube" : pvrAuthor,
                            Thumbnail = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
                            Thumbnails = [new ThumbnailInfo { Url = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg", Width = 480, Height = 360 }],
                            FullUrl = $"https://www.youtube.com/watch?v={vid}",
                            EmbedUrl = $"https://www.youtube.com/embed/{vid}?rel=0",
                            Duration = pvrDur,
                            DurationSeconds = pvrDurSec,
                        });
                    }
                }

                if (item.TryGet("continuationItemRenderer") is { } citem)
                {
                    nextToken = citem
                        .TryGet("continuationEndpoint")?
                        .TryGet("continuationCommand")?
                        .TryGet("token")?
                        .GetString();
                }
                continue;
            }

            var vr = item.TryGet("videoRenderer")
                ?? item.TryGet("richItemRenderer")?.TryGet("content")?.TryGet("videoRenderer");
            if (vr is not null)
            {
                var parsed = ParseVideoRenderer(vr.Value);
                if (parsed is not null)
                    results.Add(parsed);
            }

            if (item.TryGet("continuationItemRenderer") is { } citem2)
            {
                nextToken = citem2
                    .TryGet("continuationEndpoint")?
                    .TryGet("continuationCommand")?
                    .TryGet("token")?
                    .GetString();
            }
        }

        return (results, nextToken, apiKey);
    }

    // ---- Private parsing helpers ----

    private static List<VideoResult> ParseSearchResults(JsonElement root, int limit)
    {
        var results = new List<VideoResult>();

        var contents = root
            .TryGet("contents")?
            .TryGet("twoColumnSearchResultsRenderer")?
            .TryGet("primaryContents")?
            .TryGet("sectionListRenderer")?
            .TryGet("contents");

        if (contents is null)
            return results;

        foreach (var section in contents.Value.EnumerateArray())
        {
            if (results.Count >= limit)
                break;

            var items = section.TryGet("itemSectionRenderer")?.TryGet("contents");
            if (items is null)
                continue;

            foreach (var item in items.Value.EnumerateArray())
            {
                if (results.Count >= limit)
                    break;

                var vr = item.TryGet("videoRenderer");
                if (vr is not null)
                {
                    var parsed = ParseVideoRenderer(vr.Value);
                    if (parsed is not null)
                        results.Add(parsed);
                }
            }
        }

        return results;
    }

    private static VideoResult? ParseVideoRenderer(JsonElement vr)
    {
        try
        {
            var videoId = vr.TryGet("videoId")?.GetString();
            if (string.IsNullOrEmpty(videoId))
                return null;

            var title = GetRunText(vr.TryGet("title")?.TryGet("runs"));
            var author = GetRunText(vr.TryGet("longBylineText")?.TryGet("runs"))
                         ?? GetRunText(vr.TryGet("shortBylineText")?.TryGet("runs"))
                         ?? string.Empty;

            var channelUrl = ExtractChannelUrl(vr.TryGet("longBylineText")?.TryGet("runs"))
                          ?? ExtractChannelUrl(vr.TryGet("shortBylineText")?.TryGet("runs"))
                          ?? $"https://www.youtube.com/channel/UC";

            var thumbs = ParseThumbnails(vr.TryGet("thumbnail")?.TryGet("thumbnails"));
            var bestThumb = ExtractBestThumbnail(thumbs);
            if (string.IsNullOrEmpty(bestThumb))
                bestThumb = $"https://i.ytimg.com/vi/{videoId}/hqdefault.jpg";

            var lengthText = vr.TryGet("lengthText")?.TryGet("simpleText")?.GetString();
            if (lengthText is null)
            {
                lengthText = vr.TryGet("lengthText")?
                    .TryGet("accessibility")?
                    .TryGet("accessibilityData")?
                    .TryGet("label")?
                    .GetString();
                if (lengthText is not null)
                {
                    var idx = lengthText.LastIndexOf(' ');
                    if (idx >= 0)
                        lengthText = lengthText[(idx + 1)..];
                }
            }
            var (duration, durationSecs) = ParseDuration(lengthText ?? "");

            var viewCountText = vr.TryGet("viewCountText")?.TryGet("simpleText")?.GetString()
                             ?? GetRunText(vr.TryGet("viewCountText")?.TryGet("runs"))
                             ?? "0 views";
            var (viewLabel, viewRaw) = ParseViewCount(viewCountText);

            var publishedTime = vr.TryGet("publishedTimeText")?.TryGet("simpleText")?.GetString() ?? "";

            var desc = "";
            var snippets = vr.TryGet("detailedMetadataSnippets")
                ?? vr.TryGet("snippets");
            if (snippets is not null)
            {
                foreach (var snippet in snippets.Value.EnumerateArray())
                {
                    var runs = snippet.TryGet("snippetText")?.TryGet("runs");
                    if (runs is not null)
                    {
                        var text = GetRunText(runs);
                        if (!string.IsNullOrEmpty(text))
                        {
                            desc = text;
                            break;
                        }
                    }
                }
            }

            var channelAvatar = "";
            var cta = vr.TryGet("channelThumbnailSupportedRenderers")
                ?.TryGet("channelThumbnailWithLinkRenderer")
                ?.TryGet("thumbnail")
                ?.TryGet("thumbnails");
            if (cta is not null)
            {
                var ctaList = ParseThumbnails(cta);
                channelAvatar = ctaList.FirstOrDefault()?.Url ?? "";
            }

            var isVerified = false;
            var ownerBadges = vr.TryGet("ownerBadges");
            if (ownerBadges is not null)
            {
                foreach (var badge in ownerBadges.Value.EnumerateArray())
                {
                    var style = badge.TryGet("metadataBadgeRenderer")?.TryGet("style")?.GetString();
                    if (style == "BADGE_STYLE_TYPE_VERIFIED" || style == "BADGE_STYLE_TYPE_VERIFIED_ARTIST")
                    {
                        isVerified = true;
                        break;
                    }
                }
            }

            var isLive = false;
            var isUpcoming = false;
            var badges = vr.TryGet("badges");
            if (badges is not null)
            {
                foreach (var badge in badges.Value.EnumerateArray())
                {
                    var style = badge.TryGet("metadataBadgeRenderer")?.TryGet("style")?.GetString();
                    if (style is "BADGE_STYLE_TYPE_LIVE_NOW")
                        isLive = true;
                    else if (style is "BADGE_STYLE_TYPE_UPCOMING")
                        isUpcoming = true;
                }
            }

            if (durationSecs == 0 && isLive)
                isUpcoming = false;

            return new VideoResult
            {
                Id = videoId,
                Title = WebUtility.HtmlDecode(title ?? ""),
                Author = author,
                ChannelUrl = channelUrl,
                Thumbnail = bestThumb,
                Thumbnails = thumbs,
                FullUrl = $"https://www.youtube.com/watch?v={videoId}",
                EmbedUrl = $"https://www.youtube.com/embed/{videoId}",
                Duration = duration,
                DurationSeconds = durationSecs,
                ViewCount = viewLabel,
                ViewCountRaw = viewRaw,
                PublishedTime = publishedTime,
                Description = WebUtility.HtmlDecode(desc),
                ChannelAvatar = channelAvatar,
                IsLive = isLive,
                IsUpcoming = isUpcoming,
                IsVerified = isVerified
            };
        }
        catch
        {
            return null;
        }
    }

    private static VideoResult? BuildFromPlayerResponse(JsonElement videoDetails, string? initialDataJson, string id)
    {
        try
        {
            var videoId = videoDetails.TryGet("videoId")?.GetString() ?? id;
            var title = videoDetails.TryGet("title")?.GetString() ?? "";
            var author = videoDetails.TryGet("author")?.GetString() ?? "";

            var channelId = videoDetails.TryGet("channelId")?.GetString() ?? "";
            var channelUrl = !string.IsNullOrEmpty(channelId)
                ? $"https://www.youtube.com/channel/{channelId}"
                : "";

            var thumbs = ParseThumbnails(videoDetails.TryGet("thumbnail")?.TryGet("thumbnails"));
            var bestThumb = thumbs.FirstOrDefault()?.Url
                         ?? $"https://i.ytimg.com/vi/{videoId}/hqdefault.jpg";

            var lengthSecsStr = videoDetails.TryGet("lengthSeconds")?.GetString() ?? "0";
            _ = int.TryParse(lengthSecsStr, out var lengthSecs);
            var duration = FormatDuration(lengthSecs);

            var viewCountStr = videoDetails.TryGet("viewCount")?.GetString() ?? "0";
            _ = TryParseLong(viewCountStr, out var viewCount);
            var viewLabel = FormatViewCount(viewCount);

            var isLive = videoDetails.TryGet("isLive")?.GetBoolean() ?? false;
            var isUpcoming = videoDetails.TryGet("isUpcoming")?.GetBoolean() ?? false;

            var description = videoDetails.TryGet("shortDescription")?.GetString() ?? "";
            var publishedTime = "";
            var channelAvatar = "";
            var isVerified = false;

            if (initialDataJson is not null)
            {
                try
                {
                    using var dataDoc = JsonDocument.Parse(initialDataJson);
                    var root = dataDoc.RootElement;

                    var mf = root.TryGet("microformat")?.TryGet("playerMicroformatRenderer");
                    if (mf is not null)
                    {
                        publishedTime = mf.Value.TryGet("publishDate")?.GetString() ?? "";
                        if (string.IsNullOrEmpty(description))
                        {
                            description = mf.Value.TryGet("description")?.TryGet("simpleText")?.GetString() ?? "";
                        }
                        if (lengthSecs == 0)
                        {
                            var mfLen = mf.Value.TryGet("lengthSeconds")?.GetString();
                            if (mfLen is not null && int.TryParse(mfLen, out var mfSecs))
                            {
                                lengthSecs = mfSecs;
                                duration = FormatDuration(mfSecs);
                            }
                        }
                    }

                    var results = root
                        .TryGet("contents")?
                        .TryGet("twoColumnWatchNextResults")?
                        .TryGet("results")?
                        .TryGet("results")?
                        .TryGet("contents");

                    if (results is not null)
                    {
                        foreach (var item in results.Value.EnumerateArray())
                        {
                            var owner = item.TryGet("videoSecondaryInfoRenderer")?
                                .TryGet("owner")?
                                .TryGet("videoOwnerRenderer");

                            if (owner is not null)
                            {
                                var cta = owner.Value.TryGet("thumbnail")?.TryGet("thumbnails");
                                if (cta is not null)
                                {
                                    var ctaList = ParseThumbnails(cta);
                                    channelAvatar = ctaList.FirstOrDefault()?.Url ?? "";
                                }

                                var descRuns = item.TryGet("videoSecondaryInfoRenderer")?
                                    .TryGet("description")?
                                    .TryGet("runs");
                                if (descRuns is not null)
                                {
                                    var descText = GetRunText(descRuns);
                                    if (!string.IsNullOrEmpty(descText))
                                        description = descText;
                                }

                                var obadges = owner.Value.TryGet("badges");
                                if (obadges is not null)
                                {
                                    foreach (var badge in obadges.Value.EnumerateArray())
                                    {
                                        var style = badge.TryGet("metadataBadgeRenderer")?
                                            .TryGet("style")?.GetString();
                                        if (style is "BADGE_STYLE_TYPE_VERIFIED" or "BADGE_STYLE_TYPE_VERIFIED_ARTIST")
                                        {
                                            isVerified = true;
                                            break;
    // ─── New Types ─────────────────────────────────────────────────

    public class CommentAuthor
    {
        public string Name { get; set; } = "";
        public string ChannelId { get; set; } = "";
        public string Avatar { get; set; } = "";
        public bool IsVerified { get; set; }
        public bool IsOwner { get; set; }
    }

    public class CommentReply
    {
        public string Id { get; set; } = "";
        public CommentAuthor Author { get; set; } = new();
        public string Text { get; set; } = "";
        public int LikeCount { get; set; }
        public int LikeCountRaw { get; set; }
        public string PublishedTime { get; set; } = "";
        public bool IsLikedByCreator { get; set; }
    }

    public class VideoComment
    {
        public string Id { get; set; } = "";
        public CommentAuthor Author { get; set; } = new();
        public string Text { get; set; } = "";
        public int LikeCount { get; set; }
        public int LikeCountRaw { get; set; }
        public string PublishedTime { get; set; } = "";
        public int ReplyCount { get; set; }
        public bool IsLikedByCreator { get; set; }
        public bool IsPinned { get; set; }
        public List<CommentReply> Replies { get; set; } = [];
        public string? ReplyContinuation { get; set; }
    }

    public class RelatedVideo
    {
        public string Id { get; set; } = "";
        public string Title { get; set; } = "";
        public string Author { get; set; } = "";
        public string ChannelUrl { get; set; } = "";
        public string Duration { get; set; } = "";
        public int DurationSeconds { get; set; }
        public string ViewCount { get; set; } = "";
        public long ViewCountRaw { get; set; }
        public string PublishedTime { get; set; } = "";
        public string Thumbnail { get; set; } = "";
        public bool IsLive { get; set; }
    }

    public class LiveStreamInfo
    {
        public bool IsLive { get; set; }
        public bool IsUpcoming { get; set; }
        public long ViewerCount { get; set; }
        public string ViewerCountStr { get; set; } = "";
        public string StartTime { get; set; } = "";
        public string ScheduledStartTime { get; set; } = "";
        public long LikesCount { get; set; }
        public long DislikesCount { get; set; }
    }

    // ─── LRU Cache ──────────────────────────────────────────────

    public class LruCache<T>
    {
        private readonly int _maxSize;
        private readonly long _ttlMs;
        private readonly LinkedList<string> _order = new();
        private readonly Dictionary<string, (T value, long expires)> _map = new();

        public LruCache(int maxSize = 500, long ttlMs = 300_000)
        {
            _maxSize = maxSize;
            _ttlMs = ttlMs;
        }

        public T? Get(string key)
        {
            if (!_map.TryGetValue(key, out var entry))
                return default;
            if (DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() > entry.expires)
            {
                _map.Remove(key);
                _order.Remove(key);
                return default;
            }
            _order.Remove(key);
            _order.AddFirst(key);
            return entry.value;
        }

        public void Set(string key, T value)
        {
            if (_map.ContainsKey(key))
                _order.Remove(key);
            else if (_map.Count >= _maxSize)
            {
                var last = _order.Last!.Value;
                _map.Remove(last);
                _order.RemoveLast();
            }
            _order.AddFirst(key);
            _map[key] = (value, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() + _ttlMs);
        }

        public void Clear()
        {
            _map.Clear();
            _order.Clear();
        }

        public int Count => _map.Count;
    }

    // ─── Retry ─────────────────────────────────────────────────

    public static async Task<T> SmartRetry<T>(Func<Task<T>> fn, int maxRetries = 3, int baseDelay = 500, int maxDelay = 5000)
    {
        var rng = new Random();
        for (int a = 0; a <= maxRetries; a++)
        {
            try { return await fn(); }
            catch when (a >= maxRetries) { throw; }
            catch { }
            var delay = (int)Math.Min(baseDelay * Math.Pow(2, a) + rng.Next(500), maxDelay);
            await Task.Delay(delay);
        }
        throw new InvalidOperationException("Unreachable");
    }

    // ─── Helper: Comment Renderer Parser ────────────────────────

    private static VideoComment ParseCommentRenderer(JsonElement cr)
    {
        var id = cr.TryGet("commentId")?.GetString() ?? cr.TryGet("properties")?.TryGet("commentId")?.GetString() ?? "";
        var authorName = GetRunText(cr.TryGet("authorText")?.TryGet("runs")) ?? cr.TryGet("authorText")?.TryGet("simpleText")?.GetString() ?? "";
        var authorChannel = cr.TryGet("authorEndpoint")?.TryGet("browseEndpoint")?.TryGet("browseId")?.GetString() ?? "";
        var avatarThumbs = cr.TryGet("authorThumbnail")?.TryGet("thumbnails");
        var authorAvatar = "";
        if (avatarThumbs is not null)
        {
            var list = ParseThumbnails(avatarThumbs);
            authorAvatar = list.LastOrDefault()?.Url ?? "";
        }
        var isVerified = (cr.TryGet("authorCommentBadge")?.TryGet("authorCommentBadgeRenderer")?.TryGet("icon")?.TryGet("iconType")?.GetString() ?? "") == "CHECK";
        var isOwner = cr.TryGet("authorIsChannelOwner")?.GetBoolean() ?? false;
        var text = cr.TryGet("contentText")?.TryGet("simpleText")?.GetString() ?? GetRunText(cr.TryGet("contentText")?.TryGet("runs")) ?? "";
        var likeCount = 0;
        var likeStr = cr.TryGet("voteCount")?.TryGet("simpleText")?.GetString() ?? cr.TryGet("likeCount")?.GetString() ?? "0";
        int.TryParse(likeStr, out likeCount);
        var publishedTime = cr.TryGet("publishedTimeText")?.TryGet("runs")?.TryGetArrayElement(0)?.TryGet("text")?.GetString() ?? "";
        var replyCount = 0;
        if (cr.TryGet("replyCount")?.ValueKind == JsonValueKind.Number)
            replyCount = cr.TryGet("replyCount")!.Value.GetInt32();
        var isLiked = cr.TryGet("isLiked")?.GetBoolean() ?? false;
        var isPinned = cr.TryGet("pinnedCommentBadge")?.TryGet("pinnedCommentBadgeRenderer") is not null;

        var replies = new List<CommentReply>();
        string? replyContinuation = null;
        var replyItems = cr.TryGet("replies")?.TryGet("commentRepliesRenderer")?.TryGet("contents");
        if (replyItems is not null)
        {
            foreach (var ri in replyItems.Value.EnumerateArray())
            {
                if (ri.TryGet("continuationItemRenderer") is { } cir)
                {
                    replyContinuation = cir.TryGet("continuationEndpoint")?.TryGet("continuationCommand")?.TryGet("token")?.GetString();
                    continue;
                }
                if (ri.TryGet("commentRenderer") is { } rr)
                {
                    var rrid = rr.TryGet("commentId")?.GetString() ?? "";
                    var rrAuthorName = GetRunText(rr.TryGet("authorText")?.TryGet("runs")) ?? rr.TryGet("authorText")?.TryGet("simpleText")?.GetString() ?? "";
                    var rrChannel = rr.TryGet("authorEndpoint")?.TryGet("browseEndpoint")?.TryGet("browseId")?.GetString() ?? "";
                    var rrAvatar = "";
                    var rrAvatarThumbs = rr.TryGet("authorThumbnail")?.TryGet("thumbnails");
                    if (rrAvatarThumbs is not null)
                    {
                        var list = ParseThumbnails(rrAvatarThumbs);
                        rrAvatar = list.LastOrDefault()?.Url ?? "";
                    }
                    var rrText = rr.TryGet("contentText")?.TryGet("simpleText")?.GetString() ?? GetRunText(rr.TryGet("contentText")?.TryGet("runs")) ?? "";
                    int rrLikes = 0;
                    var rrLikeStr = rr.TryGet("voteCount")?.TryGet("simpleText")?.GetString() ?? "0";
                    int.TryParse(rrLikeStr, out rrLikes);
                    var rrTime = rr.TryGet("publishedTimeText")?.TryGet("runs")?.TryGetArrayElement(0)?.TryGet("text")?.GetString() ?? "";
                    var rrHearted = rr.TryGet("actionButtons")?.TryGet("commentActionButtonsRenderer")?.TryGet("creatorHeart")?.TryGet("creatorHeartRenderer")?.TryGet("isHearted")?.GetBoolean() ?? false;
                    replies.Add(new CommentReply
                    {
                        Id = rrid,
                        Author = new CommentAuthor { Name = rrAuthorName, ChannelId = rrChannel, Avatar = rrAvatar, IsVerified = false, IsOwner = rr.TryGet("authorIsChannelOwner")?.GetBoolean() ?? false },
                        Text = rrText,
                        LikeCount = rrLikes,
                        LikeCountRaw = rrLikes,
                        PublishedTime = rrTime,
                        IsLikedByCreator = rrHearted
                    });
                }
            }
        }

        return new VideoComment
        {
            Id = id,
            Text = text,
            LikeCount = likeCount,
            LikeCountRaw = likeCount,
            PublishedTime = publishedTime,
            ReplyCount = replyCount,
            IsLikedByCreator = isLiked,
            IsPinned = isPinned,
            Replies = replies,
            ReplyContinuation = replyContinuation,
            Author = new CommentAuthor { Name = authorName, ChannelId = authorChannel, Avatar = authorAvatar, IsVerified = isVerified, IsOwner = isOwner }
        };
    }

    // ─── Public: Comments ───────────────────────────────────────

    public static (List<VideoComment> comments, string? continuation) GetComments(
        string videoId, int limit = 20, string? continuation = null)
    {
        ArgumentNullException.ThrowIfNull(videoId);
        limit = Math.Max(1, Math.Min(limit, 100));

        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}")
                .GetAwaiter().GetResult();

            if (continuation is not null)
            {
                var apiKey = ExtractApiKeyFromHtml(html);
                var ctx = ExtractJson(html, "\"INNERTUBE_CONTEXT\"");
                var body = $$"""{"context":{{ctx ?? GetDefaultContext()}},"continuation":"{{continuation}}"}""";
                var content = new StringContent(body, Encoding.UTF8, "application/json");
                var resp = _http.PostAsync($"https://www.youtube.com/youtubei/v1/next?key={apiKey}", content)
                    .GetAwaiter().GetResult();
                var respJson = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                using var rd = JsonDocument.Parse(respJson);
                var items = (rd.RootElement.TryGet("onResponseReceivedEndpoints")?.TryGetArrayElement(0)
                    ?.TryGet("reloadContinuationItemsCommand")?.TryGet("continuationItems"))
                    ?? (rd.RootElement.TryGet("onResponseReceivedEndpoints")?.TryGetArrayElement(0)
                        ?.TryGet("appendContinuationItemsAction")?.TryGet("continuationItems"));
                if (items is null) return ([], null);
                return ParseCommentThreads(items.Value, limit);
            }

            var data = ExtractJson(html, "var ytInitialData");
            if (data is null) return ([], null);

            var apiKey2 = ExtractApiKeyFromHtml(html);
            var ctx2 = ExtractJson(html, "\"INNERTUBE_CONTEXT\"");

            using var d = JsonDocument.Parse(data);
            var allResults = d.RootElement.TryGet("contents")?.TryGet("twoColumnWatchNextResults")
                ?.TryGet("results")?.TryGet("results")?.TryGet("contents");

            string? token = null;
            foreach (var c in allResults?.EnumerateArray() ?? Enumerable.Empty<JsonElement>())
            {
                var ic = c.TryGet("itemSectionRenderer")?.TryGet("contents");
                if (ic is not null)
                {
                    foreach (var item in ic.Value.EnumerateArray())
                    {
                        token = item.TryGet("continuationItemRenderer")?.TryGet("continuationEndpoint")
                            ?.TryGet("continuationCommand")?.TryGet("token")?.GetString();
                        if (token is not null) break;
                        token = item.TryGet("commentsEntryPointHeaderRenderer")?.TryGet("contents")
                            ?.TryGetArrayElement(0)?.TryGet("continuationItemRenderer")?.TryGet("continuationEndpoint")
                            ?.TryGet("continuationCommand")?.TryGet("token")?.GetString();
                        if (token is not null) break;
                    }
                }
                if (token is not null) break;
            }
            if (token is null) return ([], null);

            var nb = $$"""{"context":{{ctx2 ?? GetDefaultContext()}},"continuation":"{{token}}"}""";
            var nc = new StringContent(nb, Encoding.UTF8, "application/json");
            var nr = _http.PostAsync($"https://www.youtube.com/youtubei/v1/next?key={apiKey2}", nc)
                .GetAwaiter().GetResult();
            var nj = nr.Content.ReadAsStringAsync().GetAwaiter().GetResult();
            using var nd = JsonDocument.Parse(nj);
            var nItems = (nd.RootElement.TryGet("onResponseReceivedEndpoints")?.TryGetArrayElement(0)
                ?.TryGet("reloadContinuationItemsCommand")?.TryGet("continuationItems"))
                ?? (nd.RootElement.TryGet("onResponseReceivedEndpoints")?.TryGetArrayElement(0)
                    ?.TryGet("appendContinuationItemsAction")?.TryGet("continuationItems"))
                ?? (nd.RootElement.TryGet("onResponseReceivedEndpoints")?.TryGetArrayElement(1)
                    ?.TryGet("reloadContinuationItemsCommand")?.TryGet("continuationItems"))
                ?? (nd.RootElement.TryGet("onResponseReceivedEndpoints")?.TryGetArrayElement(1)
                    ?.TryGet("appendContinuationItemsAction")?.TryGet("continuationItems"));
            if (nItems is null) return ([], null);

            return ParseCommentThreads(nItems.Value, limit);
        }
        catch { return ([], null); }
    }

    private static (List<VideoComment> comments, string? continuation) ParseCommentThreads(JsonElement items, int limit)
    {
        var comments = new List<VideoComment>();
        string? nc = null;
        foreach (var item in items.EnumerateArray())
        {
            if (comments.Count >= limit) break;
            if (item.TryGet("continuationItemRenderer") is { } cir)
                nc = cir.TryGet("continuationEndpoint")?.TryGet("continuationCommand")?.TryGet("token")?.GetString();
            if (item.TryGet("commentThreadRenderer") is { } ctr)
            {
                var cr = ctr.TryGet("comment")?.TryGet("commentRenderer");
                if (cr is not null)
                {
                    var parsed = ParseCommentRenderer(cr.Value);
                    comments.Add(parsed);
                }
            }
        }
        return (comments, nc);
    }

    private static string? ExtractApiKeyFromHtml(string html)
    {
        var match = System.Text.RegularExpressions.Regex.Match(html, "\"INNERTUBE_API_KEY\":\"(AIza[^\"]+)\"");
        return match.Success ? match.Groups[1].Value : "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
    }

    // ─── Public: Related Videos ─────────────────────────────────

    public static List<RelatedVideo> GetRelatedVideos(string videoId, int limit = 15)
    {
        ArgumentNullException.ThrowIfNull(videoId);
        limit = Math.Max(1, Math.Min(limit, 50));

        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}")
                .GetAwaiter().GetResult();

            var data = ExtractJson(html, "var ytInitialData");
            if (data is null) return [];

            using var doc = JsonDocument.Parse(data);
            var watchNext = doc.RootElement.TryGet("contents")?.TryGet("twoColumnWatchNextResults")
                ?.TryGet("secondaryResults")?.TryGet("secondaryResults")?.TryGet("results");
            if (watchNext is null) return [];

            var results = new List<RelatedVideo>();
            foreach (var item in watchNext.Value.EnumerateArray())
            {
                if (results.Count >= limit) break;
                var vr = item.TryGet("compactVideoRenderer") ?? item.TryGet("compactRadioRenderer");
                if (vr is null) continue;
                var vid = vr.Value.TryGet("videoId")?.GetString();
                if (string.IsNullOrEmpty(vid)) continue;

                var title = GetRunText(vr.Value.TryGet("title")?.TryGet("runs")) ?? vr.Value.TryGet("title")?.TryGet("simpleText")?.GetString() ?? "";
                var author = GetRunText(vr.Value.TryGet("shortBylineText")?.TryGet("runs")) ?? vr.Value.TryGet("shortBylineText")?.TryGet("simpleText")?.GetString() ?? "";
                var durText = vr.Value.TryGet("lengthText")?.TryGet("simpleText")?.GetString() ?? GetRunText(vr.Value.TryGet("lengthText")?.TryGet("runs")) ?? "";
                var (duration, durationSeconds) = string.IsNullOrEmpty(durText) ? ("", 0) : ParseDuration(durText);
                var viewsText = vr.Value.TryGet("viewCountText")?.TryGet("simpleText")?.GetString() ?? GetRunText(vr.Value.TryGet("viewCountText")?.TryGet("runs")) ?? "";
                var (viewCount, viewCountRaw) = ParseViewCount(viewsText);
                var publishedTime = vr.Value.TryGet("publishedTimeText")?.TryGet("simpleText")?.GetString() ?? "";
                var thumb = ExtractBestThumbnail(ParseThumbnails(vr.Value.TryGet("thumbnail")?.TryGet("thumbnails")));
                if (string.IsNullOrEmpty(thumb))
                    thumb = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg";
                var badge = vr.Value.TryGet("badges")?.TryGetArrayElement(0)?.TryGet("metadataBadgeRenderer")?.TryGet("style")?.GetString() ?? "";

                results.Add(new RelatedVideo
                {
                    Id = vid,
                    Title = WebUtility.HtmlDecode(title),
                    Author = author,
                    ChannelUrl = vr.Value.TryGet("shortBylineText")?.TryGet("runs")?.TryGetArrayElement(0)?.TryGet("navigationEndpoint")?.TryGet("browseEndpoint")?.TryGet("canonicalBaseUrl")?.GetString() ?? "",
                    Duration = duration,
                    DurationSeconds = durationSeconds,
                    ViewCount = viewCount,
                    ViewCountRaw = viewCountRaw,
                    PublishedTime = publishedTime,
                    Thumbnail = thumb,
                    IsLive = badge.Contains("LIVE", StringComparison.OrdinalIgnoreCase)
                });
            }
            return results;
        }
        catch { return []; }
    }

    // ─── Public: Live Stream Info + Stats ────────────────────────

    public static (long views, long likes, long comments, bool isLive, long viewerCount) GetVideoStats(string videoId)
    {
        ArgumentNullException.ThrowIfNull(videoId);
        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}")
                .GetAwaiter().GetResult();

            var data = ExtractJson(html, "var ytInitialData");
            if (data is null) return (0, 0, 0, false, 0);

            using var doc = JsonDocument.Parse(data);

            JsonElement? primary = null;
            var contents = doc.RootElement.TryGet("contents")?.TryGet("twoColumnWatchNextResults")
                ?.TryGet("results")?.TryGet("results")?.TryGet("contents");
            if (contents is not null)
            {
                foreach (var c in contents.Value.EnumerateArray())
                {
                    if (c.TryGet("videoPrimaryInfoRenderer") is not null)
                    {
                        primary = c.TryGet("videoPrimaryInfoRenderer");
                        break;
                    }
                }
            }

            var vcr = primary?.TryGet("viewCount")?.TryGet("videoViewCountRenderer");
            var viewsText = vcr?.TryGet("shortViewCount")?.TryGet("simpleText")?.GetString()
                ?? vcr?.TryGet("viewCount")?.TryGet("simpleText")?.GetString() ?? "";
            var (_, views) = ParseViewCount(viewsText);

            var likesStr = primary?.TryGet("videoActions")?.TryGet("menuRenderer")?.TryGet("topLevelButtons")
                ?.TryGetArrayElement(0)?.TryGet("segmentedLikeDislikeButtonViewModel")
                ?.TryGet("likeButtonViewModel")?.TryGet("likeButtonViewModel")
                ?.TryGet("toggleButtonViewModel")?.TryGet("toggleButtonViewModel")
                ?.TryGet("defaultButtonViewModel")?.TryGet("buttonViewModel")
                ?.TryGet("accessibilityText")?.GetString() ?? "";
            var (_, likes) = ParseViewCount(System.Text.RegularExpressions.Regex.Replace(likesStr, "[^0-9.KMBkmb]", ""));

            var isLive = html.Contains("\"isLive\":true");
            var vcm = System.Text.RegularExpressions.Regex.Match(html, "\"viewCount\":\\{\"videoViewCountRenderer\":\\{\"isLive\":true,\"viewCount\":\\{\"simpleText\":\"([^\"]+)\"");
            var viewerCount = vcm.Success ? ParseViewCount(vcm.Groups[1].Value).raw : 0;

            return (views, likes, 0, isLive, viewerCount);
        }
        catch { return (0, 0, 0, false, 0); }
    }

    public static LiveStreamInfo GetLiveStreamInfo(string videoId)
    {
        ArgumentNullException.ThrowIfNull(videoId);
        var (views, likes, _, isLive, viewerCount) = GetVideoStats(videoId);
        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}")
                .GetAwaiter().GetResult();

            var data = ExtractJson(html, "var ytInitialData");
            if (data is not null)
            {
                using var doc = JsonDocument.Parse(data);
                JsonElement? primary = null;
                var contents = doc.RootElement.TryGet("contents")?.TryGet("twoColumnWatchNextResults")
                    ?.TryGet("results")?.TryGet("results")?.TryGet("contents");
                if (contents is not null)
                {
                    foreach (var c in contents.Value.EnumerateArray())
                    {
                        if (c.TryGet("videoPrimaryInfoRenderer") is not null)
                        {
                            primary = c.TryGet("videoPrimaryInfoRenderer");
                            break;
                        }
                    }
                }

                return new LiveStreamInfo
                {
                    IsLive = isLive,
                    IsUpcoming = !isLive && viewerCount == 0,
                    ViewerCount = viewerCount,
                    ViewerCountStr = viewerCount.ToString("N0"),
                    StartTime = primary?.TryGet("dateText")?.TryGet("simpleText")?.GetString() ?? "",
                    ScheduledStartTime = primary?.TryGet("upcomingEventData")?.TryGet("startTime")?.GetString() ?? "",
                    LikesCount = likes,
                    DislikesCount = 0
                };
            }
        }
        catch { }

        return new LiveStreamInfo
        {
            IsLive = isLive,
            IsUpcoming = false,
            ViewerCount = viewerCount,
            ViewerCountStr = viewerCount.ToString("N0"),
            StartTime = "",
            ScheduledStartTime = "",
            LikesCount = likes,
            DislikesCount = 0
        };
    }

    // ─── Channel Metadata ───────────────────────────────────────────────────

    public class SocialLink
    {
        public string Title { get; set; } = "";
        public string Url { get; set; } = "";
        public string Icon { get; set; } = "";
    }

    public class ChannelMetadata
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string Handle { get; set; } = "";
        public string Description { get; set; } = "";
        public string SubscriberCount { get; set; } = "";
        public long SubscriberCountRaw { get; set; }
        public string VideoCount { get; set; } = "";
        public long VideoCountRaw { get; set; }
        public string Avatar { get; set; } = "";
        public string Banner { get; set; } = "";
        public bool IsVerified { get; set; }
        public List<SocialLink> SocialLinks { get; set; } = [];
        public string Url { get; set; } = "";
    }

    public static ChannelMetadata GetChannelMetadata(string channelId)
    {
        ArgumentNullException.ThrowIfNull(channelId);
        var empty = new ChannelMetadata
        {
            Id = channelId,
            Url = $"https://www.youtube.com/channel/{channelId}"
        };

        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/channel/{Uri.EscapeDataString(channelId)}/about")
                .GetAwaiter().GetResult();

            var json = ExtractJson(html, "var ytInitialData");
            if (json is null) return empty;
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var metadata = root.TryGet("metadata")?.TryGet("channelMetadataRenderer");
            var about = root.TryGet("contents")?.TryGet("twoColumnBrowseResultsRenderer")?.TryGet("tabs");
            JsonElement? aboutRenderer = null;
            if (about is not null)
            {
                foreach (var tab in about.Value.EnumerateArray())
                {
                    if (tab.TryGet("tabRenderer")?.TryGet("selected")?.GetBoolean() == true)
                    {
                        aboutRenderer = tab.TryGet("tabRenderer")?.TryGet("content")?.TryGet("sectionListRenderer")
                            ?.TryGet("contents")?.TryGetArrayElement(0)?.TryGet("itemSectionRenderer")
                            ?.TryGet("contents")?.TryGetArrayElement(0)?.TryGet("channelAboutFullMetadataRenderer");
                        break;
                    }
                }
            }

            var header = root.TryGet("header")?.TryGet("c4TabbedHeaderRenderer");
            var subText = header?.TryGet("subscriberCountText")?.TryGet("simpleText")?.GetString() ?? "";
            var (subCount, subRaw) = ParseViewCount(subText);

            var videoText = "";
            long vcRaw = 0;
            if (aboutRenderer is not null)
            {
                videoText = GetRunText(aboutRenderer.Value.TryGet("videoCountText")?.TryGet("runs")) ?? "";
                var vcMatch = System.Text.RegularExpressions.Regex.Match(videoText ?? "", @"([\d,]+)");
                if (vcMatch.Success) long.TryParse(vcMatch.Groups[1].Value.Replace(",", ""), out vcRaw);
            }

            var links = new List<SocialLink>();
            var primaryLinks = aboutRenderer?.TryGet("primaryLinks");
            if (primaryLinks is not null)
            {
                foreach (var link in primaryLinks.Value.EnumerateArray())
                {
                    var nav = link.TryGet("navigationEndpoint")?.TryGet("urlEndpoint");
                    links.Add(new SocialLink
                    {
                        Title = link.TryGet("title")?.TryGet("simpleText")?.GetString()
                            ?? GetRunText(link.TryGet("title")?.TryGet("runs")) ?? "",
                        Url = nav?.TryGet("url")?.GetString() ?? "",
                        Icon = link.TryGet("icon")?.TryGet("thumbnails")?.TryGetArrayElement(0)?.TryGet("url")?.GetString() ?? ""
                    });
                }
            }

            var name = metadata?.TryGet("title")?.GetString() ?? header?.TryGet("title")?.GetString() ?? "";
            var vanityUrl = metadata?.TryGet("vanityChannelUrl")?.GetString() ?? "";
            var handle = "";
            if (!string.IsNullOrEmpty(vanityUrl))
            {
                handle = vanityUrl.Replace("http://www.youtube.com/", "").Replace("https://www.youtube.com/", "");
            }

            var desc = metadata?.TryGet("description")?.GetString()
                ?? aboutRenderer?.TryGet("description")?.TryGet("simpleText")?.GetString()
                ?? GetRunText(aboutRenderer?.TryGet("description")?.TryGet("runs")) ?? "";

            var avatar = "";
            var metaThumbs = metadata?.TryGet("avatar")?.TryGet("thumbnails");
            var headerThumbs = header?.TryGet("avatar")?.TryGet("thumbnails");
            var parsedMetaThumbs = ParseThumbnails(metaThumbs);
            var parsedHeaderThumbs = ParseThumbnails(headerThumbs);
            avatar = ExtractBestThumbnail(parsedMetaThumbs.Count > 0 ? parsedMetaThumbs : parsedHeaderThumbs);

            var banner = "";
            var bannerMeta = metadata?.TryGet("banner")?.TryGet("thumbnails");
            var bannerHeader = header?.TryGet("banner")?.TryGet("thumbnails");
            var parsedBannerMeta = ParseThumbnails(bannerMeta);
            var parsedBannerHeader = ParseThumbnails(bannerHeader);
            banner = ExtractBestThumbnail(parsedBannerMeta.Count > 0 ? parsedBannerMeta : parsedBannerHeader);

            var isVerified = false;
            var headerBadges = header?.TryGet("badges");
            if (headerBadges is not null)
            {
                foreach (var badge in headerBadges.Value.EnumerateArray())
                {
                    var style = badge.TryGet("metadataBadgeRenderer")?.TryGet("style")?.GetString() ?? "";
                    if (style.Contains("VERIFIED")) { isVerified = true; break; }
                }
            }

            return new ChannelMetadata
            {
                Id = channelId,
                Name = name,
                Handle = handle,
                Description = desc,
                SubscriberCount = subCount,
                SubscriberCountRaw = subRaw,
                VideoCount = videoText ?? "",
                VideoCountRaw = vcRaw,
                Avatar = avatar,
                Banner = banner,
                IsVerified = isVerified,
                SocialLinks = links,
                Url = $"https://www.youtube.com/channel/{channelId}"
            };
        }
        catch
        {
            return empty;
        }
    }

    // ─── Transcripts ────────────────────────────────────────────────────────

    public class TranscriptEntry
    {
        public string Text { get; set; } = "";
        public double Start { get; set; }
        public double Duration { get; set; }
    }

    public static List<TranscriptEntry> GetTranscript(string videoId, string? lang = null)
    {
        ArgumentNullException.ThrowIfNull(videoId);

        try
        {
            var html = _http.GetStringAsync($"https://www.youtube.com/watch?v={Uri.EscapeDataString(videoId)}")
                .GetAwaiter().GetResult();

            var captionsMatch = System.Text.RegularExpressions.Regex.Match(html,
                @"""captionTracks"":\s*(\[[^\]]*\{[^}]*""baseUrl"":""([^""]+)""[^}]*\}[^\]]*\])");
            if (!captionsMatch.Success)
            {
                var playerMatch = System.Text.RegularExpressions.Regex.Match(html,
                    @"""captions"":\{[^}]*""playerCaptionsTracklistRenderer"":\{[^}]*""captionTracks"":(\[[^\]]*\])");
                if (!playerMatch.Success) return [];
            }

            var tracksStr = captionsMatch.Groups[1].Success
                ? captionsMatch.Groups[1].Value
                : System.Text.RegularExpressions.Regex.Match(html,
                    @"""captionTracks"":(\[[^\]]*\{[^}]*\}[^\]]*\])").Groups[1].Value;

            if (string.IsNullOrEmpty(tracksStr)) return [];

            using var tracksDoc = JsonDocument.Parse(tracksStr);
            var tracks = tracksDoc.RootElement;

            string? trackUrl = null;
            foreach (var track in tracks.EnumerateArray())
            {
                if (lang is not null)
                {
                    var lc = track.TryGet("languageCode")?.GetString() ?? "";
                    var tn = track.TryGet("name")?.TryGet("simpleText")?.GetString() ?? "";
                    if (lc == lang || tn.Contains(lang, StringComparison.OrdinalIgnoreCase))
                    {
                        trackUrl = track.TryGet("baseUrl")?.GetString();
                        break;
                    }
                }
            }
            if (trackUrl is null)
            {
                foreach (var track in tracks.EnumerateArray())
                {
                    if ((track.TryGet("languageCode")?.GetString() ?? "") == "en")
                    {
                        trackUrl = track.TryGet("baseUrl")?.GetString();
                        break;
                    }
                }
                trackUrl ??= tracks.EnumerateArray().FirstOrDefault().TryGet("baseUrl")?.GetString();
            }

            if (trackUrl is null) return [];

            var xml = _http.GetStringAsync(trackUrl).GetAwaiter().GetResult();
            var entries = new List<TranscriptEntry>();

            var matches = System.Text.RegularExpressions.Regex.Matches(xml,
                @"<text start=""([\d.]+)"" dur=""([\d.]+)""[^>]*>(.*?)(?:</text>)?$",
                System.Text.RegularExpressions.RegexOptions.Multiline);

            foreach (System.Text.RegularExpressions.Match m in matches)
            {
                var rawText = m.Groups[3].Value;
                rawText = System.Text.RegularExpressions.Regex.Replace(rawText, @"<[^>]+>", "");
                rawText = rawText.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">")
                    .Replace("&quot;", "\"").Replace("&#39;", "'");
                var trimmed = rawText.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                {
                    entries.Add(new TranscriptEntry
                    {
                        Text = trimmed,
                        Start = double.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture),
                        Duration = double.Parse(m.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture)
                    });
                }
            }
            return entries;
        }
        catch
        {
            return [];
        }
    }

    // ─── Shorts Search ──────────────────────────────────────────────────────

    public static SearchResponse SearchShorts(string query, int limit = 15, string? gl = null, string? hl = null)
    {
        ArgumentNullException.ThrowIfNull(query);
        limit = Math.Max(1, Math.Min(limit, 50));

        var region = "";
        if (gl is not null) region += $"&gl={gl}";
        if (hl is not null) region += $"&hl={hl}";

        var encoded = Uri.EscapeDataString(query);
        var html = _http.GetStringAsync(
            $"https://www.youtube.com/results?search_query={encoded}&sp=EgIYAQ%3D%3D{region}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return new SearchResponse { Results = [] };
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        var apiKey = ExtractApiKeyFromHtml(html);

        var contents = root.TryGet("contents")?.TryGet("twoColumnSearchResultsRenderer")
            ?.TryGet("primaryContents")?.TryGet("sectionListRenderer")?.TryGet("contents");

        JsonElement? shortsRenderer = null;
        if (contents is not null)
        {
            foreach (var section in contents.Value.EnumerateArray())
            {
                var firstItem = section.TryGet("itemSectionRenderer")?.TryGet("contents")
                    ?.TryGetArrayElement(0);
                if (firstItem?.TryGet("reelShelfRenderer") is not null)
                {
                    shortsRenderer = firstItem;
                    break;
                }
            }
        }

        List<VideoResult> results;
        string? continuation;

        if (shortsRenderer is not null)
        {
            var reelItems = shortsRenderer.Value.TryGet("reelShelfRenderer")?.TryGet("items");
            var allResults = ParseSearchResults(root, limit);

            var shortResults = new List<VideoResult>();
            if (reelItems is not null)
            {
                foreach (var item in reelItems.Value.EnumerateArray())
                {
                    if (shortResults.Count >= limit) break;
                    var ri = item.TryGet("reelItemRenderer")
                        ?? item.TryGet("shortsLockupViewModel");
                    var vid = ri?.TryGet("videoId")?.GetString()
                        ?? item.TryGet("reelItemRenderer")?.TryGet("videoId")?.GetString();
                    if (string.IsNullOrEmpty(vid)) continue;

                    var title = ri?.TryGet("headline")?.TryGet("simpleText")?.GetString()
                        ?? GetRunText(ri?.TryGet("headline")?.TryGet("runs")) ?? "";
                    var durStr = ri?.TryGet("lengthText")?.TryGet("simpleText")?.GetString() ?? "0";
                    int durSec = 0;
                    int.TryParse(durStr, out durSec);

                    shortResults.Add(new VideoResult
                    {
                        Id = vid,
                        Title = string.IsNullOrEmpty(title) ? $"Shorts {vid}" : title,
                        Duration = $"{durSec}s",
                        DurationSeconds = durSec,
                        Author = "YouTube",
                        ChannelUrl = "",
                        Thumbnail = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
                        Thumbnails = [new ThumbnailInfo { Url = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg", Width = 480, Height = 360 }],
                        FullUrl = $"https://www.youtube.com/watch?v={vid}",
                        EmbedUrl = $"https://www.youtube.com/embed/{vid}?rel=0",
                        IsLive = false,
                        IsUpcoming = false,
                        IsVerified = false
                    });
                }
            }

            var combined = new List<VideoResult>();
            var seen = new HashSet<string>();
            foreach (var r in shortResults)
            {
                if (seen.Add(r.Id)) combined.Add(r);
            }
            foreach (var r in allResults)
            {
                if (seen.Add(r.Id) && combined.Count < limit) combined.Add(r);
            }
            results = combined;
            continuation = null;
        }
        else
        {
            var parsed = ParseSearchResults(root, limit);
            results = parsed;
            continuation = null;
        }

        return new SearchResponse { Results = results, Continuation = continuation, ApiKey = apiKey };
    }

    // ─── Region-aware search overloads ──────────────────────────────────────

    private static string BuildRegionParams(string? gl = null, string? hl = null)
    {
        var parts = new List<string>();
        if (gl is not null) parts.Add($"gl={gl}");
        if (hl is not null) parts.Add($"hl={hl}");
        return parts.Count > 0 ? "&" + string.Join("&", parts) : "";
    }

    public static List<VideoResult> Search(string query, int limit, string? gl, string? hl)
    {
        ArgumentNullException.ThrowIfNull(query);
        if (limit < 1) limit = 1;

        var regionQuery = BuildRegionParams(gl, hl);
        var encoded = Uri.EscapeDataString(query);
        var html = _http.GetStringAsync(
            $"https://www.youtube.com/results?search_query={encoded}{regionQuery}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        var results = ParseSearchResults(doc.RootElement, limit);
        return results;
    }

    public static List<VideoResult> SearchTrending(int limit, string? gl, string? hl)
    {
        if (limit < 1) limit = 1;
        if (limit > 50) limit = 50;

        var regionQuery = BuildRegionParams(gl, hl);
        var html = _http.GetStringAsync($"https://www.youtube.com/feed/trending{regionQuery}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        return ParseTrendingResults(doc.RootElement, limit);
    }

    public static List<VideoResult> SearchChannel(string channelId, int limit, string? gl, string? hl)
    {
        ArgumentNullException.ThrowIfNull(channelId);
        if (limit < 1) limit = 1;
        if (limit > 50) limit = 50;

        var regionQuery = BuildRegionParams(gl, hl);
        var html = _http.GetStringAsync(
            $"https://www.youtube.com/channel/{Uri.EscapeDataString(channelId)}/videos{regionQuery}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        return ParseChannelResults(doc.RootElement, limit);
    }

    public static List<VideoResult> SearchPlaylist(string playlistId, int limit, string? gl, string? hl)
    {
        ArgumentNullException.ThrowIfNull(playlistId);
        if (limit < 1) limit = 1;
        if (limit > 50) limit = 50;

        var regionQuery = BuildRegionParams(gl, hl);
        var html = _http.GetStringAsync(
            $"https://www.youtube.com/playlist?list={Uri.EscapeDataString(playlistId)}{regionQuery}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        return ParsePlaylistResults(doc.RootElement, limit);
    }

    // ─── Global Cache ──────────────────────────────────────────

    private static readonly LruCache<string> _globalCache = new(500, 300_000);

    // ─── Client Factory ─────────────────────────────────────────

    public class YtapisClient
    {
        public Func<string, int?, List<VideoResult>> Search { get; init; } = (_, _) => [];
        public Func<int?, List<VideoResult>> SearchTrending { get; init; } = _ => [];
        public Func<string, int?, List<VideoResult>> SearchChannel { get; init; } = (_, _) => [];
        public Func<string, int?, List<VideoResult>> SearchPlaylist { get; init; } = (_, _) => [];
        public Func<string, int?, string?, string?, string?, (List<VideoResult>, string?, string?)> SearchContinue { get; init; } = (_, _, _, _, _) => ([], null, null);
        public Func<string, VideoResult?> GetVideo { get; init; } = _ => null;
        public Func<string, int?, string?, (List<VideoComment>, string?)> GetComments { get; init; } = (_, _, _) => ([], null);
        public Func<string, int?, List<RelatedVideo>> GetRelatedVideos { get; init; } = (_, _) => [];
        public Func<string, (long, long, long, bool, long)> GetVideoStats { get; init; } = _ => (0, 0, 0, false, 0);
        public Func<string, LiveStreamInfo> GetLiveStreamInfo { get; init; } = _ => new();
        public Func<string, ChannelMetadata> GetChannelMetadata { get; init; } = _ => new();
        public Func<string, string?, List<TranscriptEntry>> GetTranscript { get; init; } = (_, _) => [];
        public Func<string, int?, List<VideoResult>> SearchShorts { get; init; } = (_, _) => [];
        public LruCache<string> Cache { get; init; } = new();
    }

    public static YtapisClient CreateClient(
        LruCache<string>? cache = null, bool retry = true, int maxRetries = 3)
    {
        return new YtapisClient
        {
            Search = (q, l) => Ytapis.Search(q ?? "", l ?? 15),
            SearchTrending = (l) => Ytapis.SearchTrending(l ?? 15),
            SearchChannel = (cid, l) => Ytapis.SearchChannel(cid ?? "", l ?? 15),
            SearchPlaylist = (pid, l) => Ytapis.SearchPlaylist(pid ?? "", l ?? 15),
            SearchContinue = (cont, l, apiKey, ctx, path) => Ytapis.SearchContinue(cont ?? "", l ?? 15, apiKey, ctx, path ?? "search"),
            GetVideo = (id) => Ytapis.GetVideo(id ?? ""),
            GetComments = (vid, l, cont) => Ytapis.GetComments(vid ?? "", l ?? 20, cont),
            GetRelatedVideos = (vid, l) => Ytapis.GetRelatedVideos(vid ?? "", l ?? 15),
            GetVideoStats = (vid) => Ytapis.GetVideoStats(vid ?? ""),
            GetLiveStreamInfo = (vid) => Ytapis.GetLiveStreamInfo(vid ?? ""),
            GetChannelMetadata = (cid) => Ytapis.GetChannelMetadata(cid ?? ""),
            GetTranscript = (vid, lang) => Ytapis.GetTranscript(vid ?? "", lang),
            SearchShorts = (q, l) => Ytapis.SearchShorts(q ?? "", l ?? 15),
            Cache = cache ?? _globalCache
        };
    }
}
                                    }
                                }
                                break;
                            }
                        }
                    }
                }
                catch
                {
                    // use what we have from player response
                }
            }

            return new VideoResult
            {
                Id = videoId,
                Title = WebUtility.HtmlDecode(title),
                Author = author,
                ChannelUrl = channelUrl,
                Thumbnail = bestThumb,
                Thumbnails = thumbs,
                FullUrl = $"https://www.youtube.com/watch?v={videoId}",
                EmbedUrl = $"https://www.youtube.com/embed/{videoId}",
                Duration = duration,
                DurationSeconds = lengthSecs,
                ViewCount = viewLabel,
                ViewCountRaw = viewCount,
                PublishedTime = publishedTime,
                Description = WebUtility.HtmlDecode(description),
                ChannelAvatar = channelAvatar,
                IsLive = isLive,
                IsUpcoming = isUpcoming,
                IsVerified = isVerified
            };
        }
        catch
        {
            return null;
        }
    }

    private static VideoResult? GetVideoFallback(string id)
    {
        try
        {
            var url = $"https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={Uri.EscapeDataString(id)}&format=json";
            var json = _http.GetStringAsync(url).GetAwaiter().GetResult();
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            var title = root.TryGet("title")?.GetString() ?? "";
            var author = root.TryGet("author_name")?.GetString() ?? "";
            var authorUrl = root.TryGet("author_url")?.GetString() ?? "";
            var thumbUrl = root.TryGet("thumbnail_url")?.GetString() ?? $"https://i.ytimg.com/vi/{id}/hqdefault.jpg";
            var thumbW = root.TryGet("thumbnail_width")?.GetInt32() ?? 480;
            var thumbH = root.TryGet("thumbnail_height")?.GetInt32() ?? 360;

            return new VideoResult
            {
                Id = id,
                Title = WebUtility.HtmlDecode(title),
                Author = author,
                ChannelUrl = authorUrl,
                Thumbnail = thumbUrl,
                Thumbnails = [new ThumbnailInfo { Url = thumbUrl, Width = thumbW, Height = thumbH }],
                FullUrl = $"https://www.youtube.com/watch?v={id}",
                EmbedUrl = $"https://www.youtube.com/embed/{id}",
                Duration = "",
                DurationSeconds = 0,
                ViewCount = "",
                ViewCountRaw = 0,
                PublishedTime = "",
                Description = "",
                ChannelAvatar = "",
                IsLive = false,
                IsUpcoming = false,
                IsVerified = false
            };
        }
        catch
        {
            return null;
        }
    }

    // ---- Parsing primitives ----

    private static (string formatted, int seconds) ParseDuration(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return ("", 0);

        var parts = raw.Trim().Split(':');
        int totalSeconds;

        if (parts.Length == 3)
        {
            _ = int.TryParse(parts[0], out var h);
            _ = int.TryParse(parts[1], out var m);
            _ = int.TryParse(parts[2], out var s);
            totalSeconds = h * 3600 + m * 60 + s;
        }
        else if (parts.Length == 2)
        {
            _ = int.TryParse(parts[0], out var m);
            _ = int.TryParse(parts[1], out var s);
            totalSeconds = m * 60 + s;
        }
        else
        {
            _ = int.TryParse(parts[0], out totalSeconds);
        }

        if (parts.Length == 3)
            return (raw, totalSeconds);

        if (totalSeconds >= 3600)
            return (FormatDuration(totalSeconds), totalSeconds);

        return (raw, totalSeconds);
    }

    private static (string formatted, long raw) ParseViewCount(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return ("0 views", 0);

        var trimmed = raw.Trim();
        var numericPart = trimmed.Split(' ')[0].Trim();

        long multiplier = 1;
        var suffix = char.ToUpperInvariant(numericPart[^1]);
        var numberStr = numericPart;

        switch (suffix)
        {
            case 'K':
                multiplier = 1000;
                numberStr = numericPart[..^1];
                break;
            case 'M':
                multiplier = 1_000_000;
                numberStr = numericPart[..^1];
                break;
            case 'B':
                multiplier = 1_000_000_000;
                numberStr = numericPart[..^1];
                break;
        }

        if (double.TryParse(numberStr,
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture,
                out var parsed))
        {
            var rawCount = (long)(parsed * multiplier);
            return (FormatViewCount(rawCount), rawCount);
        }

        return (trimmed, 0);
    }

    private static string FormatDuration(int totalSeconds)
    {
        if (totalSeconds < 0) return "0:00";
        var h = totalSeconds / 3600;
        var m = (totalSeconds % 3600) / 60;
        var s = totalSeconds % 60;
        return h > 0
            ? $"{h}:{m:D2}:{s:D2}"
            : $"{m}:{s:D2}";
    }

    private static string FormatViewCount(long count)
    {
        return count switch
        {
            >= 1_000_000_000 => $"{count / 1_000_000_000d:F1}B views",
            >= 1_000_000 => $"{count / 1_000_000d:F1}M views",
            >= 1_000 => $"{count / 1_000d:F1}K views",
            >= 0 => $"{count} views",
            _ => "0 views"
        };
    }

    private static List<ThumbnailInfo> ParseThumbnails(JsonElement? element)
    {
        var list = new List<ThumbnailInfo>();
        if (element is null)
            return list;

        foreach (var thumb in element.Value.EnumerateArray())
        {
            var url = thumb.TryGet("url")?.GetString();
            if (url is null)
                continue;

            list.Add(new ThumbnailInfo
            {
                Url = url,
                Width = thumb.TryGet("width")?.GetInt32() ?? 0,
                Height = thumb.TryGet("height")?.GetInt32() ?? 0
            });
        }

        return list;
    }

    private static int ThumbnailQualityScore(string? url)
    {
        if (string.IsNullOrEmpty(url)) return 0;
        if (url.Contains("maxresdefault")) return 1280;
        if (url.Contains("sddefault")) return 640;
        if (url.Contains("hqdefault")) return 480;
        if (url.Contains("mqdefault")) return 320;
        if (url.Contains("default")) return 120;
        return 0;
    }

    private static string ExtractBestThumbnail(List<ThumbnailInfo> thumbs)
    {
        if (thumbs.Count == 0) return "";
        var best = thumbs[0];
        var bestScore = ThumbnailQualityScore(best.Url);
        for (int i = 1; i < thumbs.Count; i++)
        {
            var t = thumbs[i];
            var score = t.Width > 0 ? t.Width : ThumbnailQualityScore(t.Url);
            if (score > bestScore) { best = t; bestScore = score; }
        }
        return best.Url;
    }

    private static string? GetRunText(JsonElement? runs)
    {
        if (runs is null)
            return null;

        var sb = new StringBuilder();
        foreach (var run in runs.Value.EnumerateArray())
        {
            var text = run.TryGet("text")?.GetString();
            if (text is not null)
                sb.Append(text);
        }

        return sb.Length > 0 ? sb.ToString() : null;
    }

    private static string? ExtractChannelUrl(JsonElement? runs)
    {
        if (runs is null)
            return null;

        foreach (var run in runs.Value.EnumerateArray())
        {
            var url = run
                .TryGet("navigationEndpoint")?
                .TryGet("browseEndpoint")?
                .TryGet("canonicalBaseUrl")?
                .GetString();

            if (!string.IsNullOrEmpty(url))
                return "https://www.youtube.com" + url;
        }

        return null;
    }

    private static string? ExtractJson(string html, string prefix)
    {
        int idx = html.IndexOf(prefix, StringComparison.Ordinal);
        if (idx < 0)
            return null;

        idx += prefix.Length;

        // skip past '=' and whitespace to the opening brace
        while (idx < html.Length)
        {
            var c = html[idx];
            if (c == '{')
                break;
            idx++;
        }

        if (idx >= html.Length)
            return null;

        int braceCount = 0;
        bool inString = false;
        bool escaped = false;
        int endIdx = idx;

        for (int i = idx; i < html.Length; i++)
        {
            char c = html[i];

            if (inString)
            {
                if (escaped)
                {
                    escaped = false;
                }
                else if (c == '\\')
                {
                    escaped = true;
                }
                else if (c == '"')
                {
                    inString = false;
                }
            }
            else
            {
                if (c == '"')
                {
                    inString = true;
                }
                else if (c == '{')
                {
                    braceCount++;
                }
                else if (c == '}')
                {
                    braceCount--;
                    if (braceCount == 0)
                    {
                        endIdx = i + 1;
                        break;
                    }
                }
            }
        }

        return html[idx..endIdx];
    }

    private static string? GetApiKey()
    {
        lock (_apiKeyLock)
        {
            if (_cachedApiKey is not null)
                return _cachedApiKey;
        }

        try
        {
            var html = _http.GetStringAsync("https://www.youtube.com/results?search_query=test")
                .GetAwaiter().GetResult();

            string marker = "\"INNERTUBE_API_KEY\":\"";
            int idx = html.IndexOf(marker, StringComparison.Ordinal);
            if (idx < 0)
            {
                marker = "INNERTUBE_API_KEY\":\"";
                idx = html.IndexOf(marker, StringComparison.Ordinal);
            }

            if (idx >= 0)
            {
                idx += marker.Length;
                int end = html.IndexOf('"', idx);
                if (end > idx)
                {
                    var key = html[idx..end];
                    lock (_apiKeyLock)
                    {
                        _cachedApiKey = key;
                    }
                    return key;
                }
            }
        }
        catch
        {
            // can't extract key
        }

        return null;
    }

    private static string GetDefaultContext()
    {
        return """{"client":{"hl":"en","gl":"US","clientName":"WEB","clientVersion":"2.20241202.07.00"}}""";
    }

    // ---- Helpers for TryGet-style JSON element extension ----

    internal static JsonElement? TryGet(this JsonElement element, string propertyName)
    {
        if (element.ValueKind == JsonValueKind.Object
            && element.TryGetProperty(propertyName, out var value))
        {
            return value;
        }
        return null;
    }

    internal static JsonElement? TryGetArrayElement(this JsonElement element, int index)
    {
        if (element.ValueKind != JsonValueKind.Array)
            return null;

        var enumerator = element.EnumerateArray();
        int i = 0;
        while (enumerator.MoveNext())
        {
            if (i == index)
                return enumerator.Current;
            i++;
        }
        return null;
    }

    private static bool TryParseLong(string s, out long value)
    {
        return long.TryParse(s,
            System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture,
            out value);
    }

    private static JsonElement? GetContinuationItems(JsonElement root, string path)
    {
        if (path == "channel")
        {
            var items = root
                .TryGet("onResponseReceivedActions")?
                .TryGetArrayElement(0)?
                .TryGet("appendContinuationItemsAction")?
                .TryGet("continuationItems");
            if (items is not null) return items;
            return root
                .TryGet("onResponseReceivedEndpoints")?
                .TryGetArrayElement(0)?
                .TryGet("appendContinuationItemsAction")?
                .TryGet("continuationItems");
        }
        else if (path == "playlist")
        {
            return root
                .TryGet("onResponseReceivedActions")?
                .TryGetArrayElement(0)?
                .TryGet("appendContinuationItemsAction")?
                .TryGet("continuationItems");
        }
        else
        {
            return root
                .TryGet("onResponseReceivedEndpoints")?
                .TryGetArrayElement(0)?
                .TryGet("appendContinuationItemsAction")?
                .TryGet("continuationItems");
        }
    }

    // ── Trending / Channel / Playlist parsers ──

    private static List<VideoResult> ParseTrendingResults(JsonElement root, int limit)
    {
        var results = new List<VideoResult>();
        var tabs = root.TryGet("contents")?.TryGet("twoColumnBrowseResultsRenderer")?.TryGet("tabs");
        if (tabs is null) return results;

        foreach (var tab in tabs.Value.EnumerateArray())
        {
            var contents = tab.TryGet("tabRenderer")?.TryGet("content")
                ?.TryGet("sectionListRenderer")?.TryGet("contents");
            if (contents is null) continue;

            foreach (var section in contents.Value.EnumerateArray())
            {
                if (results.Count >= limit) break;

                var items = section.TryGet("itemSectionRenderer")?.TryGet("contents");
                if (items is not null)
                {
                    foreach (var item in items.Value.EnumerateArray())
                    {
                        if (results.Count >= limit) break;
                        var vr = item.TryGet("videoRenderer");
                        if (vr is not null)
                        {
                            var parsed = ParseVideoRenderer(vr.Value);
                            if (parsed is not null) results.Add(parsed);
                        }
                    }
                }

                var shelfContent = section.TryGet("shelfRenderer")?.TryGet("content");
                if (shelfContent is not null)
                {
                    var shelfItems = shelfContent.Value.TryGet("expandedShelfContentsRenderer")?.TryGet("items")
                        ?? shelfContent.Value.TryGet("horizontalListRenderer")?.TryGet("items");
                    if (shelfItems is not null)
                    {
                        foreach (var item in shelfItems.Value.EnumerateArray())
                        {
                            if (results.Count >= limit) break;
                            var vr = item.TryGet("videoRenderer");
                            if (vr is not null)
                            {
                                var parsed = ParseVideoRenderer(vr.Value);
                                if (parsed is not null) results.Add(parsed);
                            }
                        }
                    }
                }
            }

            if (results.Count > 0) break;
        }

        return results;
    }

    private static List<VideoResult> ParseChannelResults(JsonElement root, int limit)
    {
        var results = new List<VideoResult>();
        var tabs = root.TryGet("contents")?.TryGet("twoColumnBrowseResultsRenderer")?.TryGet("tabs");
        if (tabs is null) return results;

        foreach (var tab in tabs.Value.EnumerateArray())
        {
            var content = tab.TryGet("tabRenderer")?.TryGet("content");
            if (content is null) continue;

            var items = content.Value.TryGet("richGridRenderer")?.TryGet("contents")
                ?? content.Value.TryGet("sectionListRenderer")?.TryGet("contents");
            if (items is null) continue;

            foreach (var item in items.Value.EnumerateArray())
            {
                if (results.Count >= limit) break;

                var riVr = item.TryGet("richItemRenderer")?.TryGet("content")?.TryGet("videoRenderer");
                if (riVr is not null)
                {
                    var parsed = ParseVideoRenderer(riVr.Value);
                    if (parsed is not null) results.Add(parsed);
                }

                var vr = item.TryGet("videoRenderer");
                if (vr is not null)
                {
                    var parsed = ParseVideoRenderer(vr.Value);
                    if (parsed is not null) results.Add(parsed);
                }
            }

            if (results.Count > 0) break;
        }

        return results;
    }

    private static List<VideoResult> ParsePlaylistResults(JsonElement root, int limit)
    {
        var results = new List<VideoResult>();

        var contents = root.TryGet("contents")?.TryGet("twoColumnBrowseResultsRenderer")
            ?.TryGet("tabs")?.TryGetArrayElement(0)
            ?.TryGet("tabRenderer")?.TryGet("content")
            ?.TryGet("sectionListRenderer")?.TryGet("contents")
            ?.TryGetArrayElement(0)
            ?.TryGet("itemSectionRenderer")?.TryGet("contents")
            ?.TryGetArrayElement(0)
            ?.TryGet("playlistVideoListRenderer")?.TryGet("contents");

        if (contents is null)
        {
            contents = root.TryGet("contents")?.TryGet("twoColumnWatchNextResults")
                ?.TryGet("playlist")?.TryGet("playlist")?.TryGet("contents");
        }

        if (contents is null) return results;

        foreach (var item in contents.Value.EnumerateArray())
        {
            if (results.Count >= limit) break;

            var pvr = item.TryGet("playlistVideoRenderer");
            if (pvr is null) continue;

            var vid = pvr.Value.TryGet("videoId")?.GetString();
            if (string.IsNullOrEmpty(vid)) continue;

            var pvrTitle = GetRunText(pvr.Value.TryGet("title")?.TryGet("runs")) ?? "";
            var pvrAuthor = GetRunText(pvr.Value.TryGet("shortBylineText")?.TryGet("runs")) ?? "";
            var pvrLen = pvr.Value.TryGet("lengthText")?.TryGet("simpleText")?.GetString()
                ?? GetRunText(pvr.Value.TryGet("lengthText")?.TryGet("runs")) ?? "";
            var (pvrDur, pvrDurSec) = ParseDuration(pvrLen);

            results.Add(new VideoResult
            {
                Id = vid,
                Title = WebUtility.HtmlDecode(string.IsNullOrEmpty(pvrTitle) ? $"Video {vid}" : pvrTitle),
                Author = string.IsNullOrEmpty(pvrAuthor) ? "YouTube" : pvrAuthor,
                Thumbnail = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
                Thumbnails = [new ThumbnailInfo { Url = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg", Width = 480, Height = 360 }],
                FullUrl = $"https://www.youtube.com/watch?v={vid}",
                EmbedUrl = $"https://www.youtube.com/embed/{vid}?rel=0",
                Duration = pvrDur,
                DurationSeconds = pvrDurSec,
            });
        }

        return results;
    }

    // ── New Public API methods ──

    public static List<VideoResult> SearchTrending(int limit = 15)
    {
        if (limit < 1) limit = 1;
        if (limit > 50) limit = 50;

        var html = _http.GetStringAsync("https://www.youtube.com/feed/trending")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        return ParseTrendingResults(doc.RootElement, limit);
    }

    public static List<VideoResult> SearchChannel(string channelId, int limit = 15)
    {
        ArgumentNullException.ThrowIfNull(channelId);
        if (limit < 1) limit = 1;
        if (limit > 50) limit = 50;

        var html = _http.GetStringAsync($"https://www.youtube.com/channel/{Uri.EscapeDataString(channelId)}/videos")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        return ParseChannelResults(doc.RootElement, limit);
    }

    public static List<VideoResult> SearchPlaylist(string playlistId, int limit = 15)
    {
        ArgumentNullException.ThrowIfNull(playlistId);
        if (limit < 1) limit = 1;
        if (limit > 50) limit = 50;

        var html = _http.GetStringAsync($"https://www.youtube.com/playlist?list={Uri.EscapeDataString(playlistId)}")
            .GetAwaiter().GetResult();

        var json = ExtractJson(html, "var ytInitialData");
        if (json is null) return [];

        using var doc = JsonDocument.Parse(json);
        return ParsePlaylistResults(doc.RootElement, limit);
    }
}
