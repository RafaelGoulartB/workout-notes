import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

void main() {
  late Database db;
  late StrengthHistoryRepository repo;

  setUp(() async {
    db = await installAiTestDb();
    repo = StrengthHistoryRepository(
      exerciseMatcher: (row, query) =>
          (row['name'] as String).toLowerCase().contains(query.toLowerCase()),
    );
    await seedStrengthBasics(db);

    await seedWorkout(
      db,
      'w1',
      date: '2026-08-30',
      routineId: 'ppl',
      dayId: 'push',
      exercises: [
        (
          'bench',
          [seedSet(60, 10, warmup: true), seedSet(100, 5), seedSet(100, 5)],
        ),
      ],
    );
    await seedWorkout(
      db,
      'w2',
      date: '2026-09-02',
      routineId: 'ppl',
      dayId: 'pull',
      comment: 'felt strong',
      exercises: [
        ('row', [seedSet(80, 8), seedSet(80, 8), seedSet(80, 8, done: false)]),
        ('bench', [seedSet(50, 10)]),
      ],
    );
    // Legacy workout: no routine day, only the routine.
    await seedWorkout(
      db,
      'w3',
      date: '2026-09-10',
      routineId: 'ppl',
      exercises: [
        ('bench', [seedSet(105, 5)]),
      ],
    );
    // Free workout.
    await seedWorkout(
      db,
      'w4',
      date: '2026-09-20',
      exercises: [
        ('row', [seedSet(90, 5)]),
      ],
    );
    // Cardio only, unfinished and empty workouts must not be listed.
    await seedWorkout(
      db,
      'cardio',
      date: '2026-09-21',
      exercises: [
        ('treadmill', [seedSet(0, 0)]),
      ],
    );
    await seedWorkout(
      db,
      'open',
      date: '2026-09-22',
      finished: false,
      exercises: [
        ('bench', [seedSet(100, 5)]),
      ],
    );
    await seedWorkout(db, 'empty', date: '2026-09-23');
  });

  tearDown(uninstallAiTestDb);

  test('lists only finished gym workouts, newest first', () async {
    final list = await repo.search(const StrengthHistoryFilter());
    expect(list.map((w) => w.id), ['w4', 'w3', 'w2', 'w1']);
  });

  test('titles fall back from day to routine to free workout', () async {
    final byId = {
      for (final w in await repo.search(const StrengthHistoryFilter())) w.id: w,
    };
    expect(byId['w1']!.title, 'Push A');
    expect(byId['w1']!.routineName, 'Push Pull Legs');
    expect(byId['w3']!.title, 'Push Pull Legs');
    expect(byId['w4']!.title, isNull);
  });

  test('volume and working sets skip warm-ups and incomplete sets', () async {
    final byId = {
      for (final w in await repo.search(const StrengthHistoryFilter())) w.id: w,
    };
    expect(byId['w1']!.workingSets, 2);
    expect(byId['w1']!.volume, 1000);
    // Row: 2 done sets of 80x8 = 1280, bench 50x10 = 500.
    expect(byId['w2']!.workingSets, 3);
    expect(byId['w2']!.volume, 1780);
    expect(byId['w2']!.exerciseCount, 2);
    expect(byId['w2']!.muscles.map((m) => m.categoryId), ['back', 'chest']);
    expect(byId['w1']!.durationSeconds, 3600);
    expect(byId['w1']!.startedAt, DateTime(2026, 8, 30, 18));
  });

  test('paginates', () async {
    final first = await repo.search(const StrengthHistoryFilter(), limit: 3);
    final second = await repo.search(
      const StrengthHistoryFilter(),
      limit: 3,
      offset: 3,
    );
    expect(first.map((w) => w.id), ['w4', 'w3', 'w2']);
    expect(second.map((w) => w.id), ['w1']);
  });

  group('filters', () {
    test('search matches routine, day, notes and exercise names', () async {
      Future<List<String>> ids(String q) async => [
        for (final w in await repo.search(StrengthHistoryFilter(query: q)))
          w.id,
      ];
      expect(await ids('push a'), ['w1']);
      expect(await ids('legs'), ['w3', 'w2', 'w1']);
      expect(await ids('strong'), ['w2']);
      expect(await ids('barbell'), ['w4', 'w2']);
      expect(await ids('nothing'), isEmpty);
    });

    test('search escapes LIKE wildcards', () async {
      final list = await repo.search(const StrengthHistoryFilter(query: '%'));
      expect(list, isEmpty);
    });

    test('routine filter includes workouts linked only by day', () async {
      final list = await repo.search(
        const StrengthHistoryFilter(routineId: 'ppl'),
      );
      expect(list.map((w) => w.id), ['w3', 'w2', 'w1']);
    });

    test('muscle filter keeps workouts training that group', () async {
      final list = await repo.search(
        const StrengthHistoryFilter(categoryId: 'back'),
      );
      expect(list.map((w) => w.id), ['w4', 'w2']);
    });

    test('period filter is relative to now', () async {
      final list = await repo.search(
        const StrengthHistoryFilter(period: StrengthHistoryPeriod.last30Days),
        now: DateTime(2026, 10, 5),
      );
      expect(list.map((w) => w.id), ['w4', 'w3']);
    });
  });

  test('summarize and monthlyTotals follow the filter', () async {
    final months = await repo.monthlyTotals(const StrengthHistoryFilter());
    expect(months.keys.toSet(), {'2026-08', '2026-09'});
    expect(months['2026-08']!.count, 1);
    expect(months['2026-08']!.volume, 1000);
    expect(months['2026-09']!.count, 3);
    expect(months['2026-09']!.volume, 1780 + 525 + 450);
    expect(months['2026-09']!.workingSets, 5);

    final total = await repo.summarize(
      const StrengthHistoryFilter(routineId: 'ppl'),
    );
    expect(total.count, 3);
    expect(total.durationSeconds, 3 * 3600);
    expect(total.volume, 1000 + 1780 + 525);

    final none = await repo.summarize(
      const StrengthHistoryFilter(query: 'zzz'),
    );
    expect(none.count, 0);
  });

  test('recordCounts counts exercises with a record per workout', () async {
    final counts = await repo.recordCounts();
    // w1 is the baseline of bench, w3 beats it; row: w4 beats w2's 80x8.
    expect(counts['w1'], isNull);
    expect(counts['w3'], 1);
    expect(counts['w4'], 1);
  });

  test('routine and muscle options only offer strength data', () async {
    expect((await repo.routineOptions()).map((r) => r.id), ['ppl']);
    expect((await repo.categoryOptions()).map((c) => c.id), ['chest', 'back']);
  });

  group('detail', () {
    test('compares against the previous session of the same day', () async {
      await seedWorkout(
        db,
        'w5',
        date: '2026-09-25',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          ('bench', [seedSet(110, 6), seedSet(110, 6)]),
        ],
      );
      final detail = (await repo.loadDetail('w5'))!;
      expect(detail.title, 'Push A');
      expect(detail.comparable!.id, 'w1');
      expect(detail.comparable!.basis, WorkoutComparisonBasis.routineDay);
      expect(detail.comparableName, 'Push A');
      expect(detail.comparison!.volumeDelta, 1320 - 1000);
      expect(detail.exercises.single.sets, hasLength(2));
      expect(detail.records, isNotEmpty);
    });

    test('falls back to the routine, then to shared exercises', () async {
      await seedWorkout(
        db,
        'w6',
        date: '2026-09-26',
        routineId: 'ppl',
        exercises: [
          ('bench', [seedSet(100, 5)]),
        ],
      );
      final byRoutine = (await repo.loadDetail('w6'))!;
      expect(byRoutine.comparable!.basis, WorkoutComparisonBasis.routine);
      expect(byRoutine.comparable!.id, 'w3');

      await seedWorkout(
        db,
        'w7',
        date: '2026-09-27',
        exercises: [
          ('row', [seedSet(90, 5)]),
        ],
      );
      final byExercise = (await repo.loadDetail('w7'))!;
      expect(byExercise.comparable!.basis, WorkoutComparisonBasis.exercises);
      expect(byExercise.comparable!.id, 'w4');
    });

    test('unfinished workouts have no comparison or records', () async {
      final detail = (await repo.loadDetail('open'))!;
      expect(detail.isFinished, isFalse);
      expect(detail.comparison, isNull);
      expect(detail.records, isEmpty);
    });

    test('missing workout returns null', () async {
      expect(await repo.loadDetail('nope'), isNull);
    });
  });

  group('WorkoutRepository blank sessions', () {
    test('createWorkout derives the routine from the day', () async {
      final id = await WorkoutRepository().createWorkout(routineDayId: 'pull');
      final row = (await WorkoutRepository().getWorkout(id))!;
      expect(row['routine_day_id'], 'pull');
      expect(row['routine_id'], 'ppl');
      expect(row['is_from_routine'], 1);
    });

    test('importing a routine day links the workout to it once', () async {
      final repo = WorkoutRepository();
      final id = await repo.createWorkout();
      await repo.importRoutineDayToWorkout(id, 'push');
      await repo.importRoutineDayToWorkout(id, 'pull');
      final row = (await repo.getWorkout(id))!;
      expect(row['routine_day_id'], 'push');
      expect(row['routine_id'], 'ppl');
      expect(row['is_from_routine'], 1);
    });

    test('deleteIfBlank only removes untouched unfinished workouts', () async {
      final repo = WorkoutRepository();
      final blank = await repo.createWorkout();
      expect(await repo.deleteIfBlank(blank), isTrue);
      expect(await repo.getWorkout(blank), isNull);

      expect(await repo.deleteIfBlank('open'), isFalse);
      expect(await repo.deleteIfBlank('w1'), isFalse);
      expect(await repo.getWorkout('w1'), isNotNull);
    });

    test(
      'deleteAbandonedBlankWorkouts spares planned and routine ones',
      () async {
        final repo = WorkoutRepository();
        final orphan = await repo.createWorkout();
        final planned = await repo.createWorkout(
          date: DateTime.now().add(const Duration(days: 3)),
        );
        final fromRoutine = await repo.createWorkout(routineId: 'ppl');
        final keep = await repo.createWorkout();

        final removed = await repo.deleteAbandonedBlankWorkouts(exceptId: keep);
        expect(removed, greaterThanOrEqualTo(1));
        expect(await repo.getWorkout(orphan), isNull);
        expect(await repo.getWorkout(planned), isNotNull);
        expect(await repo.getWorkout(fromRoutine), isNotNull);
        expect(await repo.getWorkout(keep), isNotNull);
        // 'empty' (finished) stays.
        expect(await repo.getWorkout('empty'), isNotNull);
      },
    );
  });
}
