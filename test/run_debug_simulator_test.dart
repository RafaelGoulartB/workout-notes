import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/run_debug_simulator.dart';

void main() {
  test('debug simulator accumulates distance and emits km splits', () {
    final sim = RunDebugSimulator.create();
    // 1000m / 15 m/s ≈ 67 ticks for first full km.
    for (var i = 0; i < 70; i++) {
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
}
