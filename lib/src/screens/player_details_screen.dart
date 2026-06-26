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
  String? _videoErrorMessage;
  String? _lastInitializedVideoId;

  @override
  void initState() {
    super.initState();
    _determineInitialMode();
  }

  void _determineInitialMode() {
    final currentVideoId = widget.video.id.value;
    // লোকাল পাথ ডিটেকশন
    final bool isLocal = currentVideoId.contains('/') || currentVideoId == 'local';
    
    if (isLocal) {
      // লোকাল ফাইলের জন্য ডেসক্রিপশন বা আইডিতে পাথ থাকে, সেটি চেক করা
      final String path = currentVideoId.contains('/') ? currentVideoId : widget.video.description;
      _isVideoMode = path.toLowerCase().endsWith('.mp4');
    } else {
      // রিমোট ভিডিওর জন্য স্মার্ট ডিটেকশন
      _isVideoMode = !_isLikelySong(widget.video);
    }

    // যদি ভিডিও মোড হয়, তবে শুরুতেই ইনিশিয়ালাইজ করা
    if (_isVideoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final String? localPath = isLocal ? (currentVideoId.contains('/') ? currentVideoId : widget.video.description) : null;
        _initNativeVideo(currentVideoId, localPath);
      });
    }
  }

  bool _isLikelySong(Video video) {
    final title = video.title.toLowerCase();
    final author = video.author.toLowerCase();
    
    // গানের সাধারণ কি-ওয়ার্ডগুলো চেক করা
    final musicKeywords = [
      'song', 'music', 'audio', 'lyrics', 'lyrical', 'official video', 
      'music video', 'full song', 'remix', 'cover', 'unplugged', 'hits', 'gaan'
    ];
    
    // যদি টাইটেল বা চ্যানেল নেম-এ মিউজিক রিলেটেড কিছু থাকে
    bool hasMusicKeyword = musicKeywords.any((k) => title.contains(k) || author.contains(k));
    
    // যদি ভিডিওটি ১-১২ মিনিটের মধ্যে হয় (মিউজিক ভিডিওর সাধারণ ডিউরেশন)
    bool isStandardDuration = video.duration != null && 
        video.duration!.inMinutes >= 1 && 
        video.duration!.inMinutes <= 12;

    return hasMusicKeyword || isStandardDuration;
  }

  Future<void> _initNativeVideo(String videoId, String? localPath) async {
    // যদি অলরেডি এই ভিডিওটি লোড করা থাকে, তবে নতুন করে এপিআই কল করার দরকার নেই
    if (_isInitializingVideo || _lastInitializedVideoId == videoId) {
      _videoController?.play(); // জাস্ট প্লে করে দাও
      return;
    }
    
    await _videoController?.dispose();
    _chewieController?.dispose();
    
    setState(() {
      _isInitializingVideo = true;
      _videoErrorMessage = null;
      _lastInitializedVideoId = videoId;
    });

    try {
      // লোকাল ফাইল নাকি অনলাইন ভিডিও তা নিশ্চিত করা
      bool isLocalFile = videoId.contains('/') || videoId == 'local_file' || videoId == 'local';
      
      if (isLocalFile) {
        String path = localPath ?? videoId;
        if (File(path).existsSync()) {
          _videoController = VideoPlayerController.file(File(path));
        } else {
          throw "Local file not found at: $path";
        }
      } else {
        // ইউটিউব ভিডিওর জন্য লজিক
        var manifest = await _yt.videos.streamsClient.getManifest(videoId);
        VideoStreamInfo streamInfo = manifest.muxed.withHighestBitrate();
        
        if (streamInfo == null) {
          // যদি muxed না থাকে তবে শুধু ভিডিও স্ট্রীম নেওয়া (অডিও ছাড়া হতে পারে)
          streamInfo = manifest.video.withHighestBitrate();
        }
        
        if (streamInfo != null) {
          _videoController = VideoPlayerController.networkUrl(streamInfo.url);
        } else {
          throw "No playable video streams found for this video.";
        }
      }

      if (_videoController != null) {
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
      debugPrint("Video Player Error: $e");
      setState(() => _videoErrorMessage = "Failed to load video. Please try again.");
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

  void _toggleMode(bool isVideo, String videoId, String? localPath) {
    setState(() {
      _isVideoMode = isVideo;
      _videoErrorMessage = null;
    });
    
    if (isVideo) {
      widget.audioPlayer.pause();
      _initNativeVideo(videoId, localPath);
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
        
        // লোকাল পাথ ডিটেকশন
        final bool isLocal = currentVideoId.contains('/') || currentVideoId == 'local';
        final String? localPath = isLocal ? (currentVideoId.contains('/') ? currentVideoId : widget.video.description) : null;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          body: SafeArea(
            child: Column(
              children: [
                _buildAppBar(currentTitle, currentVideoId, isLocal),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        _buildModeSwitcher(currentVideoId, localPath),
                        const Spacer(),
                        _isVideoMode 
                          ? _buildVideoPlayer() 
                          : _buildMusicPlayer(currentVideoId, currentArtUri, isLocal),
                        const Spacer(),
                        _buildVideoInfo(currentTitle, currentArtist),
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
      },
    );
  }

  Widget _buildAppBar(String title, String videoId, bool isLocal) {
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
          if (!isLocal)
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white),
              onPressed: () => _confirmDownload(title, videoId),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  void _confirmDownload(String title, String videoId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text("Download Song?", style: TextStyle(color: Colors.white)),
        content: Text("Do you want to download '$title'?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startDownload(title, videoId);
            }, 
            child: const Text("Download", style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload(String title, String videoId) async {
    final videoUrl = 'https://www.youtube.com/watch?v=$videoId';
    final String? filePath = await _downloadService.downloadToStorage(title, _downloadService.getApiUrl(videoUrl));
    if (filePath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download Complete!'), backgroundColor: Colors.green));
    }
  }

  Widget _buildModeSwitcher(String videoId, String? localPath) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton("Music", !_isVideoMode, videoId, localPath),
          _modeButton("Video", _isVideoMode, videoId, localPath),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool active, String videoId, String? localPath) {
    return GestureDetector(
      onTap: () => _toggleMode(label == "Video", videoId, localPath),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(color: active ? Colors.redAccent : Colors.transparent, borderRadius: BorderRadius.circular(25)),
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildMusicPlayer(String videoId, String artUri, bool isLocal) {
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
            child: isLocal 
              ? Container(color: Colors.white10, child: const Icon(Icons.audiotrack_rounded, size: 100, color: Colors.redAccent))
              : CachedNetworkImage(imageUrl: artUri, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.music_note, size: 100, color: Colors.white24)),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isInitializingVideo) {
      return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator(color: Colors.redAccent)));
    }
    
    if (_videoErrorMessage != null) {
      return AspectRatio(
        aspectRatio: 16 / 9, 
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 8),
              Text(_videoErrorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        )
      );
    }

    if (_chewieController != null && _videoController != null && _videoController!.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(aspectRatio: 16 / 9, child: Chewie(controller: _chewieController!)),
      );
    }
    
    return const AspectRatio(aspectRatio: 16 / 9, child: Center(child: Icon(Icons.video_library, color: Colors.white24, size: 50)));
  }

  Widget _buildVideoInfo(String title, String artist) {
    return Column(
      children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Shuffle Button
            StreamBuilder<bool>(
              stream: widget.audioPlayer.shuffleModeEnabledStream,
              initialData: widget.audioPlayer.shuffleModeEnabled,
              builder: (context, snapshot) {
                final shuffleEnabled = snapshot.data ?? false;
                return IconButton(
                  icon: Icon(
                    Icons.shuffle_rounded, 
                    color: shuffleEnabled ? Colors.redAccent : Colors.white54, 
                    size: 22
                  ),
                  onPressed: () => widget.audioPlayer.setShuffleModeEnabled(!shuffleEnabled),
                );
              },
            ),
            IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 45, color: Colors.white), onPressed: widget.onPrevious),
            _buildPlayPauseButton(),
            IconButton(icon: const Icon(Icons.skip_next_rounded, size: 45, color: Colors.white), onPressed: widget.onNext),
            // Repeat Button
            StreamBuilder<LoopMode>(
              stream: widget.audioPlayer.loopModeStream,
              initialData: widget.audioPlayer.loopMode,
              builder: (context, snapshot) {
                final loopMode = snapshot.data ?? LoopMode.off;
                IconData icon;
                Color color;
                
                switch (loopMode) {
                  case LoopMode.off:
                    icon = Icons.repeat_rounded;
                    color = Colors.white54;
                    break;
                  case LoopMode.one:
                    icon = Icons.repeat_one_rounded;
                    color = Colors.redAccent;
                    break;
                  case LoopMode.all:
                    icon = Icons.repeat_rounded;
                    color = Colors.redAccent;
                    break;
                }
                
                return IconButton(
                  icon: Icon(icon, color: color, size: 22),
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
    if (_isVideoMode) {
      // ভিডিও মোডে ভিডিও কন্ট্রোলার ব্যবহার করা
      return ListenableBuilder(
        listenable: _videoController ?? VideoPlayerController.networkUrl(Uri.parse('')),
        builder: (context, child) {
          final isPlaying = _videoController?.value.isPlaying ?? false;
          final isBuffering = _videoController?.value.isBuffering ?? false;

          if (isBuffering || _isInitializingVideo) {
            return const SizedBox(width: 80, height: 80, child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.redAccent)));
          }

          return IconButton(
            icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 85, color: Colors.white),
            onPressed: () {
              if (isPlaying) {
                _videoController?.pause();
              } else {
                _videoController?.play();
              }
              setState(() {}); // UI আপডেট করার জন্য
            },
          );
        },
      );
    }

    // মিউজিক মোডে অডিও প্লেয়ার ব্যবহার করা
    return StreamBuilder<PlayerState>(
      stream: widget.audioPlayer.playerStateStream,
      initialData: widget.audioPlayer.playerState,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final playing = playerState?.playing ?? false;
        final processingState = playerState?.processingState;
        if (processingState == ProcessingState.loading || processingState == ProcessingState.buffering) {
          return const SizedBox(width: 80, height: 80, child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.redAccent)));
        }
        return IconButton(
          icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 85, color: Colors.white),
          onPressed: () => playing ? widget.audioPlayer.pause() : widget.audioPlayer.play(),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Widget _formatDurationWidget(Duration duration) {
    return Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 11));
  }
}
