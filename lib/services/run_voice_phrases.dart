import 'package:workout_notes/models/run_voice_settings.dart';

/// English-only spoken phrases for the run voice coach.
class RunVoicePhrases {
  const RunVoicePhrases._();

  static String distanceMilestone({
    required int km,
    required int durationSeconds,
    required double? avgPaceSecPerKm,
  }) {
    final buf = StringBuffer('$km ${_kilometersWord(km)}. ');
    buf.write('Time ${_durationSpeech(durationSeconds)}.');
    if (avgPaceSecPerKm != null &&
        avgPaceSecPerKm > 0 &&
        avgPaceSecPerKm.isFinite) {
      buf.write(
        ' Average pace ${_paceSpeech(avgPaceSecPerKm)} per kilometer.',
      );
    }
    return buf.toString();
  }

  static String splitComplete({
    required int km,
    required double? paceSecPerKm,
  }) {
    final pace = paceSecPerKm != null &&
            paceSecPerKm > 0 &&
            paceSecPerKm.isFinite
        ? ' Pace ${_paceSpeech(paceSecPerKm)}.'
        : '';
    return 'Kilometer $km.$pace';
  }

  static String paceTooFast() => 'Pace too fast.';

  static String paceTooSlow() => 'Pace too slow.';

  static String weakGps() => 'Weak GPS signal.';

  static String gpsRestored() => 'GPS signal restored.';

  static String workIntervalStart({
    required int index,
    required int total,
  }) =>
      'Work interval $index of $total. Go.';

  static String restIntervalStart({
    required RunIntervalMetric metric,
    required int value,
  }) {
    if (metric == RunIntervalMetric.time) {
      return 'Rest. ${_durationSpeech(value)}.';
    }
    return 'Rest. ${_distanceSpeech(value)}.';
  }

  static String intervalsComplete() => 'Intervals complete.';

  static String timeRemaining(int seconds) =>
      '${_durationSpeech(seconds)} remaining.';

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
    return '$minutes minutes $seconds seconds';
  }

  static String _distanceSpeech(int meters) {
    if (meters >= 1000 && meters % 1000 == 0) {
      final km = meters ~/ 1000;
      return '$km ${_kilometersWord(km)}';
    }
    return '$meters meters';
  }
}
