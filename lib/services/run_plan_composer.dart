import 'dart:math' as math;

import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_build_config.dart';
import 'package:workout_notes/services/run_plan_outline.dart';
import 'package:workout_notes/services/run_plan_text.dart';

export 'package:workout_notes/services/run_plan_build_config.dart';
export 'package:workout_notes/services/run_plan_outline.dart';

part 'run_plan_composer_models.dart';
part 'run_plan_session_builders.dart';
part 'run_plan_week_planner.dart';

/// Builds a full progressive schedule from a template blueprint + coach config.
///
/// Design follows mainstream endurance-training evidence:
/// - Polarized / pyramidal distribution (~80% easy, ~20% quality)
/// - Weekly volume is the primary quantity; the long run is a bounded share of
///   it, never the other way round
/// - Week-over-week volume growth capped near 10%, with a down week every 4th
/// - Taper cuts volume and *keeps* intensity (Mujika & Padilla)
/// - VO2max work capped near 8% of weekly volume, threshold near 10% (Daniels)
/// - Recovery between reps scales with rep duration, not a fixed constant
/// - Race pace is re-derived for the goal distance, never copied from the
///   calibration race
abstract final class RunPlanComposer {
  static List<List<RunPlanTemplateWorkout>> compose(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) => outline(template, config).schedule;

  /// Coach's sanity check on a template + config *before* the plan is created.
  ///
  /// The composer never silently produces a plan that cannot prepare the
  /// athlete for the race, nor one that jumps far above what they run today —
  /// but it also cannot refuse the athlete's inputs. So the two failure modes
  /// are surfaced here for the wizard to show, together with a schedule smell
  /// (three running days in a row on a 3–4 day week).
  static RunPlanReadiness assess(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) => outline(template, config).readiness;

  /// Composed sessions plus the week-by-week volume curve the wizard previews.
  static RunPlanOutline outline(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    config.validate(template: template);
    final consecutive =
        config.sessionsPerWeek <= 4 &&
        _hasThreeConsecutiveDays(config.availableDays);
    final needsHillAccess = template.key == 'hills' && !config.includeHills;
    if (template.style == RunPlanTemplateStyle.runWalk) {
      final schedule = _SessionBuilders._composeRunWalk(template, config);
      return RunPlanOutline(
        schedule: schedule,
        weeks: [
          for (var i = 0; i < schedule.length; i++)
            RunPlanWeekOutline(
              index: i,
              phase: RunPlanWeekPhase.build,
              weekKm: _WeekPlanner._materializedWeekKm(schedule[i]),
              longKm: _WeekPlanner._materializedLongKm(schedule[i]),
            ),
        ],
        readiness: RunPlanReadiness(
          startWeeklyKm: 0,
          currentWeeklyKm: config.currentWeeklyKm,
          peakLongKm: 0,
          requiredLongKm: 0,
          longRunCapKm: 0,
          baselineZero: false,
          consecutiveDays: consecutive,
          optimisticGoal: config.hasOptimisticGoal,
        ),
      );
    }
    final goalMeters = _WeekPlanner._goalDistanceMeters(template.goalKind);
    final timing = _timingFor(template, config, goalMeters);
    final ramp = paceRamp(template, config);
    final composed = _WeekPlanner._composeRuns(template, config, timing, ramp);
    final schedule = composed.schedule;
    final book = _PaceBook.forWeek(
      ramp,
      0,
      goalMeters ?? RunPaceCalculator.tenKMeters,
      config.text,
    );
    final training = schedule.where(
      (week) => !week.any((session) => session.kind == RunWorkoutKind.race),
    );
    final peakLong = training.fold<double>(0, (peak, week) {
      final longest = week.fold<double>(
        0,
        (value, session) =>
            math.max(value, (session.targetDistanceMeters ?? 0) / 1000),
      );
      return math.max(peak, longest);
    });
    final required = _requiredPeakLongKm(template.goalKind, goalMeters);
    final longCap = _WeekPlanner._longRunCapKm(template.goalKind, book);
    final firstWeek = schedule.isEmpty
        ? const <RunPlanTemplateWorkout>[]
        : schedule.first;
    return RunPlanOutline(
      schedule: schedule,
      weeks: composed.weeks,
      paceRamp: ramp,
      startWeek: timing.startWeek,
      readiness: RunPlanReadiness(
        startWeeklyKm: _WeekPlanner._materializedWeekKm(firstWeek),
        currentWeeklyKm: config.currentWeeklyKm,
        peakLongKm: peakLong,
        requiredLongKm: required,
        longRunCapKm: longCap,
        baselineZero: config.currentWeeklyKm == 0,
        consecutiveDays: consecutive,
        optimisticGoal:
            ramp.assessment == RunPlanGoalAssessment.ambitious ||
            ramp.assessment == RunPlanGoalAssessment.unrealistic,
        goalAssessment: ramp.assessment,
        raceTooSoon: timing.raceTooSoon,
        weeksToRace: timing.weeksToRace,
        minWeeks: timing.minWeeks,
        needsHillAccess: needsHillAccess,
        thinSessions:
            config.sessionsPerWeek > 3 &&
            firstWeek
                .where(
                  (s) =>
                      s.kind == RunWorkoutKind.easy ||
                      s.kind == RunWorkoutKind.recovery,
                )
                .any((s) => (s.targetDistanceMeters ?? 0) < 2000),
      ),
    );
  }

