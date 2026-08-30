// Long-term storage study.
//
// Simulates several years of realistic daily app usage and measures what
// actually matters for the user:
//   - database file size on disk (MB)
//   - per-table row counts and space (via dbstat when available)
//   - JSON backup export size and time (the exact pretty-printed format the
//     app writes, plus compact JSON for comparison)
//   - JSON backup restore/import time (real restoreFromBackup path)
//   - timing of the queries the app's screens actually run (calendar,
//     progress charts, workout detail, sleep dashboard, nutrition, AI chat)
//
// Run manually with: flutter test test/long_term_storage_study.dart
//
// Scenarios are synthetic but the volumes are grounded in real usage
// patterns (frequency per week, sets per workout, monitored nights, etc).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

class Scenario {
  final String name;
  final int years;
  final double workoutsPerWeek;
  final int exercisesPerWorkout;
  final double setsPerExercise;
  final double sleepManualShare;
  final double monitorShare;
  final int monitorAvgMinutes;
  final double nutritionDaysPerWeek;
  final double mealsPerDay;
  final double itemsPerMeal;
  final double newFoodsPerDay;
  final double measurementsPerMonth;
  final double aiChatsPerWeek;
  final int chatMessagesPerConv;
  final int periodizationPlansPerYear;

  const Scenario({
    required this.name,
    required this.years,
    required this.workoutsPerWeek,
    required this.exercisesPerWorkout,
    required this.setsPerExercise,
    required this.sleepManualShare,
    required this.monitorShare,
    required this.monitorAvgMinutes,
    required this.nutritionDaysPerWeek,
    required this.mealsPerDay,
    required this.itemsPerMeal,
    required this.newFoodsPerDay,
    required this.measurementsPerMonth,
    required this.aiChatsPerWeek,
    required this.chatMessagesPerConv,
    required this.periodizationPlansPerYear,
  });

  @override
  String toString() => name;
}

class Timed {
  final Duration duration;
  Timed(this.duration);
}

class ScenarioResult {
  final Scenario scenario;
  final Database db;
  final File dbFile;
  final int dbBytes;
  final int restoreDbBytes;
  final Map<String, int> rowCounts;
  final Map<String, int> tableBytes;
  final Timed exportPretty;
  final Timed exportCompact;
  final int exportPrettyBytes;
  final int exportCompactBytes;
  final Timed restore;
  final int restoreRows;
  final Map<String, Timed> queryTimes;

  ScenarioResult({
    required this.scenario,
    required this.db,
    required this.dbFile,
    required this.dbBytes,
    required this.restoreDbBytes,
    required this.rowCounts,
    required this.tableBytes,
    required this.exportPretty,
    required this.exportCompact,
    required this.exportPrettyBytes,
    required this.exportCompactBytes,
    required this.restore,
    required this.restoreRows,
    required this.queryTimes,
  });
}

const _uuid = Uuid();
const _mealTypes = ['breakfast', 'lunch', 'dinner', 'snacks'];

String _dateStr(DateTime d) =>
    DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);

String _iso(DateTime d) => d.toIso8601String();

double _round2(double v) => (v * 100).roundToDouble() / 100;

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Creates a fresh on-disk database with the real production schema.
Future<Database> _openFreshDb(String dir, String name) {
  return databaseFactoryFfi.openDatabase(
    p.join(dir, name),
    options: OpenDatabaseOptions(
      version: 51,
      onCreate: DatabaseSchema.onCreate,
    ),
  );
}

class _ExercisePool {
  final Database db;
  final math.Random random;
  final List<String> ids = [];
  final List<String> categoryIds = [];

  _ExercisePool(this.db, this.random);

  Future<void> init() async {
    final rows = await db.query(
      'exercises',
      columns: ['id', 'category_id'],
      orderBy: 'created_at ASC',
    );
    ids
      ..clear()
      ..addAll(rows.map((r) => r['id'] as String));
    categoryIds
      ..clear()
      ..addAll(rows.map((r) => r['category_id'] as String));
  }

  String randomId() => ids[random.nextInt(ids.length)];
}

/// Sequential row writer backed by chunked transactions (the same code path
/// the real app uses via `restoreFromBackup`). Avoids `db.batch()` entirely:
/// sqflite_common_ffi batches keep their operations after commit and are
/// timing-sensitive in this environment.
class _TxnWriter {
  final Database db;
  final int chunkSize;
  final List<(String, Map<String, Object?>)> _pending = [];

  _TxnWriter(this.db, {this.chunkSize = 800});

  Future<void> insert(String table, Map<String, Object?> row) async {
    _pending.add((table, row));
    if (_pending.length >= chunkSize) {
      await flush();
    }
  }

  /// Bulk insert of pre-built rows. The rows must be fully built before this
  /// call — never build rows with awaits inside a hot loop, see
  /// `_generateSleep` for details.
  Future<void> insertAll(String table, List<Map<String, Object?>> rows) async {
    for (final row in rows) {
      _pending.add((table, row));
    }
    if (_pending.length >= chunkSize) {
      await flush();
    }
  }

  Future<void> flush() async {
    if (_pending.isEmpty) return;
    final rows = List<(String, Map<String, Object?>)>.from(_pending);
    _pending.clear();
    await db.transaction((txn) async {
      for (final (table, row) in rows) {
        await txn.insert(table, row);
      }
    });
  }
}

class _Generator {
  final Database db;
  final Scenario s;
  final math.Random random;
  late final _ExercisePool pool;
  final DateTime endDate;
  late final DateTime startDate;
  final List<String> foodIds = [];
  final List<String> foodVariantIds = [];
  final List<String> routineIds = [];

  _Generator(this.db, this.s, this.random) : endDate = DateTime.now() {
    startDate = DateTime(endDate.year - s.years, endDate.month, endDate.day);
    pool = _ExercisePool(db, random);
  }

