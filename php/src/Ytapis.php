<?php

declare(strict_types=1);

namespace GeethuDino\Ytapis;

final class Ytapis
{
    private const SEARCH_URL = 'https://www.youtube.com/results?search_query=';
    private const INNERTUBE_URL = 'https://www.youtube.com/youtubei/v1/search';
    private const OEMBED_URL = 'https://www.youtube.com/oembed?url=https://www.youtube.com/watch=';

    private const DEFAULT_API_KEY = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

    private const DEFAULT_CONTEXT = [
        'client' => [
            'hl' => 'en',
            'gl' => 'US',
            'clientName' => 'WEB',
            'clientVersion' => '2.20240801.00.00',
        ],
    ];

    private static function fallbackResult(string $id): VideoResult
    {
        return new VideoResult(
            id: $id,
            title: "Video {$id}",
            author: 'YouTube',
            thumbnail: "https://i.ytimg.com/vi/{$id}/hqdefault.jpg",
            thumbnails: [
                ['url' => "https://i.ytimg.com/vi/{$id}/hqdefault.jpg", 'width' => 480, 'height' => 360],
            ],
            fullUrl: "https://www.youtube.com/watch?v={$id}",
            embedUrl: "https://www.youtube.com/embed/{$id}?rel=0",
        );
    }