  /// Rough duration of [session] for the preview, in seconds: timed steps as
  /// written, distance steps at their target pace (or [easySecPerKm]). Null
  /// when nothing is known about the session.
  static int? estimateDurationSeconds(
    RunPlanTemplateWorkout session, {
    double? easySecPerKm,
  }) {
    final easy = easySecPerKm ?? 390;
    if (session.steps.isEmpty) {
      if (session.targetDurationSeconds != null) {
        return session.targetDurationSeconds;
      }
      final meters = session.targetDistanceMeters;
      if (meters == null) return null;
      return (meters / 1000 * (session.targetPaceSecPerKm ?? easy)).round();
    }
    var total = 0.0;
    for (final step in session.steps) {
      if (step.metric == RunIntervalMetric.time) {
        total += step.value * step.repeatCount;
        continue;
      }
      final min = step.targetPaceMinSecPerKm;
      final max = step.targetPaceMaxSecPerKm;
      final pace = min != null && max != null
          ? (min + max) / 2
          : min ?? max ?? easy;
      total += step.value / 1000 * pace * step.repeatCount;
    }
    return total.round();
  }

  /// Training paces week by week for [template] + [config].
  ///
  /// Paces start at current fitness and move towards the goal — never jump
  /// straight to it, which made week-1 intervals up to 20 s/km too fast. The
  /// rate of improvement is capped at what a runner of this level typically
  /// gains per week, so an ambitious goal shapes race-pace work around the
  /// time actually reachable, and the wizard says so.
  static RunPlanPaceRamp paceRamp(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    if (template.style == RunPlanTemplateStyle.runWalk) {
      return RunPlanPaceRamp.none;
    }
    final goalMeters = _WeekPlanner._goalDistanceMeters(template.goalKind);
    final timing = _timingFor(template, config, goalMeters);
    final taper = _WeekPlanner._taperWeekCount(
      template,
      timing.weeks,
      timing.hasRace,
    );
    final rampWeeks = math.max(
      1,
      timing.hasRace ? timing.weeks - 1 - taper : timing.weeks - 1,
    );
    double? vdotOf(RunPlanPaceCalibration? c) {
      if (c == null) return null;
      try {
        final v = c.vdot;
        return v.isFinite && v > 0 ? v : null;
      } catch (_) {
        return null;
      }
    }

    final fitness = vdotOf(config.currentFitness);
    final goal = vdotOf(config.goalTime);
    if (fitness == null && goal == null) return RunPlanPaceRamp.none;

    // Maintenance holds fitness: no progression, no goal chase.
    if (template.maintainFitness) {
      final hold = fitness ?? goal!;
      return RunPlanPaceRamp(
        startVdot: hold,
        targetVdot: hold,
        goalVdot: goal,
        rampWeeks: rampWeeks,
        assessment: RunPlanGoalAssessment.none,
      );
    }

    if (fitness == null) {
      // Only a goal: assume it is a reachable improvement and start the
      // athlete a realistic step below it, never above.
      final assumedGain = math.min(
        RunPlanPaceRamp.weeklyGain(goal!) * rampWeeks,
        3.0,
      );
      return RunPlanPaceRamp(
        startVdot: goal - assumedGain,
        targetVdot: goal,
        goalVdot: goal,
        rampWeeks: rampWeeks,
        assessment: RunPlanGoalAssessment.none,
      );
    }

    final rate = RunPlanPaceRamp.weeklyGain(fitness);
    final reachable = fitness + math.min(rate * rampWeeks, 5.0);
    if (goal == null) {
      // No goal typed: a PB plan still nudges paces up as fitness builds —
      // half the typical rate, so the prescription never outruns the body.
      final target = config.intent == RunPlanIntent.pb
          ? fitness + (reachable - fitness) * 0.5
          : fitness;
      return RunPlanPaceRamp(
        startVdot: fitness,
        targetVdot: target,
        goalVdot: null,
        rampWeeks: rampWeeks,
        assessment: RunPlanGoalAssessment.none,
      );
    }
    final perWeek = (goal - fitness) / rampWeeks;
    final assessment = perWeek <= rate
        ? RunPlanGoalAssessment.realistic
        : perWeek <= rate * 2
        ? RunPlanGoalAssessment.ambitious
        : RunPlanGoalAssessment.unrealistic;
    return RunPlanPaceRamp(
      startVdot: fitness,
      targetVdot: goal <= fitness ? fitness : math.min(goal, reachable),
      goalVdot: goal,
      rampWeeks: rampWeeks,
      assessment: assessment,
    );
  }

