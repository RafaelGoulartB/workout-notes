import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Ids and dates of the "heavy user" database built by [seedHeavyUser], so
/// tests can call id-based tools without querying for them first.
class HeavyUserFixture {
  final DateTime today;
  final List<String> routineIds;
  final String routineId;
  final String routineDayId;
  final String completedWorkoutId;
  final String plannedWorkoutId;
  final String inProgressWorkoutId;
  final String runPlanId;
  final String runActivityId;
  final String bikeActivityId;
  final String foodId;
  final String savedMealId;
  final String goalId;
  final String sleepNightDate;
  final String diaryDate;
  final String periodizationPlanId;
  final String benchExerciseId;

  const HeavyUserFixture({
    required this.today,
    required this.routineIds,
    required this.routineId,
    required this.routineDayId,
    required this.completedWorkoutId,
    required this.plannedWorkoutId,
    required this.inProgressWorkoutId,
    required this.runPlanId,
    required this.runActivityId,
    required this.bikeActivityId,
    required this.foodId,
    required this.savedMealId,
    required this.goalId,
    required this.sleepNightDate,
    required this.diaryDate,
    required this.periodizationPlanId,
    required this.benchExerciseId,
  });
}

String _ts(DateTime value) => value.toIso8601String();

const _foodStems = [
  'Arroz',
  'Feijão',
  'Frango',
  'Ovo',
  'Banana',
  'Maçã',
  'Aveia',
  'Iogurte',
  'Queijo',
  'Pão',
  'Batata',
  'Carne',
  'Peixe',
  'Leite',
  'Brócolis',
  'Tomate',
  'Azeite',
  'Castanha',
  'Whey',
  'Macarrão',
];
const _foodStyles = [
  'integral cozido',
  'grelhado',
  'cru',
  'assado',
  'light',
  'natural',
];

/// Seeds a database with a realistic, big account: ~70 strength workouts
/// (some planned for the future), 4 full routines, ~150 runs and bike rides,
/// a 12-week running plan, 90 sleep nights with monitor sessions, 45 diary
/// days, 120 foods, 15 saved meals, 45 body measurements, goals and a
/// periodization plan. The database must be the real schema with the catalog
/// seed (`installTestDb(seed: true)`).
Future<HeavyUserFixture> seedHeavyUser(Database db, {DateTime? now}) async {
  final today = dayOf(now ?? DateTime.now());
  final random = math.Random(42);

  final routineIds = await _seedRoutines(db, today);
  final workouts = await _seedWorkouts(db, today, routineIds, random);
  final runs = await _seedRuns(db, today, random);
  final runPlanId = await _seedRunPlan(db, today, runs.activityIds);
  final sleepNight = await _seedSleep(db, today, random);
  final nutrition = await _seedNutrition(db, today, random);
  await _seedBody(db, today, random);
  final goalId = await _seedGoals(db, today);
  await _seedSettings(db);
  final planId = await _seedPeriodization(
    today,
    routineId: routineIds.first,
    runPlanId: runPlanId,
  );

  return HeavyUserFixture(
    today: today,
    routineIds: routineIds,
    routineId: routineIds.first,
    routineDayId: '${routineIds.first}-d0',
    completedWorkoutId: workouts.completedId,
    plannedWorkoutId: workouts.plannedId,
    inProgressWorkoutId: workouts.inProgressId,
    runPlanId: runPlanId,
    runActivityId: runs.detailId,
    bikeActivityId: runs.bikeId,
    foodId: nutrition.foodId,
    savedMealId: nutrition.savedMealId,
    goalId: goalId,
    sleepNightDate: sleepNight,
    diaryDate: dateKey(addDays(today, -1)),
    periodizationPlanId: planId,
    benchExerciseId: 'bench_press',
  );
}

// ---------------------------------------------------------------------------
// Routines and strength workouts
// ---------------------------------------------------------------------------

/// Exercise ids of the four routine templates (6 exercises per day).
const _routineDays = <List<String>>[
  [
    'bench_press',
    'incl_bench',
    'ohp',
    'lat_raise',
    'triceps_pushdown',
    'skull_crusher',
  ],
  [
    'bent_row',
    'lat_pulldown',
    'seated_row',
    'face_pull',
    'bb_curl',
    'hammer_curl',
  ],
  ['squat', 'leg_press', 'romanian_dl', 'leg_curl', 'calf_raise', 'hip_thrust'],
  ['db_bench', 'db_ohp', 'cable_fly', 'pullup', 'db_row', 'cable_curl'],
];

