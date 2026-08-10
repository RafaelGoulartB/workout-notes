import 'nutrition_values.dart';

/// Aggregated totals for a single day, used by the daily nutrition
/// screen and for goal progress.
class DailyNutritionSummary {
  final String date;
  final NutritionValues consumed;
  final bool hasIncompleteData;

  const DailyNutritionSummary({
    required this.date,
    required this.consumed,
    this.hasIncompleteData = false,
  });

  /// Calories left to reach the goal. Returns null when no calorie
  /// goal is configured.
  double? remainingCalories(double? goalCalories) {
    if (goalCalories == null) return null;
    final consumedCalories = consumed.calories ?? 0;
    return goalCalories - consumedCalories;
  }

  static const empty = DailyNutritionSummary(
    date: '',
    consumed: NutritionValues.empty,
  );
}
