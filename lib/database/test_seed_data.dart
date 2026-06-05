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
  /// Returns the number of workouts created.
  Future<int> generate({int months = 4}) async {
    final exercises = await _db.getExercises();
    if (exercises.isEmpty) return 0;

    // Separate exercises by category for realistic PPL-like splits
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final ex in exercises) {
      final catId = ex['category_id'] as String;
      byCategory.putIfAbsent(catId, () => []).add(ex);
    }

    final now = DateTime.now();
    int workoutsCreated = 0;
    DateTime currentDate = DateTime(now.year, now.month - months, 1);

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
        selectedExercises = _pickExercises(byCategory, ['chest', 'shoulders', 'triceps'], 4);
      } else if (dayMod == 1) {
        // Pull: back, biceps
        selectedExercises = _pickExercises(byCategory, ['back', 'biceps'], 4);
      } else {
        // Legs + core + cardio
        selectedExercises = _pickExercises(byCategory, ['legs', 'core', 'cardio'], 5);
      }

      // Add random extra from fullbody sometimes
      if (_rng.nextDouble() < 0.3 && byCategory.containsKey('fullbody')) {
        selectedExercises.add(byCategory['fullbody']![_rng.nextInt(byCategory['fullbody']!.length)]);
      }

      // Create the workout
      final startHour = 6 + _rng.nextInt(12);
      final startMinute = _rng.nextInt(60);
      final startTime = DateTime(currentDate.year, currentDate.month, currentDate.day, startHour, startMinute);
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
            final monthsSinceStart = currentDate.difference(DateTime(now.year, now.month - months, 1)).inDays / 30;
            final progress = monthsSinceStart * _progressRate(ex['name'] as String);
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

    return workoutsCreated;
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
    if (name.contains('Agachamento') || name.contains('Leg Press') || name.contains('Terra')) return 2.5;
    if (name.contains('Supino') || name.contains('Remada') || name.contains('Puxada')) return 1.5;
    if (name.contains('Rosca') || name.contains('Tríceps')) return 0.5;
    if (name.contains('Elevação') || name.contains('Crucifixo')) return 0.25;
    if (name.contains('Desenvolvimento')) return 1.0;
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
