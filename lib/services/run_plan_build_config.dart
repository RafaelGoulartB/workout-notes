import 'package:workout_notes/models/run_plan_template.dart';
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

  /// [current] unless [value] was passed (possibly as null, to clear it).
  static T? _pick<T>(Object? value, T? current) =>
      identical(value, _unset) ? current : value as T?;

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
    goalCalibration: _pick(goalCalibration, this.goalCalibration),
    raceDate: raceDate,
    startDate: _pick(startDate, this.startDate),
    currentWeeklyKm: _pick(currentWeeklyKm, this.currentWeeklyKm),
    includeHills: includeHills,
    hillSurface: hillSurface,
    longRunDay: longRunDay,
    weeks: weeks,
    remainingWeeks: _pick(remainingWeeks, this.remainingWeeks),
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
