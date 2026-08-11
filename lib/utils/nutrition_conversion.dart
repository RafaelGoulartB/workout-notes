import 'package:workout_notes/models/nutrition/food_serving.dart';
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

    final normalizedUnit = normalizeUnit(unit);
    final normalizedRef = normalizeUnit(referenceUnit);

    if (normalizedUnit == 'g' && normalizedRef == 'g') {
      return quantity / referenceAmount;
    }
    if (normalizedUnit == 'ml' && normalizedRef == 'ml') {
      return quantity / referenceAmount;
    }

    // Direct match of free units (e.g. "fatia" == "fatia", or a
    // per-serving/per-unit reference unit): no conversion needed.
    // Must run before the serving branch, which only applies when
    // the reference is expressed in grams/millilitres.
    if (normalizedUnit == normalizedRef) {
      return quantity / referenceAmount;
    }

    // Serving / unit case: requires an explicit equivalence.
    if (normalizedUnit == 'serving' || normalizedUnit == 'unit') {
      final serving = this.serving;
      if (serving == null) {
        throw NutritionConversionException('serving_equivalence_missing');
      }
      if (normalizedRef == 'g') {
        if (serving.hasGramConversion) {
          final grams = quantity * serving.gramsEquivalent!;
          return grams / referenceAmount;
        }
        final inferred = _inferFromLabel(serving.label, 'g');
        if (inferred != null) {
          final grams = quantity * inferred;
          return grams / referenceAmount;
        }
        throw NutritionConversionException('grams_equivalence_missing');
      }
      if (normalizedRef == 'ml') {
        if (serving.hasMlConversion) {
          final ml = quantity * serving.mlEquivalent!;
          return ml / referenceAmount;
        }
        final inferred = _inferFromLabel(serving.label, 'ml');
        if (inferred != null) {
          final ml = quantity * inferred;
          return ml / referenceAmount;
        }
        throw NutritionConversionException('ml_equivalence_missing');
      }
      throw NutritionConversionException('unsupported_reference_unit');
    }

    throw NutritionConversionException('unsupported_unit_combination');
  }

  /// Best-effort fallback: when a serving has no explicit
  /// [FoodServing.gramsEquivalent] / [FoodServing.mlEquivalent] for
  /// the current reference unit, try to read the value out of the
  /// serving's free-form label (e.g. "250 ml", "1 fatia · 30 g").
  /// This handles the common case where the source data lists only
  /// one of the two equivalences (e.g. a Coca-Cola can that stores
  /// `gramsEquivalent: 250` but whose label clearly reads "250 ml").
  ///
  /// Returns null when no confident match is found, in which case the
  /// caller surfaces the usual `*_equivalence_missing` error.
  static double? _inferFromLabel(String label, String refUnit) {
    return inferEquivalenceFromLabel(label, refUnit);
  }

  /// Public version of [_inferFromLabel] so the UI can preview the
  /// inferred value on serving chips (e.g. "250 ml · ~250 ml") before
  /// the user taps one.
  static double? inferEquivalenceFromLabel(String label, String refUnit) {
    final haystack = label.toLowerCase();
    final needle = refUnit.toLowerCase();
    // Match "<number> <unit>" or "<unit> <number>" so labels like
    // "250 ml", "250ml", "ml 250" all work.
    final patterns = <RegExp>[
      RegExp(r'(\d+(?:[.,]\d+)?)\s*' + RegExp.escape(needle) + r'\b'),
      RegExp(r'\b' + RegExp.escape(needle) + r'\s*(\d+(?:[.,]\d+)?)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(haystack);
      if (match == null) continue;
      final raw = match.group(1);
      if (raw == null) continue;
      final value = double.tryParse(raw.replaceAll(',', '.'));
      if (value != null && value > 0 && value.isFinite) {
        return value;
      }
    }
    return null;
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
      saturatedFatG: _scale(reference.saturatedFatG, multiplier),
      monounsaturatedFatG: _scale(reference.monounsaturatedFatG, multiplier),
      polyunsaturatedFatG: _scale(reference.polyunsaturatedFatG, multiplier),
      transFatG: _scale(reference.transFatG, multiplier),
      fiberG: _scale(reference.fiberG, multiplier),
      sugarsG: _scale(reference.sugarsG, multiplier),
      sodiumMg: _scale(reference.sodiumMg, multiplier),
      potassiumMg: _scale(reference.potassiumMg, multiplier),
      calciumMg: _scale(reference.calciumMg, multiplier),
      ironMg: _scale(reference.ironMg, multiplier),
      magnesiumMg: _scale(reference.magnesiumMg, multiplier),
      zincMg: _scale(reference.zincMg, multiplier),
      vitaminAUg: _scale(reference.vitaminAUg, multiplier),
      vitaminCMg: _scale(reference.vitaminCMg, multiplier),
      vitaminDUg: _scale(reference.vitaminDUg, multiplier),
      vitaminB12Ug: _scale(reference.vitaminB12Ug, multiplier),
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

  /// Normalizes a unit string to a canonical token (e.g. "gramas" → "g",
  /// "porção" → "serving", "unidade" → "unit"). Unknown units are
  /// returned lower-cased and trimmed so they can participate in
  /// direct (unit == reference unit) matches.
  static String normalizeUnit(String unit) {
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
}

class NutritionConversionException implements Exception {
  final String code;

  const NutritionConversionException(this.code);

  @override
  String toString() => 'NutritionConversionException($code)';
}
