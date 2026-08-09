import 'dart:convert';
import 'dart:io';
import 'package:ytapis/ytapis.dart';

const version = '1.0.0';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args[0] == '--help' || args[0] == '-h') {
    stderr.writeln('Usage: ytapi search <query> [--limit N]');
    stderr.writeln('       ytapi --version');
    exit(args.isEmpty ? 1 : 0);
  }

  if (args[0] == '--version' || args[0] == '-v') {
    print('ytapi v$version');
    exit(0);
  }

  if (args[0] != 'search') {
    stderr.writeln('Usage: ytapi search <query> [--limit N]');
    exit(1);
  }

  final queryParts = <String>[];
  int limit = 15;

  for (int i = 1; i < args.length; i++) {
    if (args[i] == '--limit' && i + 1 < args.length) {
      limit = int.tryParse(args[i + 1]) ?? 15;
      i++;
    } else if (!args[i].startsWith('--')) {
      queryParts.add(args[i]);
    }
  }

  if (queryParts.isEmpty) {
    stderr.writeln('Error: search query required');
    exit(1);
  }

  final query = queryParts.join(' ');

  try {
    final response = await search(query, limit: limit);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(response.results));
  } catch (e) {
    stderr.writeln('Search failed: $e');
    exit(1);
  }
}
