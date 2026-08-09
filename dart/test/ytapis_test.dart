import 'package:test/test.dart';
import 'package:ytapis/ytapis.dart';

void main() {
  group('VideoResult', () {
    test('fallback sets defaults from id', () {
      final vr = VideoResult.fallback('dQw4w9WgXcQ');
      expect(vr.id, equals('dQw4w9WgXcQ'));
      expect(vr.title, equals('Video dQw4w9WgXcQ'));
      expect(vr.author, equals('YouTube'));
      expect(vr.fullUrl, equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
      expect(vr.thumbnail, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
      expect(vr.embedUrl, equals('https://www.youtube.com/embed/dQw4w9WgXcQ?rel=0'));
    });

    test('constructor sets defaults from id when not provided', () {
      final vr = VideoResult(id: 'dQw4w9WgXcQ');
      expect(vr.id, equals('dQw4w9WgXcQ'));
      expect(vr.fullUrl, equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
      expect(vr.thumbnail, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
    });

    test('constructor preserves provided values', () {
      final vr = VideoResult(
        id: 'abc',
        title: 'My Title',
        author: 'My Author',
        thumbnail: 'https://example.com/thumb.jpg',
      );
      expect(vr.title, equals('My Title'));
      expect(vr.author, equals('My Author'));
      expect(vr.thumbnail, equals('https://example.com/thumb.jpg'));
    });

    test('toJson returns correct map', () {
      final vr = VideoResult.fallback('test1234567');
      final json = vr.toJson();
      expect(json['id'], equals('test1234567'));
      expect(json['fullUrl'], contains('test1234567'));
    });
  });

  group('search', () {
    test('returns results for valid query', () async {
      final response = await search('cats', limit: 3);
      final results = response.results;
      expect(results, isNotEmpty);
      expect(results.length, lessThanOrEqualTo(3));
      for (final r in results) {
        expect(r.id, isNotEmpty);
        expect(r.title, isNotEmpty);
      }
    });
  });

  group('getVideo', () {
    test('returns video for valid id', () async {
      final result = await getVideo('dQw4w9WgXcQ');
      expect(result.id, equals('dQw4w9WgXcQ'));
      expect(result.title, isNotEmpty);
    });
  });
}
