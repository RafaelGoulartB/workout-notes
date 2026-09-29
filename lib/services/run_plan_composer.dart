import 'dart:math' as math;

import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_text.dart';

/// How hard the athlete wants to push weekly volume and quality load.
enum RunPlanIntensity { conservative, standard, aggressive }

/// Finish the distance vs chase a personal best.
///
/// Both intents keep evidence-based quality work (intervals, threshold, etc.).
/// [pb] loads quality harder; [finish] keeps the same stimulus mix at lower
/// intensity — all-easy plans are reserved for return-to-running intro weeks
/// and pure run/walk progressions.
enum RunPlanIntent { finish, pb }

/// A recent race (current fitness) vs a goal time the athlete wants to hit.
enum RunPlanPaceSource { recent, goal }

/// Where hill-type strength sessions can be run. Only meaningful while
/// [RunPlanBuildConfig.includeHills] is on; "flat only" is `includeHills:
/// false`.
enum RunPlanHillSurface { hill, stairs, treadmill }

/// How a goal time compares with what the plan can realistically deliver.
enum RunPlanGoalAssessment {
  /// No goal time, or no current fitness to compare it with.
  none,

  /// Reachable at a normal rate of improvement for this plan length.
  realistic,

  /// Needs up to twice the typical rate of improvement. Training aims at the
  /// reachable time; the athlete is told.
  ambitious,

  /// Needs more than twice the typical rate. Training aims at the reachable
  /// time; the athlete should pick a longer runway or a softer goal.
  unrealistic,
}

/// Optional pace calibration from a recent race or a goal time.
class RunPlanPaceCalibration {
  final double distanceMeters;
  final int timeSeconds;

  const RunPlanPaceCalibration({
    required this.distanceMeters,
    required this.timeSeconds,
  });

  RunPaces get paces => RunPaceCalculator.fromRace(
    distanceMeters: distanceMeters,
    timeSeconds: timeSeconds,
  );

  double get vdot => RunPaceCalculator.vdotFor(
    distanceMeters: distanceMeters,
    timeSeconds: timeSeconds,
  );

  /// A 5 km-equivalent calibration for a fitness index.
  factory RunPlanPaceCalibration.fromVdot(
    double vdot,
  ) => RunPlanPaceCalibration(
    distanceMeters: RunPaceCalculator.fiveKMeters,
    timeSeconds:
        (RunPaceCalculator.racePaceFor(vdot, RunPaceCalculator.fiveKMeters) * 5)
            .round(),
  );

  Map<String, dynamic> toJson() => {'m': distanceMeters, 's': timeSeconds};

  static RunPlanPaceCalibration? fromJson(Object? json) {
    if (json is! Map) return null;
    final m = (json['m'] as num?)?.toDouble();
    final s = (json['s'] as num?)?.toInt();
    if (m == null || s == null || m <= 0 || s <= 0) return null;
    return RunPlanPaceCalibration(distanceMeters: m, timeSeconds: s);
  }
}

const Object _unset = Object();

/// Inputs collected by the customize wizard before materialising a plan.
class RunPlanBuildConfig {
  /// 3, 4 or 5 sessions per week.
  final int sessionsPerWeek;

  /// ISO weekdays (1=Mon … 7=Sun). Length must equal [sessionsPerWeek].
  final List<int> availableDays;

  final RunPlanIntent intent;
  final RunPlanIntensity intensity;

  /// The time the athlete typed — a recent race or a goal, per [paceSource].
  final RunPlanPaceCalibration? calibration;
  final RunPlanPaceSource paceSource;

  /// Current fitness from a recorded (or typed) recent race. Used when
  /// [paceSource] is a goal, so training starts from where the athlete is.
  final RunPlanPaceCalibration? fitnessCalibration;

  /// Goal time when [paceSource] is the recent race.
  final RunPlanPaceCalibration? goalCalibration;
  final DateTime? raceDate;

  /// First day the athlete can start (defaults to today). With a [raceDate]
  /// this decides how many weeks the plan actually has.
  final DateTime? startDate;

  /// Whether hill sessions may be prescribed. When false, the same training
  /// slot becomes flat work.
  final bool includeHills;

  /// Where hill sessions happen when [includeHills] is on.
  final RunPlanHillSurface hillSurface;

  /// Preferred long-run weekday. Must be one of [availableDays].
  final int? longRunDay;

  /// What the athlete actually runs today, in km/week.
  ///
  /// A jump in workload relative to what the body is used to is the strongest
  /// modifiable predictor of running injury, so when this is known week 1 is
  /// anchored to it and the whole ladder shifts with it.
  final double? currentWeeklyKm;

  /// Plan length override for templates with [RunPlanTemplate.selectableWeeks].
  /// Ignored for fixed-length templates.
  final int? weeks;

  /// Compose only the last [remainingWeeks] weeks of the template ladder —
  /// used when an active plan is re-planned mid-way (missed weeks, new
  /// fitness). More weeks than the ladder has from the current point re-runs
  /// earlier template weeks; fewer compresses. A race date still wins.
  final int? remainingWeeks;

  /// Language session names and notes are written in.
  final RunPlanLanguage language;

  /// Two short runner-specific strength sessions a week.
  final bool includeStrength;

  /// A mid-plan time trial in the first recovery week, to recalibrate paces.
  final bool includeTest;

  const RunPlanBuildConfig({
    required this.sessionsPerWeek,
    required this.availableDays,
    this.intent = RunPlanIntent.finish,
    this.intensity = RunPlanIntensity.standard,
    this.calibration,
    this.paceSource = RunPlanPaceSource.goal,
    this.fitnessCalibration,
    this.goalCalibration,
    this.raceDate,
    this.startDate,
    this.currentWeeklyKm,
    this.includeHills = true,
    this.hillSurface = RunPlanHillSurface.hill,
    this.longRunDay,
    this.weeks,
    this.remainingWeeks,
    this.language = RunPlanLanguage.pt,
    this.includeStrength = false,
    this.includeTest = true,
  });

  RunPlanText get text => RunPlanText.of(language);

  /// Copy with the fields re-planning changes.
  RunPlanBuildConfig copyWith({
    RunPlanPaceCalibration? calibration,
    RunPlanPaceSource? paceSource,
    Object? goalCalibration = _unset,
    Object? currentWeeklyKm = _unset,
    RunPlanIntensity? intensity,
    Object? startDate = _unset,
    Object? remainingWeeks = _unset,
    bool? includeTest,
  }) => RunPlanBuildConfig(
    sessionsPerWeek: sessionsPerWeek,
    availableDays: availableDays,
    intent: intent,
    intensity: intensity ?? this.intensity,
    calibration: calibration ?? this.calibration,
    paceSource: paceSource ?? this.paceSource,
    fitnessCalibration: fitnessCalibration,
    goalCalibration: identical(goalCalibration, _unset)
        ? this.goalCalibration
        : goalCalibration as RunPlanPaceCalibration?,
    raceDate: raceDate,
    startDate: identical(startDate, _unset)
        ? this.startDate
        : startDate as DateTime?,
    currentWeeklyKm: identical(currentWeeklyKm, _unset)
        ? this.currentWeeklyKm
        : currentWeeklyKm as double?,
    includeHills: includeHills,
    hillSurface: hillSurface,
    longRunDay: longRunDay,
    weeks: weeks,
    remainingWeeks: identical(remainingWeeks, _unset)
        ? this.remainingWeeks
        : remainingWeeks as int?,
    language: language,
    includeStrength: includeStrength,
    includeTest: includeTest ?? this.includeTest,
  );

  /// Stored on the plan so it can be re-planned later. Transient inputs
  /// ([startDate], [remainingWeeks]) are not persisted.
  Map<String, dynamic> toJson() => {
    'v': 1,
    'sessionsPerWeek': sessionsPerWeek,
    'availableDays': availableDays,
    'intent': intent.name,
    'intensity': intensity.name,
    'calibration': calibration?.toJson(),
    'paceSource': paceSource.name,
    'fitnessCalibration': fitnessCalibration?.toJson(),
    'goalCalibration': goalCalibration?.toJson(),
    'raceDate': raceDate?.toIso8601String().substring(0, 10),
    'currentWeeklyKm': currentWeeklyKm,
    'includeHills': includeHills,
    'hillSurface': hillSurface.name,
    'longRunDay': longRunDay,
    'weeks': weeks,
    'language': language.code,
    'includeStrength': includeStrength,
    'includeTest': includeTest,
  };

  /// Null for anything that does not describe a valid config.
  static RunPlanBuildConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      T byName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
          values.firstWhere((v) => v.name == raw, orElse: () => fallback);
      final days = (json['availableDays'] as List).cast<num>().map(
        (d) => d.toInt(),
      );
      return RunPlanBuildConfig(
        sessionsPerWeek: (json['sessionsPerWeek'] as num).toInt(),
        availableDays: days.toList(),
        intent: byName(
          RunPlanIntent.values,
          json['intent'],
          RunPlanIntent.finish,
        ),
        intensity: byName(
          RunPlanIntensity.values,
          json['intensity'],
          RunPlanIntensity.standard,
        ),
        calibration: RunPlanPaceCalibration.fromJson(json['calibration']),
        paceSource: byName(
          RunPlanPaceSource.values,
          json['paceSource'],
          RunPlanPaceSource.goal,
        ),
        fitnessCalibration: RunPlanPaceCalibration.fromJson(
          json['fitnessCalibration'],
        ),
        goalCalibration: RunPlanPaceCalibration.fromJson(
          json['goalCalibration'],
        ),
        raceDate: json['raceDate'] == null
            ? null
            : DateTime.tryParse(json['raceDate'] as String),
        currentWeeklyKm: (json['currentWeeklyKm'] as num?)?.toDouble(),
        includeHills: json['includeHills'] as bool? ?? true,
        hillSurface: byName(
          RunPlanHillSurface.values,
          json['hillSurface'],
          RunPlanHillSurface.hill,
        ),
        longRunDay: (json['longRunDay'] as num?)?.toInt(),
        weeks: (json['weeks'] as num?)?.toInt(),
        language: RunPlanLanguage.fromCode(json['language'] as String?),
        includeStrength: json['includeStrength'] as bool? ?? false,
        includeTest: json['includeTest'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }

  double get volumeFactor => switch (intensity) {
    RunPlanIntensity.conservative => 0.85,
    RunPlanIntensity.standard => 1.0,
    RunPlanIntensity.aggressive => 1.15,
  };

  /// Where the athlete is today, when known.
  RunPlanPaceCalibration? get currentFitness =>
      paceSource == RunPlanPaceSource.recent ? calibration : fitnessCalibration;

  /// Where the athlete wants to be on race day, when given.
  RunPlanPaceCalibration? get goalTime =>
      paceSource == RunPlanPaceSource.goal ? calibration : goalCalibration;

  /// Goal time is much faster than known fitness — training paces must not
  /// follow it.
  bool get hasOptimisticGoal {
    final goal = goalTime;
    final fitness = currentFitness;
    if (goal == null || fitness == null) return false;
    try {
      return RunPaceCalculator.isOptimisticGoal(
        fitness: fitness.paces,
        goalDistanceMeters: goal.distanceMeters,
        goalTimeSeconds: goal.timeSeconds,
      );
    } catch (_) {
      return false;
    }
  }

  /// Quality load multiplier (reps / tempo minutes). Finish is still quality,
  /// just gentler — matching polarized training, not junk mileage.
  double get qualityFactor => switch ((intent, intensity)) {
    (RunPlanIntent.finish, RunPlanIntensity.conservative) => 0.75,
    (RunPlanIntent.finish, _) => 0.85,
    (RunPlanIntent.pb, RunPlanIntensity.aggressive) => 1.15,
    (RunPlanIntent.pb, RunPlanIntensity.conservative) => 0.9,
    (RunPlanIntent.pb, _) => 1.0,
  };

  void validate({RunPlanTemplate? template}) {
    if (sessionsPerWeek < 3 || sessionsPerWeek > 5) {
      throw ArgumentError('sessionsPerWeek must be 3, 4 or 5');
    }
    if (availableDays.length != sessionsPerWeek) {
      throw ArgumentError('availableDays length must match sessionsPerWeek');
    }
    final unique = availableDays.toSet();
    if (unique.length != availableDays.length) {
      throw ArgumentError('availableDays must be unique');
    }
    for (final day in availableDays) {
      if (day < 1 || day > 7) {
        throw ArgumentError('availableDays must be ISO weekdays 1–7');
      }
    }
    if (longRunDay != null && !availableDays.contains(longRunDay)) {
      throw ArgumentError('longRunDay must be one of availableDays');
    }
    if (currentWeeklyKm != null && currentWeeklyKm! < 0) {
      throw ArgumentError('currentWeeklyKm must be positive');
    }
    if (template != null && template.selectableWeeks) {
      if (weeks != null && !template.allowedWeeks.contains(weeks)) {
        throw ArgumentError(
          'weeks must be one of ${template.allowedWeeks} for ${template.key}',
        );
      }
    }
  }
}

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

/// Where a week sits in the periodisation.
enum _Phase { build, recovery, taper, race }

/// Internal session roles. Quality roles map onto [RunWorkoutKind] variety
/// used in evidence-based programs (VO2, threshold, neuromuscular, hills).
enum _SessionRole {
  interval,
  tempo,
  fartlek,
  hills,
  progression,

