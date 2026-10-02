/// One day of total calories consumed, or null when the day has no
/// logged items. Powers the calorie-tracking analytics screen.
class DailyCalorieTotal {
  final DateTime date;
  final double? calories;

  const DailyCalorieTotal({required this.date, required this.calories});
}

/// Aggregated calorie balance for a window of [days]. All counters
/// consider only days with at least one logged item; days without
/// any log are not counted in any bucket (deficit / on target /
/// surplus / streak) so the user's behavior on a rest day never
/// skews the totals.
class CalorieBalance {
  final int days;
  final double totalConsumed;

  /// Sum of the active goal over days with at least one logged item
  /// (or null when no goal is configured). Combined with
  /// [totalConsumed] to produce the net surplus / deficit.
  final double? totalGoal;

  /// `consumed - totalGoal`. Null when no goal is set.
  final double? balance;
  final int daysLogged;
  final int daysInDeficit;
  final int daysOnTarget;
  final int daysInSurplus;
  final int currentStreak;
  final double averageDailyIntake;

  const CalorieBalance({
    required this.days,
    required this.totalConsumed,
    required this.totalGoal,
    required this.balance,
    required this.daysLogged,
    required this.daysInDeficit,
    required this.daysOnTarget,
    required this.daysInSurplus,
    required this.currentStreak,
    required this.averageDailyIntake,
  });
}

/// A food (or food + brand pair) that contributed calories in a
/// window, used by the "top contributors" panel.
class CalorieContributor {
  final String name;
  final String? brand;
  final double totalCalories;
  final int occurrences;

  const CalorieContributor({
    required this.name,
    this.brand,
    required this.totalCalories,
    required this.occurrences,
  });
}

/// Per-meal-type calorie subtotal, used by the "where the calories
/// come from" panel.
class MealTypeCalories {
  final String mealType;
  final String displayName;
  final double totalCalories;
  final int itemCount;

  const MealTypeCalories({
    required this.mealType,
    required this.displayName,
    required this.totalCalories,
    required this.itemCount,
  });
}
