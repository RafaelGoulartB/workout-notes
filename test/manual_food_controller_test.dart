import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/manual_food_controller.dart';

void main() {
  group('parseDouble', () {
    test('accepts comma decimals and trims', () {
      expect(ManualFoodController.parseDouble(' 12,5 ', null), 12.5);
    });

    test('blank and unparsable input use the fallback', () {
      expect(ManualFoodController.parseDouble('', 100), 100);
      expect(ManualFoodController.parseDouble('abc', 7), 7);
      expect(ManualFoodController.parseDouble('', null), isNull);
    });

    test('negative numbers are rejected as null', () {
      expect(ManualFoodController.parseDouble('-3', 100), isNull);
    });
  });

  test('amounts drop decimals only when whole', () {
    expect(ManualFoodController.formatAmount(100), '100');
    expect(ManualFoodController.formatAmount(2.5), '2.50');
  });

  group('form state', () {
    late ManualFoodController form;

    setUp(() {
      form = ManualFoodController(repository: NutritionRepository());
    });

    tearDown(() => form.dispose());

    test('adds and removes serving rows', () {
      var notified = 0;
      form.addListener(() => notified++);
      form.addServing();
      form.addServing();
      expect(form.servings, hasLength(2));
      form.removeServing(0);
      expect(form.servings, hasLength(1));
      expect(notified, 3);
    });

    test('fat sub-types may not exceed total fat', () {
      // Nothing to compare against without a total.
      form.saturatedFatController.text = '30';
      expect(form.fatBreakdownExceedsTotal, isFalse);

      form.fatController.text = '20';
      expect(form.fatBreakdownExceedsTotal, isTrue);

      form.saturatedFatController.text = '12';
      form.transFatController.text = '8,05';
      // 20.05 is inside the 0.1 tolerance.
      expect(form.fatBreakdownExceedsTotal, isFalse);
    });

    test('hasAnyText looks only at non-blank fields', () {
      expect(
        ManualFoodController.hasAnyText(form.fatBreakdownControllers),
        false,
      );
      form.zincController.text = '  ';
      expect(ManualFoodController.hasAnyText([form.zincController]), isFalse);
      form.zincController.text = '1';
      expect(ManualFoodController.hasAnyText([form.zincController]), isTrue);
    });
  });
}
