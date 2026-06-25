import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audio_service/audio_service.dart';
import '../services/download_service.dart';

class PlayerDetailsScreen extends StatefulWidget {
  final Video video;
  final AudioPlayer audioPlayer;
  final ValueNotifier<double> downloadProgressNotifier;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const PlayerDetailsScreen({
    super.key,
    required this.video,
    required this.audioPlayer,
    required this.downloadProgressNotifier,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<PlayerDetailsScreen> createState() => _PlayerDetailsScreenState();
}

class _PlayerDetailsScreenState extends State<PlayerDetailsScreen> {
  bool _isVideoMode = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  final DownloadService _downloadService = DownloadService();
  final YoutubeExplode _yt = YoutubeExplode();
  bool _isInitializingVideo = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initNativeVideo(String videoId) async {
    if (_isInitializingVideo) return;
    setState(() => _isInitializingVideo = true);

    try {
      // Get stream manifest
      var manifest = await _yt.videos.streamsClient.getManifest(videoId);
      // Get best muxed stream (video + audio) for native player compatibility
      var streamInfo = manifest.muxed.withHighestBitrate();
      
      if (streamInfo != null) {
        _videoController = VideoPlayerController.networkUrl(streamInfo.url);
        await _videoController!.initialize();

        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
          aspectRatio: _videoController!.value.aspectRatio,
          allowFullScreen: true,
          allowPlaybackSpeedChanging: true,
          showControls: true,
          deviceOrientationsAfterFullScreen: [DeviceOrientation.portraitUp],
          placeholder: Container(color: Colors.black),
          materialProgressColors: ChewieProgressColors(
            playedColor: Colors.redAccent,
            handleColor: Colors.redAccent,
            backgroundColor: Colors.white24,
            bufferedColor: Colors.white54,
          ),
        );
      }
    } catch (e) {
      debugPrint("Video Init Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isInitializingVideo = false);
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _yt.close();
    super.dispose();
  }

  void _toggleMode(bool isVideo, String videoId) {
    setState(() => _isVideoMode = isVideo);
    if (isVideo) {
      widget.audioPlayer.pause();
      _initNativeVideo(videoId);
    } else {
      _videoController?.pause();
      widget.audioPlayer.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: widget.audioPlayer.sequenceStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final metadata = state?.currentSource?.tag as MediaItem?;
        final currentVideoId = metadata?.id ?? widget.video.id.value;
        final currentTitle = metadata?.title ?? widget.video.title;
        final currentArtist = metadata?.artist ?? widget.video.author;
        final currentArtUri = metadata?.artUri?.toString() ?? widget.video.thumbnails.highResUrl;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: SafeArea(
            child: Column(
              children: [
                _buildAppBar(currentTitle, currentVideoId),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        _buildModeSwitcher(currentVideoId),
                        const Spacer(),
                        _isVideoMode 
                          ? _buildVideoPlayer(currentVideoId) 
                          : _buildMusicPlayer(currentVideoId, currentArtUri),
                        const Spacer(),
                        _buildVideoInfo(currentTitle, currentArtist),
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
      },
    );
  }

  Widget _buildAppBar(String title, String videoId) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white), 
            onPressed: () => Navigator.pop(context)
          ),
          const Text('NOW PLAYING', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
          IconButton(
            icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white),
            onPressed: () {
              final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
              final apiUrl = _downloadService.getApiUrl(videoUrl);
              // ফোল্ডার সিলেক্ট অপশন সহ ডাউনলোড
            //  _downloadService.downloadWithPicker(title, apiUrl);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a folder to start download')),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher(String videoId) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton("Music", !_isVideoMode, videoId),
          _modeButton("Video", _isVideoMode, videoId),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool active, String videoId) {
    return GestureDetector(
      onTap: () => _toggleMode(label == "Video", videoId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.redAccent : Colors.transparent, 
          borderRadius: BorderRadius.circular(25)
        ),
        child: Text(
          label, 
          style: TextStyle(
            color: active ? Colors.white : Colors.grey, 
            fontWeight: FontWeight.bold, 
            fontSize: 13
          )
        ),
      ),
    );
  }

  Widget _buildMusicPlayer(String videoId, String artUri) {
    return Hero(
      tag: 'thumb_$videoId',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 40, spreadRadius: 10)],
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: artUri, 
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(
                color: Colors.white10, 
                child: const Icon(Icons.music_note, size: 100, color: Colors.white24)
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(String videoId) {
    if (_isInitializingVideo) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    if (_chewieController != null && _videoController != null && _videoController!.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Chewie(controller: _chewieController!),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Icon(Icons.video_library, color: Colors.white24, size: 50)),
      ),
    );
  }

  Widget _buildVideoInfo(String title, String artist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title, 
          textAlign: TextAlign.center, 
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), 
          maxLines: 2, 
          overflow: TextOverflow.ellipsis
        ),
        const SizedBox(height: 8),
        Text(artist, style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w600)),
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
                    trackHeight: 2,
                    activeTrackColor: Colors.redAccent,
                    inactiveTrackColor: Colors.white.withOpacity(0.1),
                    thumbColor: Colors.white,
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
                      Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Shuffle Button
            StreamBuilder<bool>(
              stream: widget.audioPlayer.shuffleModeEnabledStream,
              builder: (context, snapshot) {
                final shuffleEnabled = snapshot.data ?? false;
                return IconButton(
                  icon: Icon(
                    Icons.shuffle_rounded, 
                    color: shuffleEnabled ? Colors.redAccent : Colors.grey, 
                    size: 20
                  ),
                  onPressed: () => widget.audioPlayer.setShuffleModeEnabled(!shuffleEnabled),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded, size: 40, color: Colors.white), 
              onPressed: widget.onPrevious
            ),
            _buildPlayPauseButton(),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, size: 40, color: Colors.white), 
              onPressed: widget.onNext
            ),
            // Repeat Button
            StreamBuilder<LoopMode>(
              stream: widget.audioPlayer.loopModeStream,
              builder: (context, snapshot) {
                final loopMode = snapshot.data ?? LoopMode.off;
                const icons = [
                  Icons.repeat_rounded,
                  Icons.repeat_one_rounded,
                  Icons.repeat_rounded,
                ];
                const colors = [
                  Colors.grey,
                  Colors.redAccent,
                  Colors.redAccent,
                ];
                final index = loopMode == LoopMode.off ? 0 : (loopMode == LoopMode.one ? 1 : 2);
                
                return IconButton(
                  icon: Icon(icons[index], color: colors[index], size: 20),
                  onPressed: () {
                    final nextMode = LoopMode.values[(LoopMode.values.indexOf(loopMode) + 1) % LoopMode.values.length];
                    widget.audioPlayer.setLoopMode(nextMode);
                  },
                );
              },
            ),
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
          initialData: widget.audioPlayer.playerState,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing ?? false;
            
            if (processingState == ProcessingState.loading || 
                processingState == ProcessingState.buffering || 
                (progress > 0 && progress < 0.05)) {
              return const SizedBox(
                width: 80, 
                height: 80, 
                child: Padding(
                  padding: EdgeInsets.all(20), 
                  child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 3)
                )
              );
            }
            
            return IconButton(
              icon: Icon(
                playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, 
                size: 85, 
                color: Colors.white
              ),
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
