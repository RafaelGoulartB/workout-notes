import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/models/run_interval_snapshot.dart';
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
    Map<String, dynamic>? workout,
  }) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('syncSettings', {
        'settings': settingsPayload(settings),
        'goal': goal,
        'intervalsOn': intervalsOn,
        'plan': plan ?? const <Map<String, dynamic>>[],
        'workout': workout,
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
    Map<String, dynamic>? workout,
  }) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod('beginSession', {
        'settings': settingsPayload(settings),
        'goal': goal,
        'intervalsOn': intervalsOn,
        'plan': plan ?? const <Map<String, dynamic>>[],
        'workout': workout,
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

  // --- Treadmill -----------------------------------------------------------
  //
  // Indoor sessions have no GPS tracking service, so a small native service
  // (`RunIndoorVoiceService.kt`) keeps the coach and its clock running with
  // the screen off. Dart starts it, mirrors pause/resume, polls its step
  // snapshot for the record screen and collects the step results at the end.

  /// Starts the treadmill coach. [plan] must already be time-based
  /// (`RunPlanWorkout.treadmillStepsJson`).
  Future<bool> indoorStart({
    required RunVoiceSettings settings,
    required Map<String, dynamic> goal,
    List<Map<String, dynamic>>? plan,
    Map<String, dynamic>? workout,
  }) async {
    if (!_isAndroid) return false;
    try {
      return await _methods.invokeMethod<bool>('indoorStart', {
            'settings': settingsPayload(settings),
            'goal': goal,
            'plan': plan ?? const <Map<String, dynamic>>[],
            'workout': workout,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('RunNativeVoiceService.indoorStart failed: $error');
      return false;
    }
  }

  Future<void> indoorPause() => _indoorCall('indoorPause');

  Future<void> indoorResume() => _indoorCall('indoorResume');

  Future<void> _indoorCall(String method) async {
    if (!_isAndroid) return;
    try {
      await _methods.invokeMethod<void>(method);
    } on MissingPluginException {
      // Desktop/tests — no native channel.
    } catch (error) {
      // Best-effort: the Dart timer stays the source of truth for the clock.
      debugPrint('RunNativeVoiceService.$method failed: $error');
    }
  }

  /// Live structured-workout progress of the treadmill coach, or null.
  Future<RunIndoorVoiceState?> indoorState() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _methods.invokeMethod<Map<Object?, Object?>>(
        'indoorState',
      );
      if (raw == null) return null;
      return RunIndoorVoiceState.fromMap(Map<String, dynamic>.from(raw));
    } on MissingPluginException {
      return null;
    } catch (_) {
      // A missed poll is harmless: the next tick asks again.
      return null;
    }
  }

  /// Stops the treadmill coach and returns the per-step results.
  Future<List<RunStepResult>> indoorStop() async {
    if (!_isAndroid) return const [];
    try {
      final raw = await _methods.invokeMethod<List<Object?>>('indoorStop');
      if (raw == null) return const [];
      return [
        for (final row in raw.whereType<Map>())
          RunStepResult.fromMap(Map<String, dynamic>.from(row)),
      ];
    } on MissingPluginException {
      return const [];
    } catch (error) {
      debugPrint('RunNativeVoiceService.indoorStop failed: $error');
      return const [];
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

/// What the treadmill coach reports back to the record screen.
class RunIndoorVoiceState {
  final RunStepSnapshot? stepSnapshot;
  final RunIntervalSnapshot? intervalSnapshot;

  const RunIndoorVoiceState({this.stepSnapshot, this.intervalSnapshot});

  factory RunIndoorVoiceState.fromMap(Map<String, dynamic> map) {
    final step = map['step_snapshot'];
    final interval = map['interval_snapshot'];
    return RunIndoorVoiceState(
      stepSnapshot: step is Map
          ? RunStepSnapshot.fromMap(Map<String, dynamic>.from(step))
          : null,
      intervalSnapshot: interval is Map
          ? RunIntervalSnapshot.fromMap(Map<String, dynamic>.from(interval))
          : null,
    );
  }
}

/// Session set-up handed to the native treadmill coach.
class RunIndoorVoiceSetup {
  final RunVoiceSettings settings;
  final Map<String, dynamic> goal;
  final List<Map<String, dynamic>> plan;
  final Map<String, dynamic>? workout;

  const RunIndoorVoiceSetup({
    required this.settings,
    required this.goal,
    required this.plan,
    this.workout,
  });
}
