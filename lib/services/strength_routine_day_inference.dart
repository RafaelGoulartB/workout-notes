import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';

/// Links older finished workouts to the routine day they most likely
/// trained, so history and the strength hub can name them ("Push", "Pull")
/// instead of "Treino livre".
///
/// Workouts logged before schema v54 have no `routine_day_id` (and often no
/// `routine_id`). A workout is matched to the routine day whose exercise set
/// overlaps it best (Jaccard ≥ [minOverlap]). Only `routine_day_id` is
/// written — never `routine_id` — so periodization counts are unaffected.
/// Runs once (flag in `app_settings`); later workouts store the day directly.
class StrengthRoutineDayInference {
  static const flagKey = 'strength_routine_day_inferred_v1';
  static const double minOverlap = 0.5;

  /// Best matching day id for a workout's exercises, or null. Pure; tested.
  static String? bestDay(
    Set<String> workoutExercises,
    Map<String, Set<String>> dayExercises,
  ) {
    if (workoutExercises.isEmpty) return null;
    String? best;
    var bestScore = 0.0;
    dayExercises.forEach((dayId, exercises) {
      if (exercises.isEmpty) return;
      final shared = exercises.intersection(workoutExercises).length;
      final union = exercises.union(workoutExercises).length;
      final score = shared / union;
      if (score > bestScore) {
        bestScore = score;
        best = dayId;
      }
    });
    return bestScore >= minOverlap ? best : null;
  }

  /// Returns how many workouts were linked (0 once done).
  static Future<int> runOnce({Database? database}) async {
    final db = database ?? await DatabaseHelper.instance.database;
    final done = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [flagKey],
      limit: 1,
    );
    if (done.isNotEmpty) return 0;

    final dayRows = await db.rawQuery(
      'SELECT routine_day_id, exercise_id FROM routine_exercises',
    );
    final days = <String, Set<String>>{};
    for (final r in dayRows) {
      final day = r['routine_day_id'] as String?;
      final exercise = r['exercise_id'] as String?;
      if (day == null || exercise == null) continue;
      days.putIfAbsent(day, () => {}).add(exercise);
    }

    var linked = 0;
    if (days.isNotEmpty) {
      final entryRows = await db.rawQuery('''
        SELECT w.id AS workout_id, ee.exercise_id AS exercise_id
        FROM workouts w
        JOIN exercise_entries ee ON ee.workout_id = w.id
        WHERE w.end_time IS NOT NULL AND w.routine_day_id IS NULL
      ''');
      final workouts = <String, Set<String>>{};
      for (final r in entryRows) {
        workouts
            .putIfAbsent(r['workout_id'] as String, () => {})
            .add(r['exercise_id'] as String);
      }
      final batch = db.batch();
      workouts.forEach((workoutId, exercises) {
        final day = bestDay(exercises, days);
        if (day == null) return;
        batch.update(
          'workouts',
          {'routine_day_id': day},
          where: 'id = ? AND routine_day_id IS NULL',
          whereArgs: [workoutId],
        );
        linked++;
      });
      await batch.commit(noResult: true);
    }
    await db.insert('app_settings', {
      'key': flagKey,
      'value': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return linked;
  }
}
