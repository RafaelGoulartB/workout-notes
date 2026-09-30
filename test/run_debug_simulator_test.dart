import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/dev_tools/run_debug_simulator.dart';

void main() {
  test('debug simulator accumulates distance and emits km splits', () {
    final sim = RunDebugSimulator.create();
    // ~1000m at ~14 m/s average still lands near a minute of ticks.
    for (var i = 0; i < 90; i++) {
      sim.tick();
    }
    expect(sim.distanceMeters, greaterThan(1000));
    expect(sim.completedSplits, isNotEmpty);
    expect(sim.completedSplits.first.km, 1);
    expect(sim.completedSplits.first.isPartial, isFalse);
    expect(sim.currentPartialSplit, isNotNull);
    expect(sim.trail.length, greaterThan(60));

    final spool = sim.toSpoolPayload();
    expect(spool['activity'], isA<Map>());
    expect((spool['points'] as List).length, sim.trail.length);
  });

  test('debug simulator speed varies across ticks but stays fast', () {
    final sim = RunDebugSimulator.create();
    final speeds = <double>[];
    for (var i = 0; i < 120; i++) {
      sim.tick();
      speeds.add(sim.lastStepMeters);
    }

    final minSpeed = speeds.reduce((a, b) => a < b ? a : b);
    final maxSpeed = speeds.reduce((a, b) => a > b ? a : b);
    expect(
      minSpeed,
      greaterThanOrEqualTo(RunDebugSimulator.minMetersPerSecond),
    );
    expect(maxSpeed, lessThanOrEqualTo(RunDebugSimulator.maxMetersPerSecond));
    // Real variation — not a flat cruise.
    expect(maxSpeed - minSpeed, greaterThan(4.0));

    // Still quick enough for QA (~1 km / minute order of magnitude).
    expect(sim.distanceMeters / sim.elapsedSeconds, greaterThan(10.0));

    final paces = [for (final s in speeds) 1000.0 / s];
    final minPace = paces.reduce((a, b) => a < b ? a : b);
    final maxPace = paces.reduce((a, b) => a > b ? a : b);
    expect(maxPace - minPace, greaterThan(20.0));

    final activity = sim.toSpoolPayload()['activity'] as Map;
    expect(
      activity['max_pace_sec_per_km'],
      lessThan(activity['avg_pace_sec_per_km']),
    );
  });

  test('speedForTick is deterministic', () {
    expect(
      RunDebugSimulator.create().speedForTick(10),
      RunDebugSimulator.create().speedForTick(10),
    );
    expect(
      RunDebugSimulator.create().speedForTick(1),
      isNot(RunDebugSimulator.create().speedForTick(20)),
    );
  });

  test('debug simulator marks manual laps and exports them in the spool', () {
    final sim = RunDebugSimulator.create();
    for (var i = 0; i < 30; i++) {
      sim.tick();
    }
    final first = sim.markLap();
    expect(first, isNotNull);
    expect(first!.index, 1);
    expect(first.durationSeconds, 30);
    expect(first.distanceMeters, closeTo(sim.distanceMeters, 0.001));

    // A second tap right away is an accident, not a lap.
    expect(sim.markLap(), isNull);

    for (var i = 0; i < 20; i++) {
      sim.tick();
    }
    final state = sim.toState(locationGranted: true);
    expect(state.laps, hasLength(1));
    expect(state.currentLap!.index, 2);
    expect(state.currentLap!.durationSeconds, 20);
    expect(state.currentLap!.startDistanceMeters, first.distanceMeters);

    final laps = (sim.toSpoolPayload()['activity'] as Map)['laps'] as List;
    // The open remainder becomes the last lap.
    expect(laps, hasLength(2));
    expect((laps.last as Map)['lap_index'], 2);
  });
}
