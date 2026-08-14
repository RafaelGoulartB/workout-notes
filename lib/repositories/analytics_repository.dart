import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';

/// Time bucketing used for the anaerobic volume trend chart.
enum AnaerobicTrendBucket { week, month, year }

/// Repository for statistics, progress charts, PRs, heatmap, and trends.
class AnalyticsRepository extends BaseRepository {
  // ===================================================================
  // EXERCISE HISTORY
  // ===================================================================

  Future<Map<String, dynamic>> getExerciseHistory(String exerciseId, {int? limit}) async {
    final db = await this.db;
    final query = '''
      SELECT s.*, w.date, w.id as workout_id, ee.exercise_id
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ee.exercise_id = ? AND s.is_warmup = 0
      ORDER BY w.date ASC
    ''';

    final results = await db.rawQuery(query, [exerciseId]);
    final effectiveLimit = limit ?? results.length;

    // Group by date
    final Map<String, List<Map<String, dynamic>>> byDate = {};
    for (final row in results) {
      final date = row['date'] as String;
      byDate.putIfAbsent(date, () => []).add(row);
    }

    // Calculate stats per session
    final history = <Map<String, dynamic>>[];
    final entries = byDate.entries.toList();
    final recent = entries.reversed.take(effectiveLimit).toList().reversed.toList();

    for (final entry in recent) {
      final sets = entry.value;
      final weights = sets.map<double>((s) => (s['weight'] as num?)?.toDouble() ?? 0.0).toList();
      final reps = sets.map<int>((s) => (s['reps'] as int?) ?? 0).toList();
      final maxWeight = weights.isEmpty ? 0.0 : weights.reduce((a, b) => a > b ? a : b);
      final totalVolume = weights.asMap().entries.fold<double>(
        0.0, (sum, e) => sum + (e.value * reps[e.key]));
      final bestSetIndex = weights.indexOf(maxWeight);

      double? estimated1RM;
      if (maxWeight > 0 && reps[bestSetIndex] > 0) {
        // Epley formula: 1RM = weight * (1 + reps/30)
        estimated1RM = maxWeight * (1 + (reps[bestSetIndex] / 30));
      }

      final firstSet = entry.value.first;
      history.add({
        'date': entry.key,
        'max_weight': maxWeight,
        'total_volume': totalVolume,
        'total_sets': sets.length,
        'total_reps': reps.fold<int>(0, (a, b) => a + b),
        'estimated_1rm': estimated1RM,
        'workout_id': firstSet['workout_id'],
        'best_set': {
          'weight': maxWeight,
          'reps': reps[bestSetIndex],
        },
      });
    }

    // Best records
    double allMaxWeight = 0;
    double allMaxVolume = 0;
    if (history.isNotEmpty) {
      allMaxWeight = history
          .map((h) => (h['max_weight'] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);
      allMaxVolume = history
          .map((h) => (h['total_volume'] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);
    }

    return {
      'exercise_id': exerciseId,
      'history': history,
      'best_weight': allMaxWeight,
      'best_volume': allMaxVolume,
      'best_1rm': history.fold<double>(
        0, (a, b) => (b['estimated_1rm'] as double? ?? 0) > a
            ? (b['estimated_1rm'] as double? ?? 0) : a),
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

      final rows = await db.rawQuery('''
        SELECT ec.name as category, ec.color as color,
          SUM(s.weight * s.reps) as volume, COUNT(s.id) as total_sets
        FROM sets s
        JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
        JOIN exercises e ON ee.exercise_id = e.id
        JOIN exercise_categories ec ON e.category_id = ec.id
        JOIN workouts w ON ee.workout_id = w.id
        WHERE w.date >= ? AND w.date <= ? AND s.is_warmup = 0
        GROUP BY ec.id
        ORDER BY volume DESC
      ''', [startStr, endStr]);

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
      final monthStr = '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';

      final row = await db.rawQuery('''
        SELECT COALESCE(SUM(s.weight * s.reps), 0) as volume,
          COUNT(DISTINCT w.id) as workouts
        FROM sets s
        JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
        JOIN workouts w ON ee.workout_id = w.id
        WHERE w.date LIKE ? AND s.is_warmup = 0
      ''', ['$monthStr%']);

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
    final rows = await db.rawQuery('''
      SELECT w.date, COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      LEFT JOIN exercise_entries ee ON w.id = ee.workout_id
      LEFT JOIN sets s ON ee.id = s.exercise_entry_id AND s.is_warmup = 0
      WHERE w.date >= ? AND w.date <= ?
      GROUP BY w.date
      ORDER BY w.date
    ''', [startDate, endDate]);

    final Map<String, int> result = {};
    for (final row in rows) {
      result[row['date'] as String] = ((row['volume'] as num?)?.toDouble() ?? 0).toInt();
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getWorkoutDatesInRange(DateTime start) async {
    final db = await this.db;
    final startStr = start.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT date, duration_seconds, start_time,
        CAST(strftime('%w', date) AS INTEGER) as day_of_week
      FROM workouts
      WHERE date >= ?
      ORDER BY date ASC
    ''', [startStr]);
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
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY ec.id
      ORDER BY volume DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getWeeklyVolumeByCategory({int weeks = 12}) async {
    final db = await this.db;
    final start = DateTime.now().subtract(Duration(days: weeks * 7))
        .toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT w.date, ec.id as category_id, ec.name as category_name,
        ec.color as category_color,
        COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE w.date >= ?
      GROUP BY w.date, ec.id
      ORDER BY w.date
    ''', [start]);
  }

  Future<List<Map<String, dynamic>>> getTopExercisesByVolume({int limit = 10}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT e.id, e.name, ec.name as category_name, ec.color as category_color,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY e.id
      ORDER BY volume DESC
      LIMIT ?
    ''', [limit]);
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
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
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
    final valueExpr = bySets ? 'COUNT(s.id)' : 'COALESCE(SUM(s.weight * s.reps), 0)';
    return db.rawQuery('''
      SELECT ec.id, ec.name, ec.color,
        $valueExpr as volume,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'anaerobic'
        AND w.date >= ? AND w.date <= ?
      GROUP BY ec.id
      ORDER BY volume DESC
    ''', [startStr, endStr]);
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
    final valueExpr = bySets ? 'COUNT(s.id)' : 'COALESCE(SUM(s.weight * s.reps), 0)';
    return db.rawQuery('''
      SELECT e.id, e.name, ec.name as category_name, ec.color as category_color,
        $valueExpr as volume,
        COUNT(s.id) as sets_count
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'anaerobic'
        AND w.date >= ? AND w.date <= ?
      GROUP BY e.id
      ORDER BY volume DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
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
    final valueExpr = bySets ? 'COUNT(s.id)' : 'COALESCE(SUM(s.weight * s.reps), 0)';

    final List<Map<String, dynamic>> results = [];

    if (bucket == AnaerobicTrendBucket.week) {
      // 12 weeks ending on the week of `end`. Monday-anchored.
      const count = 12;
      final endMonday = end.subtract(Duration(days: end.weekday - 1));
      for (int i = count - 1; i >= 0; i--) {
        final weekStart = endMonday.subtract(Duration(days: i * 7));
        final weekEnd = weekStart.add(const Duration(days: 6));
        final rows = await db.rawQuery('''
          SELECT $valueExpr as volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE ec.energy_system = 'anaerobic'
            AND s.is_warmup = 0
            AND w.date >= ? AND w.date <= ?
        ''', [
          weekStart.toIso8601String().substring(0, 10),
          weekEnd.toIso8601String().substring(0, 10),
        ]);
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
        final monthStr =
            '${ref.year}-${ref.month.toString().padLeft(2, '0')}';
        final rows = await db.rawQuery('''
          SELECT $valueExpr as volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE ec.energy_system = 'anaerobic'
            AND s.is_warmup = 0
            AND w.date >= ? AND w.date <= ?
        ''', [
          '$monthStr-01',
          lastDay.toIso8601String().substring(0, 10),
        ]);
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
        final rows = await db.rawQuery('''
          SELECT $valueExpr as volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          JOIN exercises e ON ee.exercise_id = e.id
          JOIN exercise_categories ec ON e.category_id = ec.id
          JOIN workouts w ON ee.workout_id = w.id
          WHERE ec.energy_system = 'anaerobic'
            AND s.is_warmup = 0
            AND w.date >= ? AND w.date <= ?
        ''', ['$year-01-01', '$year-12-31']);
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
    return db.rawQuery('''
      SELECT w.date, AVG(s.rpe) as avg_rpe,
        COUNT(s.id) as sets_with_rpe
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE s.rpe IS NOT NULL AND s.is_warmup = 0
      GROUP BY w.id
      ORDER BY w.date DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getWorkoutDensity({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT w.date, w.duration_seconds,
        COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE w.duration_seconds IS NOT NULL AND w.duration_seconds > 0
      GROUP BY w.id
      ORDER BY w.date DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getPersonalRecords({int limit = 20}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT e.id as exercise_id, e.name as exercise_name,
        ec.name as category_name, ec.color as category_color,
        MAX(s.weight) as best_weight,
        (SELECT s2.reps FROM sets s2
          JOIN exercise_entries ee2 ON s2.exercise_entry_id = ee2.id
          WHERE ee2.exercise_id = e.id AND s2.is_warmup = 0
          AND s2.weight = (SELECT MAX(s3.weight) FROM sets s3
            JOIN exercise_entries ee3 ON s3.exercise_entry_id = ee3.id
            WHERE ee3.exercise_id = e.id AND s3.is_warmup = 0)
          LIMIT 1
        ) as best_reps,
        (SELECT w2.date FROM sets s2
          JOIN exercise_entries ee2 ON s2.exercise_entry_id = ee2.id
          JOIN workouts w2 ON ee2.workout_id = w2.id
          WHERE ee2.exercise_id = e.id AND s2.is_warmup = 0
          AND s2.weight = (SELECT MAX(s3.weight) FROM sets s3
            JOIN exercise_entries ee3 ON s3.exercise_entry_id = ee3.id
            WHERE ee3.exercise_id = e.id AND s3.is_warmup = 0)
          LIMIT 1
        ) as date
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY e.id
      HAVING best_weight > 0
      ORDER BY best_weight DESC
      LIMIT ?
    ''', [limit]);
  }

  // ===================================================================
  // RECOVERY & FEELING
  // ===================================================================

  Future<List<Map<String, dynamic>>> getFeelingTrend({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT date, feeling_rating, duration_seconds
      FROM workouts
      WHERE feeling_rating IS NOT NULL
      ORDER BY date DESC
      LIMIT ?
    ''', [limit]);
  }

  Future<List<Map<String, dynamic>>> getFeelingVsVolume() async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT w.feeling_rating,
        AVG(s.weight * s.reps) as avg_volume,
        COUNT(DISTINCT w.id) as workout_count
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE w.feeling_rating IS NOT NULL
      GROUP BY w.feeling_rating
      ORDER BY w.feeling_rating
    ''');
  }

  // ===================================================================
  // DURATION
  // ===================================================================

  Future<List<Map<String, dynamic>>> getDurationTrend({int limit = 50}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT date, duration_seconds
      FROM workouts
      WHERE duration_seconds IS NOT NULL AND duration_seconds > 0
      ORDER BY date DESC
      LIMIT ?
    ''', [limit]);
  }

  // ===================================================================
  // BODY WEIGHT WITH VOLUME
  // ===================================================================

  Future<List<Map<String, dynamic>>> getBodyWeightWithVolume({int months = 6}) async {
    final db = await this.db;
    final start = DateTime.now().subtract(Duration(days: months * 30))
        .toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT bm.date, bm.value as weight, bm.unit,
        (SELECT COALESCE(SUM(s2.weight * s2.reps), 0)
         FROM workouts w2
         JOIN exercise_entries ee2 ON w2.id = ee2.workout_id
         JOIN sets s2 ON s2.exercise_entry_id = ee2.id AND s2.is_warmup = 0
         WHERE w2.date = bm.date
        ) as volume
      FROM body_measurements bm
      WHERE bm.type = 'weight' AND bm.date >= ?
      ORDER BY bm.date ASC
    ''', [start]);
  }

  // ===================================================================
  // MONTHLY REPORT
  // ===================================================================

  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    final db = await this.db;
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';

    final workouts = await db.rawQuery('''
      SELECT COUNT(*) as count,
        COALESCE(SUM(duration_seconds), 0) as total_duration,
        AVG(feeling_rating) as avg_feeling,
        COUNT(CASE WHEN feeling_rating IS NOT NULL THEN 1 END) as feeling_count
      FROM workouts
      WHERE date LIKE ?
    ''', ['$monthStr%']);

    final volume = await db.rawQuery('''
      SELECT COALESCE(SUM(s.weight * s.reps), 0) as total_volume,
        COUNT(s.id) as total_sets
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE w.date LIKE ? AND s.is_warmup = 0
    ''', ['$monthStr%']);

    final categoryVol = await db.rawQuery('''
      SELECT ec.name, ec.color, COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      JOIN workouts w ON ee.workout_id = w.id
      WHERE w.date LIKE ?
      GROUP BY ec.id
      ORDER BY volume DESC
    ''', ['$monthStr%']);

    final daysWithWorkouts = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(DISTINCT date) FROM workouts WHERE date LIKE ?
    ''', ['$monthStr%'])) ?? 0;

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
      'delta_workouts': (current['workout_count'] as int) - (previous['workout_count'] as int),
      'delta_volume': (current['total_volume'] as double) - (previous['total_volume'] as double),
      'delta_sets': (current['total_sets'] as int) - (previous['total_sets'] as int),
    };
  }

  // ===================================================================
  // OVERVIEW STATS
  // ===================================================================

  /// Counts consecutive workout days ending at today (or most recent day ≤ today).
  Future<int> _calculateStreak() async {
    final db = await this.db;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final rows = await db.rawQuery(
      'SELECT DISTINCT date FROM workouts WHERE date <= ? '
      'AND end_time IS NOT NULL ORDER BY date DESC',
      [today],
    );

    if (rows.isEmpty) return 0;

    int streak = 1;
    DateTime prev = DateTime.parse(rows[0]['date'] as String);

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

  Future<Map<String, dynamic>> getWorkoutOverviewStats() async {
    final db = await this.db;

    final totalWorkouts = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM workouts WHERE end_time IS NOT NULL',
    )) ?? 0;

    final totalSets = Sqflite.firstIntValue(await db.rawQuery(
      '''
      SELECT COUNT(s.id) FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL
        AND s.is_complete = 1 AND s.is_warmup = 0
      ''',
    )) ?? 0;

    final volumeRows = await db.rawQuery('''
      SELECT COALESCE(SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)), 0)
        AS total_volume
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL
        AND s.is_complete = 1 AND s.is_warmup = 0
    ''');
    final totalVolume =
        (volumeRows.first['total_volume'] as num?)?.toDouble() ?? 0.0;

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
  Future<List<Map<String, dynamic>>> getCardioWeeklyDistance({int weeks = 12}) async {
    final db = await this.db;
    final start = DateTime.now().subtract(Duration(days: weeks * 7))
        .toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT w.date,
        ec.name as modality, ec.color as modality_color,
        s.distance, s.time_seconds, w.id as workout_id,
        e.name as exercise_name, e.id as exercise_id
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ec.energy_system = 'aerobic' AND s.is_warmup = 0
        AND s.distance IS NOT NULL AND s.distance > 0
        AND w.date >= ?
      ORDER BY w.date ASC
    ''', [start]);
  }

  /// Monthly cardio stats (distance, time, sessions) by modality.
  Future<List<Map<String, dynamic>>> getCardioMonthlyDistance({int months = 6}) async {
    final db = await this.db;
    final start = DateTime.now().subtract(Duration(days: months * 31))
        .toIso8601String().substring(0, 10);
    return db.rawQuery('''
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
      WHERE ec.energy_system = 'aerobic' AND s.is_warmup = 0
        AND s.distance IS NOT NULL AND s.distance > 0
        AND w.date >= ?
      GROUP BY month, ec.id
      ORDER BY month ASC
    ''', [start]);
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
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE ec.energy_system = 'aerobic' AND s.distance IS NOT NULL AND s.distance > 0
      GROUP BY ec.id
      ORDER BY total_distance DESC
    ''');
  }

  /// Pace trend (distance + time per session) for a specific cardio exercise.
  Future<List<Map<String, dynamic>>> getPaceTrend(String exerciseId, {int limit = 30}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT w.date,
        SUM(s.distance) as total_distance,
        SUM(s.time_seconds) as total_time,
        COUNT(s.id) as sets_count
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ee.exercise_id = ? AND s.is_warmup = 0
        AND s.distance IS NOT NULL AND s.distance > 0
        AND s.time_seconds IS NOT NULL AND s.time_seconds > 0
      GROUP BY w.id
      ORDER BY w.date ASC
      LIMIT ?
    ''', [exerciseId, limit]);
  }

