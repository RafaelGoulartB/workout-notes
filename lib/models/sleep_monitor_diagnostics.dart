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
  final int digitalSilenceSeconds;
  final double timelineCoverage;
  final double signalCoverage;
  final double digitalSilenceFraction;
  final double? averageNoiseScore;
  final double? peakNoiseScore;
  final bool completedSuccessfully;
  final List<String> inferenceBlockers;

  const SleepMonitorDiagnostics({
    required this.sessionDurationSeconds,
    required this.capturedDurationSeconds,
    required this.segmentCount,
    required this.quietSeconds,
    required this.noisySeconds,
    required this.invalidSeconds,
    required this.digitalSilenceSeconds,
    required this.timelineCoverage,
    required this.signalCoverage,
    required this.digitalSilenceFraction,
    required this.averageNoiseScore,
    required this.peakNoiseScore,
    required this.completedSuccessfully,
    required this.inferenceBlockers,
  });

  bool get hasData => segmentCount > 0 && capturedDurationSeconds > 0;

  /// A field-test night needs enough duration and coverage to reveal Android
  /// background-capture problems before advancing the MVP.
  bool get isAcceptableForNextPhase => inferenceBlockers.isEmpty;

  bool get isSuitableForInference => inferenceBlockers.isEmpty;

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
    var digitalSilenceSeconds = 0;
    var weightedSignal = 0.0;
    final noiseScores = <double>[];

    for (final segment in segments) {
      final duration = segment.durationSeconds.clamp(0, 60 * 60);
      capturedSeconds += duration;
      weightedSignal += segment.validFraction.clamp(0.0, 1.0) * duration;
      if (segment.isQuiet) quietSeconds += duration;
      if (segment.isNoise) noisySeconds += duration;
      if (segment.isInvalid) invalidSeconds += duration;
      if (_isDigitalSilence(segment)) digitalSilenceSeconds += duration;
      final score = segment.noiseScore;
      if (score != null) noiseScores.add(score);
    }

    final timelineCoverage = sessionSeconds <= 0
        ? 0.0
        : (capturedSeconds / sessionSeconds).clamp(0.0, 1.0);
    final signalCoverage = capturedSeconds <= 0
        ? 0.0
        : (weightedSignal / capturedSeconds).clamp(0.0, 1.0);
    final digitalSilenceFraction = capturedSeconds <= 0
        ? 0.0
        : (digitalSilenceSeconds / capturedSeconds).clamp(0.0, 1.0);
    final averageNoise = noiseScores.isEmpty
        ? null
        : noiseScores.reduce((a, b) => a + b) / noiseScores.length;
    final peakNoise = noiseScores.isEmpty
        ? null
        : noiseScores.reduce((a, b) => a > b ? a : b);

    final completedSuccessfully = const {
      SleepMonitorSession.completed,
      SleepMonitorSession.interrupted,
    }.contains(session.status);
    final blockers = <String>[
      if (!completedSuccessfully ||
          sessionSeconds < const Duration(hours: 4).inSeconds)
        'too_short',
      if (timelineCoverage < 0.90) 'low_timeline_coverage',
      if (signalCoverage < 0.80) 'low_signal_coverage',
      if (capturedSeconds <= 0 || invalidSeconds > capturedSeconds * 0.20)
        'too_many_invalid_segments',
      if (digitalSilenceFraction > 0.20) 'digital_silence',
    ];

    return SleepMonitorDiagnostics(
      sessionDurationSeconds: sessionSeconds,
      capturedDurationSeconds: capturedSeconds,
      segmentCount: segments.length,
      quietSeconds: quietSeconds,
      noisySeconds: noisySeconds,
      invalidSeconds: invalidSeconds,
      digitalSilenceSeconds: digitalSilenceSeconds,
      timelineCoverage: timelineCoverage,
      signalCoverage: signalCoverage,
      digitalSilenceFraction: digitalSilenceFraction,
      averageNoiseScore: averageNoise,
      peakNoiseScore: peakNoise,
      completedSuccessfully: completedSuccessfully,
      inferenceBlockers: List.unmodifiable(blockers),
    );
  }

  static bool _isDigitalSilence(SleepMonitorSegment segment) {
    final rms = segment.audioRmsDbfs;
    final peak = segment.audioPeakDbfs;
    return rms != null && peak != null && rms <= -119 && peak <= -119;
  }
}
