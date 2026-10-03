import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';

import 'support/strength_workout_seed.dart';
import 'support/test_db.dart';

void main() {
  late Database db;
  late ExerciseRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await installTestDb();
    repo = ExerciseRepository();
    await seedStrengthBasics(db);
    // w1: bench only | w2: bench + row | w3: bench only but with a comment |
    // w4: row only.
    await seedWorkout(
      db,
      'w1',
      date: '2026-09-01',
      feeling: 0,
      exercises: [
        ('bench', [seedSet(100, 5), seedSet(100, 5)]),
      ],
    );
    await seedWorkout(
      db,
      'w2',
      date: '2026-09-02',
      exercises: [
        ('bench', [seedSet(90, 8)]),
        ('row', [seedSet(60, 8)]),
      ],
    );
    await seedWorkout(
      db,
      'w3',
      date: '2026-09-03',
      comment: 'felt great',
      exercises: [
        ('bench', [seedSet(95, 6)]),
      ],
    );
    await seedWorkout(
      db,
      'w4',
      date: '2026-09-04',
      exercises: [
        ('row', [seedSet(70, 8)]),
      ],
    );
    // Seeded workouts carry a rating; w1 stands for one without any.
    await db.update('workouts', {'feeling_rating': null}, where: "id = 'w1'");
    await db.insert('routines', {
      'id': 'r1',
      'name': 'Push',
      'created_at': '2026-08-01T00:00:00.000',
    });
    for (final day in ['d1', 'd2']) {
      await db.insert('routine_days', {
        'id': day,
        'routine_id': 'r1',
        'name': day,
        'order_index': 0,
      });
      await db.insert('routine_exercises', {
        'id': 're-$day',
        'routine_day_id': day,
        'exercise_id': 'bench',
        'order_index': 0,
      });
    }
  });

  tearDown(uninstallTestDb);

  Future<List<String>> workoutIds() async => [
    for (final row in await db.query('workouts', orderBy: 'id'))
      row['id']! as String,
  ];

  test('getDeletionImpact counts workouts, sets and routines', () async {
    final impact = await repo.getDeletionImpact('bench');

    expect(impact.workouts, 3);
    expect(impact.sets, 4);
    expect(impact.routines, 1);
    expect(impact.isEmpty, isFalse);
    expect((await repo.getDeletionImpact('squat')).isEmpty, isTrue);
  });

  test(
    'deleteExercise erases its history and the workouts it emptied',
    () async {
      await repo.deleteExercise('bench');

      // w1 is gone (nothing left), w3 stays for its comment, w2 keeps its row.
      expect(await workoutIds(), ['w2', 'w3', 'w4']);
      expect(
        await db.query('exercise_entries', where: "workout_id = 'w3'"),
        isEmpty,
      );
      expect(
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sets')),
        2,
      );
      expect(await db.query('routine_exercises'), isEmpty);
      expect(
        await db.query('routine_days', where: "routine_id = 'r1'"),
        hasLength(2),
      );
    },
  );

  test('deleteExercise keeps a workout holding a feeling rating', () async {
    await db.update('workouts', {'feeling_rating': 5}, where: "id = 'w1'");

    await repo.deleteExercise('bench');

    expect(await workoutIds(), ['w1', 'w2', 'w3', 'w4']);
  });
}
