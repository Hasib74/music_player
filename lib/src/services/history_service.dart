import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  static const String _fileName = 'playback_history.json';
  static const int _maxHistory = 20;

  Future<File> get _historyFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  // গান হিস্টোরিতে সেভ করা
  Future<void> addToHistory(Video video) async {
    try {
      final List<Video> history = await getHistory();
      
      // ডুপ্লিকেট রিমুভ করা
      history.removeWhere((item) => item.id.value == video.id.value);
      
      // নতুন গান সবার আগে রাখা
      history.insert(0, video);

      // লিমিট রাখা (২০টি গান)
      if (history.length > _maxHistory) {
        history.removeRange(_maxHistory, history.length);
      }

      final List<Map<String, dynamic>> jsonData = history.map((v) => {
        'id': v.id.value,
        'title': v.title,
        'author': v.author,
        'channelId': v.channelId.value,
        'duration': v.duration?.inSeconds,
        'thumbnail': v.thumbnails.highResUrl,
        'uploadDate': v.uploadDate?.toIso8601String(),
        'description': v.description,
      }).toList();

      final file = await _historyFile;
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      print('History Save Error: $e');
    }
  }

  // হিস্টোরি রিড করা
  Future<List<Video>> getHistory() async {
    try {
      final file = await _historyFile;
      if (!await file.exists()) return [];

      final String content = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(content);

      return jsonData.map((data) {
        final videoId = data['id'] ?? '';
        final uploadDate = DateTime.tryParse(data['uploadDate'] ?? '') ?? DateTime.now();
        
        // ইউটিউব এক্সপ্লোড ৩.১.০ এর ভিডিও অবজেক্ট প্রফেশনাল উপায়ে রিক্রিয়েট করা
        return Video(
          VideoId(videoId),
          data['title'] ?? 'Unknown Title',
          data['author'] ?? 'Unknown Artist',
          ChannelId(data['channelId'] ?? ''),
          uploadDate, // uploadDate
          data['uploadDate'] ?? '', // uploadDateRaw
          uploadDate, // publishDate
          data['description'] ?? '', // description
          Duration(seconds: data['duration'] ?? 0), // duration
          ThumbnailSet(videoId), // thumbnails
          [], // keywords
          Engagement(0, 0, 0), // engagement
          false, // isLive
        );
      }).toList();
    } catch (e) {
      print('History Load Error: $e');
      return [];
    }
  }

  // হিস্টোরি ক্লিয়ার করা (প্রোফেশনাল অ্যাপে এটি জরুরি)
  Future<void> clearHistory() async {
    try {
      final file = await _historyFile;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('History Clear Error: $e');
    }
  }

  // AI Suggestion এর জন্য কি-ওয়ার্ড জেনারেট করা
  Future<String> getAISuggestionQuery() async {
    final history = await getHistory();
    if (history.isEmpty) return "Trending Music";

    // হিস্টোরি থেকে টপ ৩টি গানের অথর বা টাইটেল এর কিছু কি-ওয়ার্ড নেওয়া
    final authors = history.take(3).map((v) => v.author).toSet().join(" ");
    final titles = history.take(2).map((v) => v.title.split(' ').first).join(" ");
    
    return "$authors $titles hits remix";
  }
}
