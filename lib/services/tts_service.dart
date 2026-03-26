import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInit = false;

  TtsService._internal();

  /// Initialize TTS engine with preferred language and voice profiles.
  Future<void> initTts() async {
    if (_isInit) return;

    try {
      if (!kIsWeb) {
        // Set Audio Session category for iOS/Android if background playback is needed.
        await _flutterTts.setSharedInstance(true);
        await _flutterTts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            [
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
              IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            ]);
      }

      await _flutterTts.setLanguage("tr-TR");
      await _flutterTts.setSpeechRate(0.5); // Normal speed
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInit = true;
      debugPrint("✅ TtsService initialized successfully.");
    } catch (e) {
      debugPrint("❌ Failed to initialize TtsService: $e");
    }
  }

  /// Speaks the provided text via the OS TTS engine.
  Future<void> speak(String text) async {
    if (!_isInit) await initTts();

    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  /// Stops current speech.
  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
