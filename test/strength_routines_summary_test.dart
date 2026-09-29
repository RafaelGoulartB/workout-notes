import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';

import 'support/ai_test_db.dart';
import 'support/strength_routines_seed.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await installAiTestDb();
    await seedStrengthRoutines(db);
  });

  tearDown(() async => uninstallAiTestDb());

  group('RoutineRepository.getRoutineSummaries', () {
    test('sizes days and routines in one batch', () async {
      final routines = await RoutineRepository().getRoutineSummaries();
      expect(routines.map((r) => r.id), ['r1', 'r2']); // newest first

      final ppl = routines.first;
      expect(ppl.notes, 'desc');
      expect(ppl.dayCount, 2);
      expect(ppl.exerciseCount, 3);
      final push = ppl.days.first;
      expect(push.name, 'Push');
      expect(push.exerciseCount, 1);
      expect(push.totalSets, 4);
      expect(push.workingSets, 3, reason: 'warm-ups do not count');
      expect(push.volumeKg, 2400);
      expect(push.estimatedSeconds, greaterThan(0));
      expect(push.muscles.single.categoryId, 'chest');

      final pull = ppl.days.last;
      expect(pull.exerciseCount, 2);
      expect(
        pull.workingSets,
        2,
        reason: 'cardio sets are excluded from muscle sets',
      );
      expect(pull.muscles.map((m) => m.categoryId), ['back']);
      expect(pull.totalSets, 3);

      expect(ppl.weeklySets, 5);
      expect(ppl.muscles.map((m) => m.categoryId), ['chest', 'back']);
      expect(ppl.weeklyVolumeKg, 2400 + 960);

      final empty = routines.last;
      expect(empty.dayCount, 0);
      expect(empty.weeklySets, 0);
      expect(empty.averageSessionSeconds, 0);
    });

    test('routineId limits the result', () async {
      final one = await RoutineRepository().getRoutineSummary('r2');
      expect(one?.name, 'Full body');
      expect(await RoutineRepository().getRoutineSummary('nope'), isNull);
    });

    test('last trained comes from finished workouts only', () async {
      await seedRoutineWorkout(
        db,
        'w1',
        '2026-09-10',
        routineId: 'r1',
        dayId: 'd1',
      );
      await seedRoutineWorkout(
        db,
        'w2',
        '2026-09-12',
        routineId: 'r1',
        dayId: 'd2',
      );
      await seedRoutineWorkout(
        db,
        'w3',
        '2026-09-20',
        routineId: 'r1',
        finished: false,
      );
      // Legacy workout: routine only, no day.
      await seedRoutineWorkout(db, 'w4', '2026-09-05', routineId: 'r2');

      final routines = await RoutineRepository().getRoutineSummaries();
      final ppl = routines.firstWhere((r) => r.id == 'r1');
      expect(ppl.lastTrainedAt, DateTime(2026, 9, 12));
      expect(ppl.days[0].lastTrainedAt, DateTime(2026, 9, 10));
      expect(ppl.days[1].lastTrainedAt, DateTime(2026, 9, 12));
      final full = routines.firstWhere((r) => r.id == 'r2');
      expect(full.lastTrainedAt, DateTime(2026, 9, 5));

      expect(pickNextDayId(ppl), 'd1', reason: 'wraps after the last day');
      expect(
        pickActiveRoutineId(routines: routines),
        'r1',
        reason: 'most recently trained',
      );
      expect(
        pickActiveRoutineId(routines: routines, plannedRoutineId: 'r2'),
        'r2',
        reason: 'the periodization link wins',
      );
      expect(
        pickActiveRoutineId(routines: routines, plannedRoutineId: 'gone'),
        'r1',
      );
    });

    test('works on a workouts table without routine_day_id', () async {
      await db.execute('ALTER TABLE workouts RENAME TO workouts_old');
      await db.execute(
        'CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT, end_time TEXT, routine_id TEXT)',
      );
      await db.insert('workouts', {
        'id': 'w',
        'date': '2026-09-01',
        'end_time': '2026-09-01T11:00:00',
        'routine_id': 'r1',
      });
      final ppl = await RoutineRepository().getRoutineSummary('r1');
      expect(ppl?.lastTrainedAt, DateTime(2026, 9, 1));
      expect(ppl?.days.first.lastTrainedAt, isNull);
    });
  });

  test('getPredefinedSetsForDay groups sets per exercise in order', () async {
    final sets = await RoutineRepository().getPredefinedSetsForDay('d1');
    expect(sets.keys, ['re1']);
    expect(sets['re1']!.map((s) => s['id']), ['ps0', 'ps1', 'ps2', 'ps3']);
  });

  test('day editor rows summarize like the batched query', () async {
    final repo = RoutineRepository();
    final exercises = await repo.getRoutineExercises('d2');
    final sets = await repo.getPredefinedSetsForDay('d2');
    final summary = StrengthRoutineSummaryBuilder.buildDay(
      day: {'id': 'd2', 'routine_id': 'r1', 'name': 'Pull', 'order_index': 1},
      rows: StrengthRoutineSummaryBuilder.setRowsFromDay(exercises, sets),
      lastTrainedAt: null,
    );
    final batched = (await repo.getRoutineSummary('r1'))!.days.last;
    expect(summary.workingSets, batched.workingSets);
    expect(summary.estimatedSeconds, batched.estimatedSeconds);
    expect(summary.exerciseCount, 2);
  });

  test('duplicateRoutine copies days, exercises and preset sets', () async {
    final repo = RoutineRepository();
    final copyId = await repo.duplicateRoutine('r1', 'PPL (cópia)');
    expect(copyId, isNotNull);
    expect(copyId, isNot('r1'));

    final copy = (await repo.getRoutineSummary(copyId!))!;
    final original = (await repo.getRoutineSummary('r1'))!;
    expect(copy.name, 'PPL (cópia)');
    expect(copy.notes, 'desc');
    expect(copy.dayCount, original.dayCount);
    expect(copy.exerciseCount, original.exerciseCount);
    expect(copy.weeklySets, original.weeklySets);
    expect(copy.days.map((d) => d.name), ['Push', 'Pull']);
    expect(
      copy.days
          .map((d) => d.id)
          .toSet()
          .intersection(original.days.map((d) => d.id).toSet()),
      isEmpty,
    );
    // The original is untouched.
    expect(original.weeklySets, 5);
    expect(await repo.duplicateRoutine('missing', 'x'), isNull);
  });

  test('getExerciseUsage counts finished sessions with working sets', () async {
    await seedRoutineWorkout(db, 'w1', '2026-09-01');
    await seedRoutineWorkout(db, 'w2', '2026-09-08');
    await seedRoutineWorkout(db, 'w3', '2026-09-15', finished: false);
    var entry = 0;
    Future<void> log(String workout, String exercise, {int warmup = 0}) async {
      final id = 'e${entry++}';
      await db.insert('exercise_entries', {
        'id': id,
        'workout_id': workout,
        'exercise_id': exercise,
        'order_index': 0,
      });
      await db.insert('sets', {
        'id': 's$id',
        'exercise_entry_id': id,
        'weight': 50.0,
        'reps': 5,
        'is_complete': 1,
        'is_warmup': warmup,
        'order_index': 0,
      });
    }

    await log('w1', 'bench');
    await log('w2', 'bench');
    await log('w3', 'bench'); // unfinished workout
    await log('w2', 'row', warmup: 1); // warm-up only

    final usage = await ExerciseRepository().getExerciseUsage();
    expect(usage.keys, ['bench']);
    expect(usage['bench']!.sessions, 2);
    expect(usage['bench']!.lastDate, DateTime(2026, 9, 8));
  });

  test('weekly sets level against the recommended range', () {
    expect(StrengthRoutineSummaryBuilder.levelFor(6), WeeklySetsLevel.low);
    expect(StrengthRoutineSummaryBuilder.levelFor(10), WeeklySetsLevel.inRange);
    expect(StrengthRoutineSummaryBuilder.levelFor(20), WeeklySetsLevel.inRange);
    expect(StrengthRoutineSummaryBuilder.levelFor(21), WeeklySetsLevel.high);
  });
}
