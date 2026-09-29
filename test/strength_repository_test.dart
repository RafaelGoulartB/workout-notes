import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/strength_repository.dart';

import 'support/ai_test_db.dart';
import 'support/strength_home_fixtures.dart';

void main() {
  late Database db;
  late StrengthRepository repo;

  setUp(() async {
    db = await installAiTestDb();
    await seedStrengthCatalog(db);
    await seedRoutine(
      db,
      id: 'ppl',
      name: 'PPL',
      days: [(id: 'push', name: 'Push A'), (id: 'legs-day', name: 'Legs A')],
    );
    repo = StrengthRepository();
  });

  tearDown(uninstallAiTestDb);

  group('loadFinishedWorkouts', () {
    test('counts only finished workouts and completed working sets', () async {
      await seedWorkout(
        db,
        id: 'done',
        date: '2026-09-10',
        routineId: 'ppl',
        routineDayId: 'push',
        feeling: 4,
        sets: [
          seedSet('bench', 100, 5),
          seedSet('bench', 100, 5),
          seedSet('bench', 40, 10, warmup: true),
          seedSet('bench', 100, 5, complete: false),
          seedSet('squat', 120, 3),
          seedSet('treadmill', 0, 1),
        ],
      );
      // Planned / abandoned and set-less workouts are not sessions.
      await seedWorkout(
        db,
        id: 'planned',
        date: '2026-09-11',
        finished: false,
        sets: [seedSet('bench', 100, 5)],
      );
      await seedWorkout(db, id: 'empty', date: '2026-09-12');

      final workouts = await repo.loadFinishedWorkouts();

      expect(workouts.map((w) => w.id), ['done']);
      final w = workouts.single;
      expect(w.workingSets, 3);
      expect(w.exerciseCount, 2);
      expect(w.volumeKg, 100 * 5 * 2 + 120 * 3);
      expect(w.durationSeconds, 3600);
      expect(w.feelingRating, 4);
      expect(w.routineDayName, 'Push A');
      expect(w.routineName, 'PPL');
      expect(w.routineLabel, 'Push A');
      // Most sets first; cardio never listed.
      expect(w.categoryIds, ['chest', 'legs']);
      expect(w.dominantCategoryId, 'chest');
    });

    test(
      'free workouts have no routine label; range and limit apply',
      () async {
        for (final day in ['2026-09-01', '2026-09-08', '2026-09-15']) {
          await seedWorkout(
            db,
            id: 'w-$day',
            date: day,
            sets: [seedSet('squat', 100, 5)],
          );
        }
        final ranged = await repo.loadFinishedWorkouts(
          from: DateTime(2026, 9, 5),
          to: DateTime(2026, 9, 10),
        );
        expect(ranged.map((w) => w.id), ['w-2026-09-08']);
        expect(ranged.single.routineLabel, isNull);

        final limited = await repo.loadFinishedWorkouts(limit: 2);
        expect(limited.map((w) => w.id), ['w-2026-09-15', 'w-2026-09-08']);
      },
    );

    test('falls back to the workout duration from its timestamps', () async {
      await seedWorkout(
        db,
        id: 'no-duration',
        date: '2026-09-01',
        sets: [seedSet('squat', 100, 5)],
      );
      await db.update('workouts', {'duration_seconds': null});
      final w = (await repo.loadFinishedWorkouts()).single;
      expect(w.durationSeconds, 3600);
    });
  });

  test('loadMuscleLoad groups working sets by muscle', () async {
    await seedWorkout(
      db,
      id: 'a',
      date: '2026-09-14',
      sets: [
        seedSet('bench', 100, 5),
        seedSet('bench', 100, 5),
        seedSet('squat', 100, 5),
        seedSet('squat', 60, 10, warmup: true),
        seedSet('treadmill', 0, 1),
      ],
    );
    await seedWorkout(
      db,
      id: 'old',
      date: '2026-08-01',
      sets: [seedSet('squat', 100, 5)],
    );
    await seedWorkout(
      db,
      id: 'planned',
      date: '2026-09-15',
      finished: false,
      sets: [seedSet('squat', 100, 5)],
    );

    final load = await repo.loadMuscleLoad(
      from: DateTime(2026, 9, 14),
      to: DateTime(2026, 9, 20),
    );

    expect(load.map((m) => m.category.id), ['chest', 'legs']);
    expect(load.first.sets, 2);
    expect(load.first.volumeKg, 1000);
    expect(load.first.category.color, 0xFFE53935);
    expect(load.last.sets, 1);
  });

  test('loadWorkoutStamps lists finished strength days cheaply', () async {
    await seedWorkout(
      db,
      id: 'a',
      date: '2026-09-14',
      durationSeconds: 1800,
      sets: [seedSet('bench', 100, 5)],
    );
    await seedWorkout(
      db,
      id: 'cardio-only',
      date: '2026-09-15',
      sets: [seedSet('treadmill', 0, 1)],
    );
    await seedWorkout(
      db,
      id: 'planned',
      date: '2026-09-16',
      finished: false,
      sets: [seedSet('bench', 100, 5)],
    );
    final stamps = await repo.loadWorkoutStamps(from: DateTime(2026, 9, 1));
    expect(stamps, hasLength(1));
    expect(stamps.single.date, DateTime(2026, 9, 14));
    expect(stamps.single.durationSeconds, 1800);
  });

  test(
    'loadUpcoming returns future unfinished workouts in date order',
    () async {
      await seedWorkout(
        db,
        id: 'later',
        date: '2026-09-30',
        finished: false,
        routineId: 'ppl',
        routineDayId: 'legs-day',
        sets: [seedSet('squat', 100, 5), seedSet('bench', 100, 5)],
      );
      await seedWorkout(db, id: 'soon', date: '2026-09-25', finished: false);
      await seedWorkout(db, id: 'today', date: '2026-09-20', finished: false);
      final upcoming = await repo.loadUpcoming(after: DateTime(2026, 9, 20));
      expect(upcoming.map((u) => u.id), ['soon', 'later']);
      expect(upcoming.last.label, 'Legs A');
      expect(upcoming.last.exerciseCount, 2);
      expect(upcoming.first.label, isNull);
    },
  );

  group('routines', () {
    test('routineDays follow the configured order', () async {
      final days = await repo.routineDays('ppl');
      expect(days.map((d) => d.dayId), ['push', 'legs-day']);
      expect(days.first.routineName, 'PPL');
    });

    test('lastRoutineUse reads the latest finished routine workout', () async {
      expect(await repo.lastRoutineUse(), isNull);
      await seedWorkout(
        db,
        id: 'first',
        date: '2026-09-01',
        routineId: 'ppl',
        routineDayId: 'push',
        sets: [seedSet('bench', 100, 5)],
      );
      await seedWorkout(
        db,
        id: 'second',
        date: '2026-09-03',
        routineId: 'ppl',
        routineDayId: 'legs-day',
        sets: [seedSet('squat', 100, 5)],
      );
      await seedWorkout(
        db,
        id: 'unfinished',
        date: '2026-09-05',
        finished: false,
        routineId: 'ppl',
        routineDayId: 'push',
      );
      final last = await repo.lastRoutineUse();
      expect(last?.routineDayId, 'legs-day');
      expect(await repo.routineSessionCount('ppl'), 2);
      expect(await repo.routineCount(), 1);
      expect(await repo.firstRoutineWithDays(), 'ppl');
    });

    test('loadRoutineDayInfo counts exercises, muscles and time', () async {
      await seedRoutineExercise(
        db,
        id: 're1',
        dayId: 'push',
        exerciseId: 'bench',
        sets: 4,
      );
      await seedRoutineExercise(
        db,
        id: 're2',
        dayId: 'push',
        exerciseId: 'squat',
        order: 1,
      );
      await seedRoutineExercise(
        db,
        id: 're3',
        dayId: 'push',
        exerciseId: 'bench',
        order: 2,
      );

      final info = await repo.loadRoutineDayInfo('push');
      expect(info, isNotNull);
      expect(info!.dayName, 'Push A');
      expect(info.routineName, 'PPL');
      expect(info.exerciseCount, 3);
      // Two bench exercises outrank one squat.
      expect(info.categories.map((c) => c.id), ['chest', 'legs']);
      // 10 sets x (40 s + 60 s rest) minus the final rest.
      expect(info.estimatedSeconds, 10 * 40 + 9 * 60);
      expect(await repo.loadRoutineDayInfo('missing'), isNull);
    });
  });
}
