import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeAudioSource extends StreamAudioSource {
  final YoutubeExplode yt;
  final Video video;
  final AudioStreamInfo streamInfo;

  YoutubeAudioSource({
    required this.yt,
    required this.video,
    required this.streamInfo,
  }) : super(tag: MediaItem(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          artUri: Uri.parse(video.thumbnails.highResUrl),
        ));

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final stream = yt.videos.streamsClient.get(streamInfo);
    return StreamAudioResponse(
      sourceLength: streamInfo.size.totalBytes,
      contentLength: streamInfo.size.totalBytes,
      offset: 0,
      contentType: 'audio/mpeg',
      stream: stream,
    );
  }
}
