import 'test_data_context.dart';

class FitnessGenerationResult {
  final int workouts;
  final int routines;
  final int measurements;
  final int goals;

  const FitnessGenerationResult({
    required this.workouts,
    required this.routines,
    required this.measurements,
    required this.goals,
  });
}

/// Generates workouts, cardio, routines, goals and body measurements.
class TestDataFitnessGenerator {
  final TestDataContext context;

  TestDataFitnessGenerator(this.context);

  Future<FitnessGenerationResult> generate() async {
    final exercises = await context.database.query('exercises');
    final workouts = exercises.isEmpty ? 0 : await _workouts(exercises);
    final routines = exercises.isEmpty ? 0 : await _routines(exercises);
    return FitnessGenerationResult(
      workouts: workouts,
      routines: routines,
      measurements: await _measurements(),
      goals: await _goals(),
    );
  }

  Future<int> _workouts(List<Map<String, Object?>> exercises) async {
    final byCategory = <String, List<Map<String, Object?>>>{};
    for (final exercise in exercises) {
      byCategory
          .putIfAbsent(exercise['category_id']! as String, () => [])
          .add(exercise);
    }

    var count = 0;
    final totalDays = context.now.difference(context.start).inDays;
    for (var day = 0; day <= totalDays; day++) {
      final date = context.start.add(Duration(days: day));
      final week = day ~/ 7;
      final isDeload = week > 0 && week % 6 == 5;
      final planned = switch (date.weekday) {
        DateTime.monday => ('push', const ['chest', 'shoulders', 'triceps']),
        DateTime.wednesday => ('pull', const ['back', 'biceps']),
        DateTime.friday => ('legs', const ['legs', 'core']),
        DateTime.saturday => ('cardio', const ['cardio']),
        _ => null,
      };
      if (planned == null || context.random.nextDouble() < 0.12) continue;

      final pool = <Map<String, Object?>>[
        for (final category in planned.$2) ...?byCategory[category],
      ]..shuffle(context.random);
      if (pool.isEmpty) continue;
      final exerciseCount = planned.$1 == 'cardio'
          ? 1
          : (isDeload ? 3 : 4 + context.random.nextInt(2));
      final selected = pool.take(exerciseCount).toList();
      final hour = context.random.nextBool()
          ? 6
          : 17 + context.random.nextInt(4);
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        context.random.nextInt(4) * 15,
      );
      final duration = planned.$1 == 'cardio'
          ? 25 + context.random.nextInt(31)
          : 42 + context.random.nextInt(35);
      final workoutId = context.id('workout', '$day:${planned.$1}');
      await context.database.insert('workouts', {
        'id': workoutId,
        'date': context.date(date),
        'start_time': start.toIso8601String(),
        'end_time': start.add(Duration(minutes: duration)).toIso8601String(),
        'duration_seconds': duration * 60,
        'estimated_calories': (duration * (planned.$1 == 'cardio' ? 8.2 : 6.1))
            .roundToDouble(),
        'comment': _workoutComment(planned.$1, isDeload),
        'feeling_rating': (context.jitter(
          isDeload ? 3.5 : 4.1,
          1.0,
        )).round().clamp(1, 5),
        'is_from_routine': week > 1 ? 1 : 0,
        'created_at': start.toIso8601String(),
      });

      for (var index = 0; index < selected.length; index++) {
        final exercise = selected[index];
        final entryId = context.id('entry', '$day:${planned.$1}:$index');
        await context.database.insert('exercise_entries', {
          'id': entryId,
          'workout_id': workoutId,
          'exercise_id': exercise['id'],
          'order_index': index,
          'notes': context.random.nextDouble() < 0.1
              ? 'Técnica controlada'
              : null,
          'rest_time_seconds': exercise['default_rest_time'] ?? 90,
        });
        await _sets(
          entryId: entryId,
          exercise: exercise,
          day: day,
          deload: isDeload,
        );
      }
      count++;
    }
    return count;
  }

  Future<void> _sets({
    required String entryId,
    required Map<String, Object?> exercise,
    required int day,
    required bool deload,
  }) async {
    final type = exercise['type'] as String? ?? 'weightReps';
    final numberOfSets = type == 'distanceTime'
        ? 1
        : (deload ? 3 : 3 + context.random.nextInt(2));
    for (var set = 0; set < numberOfSets; set++) {
      final warmup =
          type == 'weightReps' &&
          set == 0 &&
          context.random.nextDouble() < 0.55;
      double? weight;
      int? reps;
      double? distance;
      int? seconds;
      if (type == 'weightReps') {
        final category = exercise['category_id'] as String;
        final base = switch (category) {
          'legs' => 62.5,
          'back' || 'chest' => 45.0,
          'shoulders' => 25.0,
          'biceps' || 'triceps' => 15.0,
          _ => 10.0,
        };
        final progress = day / 28 * (category == 'legs' ? 2.0 : 1.0);
        weight =
            ((base + progress + context.jitter(0, 2.5)) / 2.5).round() * 2.5;
        if (warmup) weight *= 0.65;
        if (exercise['equipment'] == 'Bodyweight') weight = 0;
        reps = warmup
            ? 12 + context.random.nextInt(4)
            : 6 + context.random.nextInt(7);
      } else if (type == 'distanceTime') {
        distance = double.parse(
          context
              .jitter(5.2 + day / 180, 1.7)
              .clamp(1.5, 15)
              .toStringAsFixed(2),
        );
        seconds = (distance * context.jitter(360, 35)).round();
      } else {
        seconds = (45 + context.random.nextInt(9) * 15);
      }
      await context.database.insert('sets', {
        'id': context.id('set', '$entryId:$set'),
        'exercise_entry_id': entryId,
        'weight': weight,
        'reps': reps,
        'distance': distance,
        'time_seconds': seconds,
        'is_complete': context.random.nextDouble() < 0.97 ? 1 : 0,
        'is_warmup': warmup ? 1 : 0,
        'rpe': warmup
            ? 5.5
            : double.parse(
                context
                    .jitter(deload ? 6.5 : 8.0, 1.1)
                    .clamp(5, 10)
                    .toStringAsFixed(1),
              ),
        'comment': context.random.nextDouble() < 0.04
            ? 'Última repetição difícil'
            : null,
        'order_index': set,
      });
    }
  }

  Future<int> _routines(List<Map<String, Object?>> exercises) async {
    final available = {
      for (final exercise in exercises) exercise['id'] as String: exercise,
    };
    final definitions = <(String, List<(String, List<String>)>)>[
      (
        'Força 3x na semana',
        [
          ('Treino A', ['squat', 'bench_press', 'bent_row', 'plank']),
          ('Treino B', ['deadlift', 'ohp', 'lat_pulldown', 'leg_raise']),
        ],
      ),
      (
        'Corrida e condicionamento',
        [
          ('Corrida leve', ['running']),
          ('Intervalado', ['treadmill', 'jump_rope']),
        ],
      ),
    ];
    var created = 0;
    for (
      var routineIndex = 0;
      routineIndex < definitions.length;
      routineIndex++
    ) {
      final definition = definitions[routineIndex];
      final routineId = context.id('routine', routineIndex);
      await context.database.insert('routines', {
        'id': routineId,
        'name': definition.$1,
        'notes':
            'Cenário de desenvolvimento — valores ajustados a cada geração',
        'created_at': context.now
            .subtract(Duration(days: 20 + routineIndex * 9))
            .toIso8601String(),
      });
      for (var dayIndex = 0; dayIndex < definition.$2.length; dayIndex++) {
        final dayDefinition = definition.$2[dayIndex];
        final dayId = context.id('routine_day', '$routineIndex:$dayIndex');
        await context.database.insert('routine_days', {
          'id': dayId,
          'routine_id': routineId,
          'name': dayDefinition.$1,
          'notes': dayIndex == 0 ? 'Priorizar execução e amplitude' : null,
          'order_index': dayIndex,
        });
        var order = 0;
        for (final exerciseId in dayDefinition.$2) {
          final exercise = available[exerciseId];
          if (exercise == null) continue;
          final routineExerciseId = context.id(
            'routine_exercise',
            '$routineIndex:$dayIndex:$order',
          );
          await context.database.insert('routine_exercises', {
            'id': routineExerciseId,
            'routine_day_id': dayId,
            'exercise_id': exerciseId,
            'order_index': order,
            'rest_time_seconds': exercise['default_rest_time'] ?? 90,
          });
          final type = exercise['type'] as String;
          final setCount = type == 'distanceTime' ? 1 : 3;
          for (var set = 0; set < setCount; set++) {
            await context.database.insert('predefined_sets', {
              'id': context.id(
                'predefined_set',
                '$routineIndex:$dayIndex:$order:$set',
              ),
              'routine_exercise_id': routineExerciseId,
              'weight': type == 'weightReps'
                  ? ((context.jitter(40, 12) / 2.5).round() * 2.5).clamp(0, 100)
                  : null,
              'reps': type == 'weightReps'
                  ? 8 + context.random.nextInt(5)
                  : null,
              'distance': type == 'distanceTime'
                  ? context.jitter(5, 0.8)
                  : null,
              'time_seconds': type == 'distanceTime'
                  ? 30 * 60
                  : type == 'timeOnly'
                  ? 60
                  : null,
              'is_warmup': 0,
              'order_index': set,
            });
          }
          order++;
        }
      }
      created++;
    }
    return created;
  }

  Future<int> _measurements() async {
    final definitions = <(String, double, double, String, int)>[
      ('weight', 81.8, 77.6, 'kg', 7),
      ('bodyFat', 19.2, 15.8, '%', 14),
      ('waist', 89.0, 83.0, 'cm', 10),
      ('chest', 99.5, 103.0, 'cm', 14),
      ('arm', 34.0, 35.5, 'cm', 14),
      ('thigh', 55.0, 57.0, 'cm', 14),
    ];
    final days = context.now.difference(context.start).inDays;
    var count = 0;
    for (final definition in definitions) {
      for (
        var day = context.random.nextInt(definition.$5);
        day <= days;
        day += definition.$5 + context.random.nextInt(3) - 1
      ) {
        final date = context.start.add(Duration(days: day));
        final factor = days == 0 ? 1.0 : day / days;
        final value =
            definition.$2 +
            (definition.$3 - definition.$2) * factor +
            context.jitter(0, definition.$1 == 'weight' ? 0.45 : 0.25);
        final sides = definition.$1 == 'arm' || definition.$1 == 'thigh'
            ? const ['left', 'right']
            : const <String?>[null];
        for (final side in sides) {
          await context.database.insert('body_measurements', {
            'id': context.id(
              'measurement',
              '${definition.$1}:$day:${side ?? 'center'}',
            ),
            'type': definition.$1,
            'value': double.parse(
              (value + (side == 'right' ? 0.2 : 0)).toStringAsFixed(1),
            ),
            'unit': definition.$4,
            'date': context.date(date),
            'comment':
                definition.$1 == 'weight' && context.random.nextDouble() < 0.2
                ? 'Em jejum'
                : null,
            'time_of_day': 'morning',
            'is_fasted': definition.$1 == 'weight' ? 1 : 0,
            'side': side,
            'created_at': date.add(const Duration(hours: 7)).toIso8601String(),
          });
          count++;
        }
      }
    }
    return count;
  }

  Future<int> _goals() async {
    final goals = [
      ('Treinar 3 vezes', 'anaerobic', 'days', 'weekly', 3.0, 0xFF3949AB),
      ('Correr 20 km', 'aerobic', 'distance', 'weekly', 20.0, 0xFFE53935),
      ('Volume mensal', 'anaerobic', 'volume', 'monthly', 42000.0, 0xFF43A047),
    ];
    for (var index = 0; index < goals.length; index++) {
      final goal = goals[index];
      await context.database.insert('user_goals', {
        'id': context.id('goal', index),
        'title': goal.$1,
        'scope': goal.$2,
        'metric': goal.$3,
        'period': goal.$4,
        'target_value': goal.$5,
        'created_at': context.start.toIso8601String(),
        'is_active': 1,
        'color': goal.$6,
      });
    }
    return goals.length;
  }

  String? _workoutComment(String split, bool deload) {
    if (deload) return 'Semana de recuperação, volume reduzido';
    if (context.random.nextDouble() > 0.28) return null;
    return switch (split) {
      'cardio' => 'Ritmo confortável, respiração controlada',
      'legs' => 'Boa evolução no agachamento',
      _ => 'Treino consistente, técnica em primeiro lugar',
    };
  }
}
