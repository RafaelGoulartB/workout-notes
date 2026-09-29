import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';

enum RunPlanTemplateCategory {
  gettingStarted,
  fiveK,
  tenK,
  half,
  marathon,
  conditioning,
}

enum RunPlanTemplateLevel { beginner, intermediate, advanced }

enum RunPlanTemplateStyle { continuous, performance, runWalk }

class RunPlanTemplateStep {
  final RunStepRole role;
  final RunIntervalMetric metric;
  final int value;
  final int? repeatGroup;
  final int repeatCount;
  final double? targetPaceMinSecPerKm;
  final double? targetPaceMaxSecPerKm;
  const RunPlanTemplateStep({
    required this.role,
    this.metric = RunIntervalMetric.distance,
    required this.value,
    this.repeatGroup,
    this.repeatCount = 1,
    this.targetPaceMinSecPerKm,
    this.targetPaceMaxSecPerKm,
  });
}

class RunPlanTemplateWorkout {
  final String name;
  final RunWorkoutKind kind;
  final int dayOfWeek;
  final String? notes;
  final String? effortZone;
  final double? targetDistanceMeters;
  final int? targetDurationSeconds;
  final double? targetPaceSecPerKm;
  final List<RunPlanTemplateStep> steps;
  const RunPlanTemplateWorkout({
    required this.name,
    required this.kind,
    required this.dayOfWeek,
    this.notes,
    this.effortZone,
    this.targetDistanceMeters,
    this.targetDurationSeconds,
    this.targetPaceSecPerKm,
    this.steps = const [],
  });
}

/// A complete progressive template. Every entry in [schedule] is one week.
///
/// Blueprint fields ([continuousKm], [performanceLongKm], …) feed
/// [RunPlanComposer] when the user customises days / intensity / paces.
class RunPlanTemplate {
  final String key;
  final RunPlanGoalKind goalKind;
  final RunPlanTemplateCategory category;
  final RunPlanTemplateLevel level;
  final RunPlanTemplateStyle style;
  final String titlePt,
      titleEn,
      descriptionPt,
      descriptionEn,
      prerequisitePt,
      prerequisiteEn;
  final List<List<RunPlanTemplateWorkout>> schedule;

  /// Weekly volume (km) the prerequisite text assumes the athlete already
  /// runs. When the wizard has no measured baseline the composer anchors
  /// week 1 here instead of starting at the template's full ladder.
  final double? prerequisiteWeeklyKm;

  /// Continuous / base ladders: each inner list is one week of km (last = long).
  final List<List<double>>? continuousKm;
  final bool raceFinish;

  /// Performance ladders.
  final List<double>? performanceLongKm;
  final double? performanceEasyKm;
  final int? performanceIntervalMeters;
  final int? performanceBaseReps;

  /// Run/walk ladders (seconds / reps per week).
  final List<int>? runWalkWork;
  final List<int>? runWalkRest;
  final List<int>? runWalkReps;

  const RunPlanTemplate({
    required this.key,
    required this.goalKind,
    required this.category,
    required this.level,
    required this.style,
    required this.titlePt,
    required this.titleEn,
    required this.descriptionPt,
    required this.descriptionEn,
    required this.prerequisitePt,
    required this.prerequisiteEn,
    required this.schedule,
    this.prerequisiteWeeklyKm,
    this.continuousKm,
    this.raceFinish = false,
    this.performanceLongKm,
    this.performanceEasyKm,
    this.performanceIntervalMeters,
    this.performanceBaseReps,
    this.runWalkWork,
    this.runWalkRest,
    this.runWalkReps,
    this.allowedWeeks = const [],
  });
  List<RunPlanTemplateWorkout> get week => schedule.first;
  int get sessionsPerWeek =>
      schedule.fold(0, (max, value) => value.length > max ? value.length : max);
  String title(bool pt) => pt ? titlePt : titleEn;
  String description(bool pt) => pt ? descriptionPt : descriptionEn;
  String prerequisite(bool pt) => pt ? prerequisitePt : prerequisiteEn;

  /// When non-empty, the customize wizard lets the athlete pick plan length
  /// and the composer expands the blueprint into that many varied weeks.
  final List<int> allowedWeeks;

  bool get selectableWeeks => allowedWeeks.isNotEmpty;

  /// Flat-volume “keep what you have” plans — no race build or taper.
  bool get maintainFitness => key == 'keep_fit';

  /// Default length when the wizard has not picked yet (also used by tests /
  /// catalog when [RunPlanBuildConfig.weeks] is omitted).
  int get defaultSelectableWeeks {
    if (!selectableWeeks) return schedule.length;
    if (allowedWeeks.contains(8)) return 8;
    return allowedWeeks[allowedWeeks.length ~/ 2];
  }

  /// Display / catalog week count. Selectable plans report their default
  /// length; the composed schedule may differ once the athlete picks.
  int get weeks => selectableWeeks ? defaultSelectableWeeks : schedule.length;

  /// Suggested days/week choices for the customize wizard.
  ///
  /// Beginner and return progressions cap at four days: bone and tendon
  /// adaptation lags the cardiovascular system, so these runners gain little
  /// from a fifth impact day and take on avoidable injury risk.
  List<int> get allowedSessionsPerWeek {
    if (style == RunPlanTemplateStyle.runWalk ||
        key == 'return' ||
        key == 'return_injury' ||
        key == 'walk_jog' ||
        key == 'first_5k' ||
        key == 'habit_3x') {
      return const [3, 4];
    }
    return const [3, 4, 5];
  }

  /// Easy aerobic blocks that should not prescribe structured quality.
  bool get aerobicOnly =>
      key == 'base' || key == 'habit_3x' || key == 'trail_intro';

  /// Return-to-running (or post-injury) progressions that stay gentler longer.
  bool get returnStyle => key == 'return' || key == 'return_injury';
}

/// How much the athlete can run without stopping today — the first question
/// of the plan finder.
enum RunPlanExperience { none, fewMinutes, thirtyMinutes, fiveK, tenK, half }

/// What the athlete wants next — the second question of the plan finder.
enum RunPlanAim { habit, further, faster }
