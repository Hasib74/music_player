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
    if (_apiKey != "AIzaSyAbw9_BbG5pRavDI7oTYpUSvS9EEtm9mlk") {
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
        I am currently listening to: '${currentVideo.title}' by '${currentVideo.author}'.
        My recent history: $historyTitles.
        As a music expert, suggest 5 highly relevant YouTube search keywords for the NEXT song I should listen to. 
        Focus on similar genre, mood, or artist.
        Output ONLY the keywords separated by spaces.
      """;
      
      final content = [Content.text(prompt)];
      final response = await _model!.generateContent(content);
      
      final result = response.text;
      if (result != null && result.isNotEmpty) {
        _logger.info('Gemini Next Suggestion Query: $result');
        return result.trim();
      }
    } catch (e) {
      _logger.warning('Gemini Suggestion Error: $e');
    }
    
    return "${currentVideo.author} related hits";
  }
}
