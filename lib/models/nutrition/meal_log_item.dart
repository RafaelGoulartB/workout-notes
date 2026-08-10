import 'dart:convert';

import 'nutrition_values.dart';

/// Immutable snapshot of a [Food]/[FoodVariant] at the moment the user
/// logged it. Stored as JSON on the [MealLogItem] row so that future
/// edits to the food cache never change past meals.
class NutritionSnapshot {
  static const int currentVersion = 1;

  final int version;
  final String source;
  final String externalId;
  final String foodName;
  final String? foodBrand;
  final String? variantLabel;
  final double referenceAmount;
  final String referenceUnit;
  final double quantity;
  final String unit;
  final double? gramsEquivalent;
  final double? mlEquivalent;
  final NutritionValues consumed;
  final bool isEstimated;
  final bool hasMissingValues;

  const NutritionSnapshot({
    required this.version,
    required this.source,
    required this.externalId,
    required this.foodName,
    required this.foodBrand,
    required this.variantLabel,
    required this.referenceAmount,
    required this.referenceUnit,
    required this.quantity,
    required this.unit,
    required this.gramsEquivalent,
    required this.mlEquivalent,
    required this.consumed,
    required this.isEstimated,
    required this.hasMissingValues,
  });

  Map<String, dynamic> toMap() => {
    'version': version,
    'source': source,
    'external_id': externalId,
    'food_name': foodName,
    'food_brand': foodBrand,
    'variant_label': variantLabel,
    'reference_amount': referenceAmount,
    'reference_unit': referenceUnit,
    'quantity': quantity,
    'unit': unit,
    'grams_equivalent': gramsEquivalent,
    'ml_equivalent': mlEquivalent,
    'consumed': consumed.toMap(),
    'is_estimated': isEstimated,
    'has_missing_values': hasMissingValues,
  };

  factory NutritionSnapshot.fromMap(Map<String, dynamic> map) {
    final rawConsumed = map['consumed'];
    final consumed = rawConsumed is Map<String, dynamic>
        ? NutritionValues.fromMap(rawConsumed)
        : rawConsumed is Map
        ? NutritionValues.fromMap(rawConsumed.cast<String, dynamic>())
        : NutritionValues.empty;
    return NutritionSnapshot(
      version: (map['version'] as int?) ?? currentVersion,
      source: map['source'] as String,
      externalId: map['external_id'] as String,
      foodName: map['food_name'] as String,
      foodBrand: map['food_brand'] as String?,
      variantLabel: map['variant_label'] as String?,
      referenceAmount: (map['reference_amount'] as num).toDouble(),
      referenceUnit: map['reference_unit'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      gramsEquivalent: (map['grams_equivalent'] as num?)?.toDouble(),
      mlEquivalent: (map['ml_equivalent'] as num?)?.toDouble(),
      consumed: consumed,
      isEstimated: (map['is_estimated'] as bool?) ?? false,
      hasMissingValues: (map['has_missing_values'] as bool?) ?? false,
    );
  }

  String encode() => jsonEncode(toMap());

  static NutritionSnapshot decode(String raw) =>
      NutritionSnapshot.fromMap(jsonDecode(raw) as Map<String, dynamic>);
}

/// One consumed item in a [MealLog].
///
/// The numeric nutritional columns ([calories], [proteinG], ...) are
/// denormalised for fast aggregation and **must** always match
/// [snapshot.consumed]. [snapshotJson] is the source of truth used to
/// preserve the meal even when the underlying food is edited or
/// deleted.
class MealLogItem {
  final String id;
  final String mealLogId;
  final String? foodId;
  final String? foodVariantId;
  final String foodNameSnapshot;
  final String? brandSnapshot;
  final double quantity;
  final String unit;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sugarsG;
  final double? sodiumMg;
  final String snapshotJson;
  final DateTime createdAt;

