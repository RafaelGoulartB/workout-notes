/// Macros and key micronutrients for a reference amount.
///
/// Nullable fields are intentional: they represent **unknown** values,
/// not zero. A `null` field means the data source did not report a
/// value; a `0` means the value was reported as exactly zero. This
/// distinction is preserved through the database, snapshots and
/// the user interface so the daily summary can flag incomplete
/// information.
class NutritionValues {
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sugarsG;
  final double? sodiumMg;

  const NutritionValues({
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sugarsG,
    this.sodiumMg,
  });

  /// Returns a new instance with the same non-null values of [other]
  /// overriding the receiver's matching fields. Null fields in [other]
  /// are skipped.
  NutritionValues merge(NutritionValues other) {
    return NutritionValues(
      calories: other.calories ?? calories,
      proteinG: other.proteinG ?? proteinG,
      carbsG: other.carbsG ?? carbsG,
      fatG: other.fatG ?? fatG,
      fiberG: other.fiberG ?? fiberG,
      sugarsG: other.sugarsG ?? sugarsG,
      sodiumMg: other.sodiumMg ?? sodiumMg,
    );
  }

  /// True when at least the four core macros (calories, protein, carbs,
  /// fat) are present.
  bool get hasCoreMacros =>
      calories != null && proteinG != null && carbsG != null && fatG != null;

  /// True when any field is null. Used to flag incomplete data in the UI.
  bool get hasMissingFields =>
      calories == null || proteinG == null || carbsG == null || fatG == null;

  /// All-null instance used when the data source cannot provide any
  /// nutrition values for a food.
  static const empty = NutritionValues();

  Map<String, dynamic> toMap() => {
    'calories': calories,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'fiber_g': fiberG,
    'sugars_g': sugarsG,
    'sodium_mg': sodiumMg,
  };

  factory NutritionValues.fromMap(Map<String, dynamic> map) {
    return NutritionValues(
      calories: _toDouble(map['calories']),
      proteinG: _toDouble(map['protein_g']),
      carbsG: _toDouble(map['carbs_g']),
      fatG: _toDouble(map['fat_g']),
      fiberG: _toDouble(map['fiber_g']),
      sugarsG: _toDouble(map['sugars_g']),
      sodiumMg: _toDouble(map['sodium_mg']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  NutritionValues copyWith({
    Object? calories = _sentinel,
    Object? proteinG = _sentinel,
    Object? carbsG = _sentinel,
    Object? fatG = _sentinel,
    Object? fiberG = _sentinel,
    Object? sugarsG = _sentinel,
    Object? sodiumMg = _sentinel,
  }) {
    return NutritionValues(
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
    );
  }
}

const Object _sentinel = Object();
