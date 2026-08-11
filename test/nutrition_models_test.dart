import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

void main() {
  group('Food.normalizeForSearch', () {
    test('lowercases, strips accents and collapses spaces', () {
      expect(Food.normalizeForSearch('  Pão   Integral  '), 'pao integral');
    });

    test('preserves ñ and ç equivalents after normalization', () {
      expect(Food.normalizeForSearch('Mañónça'), 'manonca');
    });
  });

  group('NutritionValues', () {
    test('treats null as unknown, not zero', () {
      const v = NutritionValues(calories: 100, proteinG: null);
      expect(v.hasMissingFields, isTrue);
    });

    test('zero is a real value, not a missing one', () {
      const v = NutritionValues(calories: 0, proteinG: 0, carbsG: 0, fatG: 0);
      expect(v.hasMissingFields, isFalse);
      expect(v.hasCoreMacros, isTrue);
    });

    test('merge keeps receiver values when other has null', () {
      const a = NutritionValues(calories: 100, proteinG: 10);
      const b = NutritionValues(calories: null, proteinG: 5);
      final merged = a.merge(b);
      expect(merged.calories, 100);
      expect(merged.proteinG, 5);
    });
  });

  group('NutritionConversion', () {
    const variant = FoodVariant(
      id: 'v1',
      foodId: 'f1',
      referenceAmount: 100,
      referenceUnit: 'g',
      values: NutritionValues(
        calories: 200,
        proteinG: 20,
        carbsG: 30,
        fatG: 10,
        saturatedFatG: 3,
        monounsaturatedFatG: 4,
        polyunsaturatedFatG: 2,
        transFatG: 0.2,
        fiberG: 5,
        sugarsG: 2,
        sodiumMg: 100,
      ),
    );

    test('computes per-gram multiplier for a 50 g portion', () {
      final conv = NutritionConversion(
        quantity: 50,
        unit: 'g',
        referenceAmount: 100,
        referenceUnit: 'g',
      );
      final result = conv.apply(variant.values);
      expect(result.calories, 100);
      expect(result.proteinG, 10);
      expect(result.carbsG, 15);
      expect(result.fatG, 5);
      expect(result.saturatedFatG, 1.5);
      expect(result.monounsaturatedFatG, 2);
      expect(result.polyunsaturatedFatG, 1);
      expect(result.transFatG, 0.1);
      expect(result.reportedFatBreakdownG, closeTo(4.6, 0.001));
    });

    test('computes per-ml multiplier for an ml-referenced variant', () {
      const mlVariant = FoodVariant(
        id: 'v2',
        foodId: 'f1',
        referenceAmount: 200,
        referenceUnit: 'ml',
        values: NutritionValues(calories: 80, proteinG: 0, carbsG: 10, fatG: 2),
      );
      final conv = NutritionConversion(
        quantity: 50,
        unit: 'ml',
        referenceAmount: 200,
        referenceUnit: 'ml',
      );
      final result = conv.apply(mlVariant.values);
      expect(result.calories, 20);
      expect(result.carbsG, closeTo(2.5, 0.0001));
    });

    test('converts a serving with an explicit gram equivalence', () {
      const serving = FoodServing(
        id: 's1',
        foodVariantId: 'v1',
        label: 'Slice',
        quantity: 1,
        unit: 'slice',
        gramsEquivalent: 30,
      );
      final conv = NutritionConversion(
        quantity: 2,
        unit: 'serving',
        referenceAmount: 100,
        referenceUnit: 'g',
        serving: serving,
      );
      final result = conv.apply(variant.values);
      // 2 slices × 30 g = 60 g → 60/100 × 200 kcal = 120 kcal
      expect(result.calories, 120);
      expect(result.proteinG, 12);
    });

    test('rejects a serving without an explicit equivalence', () {
      const serving = FoodServing(
        id: 's2',
        foodVariantId: 'v1',
        label: 'Handful',
        quantity: 1,
        unit: 'handful',
      );
      final conv = NutritionConversion(
        quantity: 1,
        unit: 'serving',
        referenceAmount: 100,
        referenceUnit: 'g',
        serving: serving,
      );
      expect(
        () => conv.apply(variant.values),
        throwsA(isA<NutritionConversionException>()),
      );
    });

    test('rejects incompatible units (g against ml reference)', () {
      final conv = NutritionConversion(
        quantity: 50,
        unit: 'g',
        referenceAmount: 200,
        referenceUnit: 'ml',
      );
      expect(
        () => conv.apply(variant.values),
        throwsA(isA<NutritionConversionException>()),
      );
    });

    test('supports free manual units via direct unit match', () {
      const sliceVariant = FoodVariant(
        id: 'vs',
        foodId: 'f1',
        referenceAmount: 1,
        referenceUnit: 'fatia',
        values: NutritionValues(calories: 80, proteinG: 4),
      );
      final conv = NutritionConversion(
        quantity: 2,
        unit: 'fatia',
        referenceAmount: 1,
        referenceUnit: 'fatia',
      );
      final result = conv.apply(sliceVariant.values);
      expect(result.calories, 160);
      expect(result.proteinG, 8);
    });

    test('supports per-unit manual units ("unidade") without a serving', () {
      const unitVariant = FoodVariant(
        id: 'vu',
        foodId: 'f1',
        referenceAmount: 1,
        referenceUnit: 'unidade',
        values: NutritionValues(calories: 50, proteinG: 2),
      );
      final conv = NutritionConversion(
        quantity: 3,
        unit: 'unidade',
        referenceAmount: 1,
        referenceUnit: 'unidade',
      );
      final result = conv.apply(unitVariant.values);
      expect(result.calories, 150);
    });

    test('rejects a custom unit against a gram reference', () {
      final conv = NutritionConversion(
        quantity: 2,
        unit: 'fatia',
        referenceAmount: 100,
        referenceUnit: 'g',
      );
      expect(
        () => conv.apply(variant.values),
        throwsA(isA<NutritionConversionException>()),
      );
    });

    test('rejects non-positive quantities and reference amounts', () {
      expect(
        () => NutritionConversion(
          quantity: 0,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ).apply(variant.values),
        throwsA(isA<NutritionConversionException>()),
      );
      expect(
        () => NutritionConversion(
          quantity: 50,
          unit: 'g',
          referenceAmount: 0,
          referenceUnit: 'g',
        ).apply(variant.values),
        throwsA(isA<NutritionConversionException>()),
      );
    });

    test('rejects NaN, infinity and negative nutrient values', () {
      const broken = FoodVariant(
        id: 'vb',
        foodId: 'f1',
        referenceAmount: 100,
        referenceUnit: 'g',
        values: NutritionValues(calories: double.nan, proteinG: 10),
      );
      expect(
        () => NutritionConversion(
          quantity: 50,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ).apply(broken.values),
        throwsA(isA<NutritionConversionException>()),
      );
      const negative = FoodVariant(
        id: 'vn',
        foodId: 'f1',
        referenceAmount: 100,
        referenceUnit: 'g',
        values: NutritionValues(calories: -10, proteinG: 1),
      );
      expect(
        () => NutritionConversion(
          quantity: 50,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ).apply(negative.values),
        throwsA(isA<NutritionConversionException>()),
      );
    });
  });
}
