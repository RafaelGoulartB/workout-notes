import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/repositories/workout_sql.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Repository for user-defined goals: CRUD + progress computation.
class GoalRepository extends BaseRepository {
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

  // Transaction-aware variants (AI proposals fold them into their approval
  // transaction). Each write must hit exactly one row.

  Future<Goal?> getByIdIn(DatabaseExecutor executor, String id) async {
    final rows = await executor.query(
      'user_goals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Goal.fromMap(rows.first);
  }

  /// Plain insert (no replace): a repeated insert of the same id fails.
  Future<void> insertIn(DatabaseExecutor executor, Goal goal) =>
      executor.insert('user_goals', goal.toMap());

  Future<void> updateIn(DatabaseExecutor executor, Goal goal) async {
    final changed = await executor.update(
      'user_goals',
      goal.toMap(),
      where: 'id = ?',
      whereArgs: [goal.id],
    );
    if (changed != 1) throw StateError('goal ${goal.id} not found');
  }

  Future<void> toggleActiveIn(
    DatabaseExecutor executor,
    String id,
    bool isActive,
  ) async {
    final changed = await executor.update(
      'user_goals',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) throw StateError('goal $id not found');
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
    final today = dayOf(now ?? DateTime.now());
    if (period == GoalPeriod.weekly) {
      final start = mondayOf(today);
      return (start, addDays(start, 6));
    }
    final start = DateTime(today.year, today.month, 1);
    final nextMonth = DateTime(today.year, today.month + 1, 1);
    return (start, addDays(nextMonth, -1));
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
        ref = addDays(start, -1);
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
  //
  // What counts toward a goal (shared with the analytics screens through
  // [WorkoutSql]): completed, non-warm-up sets of finished workouts, plus
  // completed run activities for cardio goals. Planned, open or unchecked
  // work never counts.
  //
  // A "days" goal counts distinct calendar days that have at least one
  // qualifying workout or run, so two sessions on the same day are one day.

  /// Computes the current progress for the given goal.
  Future<GoalProgress> getProgress(Goal goal) async {
    final (start, end) = currentPeriod(goal.period);
    final values = await _valuesForRanges(goal.scope, goal.metric, [
      (start, end),
    ]);
    return _buildProgress(goal, values.single, start, end);
  }

  /// Computes the current progress of several goals with one query per
  /// distinct (scope, metric, period) instead of one per goal.
  Future<Map<String, GoalProgress>> getProgressForGoals(
    Iterable<Goal> goals,
  ) async {
    final groups = <(GoalScope, GoalMetric, GoalPeriod), List<Goal>>{};
    for (final goal in goals) {
      groups
          .putIfAbsent((goal.scope, goal.metric, goal.period), () => [])
          .add(goal);
    }
    final result = <String, GoalProgress>{};
    for (final entry in groups.entries) {
      final (scope, metric, period) = entry.key;
      final (start, end) = currentPeriod(period);
      final value = (await _valuesForRanges(scope, metric, [
        (start, end),
      ])).single;
      for (final goal in entry.value) {
        result[goal.id] = _buildProgress(goal, value, start, end);
      }
    }
    return result;
  }

  /// Computes the current progress and the past [historyCount] period
  /// results, reading the whole span with a single query.
  Future<(GoalProgress, List<GoalPeriodResult>)> getProgressWithHistory(
    Goal goal, {
    int historyCount = 6,
  }) async {
    final past = pastPeriods(goal.period, historyCount + 1);
    // The first entry is the current period.
    final ranges = past.take(historyCount + 1).toList();
    final values = await _valuesForRanges(goal.scope, goal.metric, ranges);
    final (currentStart, currentEnd) = ranges.first;
    final current = _buildProgress(
      goal,
      values.first,
      currentStart,
      currentEnd,
    );
    final results = <GoalPeriodResult>[
      for (var i = 1; i < ranges.length; i++)
        GoalPeriodResult(
          start: ranges[i].$1,
          end: ranges[i].$2,
          value: values[i],
          targetValue: goal.targetValue,
          wasCompleted: values[i] >= goal.targetValue,
        ),
    ];
    return (current, results);
  }

  /// Returns the list of workouts that contributed to the goal's progress
  /// in the current period, most recent first.
  /// - For volume/distance/time: the value contributed by that workout.
  /// - For days: contributedValue is always 1.0 per workout or run; several
  ///   entries on the same day still count as a single day in the progress.
  Future<List<ContributingWorkout>> getContributingWorkouts(Goal goal) async {
    final db = await this.db;
    final (start, end) = currentPeriod(goal.period);
    final startStr = dateKey(start);
    final endStr = dateKey(end);
    final endExclusive = dateKey(addDays(end, 1));
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
          WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.countedSet}
            AND ec.energy_system = ?
            AND s.weight > 0 AND s.reps > 0
          GROUP BY w.id
          ORDER BY w.date DESC
        ''',
          [startStr, endStr, energySystem],
        );
        return _contributions(rows);

      case GoalMetric.days:
        // Finished workouts with at least one performed set of the goal's
        // scope, plus (for cardio) completed run activities.
        final rows = await db.rawQuery(
          '''
          SELECT w.id as workout_id, w.date
          FROM workouts w
          WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.finished}
            AND EXISTS (
              SELECT 1
              FROM exercise_entries ee
              JOIN sets s ON s.exercise_entry_id = ee.id
              JOIN exercises e ON ee.exercise_id = e.id
              JOIN exercise_categories ec ON e.category_id = ec.id
              WHERE ee.workout_id = w.id
                AND ${WorkoutSql.workSet}
                AND ec.energy_system = ?
            )
          ${goal.scope == GoalScope.aerobic ? '''
          UNION ALL
          SELECT ra.id AS workout_id, substr(ra.started_at, 1, 10) AS date
          FROM run_activities ra
          WHERE ra.status = 'completed'
            AND ra.started_at >= ?
            AND ra.started_at < ?
          ''' : ''}
          ORDER BY date DESC
        ''',
          [
            startStr,
            endStr,
            energySystem,
            if (goal.scope == GoalScope.aerobic) startStr,
            if (goal.scope == GoalScope.aerobic) endExclusive,
          ],
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
          SELECT workout_id, date, value, set_count FROM (
            SELECT w.id as workout_id, w.date,
              SUM(s.distance) as value,
              COUNT(s.id) as set_count
            FROM sets s
            JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
            JOIN exercises e ON ee.exercise_id = e.id
            JOIN exercise_categories ec ON e.category_id = ec.id
            JOIN workouts w ON ee.workout_id = w.id
            WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.countedSet}
              AND ec.energy_system = 'aerobic'
              AND s.distance IS NOT NULL AND s.distance > 0
            GROUP BY w.id
            UNION ALL
            SELECT ra.id AS workout_id, substr(ra.started_at, 1, 10) AS date,
              ra.distance_meters / 1000.0 AS value, 0 AS set_count
            FROM run_activities ra
            WHERE ra.status = 'completed' AND ra.distance_meters > 0
              AND ra.started_at >= ?
              AND ra.started_at < ?
          ) ORDER BY date DESC
        ''',
          [startStr, endStr, startStr, endExclusive],
        );
        return _contributions(rows);

