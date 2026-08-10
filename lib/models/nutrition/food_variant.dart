import 'dart:convert';

import 'nutrition_values.dart';

/// A nutritional variant of a [Food].
///
/// Nutrients are stated for [referenceAmount] of [referenceUnit] (e.g.
/// 100 g, 1 serving, 1 unit). The actual consumed values are computed
/// by the repository from the quantity and unit selected by the user.
class FoodVariant {
  final String id;
  final String foodId;
  final String? label;
  final double referenceAmount;
  final String referenceUnit;
  final NutritionValues values;
  final bool isEstimated;
  final Map<String, dynamic>? extraNutrients;

  const FoodVariant({
    required this.id,
    required this.foodId,
    this.label,
    required this.referenceAmount,
    required this.referenceUnit,
    this.values = NutritionValues.empty,
    this.isEstimated = false,
    this.extraNutrients,
  });

  FoodVariant copyWith({
    String? id,
    String? foodId,
    Object? label = _sentinel,
    double? referenceAmount,
    String? referenceUnit,
    NutritionValues? values,
    bool? isEstimated,
    Object? extraNutrients = _sentinel,
  }) {
    return FoodVariant(
      id: id ?? this.id,
      foodId: foodId ?? this.foodId,
      label: identical(label, _sentinel) ? this.label : label as String?,
      referenceAmount: referenceAmount ?? this.referenceAmount,
      referenceUnit: referenceUnit ?? this.referenceUnit,
      values: values ?? this.values,
      isEstimated: isEstimated ?? this.isEstimated,
      extraNutrients: identical(extraNutrients, _sentinel)
          ? this.extraNutrients
          : extraNutrients as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'food_id': foodId,
    'label': label,
    'reference_amount': referenceAmount,
    'reference_unit': referenceUnit,
    ...values.toMap(),
    'is_estimated': isEstimated ? 1 : 0,
    'extra_nutrients_json': extraNutrients == null
        ? null
        : jsonEncode(extraNutrients),
  };

  factory FoodVariant.fromMap(Map<String, dynamic> map) {
    return FoodVariant(
      id: map['id'] as String,
      foodId: map['food_id'] as String,
      label: map['label'] as String?,
      referenceAmount: (map['reference_amount'] as num).toDouble(),
      referenceUnit: map['reference_unit'] as String,
      values: NutritionValues.fromMap(map),
      isEstimated: (map['is_estimated'] as int? ?? 0) == 1,
      extraNutrients: _decodeExtra(map['extra_nutrients_json'] as String?),
    );
  }

  static Map<String, dynamic>? _decodeExtra(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FoodVariant && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

const Object _sentinel = Object();
