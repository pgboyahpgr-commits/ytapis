import 'package:flutter/material.dart';
import 'package:ytapis/ytapis.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const YtapisApp());

class YtapisApp extends StatelessWidget {
  const YtapisApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ytapis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3EA6FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1e1e1e),
      ),
      home: const SearchPage(),
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<VideoResult> _results = [];
  bool _loading = false;
  String _status = 'Enter a query to search YouTube';

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _status = 'Searching...'; _results = []; });
    try {
      final r = await search(q, limit: 15);
      setState(() {
        _results = r;
        _status = 'Found ${r.length} results. Tap any to play.';
        _loading = false;
      });
    } catch (e) {
      setState(() { _status = 'Error: $e'; _loading = false; });
    }
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ytapis'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search YouTube...',
                      filled: true,
                      fillColor: const Color(0xFF2a2a2a),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_status, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _results.isEmpty
                ? Center(child: Text('No results', style: TextStyle(color: Colors.grey[600])))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final v = _results[i];
                      return Card(
                        color: const Color(0xFF2a2a2a),
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          title: Text(v.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${v.author}  •  ${v.id}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          trailing: const Icon(Icons.play_circle_fill, color: Color(0xFF3EA6FF)),
                          onTap: () => _openVideo(v),
                        ),
                      );
                    },
                  ),
            ),
        ],
      ),
    );
  }

  void _openVideo(VideoResult v) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1e1e1e),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(v.author, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            const SizedBox(height: 4),
            Text(v.id, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play Video in Browser'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4D4D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  launchUrl(Uri.parse(v.fullUrl));
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('View Thumbnail'),
                onPressed: () {
                  launchUrl(Uri.parse(v.thumbnail));
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                child: const Text('Close'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
