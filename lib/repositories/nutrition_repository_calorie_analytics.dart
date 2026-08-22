part of 'nutrition_repository.dart';

/// Calorie-balance queries and calculations used by the nutrition analytics
/// screens. Kept as an extension so the main repository remains focused on
/// persistence primitives while preserving its existing public API.
extension NutritionRepositoryCalorieAnalytics on NutritionRepository {
  /// Aggregated totals for the [days] window. [goal] is the active calorie
  /// target, or null when no goal is configured.
  Future<CalorieBalance> getCalorieBalance({
    required int days,
    required double? goal,
  }) => getCalorieBalanceForRange(
    startDate: DateTime.now().subtract(Duration(days: days - 1)),
    endDate: DateTime.now(),
    goal: goal,
  );

  Future<CalorieBalance> getCalorieBalanceForRange({
    required DateTime startDate,
    required DateTime endDate,
    required double? goal,
  }) async {
    final dailies = await getDailyCalorieTotalsForRange(
      startDate: startDate,
      endDate: endDate,
    );
    return calculateCalorieBalance(dailies: dailies, goal: goal);
  }

  /// Builds the aggregate balance from totals already loaded by a caller.
  /// This avoids repeating the daily-totals query on analytics screens.
  CalorieBalance calculateCalorieBalance({
    required List<DailyCalorieTotal> dailies,
    required double? goal,
  }) {
    final days = dailies.length;
    var consumed = 0.0;
    var loggedDays = 0;
    var inDeficit = 0;
    var onTarget = 0;
    var inSurplus = 0;
    final logged = <DailyCalorieTotal>[];
    for (final d in dailies) {
      if (d.calories == null) continue;
      consumed += d.calories!;
      loggedDays++;
      logged.add(d);
      if (goal != null && goal > 0) {
        final delta = d.calories! - goal;
        final ratio = delta.abs() / goal;
        if (ratio <= 0.10) {
          onTarget++;
        } else if (delta < 0) {
          inDeficit++;
        } else {
          inSurplus++;
        }
      }
    }

    // Current streak: consecutive logged days (newest first) inside the
    // ±10% goal band. Without a goal, count consecutive logged days.
    var streak = 0;
    if (goal != null && goal > 0) {
      for (var i = logged.length - 1; i >= 0; i--) {
        final delta = (logged[i].calories! - goal).abs() / goal;
        if (delta <= 0.10) {
          streak++;
        } else {
          break;
        }
      }
    } else {
      for (var i = logged.length - 1; i >= 0; i--) {
        if (logged[i].calories != null) {
          streak++;
        } else {
          break;
        }
      }
    }

    final average = loggedDays == 0 ? 0.0 : consumed / loggedDays;
    final totalGoal = goal == null ? null : goal * loggedDays;
    return CalorieBalance(
      days: days,
      totalConsumed: consumed,
      totalGoal: totalGoal,
      balance: totalGoal == null ? null : consumed - totalGoal,
      daysLogged: loggedDays,
      daysInDeficit: inDeficit,
      daysOnTarget: onTarget,
      daysInSurplus: inSurplus,
      currentStreak: streak,
      averageDailyIntake: average,
    );
  }
}
