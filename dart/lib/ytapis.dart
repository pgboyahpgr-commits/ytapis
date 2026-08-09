import 'dart:convert';
import 'dart:io';

class SearchResponse {
  final List<VideoResult> results;
  final String? continuation;
  final String? apiKey;
  final Map<String, dynamic>? context;

  SearchResponse({
    required this.results,
    this.continuation,
    this.apiKey,
    this.context,
  });
}

class Thumbnail {
  final String url;
  final int width;
  final int height;

  Thumbnail({required this.url, this.width = 0, this.height = 0});

  Map<String, dynamic> toJson() => {'url': url, 'width': width, 'height': height};
}

class VideoResult {
  final String id;
  final String title;
  final String author;
  final String channelUrl;
  final String thumbnail;
  final List<Thumbnail> thumbnails;
  final String fullUrl;
  final String embedUrl;
  final String duration;
  final int durationSeconds;
  final String viewCount;
  final int viewCountRaw;
  final String publishedTime;
  final String description;
  final String channelAvatar;
  final bool isLive;
  final bool isUpcoming;
  final bool isVerified;

  VideoResult({
    required this.id,
    this.title = '',
    this.author = '',
    this.channelUrl = '',
    String? thumbnail,
    List<Thumbnail>? thumbnails,
    String? fullUrl,
    String? embedUrl,
    this.duration = '',
    this.durationSeconds = 0,
    this.viewCount = '',
    this.viewCountRaw = 0,
    this.publishedTime = '',
    this.description = '',
    this.channelAvatar = '',
    this.isLive = false,
    this.isUpcoming = false,
    this.isVerified = false,
  })  : fullUrl = fullUrl ?? 'https://www.youtube.com/watch?v=${id}',
        embedUrl = embedUrl ?? 'https://www.youtube.com/embed/${id}?rel=0',
        thumbnail = thumbnail ?? 'https://i.ytimg.com/vi/${id}/hqdefault.jpg',
        thumbnails = thumbnails ?? [Thumbnail(url: 'https://i.ytimg.com/vi/${id}/hqdefault.jpg', width: 480, height: 360)];

