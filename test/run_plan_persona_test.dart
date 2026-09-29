import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Real-athlete scenarios from the persona review
/// (docs/run-plan-persona-review.md). Each test is a plan a real person would
/// have received and could not have completed, or that would not have made
/// them faster.

double _km(RunPlanTemplateWorkout s) => (s.targetDistanceMeters ?? 0) / 1000;

RunPlanTemplateStep _work(RunPlanTemplateWorkout s) =>
    s.steps.firstWhere((step) => step.role == RunStepRole.work);

const _fiveK25 = RunPlanPaceCalibration(
  distanceMeters: 5000,
  timeSeconds: 1500,
);
const _fiveK30 = RunPlanPaceCalibration(
  distanceMeters: 5000,
  timeSeconds: 1800,
);

void main() {
  group('start running', () {
    test('walk-to-jog never jumps to a continuous run', () {
      // Week 6 jogs 90 s blocks; week 7 used to prescribe 3.5 km non-stop.
      final plan = RunPlanComposer.compose(
        RunPlanTemplates.walkJog,
        const RunPlanBuildConfig(sessionsPerWeek: 3, availableDays: [2, 4, 6]),
      );
      for (final session in plan.expand((w) => w)) {
        expect(session.targetDistanceMeters, isNull, reason: session.name);
        expect(
          session.steps.where((s) => s.role == RunStepRole.work),
          isNotEmpty,
          reason: '${session.name} is not a run/walk session',
        );
      }
    });

    test('the graduation run is timed and a small step from the blocks', () {
      final template = RunPlanTemplates.runWalk;
      final plan = RunPlanComposer.compose(
        template,
        const RunPlanBuildConfig(sessionsPerWeek: 3, availableDays: [2, 4, 6]),
      );
      for (var w = 0; w < plan.length; w++) {
        final week = plan[w];
        final continuous = week.where(
          (s) => s.name.startsWith('Corrida contínua'),
        );
        if (continuous.isEmpty) continue;
        final run = continuous.single;
        // Last session of the week, after the week's run/walk sessions.
        final lastDay = week
            .map((s) => s.dayOfWeek)
            .reduce((a, b) => a > b ? a : b);
        expect(run.dayOfWeek, lastDay);
        expect(run.targetDistanceMeters, isNull);
        final steady = run.steps.firstWhere(
          (s) => s.role == RunStepRole.steady,
        );
        expect(steady.metric, RunIntervalMetric.time);
        final longestBlock = template.runWalkWork![w];
        expect(steady.value, lessThanOrEqualTo(longestBlock * 1.7));
      }
    });
  });

  group('every run is worth lacing up for', () {
    test('no easy or recovery run under ~1.6 km, recovery runs stay short', () {
      for (final template in RunPlanTemplates.all) {
        if (template.style == RunPlanTemplateStyle.runWalk) continue;
        for (final sessions in template.allowedSessionsPerWeek) {
          for (final calibration in [null, _fiveK30]) {
            final config = RunPlanBuildConfig(
              sessionsPerWeek: sessions,
              availableDays: const [1, 2, 4, 6, 7].sublist(5 - sessions),
              calibration: calibration,
              paceSource: RunPlanPaceSource.recent,
            );
            final easyPace = calibration?.paces.easySecPerKm ?? 390;
            for (final session in RunPlanComposer.compose(
              template,
              config,
            ).expand((w) => w)) {
              if (session.kind != RunWorkoutKind.easy &&
                  session.kind != RunWorkoutKind.recovery) {
                continue;
              }
              expect(
                _km(session),
                greaterThanOrEqualTo(1.19),
                reason: '${template.key}/$sessions ${session.name}',
              );
              if (session.kind == RunWorkoutKind.recovery) {
                expect(
                  _km(session) * easyPace,
                  lessThanOrEqualTo(40 * 60 + 30),
                  reason: '${template.key}/$sessions long "recovery" run',
                );
              }
            }
          }
        }
      }
    });
  });

  group('faster 5K', () {
    RunPlanBuildConfig config({
      int sessions = 3,
      RunPlanPaceCalibration? goal,
      double weeklyKm = 15,
    }) => RunPlanBuildConfig(
      sessionsPerWeek: sessions,
      availableDays: sessions == 3 ? const [2, 4, 7] : const [2, 4, 6, 7],
      intent: RunPlanIntent.pb,
      calibration: _fiveK30,
      paceSource: RunPlanPaceSource.recent,
      goalCalibration: goal,
      currentWeeklyKm: weeklyKm,
    );

    test('VO2 work shows up on a steady beat, not twice in ten weeks', () {
      final outline = RunPlanComposer.outline(
        RunPlanTemplates.fiveK,
        config(sessions: 4, weeklyKm: 20),
      );
      final buildWeeks = [
        for (var w = 0; w < outline.schedule.length; w++)
          if (outline.weeks[w].phase == RunPlanWeekPhase.build)
            outline.schedule[w],
      ];
      final withVo2 = buildWeeks.where(
        (week) => week.any(
          (s) =>
              s.kind == RunWorkoutKind.interval ||
              s.kind == RunWorkoutKind.hills,
        ),
      );
      expect(withVo2.length, buildWeeks.length);
    });

    test('interval reps are at least 400 m and lengthen towards race day', () {
      final plan = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(sessions: 4, weeklyKm: 25),
      );
      final reps = [
        for (final s in plan.expand((w) => w))
          if (s.kind == RunWorkoutKind.interval &&
              !s.name.startsWith('Ativação'))
            _work(s).value,
      ];
      expect(reps, isNotEmpty);
      expect(reps.every((m) => m >= 400), isTrue, reason: '$reps');
      expect(reps.last, greaterThan(reps.first), reason: '$reps');
    });

    test('a low-volume runner gets a real VO2 dose (≥10 min or ≥4 reps)', () {
      final interval = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(weeklyKm: 15),
      ).expand((w) => w).firstWhere((s) => s.kind == RunWorkoutKind.interval);
      final work = _work(interval);
      expect(work.repeatCount * work.value, greaterThanOrEqualTo(1600));
    });

    test('a goal time is approached, never trained at from week 1', () {
      // 25:00 today, 23:00 goal: week-1 intervals used to be 4:28/km —
      // twenty seconds faster than this runner's VO2 pace.
      const goal = RunPlanPaceCalibration(
        distanceMeters: 5000,
        timeSeconds: 1380,
      );
      final built = RunPlanComposer.outline(
        RunPlanTemplates.fiveK,
        RunPlanBuildConfig(
          sessionsPerWeek: 4,
          availableDays: const [2, 4, 5, 7],
          intent: RunPlanIntent.pb,
          calibration: _fiveK25,
          paceSource: RunPlanPaceSource.recent,
          goalCalibration: goal,
          currentWeeklyKm: 20,
        ),
      );
      final intervals = [
        for (final s in built.schedule.expand((w) => w))
          if (s.kind == RunWorkoutKind.interval &&
              !s.name.startsWith('Ativação'))
            s.targetPaceSecPerKm!,
      ];
      expect(intervals.first, closeTo(_fiveK25.paces.intervalSecPerKm, 2));
      expect(intervals.last, lessThan(intervals.first));
      expect(
        intervals.every((p) => p >= goal.paces.intervalSecPerKm - 1),
        isTrue,
      );
      expect(built.readiness.goalAssessment, isNot(RunPlanGoalAssessment.none));
    });

    test('a realistic goal becomes the race target', () {
      const goal = RunPlanPaceCalibration(
        distanceMeters: 5000,
        timeSeconds: 1740,
      );
      final outline = RunPlanComposer.outline(
        RunPlanTemplates.fiveK,
        config(goal: goal),
      );
      expect(outline.readiness.goalAssessment, RunPlanGoalAssessment.realistic);
      final race = outline.schedule.last.firstWhere(
        (s) => s.kind == RunWorkoutKind.race,
      );
      expect(race.targetPaceSecPerKm, closeTo(goal.paces.raceSecPerKm, 1));
    });

    test('race-pace labels match the prescribed block', () {
      for (final s in RunPlanComposer.compose(
        RunPlanTemplates.firstTenK,
        config(),
      ).expand((w) => w)) {
        if (!s.name.startsWith('Ritmo de prova')) continue;
        final meters = _work(s).value;
        final label = meters < 1000
            ? '$meters m'
            : meters % 1000 == 0
            ? '${meters ~/ 1000} km'
            : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
        expect(s.name, endsWith(label));
      }
    });
  });

  group('first marathon', () {
    test('a 2h10 half-marathoner at 35 km/week can start a plan', () {
      final readiness = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        const RunPlanBuildConfig(
          sessionsPerWeek: 4,
          availableDays: [2, 4, 6, 7],
          currentWeeklyKm: 35,
          calibration: RunPlanPaceCalibration(
            distanceMeters: RunPaceCalculator.halfMeters,
            timeSeconds: 7800,
          ),
          paceSource: RunPlanPaceSource.recent,
        ),
      );
      expect(readiness.canCreate, isTrue);
      expect(readiness.peakLongKm, greaterThanOrEqualTo(27));
    });
  });

  group('race date', () {
    final start = DateTime(2026, 9, 28); // Monday

    RunPlanBuildConfig config(DateTime race) => RunPlanBuildConfig(
      sessionsPerWeek: 4,
      availableDays: const [2, 4, 6, 7],
      intent: RunPlanIntent.pb,
      currentWeeklyKm: 20,
      raceDate: race,
      startDate: start,
    );

    test('a nearer race compresses the plan onto the race week', () {
      // Saturday, seven weeks out (week 1 is the start week).
      final race = start.add(const Duration(days: 6 * 7 + 5));
      final outline = RunPlanComposer.outline(
        RunPlanTemplates.fiveK,
        config(race),
      );
      expect(outline.schedule, hasLength(7));
      expect(outline.readiness.raceTooSoon, isFalse);
      final raceWeek = outline.schedule.last;
      final raceSession = raceWeek.firstWhere(
        (s) => s.kind == RunWorkoutKind.race,
      );
      expect(raceSession.dayOfWeek, DateTime.saturday);
      expect(
        raceWeek.every((s) => s.dayOfWeek <= DateTime.saturday),
        isTrue,
        reason: 'no session after the race',
      );
      expect(outline.startWeek, start);
    });

    test('a later race delays the start instead of racing mid-build', () {
      final race = start.add(const Duration(days: 13 * 7 + 6));
      final outline = RunPlanComposer.outline(
        RunPlanTemplates.fiveK,
        config(race),
      );
      expect(outline.schedule, hasLength(RunPlanTemplates.fiveK.weeks));
      expect(
        outline.startWeek,
        mondayOf(
          race,
        ).subtract(Duration(days: 7 * (RunPlanTemplates.fiveK.weeks - 1))),
      );
    });

    test('a race too close for the plan blocks creation', () {
      final race = start.add(const Duration(days: 2 * 7 + 6));
      final readiness = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        config(race),
      );
      expect(readiness.raceTooSoon, isTrue);
      expect(readiness.canCreate, isFalse);
      expect(readiness.weeksToRace, 3);
    });
  });

  group('terrain', () {
    RunPlanBuildConfig config({
      bool hills = true,
      RunPlanHillSurface surface = RunPlanHillSurface.hill,
    }) => RunPlanBuildConfig(
      sessionsPerWeek: 4,
      availableDays: const [2, 4, 6, 7],
      intent: RunPlanIntent.pb,
      currentWeeklyKm: 30,
      includeHills: hills,
      hillSurface: surface,
    );

    test('stairs and treadmill replace the hill, flat removes it', () {
      Iterable<RunPlanTemplateWorkout> hills(RunPlanBuildConfig c) =>
          RunPlanComposer.compose(
            RunPlanTemplates.hills,
            c,
          ).expand((w) => w).where((s) => s.kind == RunWorkoutKind.hills);

      expect(hills(config()).first.name, startsWith('Morros'));
      expect(
        hills(config(surface: RunPlanHillSurface.stairs)).first.name,
        startsWith('Escadaria'),
      );
      expect(
        hills(config(surface: RunPlanHillSurface.treadmill)).first.name,
        startsWith('Esteira'),
      );
      expect(hills(config(hills: false)), isEmpty);
    });

    test('a hill plan without hill access is flagged', () {
      expect(
        RunPlanComposer.assess(
          RunPlanTemplates.hills,
          config(hills: false),
        ).needsHillAccess,
        isTrue,
      );
    });
  });

  test('the chosen long-run day is honoured', () {
    final plan = RunPlanComposer.compose(
      RunPlanTemplates.tenK,
      const RunPlanBuildConfig(
        sessionsPerWeek: 4,
        availableDays: [1, 3, 5, 6],
        longRunDay: 6,
        currentWeeklyKm: 25,
      ),
    );
    for (final week in plan.take(plan.length - 1)) {
      final longest = week.reduce((a, b) => _km(a) >= _km(b) ? a : b);
      expect(longest.dayOfWeek, 6);
    }
  });

  test('the plan finder never suggests a plan above today\'s level', () {
    expect(
      RunPlanTemplates.recommend(RunPlanExperience.none, RunPlanAim.faster),
      RunPlanTemplates.walkJog,
    );
    expect(
      RunPlanTemplates.recommend(
        RunPlanExperience.fewMinutes,
        RunPlanAim.further,
      ),
      RunPlanTemplates.runWalk,
    );
    // Cannot get faster at a distance not yet covered.
    expect(
      RunPlanTemplates.recommend(
        RunPlanExperience.thirtyMinutes,
        RunPlanAim.faster,
      ),
      RunPlanTemplates.firstFiveK,
    );
    expect(
      RunPlanTemplates.recommend(RunPlanExperience.fiveK, RunPlanAim.faster),
      RunPlanTemplates.fiveK,
    );
    expect(
      RunPlanTemplates.recommend(RunPlanExperience.half, RunPlanAim.further),
      RunPlanTemplates.marathon,
    );
  });

  test('race entries outside human range are rejected', () {
    expect(
      RunPaceCalculator.isPlausibleRace(distanceMeters: 5000, timeSeconds: 25),
      isFalse,
    );
    expect(
      RunPaceCalculator.isPlausibleRace(
        distanceMeters: 5000,
        timeSeconds: 1500,
      ),
      isTrue,
    );
    expect(
      RunPaceCalculator.isPlausibleRace(
        distanceMeters: RunPaceCalculator.marathonMeters,
        timeSeconds: 6 * 3600,
      ),
      isTrue,
    );
  });
}
