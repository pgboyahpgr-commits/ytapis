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
  final _scrollController = ScrollController();
  List<VideoResult> _results = [];
  bool _loading = false;
  bool _loadingMore = false;
  String _status = 'Enter a query to search YouTube';
  String? _continuation;
  String? _apiKey;
  Map<String, dynamic>? _context;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _continuation != null) {
      _loadMore();
    }
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _status = 'Searching...';
      _results = [];
      _continuation = null;
    });
    try {
      final response = await search(q, limit: 20);
      setState(() {
        _results = response.results;
        _continuation = response.continuation;
        _apiKey = response.apiKey;
        _context = response.context;
        _status = 'Found ${response.results.length} results. Tap any for details.';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_continuation == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final response = await searchContinue(
        _continuation!,
        limit: 20,
        apiKey: _apiKey,
        context: _context,
        path: 'search',
      );
      setState(() {
        _results.addAll(response.results);
        _continuation = response.continuation;
        _loadingMore = false;
        _status = 'Found ${_results.length} results';
      });
    } catch (e) {
      setState(() {
        _loadingMore = false;
        _status = 'Error loading more: $e';
      });
    }
  }

  Future<void> _refresh() async {
    await _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ytapis'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search YouTube...',
                      filled: true,
                      fillColor: const Color(0xFF2a2a2a),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3EA6FF),
                    foregroundColor: const Color(0xFF0F0F0F),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Search',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _status,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text('No results',
                          style: TextStyle(color: Colors.grey[600])))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: const Color(0xFF3EA6FF),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _results.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _results.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            );
                          }
                          final v = _results[i];
                          return _buildCard(v);
                        },
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(VideoResult v) {
    final metaParts = <String>[];
    if (v.viewCount.isNotEmpty) metaParts.add(v.viewCount);
    if (v.publishedTime.isNotEmpty) metaParts.add(v.publishedTime);

    return Card(
      color: const Color(0xFF2a2a2a),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    v.thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF1a1a1a),
                      child: const Center(
                          child: Icon(Icons.broken_image,
                              color: Color(0xFF444))),
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: const Color(0xFF1a1a1a),
                        child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF3EA6FF))),
                      );
                    },
                  ),
                ),
                if (v.isLive)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE04040),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('LIVE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  )
                else if (v.isUpcoming)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9D423),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('UPCOMING',
                          style: TextStyle(
                              color: Color(0xFF0F0F0F),
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  )
                else if (v.duration.isNotEmpty)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        v.duration,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (v.channelAvatar.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: CircleAvatar(
                            radius: 10,
                            backgroundImage:
                                NetworkImage(v.channelAvatar),
                            backgroundColor: const Color(0xFF333),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          v.author,
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (v.isVerified)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.verified,
                              size: 14, color: Color(0xFF3EA6FF)),
                        ),
                    ],
                  ),
                  if (metaParts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      metaParts.join('  \u2022  '),
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 11),
                    ),
                  ],
                  if (v.isLive || v.isUpcoming) ...[
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(v.isLive ? 'LIVE NOW' : 'UPCOMING',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      backgroundColor: v.isLive
                          ? const Color(0xFFE04040)
                          : const Color(0xFFF9D423),
                      labelStyle: TextStyle(
                          color: v.isLive
                              ? Colors.white
                              : const Color(0xFF0F0F0F)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(VideoResult v) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DetailPage(video: v),
      ),
    );
  }
}

class _DetailPage extends StatelessWidget {
  final VideoResult video;
  const _DetailPage({required this.video});

  @override
  Widget build(BuildContext context) {
    final metaItems = <String>[];
    if (video.duration.isNotEmpty) metaItems.add('Duration: ${video.duration}');
    if (video.viewCount.isNotEmpty) metaItems.add(video.viewCount);
    if (video.publishedTime.isNotEmpty) metaItems.add(video.publishedTime);

    return Scaffold(
      backgroundColor: const Color(0xFF1e1e1e),
      appBar: AppBar(
        title: const Text('Video Details'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  video.thumbnail,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFF1a1a1a),
                    child: const Center(
                        child: Icon(Icons.broken_image,
                            color: Color(0xFF444))),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: const Color(0xFF1a1a1a),
                      child: const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF3EA6FF))),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              video.title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (video.channelAvatar.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(video.channelAvatar),
                      backgroundColor: const Color(0xFF333),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              video.author,
                              style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (video.isVerified)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.verified,
                                  size: 16,
                                  color: Color(0xFF3EA6FF)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (video.isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE04040),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                if (video.isUpcoming)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9D423),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('UPCOMING',
                        style: TextStyle(
                            color: Color(0xFF0F0F0F),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ...metaItems.map(
                  (m) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2a2a2a),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF3a3a3a)),
                    ),
                    child: Text(m,
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: 11)),
                  ),
                ),
              ],
            ),
            if (video.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Description',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                video.description,
                style:
                    TextStyle(color: Colors.grey[500], fontSize: 12),
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Text('ID: ${video.id}',
                style: TextStyle(color: Colors.grey[700], fontSize: 11)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play in Browser',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4D4D),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => launchUrl(Uri.parse(video.fullUrl)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('View Thumbnail'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[400],
                  side: BorderSide(color: Colors.grey[700]!),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => launchUrl(Uri.parse(video.thumbnail)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