  /// Blocks at goal race pace — the specificity stimulus.
  racePace,

  /// Short pre-race sharpener: a handful of race-pace reps, nothing more.
  sharpen,
  easy,
  recovery,
  long,

  /// Long run carrying goal-pace blocks (half / marathon specificity).
  longRacePace,
  race,

  /// Mid-plan time trial that recalibrates the paces.
  test,
}

bool _isQualityRole(_SessionRole role) =>
    role == _SessionRole.test ||
    role == _SessionRole.interval ||
    role == _SessionRole.tempo ||
    role == _SessionRole.fartlek ||
    role == _SessionRole.hills ||
    role == _SessionRole.progression ||
    role == _SessionRole.racePace ||
    role == _SessionRole.sharpen;

bool _isLongRole(_SessionRole role) =>
    role == _SessionRole.long ||
    role == _SessionRole.longRacePace ||
    role == _SessionRole.race;

/// Pace targets plus safe fallbacks for volume accounting.
///
/// The nullable getters are *prescriptions* and stay null when the athlete
/// skipped calibration — the plan then runs on effort zones only. The `est*`
/// getters always return a number because the composer has to convert
/// time-based work into kilometres to balance weekly volume.
class _PaceBook {
  final RunPaces? training;
  final RunPaces? race;
  final double goalMeters;

  /// Language the sessions built from this book are written in. Every
  /// session builder already receives the book, so it rides along here.
  final RunPlanText text;

  const _PaceBook({
    required this.training,
    required this.race,
    required this.goalMeters,
    required this.text,
  });

  /// Paces for zero-based [week]: training follows the ramp, race-pace work
  /// aims at the reachable target for the whole plan.
  factory _PaceBook.forWeek(
    RunPlanPaceRamp ramp,
    int week,
    double goalMeters,
    RunPlanText text,
  ) => _PaceBook(
    training: ramp.pacesAt(week),
    race: ramp.targetPaces,
    goalMeters: goalMeters,
    text: text,
  );

  double? get easy => training?.easySecPerKm;
  double? get easyFast => training?.easyFastSecPerKm;
  double? get easySlow => training?.easySlowSecPerKm;
  double? get tempo => training?.tempoSecPerKm;
  double? get interval => training?.intervalSecPerKm;
  double? get repetition => training?.repetitionSecPerKm;

  /// Race pace for the distance this plan targets — never the calibration pace.
  double? get goalRace => (race ?? training)?.racePaceFor(goalMeters);

  double get estEasy => training?.easySecPerKm ?? 390;
  double get estTempo => training?.tempoSecPerKm ?? 320;
  double get estInterval => training?.intervalSecPerKm ?? 295;

  bool get calibrated => training != null || race != null;