  /// Cardio personal records: best distance, best pace, longest duration per exercise.
  Future<List<Map<String, dynamic>>> getCardioPRs({int limit = 20}) async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT e.id as exercise_id, e.name as exercise_name,
        ec.name as modality, ec.color as modality_color,
        MAX(s.distance) as best_distance,
        MAX(s.time_seconds) as best_time,
        MIN(CAST(s.time_seconds AS REAL) / NULLIF(s.distance, 0)) as best_pace
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE ec.energy_system = 'aerobic'
        AND s.distance IS NOT NULL AND s.distance > 0
      GROUP BY e.id
      HAVING best_distance > 0
      ORDER BY best_distance DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Overall cardio stats for a given month.
  Future<Map<String, dynamic>> getMonthlyCardioStats(int year, int month) async {
    final db = await this.db;
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';
    final row = await db.rawQuery('''
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
      WHERE ec.energy_system = 'aerobic' AND s.is_warmup = 0
        AND w.date LIKE ? AND s.distance IS NOT NULL AND s.distance > 0
    ''', ['$monthStr%']);

    if (row.isEmpty) {
      return {'total_distance': 0.0, 'total_time': 0, 'cardio_sessions': 0, 'cardio_sets': 0};
    }
    return {
      'total_distance': (row.first['total_distance'] as num?)?.toDouble() ?? 0,
      'total_time': (row.first['total_time'] as int?) ?? 0,
      'cardio_sessions': (row.first['cardio_sessions'] as int?) ?? 0,
      'cardio_sets': (row.first['cardio_sets'] as int?) ?? 0,
    };
  }
}
