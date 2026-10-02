import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

import 'support/sql_capture.dart';
import 'support/test_db.dart';

const _now = '2026-08-01T08:00:00.000';

void main() {
  late Database db;
  late SqlLog sqlLog;
  late WorkoutRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    (db, sqlLog) = await installCountingTestDb();
    repo = WorkoutRepository();
    await db.insert('exercise_categories', {
      'id': 'strength',
      'name': 'Strength',
      'color': 1,
    });
    for (final id in ['bench', 'squat', 'row']) {
      await db.insert('exercises', {
        'id': id,
        'name': id,
        'category_id': 'strength',
        'created_at': _now,
      });
    }
  });

  tearDown(uninstallTestDb);

  Future<int> count(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  Future<void> seedRoutine() async {
    await db.insert('routines', {
      'id': 'routine',
      'name': 'Push',
      'created_at': _now,
    });
    await db.insert('routine_days', {
      'id': 'day',
      'routine_id': 'routine',
      'name': 'Day A',
      'order_index': 0,
    });
    for (var i = 0; i < 2; i++) {
      final id = 're$i';
      await db.insert('routine_exercises', {
        'id': id,
        'routine_day_id': 'day',
        'exercise_id': i == 0 ? 'bench' : 'squat',
        'order_index': i,
        'rest_time_seconds': 120,
      });
      for (var j = 0; j < 3; j++) {
        await db.insert('predefined_sets', {
          'id': 'ps$i$j',
          'routine_exercise_id': id,
          'weight': 50.0 + j,
          'reps': 8,
          'order_index': j,
        });
      }
    }
  }

  group('createWorkout', () {
    test('writes the workout, entries and sets in one transaction', () async {
      final id = await repo.createWorkout(
        date: DateTime(2026, 8, 1),
        exercises: [
          {
            'exercise_id': 'bench',
            'sets': [
              {'weight': 60.0, 'reps': 10},
              {'weight': 65.0, 'reps': 8, 'is_warmup': 1},
            ],
          },
          {
            'exercise_id': 'squat',
            'sets': [
              {'weight': 100.0, 'reps': 5},
            ],
          },
        ],
      );

      expect(await count('workouts'), 1);
      final entries = await db.query(
        'exercise_entries',
        orderBy: 'order_index',
      );
      expect(entries.map((e) => e['exercise_id']), ['bench', 'squat']);
      expect(entries.every((e) => e['workout_id'] == id), isTrue);
      final sets = await db.query('sets', orderBy: 'order_index');
      expect(sets, hasLength(3));
      expect(sets.every((s) => s['is_complete'] == 0), isTrue);
      expect(sets.where((s) => s['is_warmup'] == 1), hasLength(1));
    });

    test('a failure leaves no partial workout behind', () async {
      await expectLater(
        repo.createWorkout(
          exercises: [
            {'exercise_id': 'bench', 'sets': <Map<String, dynamic>>[]},
            {
              'exercise_id': 'missing-exercise',
              'sets': <Map<String, dynamic>>[],
            },
          ],
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await count('workouts'), 0);
      expect(await count('exercise_entries'), 0);
    });

    test('fills the routine from the day and keeps the link', () async {
      await seedRoutine();
      final id = await repo.createWorkout(routineDayId: 'day');

      final workout = (await db.query(
        'workouts',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(workout['routine_id'], 'routine');
      expect(workout['routine_day_id'], 'day');
      expect(workout['is_from_routine'], 1);
    });

    test('uses a bounded number of round trips', () async {
      sqlLog.clear();
      await repo.createWorkout(
        exercises: [
          for (var i = 0; i < 5; i++)
            {
              'exercise_id': 'bench',
              'sets': [
                for (var j = 0; j < 4; j++) {'weight': 50.0, 'reps': 10},
              ],
            },
        ],
      );
      // One batch for 1 workout + 5 entries + 20 sets.
      expect(sqlLog.statements.where((s) => s.startsWith('batch(')), [
        'batch(26)',
      ]);
      expect(sqlLog.total, lessThanOrEqualTo(2));
    });
  });

  group('importRoutineDayToWorkout', () {
    test('adds entries after existing ones with the preset sets', () async {
      await seedRoutine();
      final id = await repo.createWorkout(
        exercises: [
          {'exercise_id': 'row', 'sets': <Map<String, dynamic>>[]},
        ],
      );

      await repo.importRoutineDayToWorkout(id, 'day');

      final entries = await db.query(
        'exercise_entries',
        where: 'workout_id = ?',
        whereArgs: [id],
        orderBy: 'order_index',
      );
      expect(entries.map((e) => e['exercise_id']), ['row', 'bench', 'squat']);
      expect(entries.map((e) => e['order_index']), [0, 1, 2]);
      expect(entries[1]['rest_time_seconds'], 120);
      final benchSets = await db.query(
        'sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [entries[1]['id']],
        orderBy: 'order_index',
      );
      expect(benchSets.map((s) => s['weight']), [50.0, 51.0, 52.0]);
      final workout = (await db.query(
        'workouts',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(workout['routine_day_id'], 'day');
      expect(workout['is_from_routine'], 1);
    });

    test('prefers the sets of the last session over presets', () async {
      await seedRoutine();
      final previous = await repo.createWorkout(
        date: DateTime(2026, 7, 1),
        exercises: [
          {
            'exercise_id': 'bench',
            'sets': [
              {'weight': 80.0, 'reps': 5},
            ],
          },
        ],
      );
      final today = await repo.createWorkout(date: DateTime(2026, 8, 1));

      await repo.importRoutineDayToWorkout(today, 'day');

      final entry = (await db.query(
        'exercise_entries',
        where: 'workout_id = ? AND exercise_id = ?',
        whereArgs: [today, 'bench'],
      )).single;
      final sets = await db.query(
        'sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [entry['id']],
      );
      expect(sets.map((s) => s['weight']), [80.0]);
      expect(previous, isNot(today));
    });

    test('rolls back entirely when the day cannot be imported', () async {
      await seedRoutine();
      final id = await repo.createWorkout();
      // Remove a referenced exercise between reading and writing is not
      // possible here, so break the workout id instead.
      await expectLater(
        repo.importRoutineDayToWorkout('no-such-workout', 'day'),
        throwsA(isA<DatabaseException>()),
      );
      expect(await count('exercise_entries'), 0);
      expect(id, isNotEmpty);
    });
  });

  group('addExerciseToWorkout', () {
    test('appends an entry pre-filled from the last session', () async {
      await repo.createWorkout(
        date: DateTime(2026, 7, 1),
        exercises: [
          {
            'exercise_id': 'bench',
            'sets': [
              {'weight': 70.0, 'reps': 6},
              {'weight': 72.5, 'reps': 5},
            ],
          },
        ],
      );
      final today = await repo.createWorkout(date: DateTime(2026, 8, 1));

      sqlLog.clear();
      final entryId = await repo.addExerciseToWorkout(today, 'bench');

      final entry = (await db.query(
        'exercise_entries',
        where: 'id = ?',
        whereArgs: [entryId],
      )).single;
      expect(entry['order_index'], 0);
      expect(entry['rest_time_seconds'], 90);
      final sets = await db.query(
        'sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [entryId],
        orderBy: 'order_index',
      );
      expect(sets.map((s) => s['weight']), [70.0, 72.5]);
      expect(sets.every((s) => s['is_complete'] == 0), isTrue);
    });
  });

  group('copyWorkoutToDate', () {
    test('copies entries and sets unchecked to the new date', () async {
      final source = await repo.createWorkout(
        date: DateTime(2026, 7, 1),
        routineId: null,
        exercises: [
          {
            'exercise_id': 'bench',
            'notes': 'slow negatives',
            'sets': [
              {'weight': 60.0, 'reps': 10, 'rpe': 7.5, 'comment': 'easy'},
              {'weight': 65.0, 'reps': 8},
            ],
          },
          {
            'exercise_id': 'row',
            'sets': [
              {'weight': 50.0, 'reps': 12},
            ],
          },
        ],
      );
      await db.update('sets', {'is_complete': 1});

      final copyId = await repo.copyWorkoutToDate(source, DateTime(2026, 8, 5));

      final copy = (await db.query(
        'workouts',
        where: 'id = ?',
        whereArgs: [copyId],
      )).single;
      expect(copy['date'], '2026-08-05');
      expect(copy['end_time'], isNull);
      final entries = await db.query(
        'exercise_entries',
        where: 'workout_id = ?',
        whereArgs: [copyId],
        orderBy: 'order_index',
      );
      expect(entries.map((e) => e['exercise_id']), ['bench', 'row']);
      expect(entries.first['notes'], 'slow negatives');
      final sets = await db.rawQuery(
        'SELECT s.* FROM sets s JOIN exercise_entries ee '
        'ON ee.id = s.exercise_entry_id WHERE ee.workout_id = ? '
        'ORDER BY ee.order_index, s.order_index',
        [copyId],
      );
      expect(sets.map((s) => s['weight']), [60.0, 65.0, 50.0]);
      expect(sets.every((s) => s['is_complete'] == 0), isTrue);
      expect(sets.first['rpe'], 7.5);
      expect(sets.first['comment'], 'easy');
      // The source is untouched.
      expect(await count('sets'), 6);
    });

    test('copying a missing workout writes nothing', () async {
      await expectLater(
        repo.copyWorkoutToDate('missing', DateTime(2026, 8, 5)),
        throwsA(isA<Exception>()),
      );
      expect(await count('workouts'), 0);
    });

    test('reads sets for every entry with one query', () async {
      final source = await repo.createWorkout(
        exercises: [
          for (var i = 0; i < 6; i++)
            {
              'exercise_id': 'bench',
              'sets': [
                {'weight': 50.0, 'reps': 10},
              ],
            },
        ],
      );

      sqlLog.clear();
      await repo.copyWorkoutToDate(source, DateTime(2026, 8, 5));

      expect(sqlLog.reads, 3); // source workout, entries, all their sets
      expect(sqlLog.writes, 1); // one batch
    });
  });

  group('finishWorkout', () {
    test('estimates calories with a bounded number of reads', () async {
      await db.insert('body_measurements', {
        'id': 'bm',
        'type': 'weight',
        'value': 70,
        'unit': 'kg',
        'date': '2026-08-01',
        'created_at': _now,
      });
      final id = await repo.createWorkout(
        exercises: [
          for (var i = 0; i < 6; i++)
            {
              'exercise_id': 'bench',
              'sets': [
                for (var j = 0; j < 3; j++) {'weight': 50.0, 'reps': 10},
              ],
            },
        ],
      );

      sqlLog.clear();
      await repo.finishWorkout(id);

      final workout = (await db.query(
        'workouts',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(workout['end_time'], isNotNull);
      expect(workout['estimated_calories'] as num, greaterThan(0));
      // workout, latest weight, entries+sets joined, update.
      expect(sqlLog.reads, 3);
      expect(sqlLog.writes, 1);
    });
  });

  group('removing entries', () {
    test(
      'removeExerciseEntryFromWorkout deletes entries and their sets',
      () async {
        final id = await repo.createWorkout(
          exercises: [
            {
              'exercise_id': 'bench',
              'sets': [
                {'weight': 60.0, 'reps': 10},
              ],
            },
            {
              'exercise_id': 'bench',
              'sets': [
                {'weight': 62.0, 'reps': 10},
              ],
            },
            {
              'exercise_id': 'row',
              'sets': [
                {'weight': 40.0, 'reps': 10},
              ],
            },
          ],
        );

        sqlLog.clear();
        await repo.removeExerciseEntryFromWorkout(id, 'bench');

        expect(sqlLog.total, 1);
        expect(
          (await db.query('exercise_entries')).map((e) => e['exercise_id']),
          ['row'],
        );
        expect((await db.query('sets')).map((s) => s['weight']), [40.0]);
      },
    );

    test('deleteExerciseEntry cascades to its sets', () async {
      await repo.createWorkout(
        exercises: [
          {
            'exercise_id': 'bench',
            'sets': [
              {'weight': 60.0, 'reps': 10},
            ],
          },
        ],
      );
      final entry = (await db.query('exercise_entries')).single;

      await repo.deleteExerciseEntry(entry['id']! as String);

      expect(await count('exercise_entries'), 0);
      expect(await count('sets'), 0);
    });
  });
  group('deleteSet and restoreSet', () {
    Future<String> seedThreeSets() async {
      await repo.createWorkout(
        exercises: [
          {
            'exercise_id': 'bench',
            'sets': [
              {'weight': 60.0, 'reps': 10},
              {'weight': 62.5, 'reps': 8, 'is_warmup': true},
              {'weight': 65.0, 'reps': 6},
            ],
          },
        ],
      );
      return (await db.query('exercise_entries')).single['id']! as String;
    }

    test('restoreSet brings back the exact row in its original position', () async {
      final entryId = await seedThreeSets();
      final before = await repo.getExerciseSets(entryId);
      final middle = before[1];

      final deleted = await repo.deleteSet(middle['id']! as String);

      expect(deleted, middle);
      expect(await count('sets'), 2);

      expect(await repo.restoreSet(deleted!), isTrue);

      expect(await repo.getExerciseSets(entryId), before);
    });

    test('deleteSet returns null for an unknown set', () async {
      expect(await repo.deleteSet('missing'), isNull);
    });

    test('restoreSet is a no-op when its entry is gone or it is back', () async {
      final entryId = await seedThreeSets();
      final first = (await repo.getExerciseSets(entryId)).first;
      final deleted = (await repo.deleteSet(first['id']! as String))!;

      expect(await repo.restoreSet(deleted), isTrue);
      expect(await repo.restoreSet(deleted), isFalse);
      expect(await count('sets'), 3);

      await repo.deleteExerciseEntry(entryId);
      expect(await repo.restoreSet(deleted), isFalse);
      expect(await count('sets'), 0);
    });
  });

  group('month queries', () {
    Future<void> workoutOn(String id, String date) => db.insert('workouts', {
      'id': id,
      'date': date,
      'created_at': '${date}T08:00:00.000',
    });

    test('use exact month bounds, including December and January', () async {
      await workoutOn('nov', '2025-11-30');
      await workoutOn('dec1', '2025-12-01');
      await workoutOn('dec31', '2025-12-31');
      await workoutOn('jan', '2026-01-01');
      await db.insert('exercise_entries', {
        'id': 'ee-dec',
        'workout_id': 'dec31',
        'exercise_id': 'bench',
        'order_index': 0,
      });
      await db.insert('exercise_entries', {
        'id': 'ee-jan',
        'workout_id': 'jan',
        'exercise_id': 'squat',
        'order_index': 0,
      });

      final december = await repo.getWorkoutsByMonth(2025, 12);
      expect(december.map((w) => w['id']), ['dec31', 'dec1']);
      expect((await repo.getWorkoutsByMonth(2026, 1)).map((w) => w['id']), [
        'jan',
      ]);
      expect(await repo.getWorkoutsByMonth(2026, 2), isEmpty);

      final categories = await repo.getWorkoutCategoriesByDate(2025, 12);
      expect(categories.keys, ['2025-12-31']);
      expect(
        (await repo.getWorkoutCategoriesByDate(2026, 1)).keys,
        ['2026-01-01'],
      );
    });
  });
}
