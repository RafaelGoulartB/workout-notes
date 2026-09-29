import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One set to seed: `(exerciseId, weight, reps, complete, warmup)`.
typedef SeedSet = ({
  String exercise,
  double weight,
  int reps,
  bool complete,
  bool warmup,
});

SeedSet seedSet(
  String exercise,
  double weight,
  int reps, {
  bool complete = true,
  bool warmup = false,
}) => (
  exercise: exercise,
  weight: weight,
  reps: reps,
  complete: complete,
  warmup: warmup,
);

/// Categories chest (anaerobic), legs (anaerobic) and cardio (aerobic) and
/// one exercise for each: `bench`, `squat`, `treadmill`.
Future<void> seedStrengthCatalog(Database db) async {
  await db.insert('exercise_categories', {
    'id': 'chest',
    'name': 'Chest',
    'color': 0xFFE53935,
    'order_index': 0,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercise_categories', {
    'id': 'legs',
    'name': 'Legs',
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
  for (final row in const [
    ('bench', 'Bench press', 'chest'),
    ('squat', 'Squat', 'legs'),
    ('treadmill', 'Treadmill', 'cardio'),
  ]) {
    await db.insert('exercises', {
      'id': row.$1,
      'name': row.$2,
      'category_id': row.$3,
      'created_at': '2026-01-01T00:00:00.000',
    });
  }
}

Future<void> seedRoutine(
  Database db, {
  required String id,
  required String name,
  required List<({String id, String name})> days,
  String createdAt = '2026-01-01T00:00:00.000',
}) async {
  await db.insert('routines', {
    'id': id,
    'name': name,
    'created_at': createdAt,
  });
  for (var i = 0; i < days.length; i++) {
    await db.insert('routine_days', {
      'id': days[i].id,
      'routine_id': id,
      'name': days[i].name,
      'order_index': i,
    });
  }
}

/// A routine exercise with [sets] predefined sets of 10 reps.
Future<void> seedRoutineExercise(
  Database db, {
  required String id,
  required String dayId,
  required String exerciseId,
  int order = 0,
  int sets = 3,
}) async {
  await db.insert('routine_exercises', {
    'id': id,
    'routine_day_id': dayId,
    'exercise_id': exerciseId,
    'order_index': order,
    'rest_time_seconds': 60,
  });
  for (var i = 0; i < sets; i++) {
    await db.insert('predefined_sets', {
      'id': '$id-set$i',
      'routine_exercise_id': id,
      'weight': 50.0,
      'reps': 10,
      'is_warmup': 0,
      'order_index': i,
    });
  }
}

Future<void> seedWorkout(
  Database db, {
  required String id,
  required String date,
  bool finished = true,
  int durationSeconds = 3600,
  int? feeling,
  String? routineId,
  String? routineDayId,
  List<SeedSet> sets = const [],
}) async {
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': '${date}T18:00:00.000',
    'end_time': finished ? '${date}T19:00:00.000' : null,
    'duration_seconds': finished ? durationSeconds : null,
    'feeling_rating': feeling,
    'routine_id': routineId,
    'routine_day_id': routineDayId,
    'is_from_routine': routineId == null ? 0 : 1,
    'created_at': '${date}T18:00:00.000',
  });
  final entryByExercise = <String, String>{};
  var order = 0;
  for (final set in sets) {
    var entry = entryByExercise[set.exercise];
    if (entry == null) {
      entry = '$id-${set.exercise}';
      entryByExercise[set.exercise] = entry;
      await db.insert('exercise_entries', {
        'id': entry,
        'workout_id': id,
        'exercise_id': set.exercise,
        'order_index': entryByExercise.length,
      });
    }
    await db.insert('sets', {
      'id': '$id-s${order++}',
      'exercise_entry_id': entry,
      'weight': set.weight,
      'reps': set.reps,
      'is_complete': set.complete ? 1 : 0,
      'is_warmup': set.warmup ? 1 : 0,
      'order_index': order,
    });
  }
}
