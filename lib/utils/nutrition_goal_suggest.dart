import 'package:workout_notes/utils/macro_calculator.dart';

/// Goal kind stored alongside a TDEE adjustment on [suggestNutritionGoal]
/// consumers. The kind is derived from the adjustment sign: negative is a
/// deficit (cut), zero is maintenance and positive is a surplus (bulk).
enum NutritionObjective { cut, maintenance, bulk }

/// Default percentage adjustment applied to TDEE for each objective.
/// Maintenance is exactly 0%, cut defaults to a 20% deficit and bulk
/// to a 10% surplus. The UI lets the user override the percentage
/// inline while keeping the kind label.
class NutritionAdjustment {
  final NutritionObjective kind;
  final double percent;

  const NutritionAdjustment({required this.kind, required this.percent});

  double get factor => 1 + percent / 100;

  static NutritionAdjustment defaultsFor(NutritionObjective kind) {
    return switch (kind) {
      NutritionObjective.cut => const NutritionAdjustment(
        kind: NutritionObjective.cut,
        percent: -20,
      ),
      NutritionObjective.maintenance => const NutritionAdjustment(
        kind: NutritionObjective.maintenance,
        percent: 0,
      ),
      NutritionObjective.bulk => const NutritionAdjustment(
        kind: NutritionObjective.bulk,
        percent: 10,
      ),
    };
  }

  /// Kind implied by an arbitrary signed percentage, so stored goals can
  /// never end up with a kind label contradicting its percent.
  static NutritionObjective kindForPercent(double percent) {
    if (percent < 0) return NutritionObjective.cut;
    if (percent > 0) return NutritionObjective.bulk;
    return NutritionObjective.maintenance;
  }

  @override
  bool operator ==(Object other) =>
      other is NutritionAdjustment &&
      other.kind == kind &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(kind, percent);
}

/// Protein and fat targets used to derive the daily macro split.
/// Carbohydrates always absorb the remaining target calories.
class NutritionMacroRatios {
  final double proteinPerKg;
  final double fatPerKg;

  const NutritionMacroRatios({
    required this.proteinPerKg,
    required this.fatPerKg,
  });

  static const NutritionMacroRatios defaults = NutritionMacroRatios(
    proteinPerKg: 1.8,
    fatPerKg: 1.0,
  );
}

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

/// Result of [suggestNutritionGoal]: the daily calorie expenditure
/// (TDEE = maintenance) and the macro split in grams. The suggestion is
/// always maintenance — the deficit/surplus adjustment is a separate
/// concern configured in the nutrition settings.
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

/// Suggests the maintenance daily calories and macros for [weightKg] kg
/// using the Mifflin-St Jeor equation.
///
/// - BMR = 10×weight + 6.25×height − 5×age + adjustment (5 for males,
///   −161 for females).
/// - TDEE = BMR × [activity].factor; the maintenance goal equals the
///   TDEE (`calories == tdee`).
/// - Macros: protein and fat follow g/kg ratios; carbohydrates absorb
///   the remaining energy (clamped at ≥ 0).
///
/// Values are rounded to integers. Throws [ArgumentError] for
/// non-positive inputs.
NutritionGoalSuggestion suggestNutritionGoal({
  required double weightKg,
  required double heightCm,
  required int ageYears,
  required bool isMale,
  required ActivityLevel activity,
  NutritionMacroRatios? macroRatios,
}) {
  if (weightKg <= 0 || heightCm <= 0 || ageYears <= 0) {
    throw ArgumentError('weight, height and age must be positive');
  }
  final bmr =
      10 * weightKg + 6.25 * heightCm - 5 * ageYears + (isMale ? 5 : -161);
  final tdee = bmr * activity.factor;

  final ratios = macroRatios ?? NutritionMacroRatios.defaults;
  if (ratios.proteinPerKg <= 0 || ratios.fatPerKg <= 0) {
    throw ArgumentError('macro ratios must be positive');
  }
  final macros = computeMacros(
    calories: tdee,
    proteinPerKg: ratios.proteinPerKg,
    fatPerKg: ratios.fatPerKg,
    weightKg: weightKg,
  );
  return NutritionGoalSuggestion(
    bmr: bmr.roundToDouble(),
    tdee: tdee.roundToDouble(),
    calories: tdee.roundToDouble(),
    proteinG: macros.proteinG,
    carbsG: macros.carbsG,
    fatG: macros.fatG,
  );
}