const _baseWeights = <String, double>{
  'bench_press': 80,
  'incl_bench': 60,
  'ohp': 45,
  'lat_raise': 10,
  'triceps_pushdown': 30,
  'skull_crusher': 25,
  'bent_row': 70,
  'lat_pulldown': 60,
  'seated_row': 55,
  'face_pull': 25,
  'bb_curl': 30,
  'hammer_curl': 14,
  'squat': 100,
  'leg_press': 180,
  'romanian_dl': 80,
  'leg_curl': 45,
  'calf_raise': 60,
  'hip_thrust': 90,
  'db_bench': 30,
  'db_ohp': 22,
  'cable_fly': 15,
  'pullup': 0,
  'db_row': 32,
  'cable_curl': 25,
};

Future<List<String>> _seedRoutines(Database db, DateTime today) async {
  final ids = <String>[];
  final batch = db.batch();
  for (var r = 0; r < 4; r++) {
    final routineId = 'routine-$r';
    ids.add(routineId);
    batch.insert('routines', {
      'id': routineId,
      'name': ['Upper Lower', 'Push Pull Legs', 'Full Body', 'Hipertrofia'][r],
      'notes': r == 0 ? 'Foco em progressão de carga' : null,
      'created_at': _ts(addDays(today, -300 + r)),
    });
    for (var d = 0; d < 4; d++) {
      final dayId = '$routineId-d$d';
      batch.insert('routine_days', {
        'id': dayId,
        'routine_id': routineId,
        'name': 'Dia ${String.fromCharCode(65 + d)}',
        'notes': d == 0 ? 'Aquecer bem antes' : null,
        'order_index': d,
      });
      final exercises = _routineDays[(r + d) % 4];
      for (var e = 0; e < exercises.length; e++) {
        final reId = '$dayId-e$e';
        batch.insert('routine_exercises', {
          'id': reId,
          'routine_day_id': dayId,
          'exercise_id': exercises[e],
          'order_index': e,
          'rest_time_seconds': 90,
          'superset_group_id': e == 4 || e == 5 ? '$dayId-ss' : null,
        });
        for (var s = 0; s < 4; s++) {
          batch.insert('predefined_sets', {
            'id': '$reId-s$s',
            'routine_exercise_id': reId,
            'weight': _baseWeights[exercises[e]],
            'reps': 8 + (s % 3),
            'is_warmup': s == 0 && e == 0 ? 1 : 0,
            'order_index': s,
          });
        }
      }
    }
  }
  await batch.commit(noResult: true);
  return ids;
}

class _WorkoutIds {
  final String completedId;
  final String plannedId;
  final String inProgressId;

  const _WorkoutIds(this.completedId, this.plannedId, this.inProgressId);
}

