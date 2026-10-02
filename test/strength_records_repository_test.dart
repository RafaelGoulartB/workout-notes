import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';

import 'support/strength_workout_seed.dart';
import 'support/test_db.dart';

String _describe(StrengthRecordEvent e) =>
    '${e.workoutId}|${e.exerciseId}|${e.kind.name}|${e.weight}x${e.reps}|'
    '${e.value.toStringAsFixed(2)}|${e.previous?.toStringAsFixed(2)}|'
    '${e.date.toIso8601String()}';

void main() {
  late Database db;
  late StrengthRecordsRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await installTestDb();
    repo = StrengthRecordsRepository();
    await seedStrengthBasics(db);
    await seedWorkout(
      db,
      'w1',
      date: '2026-08-03',
      exercises: [
        ('bench', [seedSet(100, 5), seedSet(60, 10, warmup: true)]),
        ('row', [seedSet(80, 8)]),
      ],
    );
    await seedWorkout(
      db,
      'w2',
      date: '2026-08-10',
      exercises: [
        ('bench', [seedSet(100, 6), seedSet(102.5, 3)]),
        ('treadmill', [seedSet(0, 30)]),
      ],
    );
    await seedWorkout(
      db,
      'w3',
      date: '2026-08-17',
      exercises: [
        ('row', [seedSet(85, 8), seedSet(90, 4, done: false)]),
        ('bench', [seedSet(105, 5)]),
      ],
    );
    await seedWorkout(
      db,
      'w-open',
      date: '2026-08-20',
      finished: false,
      exercises: [
        ('bench', [seedSet(200, 5)]),
      ],
    );
    await seedWorkout(
      db,
      'w4',
      date: '2026-08-24',
      exercises: [
        ('bench', [seedSet(107.5, 5)]),
        ('row', [seedSet(85, 10)]),
      ],
    );
  });

  tearDown(uninstallTestDb);

  test('recordsInWorkout matches the events of the full history', () async {
    final all = StrengthRecordsCalculator.events(await repo.loadSets());
    expect(all, isNotEmpty);

    for (final id in ['w1', 'w2', 'w3', 'w-open', 'w4', 'missing']) {
      final expected = [
        for (final e in all)
          if (e.workoutId == id) _describe(e),
      ];
      final actual = [
        for (final e in await repo.recordsInWorkout(id)) _describe(e),
      ];
      expect(actual, expected, reason: 'workout $id');
    }
    expect(
      (await repo.recordsInWorkout('w3')).map((e) => e.exerciseId).toSet(),
      {'bench', 'row'},
    );
  });

  test('loadSets can be limited to some exercises and dates', () async {
    final sets = await repo.loadSets(
      to: DateTime(2026, 8, 10),
      exerciseIds: ['bench'],
    );

    expect(sets.map((s) => s.exerciseId).toSet(), {'bench'});
    expect(sets.map((s) => s.workoutId).toSet(), {'w1', 'w2'});
  });
}
