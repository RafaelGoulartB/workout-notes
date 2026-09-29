import 'package:workout_notes/models/run_split.dart';

/// How a split compares with the run's average pace.
enum RunSplitTone { faster, even, slower, unknown }

/// One presentable split row: the split plus its delta vs the run average,
/// tone, bar length and (optionally) the climb of that kilometre.
class RunSplitRow {
  final RunSplit split;

  /// Split pace minus the run average (negative = faster). Null without pace.
  final double? deltaSecPerKm;
  final RunSplitTone tone;
  final bool isFastest;

  /// 0..1, longer = faster.
  final double barFraction;
  final double? elevationGainMeters;

  const RunSplitRow({
    required this.split,
    required this.deltaSecPerKm,
    required this.tone,
    required this.isFastest,
    required this.barFraction,
    required this.elevationGainMeters,
  });
}

abstract final class RunSplitAnalytics {
  /// Differences smaller than this (sec/km) are shown as "even".
  static const double evenToleranceSecPerKm = 3;

  /// Shortest bar, so the slowest split is still visible.
  static const double minBarFraction = 0.28;

  /// Pace of the run: [averagePaceSecPerKm] when valid, otherwise the
  /// time-weighted mean of the completed splits.
  static double? referencePace(
    List<RunSplit> splits,
    double? averagePaceSecPerKm,
  ) {
    if (averagePaceSecPerKm != null &&
        averagePaceSecPerKm.isFinite &&
        averagePaceSecPerKm > 0) {
      return averagePaceSecPerKm;
    }
    var meters = 0.0;
    var seconds = 0;
    for (final split in splits) {
      if (split.isPartial || split.distanceMeters <= 0) continue;
      meters += split.distanceMeters;
      seconds += split.durationSeconds;
    }
    if (meters < 1 || seconds <= 0) return null;
    return seconds / (meters / 1000);
  }

  static RunSplitTone toneFor(double? delta) {
    if (delta == null || !delta.isFinite) return RunSplitTone.unknown;
    if (delta.abs() < evenToleranceSecPerKm) return RunSplitTone.even;
    return delta < 0 ? RunSplitTone.faster : RunSplitTone.slower;
  }

  static bool _valid(double? pace) => pace != null && pace.isFinite && pace > 0;

  static List<RunSplitRow> build(
    List<RunSplit> splits, {
    double? averagePaceSecPerKm,
    Map<int, double> elevationGainByKm = const {},
  }) {
    if (splits.isEmpty) return const [];
    final reference = referencePace(splits, averagePaceSecPerKm);

    double? fastest;
    double? slowest;
    var completed = 0;
    for (final split in splits) {
      if (split.isPartial) continue;
      completed++;
      final pace = split.paceSecPerKm;
      if (!_valid(pace)) continue;
      if (fastest == null || pace! < fastest) fastest = pace;
      if (slowest == null || pace! > slowest) slowest = pace;
    }

    return [
      for (final split in splits)
        () {
          final pace = split.paceSecPerKm;
          final valid = _valid(pace);
          final delta = valid && reference != null ? pace! - reference : null;
          return RunSplitRow(
            split: split,
            deltaSecPerKm: delta,
            tone: toneFor(delta),
            // A "fastest" badge only means something with 2+ full splits.
            isFastest:
                completed >= 2 &&
                !split.isPartial &&
                valid &&
                fastest != null &&
                pace == fastest,
            barFraction: _barFraction(pace, fastest, slowest),
            elevationGainMeters: elevationGainByKm[split.km],
          );
        }(),
    ];
  }

  /// Pace spread (s/km) that maps to the full bar range. A narrower real
  /// spread is widened to this, so a split only 7 s slower than the fastest
  /// keeps a nearly full bar instead of collapsing to the minimum.
  static const double minBarSpreadSecPerKm = 60;

  /// Longer bar = faster. Missing pace gets a short stub.
  static double _barFraction(double? pace, double? fastest, double? slowest) {
    if (!_valid(pace)) return 0.15;
    if (fastest == null || slowest == null) return 0.7;
    if ((slowest - fastest).abs() < 1) return 1.0;
    final spread = (slowest - fastest) < minBarSpreadSecPerKm
        ? minBarSpreadSecPerKm
        : slowest - fastest;
    final t = (1 - (pace! - fastest) / spread).clamp(0.0, 1.0);
    return minBarFraction + (1 - minBarFraction) * t;
  }
}
