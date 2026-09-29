import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/repositories/workout_sql.dart';

/// Repository for exercise history, body-weight vs volume and the workout
/// overview totals.
class AnalyticsRepository extends BaseRepository {
  /// A working set that really happened: completed, not a warm-up. Every
  /// statistic below joins `workouts w` and also requires [_finished], so
  /// planned or abandoned sessions never leak into the numbers. Goals use the
  /// same rule through [WorkoutSql].
  static const _workSet = WorkoutSql.workSet;
  static const _finished = WorkoutSql.finished;

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
}
