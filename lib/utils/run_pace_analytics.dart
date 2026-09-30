import 'dart:math' as math;

import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// One pace sample along the run, keyed by cumulative distance.
class RunPaceSample {
  final double distanceMeters;
  final double paceSecPerKm;

  const RunPaceSample({
    required this.distanceMeters,
    required this.paceSecPerKm,
  });
}

/// Cumulative distance and timestamp at every GPS point, computed once and
/// shared by the analytics that walk a track (pace curve, splits, best
/// efforts, route geometry).
class RunTrackProfile {
  /// Cumulative metres at each point, starting at 0. Hops under
  /// [RunPaceAnalytics.minStepMeters] count as standing still.
  final List<double> cumulativeMeters;

  /// Timestamp of each point; same length as [cumulativeMeters].
  final List<DateTime> times;

  const RunTrackProfile._(this.cumulativeMeters, this.times);

  factory RunTrackProfile.fromPoints(List<RunTrackPoint> points) {
    if (points.isEmpty) return const RunTrackProfile._([], []);
    final cumulative = <double>[0.0];
    final times = <DateTime>[points.first.recordedAt];
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final step = RunPaceAnalytics.haversineMeters(
        lat1: prev.lat,
        lng1: prev.lng,
        lat2: cur.lat,
        lng2: cur.lng,
      );
      final accepted = step >= RunPaceAnalytics.minStepMeters ? step : 0.0;
      cumulative.add(cumulative.last + accepted);
      times.add(cur.recordedAt);
    }
    return RunTrackProfile._(cumulative, times);
  }

  int get length => cumulativeMeters.length;

  double get totalMeters =>
      cumulativeMeters.isEmpty ? 0 : cumulativeMeters.last;
}

/// Pace series + km splits derived from GPS track points.
class RunPaceAnalytics {
  final List<RunPaceSample> samples;
  final List<RunSplit> splits;
  final double? avgPaceSecPerKm;
  final double? bestSplitPaceSecPerKm;

  const RunPaceAnalytics({
    required this.samples,
    required this.splits,
    required this.avgPaceSecPerKm,
    required this.bestSplitPaceSecPerKm,
  });

  bool get hasChart => samples.length >= 2;
  bool get hasSplits => splits.isNotEmpty;

  static const double earthRadiusMeters = 6371000.0;

  /// Rolling window used to smooth GPS jitter into a readable pace curve.
  static const double defaultWindowMeters = 80.0;

  /// Max samples retained for charting long activities.
  static const int maxChartSamples = 180;

  /// Ignore tiny GPS hops when accumulating distance.
  static const double minStepMeters = 1.0;

  /// Drop instantaneous pace outside this band (sec/km).
  static const double minPaceSecPerKm = 60.0; // 1:00 /km
  static const double maxPaceSecPerKm = 1800.0; // 30:00 /km

  static double haversineMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double? paceSecPerKm(double distanceMeters, int movingTimeSeconds) {
    final pace = RunFormatters.paceOrNull(distanceMeters, movingTimeSeconds);
    if (pace == null || !pace.isFinite || pace <= 0) return null;
    return pace;
  }

  /// Pace of the fastest completed km split, without building the chart
  /// samples. Cheap companion for callers that already hold a [profile].
  static double? bestSplitPaceOf(RunTrackProfile profile) {
    if (profile.length < 2) return null;
    return _bestCompletedPace(
      _buildSplits(cumDist: profile.cumulativeMeters, times: profile.times),
    );
  }

  /// Builds chart samples and km splits from ordered track points. Pass a
  /// [profile] already computed for the same [points] to skip that walk.
  static RunPaceAnalytics fromTrackPoints(
    List<RunTrackPoint> points, {
    double? activityAvgPaceSecPerKm,
    double windowMeters = defaultWindowMeters,
    RunTrackProfile? profile,
  }) {
    if (points.length < 2) {
      return RunPaceAnalytics(
        samples: const [],
        splits: const [],
        avgPaceSecPerKm: activityAvgPaceSecPerKm,
        bestSplitPaceSecPerKm: null,
      );
    }

    final track = profile ?? RunTrackProfile.fromPoints(points);
    final cumDist = track.cumulativeMeters;
    final times = track.times;

    final totalDistance = cumDist.last;
    final samples = _buildSamples(
      cumDist: cumDist,
      times: times,
      windowMeters: windowMeters,
    );
    final splits = _buildSplits(cumDist: cumDist, times: times);
    final best = _bestCompletedPace(splits);

    final avg =
        activityAvgPaceSecPerKm ??
        paceSecPerKm(
          totalDistance,
          times.last.difference(times.first).inSeconds,
        );

    return RunPaceAnalytics(
      samples: samples,
      splits: splits,
      avgPaceSecPerKm: avg,
      bestSplitPaceSecPerKm: best,
    );
  }

