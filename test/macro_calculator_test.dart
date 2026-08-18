import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/utils/macro_calculator.dart';

void main() {
  group('computeMacros', () {
    test('protein and fat follow g/kg times the reference weight', () {
      final macros = computeMacros(
        calories: 2400,
        proteinPerKg: 2.2,
        fatPerKg: 0.8,
        weightKg: 75,
      );
      expect(macros.proteinG, (2.2 * 75).roundToDouble());
      expect(macros.fatG, (0.8 * 75).roundToDouble());
      expect(macros.energyConflict, isFalse);
    });

    test('carbs absorb the remaining calories', () {
      final macros = computeMacros(
        calories: 2400,
        proteinPerKg: 2.2,
        fatPerKg: 0.8,
        weightKg: 75,
      );
      final expected =
          ((2400 - macros.proteinG * 4 - macros.fatG * 9) / 4).roundToDouble();
      expect(macros.carbsG, expected);
      expect(macros.carbsG, greaterThan(0));
    });

    test('energy split adds up to the target calories', () {
      final macros = computeMacros(
        calories: 2500,
        proteinPerKg: 2.0,
        fatPerKg: 1.0,
        weightKg: 80,
      );
      expect(macros.proteinKcal + macros.fatKcal + macros.carbsKcal,
          closeTo(2500, 3));
    });

    test('flags the conflict and clamps carbs to zero when P+F exceed kcal', () {
      // 3g/kg * 90 = 270g P (1080 kcal) + 1.5g/kg * 90 = 135g F (1215 kcal)
      // = 2295 kcal for a 2000 kcal target.
      final macros = computeMacros(
        calories: 2000,
        proteinPerKg: 3,
        fatPerKg: 1.5,
        weightKg: 90,
      );
      expect(macros.energyConflict, isTrue);
      expect(macros.carbsG, 0);
      expect(macros.carbsRounded, 0);
    });

    test('carbs land exactly on zero without conflict at the boundary', () {
      // 200g P (800) + 100g F (900) = 1700; kcal 1700 → carbs = 0, no conflict.
      final macros = computeMacros(
        calories: 1700,
        proteinPerKg: 2,
        fatPerKg: 1,
        weightKg: 100,
      );
      expect(macros.energyConflict, isFalse);
      expect(macros.carbsG, 0);
    });

    test('rounds grams to integers and exposes rounded getters', () {
      final macros = computeMacros(
        calories: 2100.4,
        proteinPerKg: 1.85,
        fatPerKg: 0.95,
        weightKg: 82.3,
      );
      expect(macros.proteinRounded, macros.proteinG.round());
      expect(macros.fatRounded, macros.fatG.round());
      expect(macros.carbsRounded, macros.carbsG.round());
      expect(macros.proteinG, macros.proteinG.roundToDouble());
    });

    test('rejects non-positive inputs', () {
      expect(
        () => computeMacros(
          calories: 0,
          proteinPerKg: 2,
          fatPerKg: 1,
          weightKg: 80,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeMacros(
          calories: 2000,
          proteinPerKg: -1,
          fatPerKg: 1,
          weightKg: 80,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeMacros(
          calories: 2000,
          proteinPerKg: 2,
          fatPerKg: 0,
          weightKg: 80,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeMacros(
          calories: 2000,
          proteinPerKg: 2,
          fatPerKg: 1,
          weightKg: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
