import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/services/strength_today_service.dart';

import 'support/ai_test_db.dart';
import 'support/strength_home_fixtures.dart';

StrengthRoutineDayRef _day(String id, int index) => StrengthRoutineDayRef(
  routineId: 'r',
  routineName: 'R',
  dayId: id,
  dayName: id,
  orderIndex: index,
);

void main() {
  group('StrengthTodayResolver', () {
    final days = [_day('a', 0), _day('b', 1), _day('c', 2)];

    test('next day follows the last one and wraps around', () {
      expect(StrengthTodayResolver.nextDayAfter(days, 'a')?.dayId, 'b');
      expect(StrengthTodayResolver.nextDayAfter(days, 'c')?.dayId, 'a');
    });

    test('unknown last day uses the fallback index or the first day', () {
      expect(StrengthTodayResolver.nextDayAfter(days, null)?.dayId, 'a');
      expect(StrengthTodayResolver.nextDayAfter(days, 'gone')?.dayId, 'a');
      expect(
        StrengthTodayResolver.nextDayAfter(days, null, fallbackIndex: 4)?.dayId,
        'b',
      );
      expect(StrengthTodayResolver.nextDayAfter(const [], 'a'), isNull);
    });

    test('next strength date skips days without a session', () {
      // Tuesday 2026-09-29; sessions Mon/Wed/Fri.
      final next = StrengthTodayResolver.nextStrengthDate(
        DateTime(2026, 9, 29),
        [1, 3, 5],
      );
      expect(next, DateTime(2026, 9, 30));
      expect(
        StrengthTodayResolver.nextStrengthDate(DateTime(2026, 9, 29), [2]),
        DateTime(2026, 10, 6),
      );
      expect(
        StrengthTodayResolver.nextStrengthDate(DateTime(2026, 9, 29), []),
        isNull,
      );
    });

    test('status: done wins, then rest days, then the suggestion', () {
      final tuesday = DateTime(2026, 9, 29);
      expect(
        StrengthTodayResolver.status(
          today: tuesday,
          doneToday: true,
          hasSuggestion: true,
          plannedStrengthDays: [1, 3],
        ),
        StrengthTodayStatus.done,
      );
      expect(
        StrengthTodayResolver.status(
          today: tuesday,
          doneToday: false,
          hasSuggestion: true,
          plannedStrengthDays: [1, 3],
        ),
        StrengthTodayStatus.rest,
      );
      expect(
        StrengthTodayResolver.status(
          today: tuesday,
          doneToday: false,
          hasSuggestion: true,
          plannedStrengthDays: [2, 4],
        ),
        StrengthTodayStatus.planned,
      );
      expect(
        StrengthTodayResolver.status(
          today: tuesday,
          doneToday: false,
          hasSuggestion: true,
        ),
        StrengthTodayStatus.planned,
      );
      expect(
        StrengthTodayResolver.status(
          today: tuesday,
          doneToday: false,
          hasSuggestion: false,
        ),
        StrengthTodayStatus.none,
      );
    });
  });

  group('StrengthTodayService (no planning tables)', () {
    late Database db;
    final now = DateTime(2026, 9, 29, 9);

    setUp(() async {
      db = await installAiTestDb();
      await seedStrengthCatalog(db);
    });

    tearDown(uninstallAiTestDb);

    test('no routines at all means no suggestion', () async {
      final snapshot = await StrengthTodayService().load(now: now);
      expect(snapshot.today.status, StrengthTodayStatus.none);
      expect(snapshot.hasRoutines, isFalse);
      expect(snapshot.today.startDay, isNull);
    });

    test(
      'never trained: suggests the first day of the newest routine',
      () async {
        await seedRoutine(
          db,
          id: 'ppl',
          name: 'PPL',
          days: [(id: 'push', name: 'Push A'), (id: 'pull', name: 'Pull A')],
        );
        await seedRoutineExercise(
          db,
          id: 're1',
          dayId: 'push',
          exerciseId: 'bench',
        );
        final snapshot = await StrengthTodayService().load(now: now);
        expect(snapshot.today.status, StrengthTodayStatus.planned);
        expect(snapshot.today.day?.dayName, 'Push A');
        expect(snapshot.today.day?.exerciseCount, 1);
        expect(snapshot.today.fromPlan, isFalse);
        expect(snapshot.hasRoutines, isTrue);
      },
    );

    test('suggests the day after the last one trained', () async {
      await seedRoutine(
        db,
        id: 'ppl',
        name: 'PPL',
        days: [
          (id: 'push', name: 'Push A'),
          (id: 'pull', name: 'Pull A'),
          (id: 'legs', name: 'Legs A'),
        ],
      );
      await seedWorkout(
        db,
        id: 'w1',
        date: '2026-09-27',
        routineId: 'ppl',
        routineDayId: 'pull',
        sets: [seedSet('bench', 100, 5)],
      );
      final snapshot = await StrengthTodayService().load(now: now);
      expect(snapshot.today.status, StrengthTodayStatus.planned);
      expect(snapshot.today.day?.dayName, 'Legs A');
    });

    test('older workouts without a day rotate by session count', () async {
      await seedRoutine(
        db,
        id: 'ab',
        name: 'AB',
        days: [(id: 'a', name: 'A'), (id: 'b', name: 'B')],
      );
      await seedWorkout(
        db,
        id: 'w1',
        date: '2026-09-20',
        routineId: 'ab',
        sets: [seedSet('bench', 100, 5)],
      );
      final snapshot = await StrengthTodayService().load(now: now);
      // One finished session so far: index 1 -> B.
      expect(snapshot.today.day?.dayName, 'B');
    });

    test('a workout finished today shows as done with the next day', () async {
      await seedRoutine(
        db,
        id: 'ab',
        name: 'AB',
        days: [(id: 'a', name: 'A'), (id: 'b', name: 'B')],
      );
      await seedWorkout(
        db,
        id: 'today',
        date: '2026-09-29',
        routineId: 'ab',
        routineDayId: 'a',
        sets: [seedSet('bench', 100, 5), seedSet('bench', 100, 5)],
      );
      final snapshot = await StrengthTodayService().load(now: now);
      expect(snapshot.today.status, StrengthTodayStatus.done);
      expect(snapshot.today.doneWorkout?.id, 'today');
      expect(snapshot.today.doneWorkout?.workingSets, 2);
      expect(snapshot.today.next?.dayName, 'B');
      expect(snapshot.today.startDay?.dayName, 'B');
    });

    test('an unfinished workout today is not done', () async {
      await seedRoutine(db, id: 'ab', name: 'AB', days: [(id: 'a', name: 'A')]);
      await seedWorkout(
        db,
        id: 'open',
        date: '2026-09-29',
        finished: false,
        routineId: 'ab',
        routineDayId: 'a',
        sets: [seedSet('bench', 100, 5)],
      );
      final snapshot = await StrengthTodayService().load(now: now);
      expect(snapshot.today.status, StrengthTodayStatus.planned);
    });

    test('upcoming planned workouts are listed', () async {
      await seedWorkout(db, id: 'future', date: '2026-10-02', finished: false);
      final snapshot = await StrengthTodayService().load(now: now);
      expect(snapshot.upcoming.map((u) => u.id), ['future']);
    });

    test('the weekly goal round-trips through app_settings', () async {
      final service = StrengthTodayService();
      expect(await service.readWeeklyGoalSessions(), isNull);
      await service.setWeeklyGoalSessions(4);
      expect(await service.readWeeklyGoalSessions(), 4);
      expect((await service.load(now: now)).userWeeklyGoalSessions, 4);
      await service.setWeeklyGoalSessions(null);
      expect(await service.readWeeklyGoalSessions(), isNull);
    });
  });
}