Future<_WorkoutIds> _seedWorkouts(
  Database db,
  DateTime today,
  List<String> routineIds,
  math.Random random,
) async {
  final batch = db.batch();
  var completedId = '';
  void addWorkout({
    required String id,
    required DateTime date,
    required List<String> exercises,
    required bool finished,
    required bool started,
    required double progress,
    String? routineId,
    String? dayId,
    bool done = true,
    bool aerobic = false,
  }) {
    final day = dateKey(date);
    final start = DateTime(date.year, date.month, date.day, 18);
    batch.insert('workouts', {
      'id': id,
      'date': day,
      'start_time': started ? _ts(start) : null,
      'end_time': finished ? _ts(start.add(const Duration(minutes: 65))) : null,
      'duration_seconds': finished ? 3900 + random.nextInt(600) : null,
      'estimated_calories': finished ? 320.0 + random.nextInt(140) : null,
      'comment': finished && random.nextInt(6) == 0
          ? 'Treino pesado, bom foco'
          : null,
      'feeling_rating': finished ? 3 + random.nextInt(3) : null,
      'is_from_routine': routineId == null ? 0 : 1,
      'routine_id': routineId,
      'routine_day_id': dayId,
      'created_at': _ts(start),
    });
    for (var e = 0; e < exercises.length; e++) {
      final entryId = '$id-e$e';
      batch.insert('exercise_entries', {
        'id': entryId,
        'workout_id': id,
        'exercise_id': exercises[e],
        'order_index': e,
        'rest_time_seconds': 90,
      });
      final base = _baseWeights[exercises[e]] ?? 20;
      for (var s = 0; s < 4; s++) {
        final weight = base == 0
            ? 0.0
            : ((base * (0.82 + 0.18 * progress) / 2.5).round() * 2.5);
        final complete = done && (!started || finished || e < 2);
        batch.insert('sets', {
          'id': '$entryId-s$s',
          'exercise_entry_id': entryId,
          'weight': weight,
          'reps': 12 - s - (random.nextInt(2)),
          'is_complete': complete ? 1 : 0,
          'is_warmup': 0,
          'rpe': complete && finished ? 6.5 + s * 0.5 : null,
          'order_index': s,
        });
      }
    }
    if (aerobic) {
      final entryId = '$id-cardio';
      batch.insert('exercise_entries', {
        'id': entryId,
        'workout_id': id,
        'exercise_id': 'treadmill',
        'order_index': exercises.length,
      });
      batch.insert('sets', {
        'id': '$entryId-s0',
        'exercise_entry_id': entryId,
        'distance': 2.0,
        'time_seconds': 720,
        'is_complete': 1,
        'is_warmup': 0,
        'order_index': 0,
      });
    }
  }

  const completedCount = 62;
  for (var i = 0; i < completedCount; i++) {
    final date = addDays(today, -(1 + (i * 1.75).round()));
    final routine = routineIds[(i ~/ 16) % routineIds.length];
    final dayIndex = i % 4;
    final id = 'w-$i';
    if (i == 3) completedId = id;
    addWorkout(
      id: id,
      date: date,
      exercises:
          _routineDays[(int.parse(routine.split('-').last) + dayIndex) % 4],
      finished: true,
      started: true,
      progress: 1 - i / completedCount,
      routineId: routine,
      dayId: '$routine-d$dayIndex',
      aerobic: i % 12 == 0,
    );
  }
  // An unfinished workout started today and one planned in the past.
  addWorkout(
    id: 'w-in-progress',
    date: today,
    exercises: _routineDays[0],
    finished: false,
    started: true,
    progress: 1,
    routineId: routineIds.first,
    dayId: '${routineIds.first}-d0',
  );
  addWorkout(
    id: 'w-missed',
    date: addDays(today, -20),
    exercises: _routineDays[1],
    finished: false,
    started: false,
    progress: 1,
    done: false,
  );
  // Planned workouts for the coming week.
  for (var i = 1; i <= 5; i++) {
    addWorkout(
      id: 'w-planned-$i',
      date: addDays(today, i),
      exercises: _routineDays[i % 4],
      finished: false,
      started: false,
      progress: 1,
      done: false,
      routineId: routineIds.first,
      dayId: '${routineIds.first}-d${i % 4}',
    );
  }
  await batch.commit(noResult: true);
  return _WorkoutIds(completedId, 'w-planned-1', 'w-in-progress');
}

// ---------------------------------------------------------------------------
// Runs
// ---------------------------------------------------------------------------

class _RunIds {
  final List<String> activityIds;
  final String detailId;
  final String bikeId;

  const _RunIds(this.activityIds, this.detailId, this.bikeId);
}

