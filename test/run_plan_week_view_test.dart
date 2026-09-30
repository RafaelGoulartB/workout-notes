import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_ledger.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/services/run_plan_draft.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';

RunPlanWorkout workout(
  String id, {
  required int week,
  int? day,
  double? km,
  String name = 'Rodagem',
  RunWorkoutKind kind = RunWorkoutKind.easy,
}) => RunPlanWorkout(
  id: id,
  runPlanId: 'plan',
  weekIndex: week,
  dayOfWeek: day,
  orderIndex: 0,
  kind: kind,
  name: name,
  targetDistanceMeters: km == null ? null : km * 1000,
  createdAt: DateTime(2026, 1, 1),
);

RunPlan plan({
  DateTime? activatedAt,
  int weeks = 2,
  RunPlanGoalKind goal = RunPlanGoalKind.tenK,
  List<RunPlanWorkout> workouts = const [],
}) => RunPlan(
  id: 'plan',
  name: 'Plano',
  goalKind: goal,
  weeks: weeks,
  status: RunPlanStatus.active,
  activatedAt: activatedAt,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  workouts: workouts,
);

RunPlanLedgerEntry entry(
  String id,
  ScheduledRunStatus status, {
  DateTime? date,
  double? km,
}) => RunPlanLedgerEntry(
  workoutId: id,
  status: status,
  date: date,
  scheduledRunId: 'sr-$id',
  runActivityId: status == ScheduledRunStatus.completed ? 'act-$id' : null,
  actualDistanceMeters: km == null ? null : km * 1000,
);

