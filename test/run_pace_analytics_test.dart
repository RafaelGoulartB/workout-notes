import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

void main() {
  group('RunPaceAnalytics.haversineMeters', () {
    test('known short northward distance ≈ 111 m', () {
      final meters = RunPaceAnalytics.haversineMeters(
        lat1: 0,
        lng1: 0,
        lat2: 0.001,
        lng2: 0,
      );
      expect(meters, closeTo(111.2, 1.0));
    });
  });

  group('RunPaceAnalytics.fromTrackPoints', () {
    test('empty / single point yields no chart or splits', () {
      final a = RunPaceAnalytics.fromTrackPoints(const []);
      expect(a.hasChart, isFalse);
      expect(a.hasSplits, isFalse);

      final b = RunPaceAnalytics.fromTrackPoints([
        _point(0, 0, 0, DateTime.utc(2026, 1, 1)),
      ]);
      expect(b.hasChart, isFalse);
      expect(b.splits, isEmpty);
    });

    test('synthetic 1.5 km path builds samples and splits', () {
      final points = _straightPath(
        start: DateTime.utc(2026, 8, 18, 12),
        meters: 1500,
        paceSecPerKm: 360, // 6:00 /km
        stepMeters: 25,
      );

      final analytics = RunPaceAnalytics.fromTrackPoints(
        points,
        activityAvgPaceSecPerKm: 360,
      );

      expect(analytics.hasChart, isTrue);
      expect(analytics.samples.length, greaterThan(5));
      expect(analytics.samples.first.distanceMeters, greaterThan(40));
      expect(
        analytics.samples.last.distanceMeters,
        closeTo(1500, 40),
      );

      // Distances are non-decreasing.
      for (var i = 1; i < analytics.samples.length; i++) {
        expect(
          analytics.samples[i].distanceMeters,
          greaterThanOrEqualTo(analytics.samples[i - 1].distanceMeters),
        );
      }

      expect(analytics.splits.length, 2);
      expect(analytics.splits[0].km, 1);
      expect(analytics.splits[0].isPartial, isFalse);
      expect(analytics.splits[0].distanceMeters, 1000);
      expect(analytics.splits[0].paceSecPerKm, closeTo(360, 15));

      expect(analytics.splits[1].isPartial, isTrue);
      expect(analytics.splits[1].distanceMeters, closeTo(500, 30));
      expect(analytics.bestSplitPaceSecPerKm, isNotNull);
      expect(analytics.avgPaceSecPerKm, 360);
    });

    test('paceSecPerKm helper rejects tiny distance', () {
      expect(RunPaceAnalytics.paceSecPerKm(0.5, 10), isNull);
      expect(RunPaceAnalytics.paceSecPerKm(1000, 360), 360);
    });
  });
}

RunTrackPoint _point(double lat, double lng, int seq, DateTime at) {
  return RunTrackPoint(
    id: 'p$seq',
    activityId: 'a1',
    seq: seq,
    lat: lat,
    lng: lng,
    altitude: null,
    accuracy: 5,
    speed: null,
    recordedAt: at,
  );
}

/// Builds a northward path at roughly constant pace.
List<RunTrackPoint> _straightPath({
  required DateTime start,
  required double meters,
  required double paceSecPerKm,
  required double stepMeters,
}) {
  // 1° lat ≈ 111195 m
  const metersPerDeg = 111195.0;
  final points = <RunTrackPoint>[];
  var traveled = 0.0;
  var seq = 0;
  points.add(_point(0, 0, seq++, start));

  while (traveled < meters) {
    final step = (meters - traveled).clamp(0, stepMeters);
    traveled += step;
    final lat = traveled / metersPerDeg;
    final elapsedSec = (traveled / 1000.0) * paceSecPerKm;
    points.add(
      _point(
        lat,
        0,
        seq++,
        start.add(Duration(milliseconds: (elapsedSec * 1000).round())),
      ),
    );
  }
  return points;
}
