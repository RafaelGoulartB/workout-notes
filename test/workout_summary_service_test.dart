import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations_en.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/services/workout_summary_service.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

final _loc = AppLocalizationsEn();

Map<String, dynamic> _set(
  double? weight,
  int? reps, {
  bool warmup = false,
  bool done = true,
  double? distance,
  int? time,
}) => {
  'weight': weight,
  'reps': reps,
  'distance': distance,
  'time_seconds': time,
  'is_warmup': warmup ? 1 : 0,
  'is_complete': done ? 1 : 0,
};

ExerciseWithSets _exercise(
  String id,
  List<Map<String, dynamic>> sets, {
  String category = 'chest',
}) => ExerciseWithSets(
  entryId: 'entry-$id',
  exerciseId: id,
  name: 'Ex $id',
  exerciseType: 'weightReps',
  categoryId: category,
  categoryName: category,
  categoryColor: Colors.red,
  sets: sets,
);

StrengthSetSample _past(
  String workout,
  DateTime date,
  String exercise,
  double weight,
  int reps,
) => StrengthSetSample(
  workoutId: workout,
  date: date,
  exerciseId: exercise,
  exerciseName: 'Ex $exercise',
  exerciseLocaleKey: null,
  categoryId: 'chest',
  weight: weight,
  reps: reps,
);

void main() {
  group('WorkoutSummaryService.totals', () {
    test('warm-ups count for nothing; volume only for completed sets', () {
      final totals = WorkoutSummaryService.totals([
        _exercise('bench', [
          _set(100, 5),
          _set(100, 5, done: false),
          _set(40, 10, warmup: true),
        ]),
        _exercise('row', [_set(60, 8)], category: 'back'),
      ], _loc);
      expect(totals.totalSets, 3);
      expect(totals.completedSets, 2);
      expect(totals.totalVolume, 500 + 480);
      expect(totals.totalDistance, 0);
      expect(totals.cardioByExercise, isEmpty);
    });

    test('distance and time of working sets feed the cardio totals', () {
      final totals = WorkoutSummaryService.totals([
        _exercise('run', [
          _set(null, null, distance: 5, time: 1500),
          _set(null, null, distance: 2, time: 600, done: false),
          _set(null, null, distance: 9, time: 900, warmup: true),
        ], category: 'cardio'),
      ], _loc);
      expect(totals.totalDistance, 7);
      expect(totals.totalCardioTime, 2100);
      final run = totals.cardioByExercise['run']!;
      expect(run.distance, 7);
      expect(run.timeSeconds, 2100);
      expect(run.name, 'Ex run');
    });
  });

  group('WorkoutSummaryService.strengthRecords', () {
    final earlier = DateTime(2026, 9, 1);
    final now = DateTime(2026, 9, 15);

    test('lists the records the session beat, with what they beat', () {
      final prs = WorkoutSummaryService.strengthRecords(
        loc: _loc,
        workoutId: 'today',
        exercises: [
          _exercise('bench', [_set(105, 5), _set(60, 10, warmup: true)]),
        ],
        cardioExerciseIds: const {},
        history: [
          _past('w1', earlier, 'bench', 100, 5),
          _past('w1', earlier, 'bench', 100, 5),
        ],
        now: now,
      );
      final byType = {for (final pr in prs) pr.type: pr};
      expect(byType.keys, containsAll(['e1rm', 'weight']));
      expect(byType['e1rm']!.exerciseName, 'Ex bench');
      expect(byType['e1rm']!.previous, isNotEmpty);
      // 105 x 5 is one set against two of 100 x 5: not a volume record.
      expect(byType.containsKey('volume'), isFalse);
    });

    test('a first session is a baseline, never a volume record', () {
      final prs = WorkoutSummaryService.strengthRecords(
        loc: _loc,
        workoutId: 'today',
        exercises: [
          _exercise('bench', [_set(100, 5)]),
        ],
        cardioExerciseIds: const {},
        history: const [],
        now: now,
      );
      expect(prs.where((p) => p.type == 'volume'), isEmpty);
    });

    test('cardio exercises and unfinished sets never make strength records', () {
      final prs = WorkoutSummaryService.strengthRecords(
        loc: _loc,
        workoutId: 'today',
        exercises: [
          _exercise('run', [_set(50, 5)], category: 'cardio'),
          _exercise('bench', [_set(300, 5, done: false)]),
        ],
        cardioExerciseIds: const {'run'},
        history: [_past('w1', earlier, 'bench', 100, 5)],
        now: now,
      );
      expect(prs, isEmpty);
    });

    test('the session being finished is not compared with itself', () {
      final prs = WorkoutSummaryService.strengthRecords(
        loc: _loc,
        workoutId: 'today',
        exercises: [
          _exercise('bench', [_set(100, 5)]),
        ],
        cardioExerciseIds: const {},
        // Already saved rows of this very workout must be ignored.
        history: [_past('today', earlier, 'bench', 100, 5)],
        now: now,
      );
      expect(prs.where((p) => p.type == 'volume'), isEmpty);
    });
  });

  group('WorkoutSummaryService.compute', () {
    late Database db;

    setUp(() async {
      db = await installAiTestDb();
      await seedStrengthBasics(db);
    });

    tearDown(uninstallAiTestDb);

    test('duration, calories and a longest-distance record', () async {
      await seedWorkout(db, 'old', date: '2026-09-01', exercises: const []);
      await db.insert('exercise_entries', {
        'id': 'old-run',
        'workout_id': 'old',
        'exercise_id': 'treadmill',
        'order_index': 0,
      });
      await db.insert('sets', {
        'id': 'old-run-s0',
        'exercise_entry_id': 'old-run',
        'distance': 4.0,
        'time_seconds': 1500,
        'is_complete': 1,
        'is_warmup': 0,
        'order_index': 0,
      });
      await db.insert('body_measurements', {
        'id': 'weight-1',
        'type': 'weight',
        'value': 75.0,
        'unit': 'kg',
        'date': '2026-09-14',
        'created_at': '2026-09-14T08:00:00.000',
      });
      await db.insert('workouts', {
        'id': 'today',
        'date': '2026-09-15',
        'created_at': '2026-09-15T10:00:00.000',
      });

      final start = DateTime(2026, 9, 15, 10);
      final summary = await WorkoutSummaryService().compute(
        loc: _loc,
        workoutId: 'today',
        exercises: [
          _exercise('treadmill', [
            _set(null, null, distance: 5, time: 1500),
          ], category: 'cardio'),
        ],
        cardioExerciseIds: const {'treadmill'},
        timerStart: start,
        timerEnd: start.add(const Duration(minutes: 40)),
        now: DateTime(2026, 9, 15, 11),
      );

      expect(summary.durationSeconds, 2400);
      expect(summary.totalDistance, 5);
      expect(summary.estimatedCalories, isNotNull);
      final distance = summary.prs.singleWhere((p) => p.type == 'distance');
      expect(distance.value, '5.0 km');
      expect(distance.previous, '4.0 km');
    });

    test('without a timer the planned duration feeds the calories', () async {
      final summary = await WorkoutSummaryService().compute(
        loc: _loc,
        workoutId: null,
        exercises: [
          _exercise('bench', [_set(100, 5), _set(100, 5)]),
        ],
        cardioExerciseIds: const {},
      );
      expect(summary.durationSeconds, 0);
      expect(summary.prs, isEmpty);
      expect(summary.totalSets, 2);
    });
  });
}
