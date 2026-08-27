import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin locale-aware TTS wrapper for the run module.
class RunTtsService {
  RunTtsService._();
  static final RunTtsService instance = RunTtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;
  String _languageTag = 'en-US';

  bool get isSpeaking => _speaking;

  Future<void> ensureReady({String? languageTag}) async {
    final requestedLanguage = languageTag ?? _languageTag;
    if (_ready && requestedLanguage == _languageTag) return;
    try {
      if (_ready && _speaking) {
        await _tts.stop();
        _speaking = false;
      }
      await _tts.setLanguage(requestedLanguage);
      _languageTag = requestedLanguage;
      if (_ready) return;
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      // Prefer speaker output on emulator / without headset.
      try {
        await _tts.setAudioAttributesForNavigation();
      } catch (_) {}
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
      _ready = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RunTtsService init failed: $error');
      }
    }
  }

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await ensureReady();
    try {
      if (_speaking) {
        await _tts.stop();
        _speaking = false;
      }
      await _tts.speak(trimmed);
    } catch (error) {
      _speaking = false;
      if (kDebugMode) {
        debugPrint('RunTtsService speak failed: $error');
      }
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
  }
}
