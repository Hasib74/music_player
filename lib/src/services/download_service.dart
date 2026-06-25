import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:logging/logging.dart';
//import 'package:file_picker/file_picker.dart';
import 'notification_service.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  final _logger = Logger('DownloadService');
  
  factory DownloadService() => _instance;
  DownloadService._internal() {
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 5;
    _dio.interceptors.add(PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: false, 
      responseHeader: false,
      error: true,
      compact: true,
      maxWidth: 90,
    ));
  }

  final Dio _dio = Dio();
  final String _apiBase = 'http://192.168.0.103:8000/api/download';

  String getApiUrl(String videoUrl, {String formatId = '18', bool stream = false}) {
    final url = '$_apiBase?url=$videoUrl&format_id=$formatId${stream ? '&stream=true' : ''}';
    _logger.info('Generated API URL: $url');
    return url;
  }

  Future<String> getCacheFilePath(String videoId) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'audio_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return p.join(cacheDir.path, '$videoId.mp4');
  }

  Future<void> clearAllCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory(p.join(tempDir.path, 'audio_cache'));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        _logger.info('Previous cache cleared successfully');
      }
      await cacheDir.create(recursive: true);
    } catch (e) {
      _logger.warning('Cache clear error: $e');
    }
  }

  // ফোল্ডার সিলেক্ট করে ডাউনলোড করা
/*  Future<void> downloadWithPicker(String title, String apiUrl) async {
    try {
      // ১. ইউজারকে ফোল্ডার সিলেক্ট করতে বলা
      String? selectedDirectory = await FilePicker.getDirectoryPath();

      if (selectedDirectory == null) {
        _logger.info('User cancelled directory selection');
        return;
      }

      // ২. ফাইল পাথ তৈরি করা
      final fileName = '${title.replaceAll(RegExp(r'[^\w\s]+'), '')}.mp4';
      final filePath = p.join(selectedDirectory, fileName);

      final NotificationService notificationService = NotificationService();

      _logger.info('Starting download: $title to $filePath');

      // ৩. ব্যাকগ্রাউন্ডে ডাউনলোড শুরু
      await _dio.download(
        apiUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            int progress = (received / total * 100).toInt();
            notificationService.showDownloadNotification(title, progress);
          }
        },
      );

      _logger.info('Download complete: $filePath');
    } catch (e) {
      _logger.severe('Download with picker error: $e');
    }
  }*/

  Future<void> downloadToStorage(String title, String apiUrl) async {
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      final fileName = '${title.replaceAll(RegExp(r'[^\w\s]+'), '')}.mp4';
      final filePath = p.join(downloadsDir.path, fileName);

      final NotificationService notificationService = NotificationService();

      _logger.info('Starting download: $title to $filePath');
      await _dio.download(
        apiUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            notificationService.showDownloadNotification(title, (received / total * 100).toInt());
          }
        },
      );
      
      _logger.info('Download complete: $filePath');
    } catch (e) {
      _logger.severe('Storage download error: $e');
    }
  }
}
