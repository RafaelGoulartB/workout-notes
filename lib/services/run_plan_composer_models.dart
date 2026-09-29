part of 'run_plan_composer.dart';

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
