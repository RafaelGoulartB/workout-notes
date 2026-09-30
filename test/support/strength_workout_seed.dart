import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Inserts a workout with its exercises and sets into the test database.
/// Each exercise is `(exerciseId, [(weight, reps, warmup:, done:)])`.
Future<void> seedWorkout(
  Database db,
  String id, {
  required String date,
  String? routineId,
  String? dayId,
  String? comment,
  bool finished = true,
  int feeling = 4,
  List<(String exerciseId, List<(double, int, {bool warmup, bool done})> sets)>
      exercises =
      const [],
}) async {
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': '${date}T18:00:00.000',
    'end_time': finished ? '${date}T19:00:00.000' : null,
    'duration_seconds': finished ? 3600 : null,
    'comment': comment,
    'feeling_rating': feeling,
    'routine_id': routineId,
    'routine_day_id': dayId,
    'created_at': '${date}T18:00:00.000',
  });
  var entry = 0;
  for (final (exerciseId, sets) in exercises) {
    final entryId = '$id-e$entry';
    await db.insert('exercise_entries', {
      'id': entryId,
      'workout_id': id,
      'exercise_id': exerciseId,
      'order_index': entry++,
    });
    var order = 0;
    for (final s in sets) {
      await db.insert('sets', {
        'id': '$entryId-s$order',
        'exercise_entry_id': entryId,
        'weight': s.$1,
        'reps': s.$2,
        'is_complete': s.done ? 1 : 0,
        'is_warmup': s.warmup ? 1 : 0,
        'order_index': order++,
      });
    }
  }
}

(double, int, {bool warmup, bool done}) seedSet(
  double w,
  int r, {
  bool warmup = false,
  bool done = true,
}) => (w, r, warmup: warmup, done: done);

/// Chest/back/cardio categories, three exercises and a routine with two days,
/// the fixtures the strength history tests share.
Future<void> seedStrengthBasics(Database db) async {
  for (final (id, name, color, order, energy) in [
    ('chest', 'Chest', 0xFFE53935, 0, 'anaerobic'),
    ('back', 'Back', 0xFF1E88E5, 1, 'anaerobic'),
    ('cardio', 'Cardio', 0xFF43A047, 2, 'aerobic'),
  ]) {
    await db.insert('exercise_categories', {
      'id': id,
      'name': name,
      'color': color,
      'order_index': order,
      'energy_system': energy,
    });
  }
  for (final (id, name, cat) in [
    ('bench', 'Bench Press', 'chest'),
    ('row', 'Barbell Row', 'back'),
    ('treadmill', 'Treadmill', 'cardio'),
  ]) {
    await db.insert('exercises', {
      'id': id,
      'name': name,
      'category_id': cat,
      'type': 'weightReps',
      'created_at': '2026-01-01',
    });
  }
  await db.insert('routines', {
    'id': 'ppl',
    'name': 'Push Pull Legs',
    'created_at': '2026-01-01',
  });
  await db.insert('routine_days', {
    'id': 'push',
    'routine_id': 'ppl',
    'name': 'Push A',
    'order_index': 0,
  });
  await db.insert('routine_days', {
    'id': 'pull',
    'routine_id': 'ppl',
    'name': 'Pull A',
    'order_index': 1,
  });
}
