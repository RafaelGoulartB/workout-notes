import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_voice_settings.dart';

/// Facade over the Android voice controller (`RunVoiceController.kt`), the
/// only engine that speaks run cues. It lives in the tracking foreground
/// service, so cues keep coming while the screen is off; Dart only pushes
/// settings, goal and plan, and asks for one-shot announcements.
class RunNativeVoiceService {
  RunNativeVoiceService._();
  static final RunNativeVoiceService instance = RunNativeVoiceService._();

  static const _methods = MethodChannel('workout_notes/run_voice/methods');

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  bool get isSupported => _isAndroid;

  /// Settings as the native controller reads them: the stored JSON plus the
  /// language already resolved against the app locale.
  static Map<String, dynamic> settingsPayload(RunVoiceSettings settings) => {
    ...settings.toJson(),
    'resolvedLanguage': settings.language
        .resolve(Intl.defaultLocale)
        .storageValue,
  };

  Future<void> syncSettings({
    required RunVoiceSettings settings,
    required Map<String, dynamic> goal,
    required bool intervalsOn,
    List<Map<String, dynamic>>? plan,
  }) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('syncSettings', {
        'settings': settingsPayload(settings),
        'goal': goal,
        'intervalsOn': intervalsOn,
        'plan': plan ?? const <Map<String, dynamic>>[],
      });
    } on MissingPluginException {
      // Desktop/tests — no native channel.
    } catch (_) {
      // Best-effort sync; ignore transient channel errors.
    }
  }

  Future<void> beginSession({
    required RunVoiceSettings settings,
    required Map<String, dynamic> goal,
    required bool intervalsOn,
    List<Map<String, dynamic>>? plan,
  }) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('beginSession', {
        'settings': settingsPayload(settings),
        'goal': goal,
        'intervalsOn': intervalsOn,
        'plan': plan ?? const <Map<String, dynamic>>[],
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

  /// Per-step results measured by the native controller during a structured
  /// session. Empty on other platforms or when no plan was running.
  Future<List<RunStepResult>> stepResults() async {
    if (!_isAndroid) return const [];
    try {
      final raw = await _methods.invokeMethod<List<Object?>>('stepResults');
      if (raw == null) return const [];
      return [
        for (final row in raw.whereType<Map>())
          RunStepResult.fromMap(Map<String, dynamic>.from(row)),
      ];
    } on MissingPluginException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Skips the current structured step / interval phase natively. Returns
  /// true when the native controller advanced (and spoke) the next step.
  Future<bool> skipStep() async {
    if (!_isAndroid) return false;
    try {
      return await _methods.invokeMethod<bool>('skipStep') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Speaks the settings-screen sample phrase with [settings] and their
  /// resolved language, without needing a run in progress.
  Future<bool> speakTest(RunVoiceSettings settings) =>
      _oneShot('speakTest', settings);

  /// The short "workout complete" acknowledgement after a free run stopped.
  Future<bool> speakWorkoutComplete(RunVoiceSettings settings) =>
      _oneShot('speakWorkoutComplete', settings);

  Future<bool> _oneShot(String method, RunVoiceSettings settings) async {
    if (!_isAndroid) return false;
    try {
      final result = await _methods.invokeMethod<bool>(method, {
        'settings': settingsPayload(settings),
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
