import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

void main() {
  group('suggestNutritionGoal (Mifflin-St Jeor)', () {
    test('BMR matches the formula for males', () {
      // 10*80 + 6.25*175 - 5*30 + 5 = 800 + 1093.75 - 150 + 5 = 1748.75
      final suggestion = suggestNutritionGoal(
        weightKg: 80,
        heightCm: 175,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.moderate,
        objective: NutritionObjective.maintenance,
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
        objective: NutritionObjective.maintenance,
      );
      final female = suggestNutritionGoal(
        weightKg: 60,
        heightCm: 165,
        ageYears: 25,
        isMale: false,
        activity: ActivityLevel.moderate,
        objective: NutritionObjective.maintenance,
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
        objective: NutritionObjective.maintenance,
      );
      final active = suggestNutritionGoal(
        weightKg: 70,
        heightCm: 170,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.active,
        objective: NutritionObjective.maintenance,
      );
      expect(sedentary.bmr, bmrRaw.roundToDouble());
      expect(sedentary.tdee, (bmrRaw * 1.2).roundToDouble());
      expect(active.tdee, (bmrRaw * 1.725).roundToDouble());
      expect(active.tdee, greaterThan(sedentary.tdee));
    });

    test('cut reduces and bulk increases the maintenance calories', () {
      const weightKg = 75.0;
      const heightCm = 180.0;
      const ageYears = 28;
      const isMale = true;
      final cut = suggestNutritionGoal(
        weightKg: weightKg,
        heightCm: heightCm,
        ageYears: ageYears,
        isMale: isMale,
        activity: ActivityLevel.moderate,
        objective: NutritionObjective.cut,
      );
      final maintain = suggestNutritionGoal(
        weightKg: weightKg,
        heightCm: heightCm,
        ageYears: ageYears,
        isMale: isMale,
        activity: ActivityLevel.moderate,
        objective: NutritionObjective.maintenance,
      );
      final bulk = suggestNutritionGoal(
        weightKg: weightKg,
        heightCm: heightCm,
        ageYears: ageYears,
        isMale: isMale,
        activity: ActivityLevel.moderate,
        objective: NutritionObjective.bulk,
      );
      expect(cut.calories, lessThan(maintain.calories));
      expect(bulk.calories, greaterThan(maintain.calories));
      expect(cut.calories, (maintain.tdee * 0.8).roundToDouble());
      expect(bulk.calories, (maintain.tdee * 1.1).roundToDouble());
    });

    test('macro split: protein and fat follow g/kg, carbs absorb the rest',
        () {
      final suggestion = suggestNutritionGoal(
        weightKg: 80,
        heightCm: 175,
        ageYears: 30,
        isMale: true,
        activity: ActivityLevel.moderate,
        objective: NutritionObjective.cut,
      );
      expect(suggestion.proteinG, (80 * 2.2).roundToDouble());
      expect(suggestion.fatG, (80 * 0.8).roundToDouble());
      final expectedCarbs =
          ((suggestion.calories - suggestion.proteinG * 4 - suggestion.fatG * 9) /
                  4)
              .clamp(0, double.infinity)
              .roundToDouble();
      expect(suggestion.carbsG, expectedCarbs);
    });

    test('carbs never go negative even for a heavy fat/protein split', () {
      final suggestion = suggestNutritionGoal(
        weightKg: 120,
        heightCm: 160,
        ageYears: 60,
        isMale: false,
        activity: ActivityLevel.sedentary,
        objective: NutritionObjective.cut,
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
          objective: NutritionObjective.maintenance,
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
          objective: NutritionObjective.maintenance,
        ),
        throwsArgumentError,
      );
    });
  });
}
