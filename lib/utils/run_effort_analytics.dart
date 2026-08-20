import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

/// Fixed-distance best efforts + best completed km split from GPS.
class RunEffortMetrics {
  final double? bestSplitPaceSecPerKm;
  final int? bestEffort1kSec;
  final int? bestEffort3kSec;
  final int? bestEffort5kSec;
  final int? bestEffort10kSec;
  final int? bestEffortHalfSec;
  final int? bestEffortMarathonSec;

  const RunEffortMetrics({
    this.bestSplitPaceSecPerKm,
    this.bestEffort1kSec,
    this.bestEffort3kSec,
    this.bestEffort5kSec,
    this.bestEffort10kSec,
    this.bestEffortHalfSec,
    this.bestEffortMarathonSec,
  });

  static const empty = RunEffortMetrics();
}

abstract final class RunEffortAnalytics {
  static const double effort1kMeters = 1000.0;
  static const double effort3kMeters = 3000.0;
  static const double effort5kMeters = 5000.0;
  static const double effort10kMeters = 10000.0;
  static const double effortHalfMeters = 21097.5;
  static const double effortMarathonMeters = 42195.0;

  /// Builds effort metrics from ordered track points.
  static RunEffortMetrics fromTrackPoints(List<RunTrackPoint> points) {
    if (points.length < 2) return RunEffortMetrics.empty;

    final cumDist = <double>[0.0];
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
      final accepted =
          step >= RunPaceAnalytics.minStepMeters ? step : 0.0;
      cumDist.add(cumDist.last + accepted);
      times.add(cur.recordedAt);
    }

    final pace = RunPaceAnalytics.fromTrackPoints(points);
    return RunEffortMetrics(
      bestSplitPaceSecPerKm: pace.bestSplitPaceSecPerKm,
      bestEffort1kSec: bestEffortSeconds(
        cumDist: cumDist,
        times: times,
        targetMeters: effort1kMeters,
      ),
      bestEffort3kSec: bestEffortSeconds(
        cumDist: cumDist,
        times: times,
        targetMeters: effort3kMeters,
      ),
      bestEffort5kSec: bestEffortSeconds(
        cumDist: cumDist,
        times: times,
        targetMeters: effort5kMeters,
      ),
      bestEffort10kSec: bestEffortSeconds(
        cumDist: cumDist,
        times: times,
        targetMeters: effort10kMeters,
      ),
      bestEffortHalfSec: bestEffortSeconds(
        cumDist: cumDist,
        times: times,
        targetMeters: effortHalfMeters,
      ),
      bestEffortMarathonSec: bestEffortSeconds(
        cumDist: cumDist,
        times: times,
        targetMeters: effortMarathonMeters,
      ),
    );
  }

  /// Fastest contiguous segment covering exactly [targetMeters].
  static int? bestEffortSeconds({
    required List<double> cumDist,
    required List<DateTime> times,
    required double targetMeters,
  }) {
    if (cumDist.length < 2 || cumDist.last < targetMeters) return null;

    int? best;
    var i = 0;
    for (var j = 1; j < cumDist.length; j++) {
      while (i < j - 1 && cumDist[j] - cumDist[i + 1] >= targetMeters) {
        i++;
      }
      if (cumDist[j] - cumDist[i] < targetMeters) continue;

      final startDist = cumDist[j] - targetMeters;
      final startT = _timeAtDistance(
        cumDist: cumDist,
        times: times,
        distanceMeters: startDist,
        hintIdx: i,
      );
      final endT = times[j];
      final seconds = endT.difference(startT).inSeconds;
      if (seconds <= 0) continue;
      if (best == null || seconds < best) best = seconds;
    }
    return best;
  }

  static DateTime _timeAtDistance({
    required List<double> cumDist,
    required List<DateTime> times,
    required double distanceMeters,
    required int hintIdx,
  }) {
    final target = distanceMeters.clamp(0.0, cumDist.last);
    var idx = hintIdx.clamp(0, cumDist.length - 1);
    while (idx > 0 && cumDist[idx] > target) {
      idx--;
    }
    while (idx < cumDist.length - 1 && cumDist[idx + 1] < target) {
      idx++;
    }
    if (idx >= cumDist.length - 1) return times.last;
    final d0 = cumDist[idx];
    final d1 = cumDist[idx + 1];
    final span = d1 - d0;
    if (span <= 0) return times[idx];
    final frac = ((target - d0) / span).clamp(0.0, 1.0);
    final t0 = times[idx].millisecondsSinceEpoch;
    final t1 = times[idx + 1].millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      (t0 + (t1 - t0) * frac).round(),
      isUtc: times[idx].isUtc,
    );
  }
}