  Future<void> run() async {
    await pool.init();
    await _seedRoutines();
    await _generateWorkouts();
    await _generateSleep();
    await _generateNutrition();
    await _generateMeasurements();
    await _generateGoals();
    await _generateAiChats();
    await _generatePeriodization();
    await _generateExtraSettings();
  }

  // -- routines -------------------------------------------------------------

  Future<void> _seedRoutines() async {
    final w = _TxnWriter(db);
    const routines = ['Treino A - Empurrar', 'Treino B - Puxar', 'Treino C - Pernas'];
    for (final rName in routines) {
      final rId = _uuid.v4();
      await w.insert('routines', {
        'id': rId,
        'name': rName,
        'notes': null,
        'created_at': _iso(startDate),
      });
      routineIds.add(rId);
      final dayId = _uuid.v4();
      await w.insert('routine_days', {
        'id': dayId,
        'routine_id': rId,
        'name': 'Dia principal',
        'notes': null,
        'order_index': 0,
      });
      for (var order = 0; order < 5; order++) {
        final reId = _uuid.v4();
        await w.insert('routine_exercises', {
          'id': reId,
          'routine_day_id': dayId,
          'exercise_id': pool.randomId(),
          'order_index': order,
          'superset_group_id': null,
          'rest_time_seconds': 90,
        });
        final nSets = 3 + random.nextInt(2);
        for (var i = 0; i < nSets; i++) {
          await w.insert('predefined_sets', {
            'id': _uuid.v4(),
            'routine_exercise_id': reId,
            'weight': i == 0 ? 40.0 : 60.0,
            'reps': 10,
            'distance': null,
            'time_seconds': null,
            'is_warmup': i == 0 ? 1 : 0,
            'order_index': i,
          });
        }
      }
    }
    await w.flush();
  }

  // -- workouts -------------------------------------------------------------

  Future<void> _generateWorkouts() async {
    final targetPerYear = s.workoutsPerWeek * 52;
    final totalTarget = (targetPerYear * s.years).round();
    final w = _TxnWriter(db);

    var day = startDate;
    final end = endDate;
    var generated = 0;
    while (day.isBefore(end) && generated < totalTarget + 60) {
      var weekSessions =
          (s.workoutsPerWeek + (random.nextDouble() * 2 - 1)).round();
      weekSessions = _clampInt(weekSessions, 1, (s.workoutsPerWeek + 2).round());
      if (random.nextDouble() < 0.03) weekSessions = 0; // vacation week
      final used = <int>{};
      for (var i = 0; i < weekSessions; i++) {
        int wd;
        do {
          wd = random.nextInt(7);
        } while (used.contains(wd));
        used.add(wd);
        final date = day.add(Duration(days: wd));
        if (date.isAfter(end)) break;
        await _insertWorkout(w, date, generated);
        generated++;
      }
      day = day.add(const Duration(days: 7));
    }
    await w.flush();
  }

  Future<void> _insertWorkout(_TxnWriter w, DateTime date, int idx) async {
    final workoutId = _uuid.v4();
    final startTime = DateTime(date.year, date.month, date.day, 18, 0);
    final duration = 45 + random.nextInt(40);
    final endTime = startTime.add(Duration(minutes: duration));
    final ageYears = date.difference(startDate).inDays / 365.25;
    final progressFactor = 1 + 0.12 * ageYears;

    await w.insert('workouts', {
      'id': workoutId,
      'date': _dateStr(date),
      'start_time': _iso(startTime),
      'end_time': _iso(endTime),
      'duration_seconds': duration * 60,
      'estimated_calories': _round2(250 + random.nextDouble() * 250),
      'comment': random.nextDouble() < 0.25 ? 'Treino bom, foco total' : null,
      'feeling_rating': 3 + random.nextInt(3),
      'is_from_routine': random.nextDouble() < 0.6 ? 1 : 0,
      'routine_id': random.nextDouble() < 0.6
          ? routineIds[random.nextInt(routineIds.length)]
          : null,
      'pause_start_time': null,
      'created_at': _iso(startTime),
    });

    final nExercises = _clampInt(
      (s.exercisesPerWorkout + (random.nextDouble() * 2 - 1) * 2).round(),
      3,
      12,
    );
    final usedExercises = <String>{};
    for (var e = 0; e < nExercises; e++) {
      String exId;
      do {
        exId = pool.randomId();
      } while (usedExercises.contains(exId) && usedExercises.length < 10);
      usedExercises.add(exId);

      final entryId = _uuid.v4();
      await w.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exId,
        'order_index': e,
        'superset_group_id': null,
        'notes': null,
        'rest_time_seconds': 90,
      });

