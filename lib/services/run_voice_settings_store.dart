import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/run_voice_settings.dart';

class RunVoiceSettingsStore {
  RunVoiceSettingsStore._();
  static final RunVoiceSettingsStore instance = RunVoiceSettingsStore._();

  RunVoiceSettings? _cache;

  Future<RunVoiceSettings> load() async {
    if (_cache != null) return _cache!;
    try {
      final raw =
          await DatabaseHelper.instance.getSetting(RunVoiceSettings.storageKey);
      if (raw == null || raw.isEmpty) {
        _cache = const RunVoiceSettings.defaults();
        return _cache!;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cache = RunVoiceSettings.fromJson(Map<String, dynamic>.from(decoded));
      } else {
        _cache = const RunVoiceSettings.defaults();
      }
    } catch (_) {
      _cache = const RunVoiceSettings.defaults();
    }
    return _cache!;
  }

  Future<void> save(RunVoiceSettings settings) async {
    _cache = settings;
    final encoded = jsonEncode(settings.toJson());
    await DatabaseHelper.instance.setSetting(
      RunVoiceSettings.storageKey,
      encoded,
    );
    // Mirror to SharedPreferences for native RunVoiceController which reads
    // without opening SQLite (survives engine death / START_STICKY restore).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(RunVoiceSettings.storageKey, encoded);
      await prefs.setString(
        'flutter.${RunVoiceSettings.storageKey}',
        encoded,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('RunVoiceSettingsStore mirror failed: $e');
    }
  }

  void invalidateCache() {
    _cache = null;
  }
}
