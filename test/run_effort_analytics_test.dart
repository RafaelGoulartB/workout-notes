import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_effort_analytics.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

/// Points along a meridian using the same Earth radius as RunPaceAnalytics.
List<RunTrackPoint> _straightRun({
  required int meters,
  required int paceSecPerKm,
  DateTime? start,
}) {
  final started = start ?? DateTime.utc(2026, 6, 1, 8);
  final points = <RunTrackPoint>[];
  const stepMeters = 50.0;
  // Match RunPaceAnalytics.earthRadiusMeters so haversine totals ≈ requested.
  const metersPerDeg =
      RunPaceAnalytics.earthRadiusMeters * 3.141592653589793 / 180.0;
  // Overshoot so cumulative haversine clears the target distance.
  final target = meters + 80.0;
  final steps = (target / stepMeters).ceil();
  for (var i = 0; i <= steps; i++) {
    final dist = (i * stepMeters).clamp(0, target).toDouble();
    final lat = dist / metersPerDeg;
    final elapsedSec = (dist / 1000.0 * paceSecPerKm).round();
    points.add(
      RunTrackPoint(
        id: 'p$i',
        activityId: 'run',
        seq: i,
        lat: lat,
        lng: 0,
        altitude: null,
        accuracy: 5,
        speed: null,
        recordedAt: started.add(Duration(seconds: elapsedSec)),
      ),
    );
  }
  return points;
}

void main() {
  test('computes best efforts for a steady 5k', () {
    final points = _straightRun(meters: 5000, paceSecPerKm: 300);
    final metrics = RunEffortAnalytics.fromTrackPoints(points);

    expect(metrics.bestEffort1kSec, isNotNull);
    expect(metrics.bestEffort1kSec, closeTo(300, 8));
    expect(metrics.bestEffort3kSec, closeTo(900, 15));
    expect(metrics.bestEffort5kSec, closeTo(1500, 25));
    expect(metrics.bestEffort10kSec, isNull);
    expect(metrics.bestSplitPaceSecPerKm, isNotNull);
    // Split pace comes from discrete km boundaries; allow GPS/haversine slack.
    expect(metrics.bestSplitPaceSecPerKm!, greaterThan(250));
    expect(metrics.bestSplitPaceSecPerKm!, lessThan(350));
  });

  test('best effort picks the fastest contiguous segment', () {
    // First 2k slow (400s/km), next 2k fast (280s/km).
    final start = DateTime.utc(2026, 6, 1, 8);
    final slow = _straightRun(meters: 2000, paceSecPerKm: 400, start: start);
    final fastStart = start.add(const Duration(seconds: 800));
    final fast = _straightRun(meters: 2000, paceSecPerKm: 280, start: fastStart);
    // Continue latitude from end of slow (~2000m + overshoot).
    final latOffset =
        2020 / (RunPaceAnalytics.earthRadiusMeters * 3.141592653589793 / 180.0);
    final shiftedFast = [
      for (var i = 0; i < fast.length; i++)
        RunTrackPoint(
          id: 'f$i',
          activityId: 'run',
          seq: slow.length + i,
          lat: fast[i].lat + latOffset,
          lng: 0,
          altitude: null,
          accuracy: 5,
          speed: null,
          recordedAt: fast[i].recordedAt,
        ),
    ];
    // Drop duplicate join point.
    final points = [...slow, ...shiftedFast.skip(1)];
    final metrics = RunEffortAnalytics.fromTrackPoints(points);

    expect(metrics.bestEffort1kSec, isNotNull);
    // Fast segment ~280s/km should win over slow 400s/km.
    expect(metrics.bestEffort1kSec!, lessThan(320));
    expect(metrics.bestEffort1kSec!, greaterThan(250));
  });

  test('returns empty metrics for insufficient points', () {
    final metrics = RunEffortAnalytics.fromTrackPoints(const []);
    expect(metrics.bestEffort1kSec, isNull);
    expect(metrics.bestSplitPaceSecPerKm, isNull);
  });
}