Future<_RunIds> _seedRuns(
  Database db,
  DateTime today,
  math.Random random,
) async {
  final ids = <String>[];
  var detailId = '';
  var bikeId = '';
  final batch = db.batch();
  const total = 150;
  for (var i = 0; i < total; i++) {
    final date = addDays(today, -(i * 2 + 1));
    final bike = i % 5 == 4;
    final id = bike ? 'bike-$i' : 'run-$i';
    final startedAt = DateTime(date.year, date.month, date.day, 7, 10 + i % 40);
    final progress = 1 - i / total;
    final distance = bike
        ? 14000.0 + random.nextInt(8000)
        : (i % 7 == 0
              ? 14000.0 + random.nextInt(4000)
              : 5000.0 + random.nextInt(4500));
    final pace = 345 - 40 * progress + random.nextInt(18);
    final moving = bike
        ? 1800 + random.nextInt(900)
        : (distance / 1000 * pace).round();
    ids.add(id);
    if (!bike && i == 8) detailId = id;
    if (bike && bikeId.isEmpty) bikeId = id;
    batch.insert('run_activities', {
      'id': id,
      'activity_type': bike ? 'stationary_bike' : 'running',
      'started_at': _ts(startedAt),
      'ended_at': _ts(startedAt.add(Duration(seconds: moving + 30))),
      'duration_seconds': moving + 30,
      'moving_time_seconds': moving,
      'distance_meters': distance,
      'avg_pace_sec_per_km': bike ? null : pace,
      'max_pace_sec_per_km': bike ? null : pace - 40,
      'calories': 250 + random.nextInt(450),
      'title': bike ? 'Bike indoor' : (i % 7 == 0 ? 'Longão' : null),
      'notes': i % 11 == 0 ? 'Calor forte, ritmo controlado' : null,
      'rpe': 4.0 + random.nextInt(5),
      'feeling_rating': 3 + random.nextInt(3),
      'status': 'completed',
      'created_at': _ts(startedAt),
      'updated_at': _ts(startedAt),
      'best_split_pace_sec_per_km': bike ? null : pace - 25,
      'best_effort_1k_sec': bike ? null : (pace - 28).round(),
      'best_effort_3k_sec': bike || distance < 3000
          ? null
          : ((pace - 15) * 3).round(),
      'best_effort_5k_sec': bike || distance < 5000
          ? null
          : ((pace - 8) * 5).round(),
      'best_effort_10k_sec': bike || distance < 10000
          ? null
          : (pace * 10).round(),
      'efforts_computed': 1,
      'elevation_gain_meters': bike ? null : 40.0 + random.nextInt(120),
      'raw_point_count': bike ? null : 900,
      'stored_point_count': bike ? null : 300,
      'route_quality': bike ? null : 'good',
    });
    if (id == detailId) {
      final km = (distance / 1000).floor();
      for (var s = 0; s < km + 1; s++) {
        final partial = s == km;
        final meters = partial ? distance - km * 1000 : 1000.0;
        batch.insert('run_splits', {
          'activity_id': id,
          'split_index': s,
          'distance_meters': meters,
          'duration_seconds': (meters / 1000 * (pace + random.nextInt(14) - 7))
              .round(),
          'pace_sec_per_km': pace + random.nextInt(14) - 7,
          'is_partial': partial ? 1 : 0,
        });
      }
      for (var l = 0; l < 4; l++) {
        batch.insert('run_laps', {
          'activity_id': id,
          'lap_index': l,
          'start_distance_meters': l * 1000.0,
          'distance_meters': 1000.0,
          'duration_seconds': pace.round(),
          'pace_sec_per_km': pace,
        });
      }
    }
  }
  await batch.commit(noResult: true);
  return _RunIds(ids, detailId, bikeId);
}

