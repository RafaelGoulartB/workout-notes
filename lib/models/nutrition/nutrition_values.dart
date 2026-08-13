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
  final double? saturatedFatG;
  final double? monounsaturatedFatG;
  final double? polyunsaturatedFatG;
  final double? transFatG;
  final double? fiberG;
  final double? sugarsG;
  final double? sodiumMg;
  final double? potassiumMg;
  final double? calciumMg;
  final double? ironMg;
  final double? magnesiumMg;
  final double? zincMg;
  final double? vitaminAUg;
  final double? vitaminCMg;
  final double? vitaminDUg;
  final double? vitaminB12Ug;

  const NutritionValues({
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.saturatedFatG,
    this.monounsaturatedFatG,
    this.polyunsaturatedFatG,
    this.transFatG,
    this.fiberG,
    this.sugarsG,
    this.sodiumMg,
    this.potassiumMg,
    this.calciumMg,
    this.ironMg,
    this.magnesiumMg,
    this.zincMg,
    this.vitaminAUg,
    this.vitaminCMg,
    this.vitaminDUg,
    this.vitaminB12Ug,
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
      saturatedFatG: other.saturatedFatG ?? saturatedFatG,
      monounsaturatedFatG: other.monounsaturatedFatG ?? monounsaturatedFatG,
      polyunsaturatedFatG: other.polyunsaturatedFatG ?? polyunsaturatedFatG,
      transFatG: other.transFatG ?? transFatG,
      fiberG: other.fiberG ?? fiberG,
      sugarsG: other.sugarsG ?? sugarsG,
      sodiumMg: other.sodiumMg ?? sodiumMg,
      potassiumMg: other.potassiumMg ?? potassiumMg,
      calciumMg: other.calciumMg ?? calciumMg,
      ironMg: other.ironMg ?? ironMg,
      magnesiumMg: other.magnesiumMg ?? magnesiumMg,
      zincMg: other.zincMg ?? zincMg,
      vitaminAUg: other.vitaminAUg ?? vitaminAUg,
      vitaminCMg: other.vitaminCMg ?? vitaminCMg,
      vitaminDUg: other.vitaminDUg ?? vitaminDUg,
      vitaminB12Ug: other.vitaminB12Ug ?? vitaminB12Ug,
    );
  }

  /// True when at least the four core macros (calories, protein, carbs,
  /// fat) are present.
  bool get hasCoreMacros =>
      calories != null && proteinG != null && carbsG != null && fatG != null;

  /// True when one of the primary calorie/macro fields is missing.
  /// Secondary nutrients are optional and do not make a food incomplete.
  bool get hasMissingFields =>
      calories == null || proteinG == null || carbsG == null || fatG == null;

  /// True when at least one detailed fat value was supplied.
  bool get hasFatBreakdown =>
      saturatedFatG != null ||
      monounsaturatedFatG != null ||
      polyunsaturatedFatG != null ||
      transFatG != null;

  /// Sum of the reported fat subtypes. Null means none was reported.
  double? get reportedFatBreakdownG {
    if (!hasFatBreakdown) return null;
    return (saturatedFatG ?? 0) +
        (monounsaturatedFatG ?? 0) +
        (polyunsaturatedFatG ?? 0) +
        (transFatG ?? 0);
  }

  /// All-null instance used when the data source cannot provide any
  /// nutrition values for a food.
  static const empty = NutritionValues();

  Map<String, dynamic> toMap() => {
    'calories': calories,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'saturated_fat_g': saturatedFatG,
    'monounsaturated_fat_g': monounsaturatedFatG,
    'polyunsaturated_fat_g': polyunsaturatedFatG,
    'trans_fat_g': transFatG,
    'fiber_g': fiberG,
    'sugars_g': sugarsG,
    'sodium_mg': sodiumMg,
    'potassium_mg': potassiumMg,
    'calcium_mg': calciumMg,
    'iron_mg': ironMg,
    'magnesium_mg': magnesiumMg,
    'zinc_mg': zincMg,
    'vitamin_a_ug': vitaminAUg,
    'vitamin_c_mg': vitaminCMg,
    'vitamin_d_ug': vitaminDUg,
    'vitamin_b12_ug': vitaminB12Ug,
  };

  factory NutritionValues.fromMap(Map<String, dynamic> map) {
    return NutritionValues(
      calories: _toDouble(map['calories']),
      proteinG: _toDouble(map['protein_g']),
      carbsG: _toDouble(map['carbs_g']),
      fatG: _toDouble(map['fat_g']),
      saturatedFatG: _toDouble(map['saturated_fat_g']),
      monounsaturatedFatG: _toDouble(map['monounsaturated_fat_g']),
      polyunsaturatedFatG: _toDouble(map['polyunsaturated_fat_g']),
      transFatG: _toDouble(map['trans_fat_g']),
      fiberG: _toDouble(map['fiber_g']),
      sugarsG: _toDouble(map['sugars_g']),
      sodiumMg: _toDouble(map['sodium_mg']),
      potassiumMg: _toDouble(map['potassium_mg']),
      calciumMg: _toDouble(map['calcium_mg']),
      ironMg: _toDouble(map['iron_mg']),
      magnesiumMg: _toDouble(map['magnesium_mg']),
      zincMg: _toDouble(map['zinc_mg']),
      vitaminAUg: _toDouble(map['vitamin_a_ug']),
      vitaminCMg: _toDouble(map['vitamin_c_mg']),
      vitaminDUg: _toDouble(map['vitamin_d_ug']),
      vitaminB12Ug: _toDouble(map['vitamin_b12_ug']),
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
    Object? saturatedFatG = _sentinel,
    Object? monounsaturatedFatG = _sentinel,
    Object? polyunsaturatedFatG = _sentinel,
    Object? transFatG = _sentinel,
    Object? fiberG = _sentinel,
    Object? sugarsG = _sentinel,
    Object? sodiumMg = _sentinel,
    Object? potassiumMg = _sentinel,
    Object? calciumMg = _sentinel,
    Object? ironMg = _sentinel,
    Object? magnesiumMg = _sentinel,
    Object? zincMg = _sentinel,
    Object? vitaminAUg = _sentinel,
    Object? vitaminCMg = _sentinel,
    Object? vitaminDUg = _sentinel,
    Object? vitaminB12Ug = _sentinel,
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
      saturatedFatG: identical(saturatedFatG, _sentinel)
          ? this.saturatedFatG
          : saturatedFatG as double?,
      monounsaturatedFatG: identical(monounsaturatedFatG, _sentinel)
          ? this.monounsaturatedFatG
          : monounsaturatedFatG as double?,
      polyunsaturatedFatG: identical(polyunsaturatedFatG, _sentinel)
          ? this.polyunsaturatedFatG
          : polyunsaturatedFatG as double?,
      transFatG: identical(transFatG, _sentinel)
          ? this.transFatG
          : transFatG as double?,
      fiberG: identical(fiberG, _sentinel) ? this.fiberG : fiberG as double?,
      sugarsG: identical(sugarsG, _sentinel)
          ? this.sugarsG
          : sugarsG as double?,
      sodiumMg: identical(sodiumMg, _sentinel)
          ? this.sodiumMg
          : sodiumMg as double?,
      potassiumMg: identical(potassiumMg, _sentinel)
          ? this.potassiumMg
          : potassiumMg as double?,
      calciumMg: identical(calciumMg, _sentinel)
          ? this.calciumMg
          : calciumMg as double?,
      ironMg: identical(ironMg, _sentinel) ? this.ironMg : ironMg as double?,
      magnesiumMg: identical(magnesiumMg, _sentinel)
          ? this.magnesiumMg
          : magnesiumMg as double?,
      zincMg: identical(zincMg, _sentinel) ? this.zincMg : zincMg as double?,
      vitaminAUg: identical(vitaminAUg, _sentinel)
          ? this.vitaminAUg
          : vitaminAUg as double?,
      vitaminCMg: identical(vitaminCMg, _sentinel)
          ? this.vitaminCMg
          : vitaminCMg as double?,
      vitaminDUg: identical(vitaminDUg, _sentinel)
          ? this.vitaminDUg
          : vitaminDUg as double?,
      vitaminB12Ug: identical(vitaminB12Ug, _sentinel)
          ? this.vitaminB12Ug
          : vitaminB12Ug as double?,
    );
  }
}

const Object _sentinel = Object();
