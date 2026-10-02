part of 'nutrition_repository.dart';

/// Calorie-balance queries and calculations used by the nutrition analytics
/// screens. Kept as an extension so the main repository remains focused on
/// persistence primitives while preserving its existing public API.
extension NutritionRepositoryCalorieAnalytics on NutritionRepository {
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

  Future<List<DailyCalorieTotal>> getDailyCalorieTotalsForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await this.db;
    final start = dateKey(startDate);
    final end = dateKey(endDate);
    final rows = await db.rawQuery(
      '''
      SELECT ml.date as date,
        SUM(mli.calories) as calories,
        COUNT(*) as item_count
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
      ''',
      [start, end],
    );
    final totalsByDate = <String, double>{};
    for (final row in rows) {
      final itemCount = (row['item_count'] as num?)?.toInt() ?? 0;
      if (itemCount > 0) {
        totalsByDate[row['date'] as String] = _sum(row['calories']) ?? 0;
      }
    }
    final result = <DailyCalorieTotal>[];
    final firstDay = DateTime.parse(start);
    final lastDay = DateTime.parse(end);
    final days = daysBetween(firstDay, lastDay) + 1;
    for (var i = 0; i < days; i++) {
      final d = addDays(firstDay, i);
      final key = dateKey(d);
      result.add(DailyCalorieTotal(date: d, calories: totalsByDate[key]));
    }
    return result;
  }

  Future<List<CalorieContributor>> getTopCalorieContributorsForRange({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 10,
  }) async {
    final db = await this.db;
    final start = dateKey(startDate);
    final end = dateKey(endDate);
    final rows = await db.rawQuery(
      '''
      SELECT mli.food_name_snapshot as food_name,
        mli.brand_snapshot as brand,
        SUM(mli.calories) as total_calories,
        COUNT(*) as occurrences
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
        AND mli.food_name_snapshot IS NOT NULL
        AND mli.calories IS NOT NULL
      GROUP BY mli.food_name_snapshot, mli.brand_snapshot
      ORDER BY total_calories DESC
      LIMIT ?
      ''',
      [start, end, limit],
    );
    return rows
        .map(
          (r) => CalorieContributor(
            name: (r['food_name'] as String?) ?? '',
            brand: r['brand'] as String?,
            totalCalories: ((r['total_calories'] as num?) ?? 0).toDouble(),
            occurrences: ((r['occurrences'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  Future<List<MealTypeCalories>> getCaloriesByMealTypeForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await this.db;
    final start = dateKey(startDate);
    final end = dateKey(endDate);
    final rows = await db.rawQuery(
      '''
      SELECT ml.meal_type as meal_type,
        COALESCE(ml.name, ml.meal_type) as display_name,
        SUM(mli.calories) as total_calories,
        COUNT(*) as item_count
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
        AND mli.calories IS NOT NULL
      GROUP BY ml.meal_type, display_name
      ORDER BY total_calories DESC
      ''',
      [start, end],
    );
    return rows
        .map(
          (r) => MealTypeCalories(
            mealType: (r['meal_type'] as String?) ?? '',
            displayName: (r['display_name'] as String?) ?? '',
            totalCalories: ((r['total_calories'] as num?) ?? 0).toDouble(),
            itemCount: ((r['item_count'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }
}
