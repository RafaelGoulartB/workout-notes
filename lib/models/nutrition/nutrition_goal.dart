import 'nutrition_values.dart';

/// User-defined nutrition goal. At most one [NutritionGoal] is active
/// at a time. When no goal exists, the daily screen shows the
/// consumption totals and a CTA to configure one — we never invent
/// defaults.
///
/// The aim of the goal is to derive the daily consumption target
/// (calories / protein / carbs / fat) from the user's daily calorie
/// expenditure (TDEE) and a deficit/maintenance/surplus adjustment.
/// The relation is:
///
///   goal = TDEE × factor
///   factor = 1.0 ± adjustmentPercent / 100
///
/// `calories` (and the gram fields) keep representing the *goal*
/// because every existing consumer (dashboard, progress, AI coach,
/// export) reads from there. The TDEE + adjustment values are the
/// user-facing inputs that drive the goal; the goal is recomputed
/// from them whenever the user saves.
class NutritionGoal {
  final String id;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  /// Daily calories the user spends (TDEE). When set, the goal lives
  /// in [calories] and is recomputed from this field plus the
  /// adjustment when [adjustmentKind] / [adjustmentPercent] change.
  final double? tdee;

  /// One of `cut`, `maintenance`, `bulk`. The factor is derived from
  /// the matching percentage (`-20%`, `0%`, `+10%` by default).
  final String? adjustmentKind;

  /// Percentage applied to TDEE to produce the goal. Positive for
  /// surplus, negative for deficit, zero for maintenance.
  final double? adjustmentPercent;

  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  const NutritionGoal({
    required this.id,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.tdee,
    this.adjustmentKind,
    this.adjustmentPercent,
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
    Object? tdee = _sentinel,
    Object? adjustmentKind = _sentinel,
    Object? adjustmentPercent = _sentinel,
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
      tdee: identical(tdee, _sentinel) ? this.tdee : tdee as double?,
      adjustmentKind: identical(adjustmentKind, _sentinel)
          ? this.adjustmentKind
          : adjustmentKind as String?,
      adjustmentPercent: identical(adjustmentPercent, _sentinel)
          ? this.adjustmentPercent
          : adjustmentPercent as double?,
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
      calories == null &&
      proteinG == null &&
      carbsG == null &&
      fatG == null &&
      tdee == null &&
      adjustmentKind == null &&
      adjustmentPercent == null;

  /// The headline number shown on the dashboard (`calories` field,
  /// i.e. the consumption goal). Falls back to the TDEE when no
  /// adjustment is configured — the dashboard always sees a target.
  double? get effectiveCalories {
    if (calories != null) return calories;
    if (tdee == null || adjustmentPercent == null) return null;
    return tdee! * (1 + adjustmentPercent! / 100);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'calories': calories,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
    'tdee': tdee,
    'adjustment_kind': adjustmentKind,
    'adjustment_percent': adjustmentPercent,
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
      tdee: (map['tdee'] as num?)?.toDouble(),
      adjustmentKind: map['adjustment_kind'] as String?,
      adjustmentPercent: (map['adjustment_percent'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }
}

const Object _sentinel = Object();
