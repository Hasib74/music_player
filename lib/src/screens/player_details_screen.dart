import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' hide PlayerState;
import 'package:permission_handler/permission_handler.dart';
import '../services/download_service.dart';

class PlayerDetailsScreen extends StatefulWidget {
  final Video video;
  final AudioPlayer audioPlayer;
  final ValueNotifier<double> downloadProgressNotifier;

  const PlayerDetailsScreen({
    super.key,
    required this.video,
    required this.audioPlayer,
    required this.downloadProgressNotifier,
  });

  @override
  State<PlayerDetailsScreen> createState() => _PlayerDetailsScreenState();
}

class _PlayerDetailsScreenState extends State<PlayerDetailsScreen> {
  bool _isVideoMode = false;
  late YoutubePlayerController _ytController;
  final DownloadService _downloadService = DownloadService();

  @override
  void initState() {
    super.initState();
    _ytController = YoutubePlayerController.fromVideoId(
      videoId: widget.video.id.value,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        mute: false,
      ),
    );
  }

  @override
  void dispose() {
    _ytController.close();
    super.dispose();
  }

  Future<void> _handleDownload() async {
    final status = await Permission.storage.request();
    if (!mounted) return;

    bool isGranted = status.isGranted;
    if (!isGranted) {
      isGranted = await Permission.manageExternalStorage.request().isGranted;
    }

    if (!mounted) return;

    if (isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting download to storage...')),
      );
      final videoUrl = 'https://www.youtube.com/watch?v=${widget.video.id.value}';
      final apiUrl = _downloadService.getApiUrl(videoUrl);
      await _downloadService.downloadToStorage(widget.video.title, apiUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission denied')),
      );
    }
  }

  void _toggleMode(bool isVideo) {
    setState(() => _isVideoMode = isVideo);
    if (isVideo) {
      widget.audioPlayer.pause();
    } else {
      _ytController.pauseVideo();
      widget.audioPlayer.play();
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    _buildModeSwitcher(),
                    const Spacer(),
                    _isVideoMode ? _buildVideoPlayer() : _buildMusicPlayer(),
                    const Spacer(),
                    _buildVideoInfo(),
                    const SizedBox(height: 30),
                    if (!_isVideoMode) _buildControls(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white), onPressed: () => Navigator.pop(context)),
          const Text('NOW PLAYING', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
          IconButton(icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white), onPressed: _handleDownload),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton("Music", !_isVideoMode),
          _modeButton("Video", _isVideoMode),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool active) {
    return GestureDetector(
      onTap: () => _toggleMode(label == "Video"),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(color: active ? Colors.redAccent : Colors.transparent, borderRadius: BorderRadius.circular(25)),
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildMusicPlayer() {
    return Hero(
      tag: 'thumb_${widget.video.id}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 40, spreadRadius: 10)],
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(imageUrl: widget.video.thumbnails.highResUrl, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(aspectRatio: 16 / 9, child: YoutubePlayer(controller: _ytController)),
    );
  }

  Widget _buildVideoInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(widget.video.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text(widget.video.author, style: const TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildControls() {
    return Column(
      children: [
        StreamBuilder<Duration>(
          stream: widget.audioPlayer.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = widget.audioPlayer.duration ?? Duration.zero;
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: Colors.redAccent,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: Colors.white,
                    overlayColor: Colors.redAccent.withOpacity(0.2),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: position.inSeconds.toDouble(),
                    max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                    onChanged: (value) => widget.audioPlayer.seek(Duration(seconds: value.toInt())),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(icon: const Icon(Icons.shuffle_rounded, color: Colors.grey), onPressed: () {}),
            IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 45, color: Colors.white), onPressed: () {}),
            _buildPlayPauseButton(),
            IconButton(icon: const Icon(Icons.skip_next_rounded, size: 45, color: Colors.white), onPressed: () {}),
            IconButton(icon: const Icon(Icons.repeat_rounded, color: Colors.grey), onPressed: () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton() {
    return ValueListenableBuilder<double>(
      valueListenable: widget.downloadProgressNotifier,
      builder: (context, progress, child) {
        return StreamBuilder<PlayerState>(
          stream: widget.audioPlayer.playerStateStream,
          builder: (context, snapshot) {
            final processingState = snapshot.data?.processingState;
            final playing = snapshot.data?.playing ?? false;
            
            if (processingState == ProcessingState.buffering || processingState == ProcessingState.loading) {
              return const SizedBox(width: 80, height: 80, child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 3)));
            }
            return IconButton(
              icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 85, color: Colors.white),
              onPressed: () => playing ? widget.audioPlayer.pause() : widget.audioPlayer.play(),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
