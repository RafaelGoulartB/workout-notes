import 'package:flutter/widgets.dart';

import 'package:workout_notes/utils/macro_calculator.dart';

/// Snapshot of the four nutrition target fields (calories, protein g/kg,
/// fat g/kg and the reference weight) read from the editor's controllers.
///
/// [resolve] computes the macro split only when every field is present and
/// valid; a partial input resolves to `null` so the caller can keep the
/// previous week's values (legacy absolute-gram inputs survive until the
/// user completes the g/kg fields).
class NutritionTargetInput {
  final double? calories;
  final double? proteinPerKg;
  final double? fatPerKg;
  final double? refWeight;

  const NutritionTargetInput({
    this.calories,
    this.proteinPerKg,
    this.fatPerKg,
    this.refWeight,
  });

  /// Keys are the shared `_targetKeys` names: `calories`, `proteinPerKg`,
  /// `fatPerKg`, `refWeight`.
  factory NutritionTargetInput.fromControllers(
    Map<String, TextEditingController> controllers,
  ) {
    double? read(String key) => parse(controllers[key]?.text ?? '');
    return NutritionTargetInput(
      calories: read('calories'),
      proteinPerKg: read('proteinPerKg'),
      fatPerKg: read('fatPerKg'),
      refWeight: read('refWeight'),
    );
  }

  /// True when at least one of the four fields holds a value.
  bool get hasInput =>
      calories != null ||
      proteinPerKg != null ||
      fatPerKg != null ||
      refWeight != null;

  bool get isComplete =>
      calories != null &&
      proteinPerKg != null &&
      fatPerKg != null &&
      refWeight != null;

  /// The computed macro breakdown, or null when the input is incomplete or
  /// invalid. A non-null result may still carry `energyConflict`.
  MacroBreakdown? resolve() {
    if (!isComplete) return null;
    return computeMacros(
      calories: calories!,
      proteinPerKg: proteinPerKg!,
      fatPerKg: fatPerKg!,
      weightKg: refWeight!,
    );
  }

  /// Parses one raw user input into a positive finite double (or null).
  static double? parse(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }
}
