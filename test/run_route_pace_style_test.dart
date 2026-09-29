import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_route_pace_style.dart';

void main() {
  test('colors route segments relative to the run average pace', () {
    expect(
      RunRoutePaceStyle.colorForPace(
        paceSecPerKm: 320,
        averagePaceSecPerKm: 400,
      ),
      RunRoutePaceStyle.fastColor,
    );
    expect(
      RunRoutePaceStyle.colorForPace(
        paceSecPerKm: 400,
        averagePaceSecPerKm: 400,
      ),
      RunRoutePaceStyle.averageColor,
    );
    expect(
      RunRoutePaceStyle.colorForPace(
        paceSecPerKm: 360,
        averagePaceSecPerKm: 400,
      ),
      RunRoutePaceStyle.transitionColor,
    );
    expect(
      RunRoutePaceStyle.colorForPace(
        paceSecPerKm: 500,
        averagePaceSecPerKm: 400,
      ),
      RunRoutePaceStyle.averageColor,
    );
  });

  test('smooths segment pace over recent GPS points', () {
    final start = DateTime.utc(2026, 8, 25, 10);
    final points = List.generate(
      7,
      (index) => RunTrackPoint(
        id: 'point-$index',
        activityId: 'activity',
        seq: index,
        lat: 0,
        lng: index * 0.001,
        altitude: null,
        accuracy: 5,
        speed: null,
        recordedAt: start.add(Duration(seconds: index * 30)),
      ),
    );

    final paces = RunRoutePaceStyle.segmentPaces(
      points,
      averagePaceSecPerKm: 400,
    );

    expect(paces, hasLength(points.length - 1));
    expect(paces.every((pace) => pace != null && pace > 0), isTrue);
  });

  test('groups consecutive same-colour segments into polylines', () {
    final runs = RunRoutePaceStyle.colorRuns([
      400,
      400,
      400,
      320,
      320,
      400,
    ], averagePaceSecPerKm: 400);
    expect(runs, hasLength(3));
    expect(runs[0].startSegment, 0);
    expect(runs[0].endSegment, 2);
    expect(runs[0].color, RunRoutePaceStyle.averageColor);
    expect(runs[1].color, RunRoutePaceStyle.fastColor);
    // A run's polyline covers the points of its segments, sharing the joint.
    expect(runs[1].firstPoint, 3);
    expect(runs[1].lastPoint, 5);
    expect(runs[2].firstPoint, runs[1].lastPoint);
    expect(RunRoutePaceStyle.colorRuns([], averagePaceSecPerKm: 400), isEmpty);
  });

  test('legend ends at the pace where the route turns fully red', () {
    expect(RunRoutePaceStyle.fastestLegendPace(400), closeTo(320, 0.001));
    expect(
      RunRoutePaceStyle.legendColors.first,
      RunRoutePaceStyle.averageColor,
    );
    expect(RunRoutePaceStyle.legendColors.last, RunRoutePaceStyle.fastColor);
  });
}
