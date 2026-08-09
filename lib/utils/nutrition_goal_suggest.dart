/// User body-weight objective used by [suggestNutritionGoal].
enum NutritionObjective { cut, maintenance, bulk }

/// Physical activity level used to scale the BMR into TDEE.
enum ActivityLevel {
  sedentary(1.2),
  light(1.375),
  moderate(1.55),
  active(1.725),
  veryActive(1.9);

  final double factor;
  const ActivityLevel(this.factor);
}

/// Result of [suggestNutritionGoal]: the target calories (after the
/// objective adjustment) and the macro split in grams.
class NutritionGoalSuggestion {
  final double bmr;
  final double tdee;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  const NutritionGoalSuggestion({
    required this.bmr,
    required this.tdee,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

/// Suggests daily calories and macros for [weightKg] kg using the
/// Mifflin-St Jeor equation.
///
/// - BMR = 10×weight + 6.25×height − 5×age + adjustment (5 for males,
///   −161 for females).
/// - TDEE = BMR × [activity].factor.
/// - Target calories = TDEE adjusted by the objective: −20% (cut),
///   unchanged (maintenance), +10% (bulk).
/// - Macros: protein 2.2/1.8/2.0 g/kg, fat 0.8/1.0/1.2 g/kg depending
///   on the objective; carbohydrates absorb the remaining energy
///   (clamped at ≥ 0).
///
/// Values are rounded to integers. Throws [ArgumentError] for
/// non-positive inputs.
NutritionGoalSuggestion suggestNutritionGoal({
  required double weightKg,
  required double heightCm,
  required int ageYears,
  required bool isMale,
  required ActivityLevel activity,
  required NutritionObjective objective,
}) {
  if (weightKg <= 0 || heightCm <= 0 || ageYears <= 0) {
    throw ArgumentError('weight, height and age must be positive');
  }
  final bmr = 10 * weightKg + 6.25 * heightCm - 5 * ageYears + (isMale ? 5 : -161);
  final tdee = bmr * activity.factor;
  final adjustment = switch (objective) {
    NutritionObjective.cut => 0.80,
    NutritionObjective.maintenance => 1.0,
    NutritionObjective.bulk => 1.10,
  };
  final calories = tdee * adjustment;

  final proteinPerKg = switch (objective) {
    NutritionObjective.cut => 2.2,
    NutritionObjective.maintenance => 1.8,
    NutritionObjective.bulk => 2.0,
  };
  final fatPerKg = switch (objective) {
    NutritionObjective.cut => 0.8,
    NutritionObjective.maintenance => 1.0,
    NutritionObjective.bulk => 1.2,
  };
  final protein = proteinPerKg * weightKg;
  final fat = fatPerKg * weightKg;
  final carbs = (calories - protein * 4 - fat * 9) / 4;
  return NutritionGoalSuggestion(
    bmr: bmr.roundToDouble(),
    tdee: tdee.roundToDouble(),
    calories: calories.roundToDouble(),
    proteinG: protein.roundToDouble(),
    carbsG: carbs < 0 ? 0 : carbs.roundToDouble(),
    fatG: fat.roundToDouble(),
  );
}
