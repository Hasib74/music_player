import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:logging/logging.dart';
import 'player_details_screen.dart';
import '../services/download_service.dart';

class YoutubePlayerScreen extends StatefulWidget {
  const YoutubePlayerScreen({super.key});

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends State<YoutubePlayerScreen> {
  final _logger = Logger('YoutubePlayerScreen');
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();
  final DownloadService _downloadService = DownloadService();
  final ValueNotifier<double> _downloadProgressNotifier = ValueNotifier(0);

  List<Video> _searchResults = [];
  VideoSearchList? _currentSearchList;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  Video? _currentVideo;
  List<String> _suggestions = [];

  final List<String> _categories = ["Trending", "Relax", "Workout", "Bangla Hits", "Lofi", "Podcast"];
  String _selectedCategory = "Trending";

  @override
  void initState() {
    super.initState();
    _logger.info('Initializing YoutubePlayerScreen');
    _searchVideos("Trending Music Bangladesh", isCategory: true);
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _yt.close();
    _downloadProgressNotifier.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentSearchList != null) {
        _logger.info('User reached bottom. Loading more videos...');
        _loadMoreVideos();
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    setState(() => _isLoadingMore = true);
    try {
      var nextList = await _currentSearchList!.nextPage();
      if (nextList != null && mounted) {
        setState(() {
          _searchResults.addAll(nextList.toList());
          _currentSearchList = nextList;
        });
        _logger.info('Loaded ${nextList.length} more videos');
      }
    } catch (e) {
      _logger.warning('Load More Error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _getSuggestions(String query) async {
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final moods = ["Sad music", "Gym workout", "Lofi beats", "Party dance", "Bangla hits", "New songs", "Focus study"];
      setState(() => _suggestions = moods.where((m) => m.toLowerCase().contains(query.toLowerCase())).toList());
    } catch (e) {
      _logger.warning('Suggestion Error: $e');
    }
  }

  Future<void> _searchVideos(String query, {bool isCategory = false}) async {
    if (query.isEmpty) return;

    // সব ধরণের সার্চকেই AI Expansion এর মধ্য দিয়ে পাঠানো হচ্ছে যাতে Music রেজাল্ট নিশ্চিত হয়
    String finalQuery = _expandQueryWithAI(query);
    _logger.info('Searching: $finalQuery (Original: $query)');

    if (!isCategory) {
      FocusScope.of(context).unfocus();
      setState(() {
        _selectedCategory = "";
        _suggestions = [];
      });
    }

    setState(() {
      _isSearching = true;
      _searchResults = [];
    });

    try {
      _currentSearchList = await _yt.search.search(finalQuery);
      if (!mounted) return;
      setState(() {
        _searchResults = _currentSearchList!.toList();
      });
      _logger.info('Found ${_searchResults.length} music tracks');
    } catch (e) {
      if (!mounted) return;
      _logger.severe('Search Error: $e');
      
      String errorMessage = 'Search Error: Check internet';
      if (DateTime.now().year > 2025) {
        errorMessage = 'Fix your System Date! It is set to ${DateTime.now().year}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _searchVideos(query, isCategory: isCategory),
            textColor: Colors.white,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return "--:--";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:${twoDigitMinutes}:${twoDigitSeconds}";
    }
    return "${duration.inMinutes}:${twoDigitSeconds}";
  }

  String _expandQueryWithAI(String query) {
    final lowerQuery = query.toLowerCase();
    // Force music search by adding specific keywords
    String musicTag = "official audio music song";
    
    if (lowerQuery.contains("sad") || lowerQuery.contains("broken") || lowerQuery.contains("mon kharap")) {
      return "$query $musicTag emotional deep acoustic sad";
    } else if (lowerQuery.contains("gym") || lowerQuery.contains("workout") || lowerQuery.contains("energy")) {
      return "$query $musicTag high energy aggressive workout phonk pump";
    } else if (lowerQuery.contains("study") || lowerQuery.contains("focus") || lowerQuery.contains("poralekha")) {
      return "$query $musicTag lofi hip hop chill study relax beats 24/7";
    } else if (lowerQuery.contains("party") || lowerQuery.contains("dance") || lowerQuery.contains("nach")) {
      return "$query $musicTag popular dance party club house remix";
    } else if (lowerQuery.contains("bangla") || lowerQuery.contains("gaan")) {
      return "$query latest popular bangla hits songs";
    }
    
    // Default: append music tag to any query to ensure music results
    return "$query $musicTag";
  }

  Future<void> _playVideo(Video video) async {
    _logger.info('Attempting to play: ${video.title}');
    setState(() {
      _currentVideo = video;
      _downloadProgressNotifier.value = 0;
    });

    try {
      // ১. আগের ক্যাশ ডিলিট করা (App যাতে ভারী না হয়)
      await _downloadService.clearAllCache();

      final videoUrl = 'https://www.youtube.com/watch?v=${video.id.value}';
      final apiUrl = _downloadService.getApiUrl(videoUrl);
      final cacheFilePath = await _downloadService.getCacheFilePath(video.id.value);

      if (!mounted) return;

      // ২. LockCachingAudioSource (স্ট্রিমিং শুরু হতেই প্লে হবে এবং সাথে সেভ হবে)
      final audioSource = LockCachingAudioSource(
        Uri.parse(apiUrl),
        cacheFile: File(cacheFilePath),
        tag: MediaItem(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          artUri: Uri.parse(video.thumbnails.highResUrl),
        ),
      );

      audioSource.downloadProgressStream.listen((progress) {
        _downloadProgressNotifier.value = progress;
        // একবার গান শুরু হয়ে গেলে যদি বাফার ১০% এর বেশি হয়, তবে প্লে শুরু হবে
        if (progress > 0.05 && _audioPlayer.processingState == ProcessingState.loading) {
          _audioPlayer.play();
        }
        if (progress >= 1.0) _logger.info('Streaming cache complete for: ${video.title}');
      });

      await _audioPlayer.setAudioSource(audioSource, preload: true);
      _audioPlayer.play();
      _logger.info('Playback initialized and playing');
    } catch (e) {
      if (!mounted) return;
      _logger.severe('Playback Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load music')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.redAccent, size: 28),
            const SizedBox(width: 8),
            const Text('MusiCore', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 24)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.history_rounded, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(),
            _buildCategoryChips(),
            Expanded(
              child: _isSearching
                  ? _buildShimmerLoading()
                  : _searchResults.isEmpty
                      ? _buildHomePlaceholder()
                      : _buildResultList(),
            ),
          ],
        ),
      ),
      bottomSheet: _currentVideo != null ? _buildMiniPlayer() : null,
    );
  }

  Widget _buildSearchBar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Container(
            height: 55,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _getSuggestions,
              onSubmitted: _searchVideos,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ask AI: "Gym vibes" or "Mon kharap"',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                prefixIcon: const Icon(Icons.auto_awesome, color: Colors.redAccent, size: 20),
                suffixIcon: const Icon(Icons.mic_none_rounded, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(_suggestions[index], style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    backgroundColor: Colors.white.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onPressed: () {
                      _searchController.text = _suggestions[index];
                      _searchVideos(_suggestions[index]);
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0, bottom: 10),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedCategory = category);
                _searchVideos(category, isCategory: true);
              },
              backgroundColor: Colors.white.withOpacity(0.05),
              selectedColor: Colors.redAccent,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedCategory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Text(
              _selectedCategory == "Trending" ? "Trending Today" : "Recommended for $_selectedCategory",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
            padding: const EdgeInsets.only(bottom: 100),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              if (index == _searchResults.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
                );
              }
              final video = _searchResults[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Hero(
                  tag: 'thumb_${video.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnails.lowResUrl,
                      width: 55,
                      height: 55,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.white10),
                    ),
                  ),
                ),
                title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("${video.author} • ${_formatDuration(video.duration)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.grey), onPressed: () {}),
                onTap: () {
                  _playVideo(video);
                  _showPlayerDetails(video);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPlayerDetails(Video video) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => PlayerDetailsScreen(
          video: video,
          audioPlayer: _audioPlayer,
          downloadProgressNotifier: _downloadProgressNotifier,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutExpo))),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildHomePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note_rounded, size: 100, color: Colors.redAccent.withOpacity(0.2)),
          const SizedBox(height: 16),
          const Text('Search music to start streaming', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _searchVideos("Trending Music Bangladesh", isCategory: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Load Trending'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withOpacity(0.1),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: InkWell(
        onTap: () => _showPlayerDetails(_currentVideo!),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: _currentVideo!.thumbnails.lowResUrl, width: 45, height: 45, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_currentVideo!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(_currentVideo!.author, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              _buildMiniControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniControls() {
    return Row(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _downloadProgressNotifier,
          builder: (context, progress, child) {
            return StreamBuilder<PlayerState>(
              stream: _audioPlayer.playerStateStream,
              builder: (context, snapshot) {
                final processingState = snapshot.data?.processingState;
                if (processingState == ProcessingState.buffering || (progress > 0 && progress < 0.1)) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent)),
                      if (progress > 0)
                        Text("${(progress * 100).toInt()}%", style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  );
                }
                final playing = snapshot.data?.playing ?? false;
                return IconButton(
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 30),
                  onPressed: () => playing ? _audioPlayer.pause() : _audioPlayer.play(),
                );
              },
            );
          },
        ),
        IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => setState(() => _currentVideo = null)),
      ],
    );
  }

  Widget _buildShimmerLoading() {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (context, index) => Shimmer.fromColors(
        baseColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.white.withOpacity(0.1),
        child: ListTile(
          leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
          title: Container(height: 15, color: Colors.white, margin: const EdgeInsets.only(right: 50)),
          subtitle: Container(height: 10, color: Colors.white, margin: const EdgeInsets.only(right: 150, top: 5)),
        ),
      ),
    );
  }
}
