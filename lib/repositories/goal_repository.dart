import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/goal.dart';
import 'base_repository.dart';
import '../database/database_provider.dart';

/// Repository for user-defined goals: CRUD + progress computation.
class GoalRepository extends BaseRepository {
  GoalRepository([DatabaseProvider? databaseProvider])
    : super(databaseProvider);
  // ===================================================================
  // CRUD
  // ===================================================================

  Future<List<Goal>> getAll({bool activeOnly = false}) async {
    final db = await this.db;
    final where = activeOnly ? 'is_active = 1' : null;
    final rows = await db.query(
      'user_goals',
      where: where,
      orderBy: 'is_active DESC, created_at DESC',
    );
    return rows.map(Goal.fromMap).toList();
  }

  Future<Goal?> getById(String id) async {
    final db = await this.db;
    final rows = await db.query('user_goals', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Goal.fromMap(rows.first);
  }

  Future<void> insert(Goal goal) async {
    final db = await this.db;
    await db.insert(
      'user_goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(Goal goal) async {
    final db = await this.db;
    await db.update(
      'user_goals',
      goal.toMap(),
      where: 'id = ?',
      whereArgs: [goal.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await this.db;
    await db.delete('user_goals', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleActive(String id, bool isActive) async {
    final db = await this.db;
    await db.update(
      'user_goals',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===================================================================
  // PERIOD COMPUTATION
  // ===================================================================

  /// Returns [start, end] of the current period for the given [period].
  /// Weekly = Monday → Sunday. Monthly = day 1 → last day of month.
  static (DateTime, DateTime) currentPeriod(
    GoalPeriod period, [
    DateTime? now,
  ]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    if (period == GoalPeriod.weekly) {
      // Dart weekday: 1 = Monday ... 7 = Sunday
      final weekday = today.weekday;
      final start = today.subtract(Duration(days: weekday - 1));
      final end = start.add(const Duration(days: 6));
      return (start, end);
    } else {
      final start = DateTime(today.year, today.month, 1);
      final nextMonth = today.month == 12
          ? DateTime(today.year + 1, 1, 1)
          : DateTime(today.year, today.month + 1, 1);
      final end = nextMonth.subtract(const Duration(days: 1));
      return (start, end);
    }
  }

  /// Returns list of (start, end) tuples for the past [count] periods,
  /// most recent first.
  static List<(DateTime, DateTime)> pastPeriods(
    GoalPeriod period,
    int count, [
    DateTime? now,
  ]) {
    final n = now ?? DateTime.now();
    final results = <(DateTime, DateTime)>[];
    if (period == GoalPeriod.weekly) {
      var ref = n;
      for (int i = 0; i < count; i++) {
        final (start, end) = currentPeriod(GoalPeriod.weekly, ref);
        results.add((start, end));
        // Move to previous week
        ref = start.subtract(const Duration(days: 1));
      }
    } else {
      for (int i = 0; i < count; i++) {
        final ref = DateTime(n.year, n.month - i, 1);
        final (start, end) = currentPeriod(GoalPeriod.monthly, ref);
        results.add((start, end));
      }
    }
    return results;
  }

  // ===================================================================
  // PROGRESS COMPUTATION
  // ===================================================================

  /// Computes the current progress for the given goal.
  Future<GoalProgress> getProgress(Goal goal) async {
    final (start, end) = currentPeriod(goal.period);
    final value = await _computeValueForRange(goal, start, end);
    return _buildProgress(goal, value, start, end);
  }

  /// Computes the current progress and the past [count] period results.
  Future<(GoalProgress, List<GoalPeriodResult>)> getProgressWithHistory(
    Goal goal, {
    int historyCount = 6,
  }) async {
    final current = await getProgress(goal);
    final past = pastPeriods(goal.period, historyCount + 1);
    // skip the first one because it is the current period
    final pastRanges = past.skip(1).take(historyCount).toList();

    final results = <GoalPeriodResult>[];
    for (final (start, end) in pastRanges) {
      final value = await _computeValueForRange(goal, start, end);
      results.add(
        GoalPeriodResult(
          start: start,
          end: end,
          value: value,
          targetValue: goal.targetValue,
          wasCompleted: value >= goal.targetValue,
        ),
      );
    }
    return (current, results);
  }

  /// Returns the list of workouts that contributed to the goal's progress
  /// in the current period, most recent first.
  /// - For volume/distance/time: the value contributed by that workout.
  /// - For days: contributedValue is always 1.0 (one workout = one day).
  Future<List<ContributingWorkout>> getContributingWorkouts(Goal goal) async {
    final db = await this.db;
    final (start, end) = currentPeriod(goal.period);
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final energySystem = goal.scope.value;

    switch (goal.metric) {
      case GoalMetric.volume:
        final rows = await db.rawQuery(
          '''
          SELECT w.id as workout_id, w.date,
            SUM(s.weight * s.reps) as value,
            COUNT(s.id) as set_count
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ? AND s.is_warmup = 0
            AND ec.energy_system = ?
            AND s.weight IS NOT NULL AND s.reps IS NOT NULL
            AND s.weight > 0 AND s.reps > 0
          GROUP BY w.id
          ORDER BY w.date DESC
        ''',
          [startStr, endStr, energySystem],
        );
        return rows
            .where((r) => ((r['value'] as num?) ?? 0) > 0)
            .map(
              (r) => ContributingWorkout(
                workoutId: r['workout_id'] as String,
                date: r['date'] as String,
                contributedValue: (r['value'] as num?)?.toDouble() ?? 0,
                setCount: (r['set_count'] as int?) ?? 0,
              ),
            )
            .toList();

      case GoalMetric.days:
        // Workouts that contain at least one exercise of the goal's scope.
        final rows = await db.rawQuery(
          '''
          SELECT w.id as workout_id, w.date
          FROM workouts w
          WHERE w.date >= ? AND w.date <= ?
            AND EXISTS (
              SELECT 1
              FROM exercise_entries ee
              JOIN exercises e ON ee.exercise_id = e.id
              JOIN exercise_categories ec ON e.category_id = ec.id
              WHERE ee.workout_id = w.id
                AND ec.energy_system = ?
            )
          ORDER BY w.date DESC
        ''',
          [startStr, endStr, energySystem],
        );
        return rows
            .map(
              (r) => ContributingWorkout(
                workoutId: r['workout_id'] as String,
                date: r['date'] as String,
                contributedValue: 1.0,
                setCount: 0,
              ),
            )
            .toList();

      case GoalMetric.distance:
        final rows = await db.rawQuery(
          '''
          SELECT w.id as workout_id, w.date,
            SUM(s.distance) as value,
            COUNT(s.id) as set_count
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ? AND s.is_warmup = 0
            AND ec.energy_system = 'aerobic'
            AND s.distance IS NOT NULL AND s.distance > 0
          GROUP BY w.id
          ORDER BY w.date DESC
        ''',
          [startStr, endStr],
        );
        return rows
            .where((r) => ((r['value'] as num?) ?? 0) > 0)
            .map(
              (r) => ContributingWorkout(
                workoutId: r['workout_id'] as String,
                date: r['date'] as String,
                contributedValue: (r['value'] as num?)?.toDouble() ?? 0,
                setCount: (r['set_count'] as int?) ?? 0,
              ),
            )
            .toList();

      case GoalMetric.time:
        final rows = await db.rawQuery(
          '''
          SELECT w.id as workout_id, w.date,
            SUM(s.time_seconds) as value,
            COUNT(s.id) as set_count
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ? AND s.is_warmup = 0
            AND ec.energy_system = 'aerobic'
            AND s.time_seconds IS NOT NULL AND s.time_seconds > 0
          GROUP BY w.id
          ORDER BY w.date DESC
        ''',
          [startStr, endStr],
        );
        return rows
            .where((r) => ((r['value'] as num?) ?? 0) > 0)
            .map(
              (r) => ContributingWorkout(
                workoutId: r['workout_id'] as String,
                date: r['date'] as String,
                contributedValue: ((r['value'] as int?) ?? 0).toDouble(),
                setCount: (r['set_count'] as int?) ?? 0,
              ),
            )
            .toList();
    }
  }

  /// Suggested target based on the average of the last [weeks] weeks (or months)
  /// of the same metric, multiplied by [multiplier].
  Future<double?> suggestTarget(
    GoalScope scope,
    GoalMetric metric,
    GoalPeriod period, {
    double multiplier = 1.10,
    int periods = 4,
  }) async {
    final ranges = pastPeriods(period, periods).reversed.toList();
    if (ranges.isEmpty) return null;
    final values = <double>[];
    for (final (start, end) in ranges) {
      final v = await _computeValueForRangeRaw(scope, metric, start, end);
      if (v > 0) values.add(v);
    }
    if (values.isEmpty) return null;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (avg * multiplier).roundToDouble();
  }

  // ===================================================================
  // INTERNAL
  // ===================================================================

  GoalProgress _buildProgress(
    Goal goal,
    double value,
    DateTime start,
    DateTime end,
  ) {
    final now = DateTime.now();
    final target = goal.targetValue;
    final percent = target > 0 ? (value / target).clamp(0.0, 1.5) : 0.0;
    final isComplete = target > 0 && value >= target;
    final daysElapsed = now.difference(start).inDays + 1;
    final daysTotal = end.difference(start).inDays + 1;
    final daysRemaining = (end.difference(now).inDays).clamp(0, daysTotal);
    return GoalProgress(
      currentValue: value,
      targetValue: target,
      percent: percent,
      isComplete: isComplete,
      periodStart: start,
      periodEnd: end,
      daysRemaining: daysRemaining,
      daysElapsed: daysElapsed > 0 ? daysElapsed : 0,
    );
  }

  Future<double> _computeValueForRange(
    Goal goal,
    DateTime start,
    DateTime end,
  ) {
    return _computeValueForRangeRaw(goal.scope, goal.metric, start, end);
  }

  Future<double> _computeValueForRangeRaw(
    GoalScope scope,
    GoalMetric metric,
    DateTime start,
    DateTime end,
  ) async {
    final db = await this.db;
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final energySystem = scope.value;

    switch (metric) {
      case GoalMetric.volume:
        // Sum of (weight * reps) only for sets whose exercise belongs to
        // a category of the goal's scope (anaerobic for strength).
        final row = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(s.weight * s.reps), 0) as value
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ? AND s.is_warmup = 0
            AND ec.energy_system = ?
            AND s.weight IS NOT NULL AND s.reps IS NOT NULL
            AND s.weight > 0 AND s.reps > 0
        ''',
          [startStr, endStr, energySystem],
        );
        return (row.first['value'] as num?)?.toDouble() ?? 0;

      case GoalMetric.days:
        // Distinct workout dates that contain at least one exercise
        // whose category matches the goal's scope.
        final row = await db.rawQuery(
          '''
          SELECT COUNT(DISTINCT w.date) as value
          FROM workouts w
          WHERE w.date >= ? AND w.date <= ?
            AND EXISTS (
              SELECT 1
              FROM exercise_entries ee
              JOIN exercises e ON ee.exercise_id = e.id
              JOIN exercise_categories ec ON e.category_id = ec.id
              WHERE ee.workout_id = w.id
                AND ec.energy_system = ?
            )
        ''',
          [startStr, endStr, energySystem],
        );
        return ((row.first['value'] as int?) ?? 0).toDouble();

      case GoalMetric.distance:
        // Aerobic: sum of distance for cardio exercises
        final row = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(s.distance), 0) as value
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ?
            AND s.is_warmup = 0
            AND ec.energy_system = 'aerobic'
            AND s.distance IS NOT NULL AND s.distance > 0
        ''',
          [startStr, endStr],
        );
        return (row.first['value'] as num?)?.toDouble() ?? 0;

      case GoalMetric.time:
        // Aerobic: sum of time_seconds for cardio exercises
        final row = await db.rawQuery(
          '''
          SELECT COALESCE(SUM(s.time_seconds), 0) as value
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ?
            AND s.is_warmup = 0
            AND ec.energy_system = 'aerobic'
            AND s.time_seconds IS NOT NULL AND s.time_seconds > 0
        ''',
          [startStr, endStr],
        );
        return ((row.first['value'] as int?) ?? 0).toDouble();
    }
  }
}
