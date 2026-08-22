import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';

/// English-only, intentionally brief spoken phrases for the run voice coach.
///
/// A runner may be listening to music or a podcast. Every phrase should convey
/// one actionable idea and normally finish in under three seconds.
class RunVoicePhrases {
  const RunVoicePhrases._();

  static String distanceMilestone({
    required int km,
    required int durationSeconds,
    required double? avgPaceSecPerKm,
  }) {
    final buf = StringBuffer('$km ${_kilometersWord(km)}.');
    if (avgPaceSecPerKm != null &&
        avgPaceSecPerKm > 0 &&
        avgPaceSecPerKm.isFinite) {
      buf.write(' Average ${_paceSpeech(avgPaceSecPerKm)}.');
    }
    return buf.toString();
  }

  static String splitComplete({
    required int km,
    required double? paceSecPerKm,
  }) {
    final pace =
        paceSecPerKm != null && paceSecPerKm > 0 && paceSecPerKm.isFinite
        ? ' ${_paceSpeech(paceSecPerKm)}.'
        : '';
    return 'Kilometer $km.$pace';
  }

  static String splitSummary({
    required int km,
    required double? splitPaceSecPerKm,
    required double? avgPaceSecPerKm,
  }) {
    final split = _validPace(splitPaceSecPerKm)
        ? ' ${_paceSpeech(splitPaceSecPerKm!)}.'
        : '';
    final average = _validPace(avgPaceSecPerKm)
        ? ' Average ${_paceSpeech(avgPaceSecPerKm!)}.'
        : '';
    return 'Kilometer $km.$split$average';
  }

  static String paceTooFast() => 'Ease off.';

  static String paceTooSlow() => 'Pick it up.';

  static String paceOnTarget() => 'Pace on target.';

  static String weakGps() => 'Weak GPS signal.';

  static String gpsRestored() => 'GPS signal restored.';

  static String workIntervalStart({required int index, required int total}) =>
      'Rep $index of $total. Go.';

  static String restIntervalStart({
    required RunIntervalMetric metric,
    required int value,
  }) {
    if (metric == RunIntervalMetric.time) {
      return 'Recover. ${_durationSpeech(value)}.';
    }
    return 'Recover. ${_distanceSpeech(value)}.';
  }

  static String intervalsComplete() => 'Intervals complete.';

  static String timeRemaining(int seconds) => '$seconds seconds.';

  static String distanceRemaining(int meters) => '$meters meters.';

  // ---- Structured plan sessions (RunWorkoutStepEngine) ----
  // Mirrors RunVoicePhrases.kt so the Dart and native cues read the same.

  static String stepStart({
    required RunStepRole role,
    required int repIndex,
    required int repTotal,
    required RunIntervalMetric metric,
    required int value,
    double? targetPaceSecPerKm,
  }) {
    final amount = metric == RunIntervalMetric.time
        ? _durationSpeech(value)
        : _distanceSpeech(value);
    final head = switch (role) {
      RunStepRole.warmup => 'Warm up. $amount.',
      RunStepRole.cooldown => 'Cool down. $amount.',
      RunStepRole.recovery => 'Recover. $amount.',
      RunStepRole.steady => 'Steady. $amount.',
      RunStepRole.work =>
        repTotal > 1
            ? 'Rep $repIndex of $repTotal. $amount.'
            : 'Effort. $amount.',
    };
    if (role.isEffort &&
        targetPaceSecPerKm != null &&
        targetPaceSecPerKm > 0 &&
        targetPaceSecPerKm.isFinite) {
      return '$head Target ${_paceSpeech(targetPaceSecPerKm)}.';
    }
    return head;
  }

  static String stepPaceTooSlow(double? paceSecPerKm) {
    if (paceSecPerKm == null || paceSecPerKm <= 0 || !paceSecPerKm.isFinite) {
      return 'Pick it up.';
    }
    return 'Pick it up. ${_paceSpeech(paceSecPerKm)}.';
  }

  static String stepPaceTooFast(double? paceSecPerKm) {
    if (paceSecPerKm == null || paceSecPerKm <= 0 || !paceSecPerKm.isFinite) {
      return 'Ease off.';
    }
    return 'Ease off. ${_paceSpeech(paceSecPerKm)}.';
  }

  static String workoutComplete() => 'Workout complete.';

  static String goalComplete({
    required RunIntervalMetric metric,
    required int value,
  }) {
    if (metric == RunIntervalMetric.time) {
      return 'Goal complete. ${_durationSpeech(value)}.';
    }
    return 'Goal complete. ${_distanceSpeech(value)}.';
  }

  static String goalRemaining({
    required RunIntervalMetric metric,
    required int value,
  }) => metric == RunIntervalMetric.time
      ? '${_durationSpeech(value)} left.'
      : '${_distanceSpeech(value)} left.';

  static String paused() => 'Paused.';

  static String resumed() => 'Resumed.';

  static String _kilometersWord(int km) => km == 1 ? 'kilometer' : 'kilometers';

  static String _durationSpeech(int totalSeconds) {
    final safe = totalSeconds.clamp(0, 24 * 3600);
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final seconds = safe % 60;
    final parts = <String>[];
    if (hours > 0) {
      parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
    }
    if (minutes > 0 || hours > 0) {
      parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
    }
    if (hours == 0) {
      parts.add('$seconds ${seconds == 1 ? 'second' : 'seconds'}');
    }
    if (parts.isEmpty) return '0 seconds';
    return parts.join(' ');
  }

  static String _paceSpeech(double secPerKm) {
    final total = secPerKm.round().clamp(0, 99 * 60 + 59);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes ${seconds.toString().padLeft(2, '0')} per kilometer';
  }

  static bool _validPace(double? pace) =>
      pace != null && pace > 0 && pace.isFinite;

  static String _distanceSpeech(int meters) {
    if (meters >= 1000 && meters % 1000 == 0) {
      final km = meters ~/ 1000;
      return '$km ${_kilometersWord(km)}';
    }
    return '$meters meters';
  }
}