  /// Plan length and calendar position once a race date is known.
  static _Timing _timingFor(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    double? goalMeters,
  ) {
    final templateWeeks = template.maintainFitness
        ? (config.weeks ?? template.defaultSelectableWeeks)
        : template.continuousKm?.length ??
              template.performanceLongKm?.length ??
              template.schedule.length;
    final hasRace =
        !template.maintainFitness &&
        goalMeters != null &&
        (template.raceFinish ||
            template.style == RunPlanTemplateStyle.performance);
    // Compressing further than ~60% skips the base the later weeks stand on.
    final minWeeks = math.min(
      templateWeeks,
      math.max(4, (templateWeeks * 0.6).ceil()),
    );
    final raceDate = config.raceDate;
    final remaining = config.remainingWeeks;
    if (!hasRace || raceDate == null) {
      // Re-planning an active plan: the ladder's last [remaining] weeks, so
      // the plan keeps its end and its race-specific block. Asking for more
      // weeks than are left re-runs earlier ladder weeks (missed weeks are
      // rebuilt, not skipped).
      final weeks = remaining == null
          ? templateWeeks
          : template.maintainFitness
          ? math.max(1, remaining)
          : remaining.clamp(1, templateWeeks);
      return _Timing(
        templateWeeks: templateWeeks,
        skip: template.maintainFitness ? 0 : templateWeeks - weeks,
        weeks: weeks,
        hasRace: hasRace,
        minWeeks: minWeeks,
      );
    }
    // From Friday on, what is left of this week cannot hold a training
    // week, so week 1 is next week.
    final today = config.startDate ?? DateTime.now();
    final start = weekStartOf(
      today,
    ).add(Duration(days: today.weekday >= DateTime.friday ? 7 : 0));
    final raceWeek = weekStartOf(raceDate);
    final weeksToRace = (raceWeek.difference(start).inDays / 7).round() + 1;
    if (weeksToRace >= templateWeeks) {
      // More runway than the plan needs: start later so race week lands on
      // the race, instead of racing in the middle of a build.
      return _Timing(
        templateWeeks: templateWeeks,
        skip: 0,
        weeks: templateWeeks,
        hasRace: true,
        minWeeks: minWeeks,
        weeksToRace: weeksToRace,
        startWeek: raceWeek.subtract(Duration(days: 7 * (templateWeeks - 1))),
        raceWeekday: raceDate.weekday,
      );
    }
    // A plan being re-planned mid-way must still end on the race, even when
    // that leaves less than the usual minimum — the athlete is already in it.
    final weeks = remaining != null
        ? math.max(1, math.min(weeksToRace, templateWeeks))
        : math.max(weeksToRace, minWeeks);
    return _Timing(
      templateWeeks: templateWeeks,
      skip: templateWeeks - weeks,
      weeks: weeks,
      hasRace: true,
      minWeeks: minWeeks,
      weeksToRace: weeksToRace,
      startWeek: weeksToRace >= minWeeks || remaining != null
          ? start
          : raceWeek.subtract(Duration(days: 7 * (weeks - 1))),
      raceWeekday: raceDate.weekday,
      raceTooSoon: weeksToRace < minWeeks,
    );
  }

  /// Monday of the week containing [date].
  static DateTime weekStartOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// How long the longest training run must get for the race to be safe.
  ///
  /// 5K: ~80% (4 km) — a runner who holds 4 km easy finishes a 5K; couch-to-
  /// 5K programmes never go longer. 10K: ~85% (8.5 km). Half: ~80% (17 km).
  /// Marathon: ~65% (27 km) — mainstream novice plans peak at 30–32 km, but
  /// 26–29 km is the accepted floor below which the last 10 km become a
  /// gamble.
  static double _requiredPeakLongKm(RunPlanGoalKind goal, double? goalMeters) {
    if (goalMeters == null) return 0;
    final raceKm = goalMeters / 1000;
    return switch (goal) {
      RunPlanGoalKind.marathon => raceKm * 0.65,
      RunPlanGoalKind.half => raceKm * 0.80,
      RunPlanGoalKind.tenK => raceKm * 0.85,
      RunPlanGoalKind.fiveK => raceKm * 0.80,
      _ => raceKm,
    };
  }

  static bool _hasThreeConsecutiveDays(List<int> days) {
    final set = days.toSet();
    for (final d in set) {
      final next = d % 7 + 1, after = next % 7 + 1;
      if (set.contains(next) && set.contains(after)) return true;
    }
    return false;
  }
}