/// 12-week plan, four sessions a week (easy, intervals, easy, long), active
/// since five weeks ago; past sessions are completed (linked to runs) or
/// skipped, the rest planned.
Future<String> _seedRunPlan(
  Database db,
  DateTime today,
  List<String> activityIds,
) async {
  const planId = 'run-plan-12w';
  final planStart = mondayOf(addDays(today, -7 * 5));
  final batch = db.batch();
  batch.insert('run_plans', {
    'id': planId,
    'name': 'Plano 10K em 12 semanas',
    'notes': 'Foco em base aeróbica e um treino de qualidade por semana',
    'goal_kind': '10k',
    'race_date': dateKey(addDays(planStart, 7 * 12 - 1)),
    'weeks': 12,
    'status': 'active',
    'activated_at': dateKey(planStart),
    'completion_count': 0,
    'template_key': '10k_beginner',
    'created_at': _ts(planStart),
    'updated_at': _ts(planStart),
  });
  var activityCursor = 0;
  for (var week = 0; week < 12; week++) {
    for (var s = 0; s < 4; s++) {
      final workoutId = 'rpw-$week-$s';
      final dayOfWeek = const [2, 4, 5, 7][s];
      final interval = s == 1;
      final long = s == 3;
      batch.insert('run_plan_workouts', {
        'id': workoutId,
        'run_plan_id': planId,
        'week_index': week,
        'day_of_week': dayOfWeek,
        'order_index': s,
        'kind': interval ? 'interval' : (long ? 'long' : 'easy'),
        'name': interval ? 'Tiros 6x400m' : (long ? 'Longão' : 'Rodagem leve'),
        'notes': interval ? 'Recuperação em trote' : null,
        'target_distance_meters': (long ? 8000 + week * 500 : 5000 + week * 100)
            .toDouble(),
        'target_duration_seconds': null,
        'target_pace_sec_per_km': interval ? 290.0 : 340.0,
        'effort_zone': interval ? 'Z4' : 'Z2',
        'created_at': _ts(planStart),
      });
      if (interval) {
        final steps = <(String, int, int?, int)>[
          ('warmup', 1200, null, 1),
          ('work', 400, 1, 6),
          ('recovery', 200, 1, 6),
          ('cooldown', 1000, null, 1),
        ];
        for (var i = 0; i < steps.length; i++) {
          batch.insert('run_workout_steps', {
            'id': '$workoutId-st$i',
            'run_plan_workout_id': workoutId,
            'order_index': i,
            'role': steps[i].$1,
            'metric': 'distance',
            'value': steps[i].$2,
            'repeat_group': steps[i].$3,
            'repeat_count': steps[i].$4,
            'target_pace_min_sec_per_km': steps[i].$1 == 'work' ? 280.0 : null,
            'target_pace_max_sec_per_km': steps[i].$1 == 'work' ? 300.0 : null,
          });
        }
      }
      final date = addDays(planStart, week * 7 + dayOfWeek - 1);
      final past = date.isBefore(today);
      var status = 'planned';
      String? activityId;
      if (past) {
        if ((week + s) % 5 == 4) {
          status = 'skipped';
        } else {
          status = 'completed';
          activityId =
              activityIds[math.min(activityCursor++, activityIds.length - 1)];
        }
      }
      batch.insert('scheduled_runs', {
        'id': 'sr-$week-$s',
        'date': dateKey(date),
        'run_plan_id': planId,
        'run_plan_workout_id': workoutId,
        'status': status,
        'run_activity_id': activityId,
        'created_at': _ts(planStart),
        'updated_at': _ts(planStart),
      });
    }
  }
  for (var w = 1; w <= 4; w++) {
    batch.insert('run_plan_adaptations', {
      'id': 'adapt-$w',
      'run_plan_id': planId,
      'week_index': w,
      'kind': w == 3 ? 'step_back' : 'hold',
      'status': w == 4 ? 'dismissed' : 'applied',
      'payload_json': jsonEncode({
        'adjustment': w == 3 ? 'stepBack' : 'hold',
        'fromWeek': w,
        'missedWeeks': 0,
        'doneKm': 18.5,
        'plannedKm': 21.0,
      }),
      'created_at': _ts(addDays(planStart, w * 7)),
    });
  }
  await batch.commit(noResult: true);
  return planId;
}

// ---------------------------------------------------------------------------
// Sleep
// ---------------------------------------------------------------------------

Future<String> _seedSleep(
  Database db,
  DateTime today,
  math.Random random,
) async {
  final batch = db.batch();
  var detailDate = '';
  for (var i = 0; i < 90; i++) {
    final date = addDays(today, -i);
    final day = dateKey(date);
    final monitored = i % 4 != 3;
    final minutes = 360 + random.nextInt(130);
    final inBed = minutes + 25 + random.nextInt(30);
    final bedtime = 22 * 60 + 15 + random.nextInt(90);
    final wake = (bedtime + inBed) % 1440;
    final entryId = 'sleep-$i';
    if (monitored && detailDate.isEmpty && i >= 2) detailDate = day;
    batch.insert('sleep_entries', {
      'id': entryId,
      'date': day,
      'sleep_minutes': inBed,
      'actual_sleep_minutes': monitored ? null : minutes,
      'bedtime_minutes': bedtime,
      'wake_time_minutes': wake,
      'comment': i % 9 == 0 ? 'Acordei algumas vezes' : null,
      'source': monitored ? 'monitored' : 'manual',
      'time_in_bed_minutes': inBed,
      'estimated_sleep_minutes': monitored ? minutes : null,
      'created_at': _ts(DateTime(date.year, date.month, date.day, 7)),
    });
    if (monitored) {
      final started = DateTime(date.year, date.month, date.day - 1, 22, 30);
      final alarm = i % 3 == 0;
      batch.insert('sleep_monitor_sessions', {
        'id': 'sess-$i',
        'sleep_entry_id': entryId,
        'status': 'completed',
        'started_at': _ts(started),
        'ended_at': _ts(started.add(Duration(minutes: inBed))),
        'alarm_at': alarm
            ? _ts(started.add(Duration(minutes: inBed + 10)))
            : null,
        'monitor_mode': alarm ? 'alarm_without_mission' : 'monitoring_only',
        'utc_offset_start_minutes': -180,
        'utc_offset_end_minutes': -180,
        'sensor_mode': 'audio',
        'algorithm_version': 'audio-features-v5',
        'time_in_bed_minutes': inBed,
        'quiet_minutes': inBed - 40,
        'noisy_minutes': 40,
        'estimated_sleep_minutes': minutes,
        'noise_event_count': random.nextInt(9),
        'signal_quality_score': 0.8,
        'analysis_status': 'available',
        'sleep_onset_at': _ts(started.add(const Duration(minutes: 18))),
        'final_wake_at': _ts(started.add(Duration(minutes: inBed - 5))),
        'sleep_latency_minutes': 18,
        'awake_minutes': inBed - minutes,
        'sleeping_minutes': minutes,
        'unknown_minutes': 5,
        'restless_sleep_minutes': 22,
        'snore_minutes': random.nextInt(25),
        'awakening_count': random.nextInt(4),
        'sleep_efficiency': minutes / inBed * 100,
        'stage_confidence': 0.74,
        'stage_algorithm_version': 'sleep-wake-bedside-v6',
        'smart_window_minutes': alarm ? 30 : null,
        'alarm_fired_at': alarm
            ? _ts(started.add(Duration(minutes: inBed - 5)))
            : null,
        'alarm_trigger': alarm ? (i % 2 == 0 ? 'awake' : 'deadline') : null,
        'wake_feeling': alarm ? 3 + random.nextInt(3) : null,
        'end_reason': 'user',
        'created_at': _ts(started),
      });
    }
  }
  await batch.commit(noResult: true);
  return detailDate;
}

