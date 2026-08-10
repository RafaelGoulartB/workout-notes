import 'nutrition_values.dart';

/// User-defined nutrition goal. At most one [NutritionGoal] is active
/// at a time. When no goal exists, the daily screen shows the
/// consumption totals and a CTA to configure one — we never invent
/// defaults.
class NutritionGoal {
  final String id;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  const NutritionGoal({
    required this.id,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  NutritionGoal copyWith({
    String? id,
    Object? calories = _sentinel,
    Object? proteinG = _sentinel,
    Object? carbsG = _sentinel,
    Object? fatG = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return NutritionGoal(
      id: id ?? this.id,
      calories: identical(calories, _sentinel)
          ? this.calories
          : calories as double?,
      proteinG: identical(proteinG, _sentinel)
          ? this.proteinG
          : proteinG as double?,
      carbsG: identical(carbsG, _sentinel) ? this.carbsG : carbsG as double?,
      fatG: identical(fatG, _sentinel) ? this.fatG : fatG as double?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  NutritionValues get values => NutritionValues(
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );

  bool get isEmpty =>
      calories == null && proteinG == null && carbsG == null && fatG == null;

  Map<String, dynamic> toMap() => {
    'id': id,
    'calories': calories,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_active': isActive ? 1 : 0,
  };

  factory NutritionGoal.fromMap(Map<String, dynamic> map) {
    return NutritionGoal(
      id: map['id'] as String,
      calories: (map['calories'] as num?)?.toDouble(),
      proteinG: (map['protein_g'] as num?)?.toDouble(),
      carbsG: (map['carbs_g'] as num?)?.toDouble(),
      fatG: (map['fat_g'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }
}

const Object _sentinel = Object();
