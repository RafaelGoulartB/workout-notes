import 'dart:math' as math;

import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_track_point.dart';

/// One pace sample along the run, keyed by cumulative distance.
class RunPaceSample {
  final double distanceMeters;
  final double paceSecPerKm;

  const RunPaceSample({
    required this.distanceMeters,
    required this.paceSecPerKm,
  });
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

  /// Cap a single segment's Δt so a long pause between points does not
  /// create an absurdly slow spike (points usually pause with the session).
  static const int maxSegmentSeconds = 45;

  static double haversineMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double? paceSecPerKm(double distanceMeters, int movingTimeSeconds) {
    if (distanceMeters < 1.0 || movingTimeSeconds <= 0) return null;
    final pace = movingTimeSeconds / (distanceMeters / 1000.0);
    if (!pace.isFinite || pace <= 0) return null;
    return pace;
  }

  /// Builds chart samples and km splits from ordered track points.
  static RunPaceAnalytics fromTrackPoints(
    List<RunTrackPoint> points, {
    double? activityAvgPaceSecPerKm,
    double windowMeters = defaultWindowMeters,
  }) {
    if (points.length < 2) {
      return RunPaceAnalytics(
        samples: const [],
        splits: const [],
        avgPaceSecPerKm: activityAvgPaceSecPerKm,
        bestSplitPaceSecPerKm: null,
      );
    }

    final cumDist = <double>[0.0];
    final times = <DateTime>[points.first.recordedAt];

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final step = haversineMeters(
        lat1: prev.lat,
        lng1: prev.lng,
        lat2: cur.lat,
        lng2: cur.lng,
      );
      final accepted = step >= minStepMeters ? step : 0.0;
      cumDist.add(cumDist.last + accepted);
      times.add(cur.recordedAt);
    }

    final totalDistance = cumDist.last;
    final samples = _buildSamples(
      cumDist: cumDist,
      times: times,
      windowMeters: windowMeters,
    );
    final splits = _buildSplits(cumDist: cumDist, times: times);
    final best = _bestCompletedPace(splits);

    final avg = activityAvgPaceSecPerKm ??
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

  static List<RunPaceSample> _buildSamples({
    required List<double> cumDist,
    required List<DateTime> times,
    required double windowMeters,
  }) {
    final raw = <RunPaceSample>[];
    var windowStart = 0;

    for (var i = 1; i < cumDist.length; i++) {
      while (windowStart < i - 1 &&
          cumDist[i] - cumDist[windowStart + 1] >= windowMeters) {
        windowStart++;
      }

      final dd = cumDist[i] - cumDist[windowStart];
      if (dd < windowMeters * 0.6) continue;

      var dt = times[i].difference(times[windowStart]).inSeconds;
      if (dt <= 0) continue;
      // Soft-cap long gaps so pause holes do not dominate the curve.
      if (dt > maxSegmentSeconds * 8) {
        dt = (dd / 1000.0 * 360).round().clamp(1, maxSegmentSeconds * 8);
      }

      final pace = dt / (dd / 1000.0);
      if (!pace.isFinite) continue;
      if (pace < minPaceSecPerKm || pace > maxPaceSecPerKm) continue;

      raw.add(RunPaceSample(distanceMeters: cumDist[i], paceSecPerKm: pace));
    }

    return _downsample(raw, maxChartSamples);
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
      final duration = times.last.difference(times[splitStartIdx]).inSeconds
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
