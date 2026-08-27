import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/services/run_pace_calculator.dart';

void main() {
  group('RunPaceCalculator', () {
    test('interval is faster than tempo which is faster than easy', () {
      // ~25:00 5K
      final paces = RunPaceCalculator.fromRace(
        distanceMeters: RunPaceCalculator.fiveKMeters,
        timeSeconds: 25 * 60,
      );
      expect(paces.intervalSecPerKm, lessThan(paces.tempoSecPerKm));
      expect(paces.tempoSecPerKm, lessThan(paces.easySecPerKm));
      expect(paces.raceSecPerKm, closeTo(300, 1)); // 5:00/km
    });

    test('faster race yields faster training paces', () {
      final slow = RunPaceCalculator.fromGoalTime(
        goalDistanceMeters: RunPaceCalculator.tenKMeters,
        goalTimeSeconds: 60 * 60,
      );
      final fast = RunPaceCalculator.fromGoalTime(
        goalDistanceMeters: RunPaceCalculator.tenKMeters,
        goalTimeSeconds: 45 * 60,
      );
      expect(fast.easySecPerKm, lessThan(slow.easySecPerKm));
      expect(fast.intervalSecPerKm, lessThan(slow.intervalSecPerKm));
    });

    test('band is symmetric around target', () {
      final (min, max) = RunPaceCalculator.band(300);
      expect(min, closeTo(291, 0.1));
      expect(max, closeTo(309, 0.1));
    });

    test('rejects non-positive inputs', () {
      expect(
        () => RunPaceCalculator.fromRace(distanceMeters: 0, timeSeconds: 100),
        throwsArgumentError,
      );
    });

    test('flags a goal far faster than current fitness', () {
      final fitness = RunPaceCalculator.fromRace(
        distanceMeters: RunPaceCalculator.fiveKMeters,
        timeSeconds: 28 * 60,
      );
      expect(
        RunPaceCalculator.isOptimisticGoal(
          fitness: fitness,
          goalDistanceMeters: RunPaceCalculator.fiveKMeters,
          goalTimeSeconds: 22 * 60,
        ),
        isTrue,
      );
      expect(
        RunPaceCalculator.isOptimisticGoal(
          fitness: fitness,
          goalDistanceMeters: RunPaceCalculator.fiveKMeters,
          goalTimeSeconds: 27 * 60,
        ),
        isFalse,
      );
    });
  });
}