  factory VideoResult.fallback(String id) {
    return VideoResult(
      id: id,
      title: 'Video $id',
      author: 'YouTube',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'channelUrl': channelUrl,
        'thumbnail': thumbnail,
        'thumbnails': thumbnails.map((t) => t.toJson()).toList(),
        'fullUrl': fullUrl,
        'embedUrl': embedUrl,
        'duration': duration,
        'durationSeconds': durationSeconds,
        'viewCount': viewCount,
        'viewCountRaw': viewCountRaw,
        'publishedTime': publishedTime,
        'description': description,
        'channelAvatar': channelAvatar,
        'isLive': isLive,
        'isUpcoming': isUpcoming,
        'isVerified': isVerified,
      };
}

final _httpClient = HttpClient()
  ..connectionTimeout = const Duration(seconds: 15)
  ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

Future<String> _fetchBody(Uri url) async {
  final request = await _httpClient.getUrl(url);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

Future<String> _fetchPost(Uri url, String body) async {
  final request = await _httpClient.postUrl(url)
    ..headers.contentType = ContentType.json;
  request.write(body);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

Map<String, dynamic>? _extractJson(String html, String prefix) {
  final idx = html.indexOf(prefix);
  if (idx == -1) return null;
  final start = html.indexOf('{', idx);
  if (start == -1) return null;
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (int i = start; i < html.length; i++) {
    final ch = html[i];
    if (escaped) { escaped = false; continue; }
    if (ch == '\\') { escaped = true; continue; }
    if (ch == '"') { inString = !inString; continue; }
    if (inString) continue;
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        try {
          return jsonDecode(html.substring(start, i + 1)) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}

(int, String) _parseDuration(String text) {
  if (text.isEmpty) return (0, '');
  final parts = text.split(':').map((p) => int.tryParse(p) ?? 0).toList();
  if (parts.length == 3) return (parts[0] * 3600 + parts[1] * 60 + parts[2], text);
  if (parts.length == 2) return (parts[0] * 60 + parts[1], text);
  return (parts[0], text);
}

(int, String) _parseViewCount(String text) {
  if (text.isEmpty) return (0, '');
  final cleaned = text.replaceAll(RegExp(r'[^0-9.KMBkmb]'), '');
  final numStr = cleaned.replaceAll(RegExp(r'[KMBkmb]'), '');
  final num = double.tryParse(numStr) ?? 0;
  final upper = cleaned.toUpperCase();
  double mult = 1;
  if (upper.contains('B')) { mult = 1000000000; }
  else if (upper.contains('M')) { mult = 1000000; }
  else if (upper.contains('K')) { mult = 1000; }
  return ((num * mult).round(), text);
}

String _extractRuns(dynamic runs) {
  if (runs is! List) return '';
  return runs.where((r) => r is Map).map((r) => (r as Map)['text'] ?? '').join();
}

int _thumbnailQualityScore(String url) {
  if (url.isEmpty) return 0;
  if (url.contains('maxresdefault')) return 1280;
  if (url.contains('sddefault')) return 640;
  if (url.contains('hqdefault')) return 480;
  if (url.contains('mqdefault')) return 320;
  if (url.contains('default')) return 120;
  return 0;
}

String _bestThumbnail(dynamic thumbs) {
  if (thumbs is! List || thumbs.isEmpty) return '';
  dynamic best = thumbs.first;
  int bestScore = _thumbnailQualityScore(best is Map ? (best['url'] ?? '') : '');
  for (final t in thumbs) {
    if (t is Map) {
      final w = (t['width'] ?? 0) as int;
      final score = w > 0 ? w : _thumbnailQualityScore(t['url'] ?? '');
      if (score > bestScore) {
        best = t;
        bestScore = score;
      }
    }
  }
  return best is Map ? (best['url'] ?? '') : '';
}

List<Thumbnail> _parseThumbnails(dynamic thumbs) {
  if (thumbs is! List) return [];
  return thumbs.where((t) => t is Map).map((t) {
    final m = t as Map;
    return Thumbnail(url: m['url'] ?? '', width: m['width'] ?? 0, height: m['height'] ?? 0);
  }).toList();
}

VideoResult? _parseVideoRenderer(Map vr) {
  final vid = vr['videoId'] as String?;
  if (vid == null || vid.isEmpty) return null;

  String title = '';
  final titleRuns = vr['title']?['runs'];
  if (titleRuns != null) title = _extractRuns(titleRuns);

  String author = '';
  String channelUrl = '';
  final ownerRuns = vr['ownerText']?['runs'];
  if (ownerRuns != null) {
    author = _extractRuns(ownerRuns);
    if (ownerRuns is List && ownerRuns.isNotEmpty && ownerRuns.first is Map) {
      final ep = (ownerRuns.first as Map)['navigationEndpoint'];
      if (ep is Map) {
        channelUrl = ep['browseEndpoint']?['canonicalBaseUrl'] ?? '';
      }
    }
  }

  final rawThumbs = (vr['thumbnail'] as Map?)?['thumbnails'];
  final thumbnails = _parseThumbnails(rawThumbs);
  final thumbnail = _bestThumbnail(rawThumbs);

  final durText = _extractRuns(vr['lengthText']?['runs']) as String? ?? vr['lengthText']?['simpleText'] ?? '';
  final (durationSeconds, duration) = _parseDuration(durText);

  final vcText = _extractRuns(vr['viewCountText']?['runs']) as String? ?? vr['viewCountText']?['simpleText'] ?? '';
  final (viewCountRaw, viewCount) = _parseViewCount(vcText);

  final publishedTime = vr['publishedTimeText']?['simpleText'] ?? '';

  String description = '';
  final snippets = vr['detailedMetadataSnippets'];
  if (snippets is List && snippets.isNotEmpty && snippets.first is Map) {
    final runs = (snippets.first as Map)['snippetText']?['runs'];
    if (runs != null) description = _extractRuns(runs);
  }
  if (description.isEmpty) {
    final dsRuns = vr['descriptionSnippet']?['runs'];
    if (dsRuns != null) description = _extractRuns(dsRuns);
  }

  final cThumbs = (vr['channelThumbnailSupportedRenderers'] as Map?)
    ?['channelThumbnailWithLinkRenderer']?['thumbnail']?['thumbnails'];
  final channelAvatar = _bestThumbnail(cThumbs);

  List badges = [];
  if (vr['badges'] is List) {
    for (final b in vr['badges']) {
      if (b is Map && b['metadataBadgeRenderer'] is Map) {
        badges.add((b['metadataBadgeRenderer'] as Map)['style'] ?? '');
      }
    }
  }

  final fb = VideoResult.fallback(vid);

  return VideoResult(
    id: vid,
    title: title.isNotEmpty ? title : fb.title,
    author: author.isNotEmpty ? author : fb.author,
    channelUrl: channelUrl,
    thumbnail: thumbnail.isNotEmpty ? thumbnail : fb.thumbnail,
    thumbnails: thumbnails.isNotEmpty ? thumbnails : fb.thumbnails,
    fullUrl: fb.fullUrl,
    embedUrl: fb.embedUrl,
    duration: duration,
    durationSeconds: durationSeconds,
    viewCount: viewCount,
    viewCountRaw: viewCountRaw,
    publishedTime: publishedTime,
    description: description,
    channelAvatar: channelAvatar,
    isLive: badges.any((b) => b.toString().toUpperCase().contains('LIVE')),
    isUpcoming: badges.any((b) => b.toString().toUpperCase().contains('UPCOMING')),
    isVerified: badges.any((b) => b.toString().toUpperCase().contains('VERIFIED')),
  );
}

Future<Map<String, String>> _fetchOembed(String id) async {
  try {
    final url = Uri.parse('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$id&format=json');
    final body = await _fetchBody(url);
    final data = jsonDecode(body) as Map<String, dynamic>;
    return {
      'title': data['title'] ?? '',
      'author': data['author_name'] ?? '',
      'thumbnail': data['thumbnail_url'] ?? '',
    };
  } catch (_) {
    return {'title': '', 'author': '', 'thumbnail': ''};
  }
}

Future<VideoResult> getVideo(String id) async {
  final fallback = VideoResult.fallback(id);
  try {
    final html = await _fetchBody(Uri.parse('https://www.youtube.com/watch?v=$id'));
    var data = _extractJson(html, 'var ytInitialPlayerResponse') ??
               _extractJson(html, 'var ytInitialData');

    if (data != null) {
      final vd = data['videoDetails'] as Map?;
      if (vd != null) {
        final durSec = int.tryParse(vd['lengthSeconds']?.toString() ?? '') ?? 0;
        final hrs = durSec ~/ 3600;
        final mins = (durSec % 3600) ~/ 60;
        final secs = durSec % 60;
        final durStr = hrs > 0
            ? '${hrs}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}'
            : '${mins}:${secs.toString().padLeft(2, '0')}';

        return VideoResult(
          id: id,
          title: vd['title'] ?? fallback.title,
          author: vd['author'] ?? fallback.author,
          channelUrl: 'https://www.youtube.com/${vd['channelId'] ?? ''}',
          thumbnail: (vd['thumbnail']?['thumbnails']?.isEmpty ?? true)
              ? fallback.thumbnail : _bestThumbnail(vd['thumbnail']['thumbnails']),
          thumbnails: _parseThumbnails(vd['thumbnail']?['thumbnails']),
          fullUrl: fallback.fullUrl,
          embedUrl: fallback.embedUrl,
          duration: durStr,
          durationSeconds: durSec,
          viewCountRaw: int.tryParse(vd['viewCount']?.toString() ?? '') ?? 0,
          viewCount: vd['viewCount'] != null ? '${vd['viewCount']} views' : '',
          description: vd['shortDescription'] ?? '',
          channelAvatar: (vd['authorThumbnails'] is List && (vd['authorThumbnails'] as List).isNotEmpty)
              ? ((vd['authorThumbnails'] as List).first is Map ? ((vd['authorThumbnails'] as List).first as Map)['url'] ?? '' : '') : '',
        );
      }
    }

    final enrich = await _fetchOembed(id);
    return VideoResult(
      id: id,
      title: enrich['title']?.isNotEmpty == true ? enrich['title']! : fallback.title,
      author: enrich['author']?.isNotEmpty == true ? enrich['author']! : fallback.author,
      thumbnail: enrich['thumbnail']?.isNotEmpty == true ? enrich['thumbnail']! : fallback.thumbnail,
      fullUrl: fallback.fullUrl,
      embedUrl: fallback.embedUrl,
    );
  } catch (_) {
    return fallback;
  }
}

Future<SearchResponse> search(String query, {int limit = 15, String? gl, String? hl}) async {
  limit = limit.clamp(1, 50);
  final encoded = Uri.encodeComponent(query);
  var url = 'https://www.youtube.com/results?search_query=$encoded';
  if (gl != null && gl.isNotEmpty) url += '&gl=${Uri.encodeComponent(gl)}';
  if (hl != null && hl.isNotEmpty) url += '&hl=${Uri.encodeComponent(hl)}';
  final html = await _fetchBody(Uri.parse(url));

  final data = _extractJson(html, 'var ytInitialData');
  if (data == null) return SearchResponse(results: []);

  final keys = _extractApiKeys(html);
  final results = <VideoResult>[];
  final contents = data['contents']?['twoColumnSearchResultsRenderer']
    ?['primaryContents']?['sectionListRenderer']?['contents'];
  if (contents is! List) return SearchResponse(results: results);

  String? continuation;
  for (final section in contents) {
    if (results.length >= limit) break;
    if (section is! Map) continue;

    final cir = section['continuationItemRenderer'];
    if (cir is Map) {
      final token = cir['continuationEndpoint']?['continuationCommand']?['token'];
      if (token is String) continuation = token;
    }

    if (section['itemSectionRenderer'] is Map) {
      final items = section['itemSectionRenderer']['contents'] as List?;
      if (items == null) continue;
      for (final item in items) {
        if (results.length >= limit) break;
        if (item is! Map) continue;
        if (item['videoRenderer'] is Map) {
          final vr = _parseVideoRenderer(item['videoRenderer'] as Map);
          if (vr != null) results.add(vr);
        }
      }
    }
  }

  return SearchResponse(
    results: results,
    continuation: continuation,
    apiKey: keys?['apiKey'],
    context: keys?['context'] != null ? jsonDecode(keys!['context']!) : null,
  );
}

// ---- Trending / Channel / Playlist parsers ----

(List<VideoResult>, String?) _parseTrendingResults(Map data, int limit) {
  final results = <VideoResult>[];
  String? continuation;

  final tabs = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
  if (tabs is! List) return (results, continuation);

  for (final tab in tabs) {
    if (tab is! Map) continue;
    final contents = tab['tabRenderer']?['content']?['sectionListRenderer']?['contents'];
    if (contents is! List) continue;

    for (final section in contents) {
      if (results.length >= limit) break;
      if (section is! Map) continue;

      if (section['itemSectionRenderer'] is Map) {
        final items = section['itemSectionRenderer']['contents'] as List?;
        if (items != null) {
          for (final item in items) {
            if (results.length >= limit) break;
            if (item is! Map) continue;
            if (item['videoRenderer'] is Map) {
              final vr = _parseVideoRenderer(item['videoRenderer'] as Map);
              if (vr != null) results.add(vr);
            }
          }
        }
      }

      if (section['shelfRenderer'] is Map) {
        final shelf = section['shelfRenderer'] as Map;
        final shelfItems = shelf['content']?['expandedShelfContentsRenderer']?['items']
            ?? shelf['content']?['horizontalListRenderer']?['items'];
        if (shelfItems is List) {
          for (final item in shelfItems) {
            if (results.length >= limit) break;
            if (item is! Map) continue;
            if (item['videoRenderer'] is Map) {
              final vr = _parseVideoRenderer(item['videoRenderer'] as Map);
              if (vr != null) results.add(vr);
            }
          }
        }
      }

      final cir = section['continuationItemRenderer'];
      if (cir is Map) {
        final token = cir['continuationEndpoint']?['continuationCommand']?['token'];
        if (token is String) continuation = token;
      }
    }

    if (results.isNotEmpty) break;
  }

  return (results, continuation);
}

(List<VideoResult>, String?) _parseChannelResults(Map data, int limit) {
  final results = <VideoResult>[];
  String? continuation;

  final tabs = data['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
  if (tabs is! List) return (results, continuation);

  for (final tab in tabs) {
    if (tab is! Map) continue;
    final content = tab['tabRenderer']?['content'];
    if (content is! Map) continue;

    final items = content['richGridRenderer']?['contents']
        ?? content['sectionListRenderer']?['contents'];
    if (items is! List) continue;

    for (final item in items) {
      if (results.length >= limit) break;
      if (item is! Map) continue;

      final cir = item['continuationItemRenderer'];
      if (cir is Map) {
        final token = cir['continuationEndpoint']?['continuationCommand']?['token'];
        if (token is String) continuation = token;
      }

      if (item['richItemRenderer'] is Map) {
        final riContent = item['richItemRenderer']['content'];
        if (riContent is Map && riContent['videoRenderer'] is Map) {
          final vr = _parseVideoRenderer(riContent['videoRenderer'] as Map);
          if (vr != null) results.add(vr);
        }
      }

      if (item['videoRenderer'] is Map) {
        final vr = _parseVideoRenderer(item['videoRenderer'] as Map);
        if (vr != null) results.add(vr);
      }
    }

    if (results.isNotEmpty) break;
  }

  return (results, continuation);
}

(List<VideoResult>, String?) _parsePlaylistResults(Map data, int limit) {
  final results = <VideoResult>[];
  String? continuation;

  var contents = data['contents']?['twoColumnBrowseResultsRenderer']
      ?['tabs']?[0]
      ?['tabRenderer']?['content']
      ?['sectionListRenderer']?['contents']?[0]
      ?['itemSectionRenderer']?['contents']?[0]
      ?['playlistVideoListRenderer']?['contents'];

  if (contents is! List) {
    final alt = data['contents']?['twoColumnWatchNextResults']
        ?['playlist']?['playlist']?['contents'];
    if (alt is! List) return (results, continuation);
    contents = alt;
  }

  for (final item in contents) {
    if (results.length >= limit) break;
    if (item is! Map) continue;

    final cir = item['continuationItemRenderer'];
    if (cir is Map) {
      final token = cir['continuationEndpoint']?['continuationCommand']?['token'];
      if (token is String) continuation = token;
    }

    final pvr = item['playlistVideoRenderer'];
    if (pvr is! Map) {
      continue;
    }

    final vid = pvr['videoId'] as String?;
    if (vid == null || vid.isEmpty) continue;

    String title = '';
    final titleRuns = pvr['title']?['runs'];
    if (titleRuns != null) title = _extractRuns(titleRuns);

    String author = '';
    final bylineRuns = pvr['shortBylineText']?['runs'];
    if (bylineRuns != null) author = _extractRuns(bylineRuns);

    final durText = _extractRuns(pvr['lengthText']?['runs']) as String? ?? pvr['lengthText']?['simpleText'] ?? '';
    final (durationSeconds, duration) = _parseDuration(durText);

    final fb = VideoResult.fallback(vid);
    results.add(VideoResult(
      id: vid,
      title: title.isNotEmpty ? title : fb.title,
      author: author.isNotEmpty ? author : fb.author,
      duration: duration,
      durationSeconds: durationSeconds,
    ));
  }

  return (results, continuation);
}

(List<VideoResult>, String?) _parseContinuationResults(Map data, int limit, String path) {
  final results = <VideoResult>[];
  String? continuation;

  dynamic items;
  if (path == 'channel') {
    items = data['onResponseReceivedActions']?[0]
        ?['appendContinuationItemsAction']?['continuationItems'];
    if (items is! List) {
      items = data['onResponseReceivedEndpoints']?[0]
          ?['appendContinuationItemsAction']?['continuationItems'];
    }
  } else if (path == 'playlist') {
    items = data['onResponseReceivedActions']?[0]
        ?['appendContinuationItemsAction']?['continuationItems'];
  } else {
    items = data['onResponseReceivedEndpoints']?[0]
        ?['appendContinuationItemsAction']?['continuationItems'];
  }

  if (items is! List) return (results, continuation);

  for (final item in items) {
    if (results.length >= limit) break;
    if (item is! Map) continue;

    final cir = item['continuationItemRenderer'];
    if (cir is Map) {
      final token = cir['continuationEndpoint']?['continuationCommand']?['token'];
      if (token is String) continuation = token;
    }

    if (path == 'playlist' && item['playlistVideoRenderer'] is Map) {
      final pvr = item['playlistVideoRenderer'] as Map;
      final vid = pvr['videoId'] as String?;
      if (vid != null && vid.isNotEmpty) {
        final title = _extractRuns(pvr['title']?['runs']);
        final author = _extractRuns(pvr['shortBylineText']?['runs']);
        final durText = _extractRuns(pvr['lengthText']?['runs']) as String? ?? pvr['lengthText']?['simpleText'] ?? '';
        final (durationSeconds, duration) = _parseDuration(durText);
        final fb = VideoResult.fallback(vid);
        results.add(VideoResult(
          id: vid,
          title: title.isNotEmpty ? title : fb.title,
          author: author.isNotEmpty ? author : fb.author,
          duration: duration,
          durationSeconds: durationSeconds,
        ));
      }
      continue;
    }

    var vr = item['videoRenderer'];
    if (vr is! Map && item['richItemRenderer'] is Map) {
      vr = item['richItemRenderer']['content']?['videoRenderer'];
    }
    if (vr is Map) {
      final parsed = _parseVideoRenderer(vr);
      if (parsed != null) results.add(parsed);
    }
  }

  return (results, continuation);
}

Map<String, String>? _extractApiKeys(String html) {
  final match = RegExp(r'"INNERTUBE_API_KEY":"(AIza[^"]+)"').firstMatch(html);
  return {
    'apiKey': match?.group(1) ?? '',
    'context': jsonEncode(_extractJson(html, '"INNERTUBE_CONTEXT"')),
  };
}

// ---- Public API: searchTrending ----

Future<List<VideoResult>> searchTrending({int limit = 15, String? gl, String? hl}) async {
  limit = limit.clamp(1, 50);
  var url = 'https://www.youtube.com/feed/trending';
  final params = <String>[];
  if (gl != null && gl.isNotEmpty) params.add('gl=${Uri.encodeComponent(gl)}');
  if (hl != null && hl.isNotEmpty) params.add('hl=${Uri.encodeComponent(hl)}');
  if (params.isNotEmpty) url += '?${params.join('&')}';
  final html = await _fetchBody(Uri.parse(url));
  final data = _extractJson(html, 'var ytInitialData');
  if (data == null) return [];
  final (results, _) = _parseTrendingResults(data, limit);
  return results;
}

// ---- Public API: searchChannel ----

Future<List<VideoResult>> searchChannel(String channelId, {int limit = 15, String? gl, String? hl}) async {
  limit = limit.clamp(1, 50);
  final encoded = Uri.encodeComponent(channelId);
  var url = 'https://www.youtube.com/channel/$encoded/videos';
  final params = <String>[];
  if (gl != null && gl.isNotEmpty) params.add('gl=${Uri.encodeComponent(gl)}');
  if (hl != null && hl.isNotEmpty) params.add('hl=${Uri.encodeComponent(hl)}');
  if (params.isNotEmpty) url += '?${params.join('&')}';
  final html = await _fetchBody(Uri.parse(url));
  final data = _extractJson(html, 'var ytInitialData');
  if (data == null) return [];
  final (results, _) = _parseChannelResults(data, limit);
  return results;
}

// ---- Public API: searchPlaylist ----

Future<List<VideoResult>> searchPlaylist(String playlistId, {int limit = 15, String? gl, String? hl}) async {
  limit = limit.clamp(1, 50);
  final encoded = Uri.encodeComponent(playlistId);
  var url = 'https://www.youtube.com/playlist?list=$encoded';
  if (gl != null && gl.isNotEmpty) url += '&gl=${Uri.encodeComponent(gl)}';
  if (hl != null && hl.isNotEmpty) url += '&hl=${Uri.encodeComponent(hl)}';
  final html = await _fetchBody(Uri.parse(url));
  final data = _extractJson(html, 'var ytInitialData');
  if (data == null) return [];
  final (results, _) = _parsePlaylistResults(data, limit);
  return results;
}

// ---- Public API: searchContinue (with path) ----

Future<SearchResponse> searchContinue(String continuation, {int limit = 15, String? apiKey, Map<String, dynamic>? context, String path = 'search'}) async {
  limit = limit.clamp(1, 50);
  final key = apiKey ?? 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  final ctx = context ?? {
    'client': {'hl': 'en', 'gl': 'US', 'clientName': 'WEB', 'clientVersion': '2.20240801.00.00'}
  };
  final body = jsonEncode({'context': ctx, 'continuation': continuation});

  final responseText = await _fetchPost(
    Uri.parse('https://www.youtube.com/youtubei/v1/search?key=$key'),
    body,
  );

  final data = jsonDecode(responseText) as Map<String, dynamic>;
  final (results, nextContinuation) = _parseContinuationResults(data, limit, path);
  return SearchResponse(
    results: results,
    continuation: nextContinuation,
    apiKey: apiKey,
    context: context,
  );
}

// ─── Channel Metadata ───────────────────────────────────

class SocialLink {
  final String title;
  final String url;
  final String icon;

  SocialLink({this.title = '', this.url = '', this.icon = ''});

  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'icon': icon};
}

class ChannelMetadata {
  final String id;
  final String name;
  final String handle;
  final String description;
  final String subscriberCount;
  final int subscriberCountRaw;
  final String videoCount;
  final int videoCountRaw;
  final String avatar;
  final String banner;
  final bool isVerified;
  final List<SocialLink> socialLinks;
  final String url;

  ChannelMetadata({
    required this.id,
    this.name = '',
    this.handle = '',
    this.description = '',
    this.subscriberCount = '',
    this.subscriberCountRaw = 0,
    this.videoCount = '',
    this.videoCountRaw = 0,
    this.avatar = '',
    this.banner = '',
    this.isVerified = false,
    this.socialLinks = const [],
    String? url,
  }) : url = url ?? 'https://www.youtube.com/channel/$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'handle': handle,
        'description': description,
        'subscriberCount': subscriberCount,
        'subscriberCountRaw': subscriberCountRaw,
        'videoCount': videoCount,
        'videoCountRaw': videoCountRaw,
        'avatar': avatar,
        'banner': banner,
        'isVerified': isVerified,
        'socialLinks': socialLinks.map((l) => l.toJson()).toList(),
        'url': url,
      };
}

Future<ChannelMetadata> getChannelMetadata(String channelId) async {
  final empty = ChannelMetadata(id: channelId);
  try {
    final html = await _fetchBody(Uri.parse('https://www.youtube.com/channel/$channelId/about'));
    final data = _extractJson(html, 'var ytInitialData');
    if (data == null) return empty;

    final metadata = data['metadata']?['channelMetadataRenderer'];
    if (metadata is! Map) return empty;

    final header = data;
    final tabs = header['contents']?['twoColumnBrowseResultsRenderer']?['tabs'];
    Map? about;
    if (tabs is List) {
      for (final t in tabs) {
        if (t is! Map) continue;
        final tr = t['tabRenderer'];
        if (tr is Map && tr['selected'] == true) {
          final contents = tr['content']?['sectionListRenderer']?['contents'];
          if (contents is List && contents.isNotEmpty) {
            final isr = contents.first;
            if (isr is Map) {
              final isrContents = isr['itemSectionRenderer']?['contents'];
              if (isrContents is List && isrContents.isNotEmpty) {
                about = isrContents.first?['channelAboutFullMetadataRenderer'] as Map?;
              }
            }
          }
          break;
        }
      }
    }

    final c4 = header['header']?['c4TabbedHeaderRenderer'] as Map?;
    final subscriberText = c4?['subscriberCountText']?['simpleText'] ?? '';
    final (subsRaw, subs) = _parseViewCount(subscriberText);

    String videoText = '';
    int vcRaw = 0;
    if (about != null) {
      final runs = about['videoCountText']?['runs'];
      if (runs is List && runs.isNotEmpty && runs.first is Map) {
        videoText = runs.first['text'] ?? '';
      }
      final match = RegExp(r'([\d,]+)').firstMatch(videoText);
      if (match != null) {
        vcRaw = int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
      }
    }

    final links = <SocialLink>[];
    if (about != null) {
      final primaryLinks = about['primaryLinks'];
      if (primaryLinks is List) {
        for (final l in primaryLinks) {
          if (l is! Map) continue;
          final nav = l['navigationEndpoint']?['urlEndpoint'];
          var titleText = l['title']?['simpleText'] ?? '';
          if (titleText.isEmpty) {
            final titleRuns = l['title']?['runs'];
            if (titleRuns is List && titleRuns.isNotEmpty && titleRuns.first is Map) {
              titleText = titleRuns.first['text'] ?? '';
            }
          }
          final iconThumbs = l['icon']?['thumbnails'];
          var iconUrl = '';
          if (iconThumbs is List && iconThumbs.isNotEmpty && iconThumbs.first is Map) {
            iconUrl = iconThumbs.first['url'] ?? '';
          }
          links.add(SocialLink(
            title: titleText,
            url: nav is Map ? (nav['url'] ?? '') : '',
            icon: iconUrl,
          ));
        }
      }
    }

    String handle = '';
    if (metadata['vanityChannelUrl'] is String) {
      handle = metadata['vanityChannelUrl']
          .toString()
          .replaceAll('http://www.youtube.com/', '')
          .replaceAll('https://www.youtube.com/', '');
    }

    bool isVerified = false;
    final badges = c4?['badges'];
    if (badges is List) {
      for (final b in badges) {
        if (b is Map) {
          final style = b['metadataBadgeRenderer']?['style'] ?? '';
          if (style.toString().toUpperCase().contains('VERIFIED')) {
            isVerified = true;
          }
        }
      }
    }

    String desc = metadata['description'] ?? '';
    if (desc.isEmpty && about != null) {
      desc = about['description']?['simpleText'] ?? '';
      if (desc.isEmpty) {
        desc = _extractRuns(about['description']?['runs']);
      }
    }

    final avatarThumbs = metadata['avatar']?['thumbnails'] ?? c4?['avatar']?['thumbnails'];
    final bannerThumbs = metadata['banner']?['thumbnails'] ?? c4?['banner']?['thumbnails'];

    return ChannelMetadata(
      id: channelId,
      name: metadata['title'] ?? c4?['title'] ?? '',
      handle: handle,
      description: desc,
      subscriberCount: subs,
      subscriberCountRaw: subsRaw,
      videoCount: videoText,
      videoCountRaw: vcRaw,
      avatar: _bestThumbnail(avatarThumbs),
      banner: _bestThumbnail(bannerThumbs),
      isVerified: isVerified,
      socialLinks: links,
    );
  } catch (_) {
    return empty;
  }
}

// ─── Shorts ─────────────────────────────────────────────

Future<List<VideoResult>> searchShorts(String query, {int limit = 15, String? gl, String? hl}) async {
  limit = limit.clamp(1, 50);
  final encoded = Uri.encodeComponent(query);
  var url = 'https://www.youtube.com/results?search_query=$encoded&sp=EgIYAQ%3D%3D';
  if (gl != null && gl.isNotEmpty) url += '&gl=${Uri.encodeComponent(gl)}';
  if (hl != null && hl.isNotEmpty) url += '&hl=${Uri.encodeComponent(hl)}';

  final html = await _fetchBody(Uri.parse(url));
  final data = _extractJson(html, 'var ytInitialData');
  if (data == null) return [];

  final sectionContents = data['contents']
      ?['twoColumnSearchResultsRenderer']
      ?['primaryContents']
      ?['sectionListRenderer']
      ?['contents'];
  if (sectionContents is! List) return [];

  Map? reelShelf;
  for (final c in sectionContents) {
    if (c is! Map) continue;
    final items = c['itemSectionRenderer']?['contents'];
    if (items is List && items.isNotEmpty && items.first is Map && items.first['reelShelfRenderer'] is Map) {
      reelShelf = items.first['reelShelfRenderer'] as Map;
      break;
    }
  }

  if (reelShelf == null) return [];

  final reelItems = reelShelf['items'] as List? ?? [];
  final results = <VideoResult>[];

  for (final item in reelItems) {
    if (results.length >= limit) break;
    if (item is! Map) continue;

    var vr = item['reelItemRenderer'];
    if (vr is! Map) vr = item['shortsLockupViewModel'];
    if (vr is! Map) continue;

    final vid = vr['videoId'] as String?;
    if (vid == null || vid.isEmpty) continue;

    var title = '';
    final headlineRuns = vr['headline']?['runs'];
    if (headlineRuns != null) title = _extractRuns(headlineRuns);
    if (title.isEmpty) title = vr['headline']?['simpleText'] ?? '';

    final durText = vr['lengthText']?['simpleText'] ?? '';
    final duration = int.tryParse(durText) ?? 0;

    final fb = VideoResult.fallback(vid);
    results.add(VideoResult(
      id: vid,
      title: title.isNotEmpty ? title : 'Shorts $vid',
      author: fb.author,
      duration: '${duration}s',
      durationSeconds: duration,
      isLive: false,
      isUpcoming: false,
      isVerified: false,
    ));
  }

  return results;
}

// ─── Transcript / Captions ──────────────────────────────

class TranscriptEntry {
  final String text;
  final double start;
  final double duration;

  TranscriptEntry({this.text = '', this.start = 0.0, this.duration = 0.0});

  Map<String, dynamic> toJson() => {'text': text, 'start': start, 'duration': duration};
}

Future<List<TranscriptEntry>> getTranscript(String videoId, {String? lang}) async {
  try {
    final html = await _fetchBody(Uri.parse('https://www.youtube.com/watch?v=$videoId'));

    final captionsMatch = RegExp(r'"captionTracks":\s*(\[[^\]]*\{[^}]*"baseUrl":"([^"]+)"[^}]*\}[^\]]*\])').firstMatch(html);
    if (captionsMatch == null) {
      final playerMatch = RegExp(r'"captions":\{[^}]*"playerCaptionsTracklistRenderer":\{[^}]*"captionTracks":(\[[^\]]*\])').firstMatch(html);
      if (playerMatch == null) return [];
    }

    var tracksStr = captionsMatch?.group(1);
    if (tracksStr == null) {
      final m = RegExp(r'"captionTracks":(\[[^\]]*\{[^}]*\}[^\]]*\])').firstMatch(html);
      tracksStr = m?.group(1);
    }
    if (tracksStr == null) return [];

    final tracks = jsonDecode(tracksStr) as List;
    String trackUrl = '';

    if (lang != null && lang.isNotEmpty) {
      for (final t in tracks) {
        if (t is! Map) continue;
        if (t['languageCode'] == lang || (t['name']?['simpleText']?.toString().toLowerCase().contains(lang.toLowerCase()) ?? false)) {
          trackUrl = t['baseUrl'] ?? '';
          break;
        }
      }
    }
    if (trackUrl.isEmpty) {
      for (final t in tracks) {
        if (t is Map && t['languageCode'] == 'en') {
          trackUrl = t['baseUrl'] ?? '';
          break;
        }
      }
    }
    if (trackUrl.isEmpty && tracks.isNotEmpty && tracks.first is Map) {
      trackUrl = tracks.first['baseUrl'] ?? '';
    }
    if (trackUrl.isEmpty) return [];

    final xml = await _fetchBody(Uri.parse(trackUrl));
    final entries = <TranscriptEntry>[];

    final textRe = RegExp(r'<text start="([\d.]+)" dur="([\d.]+)"[^>]*>(.*?)(?:</text>)?$', multiLine: true);
    for (final m in textRe.allMatches(xml)) {
      var raw = m.group(3) ?? '';
      raw = raw.replaceAll(RegExp(r'<[^>]+>'), '');
      raw = raw.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
      if (raw.trim().isNotEmpty) {
        entries.add(TranscriptEntry(
          text: raw.trim(),
          start: double.tryParse(m.group(1) ?? '0') ?? 0.0,
          duration: double.tryParse(m.group(2) ?? '0') ?? 0.0,
        ));
      }
    }
    return entries;
  } catch (_) {
    return [];
  }
}