void main() {
  // 2026-09-28 is a Monday.
  final monday = DateTime(2026, 9, 28);

  group('dates', () {
    test('a followed plan maps weekdays onto real dates', () {
      final p = plan(activatedAt: monday);
      expect(RunPlanWeekView.dateFor(p, 0, 2, monday), DateTime(2026, 9, 29));
      expect(RunPlanWeekView.dateFor(p, 1, 7, monday), DateTime(2026, 10, 11));
      expect(RunPlanWeekView.weekStart(p, 1, monday), DateTime(2026, 10, 5));
    });

    test('a plan that is not followed has no dates', () {
      final p = plan();
      expect(RunPlanWeekView.dateFor(p, 0, 2, monday), isNull);
      expect(RunPlanWeekView.weekStart(p, 0, monday), isNull);
    });

    test('anchoring mid-week still counts weeks from that Monday', () {
      final p = plan(activatedAt: DateTime(2026, 9, 30));
      expect(RunPlanWeekView.weekStart(p, 0, monday), DateTime(2026, 9, 28));
    });

    test('a repeating plan shows the cycle running today', () {
      final p = plan(activatedAt: monday, weeks: 1);
      expect(p.repeats, isTrue);
      final today = DateTime(2026, 10, 14); // third week after the anchor
      expect(RunPlanWeekView.weekStart(p, 0, today), DateTime(2026, 10, 12));
      expect(
        RunPlanWeekView.weekStart(p, 0, today, cycleShift: 1),
        DateTime(2026, 10, 19),
      );
    });
  });

  group('state', () {
    final today = DateTime(2026, 9, 30);

    test('done and skipped come from the ledger', () {
      expect(
        RunPlanWeekView.stateFor(
          ledger: entry('a', ScheduledRunStatus.completed),
          date: DateTime(2026, 9, 28),
          today: today,
        ),
        RunSessionState.done,
      );
      expect(
        RunPlanWeekView.stateFor(
          ledger: entry('a', ScheduledRunStatus.skipped),
          date: DateTime(2026, 9, 28),
          today: today,
        ),
        RunSessionState.skipped,
      );
    });

    test('a past session that was not run is missed; today is planned', () {
      expect(
        RunPlanWeekView.stateFor(
          ledger: null,
          date: DateTime(2026, 9, 29),
          today: today,
        ),
        RunSessionState.missed,
      );
      expect(
        RunPlanWeekView.stateFor(
          ledger: null,
          date: DateTime(2026, 9, 30),
          today: today,
        ),
        RunSessionState.planned,
      );
      expect(
        RunPlanWeekView.stateFor(ledger: null, date: null, today: today),
        RunSessionState.planned,
      );
    });

    test('a rescheduled session keeps its own date', () {
      final p = plan(
        activatedAt: monday,
        workouts: [workout('a', week: 0, day: 1)],
      );
      final views = RunPlanWeekView.sessionsForWeek(p, 0, {
        'a': entry(
          'a',
          ScheduledRunStatus.planned,
          date: DateTime(2026, 10, 1),
        ),
      }, DateTime(2026, 9, 30));
      expect(views.single.date, DateTime(2026, 10, 1));
      expect(views.single.state, RunSessionState.planned);
    });
  });

  group('weekly km', () {
    test('done km sums the runs, falling back to the planned distance', () {
      final p = plan(
        activatedAt: monday,
        workouts: [
          workout('a', week: 0, day: 1, km: 5),
          workout('b', week: 0, day: 3, km: 8),
          workout('c', week: 0, day: 5, km: 10),
        ],
      );
      final ledger = {
        'a': entry('a', ScheduledRunStatus.completed, km: 5.4),
        'b': entry('b', ScheduledRunStatus.completed),
        'c': entry('c', ScheduledRunStatus.planned),
      };
      expect(RunPlanWeekView.doneMeters(p, 0, ledger), closeTo(13400, 0.001));
      expect(RunPlanWeekView.doneMeters(p, 1, ledger), 0);
    });
  });

  group('next session', () {
    final workouts = [
      workout('a', week: 0, day: 1, name: 'Segunda'),
      workout('b', week: 0, day: 3, name: 'Quarta'),
      workout('c', week: 1, day: 2, name: 'Semana 2'),
    ];

    test('is today\'s session when it is still planned', () {
      final p = plan(activatedAt: monday, workouts: workouts);
      final next = RunPlanWeekView.nextSession(p, {
        'a': entry('a', ScheduledRunStatus.completed),
      }, DateTime(2026, 9, 30));
      expect(next!.workout.id, 'b');
      expect(next.isToday(DateTime(2026, 9, 30)), isTrue);
    });

    test('skips done and missed sessions and looks into later weeks', () {
      final p = plan(activatedAt: monday, workouts: workouts);
      final next = RunPlanWeekView.nextSession(p, {
        'a': entry('a', ScheduledRunStatus.completed),
        'b': entry('b', ScheduledRunStatus.completed),
      }, DateTime(2026, 9, 30));
      expect(next!.workout.id, 'c');
      expect(next.date, DateTime(2026, 10, 6));
    });

    test('is null for a plan that is not followed or already over', () {
      expect(
        RunPlanWeekView.nextSession(
          plan(workouts: workouts),
          const {},
          DateTime(2026, 9, 30),
        ),
        isNull,
      );
      final followed = plan(activatedAt: monday, workouts: workouts);
      expect(
        RunPlanWeekView.nextSession(followed, const {}, DateTime(2026, 12, 1)),
        isNull,
      );
    });

    test('a repeating plan carries on into the next cycle', () {
      final p = plan(
        activatedAt: monday,
        weeks: 1,
        workouts: [workout('a', week: 0, day: 1)],
      );
      // Thursday of the third week: this cycle's Monday is gone.
      final next = RunPlanWeekView.nextSession(
        p,
        const {},
        DateTime(2026, 10, 15),
      );
      expect(next!.date, DateTime(2026, 10, 19));
    });
  });

  group('draft', () {
    test('a session nobody touched is discarded, an edited one is kept', () {
      final blank = workout('a', week: 0, name: 'Fácil');
      expect(RunPlanDraft.isUntouched(blank, defaultName: 'Fácil'), isTrue);
      expect(
        RunPlanDraft.isUntouched(
          workout('a', week: 0, name: 'Fácil', km: 5),
          defaultName: 'Fácil',
        ),
        isFalse,
      );
      expect(
        RunPlanDraft.isUntouched(
          workout('a', week: 0, name: 'Longão'),
          defaultName: 'Fácil',
        ),
        isFalse,
      );
      expect(
        RunPlanDraft.isUntouched(
          workout('a', week: 0, name: 'Fácil', kind: RunWorkoutKind.tempo),
          defaultName: 'Fácil',
        ),
        isFalse,
      );
    });
  });
}