// ---------------------------------------------------------------------------
// Nutrition
// ---------------------------------------------------------------------------

class _NutritionIds {
  final String foodId;
  final String savedMealId;

  const _NutritionIds(this.foodId, this.savedMealId);
}

Map<String, double?> _nutrientsFor(int seed, double factor) {
  double? v(double base, {bool missing = false}) =>
      missing ? null : double.parse((base * factor).toStringAsFixed(1));
  return {
    'calories': v(90.0 + (seed % 9) * 25),
    'protein_g': v(3.0 + seed % 7 * 3),
    'carbs_g': v(8.0 + seed % 5 * 6),
    'fat_g': v(1.0 + seed % 4 * 2),
    'saturated_fat_g': v(0.5 + seed % 3, missing: seed % 4 == 0),
    'monounsaturated_fat_g': v(0.4, missing: seed % 4 == 0),
    'polyunsaturated_fat_g': v(0.3, missing: seed % 4 == 0),
    'trans_fat_g': v(0, missing: seed % 4 == 0),
    'fiber_g': v(1.0 + seed % 4),
    'sugars_g': v(1.0 + seed % 6),
    'sodium_mg': v(40.0 + seed % 8 * 20),
    'potassium_mg': v(150.0 + seed % 5 * 40, missing: seed % 3 == 0),
    'calcium_mg': v(20.0 + seed % 6 * 15, missing: seed % 3 == 0),
    'iron_mg': v(0.8 + seed % 4 * 0.5, missing: seed % 3 == 0),
    'magnesium_mg': v(18.0 + seed % 5 * 8, missing: seed % 3 == 0),
    'zinc_mg': v(0.6, missing: seed % 3 == 0),
    'vitamin_a_ug': v(12.0, missing: seed % 2 == 0),
    'vitamin_c_mg': v(2.0, missing: seed % 2 == 0),
    'vitamin_d_ug': v(0.2, missing: seed % 2 == 0),
    'vitamin_b12_ug': v(0.4, missing: seed % 2 == 0),
  };
}

