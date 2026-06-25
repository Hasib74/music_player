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
import '../services/history_service.dart';

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
  final HistoryService _historyService = HistoryService();
  final ValueNotifier<double> _downloadProgressNotifier = ValueNotifier(0);

  List<Video> _searchResults = [];
  List<Video> _historyVideos = [];
  List<Video> _aiRecommendations = [];
  List<Video> _currentQueue = [];
  int _currentIndex = -1;

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
    _loadInitialData();
    _scrollController.addListener(_scrollListener);

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });
  }

  Future<void> _loadInitialData() async {
    await _loadHistory();
    _searchVideos("Trending Music Bangladesh", isCategory: true);
    _generateAISuggestions();
  }

  Future<void> _loadHistory() async {
    final history = await _historyService.getHistory();
    if (mounted) {
      setState(() {
        _historyVideos = history;
      });
    }
  }

  Future<void> _generateAISuggestions() async {
    final query = await _historyService.getAISuggestionQuery();
    try {
      final results = await _yt.search.search(query);
      if (mounted) {
        setState(() {
          _aiRecommendations = results.take(10).toList();
        });
      }
    } catch (e) {
      _logger.warning('AI Suggestion Error: $e');
    }
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

  Future<void> _searchVideos(String query, {bool isCategory = false, int retryCount = 0}) async {
    if (query.isEmpty) return;

    String finalQuery = _expandQueryWithAI(query);
    if (!isCategory) {
      FocusScope.of(context).unfocus();
      setState(() {
        _selectedCategory = "";
        _suggestions = [];
      });
    }

    if (retryCount == 0) {
      setState(() {
        _isSearching = true;
        _searchResults = [];
      });
    }

    try {
      _currentSearchList = await _yt.search.search(finalQuery);
      if (!mounted) return;
      
      final results = _currentSearchList!.toList();
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      if (!mounted) return;
      
      _logger.warning('Search error (attempt ${retryCount + 1}): $e');
      
      if (retryCount < 2) {
        await Future.delayed(Duration(seconds: 1 + retryCount));
        return _searchVideos(query, isCategory: isCategory, retryCount: retryCount + 1);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube parsing error. Try a simpler search term.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted && retryCount >= 0) setState(() => _isSearching = false);
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return "--:--";
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${duration.inMinutes}:${twoDigitSeconds}";
  }

  String _expandQueryWithAI(String query) {
    final input = query.toLowerCase().trim();
    
    // ক্যাটাগরি অনুযায়ী ক্লিন কিউরি (অতিরিক্ত ট্যাগ রিমুভ করা হয়েছে এরর এড়াতে)
    if (input == "relax") return "Relaxing chill music 2024";
    if (input == "trending") return "Trending music hits";
    if (input == "workout") return "Workout motivation music";
    if (input == "lofi") return "Lofi hip hop beats";
    if (input == "bangla hits") return "New bangla hits 2024";
    if (input == "podcast") return "Music podcast 2024";

    // NLP Mood & Intent Detection
    if (input.contains("sad") || input.contains("low") || input.contains("broken")) {
      return "soulful sad music songs";
    }
    if (input.contains("gym") || input.contains("workout") || input.contains("energy")) {
      return "high energy gym motivation workout";
    }
    
    return query;
  }

  Future<void> _playVideo(Video video, {List<Video>? queue}) async {
    if (queue != null) {
      _currentQueue = queue;
      _currentIndex = _currentQueue.indexWhere((v) => v.id.value == video.id.value);
    }

    setState(() {
      _currentVideo = video;
      _downloadProgressNotifier.value = 0;
    });

    await _historyService.addToHistory(video);
    _loadHistory();

    try {
      await _downloadService.clearAllCache();
      final videoUrl = 'https://www.youtube.com/watch?v=${video.id.value}';
      final apiUrl = _downloadService.getApiUrl(videoUrl, stream: true);
      final cacheFilePath = await _downloadService.getCacheFilePath(video.id.value);

      if (!mounted) return;

      final audioSource = LockCachingAudioSource(
        Uri.parse(apiUrl),
        cacheFile: File(cacheFilePath),
        tag: MediaItem(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          artUri: Uri.parse(video.thumbnails.highResUrl),
          duration: video.duration,
        ),
      );

      audioSource.downloadProgressStream.listen((progress) {
        _downloadProgressNotifier.value = progress;
        if (progress > 0.05 && _audioPlayer.processingState == ProcessingState.loading) {
          _audioPlayer.play();
        }
      });

      await _audioPlayer.setAudioSource(audioSource, preload: true);
      _audioPlayer.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to stream music')),
      );
    }
  }

  void _playNext() {
    if (_currentQueue.isNotEmpty && _currentIndex < _currentQueue.length - 1) {
      _playVideo(_currentQueue[_currentIndex + 1]);
    }
  }

  void _playPrevious() {
    if (_currentQueue.isNotEmpty && _currentIndex > 0) {
      _playVideo(_currentQueue[_currentIndex - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildSearchBar(),
            _buildCategoryChips(),
            Expanded(
              child: _isSearching
                  ? _buildShimmerLoading()
                  : RefreshIndicator(
                      onRefresh: _loadInitialData,
                      color: Colors.redAccent,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_searchController.text.isEmpty) ...[
                              _buildHistorySection(),
                              _buildAIRecommendedSection(),
                              _buildSectionHeader(
                                "Trending Now",
                                onTap: () => _searchVideos("Trending Music", isCategory: true),
                              ),
                            ],
                            _buildResultList(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomSheet: _currentVideo != null ? _buildMiniPlayer() : null,
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.redAccent, size: 24),
              const SizedBox(width: 8),
              Text('MusiCore', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 22, letterSpacing: -0.5)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _getSuggestions,
              onSubmitted: (val) => _searchVideos(val),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Try: "I am feeling low" or "Gym hits"',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                prefixIcon: const Icon(Icons.auto_awesome, color: Colors.redAccent, size: 20),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : const Icon(Icons.search_rounded, color: Colors.white30, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI is curating your playlist...',
                    style: TextStyle(color: Colors.redAccent.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() => _selectedCategory = category);
                _searchVideos(category, isCategory: true);
              },
              backgroundColor: Colors.white.withOpacity(0.05),
              selectedColor: Colors.redAccent.withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? Colors.redAccent : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.redAccent.withOpacity(0.5) : Colors.transparent)),
              showCheckmark: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          if (onTap != null)
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('See all', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_historyVideos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Recently Played",
          onTap: () => _showFullListBottomSheet("Playback History", _historyVideos),
        ),
        SizedBox(
          height: 155,
// ... (rest of the list)
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _historyVideos.length,
            itemBuilder: (context, index) {
              final video = _historyVideos[index];
              return Container(
                width: 120,
                margin: const EdgeInsets.only(right: 14),
                child: InkWell(
                  onTap: () {
                    _playVideo(video, queue: _historyVideos);
                    _showPlayerDetails(video);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: video.thumbnails.highResUrl,
                          height: 100,
                          width: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(video.author, maxLines: 1, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAIRecommendedSection() {
    if (_aiRecommendations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          "Recommended For You",
          onTap: () => _showFullListBottomSheet("For You", _aiRecommendations),
        ),
        SizedBox(
          height: 190,
// ... (rest of the list)
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _aiRecommendations.length,
            itemBuilder: (context, index) {
              final video = _aiRecommendations[index];
              return Container(
                width: 160,
                margin: const EdgeInsets.only(right: 16),
                child: InkWell(
                  onTap: () {
                    _playVideo(video, queue: _aiRecommendations);
                    _showPlayerDetails(video);
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: CachedNetworkImage(
                              imageUrl: video.thumbnails.mediumResUrl,
                              height: 130,
                              width: 160,
                              fit: BoxFit.cover,
                            ),
                          ),
                          PositionResult(duration: _formatDuration(video.duration)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.2)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _searchResults.length + (_isLoadingMore ? 1 : 0),
      padding: const EdgeInsets.only(bottom: 100),
      itemBuilder: (context, index) {
        if (index == _searchResults.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 2)),
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
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),
          ),
          title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text("${video.author} • ${_formatDuration(video.duration)}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
          trailing: IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.white24, size: 20), onPressed: () {}),
          onTap: () {
            _playVideo(video, queue: _searchResults);
            _showPlayerDetails(video);
          },
        );
      },
    );
  }

  void _showFullListBottomSheet(String title, List<Video> videos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (title == "Playback History")
                    TextButton.icon(
                      onPressed: () => _confirmClearHistory(),
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                      label: const Text("Clear All", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: video.thumbnails.lowResUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      video.author,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _playVideo(video, queue: videos);
                      _showPlayerDetails(video);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Clear History?", style: TextStyle(color: Colors.white)),
        content: const Text("Do you want to delete your playback history?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              await _historyService.clearHistory();
              if (mounted) {
                setState(() {
                  _historyVideos = [];
                });
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close bottom sheet
              }
            },
            child: const Text("Clear", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
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
          onNext: _playNext,
          onPrevious: _playPrevious,
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
    return const SizedBox.shrink(); 
  }

  Widget _buildMiniPlayer() {
    return Container(
      color: Colors.transparent, // Background color for the area behind the floating player
      child: SafeArea(
        top: false,
        child: Container(
          height: 72,
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: InkWell(
            onTap: () => _showPlayerDetails(_currentVideo!),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: _currentVideo!.thumbnails.lowResUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentVideo!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _currentVideo!.author,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildMiniControls(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniControls() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
          onPressed: _playPrevious,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(width: 4),
        ValueListenableBuilder<double>(
          valueListenable: _downloadProgressNotifier,
          builder: (context, progress, child) {
            return StreamBuilder<PlayerState>(
              stream: _audioPlayer.playerStateStream,
              initialData: _audioPlayer.playerState,
              builder: (context, snapshot) {
                final playerState = snapshot.data;
                final processingState = playerState?.processingState;
                final playing = playerState?.playing ?? false;
                
                if (processingState == ProcessingState.loading || 
                    processingState == ProcessingState.buffering || 
                    (progress > 0 && progress < 0.1)) {
                  return const SizedBox(
                    width: 32, 
                    height: 32, 
                    child: Padding(
                      padding: EdgeInsets.all(4), 
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent)
                    )
                  );
                }
                return IconButton(
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                    color: Colors.white, 
                    size: 32
                  ),
                  onPressed: () => playing ? _audioPlayer.pause() : _audioPlayer.play(),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                );
              },
            );
          },
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
          onPressed: _playNext,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
          onPressed: () {
            _audioPlayer.stop();
            setState(() {
              _currentVideo = null;
            });
          },
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
        ),
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

class PositionResult extends StatelessWidget {
  final String duration;
  const PositionResult({super.key, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(4)),
        child: Text(duration, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
