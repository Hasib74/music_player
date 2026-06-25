import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:logging/logging.dart';
import 'src/screens/youtube_player_screen.dart';
import 'src/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Logger Initialization
  Logger.root.level = Level.ALL; 
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.time} [${record.loggerName}] ${record.level.name}: ${record.message}');
    if (record.error != null) debugPrint('Error: ${record.error}');
  });

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.youtube_player.channel.audio',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );
  await NotificationService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.redAccent,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const YoutubePlayerScreen(),
    );
  }
}
