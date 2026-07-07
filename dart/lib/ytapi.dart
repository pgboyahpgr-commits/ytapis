import 'dart:convert';
import 'dart:io';

class VideoResult {
  final String id;
  final String title;
  final String author;
  final String thumbnail;
  final String fullUrl;
  final String embedUrl;

  VideoResult({
    required this.id,
    this.title = '',
    this.author = '',
    this.thumbnail = '',
    this.fullUrl = '',
    this.embedUrl = '',
  }) {
    // Defaults are set via init method instead
  }

  factory VideoResult.fromId(String id) {
    return VideoResult(
      id: id,
      title: 'Video $id',
      author: 'YouTube',
      thumbnail: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      fullUrl: 'https://www.youtube.com/watch?v=$id',
      embedUrl: 'https://www.youtube.com/embed/$id?rel=0',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'thumbnail': thumbnail,
        'fullUrl': fullUrl,
        'embedUrl': embedUrl,
      };
}

class _OembedResponse {
  final String? title;
  final String? authorName;
  final String? thumbnailUrl;

  _OembedResponse({this.title, this.authorName, this.thumbnailUrl});

  factory _OembedResponse.fromJson(Map<String, dynamic> json) {
    return _OembedResponse(
      title: json['title'] as String?,
      authorName: json['author_name'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

Future<VideoResult> _fetchOembed(String id) async {
  final fallback = VideoResult.fromId(id);
  try {
    final url = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$id&format=json');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) return fallback;

    final body = await response.transform(utf8.decoder).join();
    final data = _OembedResponse.fromJson(jsonDecode(body));

    return VideoResult(
      id: id,
      title: data.title ?? fallback.title,
      author: data.authorName ?? fallback.author,
      thumbnail: data.thumbnailUrl ?? fallback.thumbnail,
      fullUrl: fallback.fullUrl,
      embedUrl: fallback.embedUrl,
    );
  } catch (_) {
    return fallback;
  }
}

Future<List<VideoResult>> search(String query, {int limit = 15}) async {
  final encoded = Uri.encodeComponent(query);
  final url = Uri.parse('https://www.youtube.com/results?search_query=$encoded');

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  final request = await client.getUrl(url);
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  final regex = RegExp(r'"videoId":"([^"]{11})"');
  final matches = regex.allMatches(body);
  final ids = matches.map((m) => m.group(1)!).toList();

  final uniqueIds = <String>[];
  for (final id in ids) {
    if (!uniqueIds.contains(id)) {
      uniqueIds.add(id);
      if (uniqueIds.length >= limit) break;
    }
  }

  return Future.wait(uniqueIds.map(_fetchOembed));
}
