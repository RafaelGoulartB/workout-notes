import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_effort_analytics.dart';
import 'package:workout_notes/utils/run_elevation_analytics.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/utils/run_route_geometry.dart';

List<RunTrackPoint> _run() {
  final started = DateTime.utc(2026, 6, 1, 8);
  // A wobbly 3.3 km run north, one fix every 10 s, uneven speed.
  return [
    for (var i = 0; i <= 330; i++)
      RunTrackPoint(
        id: 'p$i',
        activityId: 'run',
        seq: i,
        lat: -23.5 + i * 0.0001 + (i.isEven ? 0.0 : 0.000002),
        lng: -46.6,
        altitude: 700 + (i % 20).toDouble(),
        accuracy: 5,
        speed: null,
        recordedAt: started.add(Duration(seconds: i * (i < 150 ? 3 : 4))),
      ),
  ];
}

void main() {
  test('the profile is the cumulative distance the analytics share', () {
    final points = _run();
    final profile = RunTrackProfile.fromPoints(points);

    expect(profile.length, points.length);
    expect(profile.cumulativeMeters.first, 0);
    expect(profile.times.last, points.last.recordedAt);
    expect(
      RunRouteGeometry.fromPoints(points).cumulativeMeters,
      profile.cumulativeMeters,
    );
    expect(RunTrackProfile.fromPoints(const []).totalMeters, 0);
  });

  test('a shared profile changes nothing in the results', () {
    final points = _run();
    final profile = RunTrackProfile.fromPoints(points);

    final pace = RunPaceAnalytics.fromTrackPoints(points);
    final paceShared = RunPaceAnalytics.fromTrackPoints(
      points,
      profile: profile,
    );
    expect(paceShared.samples.length, pace.samples.length);
    expect(paceShared.splits.length, pace.splits.length);
    expect(paceShared.bestSplitPaceSecPerKm, pace.bestSplitPaceSecPerKm);

    final efforts = RunEffortAnalytics.fromTrackPoints(points);
    final effortsShared = RunEffortAnalytics.fromTrackPoints(
      points,
      profile: profile,
    );
    expect(effortsShared.bestEffort1kSec, efforts.bestEffort1kSec);
    expect(effortsShared.bestEffort3kSec, efforts.bestEffort3kSec);
    expect(effortsShared.bestSplitPaceSecPerKm, pace.bestSplitPaceSecPerKm);

    final elevation = RunElevationProfile.fromTrackPoints(points);
    final elevationShared = RunElevationProfile.fromTrackPoints(
      points,
      profile: profile,
    );
    expect(elevationShared.gainMeters, elevation.gainMeters);
  });

  test('best split pace needs no chart samples', () {
    final points = _run();
    final profile = RunTrackProfile.fromPoints(points);
    expect(
      RunPaceAnalytics.bestSplitPaceOf(profile),
      RunPaceAnalytics.fromTrackPoints(points).bestSplitPaceSecPerKm,
    );
    expect(
      RunPaceAnalytics.bestSplitPaceOf(RunTrackProfile.fromPoints(const [])),
      isNull,
    );
  });
}