Future<_NutritionIds> _seedNutrition(
  Database db,
  DateTime today,
  math.Random random,
) async {
  final batch = db.batch();
  final now = _ts(today);
  const foodCount = 120;
  final foodNames = <String>[];
  for (var i = 0; i < foodCount; i++) {
    final name =
        '${_foodStems[i % _foodStems.length]} ${_foodStyles[(i ~/ _foodStems.length) % _foodStyles.length]}';
    foodNames.add(name);
    final foodId = 'food-$i';
    batch.insert('foods', {
      'id': foodId,
      'source': i % 3 == 0 ? 'open_food_facts' : 'manual',
      'external_id': foodId,
      'name': name,
      'search_name': name.toLowerCase(),
      'brand': i % 4 == 0 ? 'Marca ${i % 7}' : null,
      'barcode': i % 3 == 0 ? '789${1000000 + i}' : null,
      'fetched_at': now,
      'last_used_at': i < 60 ? _ts(addDays(today, -i)) : null,
      'is_favorite': i % 10 == 0 ? 1 : 0,
    });
    batch.insert('food_variants', {
      'id': 'fv-$i',
      'food_id': foodId,
      'label': 'Padrão',
      'reference_amount': 100.0,
      'reference_unit': 'g',
      ..._nutrientsFor(i, 1),
      'extra_nutrients_json': i % 5 == 0
          ? jsonEncode({'selenium_ug': 12.5})
          : null,
      'is_estimated': i % 6 == 0 ? 1 : 0,
    });
    batch.insert('food_servings', {
      'id': 'fs-$i',
      'food_variant_id': 'fv-$i',
      'label': '1 porção',
      'quantity': 1.0,
      'unit': 'porção',
      'grams_equivalent': 120.0,
    });
  }

  const mealTypes = ['breakfast', 'lunch', 'dinner', 'snacks'];
  for (var day = 0; day < 45; day++) {
    final date = dateKey(addDays(today, -(day + 1) - day ~/ 10));
    for (var m = 0; m < mealTypes.length; m++) {
      final logId = 'ml-$day-$m';
      batch.insert('meal_logs', {
        'id': logId,
        'date': date,
        'meal_type': mealTypes[m],
        'name': null,
        'notes': day == 0 && m == 1 ? 'Almoço pós-treino' : null,
        'created_at': now,
      });
      for (var k = 0; k < 3; k++) {
        final foodIndex = (day * 7 + m * 3 + k * 5) % foodCount;
        final factor = 0.8 + random.nextInt(10) / 10;
        final nutrients = _nutrientsFor(foodIndex, factor);
        batch.insert('meal_log_items', {
          'id': 'mli-$day-$m-$k',
          'meal_log_id': logId,
          'food_id': 'food-$foodIndex',
          'food_variant_id': 'fv-$foodIndex',
          'food_name_snapshot': foodNames[foodIndex],
          'brand_snapshot': foodIndex % 4 == 0
              ? 'Marca ${foodIndex % 7}'
              : null,
          'quantity': (100 * factor).roundToDouble(),
          'unit': 'g',
          ...nutrients,
          'nutrition_snapshot_json': jsonEncode({
            'version': 3,
            'source': 'manual',
            'variant_label': 'Padrão',
            'reference_amount': 100.0,
            'reference_unit': 'g',
            'grams_equivalent': (100 * factor).roundToDouble(),
            'is_estimated': foodIndex % 6 == 0,
            'has_missing_values': foodIndex % 3 == 0,
          }),
          'created_at': now,
        });
      }
    }
  }

  for (var s = 0; s < 15; s++) {
    final id = 'saved-$s';
    batch.insert('saved_meals', {
      'id': id,
      'name': 'Refeição modelo $s',
      'meal_type': mealTypes[s % 4],
      'portions': 1.0,
      'created_at': now,
      'updated_at': now,
    });
    for (var k = 0; k < 4; k++) {
      final foodIndex = (s * 4 + k) % foodCount;
      batch.insert('saved_meal_items', {
        'id': '$id-i$k',
        'saved_meal_id': id,
        'food_id': 'food-$foodIndex',
        'food_variant_id': 'fv-$foodIndex',
        'food_name_snapshot': foodNames[foodIndex],
        'quantity': 150.0,
        'unit': 'g',
        'serving_label': '1 porção',
        'serving_grams_equivalent': 120.0,
        'order_index': k,
      });
    }
  }

  batch.insert('nutrition_goals', {
    'id': 'ng-active',
    'calories': 2400.0,
    'protein_g': 170.0,
    'carbs_g': 260.0,
    'fat_g': 70.0,
    'tdee': 2600.0,
    'adjustment_kind': 'deficit',
    'adjustment_percent': 8.0,
    'created_at': now,
    'updated_at': now,
    'is_active': 1,
  });
  await batch.commit(noResult: true);
  return const _NutritionIds('food-0', 'saved-0');
}

// ---------------------------------------------------------------------------
// Body, goals, settings, periodization
// ---------------------------------------------------------------------------