  /// `6:11–6:57/km` for the easy window, or null when uncalibrated.
  String? get easyWindowLabel {
    final fast = easyFast, slow = easySlow;
    if (fast == null || slow == null) return null;
    return '${_paceText(fast)}–${_paceText(slow)}/km';
  }
}

String _paceText(double secPerKm) {
  final total = secPerKm.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// One planned week: periodisation phase, volume budget and session roles.
class _WeekPlan {
  final int index;
  final _Phase phase;
  final double weekKm;
  final double longKm;
  final List<_SessionRole> roles;

  /// 0..1 position in the plan — drives how long interval reps get.
  final double progress;

  const _WeekPlan({
    required this.index,
    required this.phase,
    required this.weekKm,
    required this.longKm,
    required this.roles,
    this.progress = 0,
  });

  _WeekPlan copyWith({double? weekKm, double? longKm}) => _WeekPlan(
    index: index,
    phase: phase,
    weekKm: weekKm ?? this.weekKm,
    longKm: longKm ?? this.longKm,
    roles: roles,
    progress: progress,
  );
}

/// Plan length and calendar position.
class _Timing {
  /// Weeks in the template ladder.
  final int templateWeeks;

  /// Leading template weeks dropped to fit a near race date.
  final int skip;

  /// Weeks actually composed.
  final int weeks;
  final bool hasRace;
  final int minWeeks;
  final int? weeksToRace;
  final DateTime? startWeek;

  /// ISO weekday of the race, when a race date is set.
  final int? raceWeekday;
  final bool raceTooSoon;

  const _Timing({
    required this.templateWeeks,
    required this.skip,
    required this.weeks,
    required this.hasRace,
    required this.minWeeks,
    this.weeksToRace,
    this.startWeek,
    this.raceWeekday,
    this.raceTooSoon = false,
  });
}

/// Weekday slots held stable for the whole plan.
class _DaySlots {
  final int longDay;
  final List<int> qualityDays;
  final List<int> easyDays;

  const _DaySlots({
    required this.longDay,
    required this.qualityDays,
    required this.easyDays,
  });
}

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
      final schedule = _composeRunWalk(template, config);
      return RunPlanOutline(
        schedule: schedule,
        weeks: [
          for (var i = 0; i < schedule.length; i++)
            RunPlanWeekOutline(
              index: i,
              phase: RunPlanWeekPhase.build,
              weekKm: _materializedWeekKm(schedule[i]),
              longKm: _materializedLongKm(schedule[i]),
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
    final goalMeters = _goalDistanceMeters(template.goalKind);
    final timing = _timingFor(template, config, goalMeters);
    final ramp = paceRamp(template, config);
    final composed = _composeRuns(template, config, timing, ramp);
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
    final longCap = _longRunCapKm(template.goalKind, book);
    final firstWeek = schedule.isEmpty
        ? const <RunPlanTemplateWorkout>[]
        : schedule.first;
    return RunPlanOutline(
      schedule: schedule,
      weeks: composed.weeks,
      paceRamp: ramp,
      startWeek: timing.startWeek,
      readiness: RunPlanReadiness(
        startWeeklyKm: _materializedWeekKm(firstWeek),
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
    final goalMeters = _goalDistanceMeters(template.goalKind);
    final timing = _timingFor(template, config, goalMeters);
    final taper = _taperWeekCount(template, timing.weeks, timing.hasRace);
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

  // --- Planning ------------------------------------------------------------

  static ({
    List<List<RunPlanTemplateWorkout>> schedule,
    List<RunPlanWeekOutline> weeks,
  })
  _composeRuns(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    _Timing timing,
    RunPlanPaceRamp ramp,
  ) {
    final goalMeters = _goalDistanceMeters(template.goalKind);
    final paceMeters = goalMeters ?? RunPaceCalculator.tenKMeters;
    // Volume caps are sized on week-1 paces: the slower (safer) end of the
    // ramp, so a long run never grows because fitness is *expected* to.
    final weeks = _planWeeks(
      template,
      config,
      _PaceBook.forWeek(ramp, 0, paceMeters, config.text),
      goalMeters,
      timing,
    );
    final slots = _assignSlots(
      available: config.availableDays,
      qualitySlots: _qualitySlotCount(template, config),
      preferredLongDay: config.longRunDay,
    );

    List<RunPlanTemplateWorkout> build(_WeekPlan week) => _buildWeek(
      template: template,
      config: config,
      book: _PaceBook.forWeek(ramp, week.index, paceMeters, config.text),
      slots: slots,
      week: week,
      raceWeekday: timing.raceWeekday,
    );

    final result = <List<RunPlanTemplateWorkout>>[];
    final outlines = <RunPlanWeekOutline>[];
    var lastBuildActual = 0.0;
    var lastBuildLong = 0.0;
    for (final planned in weeks) {
      var week = planned;
      if (week.phase == _Phase.build &&
          lastBuildLong > 0 &&
          week.longKm > lastBuildLong + 3.0) {
        week = week.copyWith(longKm: lastBuildLong + 3.0);
      }
      var built = build(week);

      // The physiological growth cap applies to delivered kilometres, not to
      // an internal budget. Recovery weeks deliberately do not replace the
      // last build reference, so the next build returns to the pre-recovery
      // line instead of treating the down week as lost fitness.
      if (week.phase == _Phase.build && lastBuildActual > 0) {
        final cap = lastBuildActual * 1.10;
        // Session floors do not scale, so one rescale may not land under the
        // cap; a few passes converge.
        for (var pass = 0; pass < 8; pass++) {
          final delivered = _materializedWeekKm(built);
          if (delivered <= cap + 0.05) break;
          // Scale from what was actually delivered. The planned budget can be
          // materially higher when a three-day schedule cannot distribute all
          // of a five-day template; using it as the denominator used to
          // over-correct and collapse subsequent weeks.
          final ratio = cap / delivered;
          week = week.copyWith(
            weekKm: pass == 0 ? cap : week.weekKm * ratio,
            longKm: math.min(week.longKm * ratio, week.longKm),
          );
          built = build(week);
        }
      }
      if (week.phase == _Phase.build) {
        lastBuildActual = _materializedWeekKm(built);
        lastBuildLong = _materializedLongKm(built);
      }
      result.add(built);
      outlines.add(
        RunPlanWeekOutline(
          index: week.index,
          phase: _publicPhase(week.phase),
          weekKm: _materializedWeekKm(built),
          longKm: _materializedLongKm(built),
        ),
      );
    }
    return (schedule: result, weeks: outlines);
  }

  static RunPlanWeekPhase _publicPhase(_Phase phase) => switch (phase) {
    _Phase.build => RunPlanWeekPhase.build,
    _Phase.recovery => RunPlanWeekPhase.recovery,
    _Phase.taper => RunPlanWeekPhase.taper,
    _Phase.race => RunPlanWeekPhase.race,
  };

  static double _materializedWeekKm(List<RunPlanTemplateWorkout> week) =>
      week.fold<double>(
        0,
        (sum, session) => sum + (session.targetDistanceMeters ?? 0) / 1000,
      );

  static double _materializedLongKm(List<RunPlanTemplateWorkout> week) =>
      week.fold<double>(
        0,
        (peak, session) =>
            math.max(peak, (session.targetDistanceMeters ?? 0) / 1000),
      );

  /// Phase, volume budget and roles for every week, in one pass.
  static List<_WeekPlan> _planWeeks(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    _PaceBook book,
    double? goalMeters,
    _Timing timing,
  ) {
    if (template.maintainFitness) {
      return _planMaintainWeeks(template, config, book, timing.weeks);
    }
    final continuous = template.continuousKm;
    // A near race date drops the first template weeks: the plan still ends on
    // the template's race-specific block, and week 1 is re-anchored below to
    // what the athlete runs today.
    final total = timing.weeks;
    final skip = timing.skip;
    final templateSessions = continuous != null
        ? continuous.first.length
        : template.sessionsPerWeek;

    final hasRace = timing.hasRace;
    final raceWeek = hasRace ? total - 1 : -1;
    final taperCount = _taperWeekCount(template, total, hasRace);
    final raceKm = (goalMeters ?? 0) / 1000;

    final sessionScale = math
        .sqrt(config.sessionsPerWeek / templateSessions)
        .clamp(0.8, 1.35);
    final maxLongShare = _maxLongShare(template, config.sessionsPerWeek);
    final longCap = _longRunCapKm(template.goalKind, book);
    final qualitySlots = _qualitySlotCount(template, config);

    double templateWeekKm(int w) => continuous != null
        ? continuous[w + skip].reduce((a, b) => a + b)
        : template.performanceLongKm![w + skip] +
              template.performanceEasyKm! * (templateSessions - 1);
    double templateLongKm(int w) => continuous != null
        ? continuous[w + skip].last
        : template.performanceLongKm![w + skip];

    // Anchor week 1 to what the athlete already runs — or, failing that, to
    // the volume the template assumes as its prerequisite — then ramp back to
    // the template's own ladder over the first ~60% of the plan. The start
    // matches the body; the peak still matches the race. In between, the 10%
    // build cap below decides how fast the gap actually closes.
    var anchor = 1.0;
    final measured = config.currentWeeklyKm;
    final baseline = measured ?? template.prerequisiteWeeklyKm;
    if (baseline != null && baseline > 0) {
      // A measured baseline *is* week 1, whatever the intensity choice. The
      // prerequisite fallback is only the template's assumption, so the
      // intensity choice still shifts it.
      // Week 1 is a build week, so it reads the ladder's running maximum
      // (see below) — the anchor must scale that same value.
      var ladder0 = 0.0;
      for (var t = -skip; t <= 0; t++) {
        ladder0 = math.max(ladder0, templateWeekKm(t));
      }
      final week0 =
          ladder0 *
          sessionScale *
          (measured != null ? config.volumeFactor : 1.0);
      if (week0 > 0) anchor = (baseline / week0).clamp(0.5, 1.5);
    }
    final rampWeeks = math.max(1, (total * 0.6).floor());
    double anchorAt(int w) =>
        anchor + (1 - anchor) * math.min(1.0, w / rampWeeks);

    // Raw targets. Weekly volume is the primary quantity; the long run has to
    // fit inside its share of the week. A long run that would need a much
    // bigger week than the template intends is shortened, not accommodated:
    // the week may stretch at most 15% to carry it.
    //
    // Build weeks read the ladder's running maximum. The template's own down
    // weeks line up with this plan's recovery weeks only when nothing is
    // skipped; once a near race date or a re-plan drops leading weeks, a
    // template dip would land on a build week and make it smaller than the
    // one before. Recovery here comes from the phases, not from the ladder.
    var ladderLong = 0.0, ladderWeek = 0.0;
    for (var t = 0; t < skip; t++) {
      ladderLong = math.max(ladderLong, templateLongKm(t - skip));
      ladderWeek = math.max(ladderWeek, templateWeekKm(t - skip));
    }
    final rawWeek = <double>[], rawLong = <double>[];
    for (var w = 0; w < total; w++) {
      final scale = config.volumeFactor * anchorAt(w);
      ladderLong = math.max(ladderLong, templateLongKm(w));
      ladderWeek = math.max(ladderWeek, templateWeekKm(w));
      final build =
          _phaseOf(weekIndex: w, raceWeek: raceWeek, taperCount: taperCount) ==
          _Phase.build;
      var long = math.min(
        (build ? ladderLong : templateLongKm(w)) * scale,
        longCap,
      );
      final templateWeek =
          (build ? ladderWeek : templateWeekKm(w)) * scale * sessionScale;
      final week = math.min(
        math.max(templateWeek, long / maxLongShare),
        templateWeek * 1.15,
      );
      long = math.min(long, maxLongShare * week);
      rawLong.add(long);
      rawWeek.add(week);
    }

    final plans = <_WeekPlan>[];
    var lastBuild = 0.0, peak = 0.0, peakLong = 0.0;

    for (var w = 0; w < total; w++) {
      final phase = _phaseOf(
        weekIndex: w,
        raceWeek: raceWeek,
        taperCount: taperCount,
      );

      double weekKm;
      switch (phase) {
        case _Phase.build:
          final cap = lastBuild == 0 ? rawWeek[w] : lastBuild * 1.10;
          weekKm = math.min(rawWeek[w], cap);
          lastBuild = weekKm;
          peak = math.max(peak, weekKm);
        case _Phase.recovery:
          final reference = lastBuild == 0 ? rawWeek[w] : lastBuild;
          weekKm = math.min(rawWeek[w], reference * 0.75);
        case _Phase.taper:
          final step = w - (raceWeek - taperCount);
          final factors = taperCount >= 2 ? const [0.75, 0.55] : const [0.70];
          weekKm = peak * factors[step.clamp(0, factors.length - 1)];
        case _Phase.race:
          // Support volume only — the race itself is added on top.
          weekKm = peak * 0.20 + raceKm;
      }

      double longKm;
      if (phase == _Phase.race) {
        longKm = raceKm;
      } else {
        longKm = math.min(rawLong[w], maxLongShare * weekKm);
        if (phase == _Phase.build) {
          // Long runs grow ~3 km at a time whatever the template ladder says.
          if (peakLong > 0) longKm = math.min(longKm, peakLong + 3.0);
          peakLong = math.max(peakLong, longKm);
        }
      }

      final hasQuality = _weekHasQuality(
        template: template,
        weekIndex: w,
        totalWeeks: total,
        phase: phase,
      );

      plans.add(
        _WeekPlan(
          index: w,
          phase: phase,
          weekKm: weekKm,
          longKm: longKm,
          roles: _rolesForWeek(
            template: template,
            config: config,
            weekIndex: w,
            totalWeeks: total,
            phase: phase,
            hasQuality: hasQuality,
            qualitySlots: qualitySlots,
          ),
          progress: total <= 1 ? 1 : w / (total - 1),
        ),
      );
    }
    return plans;
  }

  /// Flat-volume maintenance: hold the athlete's current fitness with varied
  /// weeks (quality rotation + light undulation), never a progressive ladder.
  static List<_WeekPlan> _planMaintainWeeks(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    _PaceBook book,
    int total,
  ) {
    final continuous = template.continuousKm!;
    final blueprint = continuous.first;
    final templateSessions = blueprint.length;
    final sessionScale = math
        .sqrt(config.sessionsPerWeek / templateSessions)
        .clamp(0.85, 1.25);
    final maxLongShare = _maxLongShare(template, config.sessionsPerWeek);
    final longCap = _longRunCapKm(template.goalKind, book);
    final qualitySlots = _qualitySlotCount(template, config);

    final blueprintWeek = blueprint.reduce((a, b) => a + b);
    final blueprintLong = blueprint.last;
    final steady =
        (config.currentWeeklyKm ??
            template.prerequisiteWeeklyKm ??
            blueprintWeek) *
        config.volumeFactor *
        sessionScale;
    final steadyLong = math.min(
      math.min(blueprintLong * (steady / blueprintWeek), longCap),
      maxLongShare * steady,
    );

    // Mild undulation keeps stimulus fresh without raising fitness demand.
    const buildLongFactors = [1.0, 1.06, 0.94];
    const buildWeekFactors = [1.0, 1.04, 0.96];

    final plans = <_WeekPlan>[];
    for (var w = 0; w < total; w++) {
      final recovery = w > 0 && w % 4 == 3;
      final phase = recovery ? _Phase.recovery : _Phase.build;
      final cycle = w % 3;
      final weekKm = recovery
          ? steady * 0.75
          : steady * buildWeekFactors[cycle];
      final longKm = math.min(
        recovery ? steadyLong * 0.85 : steadyLong * buildLongFactors[cycle],
        maxLongShare * weekKm,
      );
      final hasQuality = _weekHasQuality(
        template: template,
        weekIndex: w,
        totalWeeks: total,
        phase: phase,
      );
      plans.add(
        _WeekPlan(
          index: w,
          phase: phase,
          weekKm: weekKm,
          longKm: longKm,
          roles: _rolesForWeek(
            template: template,
            config: config,
            weekIndex: w,
            totalWeeks: total,
            phase: phase,
            hasQuality: hasQuality,
            qualitySlots: qualitySlots,
          ),
          progress: total <= 1 ? 1 : w / (total - 1),
        ),
      );
    }
    return plans;
  }

  static _Phase _phaseOf({
    required int weekIndex,
    required int raceWeek,
    required int taperCount,
  }) {
    if (weekIndex == raceWeek) return _Phase.race;
    if (raceWeek > 0 &&
        taperCount > 0 &&
        weekIndex >= raceWeek - taperCount &&
        weekIndex < raceWeek) {
      return _Phase.taper;
    }
    if (weekIndex > 0 && weekIndex % 4 == 3) return _Phase.recovery;
    return _Phase.build;
  }

  /// A marathon needs a longer taper than a 5K.
  static int _taperWeekCount(
    RunPlanTemplate template,
    int totalWeeks,
    bool hasRace,
  ) {
    if (!hasRace || totalWeeks < 5) return 0;
    return template.goalKind == RunPlanGoalKind.marathon && totalWeeks >= 12
        ? 2
        : 1;
  }

  /// Ceiling on the long run as a fraction of the week.
  ///
  /// Textbook guidance is 25–30%, but that assumes six or seven running days.
  /// On the 3–5 day weeks this app schedules — and in every mainstream novice
  /// marathon plan — the share is legitimately higher, so the cap is goal- and
  /// frequency-aware instead of one number.
  static double _maxLongShare(RunPlanTemplate template, int sessions) {
    final base = switch (template.style) {
      RunPlanTemplateStyle.runWalk => 0.50,
      RunPlanTemplateStyle.continuous => 0.45,
      RunPlanTemplateStyle.performance => switch (template.goalKind) {
        // Novice marathon plans (Higdon Novice 1: 32 km long in a 64 km,
        // 4-run week) legitimately run a 50% share.
        RunPlanGoalKind.marathon => 0.50,
        RunPlanGoalKind.half => 0.42,
        RunPlanGoalKind.tenK => 0.36,
        _ => 0.35,
      },
    };
    if (sessions <= 3) return base + 0.05;
    if (sessions >= 5) return base - 0.03;
    return base;
  }

  /// Absolute long-run ceiling, plus a duration ceiling once paces are known.
  ///
  /// Time on feet drives the cost of a long run, so a slower runner's long run
  /// is capped earlier in kilometres than a faster one's.
  static double _longRunCapKm(RunPlanGoalKind goal, _PaceBook book) {
    final distanceCap = switch (goal) {
      RunPlanGoalKind.marathon => 32.0,
      RunPlanGoalKind.half => 22.0,
      RunPlanGoalKind.tenK => 16.0,
      RunPlanGoalKind.fiveK => 12.0,
      _ => 14.0,
    };
    if (!book.calibrated) return distanceCap;
    final kmPerMinute = 60 / book.estEasy;
    if (goal == RunPlanGoalKind.marathon) {
      // Three hours keeps most runners out of the zone where damage outruns
      // adaptation. A slower runner may stretch to 3h30 — only as far as the
      // ~27 km preparation floor needs, never further. Without it, a typical
      // 2h10 half-marathoner could not create a first-marathon plan at all.
      final floorKm = _requiredPeakLongKm(
        goal,
        RunPaceCalculator.marathonMeters,
      );
      final allowed = math.min(
        math.max(180 * kmPerMinute, floorKm),
        210 * kmPerMinute,
      );
      return math.min(distanceCap, allowed);
    }
    return math.min(distanceCap, 150 * kmPerMinute);
  }

  /// How many dedicated quality weekdays to reserve for the whole plan.
  static int _qualitySlotCount(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    if (template.style == RunPlanTemplateStyle.runWalk) return 0;
    // Beginners adapt to consistency first. One controlled pace-change
    // session is enough even when they can run four or five days.
    if (template.level == RunPlanTemplateLevel.beginner) return 1;
    // Return-to-running: ease back with one stimulus only.
    if (template.returnStyle) return 1;
    // Finishing an endurance race rewards aerobic consistency more than a
    // second mid-week workout. Specific long runs count as the second stimulus.
    final endurance =
        template.goalKind == RunPlanGoalKind.half ||
        template.goalKind == RunPlanGoalKind.marathon;
    if (config.intent == RunPlanIntent.finish && endurance) return 1;
    if (config.sessionsPerWeek >= 4) return 2;
    return 1;
  }

  /// True when this week should include structured quality (not all-easy).
  static bool _weekHasQuality({
    required RunPlanTemplate template,
    required int weekIndex,
    required int totalWeeks,
    required _Phase phase,
  }) {
    if (template.style == RunPlanTemplateStyle.runWalk) return false;
    // This template promises an easy aerobic block. Strides can still be
    // attached to an easy run without turning it into structured quality.
    if (template.aerobicOnly) return false;
    // Race week keeps a short sharpener; a taper keeps full intensity.
    if (phase == _Phase.race || phase == _Phase.taper) return true;
    if (template.style == RunPlanTemplateStyle.performance) return true;
    // Maintain-fitness: quality from week 1 so stimulus variety starts immediately.
    if (template.maintainFitness) return phase == _Phase.build;

    // Continuous: short aerobic intro, then quality. Return stays gentler longer.
    final introWeeks = template.returnStyle
        ? (totalWeeks / 2).ceil().clamp(2, 4)
        : (totalWeeks / 4).ceil().clamp(1, 2);
    return weekIndex >= introWeeks;
  }

  /// Weekly shape: one long run, up to two quality days, the rest easy.
  static List<_SessionRole> _rolesForWeek({
    required RunPlanTemplate template,
    required RunPlanBuildConfig config,
    required int weekIndex,
    required int totalWeeks,
    required _Phase phase,
    required bool hasQuality,
    required int qualitySlots,
  }) {
    final sessions = config.sessionsPerWeek;
    final endurance =
        template.goalKind == RunPlanGoalKind.half ||
        template.goalKind == RunPlanGoalKind.marathon;
    // A runner who has not yet completed the distance (first 5K, return to
    // running) gets quality that teaches pace change and finishing — fartlek
    // and progression runs — never VO2 repeats or hill sprints. Those belong
    // in the performance templates that assume the distance is already won.
    final gentle =
        template.level == RunPlanTemplateLevel.beginner &&
        template.style == RunPlanTemplateStyle.continuous;
    final hasRace = _goalDistanceMeters(template.goalKind) != null;

    if (phase == _Phase.race) {
      // Nothing that needs recovering from: one short sharpener, an easy run,
      // then the race — plus a short shake-out on five-day weeks. The other
      // training days are rest: filling them with 15-minute runs used to push
      // a beginner's race week above their peak week.
      return [
        _SessionRole.sharpen,
        _SessionRole.easy,
        if (sessions >= 5) _SessionRole.recovery,
        _SessionRole.race,
      ];
    }

    if (!hasQuality) {
      return [
        for (var i = 0; i < sessions - 1; i++) _SessionRole.easy,
        _SessionRole.long,
      ];
    }

    if (phase == _Phase.taper) {
      // Keep the intensity, cut the volume: one quality session (shortened by
      // the volume budget) plus easy running. The taper is where the stimulus
      // becomes race-specific — goal-pace blocks, not hills or a tempo the
      // rotation happens to land on.
      return [
        hasRace
            ? _SessionRole.racePace
            : gentle
            ? _SessionRole.fartlek
            : _primaryQuality(
                template,
                config,
                weekIndex,
                endurance,
                qualitySlots: qualitySlots,
              ),
        for (var i = 0; i < sessions - 2; i++) _SessionRole.easy,
        _SessionRole.long,
      ];
    }

    if (phase == _Phase.recovery) {
      // The first down week is the natural checkpoint: legs are fresher, and
      // a time trial there tells the plan whether its paces still fit before
      // the heavier half begins.
      final test =
          weekIndex == 3 &&
          totalWeeks >= 8 &&
          config.includeTest &&
          !gentle &&
          !template.aerobicOnly &&
          !template.maintainFitness &&
          !template.returnStyle;
      final soft = test
          ? _SessionRole.test
          : gentle || weekIndex.isEven
          ? _SessionRole.fartlek
          : _SessionRole.tempo;
      return [
        soft,
        for (var i = 0; i < sessions - 2; i++)
          i == 0 ? _SessionRole.easy : _SessionRole.recovery,
        _SessionRole.long,
      ];
    }

    // Build week. Long runs pick up goal-pace blocks in the second half of an
    // endurance plan — the stimulus that actually transfers to race day.
    final specific = weekIndex >= (totalWeeks * 0.5).floor();
    final longRole = endurance && specific && weekIndex % 3 == 1
        ? _SessionRole.longRacePace
        : _SessionRole.long;

    final quality = <_SessionRole>[
      gentle
          ? _gentleQuality(weekIndex)
          : _primaryQuality(
              template,
              config,
              weekIndex,
              endurance,
              qualitySlots: qualitySlots,
            ),
    ];
    // A long run with race-pace blocks is already a load-bearing quality day.
    // Never combine it with two additional workouts in the same week.
    if (qualitySlots > 1 && longRole != _SessionRole.longRacePace) {
      quality.add(
        gentle
            ? _gentleQuality(weekIndex + 1)
            : specific && weekIndex.isEven
            ? _SessionRole.racePace
            : _secondaryQuality(template, weekIndex, endurance),
      );
    }

    final filler = sessions - 1 - quality.length;
    return [
      quality.first,
      for (var i = 0; i < filler; i++)
        i == 0 ? _SessionRole.easy : _SessionRole.recovery,
      if (quality.length > 1) quality[1],
      longRole,
    ];
  }

  /// Primary quality rotation. Endurance goals lean threshold-first; 5K/10K
  /// goals put the VO2max stimulus that limits them on a fixed beat so it can
  /// actually progress — a six-way rotation used to leave a 10-week "faster
  /// 5K" plan with two interval sessions in total.
  static _SessionRole _primaryQuality(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    int weekIndex,
    bool endurance, {
    required int qualitySlots,
  }) {
    if (template.key == 'hills') {
      return weekIndex.isEven ? _SessionRole.hills : _SessionRole.fartlek;
    }
    if (template.key == 'threshold_block') {
      return weekIndex % 3 == 2 ? _SessionRole.progression : _SessionRole.tempo;
    }
    if (endurance) {
      return const [
        _SessionRole.tempo,
        _SessionRole.interval,
        _SessionRole.tempo,
        _SessionRole.hills,
        _SessionRole.tempo,
        _SessionRole.fartlek,
      ][weekIndex % 6];
    }
    if (template.maintainFitness) {
      // Holding fitness wants variety, not a progressive VO2 block.
      return const [
        _SessionRole.interval,
        _SessionRole.tempo,
        _SessionRole.hills,
        _SessionRole.interval,
        _SessionRole.fartlek,
        _SessionRole.tempo,
      ][weekIndex % 6];
    }
    // Hills are the strength variant of VO2 work; without hill access the
    // slot stays an interval session rather than a softer fartlek.
    final hillsOk = config.includeHills;
    _SessionRole vo2(int i) =>
        i % 3 == 2 && hillsOk ? _SessionRole.hills : _SessionRole.interval;
    if (qualitySlots > 1) {
      // Two slots: VO2 every week here, threshold in the secondary slot.
      return vo2(weekIndex);
    }
    // One slot: alternate the two stimuli a 5K/10K is built on.
    return weekIndex.isEven
        ? vo2(weekIndex ~/ 2)
        : const [
            _SessionRole.tempo,
            _SessionRole.progression,
            _SessionRole.tempo,
          ][(weekIndex ~/ 2) % 3];
  }

  /// Beginner quality: alternate fartlek and progression — pace changes and a
  /// strong finish, both at controlled effort.
  static _SessionRole _gentleQuality(int weekIndex) =>
      weekIndex.isEven ? _SessionRole.fartlek : _SessionRole.progression;

  /// Second quality slot (4–5 day weeks) — complementary, not duplicate.
  static _SessionRole _secondaryQuality(
    RunPlanTemplate template,
    int weekIndex,
    bool endurance,
  ) {
    if (template.key == 'hills') {
      return weekIndex.isEven ? _SessionRole.tempo : _SessionRole.hills;
    }
    if (template.key == 'threshold_block') {
      return weekIndex.isEven ? _SessionRole.tempo : _SessionRole.racePace;
    }
    if (endurance) {
      return const [
        _SessionRole.fartlek,
        _SessionRole.racePace,
        _SessionRole.progression,
        _SessionRole.tempo,
        _SessionRole.racePace,
        _SessionRole.progression,
      ][weekIndex % 6];
    }
    if (template.maintainFitness) {
      return const [
        _SessionRole.tempo,
        _SessionRole.fartlek,
        _SessionRole.progression,
        _SessionRole.racePace,
        _SessionRole.tempo,
        _SessionRole.hills,
      ][weekIndex % 6];
    }
    // 5K/10K: the primary slot already carries VO2 work every week, so this
    // one is the threshold stimulus, with a fartlek for variety.
    return const [
      _SessionRole.tempo,
      _SessionRole.tempo,
      _SessionRole.fartlek,
      _SessionRole.progression,
    ][weekIndex % 4];
  }

  // --- Weekday assignment --------------------------------------------------

  /// Stable weekday slots for the plan lifetime.
  static _DaySlots _assignSlots({
    required List<int> available,
    required int qualitySlots,
    int? preferredLongDay,
  }) {
    final remaining = [...available]..sort();

    int takePreferred(List<int> prefs) {
      for (final p in prefs) {
        final i = remaining.indexOf(p);
        if (i >= 0) return remaining.removeAt(i);
      }
      return remaining.removeLast();
    }

    final longDay = takePreferred([?preferredLongDay, 7, 6]);
    final qualityDays = <int>[];
    for (var i = 0; i < qualitySlots && remaining.isNotEmpty; i++) {
      qualityDays.add(_pickQualityDay(remaining, longDay, qualityDays));
    }
    remaining.sort();
    return _DaySlots(
      longDay: longDay,
      qualityDays: qualityDays,
      easyDays: remaining,
    );
  }

  /// Maps this week's roles onto weekdays, one session per day.
  ///
  /// The slots keep the rhythm recognisable week to week; the pool guarantees a
  /// day is never handed out twice even when the week's role mix does not match
  /// the slot layout (two quality kinds in a single-quality week, an extra
  /// recovery run, a race week).
  static List<int> _daysForWeek({
    required List<_SessionRole> roles,
    required _DaySlots slots,
    required List<int> available,
    required bool raceWeek,
    int? raceWeekday,
  }) {
    final pool = [...available]..sort();
    final used = <int>[];
    final days = List<int>.filled(roles.length, 0);
    final raceDay = raceWeek ? raceWeekday ?? slots.longDay : slots.longDay;

    int take(List<int> prefs) {
      for (final p in prefs) {
        final i = pool.indexOf(p);
        if (i >= 0) {
          final day = pool.removeAt(i);
          used.add(day);
          return day;
        }
      }
      // Fall back to whichever free day sits furthest from what we booked.
      var best = pool.first, bestScore = -1 << 20;
      for (final day in pool) {
        var score = 0;
        for (final u in used) {
          score += _circularGap(day, u);
          if (_adjacent(day, u)) score -= 4;
        }
        if (score > bestScore) {
          bestScore = score;
          best = day;
        }
      }
      pool.remove(best);
      used.add(best);
      return best;
    }

    // Long / race day first so everything else can be spaced around it.
    for (var i = 0; i < roles.length; i++) {
      if (_isLongRole(roles[i])) days[i] = take([raceDay]);
    }
    // Then quality, in slot order.
    var qi = 0;
    for (var i = 0; i < roles.length; i++) {
      final role = roles[i];
      if (!_isQualityRole(role)) continue;
      if (role == _SessionRole.sharpen && raceWeek) {
        // Sharpen 3–4 days out: close enough to stay sharp, far enough to be
        // completely recovered on race day.
        days[i] = take(_sharpenPreference(pool, raceDay));
      } else {
        days[i] = take(
          qi < slots.qualityDays.length ? [slots.qualityDays[qi]] : const [],
        );
      }
      qi++;
    }
    // Easy / recovery fill the rest.
    var ei = 0;
    for (var i = 0; i < roles.length; i++) {
      if (_isLongRole(roles[i]) || _isQualityRole(roles[i])) continue;
      days[i] = take(
        ei < slots.easyDays.length ? [slots.easyDays[ei]] : const [],
      );
      ei++;
    }
    return days;
  }

  static List<int> _sharpenPreference(List<int> pool, int raceDay) {
    int lead(int d) => (raceDay - d + 7) % 7;
    return [...pool]
      ..sort((a, b) => (lead(a) - 3).abs().compareTo((lead(b) - 3).abs()));
  }

  static int _pickQualityDay(
    List<int> remaining,
    int longDay,
    List<int> already,
  ) {
    int? best;
    var bestScore = -999;
    for (final day in remaining) {
      var score = _circularGap(day, longDay) * 10;
      if (_adjacent(day, longDay)) score -= 30;
      for (final q in already) {
        if (_adjacent(day, q)) score -= 50;
      }
      if (score > bestScore) {
        bestScore = score;
        best = day;
      }
    }
    final chosen = best ?? remaining.first;
    remaining.remove(chosen);
    return chosen;
  }

  static int _circularGap(int a, int b) {
    final d = (a - b).abs();
    return d > 3 ? 7 - d : d;
  }

  static bool _adjacent(int a, int b) {
    final d = (a - b).abs();
    return d == 1 || d == 6;
  }

  // --- Week materialisation ------------------------------------------------

  static List<RunPlanTemplateWorkout> _buildWeek({
    required RunPlanTemplate template,
    required RunPlanBuildConfig config,
    required _PaceBook book,
    required _DaySlots slots,
    required _WeekPlan week,
    int? raceWeekday,
  }) {
    var available = config.availableDays;
    if (week.phase == _Phase.race && raceWeekday != null) {
      // Race week follows the real race day: nothing after it, and the race
      // replaces the long-run slot even on a day the athlete does not usually
      // run. Fewer days than sessions sheds recovery, then easy runs.
      final before = [
        for (final d in available)
          if (d < raceWeekday) d,
      ]..sort();
      available = [...before, raceWeekday];
      final roles = [...week.roles];
      while (roles.length > available.length) {
        var drop = roles.lastIndexOf(_SessionRole.recovery);
        if (drop < 0) drop = roles.lastIndexOf(_SessionRole.easy);
        if (drop < 0) drop = roles.indexOf(_SessionRole.sharpen);
        roles.removeAt(drop);
      }
      final sharpen = roles.indexOf(_SessionRole.sharpen);
      if (sharpen >= 0 && !before.any((d) => raceWeekday - d >= 2)) {
        roles[sharpen] = _SessionRole.easy;
      }
      week = _WeekPlan(
        index: week.index,
        phase: week.phase,
        weekKm: week.weekKm,
        longKm: week.longKm,
        roles: roles,
        progress: week.progress,
      );
    }
    final days = _daysForWeek(
      roles: week.roles,
      slots: slots,
      available: available,
      raceWeek: week.phase == _Phase.race,
      raceWeekday: raceWeekday,
    );

    // Provisional split of the non-long budget. Quality days carry a little
    // more because warm-up and cool-down ride along with them. This only sizes
    // warm-ups and rep counts — the real accounting happens below.
    final support = math.max(week.weekKm - week.longKm, 0.0);
    final weights = [
      for (final role in week.roles)
        if (_isLongRole(role))
          0.0
        else
          switch (role) {
            _SessionRole.recovery => 0.7,
            _SessionRole.sharpen => 0.5,
            _SessionRole.test => 1.3,
            _SessionRole.easy => 1.0,
            _ => 1.15,
          },
    ];
    final totalWeight = weights.fold<double>(0, (a, b) => a + b);
    final hint = [
      for (var i = 0; i < week.roles.length; i++)
        totalWeight <= 0 ? 0.0 : support * weights[i] / totalWeight,
    ];

    // Shortest run worth lacing up for: ~15 minutes, within 1.6–2.5 km,
    // never approaching a very short long run. A floor, not a budget share —
    // 0.8 km "easy runs" in race week and 1 km recovery jogs are gone.
    final floorKm = math.min(
      (15 * 60 / book.estEasy).clamp(1.6, 2.5),
      math.max(week.longKm * 0.85, 1.2),
    );
    // A recovery run is short by definition: past ~40 minutes it is just an
    // easy run with a misleading name.
    final recoveryCapKm = 40 * 60 / book.estEasy;

    final effectiveRoles = [...week.roles];
    final built = List<RunPlanTemplateWorkout?>.filled(week.roles.length, null);
    var spent = 0.0;

    RunPlanTemplateWorkout make(
      int i,
      _SessionRole role,
      double km,
      bool strides,
    ) => _sessionFor(
      template: template,
      config: config,
      book: book,
      week: week,
      role: role,
      day: days[i],
      km: km,
      withStrides: strides,
    );

    // Pass 1 — quality, then the long run. How big these get is decided by
    // physiology (the long-run share and quality-work caps), not by whatever
    // volume happens to be left over. If a structured session cannot fit the
    // week while keeping the long run longest, it becomes an easy run.
    for (var i = 0; i < week.roles.length; i++) {
      final role = week.roles[i];
      if (!_isQualityRole(role)) continue;
      final session = make(i, role, math.max(hint[i], 3.0), false);
      final sessionKm = (session.targetDistanceMeters ?? 0) / 1000;
      final remainingNonLong = [
        for (var j = 0; j < week.roles.length; j++)
          if (j != i && built[j] == null && !_isLongRole(week.roles[j])) j,
      ].length;
      final projected =
          spent + sessionKm + week.longKm + remainingNonLong * floorKm;
      final outgrowsLong =
          week.phase != _Phase.race && sessionKm > week.longKm / 1.05;
      // The race-week sharpener is a few hundred metres at race pace; it is
      // the one session that stays even when the stripped-down budget is
      // already spent on run floors.
      final overBudget =
          role != _SessionRole.sharpen && projected > week.weekKm + 0.02;
      if (outgrowsLong || overBudget) {
        effectiveRoles[i] = _SessionRole.easy;
        continue;
      }
      built[i] = session;
      spent += sessionKm;
    }
    final longKm = week.longKm;
    for (var i = 0; i < week.roles.length; i++) {
      if (!_isLongRole(week.roles[i])) continue;
      final session = make(i, week.roles[i], longKm, false);
      built[i] = session;
      spent += (session.targetDistanceMeters ?? 0) / 1000;
    }

    // Pass 2 — easy and recovery runs absorb the difference so the week lands
    // on its volume budget instead of drifting with whichever quality sessions
    // the rotation happened to pick.
    final easyIndexes = [
      for (var i = 0; i < week.roles.length; i++)
        if (built[i] == null) i,
    ];
    final easyWeight = easyIndexes.fold<double>(0, (a, i) => a + weights[i]);
    final minEasyKm = floorKm;
    final leftover = math.max(week.weekKm - spent, 0.0);
    // No mid-week run may approach the long run. On a 3-day week the leftover
    // can otherwise pile onto a single easy day and quietly turn it into a
    // second long run — a 20 km "easy" Tuesday is not easy. A beginner's 4 km
    // long run legitimately has 3.5 km easy days beside it, so the cap is a
    // shrinking share: ~85% of a short long run, ~half of a big one, and
    // never more than 30% of the week. Whatever does not fit is volume the
    // week simply does not get.
    final easyCap = math.max(
      [longKm * 0.85, longKm * 0.45 + 2.0, week.weekKm * 0.3].reduce(math.min),
      minEasyKm,
    );
    final distributable = math.max(
      leftover - easyIndexes.length * minEasyKm,
      0.0,
    );
    final shares = <int, double>{
      for (final i in easyIndexes)
        i:
            minEasyKm +
            (easyWeight <= 0 ? 0.0 : distributable * weights[i] / easyWeight),
    };
    // Recovery runs are capped short; what they cannot carry moves to the
    // easy runs (within their own cap) so the long run's share of the week
    // does not creep up.
    var overflow = 0.0;
    for (final i in easyIndexes) {
      if (effectiveRoles[i] != _SessionRole.recovery) continue;
      final cap = math.max(math.min(easyCap, recoveryCapKm), minEasyKm);
      if (shares[i]! > cap) {
        overflow += shares[i]! - cap;
        shares[i] = cap;
      }
    }
    for (final i in easyIndexes) {
      if (overflow <= 0) break;
      if (effectiveRoles[i] == _SessionRole.recovery) continue;
      final room = math.max(easyCap - shares[i]!, 0.0);
      final add = math.min(room, overflow);
      shares[i] = shares[i]! + add;
      overflow -= add;
    }
    var stridesUsed = week.phase != _Phase.build || week.index < 2;
    for (final i in easyIndexes) {
      final share = shares[i]!;
      final wantsStrides =
          !stridesUsed &&
          effectiveRoles[i] == _SessionRole.easy &&
          share >= 2.5;
      if (wantsStrides) stridesUsed = true;
      final cap = effectiveRoles[i] == _SessionRole.recovery
          ? math.max(math.min(easyCap, recoveryCapKm), minEasyKm)
          : easyCap;
      built[i] = make(
        i,
        effectiveRoles[i],
        share.clamp(minEasyKm, cap),
        wantsStrides,
      );
    }

    return [for (final session in built) session!];
  }

  static RunPlanTemplateWorkout _sessionFor({
    required RunPlanTemplate template,
    required RunPlanBuildConfig config,
    required _PaceBook book,
    required _WeekPlan week,
    required _SessionRole role,
    required int day,
    required double km,
    required bool withStrides,
  }) {
    // Finish-intent softens effort; a taper must NOT — dropping intensity in a
    // taper erases the fitness the taper exists to sharpen.
    final soft = config.intent == RunPlanIntent.finish;
    final warmup = (km * 0.22).clamp(1.0, 3.0);
    final cooldown = (km * 0.15).clamp(0.8, 2.0);
    final workBudget = math.max(km - warmup - cooldown, 1.0);

    switch (role) {
      case _SessionRole.easy:
        return _easy(
          day,
          km,
          book,
          strides: withStrides ? _strideCount(config) : 0,
        );
      case _SessionRole.recovery:
        return _easy(day, km, book, recovery: true);
      case _SessionRole.long:
        return _long(day, km, book, taper: week.phase == _Phase.taper);
      case _SessionRole.longRacePace:
        return _longRacePace(day, km, book);
      case _SessionRole.race:
        return _race(day, km, book, template.goalKind);
      case _SessionRole.sharpen:
        return _sharpen(day, km, book);
      case _SessionRole.test:
        return _test(day, book, template.goalKind, week.weekKm, week.longKm) ??
            _fartlek(day, km, book, weekKm: week.weekKm, soft: true);
      case _SessionRole.interval:
        final maxWorkKm = _vo2WorkCapKm(week.weekKm, book);
        // Fewer than three 400 m reps is not a VO2 session; a fartlek gives
        // the same pace change without pretending otherwise.
        if (maxWorkKm < 1.2) {
          return _fartlek(day, km, book, weekKm: week.weekKm, soft: soft);
        }
        return _interval(
          day: day,
          maxWorkKm: maxWorkKm,
          warmupKm: warmup,
          cooldownKm: cooldown,
          templateMeters: _repMeters(
            template.performanceIntervalMeters ??
                _defaultIntervalMeters(template.goalKind),
            template.goalKind,
            week,
          ),
          desiredReps: _desiredReps(template, config, week.index, week.phase),
          book: book,
          soft: soft,
        );
      case _SessionRole.tempo:
        final maxThresholdMinutes = week.weekKm * 0.10 * book.estTempo / 60;
        if (maxThresholdMinutes < 10) {
          return _fartlek(day, km, book, weekKm: week.weekKm, soft: true);
        }
        return _tempo(
          day: day,
          weekKm: week.weekKm,
          warmupKm: warmup,
          cooldownKm: cooldown,
          desiredMinutes: _desiredTempoMinutes(config, week.index, week.phase),
          book: book,
          soft: soft,
        );
      case _SessionRole.fartlek:
        return _fartlek(day, km, book, weekKm: week.weekKm, soft: soft);
      case _SessionRole.hills:
        if (!config.includeHills) {
          return _fartlek(day, km, book, weekKm: week.weekKm, soft: soft);
        }
        return _hills(
          day: day,
          surface: config.hillSurface,
          warmupKm: warmup,
          cooldownKm: cooldown,
          workBudgetKm: workBudget,
          reps: _desiredReps(
            template,
            config,
            week.index,
            week.phase,
          ).clamp(6, 10),
          book: book,
          soft: soft,
        );
      case _SessionRole.progression:
        return _progression(day, km, book);
      case _SessionRole.racePace:
        return _racePaceSession(
          day: day,
          weekKm: week.weekKm,
          workBudget: workBudget,
          warmupKm: warmup,
          cooldownKm: cooldown,
          book: book,
          goal: template.goalKind,
        );
    }
  }

  /// VO2max work ceiling for one session, in km.
  ///
  /// Daniels caps it near 8% of weekly volume (10 km absolute). At low volume
  /// that rule leaves 3×400 m — about seven minutes of hard running, below the
  /// ~10 minutes an interval session needs to be a stimulus at all. So the
  /// cap never drops below ten minutes at interval pace, bounded to 12% of
  /// the week so it stays a minority of the load.
  static double _vo2WorkCapKm(double weekKm, _PaceBook book) {
    final tenMinutesKm = 600 / book.estInterval;
    return [
      math.max(weekKm * 0.08, tenMinutesKm),
      weekKm * 0.12,
      10.0,
    ].reduce(math.min);
  }

  /// Rep length for this point of the plan. Reps lengthen as the race nears —
  /// 400 m → 800 m for a 5K — which is how interval work turns into specific
  /// endurance at race effort. Taper and recovery weeks keep the short rep.
  static int _repMeters(int base, RunPlanGoalKind goal, _WeekPlan week) {
    if (week.phase != _Phase.build) return base;
    final factors = switch (goal) {
      RunPlanGoalKind.fiveK => const [1.0, 1.5, 2.0],
      RunPlanGoalKind.tenK => const [1.0, 1.25, 1.5],
      RunPlanGoalKind.half || RunPlanGoalKind.marathon => const [1.0, 1.0, 1.2],
      _ => const [1.0, 1.25, 1.5],
    };
    final stage = week.progress < 0.34
        ? 0
        : week.progress < 0.67
        ? 1
        : 2;
    return ((base * factors[stage]) / 200).round() * 200;
  }

  static int _strideCount(RunPlanBuildConfig config) =>
      config.intent == RunPlanIntent.pb ? 6 : 4;

  static int _desiredReps(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    int weekIndex,
    _Phase phase,
  ) {
    final base = template.performanceBaseReps ?? 4;
    final grown = phase == _Phase.taper || phase == _Phase.recovery
        ? base
        : base + (weekIndex ~/ 3).clamp(0, 3);
    return (grown * config.qualityFactor).round().clamp(3, 10);
  }

  static int _desiredTempoMinutes(
    RunPlanBuildConfig config,
    int weekIndex,
    _Phase phase,
  ) {
    final grown = phase == _Phase.taper || phase == _Phase.recovery
        ? 15
        : 15 + (weekIndex ~/ 3) * 5;
    return (grown * config.qualityFactor).round().clamp(8, 40);
  }

  static int _defaultIntervalMeters(RunPlanGoalKind goal) => switch (goal) {
    RunPlanGoalKind.fiveK => 400,
    RunPlanGoalKind.tenK => 800,
    RunPlanGoalKind.half || RunPlanGoalKind.marathon => 1000,
    _ => 400,
  };

  static double? _goalDistanceMeters(RunPlanGoalKind goal) => switch (goal) {
    RunPlanGoalKind.fiveK => RunPaceCalculator.fiveKMeters,
    RunPlanGoalKind.tenK => RunPaceCalculator.tenKMeters,
    RunPlanGoalKind.half => RunPaceCalculator.halfMeters,
    RunPlanGoalKind.marathon => RunPaceCalculator.marathonMeters,
    _ => null,
  };

  // --- Run / walk ----------------------------------------------------------

  static List<List<RunPlanTemplateWorkout>> _composeRunWalk(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    final work = template.runWalkWork!;
    final rest = template.runWalkRest!;
    final reps = template.runWalkReps!;
    final walkJog = template.key == 'walk_jog';
    final t = config.text;
    // Bone and tendon adaptation lags the cardiovascular system, so a beginner
    // progression spreads its days instead of running the block Mon–Fri.
    final days = _spacedDays(config.availableDays);
    final weeks = <List<RunPlanTemplateWorkout>>[];

    for (var w = 0; w < work.length; w++) {
      final sessionReps =
          (reps[w] *
                  switch (config.intensity) {
                    RunPlanIntensity.aggressive => 1.1,
                    RunPlanIntensity.conservative => 0.9,
                    RunPlanIntensity.standard => 1.0,
                  })
              .round()
              .clamp(2, 12);
      // Last two weeks of "Start running": the week's final session is one
      // continuous run, so the athlete graduates having actually run without
      // walking. It is time-based and only ~1.5× the week's longest block —
      // the old 3.5 km (≈30 min) run straight after 8-minute blocks was a
      // jump nobody finishing week 6 could make. Walk-to-jog never gets one:
      // its graduation is the next plan.
      final continuousSeconds =
          !walkJog && w >= work.length - 2 && config.sessionsPerWeek >= 3
          ? (((work[w] * 1.5) / 300).round() * 300).clamp(600, 1500)
          : null;
      weeks.add([
        for (var s = 0; s < config.sessionsPerWeek; s++)
          if (continuousSeconds != null && s == config.sessionsPerWeek - 1)
            _continuousRun(days[s], continuousSeconds, t)
          else
            RunPlanTemplateWorkout(
              name: walkJog ? t.walkJogName : t.runWalkName,
              kind: RunWorkoutKind.easy,
              dayOfWeek: days[s],
              effortZone: 'RPE 3–4',
              targetDurationSeconds: 600 + sessionReps * (work[w] + rest[w]),
              notes: walkJog ? t.walkJogNote : t.runWalkNote,
              steps: [
                const RunPlanTemplateStep(
                  role: RunStepRole.warmup,
                  metric: RunIntervalMetric.time,
                  value: 300,
                ),
                RunPlanTemplateStep(
                  role: RunStepRole.work,
                  metric: RunIntervalMetric.time,
                  value: work[w],
                  repeatGroup: 1,
                  repeatCount: sessionReps,
                ),
                RunPlanTemplateStep(
                  role: RunStepRole.recovery,
                  metric: RunIntervalMetric.time,
                  value: rest[w],
                  repeatGroup: 1,
                  repeatCount: sessionReps,
                ),
                const RunPlanTemplateStep(
                  role: RunStepRole.cooldown,
                  metric: RunIntervalMetric.time,
                  value: 300,
                ),
              ],
            ),
      ]);
    }
    return weeks;
  }

  /// Time-based continuous run with a walking warm-up and cool-down.
  static RunPlanTemplateWorkout _continuousRun(
    int day,
    int seconds,
    RunPlanText t,
  ) => RunPlanTemplateWorkout(
    name: t.continuousName(seconds ~/ 60),
    kind: RunWorkoutKind.easy,
    dayOfWeek: day,
    effortZone: 'RPE 3–4',
    targetDurationSeconds: seconds + 600,
    notes: t.continuousNote,
    steps: [
      const RunPlanTemplateStep(
        role: RunStepRole.warmup,
        metric: RunIntervalMetric.time,
        value: 300,
      ),
      RunPlanTemplateStep(
        role: RunStepRole.steady,
        metric: RunIntervalMetric.time,
        value: seconds,
      ),
      const RunPlanTemplateStep(
        role: RunStepRole.cooldown,
        metric: RunIntervalMetric.time,
        value: 300,
      ),
    ],
  );

  /// Orders the chosen days so back-to-back sessions come last.
  static List<int> _spacedDays(List<int> available) {
    final days = [...available]..sort();
    if (days.length <= 2) return days;
    final spread = <int>[days.first];
    final pool = days.sublist(1);
    while (pool.isNotEmpty) {
      var best = pool.first, bestScore = -1 << 20;
      for (final day in pool) {
        var score = 0;
        for (final s in spread) {
          score += _circularGap(day, s);
          if (_adjacent(day, s)) score -= 4;
        }
        if (score > bestScore) {
          bestScore = score;
          best = day;
        }
      }
      pool.remove(best);
      spread.add(best);
    }
    return spread..sort();
  }

  // --- Sessions ------------------------------------------------------------

  static double _meters(double km) => (km * 100).round() * 10;

  static String _easyNote(String base, _PaceBook book) {
    final window = book.easyWindowLabel;
    return window == null ? base : book.text.easyWindow(base, window);
  }

  static RunPlanTemplateWorkout _easy(
    int day,
    double km,
    _PaceBook book, {
    bool recovery = false,
    int strides = 0,
  }) {
    if (strides <= 0) {
      return RunPlanTemplateWorkout(
        name: recovery ? book.text.recoveryName : book.text.easyName,
        kind: recovery ? RunWorkoutKind.recovery : RunWorkoutKind.easy,
        dayOfWeek: day,
        targetDistanceMeters: _meters(km),
        targetPaceSecPerKm: book.easy,
        effortZone: recovery ? 'Z1 / RPE 2' : 'Z1–Z2 / RPE 2–4',
        notes: _easyNote(
          recovery ? book.text.recoveryNote : book.text.easyNote,
          book,
        ),
      );
    }

    // 20 s strides plus a walk-back, carved out of the steady portion.
    const strideSec = 20, strideRestSec = 60;
    final strideKm = strides * strideSec / book.estInterval;
    final steadyKm = math.max(km - strideKm, 2.0);
    final easyBand = book.calibrated
        ? RunPaceCalculator.orderedBand(book.easyFast!, book.easySlow!)
        : null;
    return RunPlanTemplateWorkout(
      name: book.text.easyStridesName(strides),
      kind: RunWorkoutKind.easy,
      dayOfWeek: day,
      targetDistanceMeters: _meters(steadyKm + strideKm),
      targetPaceSecPerKm: book.easy,
      effortZone: book.text.easyStridesZone,
      notes: _easyNote(book.text.easyStridesNote(strides, strideSec), book),
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          value: _meters(steadyKm).round(),
          targetPaceMinSecPerKm: easyBand?.$1,
          targetPaceMaxSecPerKm: easyBand?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          metric: RunIntervalMetric.time,
          value: strideSec,
          repeatGroup: 1,
          repeatCount: strides,
          targetPaceMinSecPerKm: book.repetition,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: strideRestSec,
          repeatGroup: 1,
          repeatCount: strides,
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _long(
    int day,
    double km,
    _PaceBook book, {
    required bool taper,
  }) => RunPlanTemplateWorkout(
    name: book.text.longName,
    kind: RunWorkoutKind.long,
    dayOfWeek: day,
    targetDistanceMeters: _meters(km),
    targetPaceSecPerKm: book.easy,
    effortZone: 'Z2 / RPE 3–4',
    notes: _easyNote(
      taper ? book.text.longTaperNote : book.text.longNote,
      book,
    ),
  );

  /// Long run carrying goal-race-pace blocks — the specificity session for
  /// half and marathon goals.
  static RunPlanTemplateWorkout _longRacePace(
    int day,
    double km,
    _PaceBook book,
  ) {
    final racePace = book.goalRace;
    final band = racePace == null ? null : RunPaceCalculator.band(racePace);
    // Scale the structure down with the long run. Fixed 2 km blocks used to
    // turn an 8 km budget into a 10 km workout and silently break the weekly
    // load cap for lower-volume runners.
    final blocks = km >= 24
        ? 3
        : km >= 12
        ? 2
        : 1;
    final blockKm = (km * 0.12).clamp(0.8, 5.0);
    final recoveryKm = (km * 0.04).clamp(0.4, 1.0);
    final cooldownKm = (km * 0.08).clamp(0.5, 1.0);
    final easyKm = math.max(
      km - blocks * (blockKm + recoveryKm) - cooldownKm,
      0.0,
    );
    return RunPlanTemplateWorkout(
      name: book.text.longRacePaceName,
      kind: RunWorkoutKind.progression,
      dayOfWeek: day,
      targetDistanceMeters: _meters(
        easyKm + blocks * (blockKm + recoveryKm) + cooldownKm,
      ),
      targetPaceSecPerKm: book.easy,
      effortZone: book.text.longRacePaceZone,
      notes: book.text.longRacePaceNote(blocks),
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          value: _meters(easyKm).round(),
          targetPaceMinSecPerKm: book.easyFast,
          targetPaceMaxSecPerKm: book.easySlow,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: _meters(blockKm).round(),
          repeatGroup: 1,
          repeatCount: blocks,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          value: _meters(recoveryKm).round(),
          repeatGroup: 1,
          repeatCount: blocks,
          targetPaceMinSecPerKm: book.easyFast,
          targetPaceMaxSecPerKm: book.easySlow,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldownKm).round(),
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _race(
    int day,
    double km,
    _PaceBook book,
    RunPlanGoalKind goal,
  ) => RunPlanTemplateWorkout(
    name: book.text.raceName,
    kind: RunWorkoutKind.race,
    dayOfWeek: day,
    targetDistanceMeters: _meters(km),
    // Race pace for THIS distance, re-derived from fitness — never the pace of
    // the calibration race.
    targetPaceSecPerKm: book.goalRace,
    effortZone: goal == RunPlanGoalKind.marathon ? 'RPE 7–8' : 'RPE 8–9',
    notes: book.text.raceNote,
  );

  /// Time trial: long enough to predict race fitness, short enough to run
  /// in a down week. 3 km for 5K/10K goals, 5 km for longer races.
  ///
  /// Null when even 3 km would be more than a quarter of the week — a
  /// maximal effort that dominates a down week is not a checkpoint — or when
  /// the session would outgrow the week's long run.
  static RunPlanTemplateWorkout? _test(
    int day,
    _PaceBook book,
    RunPlanGoalKind goal,
    double weekKm,
    double longKm,
  ) {
    final preferred =
        goal == RunPlanGoalKind.half || goal == RunPlanGoalKind.marathon
        ? 5.0
        : 3.0;
    final testKm = preferred <= weekKm * 0.25 ? preferred : 3.0;
    if (testKm > weekKm * 0.25) return null;
    const warmupKm = 1.5, cooldownKm = 1.0;
    // The long run stays the longest session of the week.
    if (warmupKm + testKm + cooldownKm > longKm / 1.05) return null;
    return RunPlanTemplateWorkout(
      name: book.text.testName(book.text.distance(testKm)),
      kind: RunWorkoutKind.test,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + testKm + cooldownKm),
      // A reference for the athlete, not a step target: a time trial is run
      // by effort, and a coach cue telling them to slow down would spoil it.
      targetPaceSecPerKm: book.training?.racePaceFor(testKm * 1000),
      effortZone: 'RPE 9',
      notes: book.text.testNote,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmupKm).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: _meters(testKm).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldownKm).round(),
        ),
      ],
    );
  }

  /// Race-week sharpener: enough to stay sharp, too little to cost anything.
  static RunPlanTemplateWorkout _sharpen(int day, double km, _PaceBook book) {
    final racePace = book.goalRace;
    final band = racePace == null ? null : RunPaceCalculator.band(racePace);
    final warmup = (km * 0.35).clamp(1.0, 2.5);
    final cooldown = (km * 0.25).clamp(0.8, 1.5);
    const reps = 3;
    return RunPlanTemplateWorkout(
      name: book.text.sharpenName(reps),
      kind: RunWorkoutKind.interval,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmup + reps * 0.6 + cooldown),
      targetPaceSecPerKm: racePace,
      effortZone: 'RPE 6–7',
      notes: book.text.sharpenNote,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmup).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: 400,
          repeatGroup: 1,
          repeatCount: reps,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          value: 200,
          repeatGroup: 1,
          repeatCount: reps,
          targetPaceMinSecPerKm: book.easyFast,
          targetPaceMaxSecPerKm: book.easySlow,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldown).round(),
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _interval({
    required int day,
    required double maxWorkKm,
    required double warmupKm,
    required double cooldownKm,
    required int templateMeters,
    required int desiredReps,
    required _PaceBook book,
    required bool soft,
  }) {
    // A low-volume week gets shorter reps rather than an unrunnable rep count
    // — but never below 400 m, where the rep stops reaching VO2max.
    var meters = templateMeters;
    while (meters > 400 && meters * 3 > maxWorkKm * 1000) {
      meters -= 200;
    }
    final fits = (maxWorkKm * 1000 / meters).floor();
    final reps = math.min(desiredReps, math.max(fits, 3));

    // Jog recovery roughly equal to rep duration keeps every rep at the same
    // quality — interval training is about accumulated time at VO2max, not
    // about the fatigue between reps.
    final repSeconds = meters / 1000 * book.estInterval;
    final restSec = (repSeconds * (soft ? 1.1 : 0.9)).round().clamp(45, 240);

    final band = book.interval == null
        ? null
        : RunPaceCalculator.band(book.interval!);
    final workKm = reps * meters / 1000;
    final restKm = reps * restSec / book.estEasy;
    return RunPlanTemplateWorkout(
      name: book.text.intervalName(reps, meters),
      kind: RunWorkoutKind.interval,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + workKm + restKm + cooldownKm),
      targetPaceSecPerKm: book.interval,
      effortZone: soft ? 'RPE 7–8' : 'RPE 8–9',
      notes: book.text.intervalNote(restSec),
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmupKm).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: meters,
          repeatGroup: 1,
          repeatCount: reps,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: restSec,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldownKm).round(),
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _tempo({
    required int day,
    required double weekKm,
    required double warmupKm,
    required double cooldownKm,
    required int desiredMinutes,
    required _PaceBook book,
    required bool soft,
  }) {
    // Threshold volume capped near 10% of the week — but 10% is a ceiling,
    // not a target. Below ~15 min the session stops being a threshold
    // stimulus, so that is the floor from ~30 km/week up; smaller weeks keep a
    // proportionate 10–15 min floor rather than a session that dwarfs them.
    final maxMinutes = weekKm * 0.10 * book.estTempo / 60;
    final floorMinutes = (weekKm * 0.5).round().clamp(10, 15);
    final minutes = math
        .min(desiredMinutes.toDouble(), maxMinutes)
        .round()
        .clamp(floorMinutes, 40);

    final band = book.tempo == null
        ? null
        : RunPaceCalculator.band(book.tempo!);
    final workKm = minutes * 60 / book.estTempo;

    // Beyond ~20 min at threshold, cruise intervals hold the right pace better
    // than one continuous block, for the same physiological stimulus.
    if (minutes > 20) {
      final reps = (minutes / 10).ceil().clamp(2, 5);
      final repMinutes = (minutes / reps).clamp(5, 12);
      const restSec = 60;
      final restKm = reps * restSec / book.estEasy;
      return RunPlanTemplateWorkout(
        name: book.text.tempoCruiseName(reps, repMinutes.round()),
        kind: RunWorkoutKind.tempo,
        dayOfWeek: day,
        targetDistanceMeters: _meters(warmupKm + workKm + restKm + cooldownKm),
        targetPaceSecPerKm: book.tempo,
        effortZone: soft ? 'RPE 6–7' : 'RPE 7',
        notes: book.text.tempoCruiseNote(restSec),
        steps: [
          RunPlanTemplateStep(
            role: RunStepRole.warmup,
            value: _meters(warmupKm).round(),
          ),
          RunPlanTemplateStep(
            role: RunStepRole.work,
            metric: RunIntervalMetric.time,
            value: (repMinutes * 60).round(),
            repeatGroup: 1,
            repeatCount: reps,
            targetPaceMinSecPerKm: band?.$1,
            targetPaceMaxSecPerKm: band?.$2,
          ),
          RunPlanTemplateStep(
            role: RunStepRole.recovery,
            metric: RunIntervalMetric.time,
            value: restSec,
            repeatGroup: 1,
            repeatCount: reps,
          ),
          RunPlanTemplateStep(
            role: RunStepRole.cooldown,
            value: _meters(cooldownKm).round(),
          ),
        ],
      );
    }

    return RunPlanTemplateWorkout(
      name: book.text.tempoName(minutes),
      kind: RunWorkoutKind.tempo,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + workKm + cooldownKm),
      targetPaceSecPerKm: book.tempo,
      effortZone: soft ? 'RPE 6–7' : 'RPE 7',
      notes: book.text.tempoNote,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmupKm).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          metric: RunIntervalMetric.time,
          value: minutes * 60,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldownKm).round(),
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _fartlek(
    int day,
    double km,
    _PaceBook book, {
    required double weekKm,
    required bool soft,
  }) {
    // One-minute surges, with the rep count growing with the week so the
    // session stays a real stimulus on a 40 km week and not just on a 15 km one.
    const workSec = 60;
    final restSec = soft ? 75 : 60;
    final surge = book.calibrated
        ? RunPaceCalculator.orderedBand(book.interval!, book.tempo!)
        : null;
    final warmup = (km * 0.2).clamp(1.0, 2.0);
    final cooldown = (km * 0.15).clamp(0.8, 1.5);
    // Never longer than the session's own budget (so it can't out-distance
    // the long run on a small week), but at least four surges.
    final repKm = workSec / book.estTempo + restSec / book.estEasy;
    final fits = ((km - warmup - cooldown) / repKm).floor();
    final reps = math
        .min(((soft ? 6 : 8) + weekKm / 15).floor(), fits)
        .clamp(4, 12);
    final surgeKm = reps * workSec / book.estTempo;
    final restKm = reps * restSec / book.estEasy;
    return RunPlanTemplateWorkout(
      name: book.text.fartlekName(reps, workSec),
      kind: RunWorkoutKind.fartlek,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmup + surgeKm + restKm + cooldown),
      targetPaceSecPerKm: book.tempo,
      effortZone: soft ? 'RPE 6' : 'RPE 7',
      notes: book.text.fartlekNote,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmup).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          metric: RunIntervalMetric.time,
          value: workSec,
          repeatGroup: 1,
          repeatCount: reps,
          targetPaceMinSecPerKm: surge?.$1,
          targetPaceMaxSecPerKm: surge?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: restSec,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldown).round(),
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _hills({
    required int day,
    required RunPlanHillSurface surface,
    required double warmupKm,
    required double cooldownKm,
    required double workBudgetKm,
    required int reps,
    required _PaceBook book,
    required bool soft,
  }) {
    // 45–60 s uphill is the range that builds specific strength without
    // turning into a sprint; 30 s reps never accumulate enough work. Stairs
    // are steeper and harder on the calves, so their reps are shorter.
    final workSec = switch (surface) {
      RunPlanHillSurface.stairs => soft ? 30 : 45,
      _ => soft ? 45 : 60,
    };
    // Walking down stairs takes longer than jogging down a hill.
    final restSec =
        (workSec * (surface == RunPlanHillSurface.stairs ? 2.0 : 1.6)).round();
    // On a small week the budget, not the rotation, decides the rep count —
    // the session must stay shorter than the long run. Four is the floor.
    final repKm = workSec / book.estTempo + restSec / book.estEasy;
    reps = math.min(reps, (workBudgetKm / repKm).floor()).clamp(4, 10);
    // Uphill reps plus the jog back down, so the session reports the distance
    // it actually covers rather than the budget it was handed.
    final workKm = reps * workSec / book.estTempo;
    final restKm = reps * restSec / book.estEasy;
    final t = book.text;
    final (name, notes) = switch (surface) {
      RunPlanHillSurface.hill => (
        t.hillName(reps, workSec),
        t.hillNote(workSec),
      ),
      RunPlanHillSurface.stairs => (
        t.stairsName(reps, workSec),
        t.stairsNote(workSec),
      ),
      RunPlanHillSurface.treadmill => (
        t.treadmillHillName(reps, workSec),
        t.treadmillHillNote(workSec),
      ),
    };
    return RunPlanTemplateWorkout(
      name: name,
      kind: RunWorkoutKind.hills,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + workKm + restKm + cooldownKm),
      // Deliberately no pace target: the same effort uphill is 30–60 s/km
      // slower, so a flat-ground pace here would be either impossible or a
      // licence to overreach. Hills are prescribed by effort.
      effortZone: soft ? 'RPE 7' : 'RPE 8',
      notes: notes,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmupKm).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          metric: RunIntervalMetric.time,
          value: workSec,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: restSec,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldownKm).round(),
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _progression(
    int day,
    double km,
    _PaceBook book,
  ) {
    final third = _meters(km / 3);
    final midPace = book.calibrated ? (book.easy! + book.tempo!) / 2 : null;
    final easyBand = book.calibrated
        ? RunPaceCalculator.orderedBand(book.easyFast!, book.easySlow!)
        : null;
    // Ordered so the faster bound is always `min`: a range rendered as
    // "5:16–4:50" reads as broken.
    final finishBand = book.calibrated
        ? RunPaceCalculator.orderedBand(
            book.tempo!,
            book.goalRace ?? book.tempo!,
          )
        : null;
    return RunPlanTemplateWorkout(
      name: book.text.progressionName(km.round()),
      kind: RunWorkoutKind.progression,
      dayOfWeek: day,
      targetDistanceMeters: _meters(km),
      targetPaceSecPerKm: midPace,
      effortZone: 'RPE 5 → 7',
      notes: book.text.progressionNote,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: third.round(),
          targetPaceMinSecPerKm: easyBand?.$1,
          targetPaceMaxSecPerKm: easyBand?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          value: third.round(),
          targetPaceMinSecPerKm: midPace,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: third.round(),
          targetPaceMinSecPerKm: finishBand?.$1,
          targetPaceMaxSecPerKm: finishBand?.$2,
        ),
      ],
    );
  }

  /// Cruise reps at goal race pace — specificity for the distance actually
  /// being trained for, at a volume the athlete can absorb.
  static RunPlanTemplateWorkout _racePaceSession({
    required int day,
    required double weekKm,
    required double workBudget,
    required double warmupKm,
    required double cooldownKm,
    required _PaceBook book,
    required RunPlanGoalKind goal,
  }) {
    final racePace = book.goalRace;
    final band = racePace == null ? null : RunPaceCalculator.band(racePace);
    final desiredBlockKm = switch (goal) {
      RunPlanGoalKind.marathon || RunPlanGoalKind.half => 3.0,
      RunPlanGoalKind.tenK => 2.0,
      _ => 1.0,
    };
    // Race-pace work is aerobic, but it still shares the week with another
    // stimulus. Scale both block length and count to the actual session budget;
    // forcing two 3 km blocks is what used to double low-volume weeks.
    final maxWorkKm = math.min(weekKm * 0.12, workBudget * 0.70);
    final rawBlockKm = math.min(desiredBlockKm, math.max(0.4, maxWorkKm));
    // Round to distances a runner can find on a watch: 400/600/800 m, then
    // half kilometres — the label has to match the step exactly.
    final blockKm = rawBlockKm >= 1
        ? (rawBlockKm * 2).floor() / 2
        : math.max(0.4, (rawBlockKm * 5).floor() / 5);
    final blocks = math.max(1, (maxWorkKm / blockKm).floor()).clamp(1, 6);
    final restSec = goal == RunPlanGoalKind.fiveK ? 90 : 120;
    final restKm = blocks * restSec / book.estEasy;
    return RunPlanTemplateWorkout(
      name: book.text.racePaceName(blocks, book.text.distance(blockKm)),
      kind: RunWorkoutKind.tempo,
      dayOfWeek: day,
      targetDistanceMeters: _meters(
        warmupKm + blocks * blockKm + restKm + cooldownKm,
      ),
      targetPaceSecPerKm: racePace,
      effortZone: goal == RunPlanGoalKind.marathon ? 'RPE 6–7' : 'RPE 7–8',
      notes: book.text.racePaceNote,
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: _meters(warmupKm).round(),
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: _meters(blockKm).round(),
          repeatGroup: 1,
          repeatCount: blocks,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: restSec,
          repeatGroup: 1,
          repeatCount: blocks,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.cooldown,
          value: _meters(cooldownKm).round(),
        ),
      ],
    );
  }
}
