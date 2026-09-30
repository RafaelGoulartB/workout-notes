import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/utils/workout_volume_comparison.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

Map<String, dynamic> _set(
  double? weight,
  int? reps, {
  bool warmup = false,
  bool done = false,
}) => {
  'weight': weight,
  'reps': reps,
  'is_warmup': warmup ? 1 : 0,
  'is_complete': done ? 1 : 0,
};

ExerciseWithSets _exercise(
  String id,
  List<Map<String, dynamic>> sets, {
  String category = 'chest',
  String type = 'weightReps',
}) => ExerciseWithSets(
  entryId: 'entry-$id',
  exerciseId: id,
  name: id,
  exerciseType: type,
  categoryId: category,
  categoryName: category,
  categoryColor: Colors.red,
  sets: sets,
);

void main() {
  group('WorkoutVolumeComparisons.compute', () {
    test('counts every working set with weight and reps, not warm-ups', () {
      final result = WorkoutVolumeComparisons.compute(
        [
          _exercise('bench', [
            _set(100, 5, done: true),
            _set(80, 5), // not done yet: still counted (planned volume)
            _set(40, 10, warmup: true, done: true),
            _set(null, 5),
          ]),
        ],
        {'bench': 700},
      );
      final bench = result.exercises['bench']!;
      expect(bench.currentVolume, 900);
      expect(bench.lastVolume, 700);
      expect(bench.delta, 200);
    });

    test('completing a set does not move the comparison', () {
      final exercise = _exercise('bench', [_set(100, 5), _set(100, 5)]);
      final before = WorkoutVolumeComparisons.compute([exercise], {});
      exercise.sets[0] = {...exercise.sets[0], 'is_complete': 1};
      final after = WorkoutVolumeComparisons.compute([exercise], {});
      expect(after.exercises['bench']!.currentVolume, 1000);
      expect(
        after.exercises['bench']!.currentVolume,
        before.exercises['bench']!.currentVolume,
      );
    });

    test('adding and deleting a set is reflected without a reload', () {
      final exercise = _exercise('bench', [_set(100, 5)]);
      exercise.sets.add(_set(100, 5));
      expect(
        WorkoutVolumeComparisons.compute([
          exercise,
        ], {}).exercises['bench']!.currentVolume,
        1000,
      );
      exercise.sets.removeAt(0);
      expect(
        WorkoutVolumeComparisons.compute([
          exercise,
        ], {}).exercises['bench']!.currentVolume,
        500,
      );
    });

    test('groups by muscle, most volume first, and skips other types', () {
      final result = WorkoutVolumeComparisons.compute(
        [
          _exercise('bench', [_set(100, 5)]),
          _exercise('fly', [_set(20, 10)]),
          _exercise('row', [_set(80, 10)], category: 'back'),
          _exercise('run', [_set(null, null)], type: 'distanceTime'),
        ],
        {'bench': 400, 'fly': 0, 'row': 1000},
      );
      expect(result.exercises.keys, containsAll(['bench', 'fly', 'row']));
      expect(result.exercises.containsKey('run'), isFalse);
      expect(result.categories.map((c) => c.categoryId), ['back', 'chest']);
      final chest = result.categories.last;
      expect(chest.currentVolume, 700);
      expect(chest.lastVolume, 400);
    });

    test('a category with nothing done and nothing before is left out', () {
      final result = WorkoutVolumeComparisons.compute([
        _exercise('bench', [_set(null, null)]),
      ], {});
      expect(result.categories, isEmpty);
    });
  });

  group('WorkoutRepository.getLastCompletedVolumes', () {
    late Database db;

    setUp(() async {
      db = await installAiTestDb();
      await seedStrengthBasics(db);
    });

    tearDown(uninstallAiTestDb);

    test('one query gives each exercise its last finished session', () async {
      await seedWorkout(
        db,
        'old',
        date: '2026-09-01',
        exercises: [
          (
            'bench',
            [
              seedSet(100, 5),
              seedSet(80, 5, done: false),
              seedSet(40, 10, warmup: true),
            ],
          ),
          ('row', [seedSet(60, 10)]),
        ],
      );
      await seedWorkout(
        db,
        'newer',
        date: '2026-09-08',
        exercises: [
          ('bench', [seedSet(110, 5)]),
        ],
      );
      // Not finished, so it is not a baseline.
      await seedWorkout(
        db,
        'draft',
        date: '2026-09-09',
        finished: false,
        exercises: [
          ('bench', [seedSet(200, 5)]),
        ],
      );
      await seedWorkout(
        db,
        'current',
        date: '2026-09-15',
        finished: false,
        exercises: [
          ('bench', [seedSet(120, 5)]),
          ('row', [seedSet(70, 8)]),
          ('treadmill', [seedSet(10, 1)]),
        ],
      );

      final volumes = await WorkoutRepository().getLastCompletedVolumes(
        'current',
      );

      // The newest finished session wins: 110 x 5.
      expect(volumes['bench'], 550);
      // Only in the older one; warm-up and undone sets do not count.
      expect(volumes['row'], 600);
      // Never done before: present with 0, so nothing is missing.
      expect(volumes['treadmill'], 0);
    });
  });
}
