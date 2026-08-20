import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RunNativeVoiceService {
  RunNativeVoiceService._();
  static final RunNativeVoiceService instance = RunNativeVoiceService._();

  static const _methods = MethodChannel('workout_notes/run_voice/methods');

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isSupported => _isAndroid;

  Future<void> syncSettings({
    required Map<String, dynamic> settings,
    required Map<String, dynamic> goal,
    required bool intervalsOn,
    bool bypassHeadphonesGate = false,
  }) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('syncSettings', {
        'settings': settings,
        'goal': goal,
        'intervalsOn': intervalsOn,
        'bypassHeadphonesGate': bypassHeadphonesGate,
      });
    } on MissingPluginException {
      // Desktop/tests — no native channel.
    } catch (_) {
      // Best-effort sync; ignore transient channel errors.
    }
  }

  Future<void> beginSession({
    required Map<String, dynamic> settings,
    required Map<String, dynamic> goal,
    required bool intervalsOn,
    bool bypassHeadphonesGate = false,
  }) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('beginSession', {
        'settings': settings,
        'goal': goal,
        'intervalsOn': intervalsOn,
        'bypassHeadphonesGate': bypassHeadphonesGate,
      });
    } on MissingPluginException {
      // Desktop/tests
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> endSession() async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('endSession');
    } on MissingPluginException {
      // Desktop/tests
    } catch (_) {
      // Ignore
    }
  }

  Future<bool> speakTest() async {
    if (!_isAndroid) return false;
    try {
      final result = await _methods.invokeMethod<bool>('speakTest');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
