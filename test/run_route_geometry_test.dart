import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_route_geometry.dart';

RunTrackPoint _p(int seq, double lat, double lng) => RunTrackPoint(
  id: 'p$seq',
  activityId: 'a',
  seq: seq,
  lat: lat,
  lng: lng,
  altitude: null,
  accuracy: 5,
  speed: null,
  recordedAt: DateTime.utc(2026, 8, 25).add(Duration(seconds: seq)),
);

void main() {
  // 0.001 deg of latitude is about 111 m.
  final points = [for (var i = 0; i <= 4; i++) _p(i, i * 0.001, 0)];

  test('cumulative distance grows along the trail', () {
    final geometry = RunRouteGeometry.fromPoints(points);
    expect(geometry.cumulativeMeters.first, 0);
    expect(geometry.totalMeters, closeTo(444.8, 2));
  });

  test('maps a chart distance back to an interpolated position', () {
    final geometry = RunRouteGeometry.fromPoints(points);
    final mid = geometry.positionAtDistance(geometry.totalMeters / 2)!;
    expect(mid.lat, closeTo(0.002, 1e-5));
    final quarter = geometry.positionAtDistance(geometry.totalMeters / 8)!;
    expect(quarter.lat, closeTo(0.0005, 1e-5));
  });

  test('clamps distances outside the trail', () {
    final geometry = RunRouteGeometry.fromPoints(points);
    expect(geometry.positionAtDistance(-50)!.lat, 0);
    expect(geometry.positionAtDistance(99999)!.lat, closeTo(0.004, 1e-9));
    expect(RunRouteGeometry.empty.positionAtDistance(10), isNull);
  });

  test('bounds ignore a single-spot trail', () {
    expect(
      RunRouteGeometry.boundsOf([
        (lat: 1.0, lng: 2.0),
        (lat: 1.00001, lng: 2.0),
      ]),
      isNull,
    );
    final bounds = RunRouteGeometry.boundsOf([
      (lat: 1.0, lng: 2.0),
      (lat: 1.5, lng: 2.5),
    ]);
    expect(bounds?.minLat, 1.0);
    expect(bounds?.maxLng, 2.5);
  });
}
