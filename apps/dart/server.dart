import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:ytapis/ytapis.dart';

void main() async {
  final app = Router();

  app.get('/', (Request req) {
    return Response(302, headers: {'Location': '/index.html'});
  });

  app.get('/search', (Request req) async {
    final query = req.url.queryParameters['q'] ?? '';
    if (query.isEmpty) {
      return Response.badRequest(body: '{"error":"missing query param \\"q\\""}',
          headers: {'Content-Type': 'application/json'});
    }
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '15') ?? 15;
    try {
      final results = await search(query, limit: limit);
      final json = jsonEncode(results.map((v) => v.toJson()).toList());
      return Response.ok(json, headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(
          body: '{"error":"${e.toString().replaceAll('"', '\\"')}"}',
          headers: {'Content-Type': 'application/json'});
    }
  });

  final staticHandler = createStaticHandler('static', defaultDocument: 'index.html');
  final handler = Cascade().add(app).add(staticHandler).handler;
  final server = await serve(handler, '0.0.0.0', 8080);
  print('ytapis Dart app running at http://localhost:${server.port}');
}
