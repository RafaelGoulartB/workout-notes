import 'sleep_monitor_segment.dart';
import 'sleep_monitor_session.dart';

/// Technical quality indicators for deciding whether a monitored night is
/// usable for product testing. This does not assess sleep or medical quality.
class SleepMonitorDiagnostics {
  final int sessionDurationSeconds;
  final int capturedDurationSeconds;
  final int segmentCount;
  final int quietSeconds;
  final int noisySeconds;
  final int invalidSeconds;
  final double timelineCoverage;
  final double signalCoverage;
  final double? averageNoiseScore;
  final double? peakNoiseScore;
  final bool completedSuccessfully;

  const SleepMonitorDiagnostics({
    required this.sessionDurationSeconds,
    required this.capturedDurationSeconds,
    required this.segmentCount,
    required this.quietSeconds,
    required this.noisySeconds,
    required this.invalidSeconds,
    required this.timelineCoverage,
    required this.signalCoverage,
    required this.averageNoiseScore,
    required this.peakNoiseScore,
    required this.completedSuccessfully,
  });

  bool get hasData => segmentCount > 0 && capturedDurationSeconds > 0;

  /// A field-test night needs enough duration and coverage to reveal Android
  /// background-capture problems before advancing the MVP.
  bool get isAcceptableForNextPhase =>
      completedSuccessfully &&
      sessionDurationSeconds >= const Duration(hours: 4).inSeconds &&
      timelineCoverage >= 0.90 &&
      signalCoverage >= 0.80 &&
      invalidSeconds <= capturedDurationSeconds * 0.20;

  factory SleepMonitorDiagnostics.fromSession(
    SleepMonitorSession session,
    List<SleepMonitorSegment> segments,
  ) {
    final end = session.endedAt ?? session.startedAt;
    final sessionSeconds = end
        .difference(session.startedAt)
        .inSeconds
        .clamp(0, 16 * 60 * 60);
    var capturedSeconds = 0;
    var quietSeconds = 0;
    var noisySeconds = 0;
    var invalidSeconds = 0;
    var weightedSignal = 0.0;
    final noiseScores = <double>[];

    for (final segment in segments) {
      final duration = segment.durationSeconds.clamp(0, 60 * 60);
      capturedSeconds += duration;
      weightedSignal += segment.validFraction.clamp(0.0, 1.0) * duration;
      if (segment.isQuiet) quietSeconds += duration;
      if (segment.isNoise) noisySeconds += duration;
      if (segment.isInvalid) invalidSeconds += duration;
      final score = segment.noiseScore;
      if (score != null) noiseScores.add(score);
    }

    final timelineCoverage = sessionSeconds <= 0
        ? 0.0
        : (capturedSeconds / sessionSeconds).clamp(0.0, 1.0);
    final signalCoverage = capturedSeconds <= 0
        ? 0.0
        : (weightedSignal / capturedSeconds).clamp(0.0, 1.0);
    final averageNoise = noiseScores.isEmpty
        ? null
        : noiseScores.reduce((a, b) => a + b) / noiseScores.length;
    final peakNoise = noiseScores.isEmpty
        ? null
        : noiseScores.reduce((a, b) => a > b ? a : b);

    return SleepMonitorDiagnostics(
      sessionDurationSeconds: sessionSeconds,
      capturedDurationSeconds: capturedSeconds,
      segmentCount: segments.length,
      quietSeconds: quietSeconds,
      noisySeconds: noisySeconds,
      invalidSeconds: invalidSeconds,
      timelineCoverage: timelineCoverage,
      signalCoverage: signalCoverage,
      averageNoiseScore: averageNoise,
      peakNoiseScore: peakNoise,
      completedSuccessfully: const {
        SleepMonitorSession.completed,
        SleepMonitorSession.interrupted,
      }.contains(session.status),
    );
  }
}