  const MealLogItem({
    required this.id,
    required this.mealLogId,
    this.foodId,
    this.foodVariantId,
    required this.foodNameSnapshot,
    this.brandSnapshot,
    required this.quantity,
    required this.unit,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sugarsG,
    this.sodiumMg,
    required this.snapshotJson,
    required this.createdAt,
  });

  NutritionSnapshot get snapshot => NutritionSnapshot.decode(snapshotJson);

  NutritionValues get values => NutritionValues(
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    fiberG: fiberG,
    sugarsG: sugarsG,
    sodiumMg: sodiumMg,
  );

  bool get hasMissingValues => snapshot.hasMissingValues;

  bool get isEstimated => snapshot.isEstimated;

  MealLogItem copyWith({
    String? id,
    String? mealLogId,
    Object? foodId = _sentinel,
    Object? foodVariantId = _sentinel,
    String? foodNameSnapshot,
    Object? brandSnapshot = _sentinel,
    double? quantity,
    String? unit,
    Object? calories = _sentinel,
    Object? proteinG = _sentinel,
    Object? carbsG = _sentinel,
    Object? fatG = _sentinel,
    Object? fiberG = _sentinel,
    Object? sugarsG = _sentinel,
    Object? sodiumMg = _sentinel,
    String? snapshotJson,
    DateTime? createdAt,
  }) {
    return MealLogItem(
      id: id ?? this.id,
      mealLogId: mealLogId ?? this.mealLogId,
      foodId: identical(foodId, _sentinel) ? this.foodId : foodId as String?,
      foodVariantId: identical(foodVariantId, _sentinel)
          ? this.foodVariantId
          : foodVariantId as String?,
      foodNameSnapshot: foodNameSnapshot ?? this.foodNameSnapshot,
      brandSnapshot: identical(brandSnapshot, _sentinel)
          ? this.brandSnapshot
          : brandSnapshot as String?,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      calories: identical(calories, _sentinel)
          ? this.calories
          : calories as double?,
      proteinG: identical(proteinG, _sentinel)
          ? this.proteinG
          : proteinG as double?,
      carbsG: identical(carbsG, _sentinel) ? this.carbsG : carbsG as double?,
      fatG: identical(fatG, _sentinel) ? this.fatG : fatG as double?,
      fiberG: identical(fiberG, _sentinel) ? this.fiberG : fiberG as double?,
      sugarsG: identical(sugarsG, _sentinel)
          ? this.sugarsG
          : sugarsG as double?,
      sodiumMg: identical(sodiumMg, _sentinel)
          ? this.sodiumMg
          : sodiumMg as double?,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'meal_log_id': mealLogId,
    'food_id': foodId,
    'food_variant_id': foodVariantId,
    'food_name_snapshot': foodNameSnapshot,
    'brand_snapshot': brandSnapshot,
    'quantity': quantity,
    'unit': unit,
    'calories': calories,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'fiber_g': fiberG,
    'sugars_g': sugarsG,
    'sodium_mg': sodiumMg,
    'nutrition_snapshot_json': snapshotJson,
    'created_at': createdAt.toIso8601String(),
  };

  factory MealLogItem.fromMap(Map<String, dynamic> map) {
    return MealLogItem(
      id: map['id'] as String,
      mealLogId: map['meal_log_id'] as String,
      foodId: map['food_id'] as String?,
      foodVariantId: map['food_variant_id'] as String?,
      foodNameSnapshot: map['food_name_snapshot'] as String,
      brandSnapshot: map['brand_snapshot'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      calories: (map['calories'] as num?)?.toDouble(),
      proteinG: (map['protein_g'] as num?)?.toDouble(),
      carbsG: (map['carbs_g'] as num?)?.toDouble(),
      fatG: (map['fat_g'] as num?)?.toDouble(),
      fiberG: (map['fiber_g'] as num?)?.toDouble(),
      sugarsG: (map['sugars_g'] as num?)?.toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      snapshotJson: map['nutrition_snapshot_json'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

const Object _sentinel = Object();
