import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

void main() {
  _smoothingTests();
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
      expect(analytics.samples.last.distanceMeters, closeTo(1500, 40));

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

    test('a stop does not create a slow canyon in the pace curve', () {
      final start = DateTime.utc(2026, 8, 18, 12);
      // 1 km at 6:00 /km, 90 s standing still, then 1 km at 6:00 /km.
      final first = _straightPath(
        start: start,
        meters: 1000,
        paceSecPerKm: 360,
        stepMeters: 10,
      );
      final restart = first.last.recordedAt.add(const Duration(seconds: 90));
      final second = _straightPath(
        start: restart,
        meters: 1000,
        paceSecPerKm: 360,
        stepMeters: 10,
      );
      const metersPerDeg = 111195.0;
      final points = [
        ...first,
        // Stationary jitter-free samples while stopped.
        for (var i = 1; i <= 9; i++)
          _point(
            first.last.lat,
            0,
            1000 + i,
            first.last.recordedAt.add(Duration(seconds: i * 10)),
          ),
        for (var i = 0; i < second.length; i++)
          _point(
            first.last.lat + second[i].lat,
            0,
            2000 + i,
            second[i].recordedAt,
          ),
      ];
      expect(first.last.lat * metersPerDeg, closeTo(1000, 1));

      final analytics = RunPaceAnalytics.fromTrackPoints(points);
      final slowest = analytics.samples
          .map((s) => s.paceSecPerKm)
          .reduce((a, b) => a > b ? a : b);
      expect(slowest, lessThan(420));
      final fastest = analytics.samples
          .map((s) => s.paceSecPerKm)
          .reduce((a, b) => a < b ? a : b);
      expect(fastest, greaterThan(300));
    });

    test('paceSecPerKm helper rejects tiny distance', () {
      expect(RunPaceAnalytics.paceSecPerKm(0.5, 10), isNull);
      expect(RunPaceAnalytics.paceSecPerKm(1000, 360), 360);
    });
  });
}

RunPaceSample _sample(double meters, double pace) =>
    RunPaceSample(distanceMeters: meters, paceSecPerKm: pace);

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

void _smoothingTests() {
  group('RunPaceAnalytics.smoothSamples', () {
    test('a single spike is flattened by the rolling median', () {
      final samples = [
        for (var i = 0; i < 9; i++) _sample(i * 100.0, i == 4 ? 720.0 : 360.0),
      ];
      final smoothed = RunPaceAnalytics.smoothSamples(samples);
      expect(smoothed, hasLength(samples.length));
      expect(smoothed[4].paceSecPerKm, closeTo(360, 1));
      expect(smoothed[4].distanceMeters, 400);
    });

    test('removeOutliers drops values far from the median', () {
      final samples = [
        for (var i = 0; i < 10; i++) _sample(i * 100.0, 360),
        _sample(1000, 1500),
        _sample(1100, 60),
      ];
      final kept = RunPaceAnalytics.removeOutliers(samples);
      expect(kept, hasLength(10));
    });
  });

  group('RunPaceAxis', () {
    test('picks nice ticks and ignores the extreme tail', () {
      final samples = [
        for (var i = 0; i < 100; i++) _sample(i * 50.0, 330 + (i % 10) * 4.0),
        _sample(5000, 900), // one glitch out of 101 samples
      ];
      final axis = RunPaceAxis.compute(samples, averagePace: 350);
      expect(axis.maxPace, lessThan(600));
      expect(axis.interval, anyOf(15, 30, 60));
      expect(axis.minPace % axis.interval, 0);
      expect(axis.maxPace % axis.interval, 0);
      expect(axis.minPace, lessThanOrEqualTo(330));
      expect(axis.maxPace, greaterThanOrEqualTo(366));
      expect(axis.ticks.first, axis.minPace);
      expect(axis.ticks.last, axis.maxPace);
    });

    test('falls back to the average when there are no samples', () {
      final axis = RunPaceAxis.compute(const [], averagePace: 360);
      expect(axis.minPace, lessThan(360));
      expect(axis.maxPace, greaterThan(360));
    });
  });
}