      final nSets = _clampInt(
        (s.setsPerExercise + (random.nextDouble() * 2 - 1) * 1.2).round(),
        1,
        8,
      );
      final baseWeight = (20 + (idx % 7) * 12.5) * progressFactor;
      final isDeload = random.nextDouble() < 0.08;
      for (var setIdx = 0; setIdx < nSets; setIdx++) {
        final isWarmup = setIdx == 0 && random.nextDouble() < 0.35;
        final weight = isDeload
            ? baseWeight * 0.7
            : baseWeight * (1 + setIdx * 0.05);
        await w.insert('sets', {
          'id': _uuid.v4(),
          'exercise_entry_id': entryId,
          'weight': isWarmup ? _round2(weight * 0.5) : _round2(weight),
          'reps': isWarmup ? 8 + random.nextInt(4) : 8 + random.nextInt(7),
          'distance': null,
          'time_seconds': null,
          'is_complete': 1,
          'is_warmup': isWarmup ? 1 : 0,
          'rpe': random.nextDouble() < 0.5
              ? (6 + random.nextDouble() * 3).toStringAsFixed(1)
              : null,
          'comment': null,
          'order_index': setIdx,
        });
      }
    }
  }

  // -- sleep ----------------------------------------------------------------
  //
  // Since v39 the app only persists the nightly summary: segments and stage
  // epochs are transient calculation material consumed during import, so the
  // generator writes only sleep_entries + sleep_monitor_sessions (with the
  // aggregates the analysis used to produce).

  Future<void> _generateSleep() async {
    final w = _TxnWriter(db, chunkSize: 600);
    final days = DateTime(endDate.year, endDate.month, endDate.day)
        .difference(DateTime(startDate.year, startDate.month, startDate.day))
        .inDays;

    for (var i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      if (random.nextDouble() >= s.sleepManualShare) continue;

      final sleepMinutes = 360 + random.nextInt(150);
      final bedtime = (22 * 60) + random.nextInt(120);
      final wakeTime = bedtime + sleepMinutes;
      final entryId = _uuid.v4();
      await w.insert('sleep_entries', {
        'id': entryId,
        'date': _dateStr(date),
        'sleep_minutes': sleepMinutes,
        'actual_sleep_minutes': (sleepMinutes * 0.9).round(),
        'bedtime_minutes': bedtime % 1440,
        'wake_time_minutes': wakeTime % 1440,
        'comment': random.nextDouble() < 0.1 ? 'Dormi um pouco tarde' : null,
        'source': 'manual',
        'time_in_bed_minutes': (sleepMinutes * 1.05).round(),
        'estimated_sleep_minutes': null,
        'created_at': _iso(date.add(const Duration(hours: 8))),
      });

      if (random.nextDouble() >= s.monitorShare) continue;

      final sessionId = _uuid.v4();
      final startedAt = DateTime.utc(
        date.year,
        date.month,
        date.day,
        23,
        random.nextInt(60),
      );
      final totalMinutes =
          s.monitorAvgMinutes + (random.nextDouble() * 60 - 30).round();
      await w.insert('sleep_monitor_sessions', {
        'id': sessionId,
        'sleep_entry_id': entryId,
        'status': 'completed',
        'started_at': _iso(startedAt),
        'ended_at': _iso(startedAt.add(Duration(minutes: totalMinutes))),
        'alarm_at': _iso(startedAt.add(const Duration(minutes: 450))),
        'monitor_mode': 'alarm_without_mission',
        'mission_type': null,
        'alarm_dismiss_method':
            random.nextDouble() < 0.7 ? 'snoozed' : 'dismissed',
        'alarm_dismissed_at': _iso(startedAt.add(const Duration(minutes: 455))),
        'utc_offset_start_minutes': -180,
        'utc_offset_end_minutes': -180,
        'sensor_mode': 'audio',
        'algorithm_version': '3.1.0',
        'time_in_bed_minutes': totalMinutes,
        'quiet_minutes': (totalMinutes * 0.85).round(),
        'noisy_minutes': (totalMinutes * 0.15).round(),
        'estimated_sleep_minutes': (totalMinutes * 0.92).round(),
        'noise_event_count': random.nextInt(30),
        'signal_quality_score': _round2(0.6 + random.nextDouble() * 0.35),
        'analysis_status': 'complete',
        'sleep_onset_at': _iso(startedAt.add(const Duration(minutes: 12))),
        'final_wake_at': _iso(startedAt.add(const Duration(minutes: 450))),
        'sleep_latency_minutes': 8 + random.nextInt(20),
        'awake_minutes': (totalMinutes * 0.08).round(),
        'sleeping_minutes': (totalMinutes * 0.92).round(),
        'deep_sleep_minutes': (totalMinutes * 0.2).round(),
        'unknown_minutes': random.nextInt(5),
        'awakening_count': random.nextInt(6),
        'sleep_efficiency': _round2(0.8 + random.nextDouble() * 0.15),
        'stage_confidence': _round2(0.75 + random.nextDouble() * 0.2),
        'stage_algorithm_version': '3.1.0',
        'end_reason': 'alarm',
        'created_at': _iso(startedAt),
      });
    }
    await w.flush();
  }

  // -- nutrition ------------------------------------------------------------

  Future<void> _generateNutrition() async {
    final w = _TxnWriter(db);
    final days = DateTime(endDate.year, endDate.month, endDate.day)
        .difference(DateTime(startDate.year, startDate.month, startDate.day))
        .inDays;
    var foodCounter = 0;
    final catalogCount = 120;
    final foodNames = <String>[
      'Arroz branco', 'Feijão preto', 'Frango grelhado', 'Ovo cozido',
      'Banana', 'Maçã', 'Aveia', 'Whey protein', 'Batata doce', 'Brócolis',
      'Iogurte natural', 'Pão integral', 'Café', 'Azeite', 'Amendoim',
      'Queijo minas', 'Carne moída', 'Salmão', 'Atum', 'Abacate',
      'Mamão', 'Manga', 'Cenoura', 'Alface', 'Tomate', 'Peito de peru',
      'Leite desnatado', 'Tapioca', 'Granola', 'Castanhas', 'Suco de laranja',
      'Cuscuz', 'Farinha de mandioca', 'Café com leite', 'Pão francês',
    ];

    Future<void> addFood() async {
      final name = foodNames[foodCounter % foodNames.length];
      foodCounter++;
      final foodId = _uuid.v4();
      await w.insert('foods', {
        'id': foodId,
        'source': 'off',
        'external_id': 'off_$foodCounter',
        'name': name,
        'search_name': name.toLowerCase(),
        'brand': random.nextDouble() < 0.3 ? 'Marca genérica' : null,
        'barcode': random.nextDouble() < 0.5
            ? '789${1000000000 + foodCounter}'
            : null,
        'source_url': null,
        'fetched_at': _iso(startDate),
        'last_used_at': null,
        'is_favorite': random.nextDouble() < 0.1 ? 1 : 0,
      });
      final variantId = _uuid.v4();
      await w.insert('food_variants', {
        'id': variantId,
        'food_id': foodId,
        'label': 'Padrão',
        'reference_amount': 100,
        'reference_unit': 'g',
        'calories': (50 + random.nextInt(300)).toDouble(),
        'protein_g': _round2(random.nextDouble() * 25),
        'carbs_g': _round2(random.nextDouble() * 60),
        'fat_g': _round2(random.nextDouble() * 25),
        'saturated_fat_g': _round2(random.nextDouble() * 8),
        'monounsaturated_fat_g': _round2(random.nextDouble() * 6),
        'polyunsaturated_fat_g': _round2(random.nextDouble() * 6),
        'trans_fat_g': _round2(random.nextDouble()),
        'fiber_g': _round2(random.nextDouble() * 8),
        'sugars_g': _round2(random.nextDouble() * 12),
        'sodium_mg': (100 + random.nextInt(800)).toDouble(),
        'potassium_mg': (50 + random.nextInt(600)).toDouble(),
        'calcium_mg': (10 + random.nextInt(200)).toDouble(),
        'iron_mg': _round2(random.nextDouble() * 5),
        'magnesium_mg': (5 + random.nextInt(80)).toDouble(),
        'zinc_mg': _round2(random.nextDouble() * 4),
        'vitamin_a_ug': (0 + random.nextInt(300)).toDouble(),
        'vitamin_c_mg': _round2(random.nextDouble() * 40),
        'vitamin_d_ug': _round2(random.nextDouble()),
        'vitamin_b12_ug': _round2(random.nextDouble() * 2),
        'extra_nutrients_json': null,
        'is_estimated': random.nextDouble() < 0.2 ? 1 : 0,
      });
      foodIds.add(foodId);
      foodVariantIds.add(variantId);
      await w.insert('food_servings', {
        'id': _uuid.v4(),
        'food_variant_id': variantId,
        'label': '100 g',
        'quantity': 1,
        'unit': 'g',
        'grams_equivalent': 100,
        'ml_equivalent': null,
      });
      await w.insert('food_servings', {
        'id': _uuid.v4(),
        'food_variant_id': variantId,
        'label': '1 porção',
        'quantity': 1,
        'unit': 'porção',
        'grams_equivalent': 120,
        'ml_equivalent': null,
      });
    }

    while (foodIds.length < catalogCount) {
      await addFood();
    }

    var loggedDays = 0;
    for (var i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      if (random.nextDouble() > s.nutritionDaysPerWeek / 7) continue;
      loggedDays++;
      final neededFoods = catalogCount + (loggedDays * s.newFoodsPerDay).round();
      while (foodIds.length < neededFoods) {
        await addFood();
      }

      final nMeals = _clampInt(s.mealsPerDay.round(), 1, 4);
      for (var m = 0; m < nMeals; m++) {
        final mealLogId = _uuid.v4();
        await w.insert('meal_logs', {
          'id': mealLogId,
          'date': _dateStr(date),
          'meal_type': _mealTypes[m],
          'name': null,
          'notes': null,
          'created_at': _iso(date),
        });
        final nItems = _clampInt(s.itemsPerMeal.round(), 1, 5);
        for (var it = 0; it < nItems; it++) {
          final idx = random.nextInt(foodVariantIds.length);
          final variantId = foodVariantIds[idx];
          final foodId = foodIds[idx];
          final calories = 40 + random.nextInt(350);
          final protein = _round2(random.nextDouble() * 30);
          final carbs = _round2(random.nextDouble() * 50);
          final fat = _round2(random.nextDouble() * 20);
          final snapshot = jsonEncode({
            'calories': calories,
            'protein_g': protein,
            'carbs_g': carbs,
            'fat_g': fat,
            'saturated_fat_g': _round2(fat * 0.3),
            'monounsaturated_fat_g': _round2(fat * 0.4),
            'polyunsaturated_fat_g': _round2(fat * 0.3),
            'trans_fat_g': 0,
            'fiber_g': _round2(random.nextDouble() * 5),
            'sugars_g': _round2(random.nextDouble() * 8),
            'sodium_mg': (100 + random.nextInt(600)).toDouble(),
            'potassium_mg': (50 + random.nextInt(400)).toDouble(),
            'calcium_mg': (10 + random.nextInt(150)).toDouble(),
            'iron_mg': _round2(random.nextDouble() * 3),
            'magnesium_mg': (5 + random.nextInt(60)).toDouble(),
            'zinc_mg': _round2(random.nextDouble() * 2),
            'vitamin_a_ug': (0 + random.nextInt(200)).toDouble(),
            'vitamin_c_mg': _round2(random.nextDouble() * 30),
            'vitamin_d_ug': _round2(random.nextDouble()),
            'vitamin_b12_ug': _round2(random.nextDouble()),
            'quantity': _round2(0.5 + random.nextDouble() * 3),
            'unit': 'g',
            'has_missing_values': false,
          });
          await w.insert('meal_log_items', {
            'id': _uuid.v4(),
            'meal_log_id': mealLogId,
            'food_id': foodId,
            'food_variant_id': variantId,
            'food_name_snapshot': 'Alimento ${idx + 1}',
            'brand_snapshot': null,
            'quantity': _round2(0.5 + random.nextDouble() * 3),
            'unit': 'g',
            'calories': calories.toDouble(),
            'protein_g': protein,
            'carbs_g': carbs,
            'fat_g': fat,
            'saturated_fat_g': _round2(fat * 0.3),
            'monounsaturated_fat_g': _round2(fat * 0.4),
            'polyunsaturated_fat_g': _round2(fat * 0.3),
            'trans_fat_g': 0,
            'fiber_g': _round2(random.nextDouble() * 5),
            'sugars_g': _round2(random.nextDouble() * 8),
            'sodium_mg': (100 + random.nextInt(600)).toDouble(),
            'potassium_mg': (50 + random.nextInt(400)).toDouble(),
            'calcium_mg': (10 + random.nextInt(150)).toDouble(),
            'iron_mg': _round2(random.nextDouble() * 3),
            'magnesium_mg': (5 + random.nextInt(60)).toDouble(),
            'zinc_mg': _round2(random.nextDouble() * 2),
            'vitamin_a_ug': (0 + random.nextInt(200)).toDouble(),
            'vitamin_c_mg': _round2(random.nextDouble() * 30),
            'vitamin_d_ug': _round2(random.nextDouble()),
            'vitamin_b12_ug': _round2(random.nextDouble()),
            'nutrition_snapshot_json': snapshot,
            'created_at': _iso(date),
          });
        }
      }
    }
    await w.flush();
  }

  // -- body measurements -----------------------------------------------------

  Future<void> _generateMeasurements() async {
    final w = _TxnWriter(db);
    final total = (s.measurementsPerMonth * 12 * s.years).round();
    final types = ['weight', 'waist', 'chest', 'arm_left', 'arm_right'];
    var weight = 92.0;
    for (var i = 0; i < total; i++) {
      final date = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: ((i / total) * s.years * 365.25).round()));
      final type = types[i % types.length];
      if (type == 'weight') {
        weight = math.max(78.0, weight - 0.45 + (random.nextDouble() - 0.5));
      }
      final value = type == 'weight'
          ? _round2(weight)
          : _round2(30 + random.nextDouble() * 60);
      await w.insert('body_measurements', {
        'id': _uuid.v4(),
        'type': type,
        'value': value,
        'unit': type == 'weight' ? 'kg' : 'cm',
        'date': _dateStr(date),
        'comment': null,
        'time_of_day': 'morning',
        'is_fasted': random.nextDouble() < 0.7 ? 1 : 0,
        'photos_paths': null,
        'side': type.contains('arm') ? 'left' : null,
        'created_at': _iso(date),
      });
    }
    await w.flush();
  }

  // -- goals ----------------------------------------------------------------

  Future<void> _generateGoals() async {
    final w = _TxnWriter(db);
    final nowIso = _iso(endDate);
    await w.insert('user_goals', {
      'id': _uuid.v4(),
      'title': 'Perder gordura corporal',
      'scope': 'body',
      'metric': 'body_fat',
      'period': 'weekly',
      'target_value': 15,
      'created_at': nowIso,
      'is_active': 1,
      'color': 4280391411,
    });
    await w.insert('user_goals', {
      'id': _uuid.v4(),
      'title': 'Aumentar volume semanal',
      'scope': 'workout',
      'metric': 'volume',
      'period': 'weekly',
      'target_value': 30000,
      'created_at': nowIso,
      'is_active': 1,
      'color': 4283215696,
    });
    await w.insert('user_goals', {
      'id': _uuid.v4(),
      'title': 'Dormir 8h por noite',
      'scope': 'sleep',
      'metric': 'sleep_minutes',
      'period': 'daily',
      'target_value': 480,
      'created_at': nowIso,
      'is_active': 1,
      'color': 4288319086,
    });
    await w.flush();
  }

  // -- AI chat ---------------------------------------------------------------

  Future<void> _generateAiChats() async {
    final w = _TxnWriter(db);
    final weeks = s.years * 52;
    final totalChats = (s.aiChatsPerWeek * weeks).round();
    for (var c = 0; c < totalChats; c++) {
      final threadId = _uuid.v4();
      final threadDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: ((c / totalChats) * s.years * 365.25).round()));
      final nMessages = s.chatMessagesPerConv;
      await w.insert('ai_chat_threads', {
        'id': threadId,
        'title': c % 5 == 0 ? 'Ajuste de treino' : 'Dúvida sobre progresso',
        'created_at': _iso(threadDate),
        'updated_at': _iso(threadDate.add(const Duration(hours: 1))),
        'last_message_preview': 'Entendi! Vamos ajustar o volume...',
        'archived': c % 20 == 0 ? 1 : 0,
        'is_pinned': c % 50 == 0 ? 1 : 0,
      });
      for (var m = 0; m < nMessages; m++) {
        final isUser = m % 2 == 0;
        final hasToolCall = !isUser && m % 3 == 0;
        await w.insert('ai_chat_messages', {
          'id': _uuid.v4(),
          'thread_id': threadId,
          'role': isUser ? 'user' : 'assistant',
          'content': isUser
              ? 'Quanto evoluiu meu supino nos últimos 3 meses?'
              : hasToolCall
                  ? null
                  : 'Seu supino evoluiu X% nas últimas 12 semanas. Os dados mostram progressão consistente de carga.',
          'tool_call_id': hasToolCall ? _uuid.v4() : null,
          'tool_name': hasToolCall ? 'get_exercise_history' : null,
          'tool_calls_json': hasToolCall
              ? jsonEncode([
                  {
                    'id': _uuid.v4(),
                    'type': 'function',
                    'function': {
                      'name': 'get_exercise_history',
                      'arguments': '{"exercise_id":"ex1"}',
                    },
                  },
                ])
              : null,
          'attachments_json': null,
          'created_at': _iso(threadDate.add(Duration(minutes: m * 4))),
        });
        if (hasToolCall && m + 1 < nMessages) {
          await w.insert('ai_chat_messages', {
            'id': _uuid.v4(),
            'thread_id': threadId,
            'role': 'tool',
            'content': '{"ok":true,"data":{"max_weight":120,"sessions":42}}',
            'tool_call_id': null,
            'tool_name': null,
            'tool_calls_json': null,
            'attachments_json': null,
            'created_at': _iso(threadDate.add(Duration(minutes: m * 4 + 1))),
          });
        }
      }
    }
    await w.flush();
  }

  // -- periodization ---------------------------------------------------------

  Future<void> _generatePeriodization() async {
    final w = _TxnWriter(db);
    final totalPlans = s.periodizationPlansPerYear * s.years;
    for (var p = 0; p < totalPlans; p++) {
      final planId = _uuid.v4();
      final planStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: (p / totalPlans * s.years * 365.25).round()));
      final planEnd = planStart.add(const Duration(days: 120));
      final nowIso = _iso(planStart);
      await w.insert('periodization_plans', {
        'id': planId,
        'name': 'Plano ${p + 1} - Hipertrofia',
        'start_date': _dateStr(planStart),
        'end_date': _dateStr(planEnd),
        'status': p == totalPlans - 1 ? 'active' : 'completed',
        'notes': 'Foco em volume',
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      for (var ph = 0; ph < 4; ph++) {
        final phaseId = _uuid.v4();
        final phaseStart = planStart.add(Duration(days: ph * 30));
        final phaseEnd = phaseStart.add(const Duration(days: 30));
        await w.insert('periodization_phases', {
          'id': phaseId,
          'plan_id': planId,
          'name': 'Fase ${ph + 1}',
          'template_key': 'hypertrophy',
          'color': 4280391411 + ph,
          'start_date': _dateStr(phaseStart),
          'end_date': _dateStr(phaseEnd),
          'intent': 'volume',
          'order_index': ph,
          'created_at': _iso(phaseStart),
          'updated_at': _iso(phaseStart),
        });
        await w.insert('phase_targets', {
          'id': _uuid.v4(),
          'phase_id': phaseId,
          'nutrition_json': jsonEncode({'calories': 2500, 'protein_g': 180}),
          'training_json': jsonEncode({
            'weekly_volume': 30000,
            'days_per_week': 4,
          }),
          'body_json': jsonEncode({'weight': 84}),
          'sleep_json': jsonEncode({'sleep_minutes': 480}),
          'version': 1,
          'valid_from': _dateStr(phaseStart),
          'created_at': _iso(phaseStart),
        });
        if (routineIds.isNotEmpty) {
          await w.insert('phase_routine_links', {
            'id': _uuid.v4(),
            'phase_id': phaseId,
            'routine_id': routineIds[p % routineIds.length],
            'starts_on': _dateStr(phaseStart),
            'ends_on': _dateStr(phaseEnd),
            'created_at': _iso(phaseStart),
          });
        }
        for (var wk = 0; wk < 4; wk++) {
          final weekStart = phaseStart.add(Duration(days: wk * 7));
          if (weekStart.isAfter(endDate)) break;
          await w.insert('periodization_checkins', {
            'id': _uuid.v4(),
            'phase_id': phaseId,
            'week_start': _dateStr(weekStart),
            'energy': 3 + random.nextInt(3),
            'hunger': 3 + random.nextInt(3),
            'recovery': 3 + random.nextInt(3),
            'performance': 'estável',
            'decision': 'manter',
            'notes': random.nextDouble() < 0.2 ? 'Semana puxada no trabalho' : null,
            'metrics_json': jsonEncode({
              'weight': _round2(80 + random.nextDouble() * 5),
              'waist': _round2(85 + random.nextDouble() * 5),
            }),
            'targets_snapshot_json': jsonEncode({
              'calories': 2500,
              'protein_g': 180,
            }),
            'created_at': _iso(weekStart),
          });
        }
      }
    }
    await w.flush();
  }

  Future<void> _generateExtraSettings() async {
    await db.insert('app_settings', {
      'key': 'last_backup_at',
      'value': _iso(endDate),
    });
  }
}

