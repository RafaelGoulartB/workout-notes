import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Two routines (PPL with Push/Pull days, an empty Full body), three
/// exercises (chest, back, cardio) and their preset sets.
Future<void> seedStrengthRoutines(Database db) async {
  await db.insert('exercise_categories', {
    'id': 'chest',
    'name': 'Peito',
    'color': 0xFFE53935,
    'order_index': 0,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercise_categories', {
    'id': 'back',
    'name': 'Costas',
    'color': 0xFF1E88E5,
    'order_index': 1,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercise_categories', {
    'id': 'cardio',
    'name': 'Cardio',
    'color': 0xFF43A047,
    'order_index': 2,
    'energy_system': 'aerobic',
  });
  for (final (id, cat, type) in [
    ('bench', 'chest', 'weightReps'),
    ('row', 'back', 'weightReps'),
    ('run', 'cardio', 'distanceTime'),
  ]) {
    await db.insert('exercises', {
      'id': id,
      'name': id,
      'category_id': cat,
      'type': type,
      'created_at': '2026-01-01',
    });
  }
  await db.insert('routines', {
    'id': 'r1',
    'name': 'PPL',
    'notes': 'desc',
    'created_at': '2026-09-01T10:00:00',
  });
  await db.insert('routines', {
    'id': 'r2',
    'name': 'Full body',
    'created_at': '2026-08-01T10:00:00',
  });
  await db.insert('routine_days', {
    'id': 'd1',
    'routine_id': 'r1',
    'name': 'Push',
    'order_index': 0,
  });
  await db.insert('routine_days', {
    'id': 'd2',
    'routine_id': 'r1',
    'name': 'Pull',
    'order_index': 1,
  });
  await db.insert('routine_exercises', {
    'id': 're1',
    'routine_day_id': 'd1',
    'exercise_id': 'bench',
    'order_index': 0,
    'rest_time_seconds': 60,
  });
  await db.insert('routine_exercises', {
    'id': 're2',
    'routine_day_id': 'd2',
    'exercise_id': 'row',
    'order_index': 0,
  });
  await db.insert('routine_exercises', {
    'id': 're3',
    'routine_day_id': 'd2',
    'exercise_id': 'run',
    'order_index': 1,
  });
  // Bench: 1 warm-up + 3 working sets (80 kg x 10).
  await db.insert('predefined_sets', {
    'id': 'ps0',
    'routine_exercise_id': 're1',
    'weight': 40.0,
    'reps': 10,
    'is_warmup': 1,
    'order_index': 0,
  });
  for (var i = 1; i <= 3; i++) {
    await db.insert('predefined_sets', {
      'id': 'ps$i',
      'routine_exercise_id': 're1',
      'weight': 80.0,
      'reps': 10,
      'is_warmup': 0,
      'order_index': i,
    });
  }
  // Row: 2 working sets, cardio: 1 set that must not count as muscle sets.
  for (var i = 0; i < 2; i++) {
    await db.insert('predefined_sets', {
      'id': 'pr$i',
      'routine_exercise_id': 're2',
      'weight': 60.0,
      'reps': 8,
      'is_warmup': 0,
      'order_index': i,
    });
  }
  await db.insert('predefined_sets', {
    'id': 'pc0',
    'routine_exercise_id': 're3',
    'time_seconds': 600,
    'is_warmup': 0,
    'order_index': 0,
  });
}

Future<void> seedRoutineWorkout(
  Database db,
  String id,
  String date, {
  String? routineId,
  String? dayId,
  bool finished = true,
}) => db.insert('workouts', {
  'id': id,
  'date': date,
  'start_time': '${date}T10:00:00',
  'end_time': finished ? '${date}T11:00:00' : null,
  'is_from_routine': routineId == null ? 0 : 1,
  'routine_id': routineId,
  'routine_day_id': dayId,
  'created_at': '${date}T10:00:00',
});