Future<void> _seedBody(Database db, DateTime today, math.Random random) async {
  final batch = db.batch();
  void add(
    String id,
    String type,
    double value,
    String unit,
    int daysAgo, {
    double? secondary,
    String? side,
    bool fasted = false,
  }) {
    batch.insert('body_measurements', {
      'id': id,
      'type': type,
      'value': value,
      'secondary_value': secondary,
      'unit': unit,
      'date': dateKey(addDays(today, -daysAgo)),
      'time_of_day': fasted ? 'morning' : null,
      'is_fasted': fasted ? 1 : 0,
      'side': side,
      'comment': null,
      'created_at': _ts(addDays(today, -daysAgo)),
    });
  }

  for (var i = 0; i < 30; i++) {
    add(
      'bm-w-$i',
      'weight',
      84.0 - (30 - i) * -0.04 + random.nextInt(8) / 10 - 2.4,
      'kg',
      i * 3,
      fasted: true,
    );
  }
  for (var i = 0; i < 7; i++) {
    add('bm-bf-$i', 'bodyFat', 18.0 + i * 0.3, '%', i * 14);
  }
  for (var i = 0; i < 4; i++) {
    add('bm-waist-$i', 'waist', 86.0 + i * 0.5, 'cm', i * 14);
  }
  add('bm-bp-0', 'bloodPressure', 120, 'mmHg', 5, secondary: 78);
  add('bm-bp-1', 'bloodPressure', 118, 'mmHg', 40, secondary: 76);
  add('bm-arm-l', 'arm', 36.5, 'cm', 14, side: 'left');
  add('bm-arm-r', 'arm', 37.0, 'cm', 14, side: 'right');
  await batch.commit(noResult: true);
}

Future<String> _seedGoals(Database db, DateTime today) async {
  final now = _ts(addDays(today, -90));
  final goals = <(String, String, String, String, String, double)>[
    ('goal-volume', 'Volume semanal', 'anaerobic', 'volume', 'weekly', 45000),
    ('goal-days', 'Treinar 4 dias', 'anaerobic', 'days', 'weekly', 4),
    (
      'goal-distance',
      'Correr 80 km no mês',
      'aerobic',
      'distance',
      'monthly',
      80,
    ),
    ('goal-time', 'Cardio semanal', 'aerobic', 'time', 'weekly', 14400),
  ];
  final batch = db.batch();
  for (final g in goals) {
    batch.insert('user_goals', {
      'id': g.$1,
      'title': g.$2,
      'scope': g.$3,
      'metric': g.$4,
      'period': g.$5,
      'target_value': g.$6,
      'created_at': now,
      'is_active': 1,
    });
  }
  await batch.commit(noResult: true);
  return 'goal-volume';
}

Future<void> _seedSettings(Database db) async {
  final settings = <String, String>{
    'distance_unit': 'km',
    'nutrition_profile_sex': 'male',
    'nutrition_profile_age': '32',
    'nutrition_profile_height_cm': '178',
    'nutrition_profile_weight_kg': '83.5',
    'nutrition_profile_activity': 'moderate',
  };
  for (final entry in settings.entries) {
    await db.insert('app_settings', {
      'key': entry.key,
      'value': entry.value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

Future<String> _seedPeriodization(
  DateTime today, {
  required String routineId,
  required String runPlanId,
}) async {
  final repository = DatabaseHelper.instance.periodizationRepo;
  final start = mondayOf(addDays(today, -7 * 4));
  PeriodizationTarget target(
    double calories, {
    double? restCalories,
    String? label,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 1,
    validFrom: start,
    calories: calories,
    proteinG: 170,
    carbsG: 250,
    fatG: 70,
    restCalories: restCalories,
    workoutsPerWeek: 4,
    minSetsPerWeek: 60,
    maxSetsPerWeek: 90,
    routineIds: [routineId],
    strengthDays: const [1, 3, 5],
    runDays: const [2, 6],
    weekLabel: label,
    sleepHours: 8,
    targetWeightKg: 80,
    weeklyWeightChangePercent: -0.4,
    createdAt: start,
  );
  final plan = await repository.createChainedPlan(
    name: 'Ciclo de verão',
    startDate: start,
    phases: [
      PhaseScheduleEntry(
        name: 'Base',
        templateKey: 'maintenance',
        color: 0xFF43A047,
        weeks: 4,
        seedTarget: target(2600, restCalories: 2300),
      ),
      PhaseScheduleEntry(
        name: 'Definição',
        templateKey: 'cutting',
        color: 0xFF1E88E5,
        weeks: 6,
        seedTarget: target(2300, restCalories: 2050, label: 'Déficit'),
      ),
      PhaseScheduleEntry(
        name: 'Manutenção',
        templateKey: 'maintenance',
        color: 0xFF8E24AA,
        weeks: 4,
        seedTarget: target(2600),
      ),
    ],
  );
  return plan.id;
}
