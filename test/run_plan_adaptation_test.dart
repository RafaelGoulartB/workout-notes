import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_adaptation.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/run_plan_text.dart';
import 'package:workout_notes/services/run_strength_planner.dart';
import 'package:workout_notes/services/run_week_balance.dart';

final _now = DateTime(2026, 10, 19); // Monday

RunPlanWeekReview _week(
  int index,
  double done, {
  double planned = 20,
  double? easyRpe,
  int maxed = 0,
}) => RunPlanWeekReview(
  weekIndex: index,
  weekStart: _now.subtract(Duration(days: 7 * (4 - index))),
  plannedKm: planned,
  doneKm: done,
  plannedSessions: 4,
  doneSessions: (4 * done / planned).round(),
  easyRpe: easyRpe,
  maxedOutRuns: maxed,
);

RunPlanAdaptationProposal _propose(
  List<RunPlanWeekReview> weeks, {
  double? expectedVdot,
  List<RunFitnessSample> fitness = const [],
  bool started = false,
}) => RunPlanAdaptationEngine.propose(
  currentWeek: 4,
  planWeeks: 10,
  currentWeekStarted: started,
  pastWeeks: weeks,
  expectedVdot: expectedVdot,
  fitness: fitness,
  now: _now,
);

void main() {
  group('weekly review — volume', () {
    test('a full week changes nothing', () {
      final p = _propose([_week(2, 20), _week(3, 19)]);
      expect(p.adjustment, RunPlanAdjustment.none);
      expect(p.isEmpty, isTrue);
    });

    test('a partial week holds at what was actually run', () {
      final p = _propose([_week(2, 20), _week(3, 13)]);
      expect(p.adjustment, RunPlanAdjustment.hold);
      expect(p.baselineKm, 13);
      // Holding repeats a week, so the plan (without a race) grows by one.
      expect(p.remainingWeeks, 10 - 4 + 1);
    });

    test('one missed week resumes a notch below the last solid week', () {
      final p = _propose([_week(2, 22), _week(3, 4)]);
      expect(p.adjustment, RunPlanAdjustment.stepBack);
      expect(p.missedWeeks, 1);
      expect(p.baselineKm, closeTo(22 * 0.9, 0.01));
    });

    test('two missed weeks rebuild from clearly lower volume', () {
      final p = _propose([_week(1, 22), _week(2, 0), _week(3, 5)]);
      expect(p.adjustment, RunPlanAdjustment.rebuild);
      expect(p.baselineKm, closeTo(22 * 0.75, 0.01));
      expect(p.suggestReturnPlan, isFalse);
    });

    test('three or more missed weeks suggest a return-to-running plan', () {
      final p = _propose([_week(0, 20), _week(1, 0), _week(2, 0), _week(3, 0)]);
      expect(p.adjustment, RunPlanAdjustment.rebuild);
      expect(p.baselineKm, closeTo(20 * 0.6, 0.01));
      expect(p.suggestReturnPlan, isTrue);
      // Missed weeks push the end of a plan without a race, capped at three.
      expect(p.remainingWeeks, 10 - 4 + 3);
    });

    test('a full week run while exhausted holds instead of progressing', () {
      final p = _propose([_week(3, 20, easyRpe: 7)]);
      expect(p.adjustment, RunPlanAdjustment.hold);
      expect(p.baselineKm, 20);
    });

    test('an already-started week is re-planned from the next one', () {
      final p = _propose([_week(3, 10)], started: true);
      expect(p.fromWeek, 5);
    });
  });

  group('weekly review — pace', () {
    RunFitnessSample sample(
      double vdot,
      RunFitnessSource source, {
      int ago = 3,
    }) => RunFitnessSample(
      date: _now.subtract(Duration(days: ago)),
      vdot: vdot,
      source: source,
    );

    test('a time trial moves the paces, in bounded steps', () {
      final up = _propose(
        [_week(3, 20)],
        expectedVdot: 40,
        fitness: [sample(42, RunFitnessSource.test)],
      );
      expect(up.changesPace, isTrue);
      expect(up.newVdot, 42);
      expect(up.paceSource, RunFitnessSource.test);

      final huge = _propose(
        [_week(3, 20)],
        expectedVdot: 40,
        fitness: [sample(48, RunFitnessSource.test)],
      );
      expect(huge.newVdot, 42.5);
    });

    test('reps run slower than prescribed bring the paces down', () {
      final p = _propose(
        [_week(3, 20)],
        expectedVdot: 45,
        fitness: [
          sample(43, RunFitnessSource.workout),
          sample(43.4, RunFitnessSource.workout, ago: 8),
        ],
      );
      expect(p.newVdot, lessThan(45));
      expect(p.pacesUp, isFalse);
    });

    test('best efforts can only raise the estimate, and only halfway', () {
      final down = _propose(
        [_week(3, 20)],
        expectedVdot: 45,
        fitness: [sample(38, RunFitnessSource.bestEffort)],
      );
      expect(down.changesPace, isFalse);
      final up = _propose(
        [_week(3, 20)],
        expectedVdot: 40,
        fitness: [sample(42, RunFitnessSource.bestEffort)],
      );
      expect(up.newVdot, 41);
    });

    test('fatigue blocks speeding up on workout evidence', () {
      final p = _propose(
        [_week(3, 20, maxed: 2)],
        expectedVdot: 40,
        fitness: [
          sample(42, RunFitnessSource.workout),
          sample(42, RunFitnessSource.workout, ago: 6),
        ],
      );
      expect(p.pacesUp, isFalse);
    });

    test('old evidence is ignored', () {
      final p = _propose(
        [_week(3, 20)],
        expectedVdot: 40,
        fitness: [sample(44, RunFitnessSource.test, ago: 40)],
      );
      expect(p.changesPace, isFalse);
    });

    test('rep paces convert back to the fitness that prescribed them', () {
      final paces = RunPaceCalculator.fromVdot(42);
      final fromIntervals = RunFitnessSample.fromWorkPaces(
        date: _now,
        paces: List.filled(5, paces.intervalSecPerKm),
        fractionOfVo2Max: 0.98,
      );
      expect(fromIntervals!.vdot, closeTo(42, 0.2));
      final fromTempo = RunFitnessSample.fromWorkPaces(
        date: _now,
        paces: List.filled(3, paces.tempoSecPerKm),
        fractionOfVo2Max: 0.88,
      );
      expect(fromTempo!.vdot, closeTo(42, 0.2));
      expect(
        RunFitnessSample.fromWorkPaces(
          date: _now,
          paces: [paces.intervalSecPerKm],
          fractionOfVo2Max: 0.98,
        ),
        isNull,
        reason: 'one rep is noise',
      );
    });
  });

  group('re-planning with the composer', () {
    const base = RunPlanBuildConfig(
      sessionsPerWeek: 4,
      availableDays: [2, 4, 6, 7],
      intent: RunPlanIntent.pb,
      currentWeeklyKm: 20,
      calibration: RunPlanPaceCalibration(
        distanceMeters: 5000,
        timeSeconds: 1500,
      ),
      paceSource: RunPlanPaceSource.recent,
    );

    test('the config survives a JSON round trip', () {
      final config = base.copyWith(
        goalCalibration: const RunPlanPaceCalibration(
          distanceMeters: 5000,
          timeSeconds: 1440,
        ),
      );
      final back = RunPlanBuildConfig.fromJson(config.toJson())!;
      expect(back.toJson(), config.toJson());
      expect(RunPlanBuildConfig.fromJson({'nonsense': 1}), isNull);
    });

    test('remaining weeks keep the end of the ladder, or rebuild', () {
      final full = RunPlanComposer.compose(RunPlanTemplates.fiveK, base);
      final rest = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        base.copyWith(remainingWeeks: 4),
      );
      expect(rest, hasLength(4));
      expect(rest.last.any((s) => s.kind == RunWorkoutKind.race), isTrue);
      final longer = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        base.copyWith(remainingWeeks: 30),
      );
      expect(longer, hasLength(full.length), reason: 'capped at the ladder');
    });

    test('re-planning into a near race still ends on race day', () {
      final monday = DateTime(2026, 10, 19);
      final plan = RunPlanComposer.outline(
        RunPlanTemplates.marathon,
        base
            .copyWith(startDate: monday, remainingWeeks: 3)
            .copyWithRace(monday.add(const Duration(days: 13))),
      );
      expect(plan.schedule, hasLength(2));
      expect(
        plan.schedule.last.any((s) => s.kind == RunWorkoutKind.race),
        isTrue,
      );
    });

    test(
      'a shortened ladder never shrinks from one build week to the next',
      () {
        // Skipping leading template weeks used to land the template's own down
        // weeks on build weeks: 20.5 km, then 18.6 km, then 20.5 km again.
        for (final template in [
          RunPlanTemplates.fiveK,
          RunPlanTemplates.tenK,
          RunPlanTemplates.half,
          RunPlanTemplates.marathon,
          RunPlanTemplates.firstTenK,
        ]) {
          for (var remaining = 3; remaining < template.weeks; remaining++) {
            final outline = RunPlanComposer.outline(
              template,
              base.copyWith(remainingWeeks: remaining, includeTest: false),
            );
            final weeks = outline.weeks;
            for (var i = 1; i < weeks.length; i++) {
              if (weeks[i].phase != RunPlanWeekPhase.build ||
                  weeks[i - 1].phase != RunPlanWeekPhase.build) {
                continue;
              }
              expect(
                weeks[i].weekKm,
                greaterThanOrEqualTo(weeks[i - 1].weekKm * 0.97),
                reason: '${template.key} remaining=$remaining week ${i + 1}',
              );
            }
          }
        }
      },
    );

    test('plans with room include a mid-plan time trial', () {
      final plan = RunPlanComposer.compose(RunPlanTemplates.fiveK, base);
      final test = plan[3].where((s) => s.kind == RunWorkoutKind.test);
      expect(test, hasLength(1));
      expect(test.single.name, 'Teste de 3 km');
      final noTest = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        base.copyWith(includeTest: false),
      );
      expect(
        noTest.expand((w) => w).any((s) => s.kind == RunWorkoutKind.test),
        isFalse,
      );
    });

    test('sessions are written in the chosen language', () {
      final en = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        const RunPlanBuildConfig(
          sessionsPerWeek: 4,
          availableDays: [2, 4, 6, 7],
          currentWeeklyKm: 20,
          language: RunPlanLanguage.en,
        ),
      ).expand((w) => w);
      final names = en.map((s) => s.name).join(' ');
      expect(names, contains('Easy run'));
      expect(names, isNot(contains('Rodagem')));
      expect(en.first.notes, isNot(contains('Ritmo de conversa')));
    });
  });

  group('strength days', () {
    test('never on or the day before a hard day, two days apart', () {
      final days = RunStrengthPlanner.daysFor([
        (day: 2, kind: RunWorkoutKind.interval, km: 6),
        (day: 4, kind: RunWorkoutKind.easy, km: 5),
        (day: 7, kind: RunWorkoutKind.long, km: 12),
      ]);
      expect(days, hasLength(2));
      for (final d in days) {
        expect({2, 7}.contains(d), isFalse, reason: 'hard day $d');
        expect({1, 6}.contains(d), isFalse, reason: 'day before hard: $d');
      }
      final gap = (days[0] - days[1]).abs();
      expect(gap > 3 ? 7 - gap : gap, greaterThanOrEqualTo(2));
    });

    test('a crowded week shares a quality day, never the long run', () {
      final days = RunStrengthPlanner.daysFor([
        (day: 2, kind: RunWorkoutKind.interval, km: 6),
        (day: 4, kind: RunWorkoutKind.easy, km: 5),
        (day: 5, kind: RunWorkoutKind.tempo, km: 6),
        (day: 7, kind: RunWorkoutKind.long, km: 12),
      ]);
      expect(days, hasLength(2));
      expect(days, isNot(contains(7)));
      expect(days, isNot(contains(6)), reason: 'day before the long run');
      expect(days, isNot(contains(1)), reason: 'day before intervals');
    });

    test('race week has none, the week before one', () {
      const sessions = [
        (day: 2, kind: RunWorkoutKind.easy, km: 5.0),
        (day: 7, kind: RunWorkoutKind.race, km: 5.0),
      ];
      expect(RunStrengthPlanner.daysFor(sessions, raceWeek: true), isEmpty);
      expect(
        RunStrengthPlanner.daysFor(sessions, weekBeforeRace: true),
        hasLength(1),
      );
    });
  });

  group('moving sessions', () {
    final mon = DateTime(2026, 10, 19);
    List<RunBalanceSession> week() => [
      RunBalanceSession(
        id: 'tiro',
        date: mon.add(const Duration(days: 1)),
        kind: RunWorkoutKind.interval,
        km: 6,
      ),
      RunBalanceSession(
        id: 'leve',
        date: mon.add(const Duration(days: 3)),
        kind: RunWorkoutKind.easy,
        km: 5,
      ),
      RunBalanceSession(
        id: 'longao',
        date: mon.add(const Duration(days: 6)),
        kind: RunWorkoutKind.long,
        km: 12,
      ),
    ];

    test('a move that keeps hard and easy days apart is fine', () {
      final advice = RunWeekBalance.adviseMove(
        week: week(),
        movingId: 'tiro',
        to: mon.add(const Duration(days: 2)),
      );
      expect(advice.ok, isTrue);
    });

    test('intervals the day before the long run are flagged', () {
      final advice = RunWeekBalance.adviseMove(
        week: week(),
        movingId: 'tiro',
        to: mon.add(const Duration(days: 5)),
      );
      expect(advice.ok, isFalse);
      expect(advice.issues.single.problem, RunBalanceProblem.hardBackToBack);
      expect(advice.issues.single.other.id, 'longao');
      expect(advice.betterDate, isNotNull);
      final gapToLong = mon
          .add(const Duration(days: 6))
          .difference(advice.betterDate!)
          .inDays;
      expect(gapToLong, isNot(1));
    });

    test('moving onto an easy day offers a swap', () {
      final advice = RunWeekBalance.adviseMove(
        week: week(),
        movingId: 'tiro',
        to: mon.add(const Duration(days: 3)),
      );
      expect(advice.issues.first.problem, RunBalanceProblem.sameDay);
      expect(advice.swapWith?.id, 'leve');
    });
  });

  group('end of plan', () {
    RunPlan plan(RunPlanGoalKind goal, int weeks) => RunPlan(
      id: 'p',
      name: 'p',
      goalKind: goal,
      weeks: weeks,
      status: RunPlanStatus.active,
      activatedAt: DateTime(2026, 8, 3),
      createdAt: DateTime(2026, 8, 3),
      updatedAt: DateTime(2026, 8, 3),
    );

    test('a goal plan ends instead of starting week 1 again', () {
      final tenK = plan(RunPlanGoalKind.tenK, 4);
      expect(tenK.activeWeekIndexOn(DateTime(2026, 8, 24)), 3);
      expect(tenK.activeWeekIndexOn(DateTime(2026, 8, 31)), isNull);
      expect(tenK.isFinishedOn(DateTime(2026, 8, 31)), isTrue);
      expect(tenK.isFinishedOn(DateTime(2026, 8, 24)), isFalse);
    });

    test('maintenance and one-week plans keep repeating', () {
      final keep = plan(RunPlanGoalKind.maintenance, 4);
      expect(keep.activeWeekIndexOn(DateTime(2026, 8, 31)), 0);
      expect(keep.isFinishedOn(DateTime(2026, 8, 31)), isFalse);
      final weekly = plan(RunPlanGoalKind.base, 1);
      expect(weekly.activeWeekIndexOn(DateTime(2026, 9, 14)), 0);
    });

    test('the next plan is one level up, never the same plan', () {
      final afterFirst5k = RunPlanTemplates.nextSteps(
        'first_5k',
        RunPlanGoalKind.fiveK,
      );
      expect(afterFirst5k.first.key, '5k');
      for (final template in RunPlanTemplates.all) {
        final next = RunPlanTemplates.nextSteps(
          template.key,
          template.goalKind,
        );
        expect(next, isNotEmpty, reason: template.key);
        expect(next.map((t) => t.key), isNot(contains(template.key)));
      }
    });
  });
}

extension on RunPlanBuildConfig {
  RunPlanBuildConfig copyWithRace(DateTime race) => RunPlanBuildConfig(
    sessionsPerWeek: sessionsPerWeek,
    availableDays: availableDays,
    intent: intent,
    intensity: intensity,
    calibration: calibration,
    paceSource: paceSource,
    currentWeeklyKm: currentWeeklyKm,
    startDate: startDate,
    remainingWeeks: remainingWeeks,
    raceDate: race,
  );
}
