import 'package:flutter/widgets.dart';

import 'package:workout_notes/utils/macro_calculator.dart';

/// Snapshot of the nutrition target fields read from the editor's
/// controllers. Calories are derived from the user's daily expenditure
/// (TDEE) plus a signed deficit/surplus adjustment in kcal; the
/// remaining fields (protein g/kg, fat g/kg, reference weight) convert
/// the daily calories into grams.
///
/// [resolve] computes the macro split only when every field is present
/// and valid; a partial input resolves to `null` so the caller can keep
/// the previous week's values (legacy absolute-gram inputs survive
/// until the user completes the g/kg fields).
class NutritionTargetInput {
  /// Daily calorie expenditure from the app settings (read-only).
  /// The week goal is always `tdee + adjustmentKcal`.
  final double? tdee;

  /// Signed kcal adjustment applied on top of [tdee]: negative for a
  /// deficit (cut), positive for a surplus (bulk), zero for maintenance.
  final double? adjustmentKcal;

  final double? proteinPerKg;
  final double? fatPerKg;
  final double? refWeight;

  const NutritionTargetInput({
    this.tdee,
    this.adjustmentKcal,
    this.proteinPerKg,
    this.fatPerKg,
    this.refWeight,
  });

  /// Keys are the shared `_targetKeys` names: `tdee` (read-only),
  /// `adjustment`, `proteinPerKg`, `fatPerKg`, `refWeight`.
  factory NutritionTargetInput.fromControllers(
    Map<String, TextEditingController> controllers,
  ) {
    double? read(String key) => parse(controllers[key]?.text ?? '');
    return NutritionTargetInput(
      tdee: parse(controllers['tdee']?.text ?? ''),
      adjustmentKcal: parse(
        controllers['adjustment']?.text ?? '',
        allowSigned: true,
      ),
      proteinPerKg: read('proteinPerKg'),
      fatPerKg: read('fatPerKg'),
      refWeight: read('refWeight'),
    );
  }

  /// True when at least one of the five fields holds a value.
  bool get hasInput =>
      tdee != null ||
      adjustmentKcal != null ||
      proteinPerKg != null ||
      fatPerKg != null ||
      refWeight != null;

  bool get isComplete =>
      tdee != null &&
      proteinPerKg != null &&
      fatPerKg != null &&
      refWeight != null;

  /// The computed macro breakdown, or null when the input is
  /// incomplete or invalid. A non-null result may still carry
  /// `energyConflict`.
  MacroBreakdown? resolve() {
    if (!isComplete) return null;
    final adjustment = adjustmentKcal ?? 0;
    final calories = tdee! + adjustment;
    if (calories <= 0) return null;
    return computeMacros(
      calories: calories,
      proteinPerKg: proteinPerKg!,
      fatPerKg: fatPerKg!,
      weightKg: refWeight!,
    );
  }

  /// Parses one raw user input into a finite double (or null). The
  /// adjustment field accepts signed values; the others must be
  /// strictly positive.
  static double? parse(String raw, {bool allowSigned = false}) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || !value.isFinite) return null;
    if (!allowSigned && value <= 0) return null;
    if (allowSigned && value == 0) return null;
    return value;
  }
}