      case GoalMetric.time:
        final rows = await db.rawQuery(
          '''
          SELECT workout_id, date, value, set_count FROM (
            SELECT w.id as workout_id, w.date,
              SUM(s.time_seconds) as value,
              COUNT(s.id) as set_count
            FROM sets s
            JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
            JOIN exercises e ON ee.exercise_id = e.id
            JOIN exercise_categories ec ON e.category_id = ec.id
            JOIN workouts w ON ee.workout_id = w.id
            WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.countedSet}
              AND ec.energy_system = 'aerobic'
              AND s.time_seconds IS NOT NULL AND s.time_seconds > 0
            GROUP BY w.id
            UNION ALL
            SELECT ra.id AS workout_id, substr(ra.started_at, 1, 10) AS date,
              CASE WHEN ra.moving_time_seconds > 0 THEN ra.moving_time_seconds
                ELSE ra.duration_seconds END AS value, 0 AS set_count
            FROM run_activities ra
            WHERE ra.status = 'completed'
              AND (ra.moving_time_seconds > 0 OR ra.duration_seconds > 0)
              AND ra.started_at >= ?
              AND ra.started_at < ?
          ) ORDER BY date DESC
        ''',
          [startStr, endStr, startStr, endExclusive],
        );
        return _contributions(rows);
    }
  }

  static List<ContributingWorkout> _contributions(
    List<Map<String, Object?>> rows,
  ) => rows
      .where((r) => ((r['value'] as num?) ?? 0) > 0)
      .map(
        (r) => ContributingWorkout(
          workoutId: r['workout_id'] as String,
          date: r['date'] as String,
          contributedValue: (r['value'] as num?)?.toDouble() ?? 0,
          setCount: (r['set_count'] as num?)?.toInt() ?? 0,
        ),
      )
      .toList();

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
    final values = (await _valuesForRanges(
      scope,
      metric,
      ranges,
    )).where((v) => v > 0).toList();
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

  /// The metric's value for each of [ranges] (inclusive day ranges), read with
  /// one query over the whole span and bucketed per range in Dart.
  Future<List<double>> _valuesForRanges(
    GoalScope scope,
    GoalMetric metric,
    List<(DateTime, DateTime)> ranges,
  ) async {
    if (ranges.isEmpty) return const [];
    var from = ranges.first.$1;
    var to = ranges.first.$2;
    for (final (start, end) in ranges) {
      if (start.isBefore(from)) from = start;
      if (end.isAfter(to)) to = end;
    }
    final daily = await _dailyValues(scope, metric, from, to);
    return [
      for (final (start, end) in ranges)
        _sumBetween(daily, dateKey(start), dateKey(end)),
    ];
  }

  static double _sumBetween(
    Map<String, double> daily,
    String startKey,
    String endKey,
  ) {
    var total = 0.0;
    for (final entry in daily.entries) {
      if (entry.key.compareTo(startKey) >= 0 &&
          entry.key.compareTo(endKey) <= 0) {
        total += entry.value;
      }
    }
    return total;
  }

  /// Per-day metric values between [from] and [to] (inclusive), keyed by
  /// `yyyy-MM-dd`. For the `days` metric every active day has value 1.
  ///
  /// Run activities are matched with `started_at >= day AND started_at <
  /// nextDay`, the same rows `substr(started_at, 1, 10)` selects (the stored
  /// text starts with the date) but able to use the started_at indexes.
  Future<Map<String, double>> _dailyValues(
    GoalScope scope,
    GoalMetric metric,
    DateTime from,
    DateTime to,
  ) async {
    final db = await this.db;
    final fromKey = dateKey(from);
    final toKey = dateKey(to);
    final toExclusive = dateKey(addDays(to, 1));
    final energySystem = scope.value;
    final String sql;
    final List<Object?> args;

    switch (metric) {
      case GoalMetric.volume:
        // Sum of (weight * reps) only for sets whose exercise belongs to
        // a category of the goal's scope (anaerobic for strength).
        sql =
            '''
          SELECT w.date AS day, SUM(s.weight * s.reps) AS value
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.countedSet}
            AND ec.energy_system = ?
            AND s.weight > 0 AND s.reps > 0
          GROUP BY w.date
        ''';
        args = [fromKey, toKey, energySystem];

      case GoalMetric.days:
        // Active calendar days across finished workouts and (cardio) tracked
        // run activities. UNION keeps two records on the same day from
        // inflating a days goal.
        sql =
            '''
          SELECT DISTINCT day, 1.0 AS value FROM (
            SELECT w.date AS day
            FROM workouts w
            WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.finished}
              AND EXISTS (
                SELECT 1
                FROM exercise_entries ee
                JOIN sets s ON s.exercise_entry_id = ee.id
                JOIN exercises e ON ee.exercise_id = e.id
                JOIN exercise_categories ec ON e.category_id = ec.id
                WHERE ee.workout_id = w.id
                  AND ${WorkoutSql.workSet}
                  AND ec.energy_system = ?
              )
            ${scope == GoalScope.aerobic ? '''
            UNION
            SELECT substr(ra.started_at, 1, 10) AS day
            FROM run_activities ra
            WHERE ra.status = 'completed'
              AND ra.started_at >= ?
              AND ra.started_at < ?
            ''' : ''}
          )
        ''';
        args = [
          fromKey,
          toKey,
          energySystem,
          if (scope == GoalScope.aerobic) fromKey,
          if (scope == GoalScope.aerobic) toExclusive,
        ];

      case GoalMetric.distance:
        // Aerobic goals use km. Tracked activities store meters, while legacy
        // cardio sets already store the user-facing distance unit.
        sql =
            '''
          SELECT day, SUM(value) AS value FROM (
            SELECT w.date AS day, s.distance AS value
            FROM sets s
            JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
            JOIN exercises e ON ee.exercise_id = e.id
            JOIN exercise_categories ec ON e.category_id = ec.id
            JOIN workouts w ON ee.workout_id = w.id
            WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.countedSet}
              AND ec.energy_system = 'aerobic'
              AND s.distance IS NOT NULL AND s.distance > 0
            UNION ALL
            SELECT substr(ra.started_at, 1, 10) AS day,
              ra.distance_meters / 1000.0 AS value
            FROM run_activities ra
            WHERE ra.status = 'completed' AND ra.distance_meters > 0
              AND ra.started_at >= ?
              AND ra.started_at < ?
          ) GROUP BY day
        ''';
        args = [fromKey, toKey, fromKey, toExclusive];

      case GoalMetric.time:
        // Prefer moving time for tracked activities, falling back to duration.
        sql =
            '''
          SELECT day, SUM(value) AS value FROM (
            SELECT w.date AS day, s.time_seconds AS value
            FROM sets s
            JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
            JOIN exercises e ON ee.exercise_id = e.id
            JOIN exercise_categories ec ON e.category_id = ec.id
            JOIN workouts w ON ee.workout_id = w.id
            WHERE w.date >= ? AND w.date <= ? AND ${WorkoutSql.countedSet}
              AND ec.energy_system = 'aerobic'
              AND s.time_seconds IS NOT NULL AND s.time_seconds > 0
            UNION ALL
            SELECT substr(ra.started_at, 1, 10) AS day,
              CASE WHEN ra.moving_time_seconds > 0
                THEN ra.moving_time_seconds ELSE ra.duration_seconds END
                AS value
            FROM run_activities ra
            WHERE ra.status = 'completed'
              AND ra.started_at >= ?
              AND ra.started_at < ?
          ) GROUP BY day
        ''';
        args = [fromKey, toKey, fromKey, toExclusive];
    }

    final rows = await db.rawQuery(sql, args);
    return {
      for (final row in rows)
        if (row['day'] != null)
          row['day'] as String: (row['value'] as num?)?.toDouble() ?? 0,
    };
  }
}
