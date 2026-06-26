import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audio_service/audio_service.dart';

class LocalPlayerScreen extends StatefulWidget {
  final List<File> playlist;
  final int initialIndex;
  final AudioPlayer audioPlayer;

  const LocalPlayerScreen({
    super.key,
    required this.playlist,
    required this.initialIndex,
    required this.audioPlayer,
  });

  @override
  State<LocalPlayerScreen> createState() => _LocalPlayerScreenState();
}

class _LocalPlayerScreenState extends State<LocalPlayerScreen> {
  late int _currentIndex;
  bool _isVideoMode = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isInitializingVideo = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _updateMode();
  }

  void _updateMode() {
    final file = widget.playlist[_currentIndex];
    setState(() {
      _isVideoMode = file.path.toLowerCase().endsWith('.mp4');
    });
    
    if (_isVideoMode) {
      widget.audioPlayer.pause();
      _initVideo(file);
    } else {
      _videoController?.pause();
      _playAudio(file);
    }
  }

  Future<void> _playAudio(File file) async {
    try {
      final source = AudioSource.uri(
        Uri.file(file.path),
        tag: MediaItem(
          id: file.path,
          title: file.path.split('/').last,
          artist: 'Local Storage',
        ),
      );
      await widget.audioPlayer.setAudioSource(source);
      widget.audioPlayer.play();
    } catch (e) {
      debugPrint("Audio Play Error: $e");
    }
  }

  Future<void> _initVideo(File file) async {
    await _videoController?.dispose();
    _chewieController?.dispose();
    
    setState(() => _isInitializingVideo = true);

    try {
      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoController!.value.aspectRatio,
        allowFullScreen: true,
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
      
      // Update UI when video position changes (for the custom slider)
      _videoController!.addListener(() {
        if (mounted) setState(() {});
      });
      
    } catch (e) {
      debugPrint("Local Video Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isInitializingVideo = false);
      }
    }
  }

  void _next() {
    if (_currentIndex < widget.playlist.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _updateMode();
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _updateMode();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentFile = widget.playlist[_currentIndex];
    final fileName = currentFile.path.split('/').last;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(fileName),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    const Spacer(),
                    _isVideoMode ? _buildVideoPlayer() : _buildMusicPlayer(),
                    const Spacer(),
                    _buildFileInfo(fileName),
                    const SizedBox(height: 30),
                    _buildControls(),
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

  Widget _buildAppBar(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white), 
            onPressed: () => Navigator.pop(context)
          ),
          const Text('LOCAL PLAYER', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMusicPlayer() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 40, spreadRadius: 10)],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.audiotrack_rounded, size: 100, color: Colors.redAccent)
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isInitializingVideo) {
      return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator(color: Colors.redAccent)));
    }
    if (_chewieController != null && _videoController != null && _videoController!.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(aspectRatio: 16 / 9, child: Chewie(controller: _chewieController!)),
      );
    }
    return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: Icon(Icons.video_library, color: Colors.white24, size: 50)));
  }

  Widget _buildFileInfo(String title) {
    return Column(
      children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2),
        const SizedBox(height: 8),
        const Text("Local Storage", style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildControls() {
    if (_isVideoMode) {
      return _buildControlButtons();
    }

    return Column(
      children: [
        StreamBuilder<Duration>(
          stream: widget.audioPlayer.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = widget.audioPlayer.duration ?? Duration.zero;
            return Column(
              children: [
                Slider(
                  activeColor: Colors.redAccent,
                  inactiveColor: Colors.white10,
                  value: position.inSeconds.toDouble(),
                  max: duration.inSeconds.toDouble() > 0 ? duration.inSeconds.toDouble() : 1.0,
                  onChanged: (value) => widget.audioPlayer.seek(Duration(seconds: value.toInt())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _formatDurationWidget(position),
                      _formatDurationWidget(duration),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        _buildControlButtons(),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(icon: const Icon(Icons.shuffle, color: Colors.grey), onPressed: () {}),
        IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 45, color: Colors.white), onPressed: _previous),
        _buildPlayPauseButton(),
        IconButton(icon: const Icon(Icons.skip_next_rounded, size: 45, color: Colors.white), onPressed: _next),
        IconButton(icon: const Icon(Icons.repeat, color: Colors.grey), onPressed: () {}),
      ],
    );
  }

  Widget _buildPlayPauseButton() {
    if (_isVideoMode) {
      final isPlaying = _videoController?.value.isPlaying ?? false;
      return IconButton(
        icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 85, color: Colors.white),
        onPressed: () {
          if (isPlaying) {
            _videoController?.pause();
          } else {
            _videoController?.play();
          }
          setState(() {});
        },
      );
    }

    return StreamBuilder<PlayerState>(
      stream: widget.audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return IconButton(
          icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 85, color: Colors.white),
          onPressed: () => playing ? widget.audioPlayer.pause() : widget.audioPlayer.play(),
        );
      },
    );
  }

  Widget _formatDurationWidget(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return Text(
      "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}",
      style: const TextStyle(color: Colors.grey, fontSize: 11),
    );
  }
}
