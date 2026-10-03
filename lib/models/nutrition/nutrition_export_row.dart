import 'dart:convert';

/// CSV export row.
class NutritionExportRow {
  final String date;
  final String mealType;

  /// Custom display name of the meal section (null for legacy rows).
  final String? mealName;
  final String food;
  final String? brand;
  final double quantity;
  final String unit;
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
  final String? source;
  final bool isEstimated;
  final bool hasMissingValues;

  const NutritionExportRow({
    required this.date,
    required this.mealType,
    this.mealName,
    required this.food,
    this.brand,
    required this.quantity,
    required this.unit,
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
    this.source,
    this.isEstimated = false,
    this.hasMissingValues = false,
  });

  factory NutritionExportRow.fromMap(Map<String, dynamic> map) {
    final rawSnapshot = map['snapshot'] as String?;
    bool isEstimated = false;
    bool hasMissing = false;
    if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
      try {
        final snapshot = jsonDecode(rawSnapshot);
        if (snapshot is Map) {
          isEstimated = (snapshot['is_estimated'] as bool?) ?? false;
          hasMissing = (snapshot['has_missing_values'] as bool?) ?? false;
        }
      } catch (_) {
        // Corrupt snapshot: keep the default flags.
      }
    }
    return NutritionExportRow(
      date: (map['date'] as String?) ?? '',
      mealType: (map['meal_type'] as String?) ?? '',
      mealName: map['meal_name'] as String?,
      food: (map['food'] as String?) ?? '',
      brand: map['brand'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: (map['unit'] as String?) ?? '',
      calories: (map['calories'] as num?)?.toDouble(),
      proteinG: (map['protein_g'] as num?)?.toDouble(),
      carbsG: (map['carbs_g'] as num?)?.toDouble(),
      fatG: (map['fat_g'] as num?)?.toDouble(),
      saturatedFatG: (map['saturated_fat_g'] as num?)?.toDouble(),
      monounsaturatedFatG: (map['monounsaturated_fat_g'] as num?)?.toDouble(),
      polyunsaturatedFatG: (map['polyunsaturated_fat_g'] as num?)?.toDouble(),
      transFatG: (map['trans_fat_g'] as num?)?.toDouble(),
      fiberG: (map['fiber_g'] as num?)?.toDouble(),
      sugarsG: (map['sugars_g'] as num?)?.toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      potassiumMg: (map['potassium_mg'] as num?)?.toDouble(),
      calciumMg: (map['calcium_mg'] as num?)?.toDouble(),
      ironMg: (map['iron_mg'] as num?)?.toDouble(),
      magnesiumMg: (map['magnesium_mg'] as num?)?.toDouble(),
      zincMg: (map['zinc_mg'] as num?)?.toDouble(),
      vitaminAUg: (map['vitamin_a_ug'] as num?)?.toDouble(),
      vitaminCMg: (map['vitamin_c_mg'] as num?)?.toDouble(),
      vitaminDUg: (map['vitamin_d_ug'] as num?)?.toDouble(),
      vitaminB12Ug: (map['vitamin_b12_ug'] as num?)?.toDouble(),
      source: map['source'] as String?,
      isEstimated: isEstimated,
      hasMissingValues: hasMissing,
    );
  }
}
