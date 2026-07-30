import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';

/// Validation/calculation helpers for nutrition conversions.
///
/// The MVP allows four consumption unit categories: grams, millilitres,
/// serving (or "unit"). Conversions are only allowed when:
///   * grams ⇄ grams reference (no conversion needed)
///   * millilitres ⇄ millilitres reference (no conversion needed)
///   * serving/units that the source/model provided an explicit
///     `grams_equivalent` or `ml_equivalent` for.
///   * the unit itself matches the reference unit (1:1 case).
///
/// We never fabricate equivalencies and never assume a portion
/// equals 100 g.
class NutritionConversion {
  final double quantity;
  final String unit;
  final double referenceAmount;
  final String referenceUnit;
  final FoodServing? serving;

  const NutritionConversion({
    required this.quantity,
    required this.unit,
    required this.referenceAmount,
    required this.referenceUnit,
    this.serving,
  });

  /// Computes the multiplier applied to the reference nutrition
  /// values. Throws [NutritionConversionException] when the unit
  /// cannot be converted.
  double resolveMultiplier() {
    if (quantity <= 0) {
      throw NutritionConversionException('quantity_must_be_positive');
    }
    if (referenceAmount <= 0) {
      throw NutritionConversionException('reference_amount_must_be_positive');
    }
    if (_isInvalidNumber(quantity) || _isInvalidNumber(referenceAmount)) {
      throw NutritionConversionException('invalid_numeric_value');
    }

    final normalizedUnit = _normalizeUnit(unit);
    final normalizedRef = _normalizeUnit(referenceUnit);

    if (normalizedUnit == 'g' && normalizedRef == 'g') {
      return quantity / referenceAmount;
    }
    if (normalizedUnit == 'ml' && normalizedRef == 'ml') {
      return quantity / referenceAmount;
    }

    // Serving / unit case: requires an explicit equivalence.
    if (normalizedUnit == 'serving' || normalizedUnit == 'unit') {
      final serving = this.serving;
      if (serving == null) {
        throw NutritionConversionException('serving_equivalence_missing');
      }
      if (normalizedRef == 'g') {
        if (!serving.hasGramConversion) {
          throw NutritionConversionException('grams_equivalence_missing');
        }
        final grams = quantity * serving.gramsEquivalent!;
        return grams / referenceAmount;
      }
      if (normalizedRef == 'ml') {
        if (!serving.hasMlConversion) {
          throw NutritionConversionException('ml_equivalence_missing');
        }
        final ml = quantity * serving.mlEquivalent!;
        return ml / referenceAmount;
      }
      throw NutritionConversionException('unsupported_reference_unit');
    }

    // Direct match of free units (e.g. "fatia" == "fatia").
    if (normalizedUnit == normalizedRef) {
      return quantity / referenceAmount;
    }

    throw NutritionConversionException('unsupported_unit_combination');
  }

  /// Computes the consumed nutrition values for this conversion.
  /// Throws when the conversion cannot be performed.
  NutritionValues apply(NutritionValues reference) {
    final multiplier = resolveMultiplier();
    if (_isInvalidNumber(multiplier)) {
      throw NutritionConversionException('invalid_multiplier');
    }
    return NutritionValues(
      calories: _scale(reference.calories, multiplier),
      proteinG: _scale(reference.proteinG, multiplier),
      carbsG: _scale(reference.carbsG, multiplier),
      fatG: _scale(reference.fatG, multiplier),
      fiberG: _scale(reference.fiberG, multiplier),
      sugarsG: _scale(reference.sugarsG, multiplier),
      sodiumMg: _scale(reference.sodiumMg, multiplier),
    );
  }

  static double? _scale(double? value, double multiplier) {
    if (value == null) return null;
    if (value < 0) {
      throw NutritionConversionException('negative_nutrient');
    }
    final result = value * multiplier;
    if (_isInvalidNumber(result) || result < 0) {
      throw NutritionConversionException('invalid_scaled_value');
    }
    return result;
  }

  static String _normalizeUnit(String unit) {
    final trimmed = unit.trim().toLowerCase();
    switch (trimmed) {
      case 'g':
      case 'gram':
      case 'grams':
      case 'gramas':
        return 'g';
      case 'ml':
      case 'millilitre':
      case 'millilitres':
      case 'mililitro':
      case 'mililitros':
        return 'ml';
      case 'serving':
      case 'servings':
      case 'porção':
      case 'porcao':
      case 'porcoes':
      case 'porções':
      case 'serving_size':
        return 'serving';
      case 'unit':
      case 'units':
      case 'un':
      case 'unidade':
      case 'unidades':
        return 'unit';
      default:
        return trimmed;
    }
  }

  static bool _isInvalidNumber(double value) => value.isNaN || value.isInfinite;

  /// Returns the available unit categories for a given variant, based
  /// on the variant's reference unit and any serving equivalences.
  static Set<String> availableUnitsFor(FoodVariant variant) {
    final units = <String>{};
    final normalizedRef = _normalizeUnit(variant.referenceUnit);
    if (normalizedRef == 'g' || normalizedRef == 'ml') {
      units.add(normalizedRef);
    }
    return units;
  }
}

class NutritionConversionException implements Exception {
  final String code;

  const NutritionConversionException(this.code);

  @override
  String toString() => 'NutritionConversionException($code)';
}
