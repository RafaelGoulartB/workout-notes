import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_build_config.dart';

/// Training paces for every week: they start at current fitness and move
/// towards the reachable goal, instead of freezing on the day of creation.
class RunPlanPaceRamp {
  /// Fitness the plan opens with, or null when uncalibrated.
  final double? startVdot;

  /// Fitness the plan aims to reach by the end of the build.
  final double? targetVdot;

  /// Fitness the typed goal time implies, when there is one.
  final double? goalVdot;

  /// Weeks over which paces move from [startVdot] to [targetVdot].
  final int rampWeeks;
  final RunPlanGoalAssessment assessment;

  const RunPlanPaceRamp({
    required this.startVdot,
    required this.targetVdot,
    required this.goalVdot,
    required this.rampWeeks,
    required this.assessment,
  });

  static const none = RunPlanPaceRamp(
    startVdot: null,
    targetVdot: null,
    goalVdot: null,
    rampWeeks: 1,
    assessment: RunPlanGoalAssessment.none,
  );

  bool get calibrated => startVdot != null;

  /// VDOT a runner can typically bank per week of consistent training.
  /// Newer (slower) runners improve faster than trained ones.
  static double weeklyGain(double vdot) => vdot < 40
      ? 0.35
      : vdot < 50
      ? 0.25
      : 0.15;

  /// Fitness at zero-based [week]: linear from start to target over
  /// [rampWeeks], then held through taper and race week.
  double? vdotAt(int week) {
    final start = startVdot, target = targetVdot;
    if (start == null || target == null) return null;
    final progress = (week / rampWeeks).clamp(0.0, 1.0);
    return start + (target - start) * progress;
  }

  RunPaces? pacesAt(int week) {
    final vdot = vdotAt(week);
    return vdot == null ? null : RunPaceCalculator.fromVdot(vdot);
  }

  /// Paces the plan aims at — race-pace work and the race itself.
  RunPaces? get targetPaces {
    final target = targetVdot;
    return target == null ? null : RunPaceCalculator.fromVdot(target);
  }

  /// Predicted finish at [distanceMeters] for the target fitness.
  int? projectedSeconds(double distanceMeters) {
    final target = targetVdot;
    if (target == null) return null;
    return (RunPaceCalculator.racePaceFor(target, distanceMeters) *
            distanceMeters /
            1000)
        .round();
  }
}

/// Result of [RunPlanComposer.assess]: what the wizard should warn about.
class RunPlanReadiness {
  /// Volume the plan opens with, in km.
  final double startWeeklyKm;

  /// What the athlete said they run today, when they filled it in.
  final double? currentWeeklyKm;

  /// Longest training run the plan reaches before race week.
  final double peakLongKm;

  /// Longest run the goal distance demands (0 when there is no race).
  final double requiredLongKm;

  /// Distance allowed by the time-on-feet ceiling for this athlete.
  final double longRunCapKm;

  /// The athlete explicitly reported no current running volume.
  final bool baselineZero;

  /// Three running days in a row on a 3–4 day week.
  final bool consecutiveDays;

  /// Goal time is far faster than known fitness; training paces stay on
  /// current fitness. Does not block creation.
  final bool optimisticGoal;

  /// How the goal time compares with what this plan can deliver.
  final RunPlanGoalAssessment goalAssessment;

  /// The race date leaves fewer weeks than the plan can safely be compressed
  /// to. Blocks creation: the athlete needs a later race or a shorter plan.
  final bool raceTooSoon;

  /// Weeks between the start and the race date, when a race date is set.
  final int? weeksToRace;

  /// Fewest weeks this template can be compressed to.
  final int minWeeks;

  /// The template is built around hill work but the athlete has no hill,
  /// stairs or treadmill. Does not block: the sessions become flat work.
  final bool needsHillAccess;

  /// Week 1 volume is spread over so many days that runs get very short —
  /// fewer days would give runs worth lacing up for.
  final bool thinSessions;

  const RunPlanReadiness({
    required this.startWeeklyKm,
    required this.currentWeeklyKm,
    required this.peakLongKm,
    required this.requiredLongKm,
    required this.longRunCapKm,
    required this.baselineZero,
    required this.consecutiveDays,
    this.optimisticGoal = false,
    this.goalAssessment = RunPlanGoalAssessment.none,
    this.raceTooSoon = false,
    this.weeksToRace,
    this.minWeeks = 0,
    this.needsHillAccess = false,
    this.thinSessions = false,
  });

  /// Week 1 sits more than 25% above what the athlete runs today.
  bool get volumeGap {
    final current = currentWeeklyKm;
    return current != null && current > 0 && startWeeklyKm > current * 1.25;
  }

  /// The plan never gets the long run close enough to the race distance.
  bool get longRunShort =>
      requiredLongKm > 0 && peakLongKm < requiredLongKm - 0.5;

  /// The long-run safety ceiling itself prevents reaching the preparation
  /// floor. The ceiling remains valid; the race goal is what must change.
  bool get timeCapDistanceGap =>
      requiredLongKm > 0 && longRunCapKm < requiredLongKm - 0.5;

  bool get canCreate =>
      !baselineZero && !volumeGap && !longRunShort && !raceTooSoon;

  bool get ok => canCreate;
}

/// Periodisation of a composed week, for the customize-wizard sparkline.
enum RunPlanWeekPhase { build, recovery, taper, race }

/// Materialised week: phase plus the kilometres the athlete will actually run.
class RunPlanWeekOutline {
  final int index;
  final RunPlanWeekPhase phase;
  final double weekKm;
  final double longKm;

  const RunPlanWeekOutline({
    required this.index,
    required this.phase,
    required this.weekKm,
    required this.longKm,
  });
}

/// Full composed plan plus the week-by-week shape the wizard previews.
class RunPlanOutline {
  final List<List<RunPlanTemplateWorkout>> schedule;
  final List<RunPlanWeekOutline> weeks;
  final RunPlanReadiness readiness;

  /// Training paces week by week.
  final RunPlanPaceRamp paceRamp;

  /// Monday of plan week 1. Later than the start date when a race date is
  /// further away than the plan is long.
  final DateTime? startWeek;

  const RunPlanOutline({
    required this.schedule,
    required this.weeks,
    required this.readiness,
    this.paceRamp = RunPlanPaceRamp.none,
    this.startWeek,
  });

  List<RunPlanTemplateWorkout> get week1 =>
      schedule.isEmpty ? const [] : schedule.first;

  double get startWeeklyKm => readiness.startWeeklyKm;

  double get peakWeeklyKm {
    var peak = 0.0;
    for (final week in weeks) {
      if (week.phase == RunPlanWeekPhase.race) continue;
      if (week.weekKm > peak) peak = week.weekKm;
    }
    return peak;
  }

  double get peakLongKm => readiness.peakLongKm;

  /// 1-based week number of the race session, or null when there is none.
  int? get raceWeekNumber {
    for (final week in weeks) {
      if (week.phase == RunPlanWeekPhase.race) return week.index + 1;
    }
    return null;
  }

  bool get hasVolumeCurve => weeks.any((week) => week.weekKm >= 1);
}
