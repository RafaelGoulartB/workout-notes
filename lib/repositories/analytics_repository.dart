import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';

/// Time bucketing used for the anaerobic volume trend chart.
enum AnaerobicTrendBucket { week, month, year }

/// Repository for statistics, progress charts, PRs, heatmap, and trends.
class AnalyticsRepository extends BaseRepository {
  /// A working set that really happened: completed, not a warm-up. Every
  /// statistic below joins `workouts w` and also requires [_finished], so
  /// planned or abandoned sessions never leak into the numbers.
  static const _workSet = 's.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0';
  static const _finished = 'w.end_time IS NOT NULL';

  // ===================================================================
  // EXERCISE HISTORY
  // ===================================================================

  /// Sessions of one exercise, oldest first (only the newest [limit] when
  /// given). Only completed, non-warm-up sets of finished workouts count. Each
  /// session carries its best estimated 1RM (the maximum over its sets, not
  /// the estimate of the heaviest set) and the sets themselves.
  Future<Map<String, dynamic>> getExerciseHistory(
    String exerciseId, {
    int? limit,
  }) async {
    final db = await this.db;
    final results = await db.rawQuery(
      '''
      SELECT s.weight AS weight, s.reps AS reps,
        w.date AS date, w.id AS workout_id
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ee.exercise_id = ? AND $_workSet AND $_finished
      ORDER BY w.date ASC, w.start_time ASC, ee.order_index ASC,
        s.order_index ASC
    ''',
      [exerciseId],
    );

    // Group by workout (two sessions on the same day stay separate).
    final byWorkout = <String, List<Map<String, dynamic>>>{};
    for (final row in results) {
      byWorkout.putIfAbsent(row['workout_id'] as String, () => []).add(row);
    }

    final sessions = byWorkout.entries.toList();
    final recent = limit == null || limit >= sessions.length
        ? sessions
        : sessions.sublist(sessions.length - limit);

    final history = <Map<String, dynamic>>[];
    for (final entry in recent) {
      final sets = <Map<String, dynamic>>[];
      var maxWeight = 0.0;
      var totalVolume = 0.0;
      var totalReps = 0;
      double? best1rm;
      Map<String, dynamic>? bestSet;
      double bestSetScore = -1;
      for (final row in entry.value) {
        final weight = (row['weight'] as num?)?.toDouble() ?? 0.0;
        final reps = (row['reps'] as num?)?.toInt() ?? 0;
        final e1rm = strengthE1rm(weight, reps);
        sets.add({'weight': weight, 'reps': reps, 'e1rm': e1rm});
        if (weight > maxWeight) maxWeight = weight;
        totalVolume += weight * reps;
        totalReps += reps;
        if (e1rm != null && (best1rm == null || e1rm > best1rm)) {
          best1rm = e1rm;
        }
        // Best set: highest e1RM, else heaviest, else most reps.
        final score = e1rm ?? (weight > 0 ? weight / 1000 : reps / 1000000);
        if (score > bestSetScore) {
          bestSetScore = score;
          bestSet = {'weight': weight, 'reps': reps};
        }
      }
      history.add({
        'date': entry.value.first['date'] as String,
        'max_weight': maxWeight,
        'total_volume': totalVolume,
        'total_sets': sets.length,
        'total_reps': totalReps,
        'estimated_1rm': best1rm,
        'workout_id': entry.key,
        'best_set': bestSet ?? {'weight': 0.0, 'reps': 0},
        'sets': sets,
      });
    }

    double best(String key) => history.fold<double>(0, (a, h) {
      final v = (h[key] as num?)?.toDouble() ?? 0;
      return v > a ? v : a;
    });

    return {
      'exercise_id': exerciseId,
      'history': history,
      'best_weight': best('max_weight'),
      'best_volume': best('total_volume'),
      'best_1rm': best('estimated_1rm'),
    };
  }

  // ===================================================================
  // VOLUME
  // ===================================================================

