import 'nutrition_values.dart';

/// One serving extracted from a nutrition label photo.
class AiFoodLabelServingDraft {
  final String label;
  final double quantity;
  final String unit;
  final double? gramsEquivalent;

  const AiFoodLabelServingDraft({
    required this.label,
    this.quantity = 1,
    required this.unit,
    this.gramsEquivalent,
  });

  factory AiFoodLabelServingDraft.fromJson(Map<String, dynamic> json) {
    return AiFoodLabelServingDraft(
      label: _nullableString(json['label']) ?? '',
      quantity: _nonNegativeDouble(json['quantity']) ?? 1,
      unit: _nullableString(json['unit']) ?? '',
      gramsEquivalent: _nonNegativeDouble(json['grams_equivalent']),
    );
  }
}

/// Food identified by the AI from a nutrition label photo. Values refer
/// to [referenceAmount] of [referenceUnit] (normally 100 g).
class AiFoodLabelDraft {
  final String name;
  final String? brand;
  final String? barcode;
  final double referenceAmount;
  final String referenceUnit;
  final NutritionValues values;
  final List<AiFoodLabelServingDraft> servings;

  const AiFoodLabelDraft({
    required this.name,
    this.brand,
    this.barcode,
    this.referenceAmount = 100,
    this.referenceUnit = 'g',
    this.values = NutritionValues.empty,
    this.servings = const [],
  });

  factory AiFoodLabelDraft.fromJson(Map<String, dynamic> json) {
    final name = _nullableString(json['name']) ?? '';
    if (name.isEmpty) {
      throw const FormatException('missing food name');
    }
    final per = json['per'];
    final values = per is Map
        ? NutritionValues(
            calories: _nonNegativeDouble(per['calories']),
            proteinG: _nonNegativeDouble(per['protein_g']),
            carbsG: _nonNegativeDouble(per['carbs_g']),
            fatG: _nonNegativeDouble(per['fat_g']),
            fiberG: _nonNegativeDouble(per['fiber_g']),
            sugarsG: _nonNegativeDouble(per['sugars_g']),
            sodiumMg: _nonNegativeDouble(per['sodium_mg']),
            potassiumMg: _nonNegativeDouble(per['potassium_mg']),
            calciumMg: _nonNegativeDouble(per['calcium_mg']),
            ironMg: _nonNegativeDouble(per['iron_mg']),
            magnesiumMg: _nonNegativeDouble(per['magnesium_mg']),
            zincMg: _nonNegativeDouble(per['zinc_mg']),
            vitaminAUg: _nonNegativeDouble(per['vitamin_a_ug']),
            vitaminCMg: _nonNegativeDouble(per['vitamin_c_mg']),
            vitaminDUg: _nonNegativeDouble(per['vitamin_d_ug']),
            vitaminB12Ug: _nonNegativeDouble(per['vitamin_b12_ug']),
          )
        : NutritionValues.empty;
    final servings = <AiFoodLabelServingDraft>[];
    final rawServings = json['servings'];
    if (rawServings is List) {
      for (final item in rawServings) {
        if (item is Map) {
          try {
            servings.add(
              AiFoodLabelServingDraft.fromJson(item.cast<String, dynamic>()),
            );
          } catch (_) {}
        }
      }
    }
    final unit = _nullableString(json['reference_unit']) ?? 'g';
    return AiFoodLabelDraft(
      name: name,
      brand: _nullableString(json['brand']),
      barcode: _nullableString(json['barcode']),
      referenceAmount: _nonNegativeDouble(json['reference_amount']) ?? 100,
      referenceUnit: unit,
      values: values,
      servings: servings,
    );
  }
}

double? _nonNegativeDouble(dynamic value) {
  if (value == null) return null;
  double? parsed;
  if (value is num) {
    parsed = value.toDouble();
  } else if (value is String) {
    parsed = double.tryParse(value.trim().replaceAll(',', '.'));
  }
  if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
    return null;
  }
  return parsed;
}

String? _nullableString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
