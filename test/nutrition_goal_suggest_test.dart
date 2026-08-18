import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

void main() {
  group('suggestNutritionGoal (Mifflin-St Jeor, maintenance-only)', () {
    test('BMR matches the formula for males', () {
      // 10*80 + 6.25*175 - 5*30 + 5 = 800 + 1093.75 - 150 + 5 = 1748.75
      final suggestion = suggestNutritionGoal(
        weightKg: 80,
        heightCm: 175,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.moderate,
      );
      expect(suggestion.bmr, 1749);
    });

    test('BMR uses the -161 adjustment for females', () {
      final male = suggestNutritionGoal(
        weightKg: 60,
        heightCm: 165,
        ageYears: 25,
        isMale: true,
        activity: ActivityLevel.moderate,
      );
      final female = suggestNutritionGoal(
        weightKg: 60,
        heightCm: 165,
        ageYears: 25,
        isMale: false,
        activity: ActivityLevel.moderate,
      );
      expect(female.bmr, male.bmr - 166);
    });

    test('TDEE scales BMR by the activity factor', () {
      const bmrRaw = 10 * 70 + 6.25 * 170 - 5 * 30 + 5; // 1617.5
      final sedentary = suggestNutritionGoal(
        weightKg: 70,
        heightCm: 170,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.sedentary,
      );
      final active = suggestNutritionGoal(
        weightKg: 70,
        heightCm: 170,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.active,
      );
      expect(sedentary.bmr, bmrRaw.roundToDouble());
      expect(sedentary.tdee, (bmrRaw * 1.2).roundToDouble());
      expect(active.tdee, (bmrRaw * 1.725).roundToDouble());
      expect(active.tdee, greaterThan(sedentary.tdee));
    });

    test('always returns maintenance: goal calories equal the TDEE', () {
      final suggestion = suggestNutritionGoal(
        weightKg: 75,
        heightCm: 180,
        ageYears: 28,
        isMale: true,
        activity: ActivityLevel.moderate,
      );
      expect(suggestion.calories, suggestion.tdee);
      expect(suggestion.tdee, greaterThan(suggestion.bmr));
    });

    test('macro split: protein and fat follow g/kg, carbs absorb the rest', () {
      final suggestion = suggestNutritionGoal(
        weightKg: 80,
        heightCm: 175,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.moderate,
      );
      // Maintenance defaults: 1.8 g/kg protein, 1.0 g/kg fat.
      expect(suggestion.proteinG, (80 * 1.8).roundToDouble());
      expect(suggestion.fatG, (80 * 1.0).roundToDouble());
      final expectedCarbs =
          ((suggestion.calories -
                      suggestion.proteinG * 4 -
                      suggestion.fatG * 9) /
                  4)
              .clamp(0, double.infinity)
              .roundToDouble();
      expect(suggestion.carbsG, expectedCarbs);
    });

    test('custom macro ratios override the defaults', () {
      final suggestion = suggestNutritionGoal(
        weightKg: 80,
        heightCm: 175,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.moderate,
        macroRatios: const NutritionMacroRatios(
          proteinPerKg: 2.1,
          fatPerKg: 0.7,
        ),
      );

      expect(suggestion.proteinG, 168);
      expect(suggestion.fatG, 56);
      expect(
        suggestion.carbsG,
        ((suggestion.calories - 168 * 4 - 56 * 9) / 4).roundToDouble(),
      );
    });

    test('rejects non-positive custom macro ratios', () {
      expect(
        () => suggestNutritionGoal(
          weightKg: 80,
          heightCm: 175,
          ageYears: 30,
          isMale: true,
          activity: ActivityLevel.moderate,
          macroRatios: const NutritionMacroRatios(proteinPerKg: 0, fatPerKg: 1),
        ),
        throwsArgumentError,
      );
    });

    test('carbs never go negative even for a heavy fat/protein split', () {
      final suggestion = suggestNutritionGoal(
        weightKg: 120,
        heightCm: 160,
        ageYears: 60,
        isMale: false,
        activity: ActivityLevel.sedentary,
      );
      expect(suggestion.carbsG, greaterThanOrEqualTo(0));
    });

    test('rejects non-positive inputs', () {
      expect(
        () => suggestNutritionGoal(
          weightKg: 0,
          heightCm: 170,
          ageYears: 30,
          isMale: true,
          activity: ActivityLevel.moderate,
        ),
        throwsArgumentError,
      );
      expect(
        () => suggestNutritionGoal(
          weightKg: 70,
          heightCm: -10,
          ageYears: 30,
          isMale: true,
          activity: ActivityLevel.moderate,
        ),
        throwsArgumentError,
      );
    });
  });

  group('NutritionAdjustment', () {
    test('defaults keep the cut/maintenance/bulk presets', () {
      expect(NutritionAdjustment.defaultsFor(NutritionObjective.cut).percent,
          -20);
      expect(
        NutritionAdjustment.defaultsFor(NutritionObjective.maintenance).percent,
        0,
      );
      expect(
        NutritionAdjustment.defaultsFor(NutritionObjective.bulk).percent,
        10,
      );
    });

    test('kind is derived from the percent sign', () {
      expect(
        NutritionAdjustment.kindForPercent(-15),
        NutritionObjective.cut,
      );
      expect(
        NutritionAdjustment.kindForPercent(0),
        NutritionObjective.maintenance,
      );
      expect(NutritionAdjustment.kindForPercent(12.5), NutritionObjective.bulk);
    });
  });
}
