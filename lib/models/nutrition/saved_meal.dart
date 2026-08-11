import 'nutrition_values.dart';

/// A user-defined meal template (e.g. "Vitamina pós-treino").
///
/// Items reference the food cache live (food + variant + quantity), so
/// the computed nutrition always reflects the current cached values —
/// editing an ingredient in the food cache automatically "recalculates"
/// the saved meal's totals on the next read.
class SavedMeal {
  final String id;
  final String name;
  final String? mealType;
  final double portions;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SavedMeal({
    required this.id,
    required this.name,
    this.mealType,
    this.portions = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  SavedMeal copyWith({
    String? id,
    String? name,
    Object? mealType = _sentinel,
    double? portions,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SavedMeal(
      id: id ?? this.id,
      name: name ?? this.name,
      mealType: identical(mealType, _sentinel)
          ? this.mealType
          : mealType as String?,
      portions: portions ?? this.portions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'meal_type': mealType,
    'portions': portions,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory SavedMeal.fromMap(Map<String, dynamic> map) {
    return SavedMeal(
      id: map['id'] as String,
      name: map['name'] as String,
      mealType: map['meal_type'] as String?,
      portions: (map['portions'] as num?)?.toDouble() ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

/// One ingredient of a [SavedMeal]. [foodId] and [foodVariantId] may
/// be null when the cached food was deleted (FK `ON DELETE SET NULL`);
/// [foodNameSnapshot] keeps the label visible either way.
class SavedMealItem {
  final String id;
  final String savedMealId;
  final String? foodId;
  final String? foodVariantId;
  final String foodNameSnapshot;
  final String? brandSnapshot;
  final double quantity;
  final String unit;

  /// Snapshot of the exact serving selected when [unit] is `serving`.
  ///
  /// The label identifies the serving while it still exists in the food
  /// library. The equivalences keep the meal calculable if that serving is
  /// later edited or removed.
  final String? servingLabel;
  final double? servingGramsEquivalent;
  final double? servingMlEquivalent;
  final int orderIndex;

  const SavedMealItem({
    required this.id,
    required this.savedMealId,
    this.foodId,
    this.foodVariantId,
    required this.foodNameSnapshot,
    this.brandSnapshot,
    required this.quantity,
    required this.unit,
    this.servingLabel,
    this.servingGramsEquivalent,
    this.servingMlEquivalent,
    this.orderIndex = 0,
  });

  SavedMealItem copyWith({
    String? id,
    String? savedMealId,
    Object? foodId = _sentinel,
    Object? foodVariantId = _sentinel,
    String? foodNameSnapshot,
    Object? brandSnapshot = _sentinel,
    double? quantity,
    String? unit,
    Object? servingLabel = _sentinel,
    Object? servingGramsEquivalent = _sentinel,
    Object? servingMlEquivalent = _sentinel,
    int? orderIndex,
  }) {
    return SavedMealItem(
      id: id ?? this.id,
      savedMealId: savedMealId ?? this.savedMealId,
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
      servingLabel: identical(servingLabel, _sentinel)
          ? this.servingLabel
          : servingLabel as String?,
      servingGramsEquivalent: identical(servingGramsEquivalent, _sentinel)
          ? this.servingGramsEquivalent
          : servingGramsEquivalent as double?,
      servingMlEquivalent: identical(servingMlEquivalent, _sentinel)
          ? this.servingMlEquivalent
          : servingMlEquivalent as double?,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'saved_meal_id': savedMealId,
    'food_id': foodId,
    'food_variant_id': foodVariantId,
    'food_name_snapshot': foodNameSnapshot,
    'brand_snapshot': brandSnapshot,
    'quantity': quantity,
    'unit': unit,
    'serving_label': servingLabel,
    'serving_grams_equivalent': servingGramsEquivalent,
    'serving_ml_equivalent': servingMlEquivalent,
    'order_index': orderIndex,
  };

  factory SavedMealItem.fromMap(Map<String, dynamic> map) {
    return SavedMealItem(
      id: map['id'] as String,
      savedMealId: map['saved_meal_id'] as String,
      foodId: map['food_id'] as String?,
      foodVariantId: map['food_variant_id'] as String?,
      foodNameSnapshot: map['food_name_snapshot'] as String,
      brandSnapshot: map['brand_snapshot'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String,
      servingLabel: map['serving_label'] as String?,
      servingGramsEquivalent: (map['serving_grams_equivalent'] as num?)
          ?.toDouble(),
      servingMlEquivalent: (map['serving_ml_equivalent'] as num?)?.toDouble(),
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A [SavedMeal] with its ingredients and the computed nutrition totals.
/// [totals] is null when the meal has no items; [consumedByItem] maps
/// each item id to its live-computed values for list/editor display.
class SavedMealWithItems {
  final SavedMeal meal;
  final List<SavedMealItem> items;
  final NutritionValues? totals;
  final Map<String, NutritionValues> consumedByItem;

  const SavedMealWithItems({
    required this.meal,
    this.items = const [],
    this.totals,
    this.consumedByItem = const {},
  });
}

const Object _sentinel = Object();