  /// Below this speed a step counts as standing still (about 20:50 /km).
  static const double minMovingSpeedMetersPerSecond = 0.8;

  /// Samples slower / faster than this multiple of the median are GPS noise.
  static const double outlierSlowFactor = 2.5;
  static const double outlierFastFactor = 0.4;

  static List<RunPaceSample> _buildSamples({
    required List<double> cumDist,
    required List<DateTime> times,
    required double windowMeters,
  }) {
    // Prefix sums of moving time / moving distance. Steps where the runner
    // stood still (traffic light, tying a shoe) or GPS paused are left out,
    // so a stop never turns into a 12:00 /km canyon in the curve.
    final movingSeconds = <double>[0.0];
    final movingMeters = <double>[0.0];
    for (var i = 1; i < cumDist.length; i++) {
      final dd = cumDist[i] - cumDist[i - 1];
      final dt = times[i].difference(times[i - 1]).inMilliseconds / 1000.0;
      final moving = dt > 0 && dd / dt >= minMovingSpeedMetersPerSecond;
      movingSeconds.add(movingSeconds.last + (moving ? dt : 0.0));
      movingMeters.add(movingMeters.last + (moving ? dd : 0.0));
    }

    final raw = <RunPaceSample>[];
    var windowStart = 0;

    for (var i = 1; i < cumDist.length; i++) {
      while (windowStart < i - 1 &&
          cumDist[i] - cumDist[windowStart + 1] >= windowMeters) {
        windowStart++;
      }

      final dd = movingMeters[i] - movingMeters[windowStart];
      if (dd < windowMeters * 0.6) continue;
      final dt = movingSeconds[i] - movingSeconds[windowStart];
      if (dt <= 0) continue;

      final pace = RunFormatters.paceSecondsPerKm(dd, dt);
      if (!pace.isFinite) continue;
      if (pace < minPaceSecPerKm || pace > maxPaceSecPerKm) continue;

      raw.add(RunPaceSample(distanceMeters: cumDist[i], paceSecPerKm: pace));
    }

    final smoothed = smoothSamples(removeOutliers(raw));
    return _downsample(smoothed, maxChartSamples);
  }

  /// Drops samples that are wildly off the run's median pace (GPS glitches).
  static List<RunPaceSample> removeOutliers(List<RunPaceSample> samples) {
    if (samples.length < 5) return samples;
    final median = _median([for (final s in samples) s.paceSecPerKm]);
    final kept = [
      for (final s in samples)
        if (s.paceSecPerKm <= median * outlierSlowFactor &&
            s.paceSecPerKm >= median * outlierFastFactor)
          s,
    ];
    return kept.length < 2 ? samples : kept;
  }

  /// Rolling median (kills short spikes) followed by a light rolling mean
  /// (rounds the curve). Distances are untouched.
  static List<RunPaceSample> smoothSamples(
    List<RunPaceSample> samples, {
    int medianWindow = 5,
    int meanWindow = 3,
  }) {
    if (samples.length < 3) return samples;
    final paces = [for (final s in samples) s.paceSecPerKm];
    final medians = _rolling(paces, medianWindow, _median);
    final means = _rolling(
      medians,
      meanWindow,
      (values) => values.reduce((a, b) => a + b) / values.length,
    );
    return [
      for (var i = 0; i < samples.length; i++)
        RunPaceSample(
          distanceMeters: samples[i].distanceMeters,
          paceSecPerKm: means[i],
        ),
    ];
  }

