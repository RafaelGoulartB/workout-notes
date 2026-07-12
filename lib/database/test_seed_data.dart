import 'dart:math';
import 'package:uuid/uuid.dart';
import 'database_helper.dart';

/// Generates realistic fake workout data for testing purposes.
/// Uses a fixed seed (42) so results are reproducible.
class TestDataGenerator {
  final _db = DatabaseHelper.instance;
  final _uuid = const Uuid();
  final _rng = Random(42);

  /// Generate [months] of fake workout data.
  /// Returns a map with workout count and routine count.
  Future<Map<String, int>> generate({int months = 4}) async {
    final exercises = await _db.getExercises();
    if (exercises.isEmpty) return {'workouts': 0, 'routines': 0};

    // Separate exercises by category for realistic PPL-like splits
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final ex in exercises) {
      final catId = ex['category_id'] as String;
      byCategory.putIfAbsent(catId, () => []).add(ex);
    }

    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month - months, 1);
    int workoutsCreated = 0;
    DateTime currentDate = periodStart;

    // Build a progression map per exercise: {exerciseId: baseWeight}
    final progression = <String, double>{};
    for (final ex in exercises) {
      if (ex['type'] == 'weightReps') {
        progression[ex['id'] as String] = _baseWeight(ex['name'] as String);
      }
    }

    // Generate workouts at 2-4 day intervals
    while (currentDate.isBefore(now)) {
      final skipDays = _rng.nextInt(3) + 1; // 1-3 days gap
      currentDate = currentDate.add(Duration(days: skipDays));
      if (currentDate.isAfter(now)) break;

      final dateStr = currentDate.toIso8601String().substring(0, 10);
      final workoutId = _uuid.v4();
      final db = await _db.database;

      // Determine workout "split" based on day pattern
      final weekOfMonth = (currentDate.day / 7).floor();
      final dayMod = (currentDate.weekday + weekOfMonth) % 3;

      // Pick 3-5 exercises for this workout
      List<Map<String, dynamic>> selectedExercises;
      if (dayMod == 0) {
        // Push: chest, shoulders, triceps
        selectedExercises = _pickExercises(byCategory, [
          'chest',
          'shoulders',
          'triceps',
        ], 4);
      } else if (dayMod == 1) {
        // Pull: back, biceps
        selectedExercises = _pickExercises(byCategory, ['back', 'biceps'], 4);
      } else {
        // Legs + core + cardio
        selectedExercises = _pickExercises(byCategory, [
          'legs',
          'core',
          'cardio',
        ], 5);
      }

      // Add random extra from fullbody sometimes
      if (_rng.nextDouble() < 0.3 && byCategory.containsKey('fullbody')) {
        selectedExercises.add(
          byCategory['fullbody']![_rng.nextInt(byCategory['fullbody']!.length)],
        );
      }

      // Create the workout
      final startHour = 6 + _rng.nextInt(12);
      final startMinute = _rng.nextInt(60);
      final startTime = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
        startHour,
        startMinute,
      );
      final durationMinutes = 30 + _rng.nextInt(60);

      await db.rawInsert(
        'INSERT INTO workouts (id, date, start_time, end_time, duration_seconds, feeling_rating, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          workoutId,
          dateStr,
          startTime.toIso8601String(),
          startTime.add(Duration(minutes: durationMinutes)).toIso8601String(),
          durationMinutes * 60,
          3 + _rng.nextInt(3), // feeling 3-5
          startTime.toIso8601String(),
        ],
      );

      // Add exercise entries with sets
      for (int i = 0; i < selectedExercises.length; i++) {
        final ex = selectedExercises[i];
        final entryId = _uuid.v4();
        final exType = ex['type'] as String? ?? 'weightReps';

        await db.rawInsert(
          'INSERT INTO exercise_entries (id, workout_id, exercise_id, order_index, rest_time_seconds) '
          'VALUES (?, ?, ?, ?, ?)',
          [entryId, workoutId, ex['id'], i, 60 + _rng.nextInt(120)],
        );

        // Generate 3-4 sets
        final numSets = 3 + _rng.nextInt(2);
        for (int j = 0; j < numSets; j++) {
          final setId = _uuid.v4();
          double? weight;
          int? reps;
          double? distance;
          int? timeSeconds;
          final isWarmup = j == 0 && _rng.nextDouble() < 0.5;

          if (exType == 'weightReps') {
            double base = progression[ex['id'] as String] ?? 20;
            final monthsSinceStart =
                currentDate
                    .difference(DateTime(now.year, now.month - months, 1))
                    .inDays /
                30;
            final progress =
                monthsSinceStart * _progressRate(ex['name'] as String);
            final noise = (_rng.nextDouble() - 0.5) * 4;
            weight = (base + progress + noise).clamp(1, 500);
            weight = (weight / 2.5).round() * 2.5;
            reps = isWarmup ? 12 + _rng.nextInt(4) : 6 + _rng.nextInt(7);
          } else if (exType == 'distanceTime') {
            distance = (1 + _rng.nextDouble() * 9).clamp(0.5, 20);
            distance = (distance * 10).round() / 10;
            timeSeconds = (5 * 60 + _rng.nextInt(25 * 60)).roundToMultiple(30);
          } else if (exType == 'timeOnly') {
            timeSeconds = (30 + _rng.nextInt(150)).roundToMultiple(5);
          }

          await db.rawInsert(
            'INSERT INTO sets (id, exercise_entry_id, weight, reps, distance, time_seconds, '
            'is_complete, is_warmup, rpe, order_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              setId, entryId, weight, reps, distance, timeSeconds,
              1, // all sets complete
              isWarmup ? 1 : 0,
              (6 + _rng.nextDouble() * 4).roundToDouble(), // RPE 6-10
              j,
            ],
          );
        }
      }

      workoutsCreated++;
    }

    // Generate body measurements over the same period
    await _generateBodyMeasurements(periodStart, now);

    // Also generate sample routines for testing
    final routineCount = await generateRoutines();

    return {'workouts': workoutsCreated, 'routines': routineCount};
  }

  /// Generates sample routines (PPL, Upper/Lower, Full Body) for testing.
  Future<int> generateRoutines() async {
    final db = await _db.database;
    final exercises = await _db.getExercises();
    if (exercises.isEmpty) return 0;

    // Build exercise lookup by ID
    final exById = <String, Map<String, dynamic>>{};
    for (final ex in exercises) {
      exById[ex['id'] as String] = ex;
    }

    int routinesCreated = 0;

    // Helper constants for exercise/set definitions
    const kEx = 'exercise_id';
    const kRest = 'rest_time';
    const kSets = 'sets';
    const kW = 'weight';
    const kR = 'reps';

    // Helper to add a routine with days, exercises, and predefined sets
    Future<void> createRoutine(
      String name,
      List<Map<String, dynamic>> days,
    ) async {
      final routineId = _uuid.v4();
      await db.insert('routines', {
        'id': routineId,
        'name': name,
        'notes': 'Rotina de teste gerada automaticamente',
        'created_at': DateTime.now().toIso8601String(),
      });

      for (int d = 0; d < days.length; d++) {
        final day = days[d];
        final dayId = _uuid.v4();
        await db.insert('routine_days', {
          'id': dayId,
          'routine_id': routineId,
          'name': day['name'],
          'order_index': d,
        });

        final entries = day['exercises'] as List<Map<String, dynamic>>;
        for (int e = 0; e < entries.length; e++) {
          final entry = entries[e];
          final exId = entry['exercise_id'] as String;
          final ex = exById[exId];
          if (ex == null) continue;

          final reId = _uuid.v4();
          final defaultRest = ex['default_rest_time'] as int? ?? 90;
          await db.insert('routine_exercises', {
            'id': reId,
            'routine_day_id': dayId,
            'exercise_id': exId,
            'order_index': e,
            'rest_time_seconds': entry['rest_time'] as int? ?? defaultRest,
            'superset_group_id': null,
          });

          // Add predefined sets
          final sets = entry['sets'] as List<Map<String, dynamic>>;
          for (int s = 0; s < sets.length; s++) {
            final set = sets[s];
            await db.insert('predefined_sets', {
              'id': _uuid.v4(),
              'routine_exercise_id': reId,
              'weight': set['weight'],
              'reps': set['reps'],
              'distance': set['distance'],
              'time_seconds': set['time_seconds'],
              'is_warmup': set['is_warmup'] ?? 0,
              'order_index': s,
            });
          }
        }
      }

      routinesCreated++;
    }

    // ═══════════════════════════════════════════════════════════
    // 1. PUSH PULL LEGS (6 days)
    // ═══════════════════════════════════════════════════════════

    await createRoutine('PPL - Push Pull Legs', [
      {
        'name': 'Push A - Peito',
        'exercises': [
          {
            kEx: 'bench_press',
            kRest: 120,
            kSets: [
              {kW: 60, kR: 10},
              {kW: 70, kR: 8},
              {kW: 75, kR: 6},
              {kW: 60, kR: 12},
            ],
          },
          {
            kEx: 'incl_bench',
            kRest: 90,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 55, kR: 8},
              {kW: 60, kR: 8},
            ],
          },
          {
            kEx: 'ohp',
            kRest: 120,
            kSets: [
              {kW: 30, kR: 10},
              {kW: 35, kR: 8},
              {kW: 40, kR: 6},
            ],
          },
          {
            kEx: 'lat_raise',
            kRest: 60,
            kSets: [
              {kW: 10, kR: 15},
              {kW: 12, kR: 12},
              {kW: 12, kR: 12},
            ],
          },
          {
            kEx: 'triceps_pushdown',
            kRest: 60,
            kSets: [
              {kW: 20, kR: 12},
              {kW: 25, kR: 10},
              {kW: 25, kR: 10},
            ],
          },
          {
            kEx: 'cable_fly',
            kRest: 60,
            kSets: [
              {kW: 15, kR: 15},
              {kW: 20, kR: 12},
              {kW: 20, kR: 12},
            ],
          },
        ],
      },
      {
        'name': 'Pull A - Costas',
        'exercises': [
          {
            kEx: 'deadlift',
            kRest: 180,
            kSets: [
              {kW: 80, kR: 8},
              {kW: 100, kR: 6},
              {kW: 110, kR: 4},
              {kW: 80, kR: 10},
            ],
          },
          {
            kEx: 'pullup',
            kRest: 90,
            kSets: [
              {kW: 0, kR: 10},
              {kW: 0, kR: 8},
              {kW: 0, kR: 8},
            ],
          },
          {
            kEx: 'bent_row',
            kRest: 90,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 65, kR: 6},
            ],
          },
          {
            kEx: 'face_pull',
            kRest: 60,
            kSets: [
              {kW: 15, kR: 15},
              {kW: 17.5, kR: 12},
              {kW: 17.5, kR: 12},
            ],
          },
          {
            kEx: 'bb_curl',
            kRest: 60,
            kSets: [
              {kW: 25, kR: 12},
              {kW: 30, kR: 10},
              {kW: 30, kR: 10},
            ],
          },
          {
            kEx: 'hammer_curl',
            kRest: 60,
            kSets: [
              {kW: 12, kR: 12},
              {kW: 14, kR: 10},
              {kW: 14, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Legs A - Quadríceps',
        'exercises': [
          {
            kEx: 'squat',
            kRest: 180,
            kSets: [
              {kW: 60, kR: 10},
              {kW: 80, kR: 8},
              {kW: 90, kR: 6},
              {kW: 100, kR: 4},
            ],
          },
          {
            kEx: 'leg_press',
            kRest: 120,
            kSets: [
              {kW: 140, kR: 12},
              {kW: 180, kR: 10},
              {kW: 200, kR: 8},
            ],
          },
          {
            kEx: 'leg_ext',
            kRest: 90,
            kSets: [
              {kW: 40, kR: 12},
              {kW: 50, kR: 10},
              {kW: 55, kR: 10},
            ],
          },
          {
            kEx: 'leg_curl',
            kRest: 90,
            kSets: [
              {kW: 35, kR: 12},
              {kW: 40, kR: 10},
              {kW: 45, kR: 10},
            ],
          },
          {
            kEx: 'calf_raise',
            kRest: 60,
            kSets: [
              {kW: 60, kR: 15},
              {kW: 70, kR: 12},
              {kW: 80, kR: 12},
            ],
          },
        ],
      },
      {
        'name': 'Push B - Ombros',
        'exercises': [
          {
            kEx: 'db_ohp',
            kRest: 90,
            kSets: [
              {kW: 20, kR: 10},
              {kW: 24, kR: 8},
              {kW: 26, kR: 6},
            ],
          },
          {
            kEx: 'db_bench',
            kRest: 90,
            kSets: [
              {kW: 28, kR: 10},
              {kW: 32, kR: 8},
              {kW: 36, kR: 6},
            ],
          },
          {
            kEx: 'chest_dip',
            kRest: 90,
            kSets: [
              {kW: 0, kR: 12},
              {kW: 0, kR: 10},
              {kW: 0, kR: 8},
            ],
          },
          {
            kEx: 'lat_raise',
            kRest: 60,
            kSets: [
              {kW: 10, kR: 15},
              {kW: 12, kR: 12},
              {kW: 12, kR: 12},
            ],
          },
          {
            kEx: 'skull_crusher',
            kRest: 60,
            kSets: [
              {kW: 20, kR: 12},
              {kW: 25, kR: 10},
              {kW: 25, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Pull B - Dorsal',
        'exercises': [
          {
            kEx: 'chinup',
            kRest: 90,
            kSets: [
              {kW: 0, kR: 10},
              {kW: 0, kR: 8},
              {kW: 0, kR: 6},
            ],
          },
          {
            kEx: 'lat_pulldown',
            kRest: 90,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 65, kR: 6},
            ],
          },
          {
            kEx: 'seated_row',
            kRest: 90,
            kSets: [
              {kW: 40, kR: 12},
              {kW: 50, kR: 10},
              {kW: 55, kR: 8},
            ],
          },
          {
            kEx: 'rear_delt_fly',
            kRest: 60,
            kSets: [
              {kW: 12, kR: 15},
              {kW: 15, kR: 12},
              {kW: 15, kR: 12},
            ],
          },
          {
            kEx: 'cable_curl',
            kRest: 60,
            kSets: [
              {kW: 15, kR: 12},
              {kW: 20, kR: 10},
              {kW: 20, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Legs B - Posterior',
        'exercises': [
          {
            kEx: 'romanian_dl',
            kRest: 120,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 70, kR: 6},
            ],
          },
          {
            kEx: 'front_squat',
            kRest: 150,
            kSets: [
              {kW: 40, kR: 8},
              {kW: 50, kR: 6},
              {kW: 55, kR: 4},
            ],
          },
          {
            kEx: 'bulgarian_split',
            kRest: 90,
            kSets: [
              {kW: 20, kR: 10},
              {kW: 24, kR: 8},
              {kW: 24, kR: 8},
            ],
          },
          {
            kEx: 'hip_thrust',
            kRest: 90,
            kSets: [
              {kW: 60, kR: 12},
              {kW: 70, kR: 10},
              {kW: 80, kR: 8},
            ],
          },
          {
            kEx: 'calf_raise',
            kRest: 60,
            kSets: [
              {kW: 60, kR: 15},
              {kW: 70, kR: 12},
              {kW: 80, kR: 12},
            ],
          },
        ],
      },
    ]);

    // ═══════════════════════════════════════════════════════════
    // 2. UPPER / LOWER (4 days)
    // ═══════════════════════════════════════════════════════════

    await createRoutine('Upper / Lower', [
      {
        'name': 'Upper A - Força',
        'exercises': [
          {
            kEx: 'bench_press',
            kRest: 120,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 70, kR: 6},
              {kW: 75, kR: 4},
            ],
          },
          {
            kEx: 'bent_row',
            kRest: 120,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 65, kR: 6},
            ],
          },
          {
            kEx: 'ohp',
            kRest: 90,
            kSets: [
              {kW: 30, kR: 8},
              {kW: 35, kR: 6},
              {kW: 40, kR: 4},
            ],
          },
          {
            kEx: 'pullup',
            kRest: 90,
            kSets: [
              {kW: 0, kR: 10},
              {kW: 0, kR: 8},
              {kW: 0, kR: 6},
            ],
          },
          {
            kEx: 'bb_curl',
            kRest: 60,
            kSets: [
              {kW: 25, kR: 12},
              {kW: 30, kR: 10},
              {kW: 30, kR: 10},
            ],
          },
          {
            kEx: 'triceps_pushdown',
            kRest: 60,
            kSets: [
              {kW: 20, kR: 12},
              {kW: 25, kR: 10},
              {kW: 25, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Lower A - Quad Dominant',
        'exercises': [
          {
            kEx: 'squat',
            kRest: 180,
            kSets: [
              {kW: 60, kR: 10},
              {kW: 80, kR: 8},
              {kW: 90, kR: 6},
              {kW: 100, kR: 4},
            ],
          },
          {
            kEx: 'romanian_dl',
            kRest: 120,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 65, kR: 6},
            ],
          },
          {
            kEx: 'leg_ext',
            kRest: 90,
            kSets: [
              {kW: 40, kR: 12},
              {kW: 50, kR: 10},
              {kW: 55, kR: 10},
            ],
          },
          {
            kEx: 'leg_curl',
            kRest: 90,
            kSets: [
              {kW: 35, kR: 12},
              {kW: 40, kR: 10},
              {kW: 45, kR: 10},
            ],
          },
          {
            kEx: 'calf_raise',
            kRest: 60,
            kSets: [
              {kW: 60, kR: 15},
              {kW: 70, kR: 12},
              {kW: 80, kR: 12},
            ],
          },
        ],
      },
      {
        'name': 'Upper B - Hipertrofia',
        'exercises': [
          {
            kEx: 'db_incl',
            kRest: 90,
            kSets: [
              {kW: 26, kR: 10},
              {kW: 30, kR: 8},
              {kW: 32, kR: 8},
              {kW: 26, kR: 12},
            ],
          },
          {
            kEx: 'lat_pulldown',
            kRest: 90,
            kSets: [
              {kW: 50, kR: 12},
              {kW: 60, kR: 10},
              {kW: 65, kR: 8},
            ],
          },
          {
            kEx: 'db_ohp',
            kRest: 90,
            kSets: [
              {kW: 20, kR: 10},
              {kW: 24, kR: 8},
              {kW: 26, kR: 8},
            ],
          },
          {
            kEx: 'seated_row',
            kRest: 90,
            kSets: [
              {kW: 45, kR: 12},
              {kW: 55, kR: 10},
              {kW: 55, kR: 10},
            ],
          },
          {
            kEx: 'hammer_curl',
            kRest: 60,
            kSets: [
              {kW: 12, kR: 12},
              {kW: 14, kR: 10},
              {kW: 14, kR: 10},
            ],
          },
          {
            kEx: 'skull_crusher',
            kRest: 60,
            kSets: [
              {kW: 20, kR: 12},
              {kW: 25, kR: 10},
              {kW: 25, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Lower B - Posterior Focus',
        'exercises': [
          {
            kEx: 'deadlift',
            kRest: 180,
            kSets: [
              {kW: 80, kR: 8},
              {kW: 100, kR: 6},
              {kW: 110, kR: 4},
              {kW: 80, kR: 10},
            ],
          },
          {
            kEx: 'leg_press',
            kRest: 120,
            kSets: [
              {kW: 160, kR: 12},
              {kW: 200, kR: 10},
              {kW: 220, kR: 8},
            ],
          },
          {
            kEx: 'bulgarian_split',
            kRest: 90,
            kSets: [
              {kW: 20, kR: 10},
              {kW: 24, kR: 8},
              {kW: 24, kR: 8},
            ],
          },
          {
            kEx: 'hip_thrust',
            kRest: 90,
            kSets: [
              {kW: 60, kR: 12},
              {kW: 80, kR: 10},
              {kW: 90, kR: 8},
            ],
          },
          {
            kEx: 'leg_curl',
            kRest: 90,
            kSets: [
              {kW: 40, kR: 12},
              {kW: 45, kR: 10},
              {kW: 50, kR: 10},
            ],
          },
        ],
      },
    ]);

    // ═══════════════════════════════════════════════════════════
    // 3. FULL BODY (3 days)
    // ═══════════════════════════════════════════════════════════

    await createRoutine('Full Body', [
      {
        'name': 'Full A - Força',
        'exercises': [
          {
            kEx: 'squat',
            kRest: 180,
            kSets: [
              {kW: 60, kR: 10},
              {kW: 80, kR: 8},
              {kW: 90, kR: 6},
            ],
          },
          {
            kEx: 'bench_press',
            kRest: 120,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 70, kR: 6},
            ],
          },
          {
            kEx: 'bent_row',
            kRest: 120,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 65, kR: 6},
            ],
          },
          {
            kEx: 'ohp',
            kRest: 90,
            kSets: [
              {kW: 30, kR: 8},
              {kW: 35, kR: 6},
              {kW: 40, kR: 5},
            ],
          },
          {
            kEx: 'bb_curl',
            kRest: 60,
            kSets: [
              {kW: 25, kR: 12},
              {kW: 30, kR: 10},
            ],
          },
          {
            kEx: 'leg_curl',
            kRest: 90,
            kSets: [
              {kW: 35, kR: 12},
              {kW: 40, kR: 10},
              {kW: 45, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Full B - Resistência',
        'exercises': [
          {
            kEx: 'deadlift',
            kRest: 180,
            kSets: [
              {kW: 80, kR: 8},
              {kW: 100, kR: 6},
              {kW: 105, kR: 5},
            ],
          },
          {
            kEx: 'incl_bench',
            kRest: 90,
            kSets: [
              {kW: 40, kR: 10},
              {kW: 50, kR: 8},
              {kW: 55, kR: 8},
            ],
          },
          {
            kEx: 'lat_pulldown',
            kRest: 90,
            kSets: [
              {kW: 50, kR: 10},
              {kW: 60, kR: 8},
              {kW: 65, kR: 8},
            ],
          },
          {
            kEx: 'db_ohp',
            kRest: 90,
            kSets: [
              {kW: 20, kR: 10},
              {kW: 24, kR: 8},
              {kW: 26, kR: 8},
            ],
          },
          {
            kEx: 'triceps_pushdown',
            kRest: 60,
            kSets: [
              {kW: 20, kR: 12},
              {kW: 25, kR: 10},
              {kW: 25, kR: 10},
            ],
          },
          {
            kEx: 'leg_ext',
            kRest: 90,
            kSets: [
              {kW: 40, kR: 12},
              {kW: 50, kR: 10},
              {kW: 55, kR: 10},
            ],
          },
        ],
      },
      {
        'name': 'Full C - Híbrido',
        'exercises': [
          {
            kEx: 'front_squat',
            kRest: 150,
            kSets: [
              {kW: 40, kR: 8},
              {kW: 50, kR: 6},
              {kW: 60, kR: 5},
            ],
          },
          {
            kEx: 'db_bench',
            kRest: 90,
            kSets: [
              {kW: 28, kR: 10},
              {kW: 32, kR: 8},
              {kW: 36, kR: 6},
            ],
          },
          {
            kEx: 'pullup',
            kRest: 90,
            kSets: [
              {kW: 0, kR: 8},
              {kW: 0, kR: 6},
              {kW: 0, kR: 6},
            ],
          },
          {
            kEx: 'arnold_press',
            kRest: 90,
            kSets: [
              {kW: 18, kR: 10},
              {kW: 20, kR: 8},
              {kW: 22, kR: 8},
            ],
          },
          {
            kEx: 'hammer_curl',
            kRest: 60,
            kSets: [
              {kW: 12, kR: 12},
              {kW: 14, kR: 10},
              {kW: 14, kR: 10},
            ],
          },
          {
            kEx: 'cable_curl',
            kRest: 60,
            kSets: [
              {kW: 15, kR: 12},
              {kW: 20, kR: 10},
              {kW: 20, kR: 10},
            ],
          },
        ],
      },
    ]);

    return routinesCreated;
  }

  /// Generates realistic body measurement data over the given period.
  Future<void> _generateBodyMeasurements(
    DateTime periodStart,
    DateTime now,
  ) async {
    final db = await _db.database;

    // ── Measurement definitions with realistic progression ───────────
    // Each entry: (type, startVal, endVal, unit, isBilateral, dayInterval)
    final definitions = [
      ('weight', 82.0, 77.0, 'kg', false, 7),
      ('bodyFat', 18.5, 14.0, '%', false, 14),
      ('waist', 88.0, 81.0, 'cm', false, 10),
      ('chest', 100.0, 104.5, 'cm', false, 14),
      ('arm', 33.5, 36.5, 'cm', true, 14),
      ('forearm', 27.0, 29.0, 'cm', true, 14),
      ('neck', 39.0, 38.0, 'cm', false, 14),
      ('thigh', 55.0, 57.5, 'cm', true, 14),
      ('calf', 36.0, 37.0, 'cm', true, 14),
      ('hip', 98.0, 94.0, 'cm', false, 14),
    ];

    final totalDays = now.difference(periodStart).inDays;

    for (final def in definitions) {
      final type = def.$1;
      final startVal = def.$2;
      final endVal = def.$3;
      final unit = def.$4;
      final isBilateral = def.$5;
      final interval = def.$6;

      final progress = endVal - startVal;

      // Time-of-day distribution
      final todOptions = [
        null,
        null,
        null,
        'morning',
        'afternoon',
        'morning',
        'evening',
      ];

      // Generate measurements at regular intervals with some noise
      int dayOffset = _rng.nextInt(interval); // random start offset
      while (dayOffset < totalDays) {
        final date = periodStart.add(Duration(days: dayOffset));
        if (date.isAfter(now)) break;

        final dateStr = date.toIso8601String().substring(0, 10);

        // Progress factor (0.0 to 1.0) with slight random jitter
        final rawFactor = dayOffset / totalDays;
        // Add noise: most measurements are close to the trend line
        final noise = (_rng.nextDouble() - 0.5) * 0.6; // ±0.3 progress noise
        final factor = (rawFactor + noise).clamp(0.0, 1.0);

        final trendValue = startVal + progress * factor;

        // Add measurement noise: larger for weight, smaller for tape measures
        final measurementNoise = type == 'weight'
            ? (_rng.nextDouble() - 0.5) *
                  1.2 // ±0.6kg for weight
            : type == 'bodyFat'
            ? (_rng.nextDouble() - 0.5) *
                  0.8 // ±0.4% for body fat
            : (_rng.nextDouble() - 0.5) * 0.6; // ±0.3cm for tape

        double value = (trendValue + measurementNoise).clamp(1.0, 200.0);
        value = double.parse(value.toStringAsFixed(1));

        final tod = todOptions[_rng.nextInt(todOptions.length)];
        final isFasted = _rng.nextDouble() < 0.35 ? 1 : 0;

        // 30% chance of a comment on weight/bodyfat measurements
        String? comment;
        if (_rng.nextDouble() < 0.3 &&
            (type == 'weight' || type == 'bodyFat')) {
          comment = _randomWeightComment();
          if (comment?.isEmpty == true) comment = null;
        }

        if (isBilateral) {
          // Generate left and right with slight natural asymmetry
          final asymmetry = double.parse(
            ((_rng.nextDouble() - 0.5) * 0.8).toStringAsFixed(1),
          ); // ±0.4cm asymmetry

          for (final side in ['left', 'right']) {
            final sideOffset = side == 'right' ? asymmetry : 0.0;
            final sideValue = double.parse(
              (value + sideOffset).clamp(1.0, 200.0).toStringAsFixed(1),
            );

            await db.rawInsert(
              'INSERT INTO body_measurements '
              '(id, type, value, unit, date, comment, time_of_day, is_fasted, side, created_at) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                _uuid.v4(),
                type,
                sideValue,
                unit,
                dateStr,
                comment,
                tod,
                isFasted,
                side,
                date.toIso8601String(),
              ],
            );
          }
        } else {
          await db.rawInsert(
            'INSERT INTO body_measurements '
            '(id, type, value, unit, date, comment, time_of_day, is_fasted, side, created_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              _uuid.v4(),
              type,
              value,
              unit,
              dateStr,
              comment,
              tod,
              isFasted,
              null,
              date.toIso8601String(),
            ],
          );
        }

        // Next measurement: interval with some randomness
        final jitter = _rng.nextInt(5) - 2; // -2 to +2 days
        dayOffset += (interval + jitter).clamp(3, 21);
      }
    }
  }

  String? _randomWeightComment() {
    final options = [
      'Pós treino',
      'Em jejum',
      'Depois do café',
      'Final de semana',
      'Segunda feira',
      'Pós refeição',
      null,
      null,
      null,
      null,
    ];
    return options[_rng.nextInt(options.length)];
  }

  List<Map<String, dynamic>> _pickExercises(
    Map<String, List<Map<String, dynamic>>> byCategory,
    List<String> categoryKeys,
    int count,
  ) {
    final pool = <Map<String, dynamic>>[];
    for (final key in categoryKeys) {
      if (byCategory.containsKey(key)) {
        pool.addAll(byCategory[key]!);
      }
    }
    if (pool.isEmpty) return [];
    pool.shuffle(_rng);

    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final ex in pool) {
      if (result.length >= count) break;
      if (seen.add(ex['id'] as String)) {
        result.add(ex);
      }
    }
    return result;
  }

  double _baseWeight(String name) {
    if (name.contains('Agachamento')) return 60;
    if (name.contains('Levantamento Terra')) return 80;
    if (name.contains('Leg Press')) return 100;
    if (name.contains('Supino') || name.contains('Mergulho')) return 40;
    if (name.contains('Remada')) return 40;
    if (name.contains('Rosca') || name.contains('Martelo')) return 10;
    if (name.contains('Tríceps') || name.contains('Francês')) return 15;
    if (name.contains('Desenvolvimento') || name.contains('Militar')) return 30;
    if (name.contains('Elevação') || name.contains('Crucifixo')) return 8;
    if (name.contains('Puxada')) return 40;
    if (name.contains('Prancha') || name.contains('Flexão')) return 0;
    if (name.contains('Barra')) return 0;
    return 20;
  }

  double _progressRate(String name) {
    if (name.contains('Agachamento') ||
        name.contains('Leg Press') ||
        name.contains('Terra')) {
      return 2.5;
    }
    if (name.contains('Supino') ||
        name.contains('Remada') ||
        name.contains('Puxada')) {
      return 1.5;
    }
    if (name.contains('Rosca') || name.contains('Tríceps')) {
      return 0.5;
    }
    if (name.contains('Elevação') || name.contains('Crucifixo')) {
      return 0.25;
    }
    if (name.contains('Desenvolvimento')) {
      return 1.0;
    }
    return 1.0;
  }
}

extension _IntRounding on int {
  int roundToMultiple(int multiple) {
    final remainder = this % multiple;
    return remainder < multiple ~/ 2
        ? this - remainder
        : this + (multiple - remainder);
  }
}
