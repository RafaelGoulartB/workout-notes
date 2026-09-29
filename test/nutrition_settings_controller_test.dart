import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/screens/workout/nutrition_settings_controller.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

void main() {
  group('resolveCarbs', () {
    test('carbs absorb the energy left by protein and fat', () {
      // 2500 kcal * 0.8 = 2000 kcal; (2000 - 150*4 - 60*9) / 4 = 215.
      expect(
        NutritionSettingsController.resolveCarbs(
          tdee: 2500,
          adjustmentPercent: -20,
          proteinG: 150,
          fatG: 60,
          carbsG: 999,
        ),
        215,
      );
    });

    test('never goes negative', () {
      expect(
        NutritionSettingsController.resolveCarbs(
          tdee: 1200,
          adjustmentPercent: -30,
          proteinG: 200,
          fatG: 100,
          carbsG: 50,
        ),
        0,
      );
    });

    test('keeps the given carbs when the goal cannot be derived', () {
      expect(
        NutritionSettingsController.resolveCarbs(
          tdee: null,
          adjustmentPercent: 0,
          proteinG: 150,
          fatG: 60,
          carbsG: 180,
        ),
        180,
      );
      expect(
        NutritionSettingsController.resolveCarbs(
          tdee: 2500,
          adjustmentPercent: 0,
          proteinG: null,
          fatG: 60,
          carbsG: 180,
        ),
        180,
      );
    });
  });

  group('formatting', () {
    test('numbers drop a trailing zero decimal', () {
      expect(NutritionSettingsController.formatNum(2000), '2000');
      expect(NutritionSettingsController.formatNum(72.5), '72.5');
    });

    test('percent labels are signed only when positive', () {
      expect(NutritionSettingsController.formatPercent(15), '+15%');
      expect(NutritionSettingsController.formatPercent(-15), '-15%');
      expect(NutritionSettingsController.formatPercent(0), '0%');
    });

    test('unknown adjustment kinds fall back to maintenance', () {
      expect(
        NutritionSettingsController.parseAdjustmentKind('bulk'),
        NutritionObjective.bulk,
      );
      expect(
        NutritionSettingsController.parseAdjustmentKind('nonsense'),
        NutritionObjective.maintenance,
      );
    });
  });
}