  Future<Map<String, dynamic>> getWeeklyVolume({int weeks = 4}) async {
    final db = await this.db;
    final now = DateTime.now();
    final results = <String, dynamic>{};

    for (int w = 0; w < weeks; w++) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (w * 7)));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final startStr = weekStart.toIso8601String().substring(0, 10);
      final endStr = weekEnd.toIso8601String().substring(0, 10);

      final rows = await db.rawQuery(
        '''
        SELECT ec.name as category, ec.color as color,
          SUM(s.weight * s.reps) as volume, COUNT(s.id) as total_sets
        FROM sets s
        JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
        JOIN exercises e ON ee.exercise_id = e.id
        JOIN exercise_categories ec ON e.category_id = ec.id
        JOIN workouts w ON ee.workout_id = w.id
        WHERE w.date >= ? AND w.date <= ? AND $_workSet AND $_finished
        GROUP BY ec.id
        ORDER BY volume DESC
      ''',
        [startStr, endStr],
      );

      results['week_${w + 1}'] = {
        'start': startStr,
        'end': endStr,
        'categories': rows,
      };
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> getMonthlyVolume({int months = 6}) async {
    final db = await this.db;
    final now = DateTime.now();
    final results = <Map<String, dynamic>>[];

    for (int m = months - 1; m >= 0; m--) {
      final monthDate = DateTime(now.year, now.month - m, 1);
      final monthStr =
          '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';

      final row = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(s.weight * s.reps), 0) as volume,
          COUNT(DISTINCT w.id) as workouts
        FROM sets s
        JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
        JOIN workouts w ON ee.workout_id = w.id
        WHERE w.date LIKE ? AND $_workSet AND $_finished
      ''',
        ['$monthStr%'],
      );

      if (row.isNotEmpty) {
        results.add({
          'month': '$monthStr-01',
          'volume': (row.first['volume'] as num?)?.toDouble() ?? 0,
          'workouts': row.first['workouts'] as int? ?? 0,
        });
      }
    }

    return results;
  }

  // ===================================================================
  // FREQUENCY & CONSISTENCY
  // ===================================================================

  Future<Map<String, int>> getYearlyHeatmapData(int year) async {
    final db = await this.db;
    final startDate = '$year-01-01';
    final endDate = '$year-12-31';
    final rows = await db.rawQuery(
      '''
      SELECT w.date, COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      LEFT JOIN exercise_entries ee ON w.id = ee.workout_id
      LEFT JOIN sets s ON ee.id = s.exercise_entry_id AND $_workSet
      WHERE w.date >= ? AND w.date <= ? AND $_finished
      GROUP BY w.date
      ORDER BY w.date
    ''',
      [startDate, endDate],
    );

    final Map<String, int> result = {};
    for (final row in rows) {
      result[row['date'] as String] = ((row['volume'] as num?)?.toDouble() ?? 0)
          .toInt();
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getWorkoutDatesInRange(
    DateTime start,
  ) async {
    final db = await this.db;
    final startStr = start.toIso8601String().substring(0, 10);
    return db.rawQuery(
      '''
      SELECT date, duration_seconds, start_time,
        CAST(strftime('%w', date) AS INTEGER) as day_of_week
      FROM workouts
      WHERE date >= ? AND end_time IS NOT NULL
      ORDER BY date ASC
    ''',
      [startStr],
    );
  }

  // ===================================================================
  // VOLUME BY CATEGORY
  // ===================================================================

  Future<List<Map<String, dynamic>>> getVolumeByCategory() async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT ec.id, ec.name, ec.color, ec.energy_system,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN workouts w ON ee.workout_id = w.id AND $_finished
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      GROUP BY ec.id
      ORDER BY volume DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getWeeklyVolumeByCategory({
    int weeks = 12,
  }) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: weeks * 7))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(
      '''
      SELECT w.date, ec.id as category_id, ec.name as category_name,
        ec.color as category_color,
        COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      WHERE w.date >= ? AND $_finished
      GROUP BY w.date, ec.id
      ORDER BY w.date
    ''',
      [start],
    );
  }

  Future<List<Map<String, dynamic>>> getTopExercisesByVolume({
    int limit = 10,
  }) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT e.id, e.name, ec.name as category_name, ec.color as category_color,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN workouts w ON ee.workout_id = w.id AND $_finished
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      GROUP BY e.id
      ORDER BY volume DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  Future<List<Map<String, dynamic>>> getEnergySystemDistribution() async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT ec.energy_system,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN workouts w ON ee.workout_id = w.id AND $_finished
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      GROUP BY ec.energy_system
    ''');
  }

  // ===================================================================
  // ANAEROBIC VOLUME (strength only, scoped to a date range)
  // ===================================================================

  /// Volume by muscle group (anaerobic only) for a date range.
  /// `bySets = true` counts sets; otherwise sums weight*reps.
  Future<List<Map<String, dynamic>>> getAnaerobicVolumeByCategory(
    DateTime start,
    DateTime end, {
    required bool bySets,
  }) async {
    final db = await this.db;
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final valueExpr = bySets
        ? 'COUNT(s.id)'
        : 'COALESCE(SUM(s.weight * s.reps), 0)';
    return db.rawQuery(
      '''
      SELECT ec.id, ec.name, ec.color,
        $valueExpr as volume,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'anaerobic' AND $_finished
        AND w.date >= ? AND w.date <= ?
      GROUP BY ec.id
      ORDER BY volume DESC
    ''',
      [startStr, endStr],
    );
  }

  /// Top exercises (anaerobic only) for a date range.
  Future<List<Map<String, dynamic>>> getAnaerobicTopExercises(
    DateTime start,
    DateTime end, {
    required bool bySets,
    int limit = 5,
  }) async {
    final db = await this.db;
    final startStr = start.toIso8601String().substring(0, 10);
    final endStr = end.toIso8601String().substring(0, 10);
    final valueExpr = bySets
        ? 'COUNT(s.id)'
        : 'COALESCE(SUM(s.weight * s.reps), 0)';
    return db.rawQuery(
      '''
      SELECT e.id, e.name, ec.name as category_name, ec.color as category_color,
        $valueExpr as volume,
        COUNT(s.id) as sets_count
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'anaerobic' AND $_finished
        AND w.date >= ? AND w.date <= ?
      GROUP BY e.id
      ORDER BY volume DESC
      LIMIT ?
    ''',
      [startStr, endStr, limit],
    );
  }

  /// Time-bucketed trend of anaerobic volume.
  /// - [AnaerobicTrendBucket.week]   → last 12 ISO weeks
  /// - [AnaerobicTrendBucket.month]  → last 12 months
  /// - [AnaerobicTrendBucket.year]   → last 5 years
  Future<List<Map<String, dynamic>>> getAnaerobicVolumeTrend(
    DateTime end,
    AnaerobicTrendBucket bucket, {
    required bool bySets,
  }) async {
    final db = await this.db;
    final valueExpr = bySets
        ? 'COUNT(s.id)'
        : 'COALESCE(SUM(s.weight * s.reps), 0)';

    final List<Map<String, dynamic>> results = [];

    if (bucket == AnaerobicTrendBucket.week) {
      // 12 weeks ending on the week of `end`. Monday-anchored.
      const count = 12;
      final endMonday = end.subtract(Duration(days: end.weekday - 1));
      for (int i = count - 1; i >= 0; i--) {
        final weekStart = endMonday.subtract(Duration(days: i * 7));
        final weekEnd = weekStart.add(const Duration(days: 6));
        final rows = await db.rawQuery(
          '''
          SELECT $valueExpr as volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE ec.energy_system = 'anaerobic'
            AND $_workSet AND $_finished
            AND w.date >= ? AND w.date <= ?
        ''',
          [
            weekStart.toIso8601String().substring(0, 10),
            weekEnd.toIso8601String().substring(0, 10),
          ],
        );
        results.add({
          'bucket_start': weekStart.toIso8601String().substring(0, 10),
          'volume': (rows.first['volume'] as num?)?.toDouble() ?? 0,
        });
      }
      return results;
    } else if (bucket == AnaerobicTrendBucket.month) {
      const count = 12;
      for (int i = count - 1; i >= 0; i--) {
        final ref = DateTime(end.year, end.month - i, 1);
        final nextMonth = ref.month == 12
            ? DateTime(ref.year + 1, 1, 1)
            : DateTime(ref.year, ref.month + 1, 1);
        final lastDay = nextMonth.subtract(const Duration(days: 1));
        final monthStr = '${ref.year}-${ref.month.toString().padLeft(2, '0')}';
        final rows = await db.rawQuery(
          '''
          SELECT $valueExpr as volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE ec.energy_system = 'anaerobic'
            AND $_workSet AND $_finished
            AND w.date >= ? AND w.date <= ?
        ''',
          ['$monthStr-01', lastDay.toIso8601String().substring(0, 10)],
        );
        results.add({
          'bucket_start': '$monthStr-01',
          'volume': (rows.first['volume'] as num?)?.toDouble() ?? 0,
        });
      }
      return results;
    } else {
      // year: last 5 calendar years.
      const count = 5;
      for (int i = count - 1; i >= 0; i--) {
        final year = end.year - i;
        final rows = await db.rawQuery(
          '''
          SELECT $valueExpr as volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE ec.energy_system = 'anaerobic'
            AND $_workSet AND $_finished
            AND w.date >= ? AND w.date <= ?
        ''',
          ['$year-01-01', '$year-12-31'],
        );
        results.add({
          'bucket_start': '$year-01-01',
          'volume': (rows.first['volume'] as num?)?.toDouble() ?? 0,
        });
      }
      return results;
    }
  }

  // ===================================================================
  // PERFORMANCE & INTENSITY
  // ===================================================================

  Future<List<Map<String, dynamic>>> getRpeTrend({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT w.date, AVG(s.rpe) as avg_rpe,
        COUNT(s.id) as sets_with_rpe
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE s.rpe IS NOT NULL AND $_workSet AND $_finished
      GROUP BY w.id
      ORDER BY w.date DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  Future<List<Map<String, dynamic>>> getWorkoutDensity({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT w.date, w.duration_seconds,
        COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      WHERE w.duration_seconds IS NOT NULL AND w.duration_seconds > 0
        AND $_finished
      GROUP BY w.id
      ORDER BY w.date DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  /// Heaviest weighted set per exercise (completed working sets of finished
  /// workouts), with its reps and date.
  Future<List<Map<String, dynamic>>> getPersonalRecords({
    int limit = 20,
  }) async {
    final db = await this.db;
    // A single MAX() aggregate makes SQLite take the bare columns (reps,
    // date) from the row holding the maximum weight.
    return db.rawQuery(
      '''
      SELECT e.id as exercise_id, e.name as exercise_name,
        ec.name as category_name, ec.color as category_color,
        MAX(s.weight) as best_weight,
        s.reps as best_reps,
        w.date as date
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN workouts w ON ee.workout_id = w.id AND $_finished
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      GROUP BY e.id
      HAVING best_weight > 0
      ORDER BY best_weight DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  // ===================================================================
  // RECOVERY & FEELING
  // ===================================================================

  Future<List<Map<String, dynamic>>> getFeelingTrend({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT date, feeling_rating, duration_seconds
      FROM workouts
      WHERE feeling_rating IS NOT NULL AND end_time IS NOT NULL
      ORDER BY date DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  Future<List<Map<String, dynamic>>> getFeelingVsVolume() async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT w.feeling_rating,
        AVG(s.weight * s.reps) as avg_volume,
        COUNT(DISTINCT w.id) as workout_count
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      WHERE w.feeling_rating IS NOT NULL AND $_finished
      GROUP BY w.feeling_rating
      ORDER BY w.feeling_rating
    ''');
  }

  // ===================================================================
  // DURATION
  // ===================================================================

  Future<List<Map<String, dynamic>>> getDurationTrend({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT date, duration_seconds
      FROM workouts
      WHERE duration_seconds IS NOT NULL AND duration_seconds > 0
        AND end_time IS NOT NULL
      ORDER BY date DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  // ===================================================================
  // BODY WEIGHT WITH VOLUME
  // ===================================================================

  Future<List<Map<String, dynamic>>> getBodyWeightWithVolume({
    int months = 6,
  }) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: months * 30))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(
      '''
      SELECT bm.date, bm.value as weight, bm.unit,
        (SELECT COALESCE(SUM(s2.weight * s2.reps), 0)
         FROM workouts w2
         JOIN exercise_entries ee2 ON w2.id = ee2.workout_id
         JOIN sets s2 ON s2.exercise_entry_id = ee2.id
           AND s2.is_complete = 1 AND IFNULL(s2.is_warmup, 0) = 0
         WHERE w2.date = bm.date AND w2.end_time IS NOT NULL
        ) as volume
      FROM body_measurements bm
      WHERE bm.type = 'weight' AND bm.date >= ?
      ORDER BY bm.date ASC
    ''',
      [start],
    );
  }

  // ===================================================================
  // MONTHLY REPORT
  // ===================================================================

  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    final db = await this.db;
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';

    final workouts = await db.rawQuery(
      '''
      SELECT COUNT(*) as count,
        COALESCE(SUM(duration_seconds), 0) as total_duration,
        AVG(feeling_rating) as avg_feeling,
        COUNT(CASE WHEN feeling_rating IS NOT NULL THEN 1 END) as feeling_count
      FROM workouts
      WHERE date LIKE ? AND end_time IS NOT NULL
    ''',
      ['$monthStr%'],
    );

    final volume = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(s.weight * s.reps), 0) as total_volume,
        COUNT(s.id) as total_sets
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE w.date LIKE ? AND $_workSet AND $_finished
    ''',
      ['$monthStr%'],
    );

    final categoryVol = await db.rawQuery(
      '''
      SELECT ec.name, ec.color, COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      JOIN workouts w ON ee.workout_id = w.id
      WHERE w.date LIKE ? AND $_finished
      GROUP BY ec.id
      ORDER BY volume DESC
    ''',
      ['$monthStr%'],
    );

    final daysWithWorkouts =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
      SELECT COUNT(DISTINCT date) FROM workouts
      WHERE date LIKE ? AND end_time IS NOT NULL
    ''',
            ['$monthStr%'],
          ),
        ) ??
        0;

    return {
      'workout_count': (workouts.first['count'] as int?) ?? 0,
      'total_duration': (workouts.first['total_duration'] as int?) ?? 0,
      'avg_feeling': (workouts.first['avg_feeling'] as num?)?.toDouble(),
      'total_volume': (volume.first['total_volume'] as num?)?.toDouble() ?? 0,
      'total_sets': (volume.first['total_sets'] as int?) ?? 0,
      'days_with_workouts': daysWithWorkouts,
      'categories': categoryVol,
    };
  }

  Future<Map<String, dynamic>> getMonthComparison(int year, int month) async {
    final current = await getMonthlyReport(year, month);

    DateTime prevDate;
    if (month == 1) {
      prevDate = DateTime(year - 1, 12, 1);
    } else {
      prevDate = DateTime(year, month - 1, 1);
    }
    final previous = await getMonthlyReport(prevDate.year, prevDate.month);

    return {
      'current': current,
      'previous': previous,
      'delta_workouts':
          (current['workout_count'] as int) -
          (previous['workout_count'] as int),
      'delta_volume':
          (current['total_volume'] as double) -
          (previous['total_volume'] as double),
      'delta_sets':
          (current['total_sets'] as int) - (previous['total_sets'] as int),
    };
  }

  // ===================================================================
  // OVERVIEW STATS
  // ===================================================================

  /// Counts consecutive workout days ending today or yesterday.
  ///
  /// A streak older than yesterday is no longer current, so it must not stay
  /// visible as an active streak indefinitely.
  Future<int> _calculateStreak() async {
    final db = await this.db;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = today.toIso8601String().substring(0, 10);

    final rows = await db.rawQuery(
      'SELECT DISTINCT date FROM workouts WHERE date <= ? '
      'AND end_time IS NOT NULL ORDER BY date DESC',
      [todayKey],
    );

    if (rows.isEmpty) return 0;

    int streak = 1;
    DateTime prev = DateTime.parse(rows[0]['date'] as String);
    if (today.difference(prev).inDays > 1) return 0;

    for (int i = 1; i < rows.length; i++) {
      final curr = DateTime.parse(rows[i]['date'] as String);
      if (prev.difference(curr).inDays == 1) {
        streak++;
        prev = curr;
      } else {
        break;
      }
    }

    return streak;
  }

  Future<int> getCurrentWorkoutStreak() => _calculateStreak();

  Future<Map<String, dynamic>> getWorkoutOverviewStats() async {
    final db = await this.db;

    final rows = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT CASE WHEN w.end_time IS NOT NULL THEN w.id END)
          AS total_workouts,
        COUNT(CASE WHEN w.end_time IS NOT NULL
          AND $_workSet THEN s.id END)
          AS total_sets,
        COALESCE(SUM(CASE WHEN w.end_time IS NOT NULL
          AND $_workSet
          THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END), 0)
          AS total_volume
      FROM workouts w
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
    ''');
    final totals = rows.first;
    final totalWorkouts = (totals['total_workouts'] as num?)?.toInt() ?? 0;
    final totalSets = (totals['total_sets'] as num?)?.toInt() ?? 0;
    final totalVolume = (totals['total_volume'] as num?)?.toDouble() ?? 0.0;

    final currentStreak = await _calculateStreak();

    return {
      'total_workouts': totalWorkouts,
      'total_sets': totalSets,
      'total_volume': totalVolume,
      'current_streak': currentStreak,
    };
  }

  // ===================================================================
  // CARDIO STATS
  // ===================================================================

  /// Weekly cardio distance grouped by modality (running, cycling, etc.)
  Future<List<Map<String, dynamic>>> getCardioWeeklyDistance({
    int weeks = 12,
  }) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: weeks * 7))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(
      '''
      SELECT w.date,
        ec.name as modality, ec.color as modality_color,
        s.distance, s.time_seconds, w.id as workout_id,
        e.name as exercise_name, e.id as exercise_id
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'aerobic' AND $_workSet AND $_finished
        AND s.distance IS NOT NULL AND s.distance > 0
        AND w.date >= ?
      ORDER BY w.date ASC
    ''',
      [start],
    );
  }

  /// Monthly cardio stats (distance, time, sessions) by modality.
  Future<List<Map<String, dynamic>>> getCardioMonthlyDistance({
    int months = 6,
  }) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: months * 31))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(
      '''
      SELECT substr(w.date, 1, 7) as month,
        ec.name as modality, ec.color as modality_color,
        SUM(s.distance) as total_distance,
        SUM(s.time_seconds) as total_time,
        COUNT(DISTINCT w.id) as sessions
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'aerobic' AND $_workSet AND $_finished
        AND s.distance IS NOT NULL AND s.distance > 0
        AND w.date >= ?
      GROUP BY month, ec.id
      ORDER BY month ASC
    ''',
      [start],
    );
  }

  /// Total distance grouped by modality (for pie chart).
  Future<List<Map<String, dynamic>>> getCardioDistanceByModality() async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT ec.id, ec.name as modality, ec.color as modality_color,
        COALESCE(SUM(s.distance), 0) as total_distance,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN workouts w ON ee.workout_id = w.id AND $_finished
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      WHERE ec.energy_system = 'aerobic' AND s.distance IS NOT NULL AND s.distance > 0
      GROUP BY ec.id
      ORDER BY total_distance DESC
    ''');
  }

  /// Pace trend (distance + time per session) for a specific cardio exercise.
  Future<List<Map<String, dynamic>>> getPaceTrend(
    String exerciseId, {
    int limit = 30,
  }) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT w.date,
        SUM(s.distance) as total_distance,
        SUM(s.time_seconds) as total_time,
        COUNT(s.id) as sets_count
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ee.exercise_id = ? AND $_workSet AND $_finished
        AND s.distance IS NOT NULL AND s.distance > 0
        AND s.time_seconds IS NOT NULL AND s.time_seconds > 0
      GROUP BY w.id
      ORDER BY w.date ASC
      LIMIT ?
    ''',
      [exerciseId, limit],
    );
  }

  /// Cardio personal records: best distance, best pace, longest duration per exercise.
  Future<List<Map<String, dynamic>>> getCardioPRs({int limit = 20}) async {
    final db = await this.db;
    return db.rawQuery(
      '''
      SELECT e.id as exercise_id, e.name as exercise_name,
        ec.name as modality, ec.color as modality_color,
        MAX(s.distance) as best_distance,
        MAX(s.time_seconds) as best_time,
        MIN(CAST(s.time_seconds AS REAL) / NULLIF(s.distance, 0)) as best_pace
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN workouts w ON ee.workout_id = w.id AND $_finished
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_workSet
      WHERE ec.energy_system = 'aerobic'
        AND s.distance IS NOT NULL AND s.distance > 0
      GROUP BY e.id
      HAVING best_distance > 0
      ORDER BY best_distance DESC
      LIMIT ?
    ''',
      [limit],
    );
  }

  /// Overall cardio stats for a given month.
  Future<Map<String, dynamic>> getMonthlyCardioStats(
    int year,
    int month,
  ) async {
    final db = await this.db;
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';
    final row = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(s.distance), 0) as total_distance,
        COALESCE(SUM(s.time_seconds), 0) as total_time,
        COUNT(DISTINCT w.id) as cardio_sessions,
        COUNT(s.id) as cardio_sets
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'aerobic' AND $_workSet AND $_finished
        AND w.date LIKE ? AND s.distance IS NOT NULL AND s.distance > 0
    ''',
      ['$monthStr%'],
    );

    if (row.isEmpty) {
      return {
        'total_distance': 0.0,
        'total_time': 0,
        'cardio_sessions': 0,
        'cardio_sets': 0,
      };
    }
    return {
      'total_distance': (row.first['total_distance'] as num?)?.toDouble() ?? 0,
      'total_time': (row.first['total_time'] as int?) ?? 0,
      'cardio_sessions': (row.first['cardio_sessions'] as int?) ?? 0,
      'cardio_sets': (row.first['cardio_sets'] as int?) ?? 0,
    };
  }
}
