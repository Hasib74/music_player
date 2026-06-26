import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final _logger = Logger('AIService');
  
  // আপনার Gemini API Key এখানে বসাবেন
  final String _apiKey = "AIzaSyAbw9_BbG5pRavDI7oTYpUSvS9EEtm9mlk";

  GenerativeModel? _model;

  void _initModel() {
    if (_model != null) return;
    if (_apiKey != "") {
      _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
    }
  }

  Future<String> getSmartSearchQuery(String userPrompt) async {
    _initModel();
    if (_model == null) return userPrompt;

    try {
      final content = [Content.text("You are a music expert DJ. Convert the user's mood or request into 5 high-quality YouTube music search keywords. Output ONLY the keywords separated by spaces. User says: $userPrompt")];
      final response = await _model!.generateContent(content);
      
      final result = response.text;
      if (result != null && result.isNotEmpty) {
        _logger.info('Gemini Refined Query: $result');
        return result.trim();
      }
    } catch (e) {
      _logger.warning('Gemini Search Error: $e');
    }
    return userPrompt;
  }

  Future<String> getNextSongSuggestion(Video currentVideo, List<Video> history) async {
    _initModel();
    if (_model == null) return "${currentVideo.author} ${currentVideo.title} related music";

    try {
      final historyTitles = history.take(5).map((v) => v.title).join(", ");
      final prompt = """
        You are a highly intelligent Music Recommendation AI. 
        User is currently listening to: '${currentVideo.title}' by '${currentVideo.author}'.
        Their recent history includes: $historyTitles.

        Task: Generate 5 specific YouTube search keywords for the NEXT song the user should listen to.
        Rules:
        - Analyze the mood, genre, and artist of the current song.
        - DO NOT suggest the same song or artist if possible unless it's a perfect match for the vibe.
        - Aim for variety while maintaining the current vibe (e.g., if Lofi, suggest another Lofi or Chillhop track).
        - Output ONLY the keywords separated by spaces (e.g., 'Arijit Singh sad soulful hits').
      """;
      
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      
      final result = response.text;
      if (result != null && result.isNotEmpty) {
        _logger.info('Gemini Smart Suggestion: $result');
        return result.trim();
      }
    } catch (e) {
      _logger.warning('Gemini Suggestion Error: $e');
    }
    
    return "${currentVideo.author} related tracks";
  }

  Future<Map<String, String>> getSongContext(Video video) async {
    _initModel();
    if (_model == null) {
      return {
        "moodColor": "#FF5252", // Default RedAccent
        "djIntro": "Playing ${video.title} for you."
      };
    }

    try {
      final prompt = """
        Analyze the song: '${video.title}' by '${video.author}'.
        1. Assign a hex color code (e.g., #4CAF50) that represents its mood (Sad=Blue/Purple, Energetic=Red/Orange, Calm=Green/Blue).
        2. Write a one-sentence DJ introduction for this song (max 15 words) in a friendly tone.
        Output ONLY in this format: COLOR: #hexcolor | INTRO: your intro sentence.
      """;
      
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      final text = response.text ?? "";
      
      if (text.contains("|")) {
        final parts = text.split("|");
        final color = parts[0].replaceAll("COLOR:", "").trim();
        final intro = parts[1].replaceAll("INTRO:", "").trim();
        return {"moodColor": color, "djIntro": intro};
      }
    } catch (e) {
      _logger.warning('Gemini Context Error: $e');
    }

    return {
      "moodColor": "#FF5252",
      "djIntro": "Hope you enjoy this track!"
    };
  }

  Future<String> getPersonalizedMixQuery(List<Video> history) async {
    _initModel();
    if (_model == null) return "Trending Music Discovery 2024";

    try {
      final historyInfo = history.take(15).map((v) => "${v.title} by ${v.author}").join(", ");
      final prompt = """
        Based on my music taste (History: $historyInfo), 
        generate a single highly effective YouTube search query to discover 10-15 NEW and RELATED songs 
        I haven't heard yet. The query should be broad enough to return a list but specific to my genre/style.
        Output ONLY the search query.
      """;
      
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      return response.text?.trim() ?? "Personalized music discovery mix";
    } catch (e) {
      return "Personalized music hits";
    }
  }
}