    private static function fetch(string $url, ?string $postBody = null, array $headers = []): ?string
    {
        $ch = curl_init($url);
        if ($ch === false) {
            return null;
        }

        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT => 15,
            CURLOPT_USERAGENT => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
            CURLOPT_SSL_VERIFYPEER => true,
        ]);

        if ($postBody !== null) {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $postBody);
        }

        if (!empty($headers)) {
            curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        }

        $body = curl_exec($ch);
        curl_close($ch);

        return $body !== false ? $body : null;
    }

    private static function fetchJson(string $url, ?string $postBody = null, array $headers = []): ?array
    {
        $body = self::fetch($url, $postBody, $headers);
        if ($body === null) {
            return null;
        }

        try {
            $data = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
            return is_array($data) ? $data : null;
        } catch (\JsonException) {
            return null;
        }
    }

    /**
     * @return array{duration: string, seconds: int}
     */
    private static function parseDuration(string $text): array
    {
        $parts = array_map('intval', explode(':', $text));
        if (count($parts) === 3) {
            return [
                'duration' => $text,
                'seconds' => $parts[0] * 3600 + $parts[1] * 60 + $parts[2],
            ];
        }
        if (count($parts) === 2) {
            return [
                'duration' => $text,
                'seconds' => $parts[0] * 60 + $parts[1],
            ];
        }
        return [
            'duration' => $text,
            'seconds' => (int) $text ?: 0,
        ];
    }

    /**
     * @return array{viewCount: string, raw: int}
     */
    private static function parseViewCount(string $text): array
    {
        if (empty($text)) {
            return ['viewCount' => '', 'raw' => 0];
        }

        $cleaned = preg_replace('/[^0-9.KMBkmb]/', '', $text);
        $num = (float) preg_replace('/[KMBkmb]/', '', $cleaned);
        $multiplier = 1;

        if (stripos($cleaned, 'B') !== false) {
            $multiplier = 1_000_000_000;
        } elseif (stripos($cleaned, 'M') !== false) {
            $multiplier = 1_000_000;
        } elseif (stripos($cleaned, 'K') !== false) {
            $multiplier = 1_000;
        }

        return [
            'viewCount' => $text,
            'raw' => (int) round($num * $multiplier),
        ];
    }

    private static function thumbnailQualityScore(string $url): int
    {
        if (empty($url)) {
            return 0;
        }
        if (str_contains($url, 'maxresdefault')) {
            return 1280;
        }
        if (str_contains($url, 'sddefault')) {
            return 640;
        }
        if (str_contains($url, 'hqdefault')) {
            return 480;
        }
        if (str_contains($url, 'mqdefault')) {
            return 320;
        }
        if (str_contains($url, 'default')) {
            return 120;
        }
        return 0;
    }

    /**
     * @param array<array-key, array{url?: string, width?: int, height?: int}> $thumbnails
     */
    private static function extractBestThumbnail(array $thumbnails): string
    {
        if (empty($thumbnails)) {
            return '';
        }

        $best = $thumbnails[0];
        $bestScore = self::thumbnailQualityScore($best['url'] ?? '');
        foreach ($thumbnails as $t) {
            $score = ($t['width'] ?? 0) > 0 ? ($t['width'] ?? 0) : self::thumbnailQualityScore($t['url'] ?? '');
            if ($score > $bestScore) {
                $best = $t;
                $bestScore = $score;
            }
        }

        return $best['url'] ?? '';
    }

    /**
     * @param array<array-key, string|null>|null $runs
     */
    private static function extractRuns(?array $runs): string
    {
        if (empty($runs)) {
            return '';
        }

        return implode('', array_map(
            fn(array $r): string => $r['text'] ?? '',
            $runs,
        ));
    }

    /**
     * @param array<string, mixed> $vr
     */
    private static function parseVideoRenderer(array $vr): ?VideoResult
    {
        try {
            $id = $vr['videoId'] ?? null;
            if (empty($id) || !is_string($id)) {
                return null;
            }

            $title = self::extractRuns($vr['title']['runs'] ?? null);
            $author = self::extractRuns($vr['ownerText']['runs'] ?? null);
            $channelUrl = $vr['ownerText']['runs'][0]['navigationEndpoint']['browseEndpoint']['canonicalBaseUrl'] ?? '';

            $rawThumbs = $vr['thumbnail']['thumbnails'] ?? [];
            $thumbnails = array_map(
                fn(array $t): array => [
                    'url' => $t['url'] ?? '',
                    'width' => $t['width'] ?? 0,
                    'height' => $t['height'] ?? 0,
                ],
                $rawThumbs,
            );
            $thumbnail = self::extractBestThumbnail($thumbnails);

            $durText = $vr['lengthText']['simpleText']
                ?? self::extractRuns($vr['lengthText']['runs'] ?? null)
                ?? '';
            ['duration' => $duration, 'seconds' => $durationSeconds] = self::parseDuration($durText);

            $vcText = $vr['viewCountText']['simpleText']
                ?? self::extractRuns($vr['viewCountText']['runs'] ?? null)
                ?? '';
            ['viewCount' => $viewCount, 'raw' => $viewCountRaw] = self::parseViewCount($vcText);

            $publishedTime = $vr['publishedTimeText']['simpleText'] ?? '';

            $descRuns = $vr['detailedMetadataSnippets'][0]['snippetText']['runs']
                ?? $vr['descriptionSnippet']['runs']
                ?? null;
            $description = self::extractRuns($descRuns);

            $channelThumbs = $vr['channelThumbnailSupportedRenderers']['channelThumbnailWithLinkRenderer']['thumbnail']['thumbnails']
                ?? null;
            $channelAvatar = is_array($channelThumbs) ? self::extractBestThumbnail($channelThumbs) : '';

            $badges = array_map(
                fn(array $b): string => $b['metadataBadgeRenderer']['style']
                    ?? $b['metadataBadgeRenderer']['label']
                    ?? '',
                $vr['badges'] ?? [],
            );

            $fallback = self::fallbackResult($id);

            return new VideoResult(
                id: $id,
                title: $title ?: $fallback->title,
                author: $author ?: $fallback->author,
                channelUrl: $channelUrl,
                thumbnail: $thumbnail ?: $fallback->thumbnail,
                thumbnails: !empty($thumbnails) ? $thumbnails : $fallback->thumbnails,
                fullUrl: "https://www.youtube.com/watch?v={$id}",
                embedUrl: "https://www.youtube.com/embed/{$id}?rel=0",
                duration: $duration,
                durationSeconds: $durationSeconds,
                viewCount: $viewCount,
                viewCountRaw: $viewCountRaw,
                publishedTime: $publishedTime,
                description: $description,
                channelAvatar: $channelAvatar,
                isLive: self::badgeContains($badges, 'LIVE'),
                isUpcoming: self::badgeContains($badges, 'UPCOMING'),
                isVerified: self::badgeContains($badges, 'VERIFIED'),
            );
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * @param string[] $badges
     */
    private static function badgeContains(array $badges, string $needle): bool
    {
        foreach ($badges as $badge) {
            if (is_string($badge) && stripos($badge, $needle) !== false) {
                return true;
            }
        }
        return false;
    }

    /**
     * Extract a JSON object from HTML by finding a prefix then brace-counting.
     */
    private static function extractJson(string $html, string $prefix): ?array
    {
        $idx = strpos($html, $prefix);
        if ($idx === false) {
            return null;
        }

        $start = strpos($html, '{', $idx);
        if ($start === false) {
            return null;
        }

        $depth = 0;
        $inString = false;
        $escaped = false;
        $len = strlen($html);

        for ($i = $start; $i < $len; $i++) {
            $ch = $html[$i];

            if ($escaped) {
                $escaped = false;
                continue;
            }

            if ($ch === '\\') {
                $escaped = true;
                continue;
            }

            if ($ch === '"') {
                $inString = !$inString;
                continue;
            }

            if ($inString) {
                continue;
            }

            if ($ch === '{') {
                $depth++;
            }

            if ($ch === '}') {
                $depth--;
                if ($depth === 0) {
                    $json = substr($html, $start, $i - $start + 1);
                    $decoded = json_decode($json, true);
                    return is_array($decoded) ? $decoded : null;
                }
            }
        }

        return null;
    }

    /**
     * @return array{results: VideoResult[], continuation: ?string}
     */
    private static function parseSearchResults(array $data, int $limit): array
    {
        $results = [];
        $continuation = null;

        try {
            $contents = $data['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents'] ?? null;
            if (!is_array($contents)) {
                return ['results' => [], 'continuation' => null];
            }

            foreach ($contents as $section) {
                if (count($results) >= $limit) {
                    break;
                }

                if (isset($section['itemSectionRenderer']['contents'])) {
                    foreach ($section['itemSectionRenderer']['contents'] as $item) {
                        if (count($results) >= $limit) {
                            break;
                        }
                        if (isset($item['videoRenderer'])) {
                            $vr = self::parseVideoRenderer($item['videoRenderer']);
                            if ($vr !== null) {
                                $results[] = $vr;
    /**
     * @return array{results: VideoResult[], continuation: ?string}
     */
    private static function parseTrendingResults(array $data, int $limit): array
    {
        $results = [];
        $continuation = null;

        try {
            $tabs = $data['contents']['twoColumnBrowseResultsRenderer']['tabs'] ?? null;
            if (!is_array($tabs)) {
                return ['results' => [], 'continuation' => null];
            }

            foreach ($tabs as $tab) {
                $contents = $tab['tabRenderer']['content']['sectionListRenderer']['contents'] ?? null;
                if (!is_array($contents)) {
                    continue;
                }

                foreach ($contents as $section) {
                    if (count($results) >= $limit) {
                        break;
                    }

                    if (isset($section['itemSectionRenderer']['contents'])) {
                        foreach ($section['itemSectionRenderer']['contents'] as $item) {
                            if (count($results) >= $limit) {
                                break;
                            }
                            if (isset($item['videoRenderer'])) {
                                $vr = self::parseVideoRenderer($item['videoRenderer']);
                                if ($vr !== null) {
                                    $results[] = $vr;
                                }
                            }
                        }
                    }

                    if (isset($section['shelfRenderer']['content'])) {
                        $shelfItems = $section['shelfRenderer']['content']['expandedShelfContentsRenderer']['items']
                            ?? $section['shelfRenderer']['content']['horizontalListRenderer']['items']
                            ?? null;
                        if (is_array($shelfItems)) {
                            foreach ($shelfItems as $item) {
                                if (count($results) >= $limit) {
                                    break;
                                }
                                if (isset($item['videoRenderer'])) {
                                    $vr = self::parseVideoRenderer($item['videoRenderer']);
                                    if ($vr !== null) {
                                        $results[] = $vr;

    // ─── New Types ──────────────────────────────────────────────────────────

    public static function getComments(
        string $videoId, int $limit = 20, ?string $continuation = null, string $sortBy = 'top'
    ): array {
        $limit = max(1, min($limit, 100));

        try {
            $html = self::fetch("https://www.youtube.com/watch?v={$videoId}");
            if ($html === null) {
                return ['comments' => [], 'continuation' => null];
            }

            if ($continuation !== null) {
                preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
                $apiKey = $apiKeyMatches[1] ?? self::DEFAULT_API_KEY;
                $ctx = self::extractJson($html, '"INNERTUBE_CONTEXT"');

                $body = json_encode([
                    'context' => $ctx ?? self::DEFAULT_CONTEXT,
                    'continuation' => $continuation,
                ], JSON_UNESCAPED_SLASHES);

                $data = self::fetchJson(
                    "https://www.youtube.com/youtubei/v1/next?key={$apiKey}",
                    $body,
                    ['Content-Type: application/json'],
                );

                $items = $data['onResponseReceivedEndpoints'][0]['reloadContinuationItemsCommand']['continuationItems']
                    ?? $data['onResponseReceivedEndpoints'][0]['appendContinuationItemsAction']['continuationItems']
                    ?? null;
                if (!is_array($items)) {
                    return ['comments' => [], 'continuation' => null];
                }

                return self::parseCommentThreads($items, $limit);
            }

            $data = self::extractJson($html, 'var ytInitialData');
            if ($data === null) {
                return ['comments' => [], 'continuation' => null];
            }

            preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
            $apiKey = $apiKeyMatches[1] ?? self::DEFAULT_API_KEY;
            $ctx = self::extractJson($html, '"INNERTUBE_CONTEXT"');

            $allResults = $data['contents']['twoColumnWatchNextResults']['results']['results']['contents'] ?? [];
            $token = self::extractCommentsToken($allResults);
            if ($token === null) {
                return ['comments' => [], 'continuation' => null];
            }

            $body = json_encode([
                'context' => $ctx ?? self::DEFAULT_CONTEXT,
                'continuation' => $token,
            ], JSON_UNESCAPED_SLASHES);

            $nd = self::fetchJson(
                "https://www.youtube.com/youtubei/v1/next?key={$apiKey}",
                $body,
                ['Content-Type: application/json'],
            );

            $nItems = $nd['onResponseReceivedEndpoints'][0]['reloadContinuationItemsCommand']['continuationItems']
                ?? $nd['onResponseReceivedEndpoints'][0]['appendContinuationItemsAction']['continuationItems']
                ?? $nd['onResponseReceivedEndpoints'][1]['reloadContinuationItemsCommand']['continuationItems']
                ?? $nd['onResponseReceivedEndpoints'][1]['appendContinuationItemsAction']['continuationItems']
                ?? null;

            if (!is_array($nItems)) {
                return ['comments' => [], 'continuation' => null];
            }

            return self::parseCommentThreads($nItems, $limit);
        } catch (\Throwable) {
            return ['comments' => [], 'continuation' => null];
        }
    }

    private static function extractCommentsToken(array $allResults): ?string
    {
        foreach ($allResults as $c) {
            $items = $c['itemSectionRenderer']['contents'] ?? [];
            foreach ($items as $item) {
                $token = $item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'] ?? null;
                if ($token !== null) {
                    return $token;
                }
                $token = $item['commentsEntryPointHeaderRenderer']['contents'][0]['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'] ?? null;
                if ($token !== null) {
                    return $token;
                }
            }
        }
        return null;
    }

    /**
     * @param array<array-key, mixed> $items
     * @return array{comments: array<array-key, array>, continuation: ?string}
     */
    private static function parseCommentThreads(array $items, int $limit): array
    {
        $comments = [];
        $continuation = null;

        foreach ($items as $item) {
            if (count($comments) >= $limit) {
                break;
            }

            if (isset($item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                $continuation = $item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
            }

            if (isset($item['commentThreadRenderer']['comment']['commentRenderer'])) {
                $cr = $item['commentThreadRenderer']['comment']['commentRenderer'];
                if (isset($item['commentThreadRenderer']['replies'])) {
                    $cr['replies'] = $item['commentThreadRenderer']['replies'];
                }
                $comments[] = self::parseCommentRenderer($cr);
            }
        }

        return ['comments' => $comments, 'continuation' => $continuation];
    }

    /**
     * @param array<string, mixed> $cr
     * @return array<string, mixed>
     */
    private static function parseCommentRenderer(array $cr): array
    {
        $id = $cr['commentId'] ?? $cr['properties']['commentId'] ?? '';
        $authorName = self::extractRuns($cr['authorText']['runs'] ?? null) ?: ($cr['authorText']['simpleText'] ?? '');
        $authorChannel = $cr['authorEndpoint']['browseEndpoint']['browseId'] ?? '';
        $authorThumbs = $cr['authorThumbnail']['thumbnails'] ?? [];
        $authorAvatar = '';
        if (!empty($authorThumbs)) {
            $last = end($authorThumbs);
            $authorAvatar = $last['url'] ?? '';
        }
        $isVerified = ($cr['authorCommentBadge']['authorCommentBadgeRenderer']['icon']['iconType'] ?? '') === 'CHECK';
        $isOwner = $cr['authorIsChannelOwner'] ?? false;
        $text = $cr['contentText']['simpleText'] ?? self::extractRuns($cr['contentText']['runs'] ?? null) ?? '';
        $likeCount = (int) ($cr['voteCount']['simpleText'] ?? $cr['likeCount'] ?? '0');
        $publishedTime = $cr['publishedTimeText']['runs'][0]['text'] ?? '';
        $replyCount = (int) ($cr['replyCount'] ?? 0);
        $isLiked = $cr['isLiked'] ?? false;
        $isPinned = isset($cr['pinnedCommentBadge']['pinnedCommentBadgeRenderer']);

        $replies = [];
        $replyContinuation = null;
        $replyItems = $cr['replies']['commentRepliesRenderer']['contents'] ?? null;
        if (is_array($replyItems)) {
            foreach ($replyItems as $ri) {
                if (isset($ri['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                    $replyContinuation = $ri['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
                    continue;
                }
                if (isset($ri['commentRenderer'])) {
                    $rr = $ri['commentRenderer'];
                    $replies[] = [
                        'id' => $rr['commentId'] ?? '',
                        'author' => [
                            'name' => self::extractRuns($rr['authorText']['runs'] ?? null) ?: ($rr['authorText']['simpleText'] ?? ''),
                            'channelId' => $rr['authorEndpoint']['browseEndpoint']['browseId'] ?? '',
                            'avatar' => self::getLastThumbUrl($rr['authorThumbnail']['thumbnails'] ?? []),
                            'isVerified' => false,
                            'isOwner' => $rr['authorIsChannelOwner'] ?? false,
                        ],
                        'text' => $rr['contentText']['simpleText'] ?? self::extractRuns($rr['contentText']['runs'] ?? null) ?? '',
                        'likeCount' => (int) ($rr['voteCount']['simpleText'] ?? '0'),
                        'likeCountRaw' => (int) ($rr['voteCount']['simpleText'] ?? '0'),
                        'publishedTime' => $rr['publishedTimeText']['runs'][0]['text'] ?? '',
                        'isLikedByCreator' => $rr['actionButtons']['commentActionButtonsRenderer']['creatorHeart']['creatorHeartRenderer']['isHearted'] ?? false,
                    ];
                }
            }
        }

        return [
            'id' => $id,
            'author' => [
                'name' => $authorName,
                'channelId' => $authorChannel,
                'avatar' => $authorAvatar,
                'isVerified' => $isVerified,
                'isOwner' => $isOwner,
            ],
            'text' => $text,
            'likeCount' => $likeCount,
            'likeCountRaw' => $likeCount,
            'publishedTime' => $publishedTime,
            'replyCount' => $replyCount,
            'isLikedByCreator' => $isLiked,
            'isPinned' => $isPinned,
            'replies' => $replies,
            'replyContinuation' => $replyContinuation,
        ];
    }

    private static function getLastThumbUrl(array $thumbs): string
    {
        if (empty($thumbs)) {
            return '';
        }
        $last = end($thumbs);
        return $last['url'] ?? '';
    }

    // ─── Public: Related Videos ─────────────────────────────────────────────

    /**
     * @return array<int, array<string, mixed>>
     */
    public static function getRelatedVideos(string $videoId, int $limit = 15): array
    {
        $limit = max(1, min($limit, 50));

        try {
            $html = self::fetch("https://www.youtube.com/watch?v={$videoId}");
            if ($html === null) {
                return [];
            }

            $data = self::extractJson($html, 'var ytInitialData');
            if ($data === null) {
                return [];
            }

            $watchNext = $data['contents']['twoColumnWatchNextResults']['secondaryResults']['secondaryResults']['results'] ?? null;
            if (!is_array($watchNext)) {
                return [];
            }

            $results = [];
            foreach ($watchNext as $item) {
                if (count($results) >= $limit) {
                    break;
                }
                $vr = $item['compactVideoRenderer'] ?? $item['compactRadioRenderer'] ?? null;
                if (!is_array($vr)) {
                    continue;
                }
                $vid = $vr['videoId'] ?? null;
                if (empty($vid)) {
                    continue;
                }

                $title = self::extractRuns($vr['title']['runs'] ?? null) ?: ($vr['title']['simpleText'] ?? '');
                $author = self::extractRuns($vr['shortBylineText']['runs'] ?? null) ?: ($vr['shortBylineText']['simpleText'] ?? '');
                $durText = $vr['lengthText']['simpleText'] ?? self::extractRuns($vr['lengthText']['runs'] ?? null) ?? '';
                ['duration' => $duration, 'seconds' => $durationSeconds] = self::parseDuration($durText);
                $viewsText = $vr['viewCountText']['simpleText'] ?? self::extractRuns($vr['viewCountText']['runs'] ?? null) ?? '';
                ['viewCount' => $viewCount, 'raw' => $viewCountRaw] = self::parseViewCount($viewsText);
                $publishedTime = $vr['publishedTimeText']['simpleText'] ?? '';
                $thumbnails = array_map(
                    fn(array $t): array => ['url' => $t['url'] ?? '', 'width' => $t['width'] ?? 0, 'height' => $t['height'] ?? 0],
                    $vr['thumbnail']['thumbnails'] ?? [],
                );
                $thumbnail = self::extractBestThumbnail($thumbnails) ?: "https://i.ytimg.com/vi/{$vid}/hqdefault.jpg";
                $badge = $vr['badges'][0]['metadataBadgeRenderer']['style'] ?? '';

                $results[] = [
                    'id' => $vid,
                    'title' => html_entity_decode($title, ENT_QUOTES, 'UTF-8'),
                    'author' => $author,
                    'channelUrl' => $vr['shortBylineText']['runs'][0]['navigationEndpoint']['browseEndpoint']['canonicalBaseUrl'] ?? '',
                    'duration' => $duration,
                    'durationSeconds' => $durationSeconds,
                    'viewCount' => $viewCount,
                    'viewCountRaw' => (int) round($viewCountRaw),
                    'publishedTime' => $publishedTime,
                    'thumbnail' => $thumbnail,
                    'isLive' => stripos($badge, 'LIVE') !== false,
                ];
            }
            return $results;
        } catch (\Throwable) {
            return [];
        }
    }

    // ─── Public: Live Stream Info + Stats ────────────────────────────────────

    /**
     * @return array{views: int, likes: int, comments: int, isLive: bool, viewerCount: int}
     */
    public static function getVideoStats(string $videoId): array
    {
        try {
            $html = self::fetch("https://www.youtube.com/watch?v={$videoId}");
            if ($html === null) {
                return ['views' => 0, 'likes' => 0, 'comments' => 0, 'isLive' => false, 'viewerCount' => 0];
            }

            $data = self::extractJson($html, 'var ytInitialData');
            if ($data === null) {
                return ['views' => 0, 'likes' => 0, 'comments' => 0, 'isLive' => false, 'viewerCount' => 0];
            }

            $contents = $data['contents']['twoColumnWatchNextResults']['results']['results']['contents'] ?? [];
            $primary = null;
            foreach ($contents as $c) {
                if (isset($c['videoPrimaryInfoRenderer'])) {
                    $primary = $c['videoPrimaryInfoRenderer'];
                    break;
                }
            }

            $vcr = $primary['viewCount']['videoViewCountRenderer'] ?? null;
            $viewsText = $vcr['shortViewCount']['simpleText'] ?? $vcr['viewCount']['simpleText'] ?? '';
            ['raw' => $views] = self::parseViewCount($viewsText);

            $likesStr = $primary['videoActions']['menuRenderer']['topLevelButtons'][0]
                ['segmentedLikeDislikeButtonViewModel']['likeButtonViewModel']['likeButtonViewModel']
                ['toggleButtonViewModel']['toggleButtonViewModel']['defaultButtonViewModel']
                ['buttonViewModel']['accessibilityText'] ?? '';
            ['raw' => $likes] = self::parseViewCount(preg_replace('/[^0-9.KMBkmb]/', '', $likesStr));

            $isLive = strpos($html, '"isLive":true') !== false;
            preg_match('/"viewCount":\{"videoViewCountRenderer":\{"isLive":true,"viewCount":\{"simpleText":"([^"]+)"/', $html, $vcm);
            $viewerCount = isset($vcm[1]) ? self::parseViewCount($vcm[1])['raw'] : 0;

            return [
                'views' => (int) $views,
                'likes' => (int) round($likes),
                'comments' => 0,
                'isLive' => $isLive,
                'viewerCount' => (int) $viewerCount,
            ];
        } catch (\Throwable) {
            return ['views' => 0, 'likes' => 0, 'comments' => 0, 'isLive' => false, 'viewerCount' => 0];
        }
    }

    /**
     * @return array{isLive: bool, isUpcoming: bool, viewerCount: int, viewerCountStr: string, startTime: string, scheduledStartTime: string, likesCount: int, dislikesCount: int}
     */
    public static function getLiveStreamInfo(string $videoId): array
    {
        $stats = self::getVideoStats($videoId);
        try {
            $html = self::fetch("https://www.youtube.com/watch?v={$videoId}");
            $data = self::extractJson($html, 'var ytInitialData');

            $primary = null;
            if ($data !== null) {
                $contents = $data['contents']['twoColumnWatchNextResults']['results']['results']['contents'] ?? [];
                foreach ($contents as $c) {
                    if (isset($c['videoPrimaryInfoRenderer'])) {
                        $primary = $c['videoPrimaryInfoRenderer'];
                        break;
                    }
                }
            }

            return [
                'isLive' => $stats['isLive'],
                'isUpcoming' => $stats['isLive'] === false && $stats['viewerCount'] === 0,
                'viewerCount' => $stats['viewerCount'],
                'viewerCountStr' => number_format($stats['viewerCount']),
                'startTime' => $primary['dateText']['simpleText'] ?? '',
                'scheduledStartTime' => $primary['upcomingEventData']['startTime'] ?? '',
                'likesCount' => $stats['likes'],
                'dislikesCount' => 0,
            ];
        } catch (\Throwable) {
            return [
                'isLive' => $stats['isLive'],
                'isUpcoming' => false,
                'viewerCount' => $stats['viewerCount'],
                'viewerCountStr' => number_format($stats['viewerCount']),
                'startTime' => '',
                'scheduledStartTime' => '',
                'likesCount' => $stats['likes'],
                'dislikesCount' => 0,
            ];
        }
    }

    // ─── Channel Metadata ───────────────────────────────────────────────────

    /**
     * @return array{id: string, name: string, handle: string, description: string, subscriberCount: string, subscriberCountRaw: int, videoCount: string, videoCountRaw: int, avatar: string, banner: string, isVerified: bool, socialLinks: array<int, array{title: string, url: string, icon: string}>, url: string}
     */
    public static function getChannelMetadata(string $channelId): array
    {
        $empty = [
            'id' => $channelId,
            'name' => '',
            'handle' => '',
            'description' => '',
            'subscriberCount' => '',
            'subscriberCountRaw' => 0,
            'videoCount' => '',
            'videoCountRaw' => 0,
            'avatar' => '',
            'banner' => '',
            'isVerified' => false,
            'socialLinks' => [],
            'url' => "https://www.youtube.com/channel/{$channelId}",
        ];

        try {
            $html = self::fetch("https://www.youtube.com/channel/{$channelId}/about");
            if ($html === null) {
                return $empty;
            }

            $data = self::extractJson($html, 'var ytInitialData');
            if ($data === null) {
                return $empty;
            }

            $metadata = $data['metadata']['channelMetadataRenderer'] ?? null;

            $header = $data['header']['c4TabbedHeaderRenderer'] ?? null;

            $aboutRenderer = null;
            $tabs = $data['contents']['twoColumnBrowseResultsRenderer']['tabs'] ?? [];
            foreach ($tabs as $tab) {
                if (($tab['tabRenderer']['selected'] ?? false)) {
                    $aboutRenderer = $tab['tabRenderer']['content']['sectionListRenderer']['contents'][0]
                        ['itemSectionRenderer']['contents'][0]['channelAboutFullMetadataRenderer'] ?? null;
                    break;
                }
            }

            $subText = $header['subscriberCountText']['simpleText'] ?? '';
            ['viewCount' => $subCount, 'raw' => $subRaw] = self::parseViewCount($subText);

            $videoText = $aboutRenderer['videoCountText']['runs'][0]['text'] ?? '';
            $vcRaw = 0;
            if (preg_match('/([\d,]+)/', $videoText, $m)) {
                $vcRaw = (int) str_replace(',', '', $m[1]);
            }

            $links = [];
            foreach (($aboutRenderer['primaryLinks'] ?? []) as $l) {
                $nav = $l['navigationEndpoint']['urlEndpoint'] ?? null;
                $links[] = [
                    'title' => $l['title']['simpleText'] ?? $l['title']['runs'][0]['text'] ?? '',
                    'url' => $nav['url'] ?? '',
                    'icon' => $l['icon']['thumbnails'][0]['url'] ?? '',
                ];
            }

            $name = $metadata['title'] ?? $header['title'] ?? '';
            $vanityUrl = $metadata['vanityChannelUrl'] ?? '';
            $handle = '';
            if (!empty($vanityUrl)) {
                $handle = str_replace(['http://www.youtube.com/', 'https://www.youtube.com/'], '', $vanityUrl);
            }

            $desc = $metadata['description'] ?? $aboutRenderer['description']['simpleText']
                ?? implode('', array_map(fn(array $r): string => $r['text'] ?? '', $aboutRenderer['description']['runs'] ?? []))
                ?? '';

            $avatarThumbs = $metadata['avatar']['thumbnails'] ?? $header['avatar']['thumbnails'] ?? [];
            $avatar = self::extractBestThumbnail($avatarThumbs);

            $bannerThumbs = $metadata['banner']['thumbnails'] ?? $header['banner']['thumbnails'] ?? [];
            $banner = self::extractBestThumbnail($bannerThumbs);

            $isVerified = false;
            foreach (($header['badges'] ?? []) as $badge) {
                $style = $badge['metadataBadgeRenderer']['style'] ?? '';
                if (str_contains($style, 'VERIFIED')) {
                    $isVerified = true;
                    break;
                }
            }

            return [
                'id' => $channelId,
                'name' => $name,
                'handle' => $handle,
                'description' => $desc,
                'subscriberCount' => $subCount,
                'subscriberCountRaw' => (int) round($subRaw),
                'videoCount' => $videoText,
                'videoCountRaw' => $vcRaw,
                'avatar' => $avatar,
                'banner' => $banner,
                'isVerified' => $isVerified,
                'socialLinks' => $links,
                'url' => "https://www.youtube.com/channel/{$channelId}",
            ];
        } catch (\Throwable) {
            return $empty;
        }
    }

    // ─── Transcripts ────────────────────────────────────────────────────────

    /**
     * @return array<int, array{text: string, start: float, duration: float}>
     */
    public static function getTranscript(string $videoId, ?string $lang = null): array
    {
        try {
            $html = self::fetch("https://www.youtube.com/watch?v={$videoId}");
            if ($html === null) {
                return [];
            }

            $tracksStr = null;
            if (preg_match('/"captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])/', $html, $m)) {
                $tracksStr = $m[1];
            } elseif (preg_match('/"captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])/', $html, $m)) {
                $tracksStr = $m[1];
            }

            if ($tracksStr === null) {
                return [];
            }

            $tracks = json_decode($tracksStr, true);
            if (!is_array($tracks)) {
                return [];
            }

            $trackUrl = '';
            if ($lang !== null) {
                foreach ($tracks as $track) {
                    $lc = $track['languageCode'] ?? '';
                    $tn = $track['name']['simpleText'] ?? '';
                    if ($lc === $lang || stripos($tn, $lang) !== false) {
                        $trackUrl = $track['baseUrl'] ?? '';
                        break;
                    }
                }
            }
            if (empty($trackUrl)) {
                foreach ($tracks as $track) {
                    if (($track['languageCode'] ?? '') === 'en') {
                        $trackUrl = $track['baseUrl'] ?? '';
                        break;
                    }
                }
            }
            if (empty($trackUrl) && !empty($tracks)) {
                $trackUrl = $tracks[0]['baseUrl'] ?? '';
            }
            if (empty($trackUrl)) {
                return [];
            }

            $xml = self::fetch($trackUrl);
            if ($xml === null) {
                return [];
            }

            $entries = [];
            if (preg_match_all('/<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:<\/text>)?$/m', $xml, $matches, PREG_SET_ORDER)) {
                foreach ($matches as $m) {
                    $rawText = htmlspecialchars_decode(strip_tags($m[3]), ENT_QUOTES);
                    if (trim($rawText) !== '') {
                        $entries[] = [
                            'text' => trim($rawText),
                            'start' => (float) $m[1],
                            'duration' => (float) $m[2],
                        ];
                    }
                }
            }
            return $entries;
        } catch (\Throwable) {
            return [];
        }
    }

    // ─── Shorts Search ──────────────────────────────────────────────────────

    /**
     * @return array{results: VideoResult[], continuation: ?string, apiKey: ?string, context: ?array}
     */
    public static function searchShorts(string $query, int $limit = 15, ?string $gl = null, ?string $hl = null): array
    {
        $limit = max(1, min($limit, 50));
        $region = '';
        if ($gl !== null) {
            $region .= "&gl={$gl}";
        }
        if ($hl !== null) {
            $region .= "&hl={$hl}";
        }

        $encoded = urlencode($query);
        $html = self::fetch("https://www.youtube.com/results?search_query={$encoded}&sp=EgIYAQ%3D%3D{$region}");
        if ($html === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        $data = self::extractJson($html, 'var ytInitialData');
        if ($data === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
        $apiKey = $apiKeyMatches[1] ?? null;
        $context = self::extractJson($html, '"INNERTUBE_CONTEXT"');

        $contents = $data['contents']['twoColumnSearchResultsRenderer']['primaryContents']['sectionListRenderer']['contents'] ?? [];
        $shortsRenderer = null;
        foreach ($contents as $section) {
            $firstItem = $section['itemSectionRenderer']['contents'][0] ?? null;
            if ($firstItem !== null && isset($firstItem['reelShelfRenderer'])) {
                $shortsRenderer = $firstItem;
                break;
            }
        }

        if ($shortsRenderer !== null) {
            $reelItems = $shortsRenderer['reelShelfRenderer']['items'] ?? [];

            $shortResults = [];
            foreach ($reelItems as $item) {
                if (count($shortResults) >= $limit) {
                    break;
                }
                $ri = $item['reelItemRenderer'] ?? $item['shortsLockupViewModel'] ?? null;
                $vid = $ri['videoId'] ?? $item['reelItemRenderer']['videoId'] ?? null;
                if (empty($vid)) {
                    continue;
                }

                $title = $ri['headline']['simpleText']
                    ?? implode('', array_map(fn(array $r): string => $r['text'] ?? '', $ri['headline']['runs'] ?? []))
                    ?? '';
                $dur = (int) ($ri['lengthText']['simpleText'] ?? 0);

                $fb = self::fallbackResult($vid);
                $shortResults[] = new VideoResult(
                    id: $vid,
                    title: empty($title) ? "Shorts {$vid}" : $title,
                    duration: "{$dur}s",
                    durationSeconds: $dur,
                    isLive: false,
                    isUpcoming: false,
                    isVerified: false,
                );
            }

            $allParsed = self::parseSearchResults($data, $limit);
            $combined = [];
            $seen = [];
            foreach ($shortResults as $r) {
                if (!isset($seen[$r->id])) {
                    $seen[$r->id] = true;
                    $combined[] = $r;
                }
            }
            foreach ($allParsed['results'] as $r) {
                if (!isset($seen[$r->id]) && count($combined) < $limit) {
                    $seen[$r->id] = true;
                    $combined[] = $r;
                }
            }

            return [
                'results' => $combined,
                'continuation' => $allParsed['continuation'] ?? null,
                'apiKey' => $apiKey,
                'context' => $context,
            ];
        }

        ['results' => $results, 'continuation' => $continuation] = self::parseSearchResults($data, $limit);

        return [
            'results' => $results,
            'continuation' => $continuation,
            'apiKey' => $apiKey,
            'context' => $context,
        ];
    }

    // ─── Region-aware search helpers ────────────────────────────────────────

    private static function buildRegionParams(?string $gl = null, ?string $hl = null): string
    {
        $parts = [];
        if ($gl !== null) {
            $parts[] = "gl={$gl}";
        }
        if ($hl !== null) {
            $parts[] = "hl={$hl}";
        }
        return !empty($parts) ? '&' . implode('&', $parts) : '';
    }

    // ─── LRU Cache ────────────────────────────────────────────────────────

    /**
     * @template V
     */
    private static ?LRUCache $globalCache = null;

    public static function globalCache(): LRUCache
    {
        if (self::$globalCache === null) {
            self::$globalCache = new LRUCache(500, 300_000);
        }
        return self::$globalCache;
    }

    // ─── Retry ─────────────────────────────────────────────────────────────

    /**
     * @template T
     * @param callable(): T $fn
     * @return T
     */
    public static function withRetry(callable $fn, int $maxRetries = 3, int $baseDelay = 500, int $maxDelay = 5000): mixed
    {
        $lastErr = null;
        for ($a = 0; $a <= $maxRetries; $a++) {
            try {
                return $fn();
            } catch (\Throwable $err) {
                $lastErr = $err;
                if ($a >= $maxRetries) {
                    throw $err;
                }
                $delay = (int) min($baseDelay * pow(2, $a) + (mt_rand() / mt_getrandmax()) * 500, $maxDelay);
                usleep($delay * 1000);
            }
        }
        throw $lastErr;
    }

    // ─── Client Factory ────────────────────────────────────────────────────

    /**
     * @return array<string, callable|LRUCache>
     */
    public static function createClient(?LRUCache $cache = null, bool $retry = true, int $maxRetries = 3): array
    {
        $cache = $cache ?? self::globalCache();

        return [
            'search' => fn(string $q, int $l = 15): array => self::search($q, $l),
            'searchTrending' => fn(int $l = 15): array => self::searchTrending($l),
            'searchChannel' => fn(string $cid, int $l = 15): array => self::searchChannel($cid, $l),
            'searchPlaylist' => fn(string $pid, int $l = 15): array => self::searchPlaylist($pid, $l),
            'searchContinue' => fn(string $cont, int $l = 15, ?string $apiKey = null, ?array $ctx = null, string $path = 'search'): array => self::searchContinue($cont, $l, $apiKey, $ctx, $path),
            'getVideo' => fn(string $id): VideoResult => self::getVideo($id),
            'getComments' => fn(string $vid, int $l = 20, ?string $c = null): array => self::getComments($vid, $l, $c),
            'getRelatedVideos' => fn(string $vid, int $l = 15): array => self::getRelatedVideos($vid, $l),
            'getVideoStats' => fn(string $vid): array => self::getVideoStats($vid),
            'getLiveStreamInfo' => fn(string $vid): array => self::getLiveStreamInfo($vid),
            'getChannelMetadata' => fn(string $cid): array => self::getChannelMetadata($cid),
            'getTranscript' => fn(string $vid, ?string $lang = null): array => self::getTranscript($vid, $lang),
            'searchShorts' => fn(string $q, int $l = 15): array => self::searchShorts($q, $l),
            'cache' => $cache,
        ];
    }
}

final class LRUCache
{
    /** @var array<string, array{value: mixed, expires: int}> */
    private array $map = [];
    /** @var array<int, string> */
    private array $order = [];
    private int $maxSize;
    private int $ttlMs;

    public function __construct(int $maxSize = 500, int $ttlMs = 300_000)
    {
        $this->maxSize = $maxSize;
        $this->ttlMs = $ttlMs;
    }

    public function get(string $key): mixed
    {
        if (!isset($this->map[$key])) {
            return null;
        }
        if ((int) (microtime(true) * 1000) > $this->map[$key]['expires']) {
            unset($this->map[$key]);
            $pos = array_search($key, $this->order, true);
            if ($pos !== false) {
                unset($this->order[$pos]);
                $this->order = array_values($this->order);
            }
            return null;
        }
        $pos = array_search($key, $this->order, true);
        if ($pos !== false) {
            unset($this->order[$pos]);
        }
        $this->order[] = $key;
        return $this->map[$key]['value'];
    }

    public function set(string $key, mixed $value): void
    {
        $pos = array_search($key, $this->order, true);
        if ($pos !== false) {
            unset($this->order[$pos]);
        } elseif (count($this->map) >= $this->maxSize) {
            $oldest = array_shift($this->order);
            unset($this->map[$oldest]);
        }
        $this->order[] = $key;
        $this->map[$key] = ['value' => $value, 'expires' => (int) (microtime(true) * 1000) + $this->ttlMs];
    }

    public function clear(): void
    {
        $this->map = [];
        $this->order = [];
    }

    public function size(): int
    {
        return count($this->map);
    }
}
                                }
                            }
                        }
                    }

                    if (isset($section['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                        $continuation = $section['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
                    }
                }

                if (!empty($results)) {
                    break;
                }
            }
        } catch (\Throwable) {
        }

        return ['results' => $results, 'continuation' => $continuation];
    }

    /**
     * @return array{results: VideoResult[], continuation: ?string}
     */
    private static function parseChannelResults(array $data, int $limit): array
    {
        $results = [];
        $continuation = null;

        try {
            $tabs = $data['contents']['twoColumnBrowseResultsRenderer']['tabs'] ?? null;
            if (!is_array($tabs)) {
                return ['results' => [], 'continuation' => null];
            }

            foreach ($tabs as $tab) {
                $content = $tab['tabRenderer']['content'] ?? null;
                if (!is_array($content)) {
                    continue;
                }

                $items = $content['richGridRenderer']['contents']
                    ?? $content['sectionListRenderer']['contents']
                    ?? null;
                if (!is_array($items)) {
                    continue;
                }

                foreach ($items as $item) {
                    if (count($results) >= $limit) {
                        break;
                    }

                    if (isset($item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                        $continuation = $item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
                    }

                    if (isset($item['richItemRenderer']['content']['videoRenderer'])) {
                        $vr = self::parseVideoRenderer($item['richItemRenderer']['content']['videoRenderer']);
                        if ($vr !== null) {
                            $results[] = $vr;
                        }
                    }

                    if (isset($item['videoRenderer'])) {
                        $vr = self::parseVideoRenderer($item['videoRenderer']);
                        if ($vr !== null) {
                            $results[] = $vr;
                        }
                    }
                }

                if (!empty($results)) {
                    break;
                }
            }
        } catch (\Throwable) {
        }

        return ['results' => $results, 'continuation' => $continuation];
    }

    /**
     * @return array{results: VideoResult[], continuation: ?string}
     */
    private static function parsePlaylistResults(array $data, int $limit): array
    {
        $results = [];
        $continuation = null;

        try {
            $contents = $data['contents']['twoColumnBrowseResultsRenderer']['tabs'][0]
                ['tabRenderer']['content']['sectionListRenderer']['contents'][0]
                ['itemSectionRenderer']['contents'][0]
                ['playlistVideoListRenderer']['contents'] ?? null;

            if (!is_array($contents)) {
                $contents = $data['contents']['twoColumnWatchNextResults']['playlist']['playlist']['contents'] ?? null;
            }
            if (!is_array($contents)) {
                return ['results' => [], 'continuation' => null];
            }

            foreach ($contents as $item) {
                if (count($results) >= $limit) {
                    break;
                }

                if (isset($item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                    $continuation = $item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
                }

                if (!isset($item['playlistVideoRenderer'])) {
                    continue;
                }

                $pvr = $item['playlistVideoRenderer'];
                $vid = $pvr['videoId'] ?? null;
                if (empty($vid) || !is_string($vid)) {
                    continue;
                }

                $title = self::extractRuns($pvr['title']['runs'] ?? null);
                $author = self::extractRuns($pvr['shortBylineText']['runs'] ?? null);
                $durText = $pvr['lengthText']['simpleText']
                    ?? self::extractRuns($pvr['lengthText']['runs'] ?? null)
                    ?? '';
                ['duration' => $duration, 'seconds' => $durationSeconds] = self::parseDuration($durText);
                $fb = self::fallbackResult($vid);

                $results[] = new VideoResult(
                    id: $vid,
                    title: $title ?: $fb->title,
                    author: $author ?: $fb->author,
                    duration: $duration,
                    durationSeconds: $durationSeconds,
                );
            }
        } catch (\Throwable) {
        }

        return ['results' => $results, 'continuation' => $continuation];
    }

    // ── New Public API methods ─────────────────────────────────────────────────

    /**
     * Search YouTube trending feed.
     *
     * @return array{results: VideoResult[], continuation: ?string, apiKey: ?string, context: ?array}
     */
    public static function searchTrending(int $limit = 15): array
    {
        $limit = max(1, min($limit, 50));

        $html = self::fetch('https://www.youtube.com/feed/trending');
        if ($html === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        $data = self::extractJson($html, 'var ytInitialData');
        if ($data === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
        $apiKey = $apiKeyMatches[1] ?? null;
        $context = self::extractJson($html, '"INNERTUBE_CONTEXT"');

        ['results' => $results, 'continuation' => $continuation] = self::parseTrendingResults($data, $limit);

        return [
            'results' => $results,
            'continuation' => $continuation,
            'apiKey' => $apiKey,
            'context' => $context,
        ];
    }

    /**
     * Search a YouTube channel's video tab.
     *
     * @return array{results: VideoResult[], continuation: ?string, apiKey: ?string, context: ?array}
     */
    public static function searchChannel(string $channelId, int $limit = 15): array
    {
        $limit = max(1, min($limit, 50));

        $html = self::fetch("https://www.youtube.com/channel/{$channelId}/videos");
        if ($html === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        $data = self::extractJson($html, 'var ytInitialData');
        if ($data === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
        $apiKey = $apiKeyMatches[1] ?? null;
        $context = self::extractJson($html, '"INNERTUBE_CONTEXT"');

        ['results' => $results, 'continuation' => $continuation] = self::parseChannelResults($data, $limit);
        self::enrichResults($results);

        return [
            'results' => $results,
            'continuation' => $continuation,
            'apiKey' => $apiKey,
            'context' => $context,
        ];
    }

    /**
     * Search a YouTube playlist.
     *
     * @return array{results: VideoResult[], continuation: ?string, apiKey: ?string, context: ?array}
     */
    public static function searchPlaylist(string $playlistId, int $limit = 15): array
    {
        $limit = max(1, min($limit, 50));

        $html = self::fetch("https://www.youtube.com/playlist?list={$playlistId}");
        if ($html === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        $data = self::extractJson($html, 'var ytInitialData');
        if ($data === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
        $apiKey = $apiKeyMatches[1] ?? null;
        $context = self::extractJson($html, '"INNERTUBE_CONTEXT"');

        ['results' => $results, 'continuation' => $continuation] = self::parsePlaylistResults($data, $limit);
        self::enrichResults($results);

        return [
            'results' => $results,
            'continuation' => $continuation,
            'apiKey' => $apiKey,
            'context' => $context,
        ];
    }
                        }
                    }
                }

                if (isset($section['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                    $continuation = $section['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
                }
            }
        } catch (\Throwable) {
            // ignore parse errors
        }

        return ['results' => $results, 'continuation' => $continuation];
    }

    /**
     * @return array{results: VideoResult[], continuation: ?string}
     */
    private static function parseContinuationResults(array $data, int $limit, string $path = 'search'): array
    {
        $results = [];
        $continuation = null;

        try {
            $items = null;
            if ($path === 'channel') {
                $items = $data['onResponseReceivedActions'][0]['appendContinuationItemsAction']['continuationItems'] ?? null;
                if (!is_array($items)) {
                    $items = $data['onResponseReceivedEndpoints'][0]['appendContinuationItemsAction']['continuationItems'] ?? null;
                }
            } elseif ($path === 'playlist') {
                $items = $data['onResponseReceivedActions'][0]['appendContinuationItemsAction']['continuationItems'] ?? null;
            } else {
                $items = $data['onResponseReceivedEndpoints'][0]['appendContinuationItemsAction']['continuationItems'] ?? null;
            }
            if (!is_array($items)) {
                return ['results' => [], 'continuation' => null];
            }

            foreach ($items as $item) {
                if (count($results) >= $limit) {
                    break;
                }

                if (isset($item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'])) {
                    $continuation = $item['continuationItemRenderer']['continuationEndpoint']['continuationCommand']['token'];
                }

                if ($path === 'playlist' && isset($item['playlistVideoRenderer'])) {
                    $pvr = $item['playlistVideoRenderer'];
                    $vid = $pvr['videoId'] ?? '';
                    if (!empty($vid)) {
                        $title = self::extractRuns($pvr['title']['runs'] ?? null);
                        $author = self::extractRuns($pvr['shortBylineText']['runs'] ?? null);
                        $durText = $pvr['lengthText']['simpleText']
                            ?? self::extractRuns($pvr['lengthText']['runs'] ?? null)
                            ?? '';
                        ['duration' => $duration, 'seconds' => $durationSeconds] = self::parseDuration($durText);
                        $fb = self::fallbackResult($vid);
                        $results[] = new VideoResult(
                            id: $vid,
                            title: $title ?: $fb->title,
                            author: $author ?: $fb->author,
                            duration: $duration,
                            durationSeconds: $durationSeconds,
                        );
                    }
                    continue;
                }

                $vr = $item['videoRenderer'] ?? $item['richItemRenderer']['content']['videoRenderer'] ?? null;
                if (is_array($vr)) {
                    $parsed = self::parseVideoRenderer($vr);
                    if ($parsed !== null) {
                        $results[] = $parsed;
                    }
                }
            }
        } catch (\Throwable) {
            // ignore
        }

        return ['results' => $results, 'continuation' => $continuation];
    }

    /**
     * @return array{title: string, author: string, thumbnail: string}
     */
    private static function enrichWithOembed(string $id): array
    {
        try {
            $json = self::fetch(self::OEMBED_URL . $id . '&format=json');
            if ($json === null) {
                return ['title' => '', 'author' => '', 'thumbnail' => ''];
            }

            $data = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
            if (!is_array($data)) {
                return ['title' => '', 'author' => '', 'thumbnail' => ''];
            }

            return [
                'title' => $data['title'] ?? '',
                'author' => $data['author_name'] ?? '',
                'thumbnail' => $data['thumbnail_url'] ?? '',
            ];
        } catch (\Throwable) {
            return ['title' => '', 'author' => '', 'thumbnail' => ''];
        }
    }

    /**
     * @param VideoResult[] $results
     */
    private static function enrichResults(array $results): void
    {
        $needsEnrichment = array_filter(
            $results,
            fn(VideoResult $r): bool =>
                empty($r->title) || $r->title === "Video {$r->id}" || $r->author === 'YouTube',
        );

        if (empty($needsEnrichment)) {
            return;
        }

        foreach ($needsEnrichment as $r) {
            $enriched = self::enrichWithOembed($r->id);
            if (!empty($enriched['title'])) {
                $r->title = $enriched['title'];
            }
            if (!empty($enriched['author'])) {
                $r->author = $enriched['author'];
            }
            if (!empty($enriched['thumbnail']) && $enriched['thumbnail'] !== $r->thumbnail) {
                $r->thumbnail = $enriched['thumbnail'];
            }
        }
    }

    /**
     * Search YouTube and return rich video results.
     *
     * @return array{results: VideoResult[], continuation: ?string, apiKey: ?string, context: ?array}
     */
    public static function search(string $query, int $limit = 15): array
    {
        $limit = max(1, min($limit, 50));

        $html = self::fetch(self::SEARCH_URL . urlencode($query));
        if ($html === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        $data = self::extractJson($html, 'var ytInitialData');
        if ($data === null) {
            return ['results' => [], 'continuation' => null, 'apiKey' => null, 'context' => null];
        }

        preg_match('/"INNERTUBE_API_KEY":"(AIza[^"]+)"/', $html, $apiKeyMatches);
        $apiKey = $apiKeyMatches[1] ?? null;

        $context = self::extractJson($html, '"INNERTUBE_CONTEXT"');

        ['results' => $results, 'continuation' => $continuation] = self::parseSearchResults($data, $limit);
        self::enrichResults($results);

        return [
            'results' => $results,
            'continuation' => $continuation,
            'apiKey' => $apiKey,
            'context' => $context,
        ];
    }

    /**
     * Get metadata for a single video by its ID.
     */
    public static function getVideo(string $id): VideoResult
    {
        $fallback = self::fallbackResult($id);

        try {
            $html = self::fetch("https://www.youtube.com/watch?v={$id}");
            if ($html === null) {
                return $fallback;
            }

            $data = self::extractJson($html, 'var ytInitialPlayerResponse')
                ?? self::extractJson($html, 'var ytInitialData');

            if ($data !== null) {
                $vd = $data['videoDetails'] ?? null;
                if (is_array($vd)) {
                    $durSec = (int) ($vd['lengthSeconds'] ?? 0);
                    $mins = intdiv($durSec, 60);
                    $secs = $durSec % 60;

                    if ($durSec > 3600) {
                        $durStr = intdiv($durSec, 3600) . ':' . str_pad((string) ($mins % 60), 2, '0', STR_PAD_LEFT) . ':' . str_pad((string) $secs, 2, '0', STR_PAD_LEFT);
                    } else {
                        $durStr = "{$mins}:" . str_pad((string) $secs, 2, '0', STR_PAD_LEFT);
                    }

                    $rawThumbs = $vd['thumbnail']['thumbnails'] ?? [];
                    $thumbs = array_map(
                        fn(array $t): array => [
                            'url' => $t['url'] ?? '',
                            'width' => $t['width'] ?? 0,
                            'height' => $t['height'] ?? 0,
                        ],
                        $rawThumbs,
                    );

                    $rawViewCount = (int) ($vd['viewCount'] ?? 0);

                    return new VideoResult(
                        id: $id,
                        title: $vd['title'] ?? $fallback->title,
                        author: $vd['author'] ?? $fallback->author,
                        channelUrl: isset($vd['channelId']) ? "https://www.youtube.com/{$vd['channelId']}" : '',
                        thumbnail: self::extractBestThumbnail($thumbs) ?: $fallback->thumbnail,
                        thumbnails: !empty($thumbs) ? $thumbs : $fallback->thumbnails,
                        fullUrl: $fallback->fullUrl,
                        embedUrl: $fallback->embedUrl,
                        duration: $durStr,
                        durationSeconds: $durSec,
                        viewCount: $rawViewCount > 0 ? number_format($rawViewCount) . ' views' : '',
                        viewCountRaw: $rawViewCount,
                        description: $vd['shortDescription'] ?? '',
                        channelAvatar: $vd['authorThumbnails'][0]['url'] ?? '',
                    );
                }
            }

            $enriched = self::enrichWithOembed($id);
            return new VideoResult(
                id: $id,
                title: $enriched['title'] ?: $fallback->title,
                author: $enriched['author'] ?: $fallback->author,
                thumbnail: $enriched['thumbnail'] ?: $fallback->thumbnail,
                fullUrl: $fallback->fullUrl,
                embedUrl: $fallback->embedUrl,
                thumbnails: $fallback->thumbnails,
            );
        } catch (\Throwable) {
            return $fallback;
        }
    }

    /**
     * Continue a paginated search using an InnerTube continuation token.
     *
     * @param array<array-key, mixed>|null $context
     * @return array{results: VideoResult[], continuation: ?string}
     */
    public static function searchContinue(string $continuationToken, int $limit = 15, ?string $apiKey = null, ?array $context = null, string $path = 'search'): array
    {
        $limit = max(1, min($limit, 50));
        $key = $apiKey ?? self::DEFAULT_API_KEY;

        $body = [
            'context' => $context ?? self::DEFAULT_CONTEXT,
            'continuation' => $continuationToken,
        ];

        $data = self::fetchJson(
            self::INNERTUBE_URL . '?key=' . $key,
            json_encode($body, JSON_UNESCAPED_SLASHES),
            ['Content-Type: application/json'],
        );

        if ($data === null) {
            return ['results' => [], 'continuation' => null];
        }

        ['results' => $results, 'continuation' => $nextContinuation] = self::parseContinuationResults($data, $limit, $path);
        self::enrichResults($results);

        return [
            'results' => $results,
            'continuation' => $nextContinuation,
        ];
    }
}
