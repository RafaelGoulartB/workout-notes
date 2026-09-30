import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_elevation_analytics.dart';

const _metersPerDegree = 111195.0;

/// A northward path with a point every [stepMeters] whose altitude comes
/// from [altitudeAt] (metres travelled -> altitude).
List<RunTrackPoint> _path({
  required double meters,
  required double stepMeters,
  required double? Function(double traveled) altitudeAt,
}) {
  final start = DateTime.utc(2026, 8, 18, 12);
  final points = <RunTrackPoint>[];
  var traveled = 0.0;
  var seq = 0;
  while (traveled <= meters) {
    points.add(
      RunTrackPoint(
        id: 'p$seq',
        activityId: 'a',
        seq: seq,
        lat: traveled / _metersPerDegree,
        lng: 0,
        altitude: altitudeAt(traveled),
        accuracy: 5,
        speed: null,
        recordedAt: start.add(Duration(seconds: seq * 3)),
      ),
    );
    seq++;
    traveled += stepMeters;
  }
  return points;
}

void main() {
  group('RunElevationProfile', () {
    test('no altitude data yields an empty profile', () {
      final points = _path(
        meters: 500,
        stepMeters: 10,
        altitudeAt: (_) => null,
      );
      final profile = RunElevationProfile.fromTrackPoints(points);
      expect(profile.hasData, isFalse);
      expect(profile.gainMeters, 0);
    });

    test('measures a steady climb and attributes it to kilometres', () {
      // +30 m over the first km, flat over the second.
      final points = _path(
        meters: 2000,
        stepMeters: 10,
        altitudeAt: (d) => 100 + (d < 1000 ? d * 0.03 : 30),
      );
      final profile = RunElevationProfile.fromTrackPoints(points);
      expect(profile.hasData, isTrue);
      expect(profile.gainMeters, closeTo(30, 4));
      expect(profile.lossMeters, lessThan(2));
      expect(profile.minAltitudeMeters, closeTo(100, 2));
      expect(profile.maxAltitudeMeters, closeTo(130, 2));
      // Smoothing spreads a climb a few metres past the km boundary.
      expect(profile.gainByKm[1], closeTo(30, 6));
      expect(profile.gainByKm[2] ?? 0, lessThan(5));
    });

    test('sensor jitter on flat ground does not count as climbing', () {
      final points = _path(
        meters: 1500,
        stepMeters: 5,
        altitudeAt: (d) => 50 + ((d ~/ 5) % 2 == 0 ? 0.8 : -0.8),
      );
      final profile = RunElevationProfile.fromTrackPoints(points);
      expect(profile.gainMeters, lessThan(2));
      expect(profile.lossMeters, lessThan(2));
    });

    test('a descent counts as loss only', () {
      final points = _path(
        meters: 1000,
        stepMeters: 10,
        altitudeAt: (d) => 200 - d * 0.04,
      );
      final profile = RunElevationProfile.fromTrackPoints(points);
      expect(profile.lossMeters, closeTo(40, 5));
      expect(profile.gainMeters, lessThan(2));
    });

    test('chart samples are bounded and ordered by distance', () {
      final points = _path(
        meters: 20000,
        stepMeters: 10,
        altitudeAt: (d) => 100 + d * 0.01,
      );
      final profile = RunElevationProfile.fromTrackPoints(points);
      expect(
        profile.samples.length,
        lessThanOrEqualTo(RunElevationProfile.maxChartSamples),
      );
      for (var i = 1; i < profile.samples.length; i++) {
        expect(
          profile.samples[i].distanceMeters,
          greaterThanOrEqualTo(profile.samples[i - 1].distanceMeters),
        );
      }
    });
  });

  group('RunElevationAxis', () {
    test('never zooms into a few metres of noise', () {
      final points = _path(
        meters: 1000,
        stepMeters: 10,
        altitudeAt: (d) => 30 + (d ~/ 10 % 2) * 0.3,
      );
      final axis = RunElevationAxis.compute(
        RunElevationProfile.fromTrackPoints(points),
      );
      expect(axis.maxAltitude - axis.minAltitude, greaterThanOrEqualTo(20));
      expect(axis.minAltitude % axis.interval, 0);
    });

    test('covers the whole profile with round bounds', () {
      final points = _path(
        meters: 3000,
        stepMeters: 10,
        altitudeAt: (d) => 700 + d * 0.05,
      );
      final profile = RunElevationProfile.fromTrackPoints(points);
      final axis = RunElevationAxis.compute(profile);
      expect(axis.minAltitude, lessThanOrEqualTo(profile.minAltitudeMeters!));
      expect(
        axis.maxAltitude,
        greaterThanOrEqualTo(profile.maxAltitudeMeters!),
      );
    });
  });
}
