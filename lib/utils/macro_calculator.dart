/// Computes the daily macro split from total calories, g/kg protein and fat
/// ratios, and a reference body weight. Carbohydrates absorb the remaining
/// calories: `carbs = (kcal − protein×4 − fat×9) / 4`, clamped at ≥ 0.
class MacroBreakdown {
  final double calories;
  final double proteinPerKg;
  final double fatPerKg;
  final double weightKg;
  final double proteinG;
  final double fatG;
  final double carbsG;

  /// True when protein + fat already exceed [calories], so carbs were
  /// clamped to zero and the split does not add up to the target calories.
  final bool energyConflict;

  const MacroBreakdown({
    required this.calories,
    required this.proteinPerKg,
    required this.fatPerKg,
    required this.weightKg,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.energyConflict,
  });

  int get proteinRounded => proteinG.round();
  int get fatRounded => fatG.round();
  int get carbsRounded => carbsG.round();

  int get proteinKcal => (proteinG * 4).round();
  int get fatKcal => (fatG * 9).round();
  int get carbsKcal => (carbsG * 4).round();
}

/// Throws [ArgumentError] when any input is non-positive or not finite.
MacroBreakdown computeMacros({
  required double calories,
  required double proteinPerKg,
  required double fatPerKg,
  required double weightKg,
}) {
  for (final value in [calories, proteinPerKg, fatPerKg, weightKg]) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('macro inputs must be positive');
    }
  }
  final protein = proteinPerKg * weightKg;
  final fat = fatPerKg * weightKg;
  final carbs = (calories - protein * 4 - fat * 9) / 4;
  return MacroBreakdown(
    calories: calories,
    proteinPerKg: proteinPerKg,
    fatPerKg: fatPerKg,
    weightKg: weightKg,
    proteinG: protein.roundToDouble(),
    fatG: fat.roundToDouble(),
    carbsG: (carbs < 0 ? 0 : carbs).roundToDouble(),
    energyConflict: carbs < 0,
  );
}
