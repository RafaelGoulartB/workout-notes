import 'package:workout_notes/models/nutrition/nutrition_values.dart';

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

  static const empty = DailyNutritionSummary(
    date: '',
    consumed: NutritionValues.empty,
  );
}