// ---------------------------------------------------------------------------
// Measurements
// ---------------------------------------------------------------------------

Future<Map<String, int>> _rowCounts(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  final counts = <String, int>{};
  for (final row in tables) {
    final name = row['name'] as String;
    final c = await db.rawQuery('SELECT COUNT(*) c FROM "$name"');
    counts[name] = Sqflite.firstIntValue(c) ?? 0;
  }
  return counts;
}

Future<Map<String, int>> _tableBytes(Database db) async {
  try {
    final rows = await db.rawQuery(
      "SELECT name, SUM(pgsize) AS bytes FROM dbstat WHERE aggregate=TRUE GROUP BY name",
    );
    return {
      for (final r in rows) r['name'] as String: (r['bytes'] as int?) ?? 0,
    };
  } catch (_) {
    return {};
  }
}

String _fmtBytes(int bytes) {
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _fmtMs(Duration d) {
  final ms = d.inMicroseconds / 1000;
  if (ms >= 10000) return '${(ms / 1000).toStringAsFixed(1)} s';
  return '${ms.toStringAsFixed(0)} ms';
}

Future<Timed> _timed(Future<void> Function() fn) async {
  final sw = Stopwatch()..start();
  await fn();
  sw.stop();
  return Timed(sw.elapsed);
}

Future<String?> _mostUsedExercise(Database db) async {
  final rows = await db.rawQuery('''
    SELECT ee.exercise_id, COUNT(*) c
    FROM sets s JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
    GROUP BY ee.exercise_id ORDER BY c DESC LIMIT 1
  ''');
  return rows.isEmpty ? null : rows.first['exercise_id'] as String?;
}

Future<String?> _recentWorkout(Database db) async {
  final rows = await db.query(
    'workouts',
    columns: ['id'],
    orderBy: 'date DESC',
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['id'] as String?;
}

Future<String?> _biggestThread(Database db) async {
  final rows = await db.rawQuery('''
    SELECT thread_id, COUNT(*) c FROM ai_chat_messages
    GROUP BY thread_id ORDER BY c DESC LIMIT 1
  ''');
  return rows.isEmpty ? null : rows.first['thread_id'] as String?;
}

void main() {
  sqfliteFfiInit();

  final scenarios = <Scenario>[
    const Scenario(
      name: 'S1 Leve (1 ano)',
      years: 1,
      workoutsPerWeek: 2,
      exercisesPerWorkout: 5,
      setsPerExercise: 3,
      sleepManualShare: 0.82,
      monitorShare: 0.0,
      monitorAvgMinutes: 0,
      nutritionDaysPerWeek: 2,
      mealsPerDay: 3,
      itemsPerMeal: 2,
      newFoodsPerDay: 0.5,
      measurementsPerMonth: 1,
      aiChatsPerWeek: 1,
      chatMessagesPerConv: 5,
      periodizationPlansPerYear: 1,
    ),
    const Scenario(
      name: 'S2 Moderado (3 anos)',
      years: 3,
      workoutsPerWeek: 3,
      exercisesPerWorkout: 6,
      setsPerExercise: 3.5,
      sleepManualShare: 0.98,
      monitorShare: 0.25,
      monitorAvgMinutes: 390,
      nutritionDaysPerWeek: 5,
      mealsPerDay: 3,
      itemsPerMeal: 2.5,
      newFoodsPerDay: 1,
      measurementsPerMonth: 2,
      aiChatsPerWeek: 3,
      chatMessagesPerConv: 6,
      periodizationPlansPerYear: 2,
    ),
    const Scenario(
      name: 'S3 Pesado (5 anos)',
      years: 5,
      workoutsPerWeek: 4.5,
      exercisesPerWorkout: 7,
      setsPerExercise: 3.5,
      sleepManualShare: 1.0,
      monitorShare: 0.55,
      monitorAvgMinutes: 420,
      nutritionDaysPerWeek: 6,
      mealsPerDay: 3.5,
      itemsPerMeal: 3,
      newFoodsPerDay: 2,
      measurementsPerMonth: 4.3,
      aiChatsPerWeek: 5,
      chatMessagesPerConv: 8,
      periodizationPlansPerYear: 2,
    ),
    const Scenario(
      name: 'S4 Extremo (10 anos)',
      years: 10,
      workoutsPerWeek: 6,
      exercisesPerWorkout: 7,
      setsPerExercise: 4,
      sleepManualShare: 1.0,
      monitorShare: 0.75,
      monitorAvgMinutes: 450,
      nutritionDaysPerWeek: 7,
      mealsPerDay: 4,
      itemsPerMeal: 3.5,
      newFoodsPerDay: 3,
      measurementsPerMonth: 6.5,
      aiChatsPerWeek: 7,
      chatMessagesPerConv: 10,
      periodizationPlansPerYear: 3,
    ),
  ];

  test(
    'Long-term storage study (multi-year simulation)',
    () async {
      final dir = Directory.systemTemp.createTempSync('wn_storage_study');
      final results = <ScenarioResult>[];

      for (final scenario in scenarios) {
        // ignore: avoid_print
        print(
          '\n═══════════════════════════════════════════════════════════\n'
          'GEN: ${scenario.name}',
        );

        final dbName = '${scenario.name.replaceAll(' ', '_')}.db';
        final db = await _openFreshDb(dir.path, dbName);
        DatabaseHelper.overrideDatabase = db;
        final generator = _Generator(
          db,
          scenario,
          math.Random(42 + scenario.years * 7),
        );
        final genSw = Stopwatch()..start();
        await generator.run();
        genSw.stop();
        final dbFile = File(p.join(dir.path, dbName));
        // ignore: avoid_print
        print(
          'GEN: done in ${_fmtMs(genSw.elapsed)} | '
          'size=${_fmtBytes(dbFile.lengthSync())}',
        );

        // ---- row counts & table bytes ----
        final counts = await _rowCounts(db);
        final bytes = await _tableBytes(db);

        // ---- representative queries (warm run first, then timed) ----
        final now = DateTime.now();
        final workoutRepo = WorkoutRepository();
        final analyticsRepo = AnalyticsRepository();
        final sleepRepo = SleepRepository();

        final mostUsedExercise = await _mostUsedExercise(db);
        final recentWorkout = await _recentWorkout(db);
        final biggestThread = await _biggestThread(db);
        final recentDay = _dateStr(now);

        Future<void> warmup() async {
          await workoutRepo.getWorkoutsByMonth(now.year, now.month);
          await workoutRepo.getWorkoutCategoriesByDate(now.year, now.month);
          if (mostUsedExercise != null) {
            await analyticsRepo.getExerciseHistory(mostUsedExercise);
          }
          await analyticsRepo.getWeeklyVolume(weeks: 4);
          await analyticsRepo.getAnaerobicVolumeByCategory(
            now.subtract(const Duration(days: 30)),
            now,
            bySets: false,
          );
          await analyticsRepo.getTopExercisesByVolume(limit: 10);
          if (recentWorkout != null) {
            await workoutRepo.getWorkout(recentWorkout);
            final entries = await workoutRepo.getWorkoutExercises(recentWorkout);
            for (final e in entries) {
              await workoutRepo.getExerciseSets(e['id'] as String);
            }
          }
          await sleepRepo.getDashboardStats();
        }

        await warmup();

        final queryTimes = <String, Timed>{};
        queryTimes['calendario (mes)'] = await _timed(() async {
          await workoutRepo.getWorkoutsByMonth(now.year, now.month);
        });
        queryTimes['calendario categorias (mes)'] = await _timed(() async {
          await workoutRepo.getWorkoutCategoriesByDate(now.year, now.month);
        });
        if (mostUsedExercise != null) {
          queryTimes['historico exercicio (todo periodo)'] = await _timed(
            () async {
              await analyticsRepo.getExerciseHistory(mostUsedExercise);
            },
          );
        }
        queryTimes['volume semanal (4 semanas)'] = await _timed(() async {
          await analyticsRepo.getWeeklyVolume(weeks: 4);
        });
        queryTimes['volume por categoria (30d)'] = await _timed(() async {
          await analyticsRepo.getAnaerobicVolumeByCategory(
            now.subtract(const Duration(days: 30)),
            now,
            bySets: false,
          );
        });
        queryTimes['top exercicios (all-time)'] = await _timed(() async {
          await analyticsRepo.getTopExercisesByVolume(limit: 10);
        });
        if (recentWorkout != null) {
          queryTimes['detalhe treino + sets'] = await _timed(() async {
            await workoutRepo.getWorkout(recentWorkout);
            final entries = await workoutRepo.getWorkoutExercises(recentWorkout);
            for (final e in entries) {
              await workoutRepo.getExerciseSets(e['id'] as String);
            }
          });
        }
        queryTimes['dashboard sono (30d)'] = await _timed(() async {
          await sleepRepo.getDashboardStats();
        });
        queryTimes['sessoes monitoradas recentes (20)'] = await _timed(() async {
          await db.query(
            'sleep_monitor_sessions',
            where: "status = 'completed'",
            orderBy: 'started_at DESC',
            limit: 20,
          );
        });
        queryTimes['nutricao: diario completo'] = await _timed(() async {
          final logs = await db.query(
            'meal_logs',
            where: 'date = ?',
            whereArgs: [recentDay],
          );
          for (final log in logs) {
            await db.query(
              'meal_log_items',
              where: 'meal_log_id = ?',
              whereArgs: [log['id']],
            );
          }
        });
        queryTimes['nutricao: resumo 30d macros'] = await _timed(() async {
          await db.rawQuery(
            '''
            SELECT SUM(calories) cals, SUM(protein_g) protein,
                   SUM(carbs_g) carbs, SUM(fat_g) fat
            FROM meal_log_items
            WHERE meal_log_id IN (
              SELECT id FROM meal_logs WHERE date >= ? AND date <= ?
            )
            ''',
            [_dateStr(now.subtract(const Duration(days: 30))), _dateStr(now)],
          );
        });
        if (biggestThread != null) {
          queryTimes['carregar thread IA'] = await _timed(() async {
            await db.query(
              'ai_chat_messages',
              where: 'thread_id = ?',
              whereArgs: [biggestThread],
              orderBy: 'created_at ASC',
            );
          });
        }

        // ---- export (exact app path: pretty-printed JSON) ----
        final exportRepo = ExportImportRepository();
        Map<String, dynamic> backupData = {};
        final exportDump = await _timed(() async {
          backupData = await exportRepo.exportAllData();
        });
        final prettySw = Stopwatch()..start();
        final prettyStr = const JsonEncoder.withIndent('  ').convert(backupData);
        final prettySize = utf8.encode(prettyStr).length;
        prettySw.stop();
        final compactSw = Stopwatch()..start();
        final compactSize = utf8.encode(jsonEncode(backupData)).length;
        compactSw.stop();

        // ---- restore into a fresh DB (real restoreFromBackup path) ----
        final restoreDbName =
            'restore_${scenario.name.replaceAll(' ', '_')}.db';
        final restoreDb = await _openFreshDb(dir.path, restoreDbName);
        DatabaseHelper.overrideDatabase = restoreDb;
        final restoreRepo = ExportImportRepository();
        var restoreRows = 0;
        final restoreTimed = await _timed(() async {
          restoreRows = await restoreRepo.restoreFromBackup(backupData);
        });
        final restoreDbFile = File(p.join(dir.path, restoreDbName));
        final restoreBytes = restoreDbFile.lengthSync();
        await restoreDb.close();
        DatabaseHelper.overrideDatabase = db;

        results.add(
          ScenarioResult(
            scenario: scenario,
            db: db,
            dbFile: dbFile,
            dbBytes: dbFile.lengthSync(),
            restoreDbBytes: restoreBytes,
            rowCounts: counts,
            tableBytes: bytes,
            exportPretty: Timed(exportDump.duration + prettySw.elapsed),
            exportCompact: Timed(compactSw.elapsed),
            exportPrettyBytes: prettySize,
            exportCompactBytes: compactSize,
            restore: restoreTimed,
            restoreRows: restoreRows,
            queryTimes: queryTimes,
          ),
        );
      }

      // -----------------------------------------------------------------
      // REPORT
      // -----------------------------------------------------------------
      for (final r in results) {
        final dbSize = r.dbBytes;
        final totalRows = r.rowCounts.values.fold(0, (a, b) => a + b);
        // ignore: avoid_print
        print(
          '\n'
          '──────────────────────────────────────────────────────────────\n'
          'RESULT: ${r.scenario.name} (${r.scenario.years} ano(s))\n'
          '──────────────────────────────────────────────────────────────\n'
          'Tamanho do arquivo .db ............ ${_fmtBytes(dbSize)}\n'
          'Linhas no banco ................... $totalRows\n'
          'Backup JSON pretty (formato do app) ${_fmtBytes(r.exportPrettyBytes)} '
          '(${_fmtMs(r.exportPretty.duration)})\n'
          'Backup JSON compacto .............. ${_fmtBytes(r.exportCompactBytes)} '
          '(${_fmtMs(r.exportCompact.duration)})\n'
          'Restore (import) .................. ${_fmtMs(r.restore.duration)} '
          'para ${r.restoreRows} linhas | db resultante=${_fmtBytes(r.restoreDbBytes)}\n'
          'Proporcao pretty/compacto ......... '
          '${(r.exportPrettyBytes / r.exportCompactBytes).toStringAsFixed(2)}x\n'
          'Proporcao json/db ................. '
          '${(r.exportPrettyBytes / dbSize).toStringAsFixed(2)}x\n',
        );

        final entries = r.tableBytes.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (r.tableBytes.isNotEmpty) {
          // ignore: avoid_print
          print('  Espaco por tabela (top 12, dbstat):');
          for (final e in entries.take(12)) {
            final pct = dbSize == 0 ? 0 : e.value * 100.0 / dbSize;
            // ignore: avoid_print
            print(
              '    ${e.key.padRight(28)} ${_fmtBytes(e.value).padLeft(10)}  '
              '${pct.toStringAsFixed(1).padLeft(5)}%  '
              '(${r.rowCounts[e.key] ?? 0} linhas)',
            );
          }
        } else {
          // ignore: avoid_print
          print('  (dbstat indisponivel; apenas contagem de linhas)');
          final countEntries = r.rowCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          for (final e in countEntries.take(12)) {
            // ignore: avoid_print
            print(
              '    ${e.key.padRight(28)} ${e.value.toString().padLeft(9)} linhas',
            );
          }
        }

        // ignore: avoid_print
        print('\n  Queries representativas (2a execucao, cache quente):');
        for (final q in r.queryTimes.entries) {
          // ignore: avoid_print
          print('    ${q.key.padRight(36)} ${_fmtMs(q.value.duration)}');
        }
        // ignore: avoid_print
        print('');
      }

      for (final r in results) {
        await r.db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