  static List<double> _rolling(
    List<double> values,
    int window,
    double Function(List<double>) reduce,
  ) {
    final half = window ~/ 2;
    return [
      for (var i = 0; i < values.length; i++)
        reduce(
          values.sublist(
            (i - half).clamp(0, values.length - 1),
            (i + half + 1).clamp(1, values.length),
          ),
        ),
    ];
  }

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static List<RunSplit> _buildSplits({
    required List<double> cumDist,
    required List<DateTime> times,
  }) {
    final total = cumDist.last;
    if (total < 20) return const [];

    final splits = <RunSplit>[];
    var nextKm = 1;
    var splitStartIdx = 0;

    for (var i = 1; i < cumDist.length; i++) {
      while (cumDist[i] >= nextKm * 1000.0) {
        final boundary = nextKm * 1000.0;
        final duration = _durationCrossing(
          cumDist: cumDist,
          times: times,
          startIdx: splitStartIdx,
          endIdx: i,
          boundaryMeters: boundary,
        );
        final pace = paceSecPerKm(1000.0, duration);
        splits.add(
          RunSplit(
            km: nextKm,
            distanceMeters: 1000.0,
            durationSeconds: duration,
            paceSecPerKm: pace,
            isPartial: false,
          ),
        );
        splitStartIdx = i;
        nextKm++;
      }
    }

    final completedMeters = (nextKm - 1) * 1000.0;
    final rem = total - completedMeters;
    if (rem >= 20) {
      final duration = times.last
          .difference(times[splitStartIdx])
          .inSeconds
          .clamp(0, 24 * 3600);
      splits.add(
        RunSplit(
          km: nextKm,
          distanceMeters: rem,
          durationSeconds: duration,
          paceSecPerKm: paceSecPerKm(rem, duration),
          isPartial: true,
        ),
      );
    }

    return splits;
  }

  static int _durationCrossing({
    required List<double> cumDist,
    required List<DateTime> times,
    required int startIdx,
    required int endIdx,
    required double boundaryMeters,
  }) {
    final startT = times[startIdx];
    final prevDist = cumDist[endIdx - 1];
    final curDist = cumDist[endIdx];
    final span = curDist - prevDist;
    DateTime endT;
    if (span <= 0) {
      endT = times[endIdx];
    } else {
      final frac = ((boundaryMeters - prevDist) / span).clamp(0.0, 1.0);
      final prevMs = times[endIdx - 1].millisecondsSinceEpoch;
      final curMs = times[endIdx].millisecondsSinceEpoch;
      endT = DateTime.fromMillisecondsSinceEpoch(
        (prevMs + (curMs - prevMs) * frac).round(),
        isUtc: times[endIdx].isUtc,
      );
    }
    return endT.difference(startT).inSeconds.clamp(0, 24 * 3600);
  }

  static double? _bestCompletedPace(List<RunSplit> splits) {
    double? best;
    for (final s in splits) {
      if (s.isPartial) continue;
      final p = s.paceSecPerKm;
      if (p == null || !p.isFinite) continue;
      if (best == null || p < best) best = p;
    }
    return best;
  }

  static List<RunPaceSample> _downsample(List<RunPaceSample> samples, int max) {
    if (samples.length <= max) return samples;
    final out = <RunPaceSample>[];
    final step = (samples.length - 1) / (max - 1);
    for (var i = 0; i < max; i++) {
      final idx = (i * step).round().clamp(0, samples.length - 1);
      out.add(samples[idx]);
    }
    return out;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
}

/// Y axis for a pace chart: "nice" tick steps and a range that ignores the
/// extreme few percent of samples so one slow spike cannot flatten the curve.
class RunPaceAxis {
  final double minPace;
  final double maxPace;
  final double interval;

  const RunPaceAxis({
    required this.minPace,
    required this.maxPace,
    required this.interval,
  });

  static const List<double> _steps = [15, 30, 60, 120, 180, 300];

  /// Ticks (sec/km) from [minPace] to [maxPace], every [interval].
  List<double> get ticks => [
    for (var v = minPace; v <= maxPace + 0.5; v += interval) v,
  ];

  factory RunPaceAxis.compute(
    List<RunPaceSample> samples, {
    double? averagePace,
  }) {
    final paces = [for (final s in samples) s.paceSecPerKm]..sort();
    if (paces.isEmpty) {
      final avg = averagePace ?? 360;
      return RunPaceAxis(
        minPace: (avg - 60).clamp(30, 3600),
        maxPace: avg + 60,
        interval: 30,
      );
    }
    var lo = _percentile(paces, 0.02);
    var hi = _percentile(paces, 0.98);
    if (averagePace != null && averagePace.isFinite && averagePace > 0) {
      if (averagePace < lo) lo = averagePace;
      if (averagePace > hi) hi = averagePace;
    }
    final span = math.max(hi - lo, 20.0);
    final pad = span * 0.15;
    var low = lo - pad;
    var high = hi + pad;
    var step = _steps.last;
    for (final candidate in _steps) {
      if ((high - low) / candidate <= 5) {
        step = candidate;
        break;
      }
    }
    low = (low / step).floor() * step;
    high = (high / step).ceil() * step;
    if (low < 0) low = 0;
    if (high - low < step * 2) high = low + step * 2;
    return RunPaceAxis(minPace: low, maxPace: high, interval: step);
  }

  static double _percentile(List<double> sorted, double q) {
    final position = (sorted.length - 1) * q;
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower];
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
  }
}
