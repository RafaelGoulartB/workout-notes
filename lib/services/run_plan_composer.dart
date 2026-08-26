import 'dart:math' as math;

import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

/// How hard the athlete wants to push weekly volume and quality load.
enum RunPlanIntensity { conservative, standard, aggressive }

/// Finish the distance vs chase a personal best.
///
/// Both intents keep evidence-based quality work (intervals, threshold, etc.).
/// [pb] loads quality harder; [finish] keeps the same stimulus mix at lower
/// intensity — all-easy plans are reserved for return-to-running intro weeks
/// and pure run/walk progressions.
enum RunPlanIntent { finish, pb }

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
}

/// Inputs collected by the customize wizard before materialising a plan.
class RunPlanBuildConfig {
  /// 3, 4 or 5 sessions per week.
  final int sessionsPerWeek;

  /// ISO weekdays (1=Mon … 7=Sun). Length must equal [sessionsPerWeek].
  final List<int> availableDays;

  final RunPlanIntent intent;
  final RunPlanIntensity intensity;
  final RunPlanPaceCalibration? calibration;
  final DateTime? raceDate;

  /// What the athlete actually runs today, in km/week.
  ///
  /// A jump in workload relative to what the body is used to is the strongest
  /// modifiable predictor of running injury, so when this is known week 1 is
  /// anchored to it and the whole ladder shifts with it.
  final double? currentWeeklyKm;

  const RunPlanBuildConfig({
    required this.sessionsPerWeek,
    required this.availableDays,
    this.intent = RunPlanIntent.finish,
    this.intensity = RunPlanIntensity.standard,
    this.calibration,
    this.raceDate,
    this.currentWeeklyKm,
  });

  double get volumeFactor => switch (intensity) {
    RunPlanIntensity.conservative => 0.85,
    RunPlanIntensity.standard => 1.0,
    RunPlanIntensity.aggressive => 1.15,
  };

  /// Quality load multiplier (reps / tempo minutes). Finish is still quality,
  /// just gentler — matching polarized training, not junk mileage.
  double get qualityFactor => switch ((intent, intensity)) {
    (RunPlanIntent.finish, RunPlanIntensity.conservative) => 0.75,
    (RunPlanIntent.finish, _) => 0.85,
    (RunPlanIntent.pb, RunPlanIntensity.aggressive) => 1.15,
    (RunPlanIntent.pb, RunPlanIntensity.conservative) => 0.9,
    (RunPlanIntent.pb, _) => 1.0,
  };

  void validate() {
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
    if (currentWeeklyKm != null && currentWeeklyKm! < 0) {
      throw ArgumentError('currentWeeklyKm must be positive');
    }
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

  /// Three running days in a row on a 3–4 day week.
  final bool consecutiveDays;

  const RunPlanReadiness({
    required this.startWeeklyKm,
    required this.currentWeeklyKm,
    required this.peakLongKm,
    required this.requiredLongKm,
    required this.consecutiveDays,
  });

  /// Week 1 sits more than 25% above what the athlete runs today.
  bool get volumeGap {
    final current = currentWeeklyKm;
    return current != null && current > 0 && startWeeklyKm > current * 1.25;
  }

  /// The plan never gets the long run close enough to the race distance.
  bool get longRunShort =>
      requiredLongKm > 0 && peakLongKm < requiredLongKm - 0.5;

  bool get ok => !volumeGap && !longRunShort;
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
}

bool _isQualityRole(_SessionRole role) =>
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
  final RunPaces? paces;
  final double goalMeters;

  const _PaceBook(this.paces, this.goalMeters);

  double? get easy => paces?.easySecPerKm;
  double? get easyFast => paces?.easyFastSecPerKm;
  double? get easySlow => paces?.easySlowSecPerKm;
  double? get tempo => paces?.tempoSecPerKm;
  double? get interval => paces?.intervalSecPerKm;
  double? get repetition => paces?.repetitionSecPerKm;

  /// Race pace for the distance this plan targets — never the calibration pace.
  double? get goalRace => paces?.racePaceFor(goalMeters);

  double get estEasy => paces?.easySecPerKm ?? 390;
  double get estTempo => paces?.tempoSecPerKm ?? 320;
  double get estInterval => paces?.intervalSecPerKm ?? 295;

  bool get calibrated => paces != null;

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

  const _WeekPlan({
    required this.index,
    required this.phase,
    required this.weekKm,
    required this.longKm,
    required this.roles,
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
  ) {
    config.validate();
    if (template.style == RunPlanTemplateStyle.runWalk) {
      return _composeRunWalk(template, config);
    }
    return _composeRuns(template, config);
  }

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
  ) {
    config.validate();
    final consecutive =
        config.sessionsPerWeek <= 4 &&
        _hasThreeConsecutiveDays(config.availableDays);
    if (template.style == RunPlanTemplateStyle.runWalk) {
      return RunPlanReadiness(
        startWeeklyKm: 0,
        currentWeeklyKm: config.currentWeeklyKm,
        peakLongKm: 0,
        requiredLongKm: 0,
        consecutiveDays: consecutive,
      );
    }
    final goalMeters = _goalDistanceMeters(template.goalKind);
    final book = _PaceBook(
      config.calibration?.paces,
      goalMeters ?? RunPaceCalculator.tenKMeters,
    );
    final weeks = _planWeeks(template, config, book, goalMeters);
    final training = weeks.where((w) => w.phase != _Phase.race);
    final peakLong = training.fold<double>(
      0,
      (max, w) => math.max(max, w.longKm),
    );
    // The time-on-feet cap is a deliberate ceiling, so it bounds what the plan
    // can be asked to reach.
    final required = math.min(
      _requiredPeakLongKm(template.goalKind, goalMeters),
      _longRunCapKm(template.goalKind, book),
    );
    return RunPlanReadiness(
      startWeeklyKm: weeks.first.weekKm,
      currentWeeklyKm: config.currentWeeklyKm,
      peakLongKm: peakLong,
      requiredLongKm: required,
      consecutiveDays: consecutive,
    );
  }

  /// How long the longest training run must get for the race to be safe.
  ///
  /// 5K/10K: the distance itself. Half: ~80% (17 km). Marathon: ~65% (27 km)
  /// — mainstream novice plans peak at 30–32 km, but 26–29 km is the accepted
  /// floor below which the last 10 km become a gamble.
  static double _requiredPeakLongKm(RunPlanGoalKind goal, double? goalMeters) {
    if (goalMeters == null) return 0;
    final raceKm = goalMeters / 1000;
    return switch (goal) {
      RunPlanGoalKind.marathon => raceKm * 0.65,
      RunPlanGoalKind.half => raceKm * 0.80,
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

  static List<List<RunPlanTemplateWorkout>> _composeRuns(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    final goalMeters = _goalDistanceMeters(template.goalKind);
    final book = _PaceBook(
      config.calibration?.paces,
      goalMeters ?? RunPaceCalculator.tenKMeters,
    );
    final weeks = _planWeeks(template, config, book, goalMeters);
    final slots = _assignSlots(
      available: config.availableDays,
      qualitySlots: _qualitySlotCount(template, config),
    );

    return [
      for (final week in weeks)
        _buildWeek(
          template: template,
          config: config,
          book: book,
          slots: slots,
          week: week,
        ),
    ];
  }

  /// Phase, volume budget and roles for every week, in one pass.
  static List<_WeekPlan> _planWeeks(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    _PaceBook book,
    double? goalMeters,
  ) {
    final continuous = template.continuousKm;
    final total = continuous?.length ?? template.performanceLongKm!.length;
    final templateSessions = continuous != null
        ? continuous.first.length
        : template.sessionsPerWeek;

    final hasRace =
        goalMeters != null &&
        (template.raceFinish ||
            template.style == RunPlanTemplateStyle.performance);
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
        ? continuous[w].reduce((a, b) => a + b)
        : template.performanceLongKm![w] +
              template.performanceEasyKm! * (templateSessions - 1);
    double templateLongKm(int w) => continuous != null
        ? continuous[w].last
        : template.performanceLongKm![w];

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
      final week0 =
          templateWeekKm(0) *
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
    final rawWeek = <double>[], rawLong = <double>[];
    for (var w = 0; w < total; w++) {
      final scale = config.volumeFactor * anchorAt(w);
      var long = math.min(templateLongKm(w) * scale, longCap);
      final templateWeek = templateWeekKm(w) * scale * sessionScale;
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
    final maxMinutes = goal == RunPlanGoalKind.marathon ? 180.0 : 150.0;
    return math.min(distanceCap, maxMinutes * 60 / book.estEasy);
  }

  /// How many dedicated quality weekdays to reserve for the whole plan.
  static int _qualitySlotCount(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    if (template.style == RunPlanTemplateStyle.runWalk) return 0;
    // Return-to-running: ease back with one stimulus only.
    if (template.key == 'return') return 1;
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
    // Race week keeps a short sharpener; a taper keeps full intensity.
    if (phase == _Phase.race || phase == _Phase.taper) return true;
    if (template.style == RunPlanTemplateStyle.performance) return true;

    // Continuous: short aerobic intro, then quality. Return stays gentler longer.
    final introWeeks = template.key == 'return'
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
      // Nothing that needs recovering from: one short sharpener, easy days,
      // then the race. Volume is already cut to ~20% of peak.
      return [
        _SessionRole.sharpen,
        for (var i = 0; i < sessions - 2; i++)
          i == 0 ? _SessionRole.easy : _SessionRole.recovery,
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
            : _primaryQuality(weekIndex, endurance),
        for (var i = 0; i < sessions - 2; i++) _SessionRole.easy,
        _SessionRole.long,
      ];
    }

    if (phase == _Phase.recovery) {
      final soft = gentle || weekIndex.isEven
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
          : _primaryQuality(weekIndex, endurance),
    ];
    if (qualitySlots > 1) {
      quality.add(
        gentle
            ? _gentleQuality(weekIndex + 1)
            : specific && weekIndex.isEven
            ? _SessionRole.racePace
            : _secondaryQuality(weekIndex, endurance),
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
  /// goals lean VO2max-first, matching where each distance is limited.
  static _SessionRole _primaryQuality(int weekIndex, bool endurance) =>
      endurance
      ? const [
          _SessionRole.tempo,
          _SessionRole.interval,
          _SessionRole.tempo,
          _SessionRole.hills,
          _SessionRole.tempo,
          _SessionRole.fartlek,
        ][weekIndex % 6]
      : const [
          _SessionRole.interval,
          _SessionRole.tempo,
          _SessionRole.hills,
          _SessionRole.interval,
          _SessionRole.fartlek,
          _SessionRole.tempo,
        ][weekIndex % 6];

  /// Beginner quality: alternate fartlek and progression — pace changes and a
  /// strong finish, both at controlled effort.
  static _SessionRole _gentleQuality(int weekIndex) =>
      weekIndex.isEven ? _SessionRole.fartlek : _SessionRole.progression;

  /// Second quality slot (4–5 day weeks) — complementary, not duplicate.
  static _SessionRole _secondaryQuality(int weekIndex, bool endurance) =>
      endurance
      ? const [
          _SessionRole.fartlek,
          _SessionRole.racePace,
          _SessionRole.progression,
          _SessionRole.tempo,
          _SessionRole.racePace,
          _SessionRole.progression,
        ][weekIndex % 6]
      : const [
          _SessionRole.tempo,
          _SessionRole.fartlek,
          _SessionRole.progression,
          _SessionRole.racePace,
          _SessionRole.tempo,
          _SessionRole.hills,
        ][weekIndex % 6];

  // --- Weekday assignment --------------------------------------------------

  /// Stable weekday slots for the plan lifetime.
  static _DaySlots _assignSlots({
    required List<int> available,
    required int qualitySlots,
  }) {
    final remaining = [...available]..sort();

    int takePreferred(List<int> prefs) {
      for (final p in prefs) {
        final i = remaining.indexOf(p);
        if (i >= 0) return remaining.removeAt(i);
      }
      return remaining.removeLast();
    }

    final longDay = takePreferred(const [7, 6]);
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
  }) {
    final pool = [...available]..sort();
    final used = <int>[];
    final days = List<int>.filled(roles.length, 0);
    final raceDay = slots.longDay;

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
      if (_isLongRole(roles[i])) days[i] = take([slots.longDay]);
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
  }) {
    final days = _daysForWeek(
      roles: week.roles,
      slots: slots,
      available: config.availableDays,
      raceWeek: week.phase == _Phase.race,
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
            _SessionRole.easy => 1.0,
            _ => 1.15,
          },
    ];
    final totalWeight = weights.fold<double>(0, (a, b) => a + b);
    final hint = [
      for (var i = 0; i < week.roles.length; i++)
        totalWeight <= 0 ? 0.0 : support * weights[i] / totalWeight,
    ];

    final built = List<RunPlanTemplateWorkout?>.filled(week.roles.length, null);
    var spent = 0.0;

    RunPlanTemplateWorkout make(int i, double km, bool strides) => _sessionFor(
      template: template,
      config: config,
      book: book,
      week: week,
      role: week.roles[i],
      day: days[i],
      km: km,
      withStrides: strides,
    );

    // Pass 1 — quality, then the long run. How big these get is decided by
    // physiology (the long-run share, the 8% / 10% quality caps), not by
    // whatever volume happens to be left over. On a tiny week (a beginner on
    // five days runs 2–3 km at a time) a quality session's warm-up and
    // cool-down alone can out-distance the long run, so the long run is
    // built last and lifted just above the longest quality session — the long
    // run must stay the longest run of the week.
    var longestQualityKm = 0.0;
    for (var i = 0; i < week.roles.length; i++) {
      final role = week.roles[i];
      if (!_isQualityRole(role)) continue;
      final session = make(i, math.max(hint[i], 3.0), false);
      built[i] = session;
      final km = (session.targetDistanceMeters ?? 0) / 1000;
      spent += km;
      longestQualityKm = math.max(longestQualityKm, km);
    }
    var longKm = week.longKm;
    for (var i = 0; i < week.roles.length; i++) {
      if (!_isLongRole(week.roles[i])) continue;
      if (week.phase != _Phase.race) {
        longKm = math.max(longKm, longestQualityKm * 1.05);
      }
      final session = make(i, longKm, false);
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
    // 2.5 km is the shortest run worth lacing up for — unless the long run
    // itself is barely longer, in which case the easy days shrink with it.
    final minEasyKm = math.min(2.5, longKm * 0.85);
    final leftover = math.max(
      week.weekKm - spent,
      easyIndexes.length * minEasyKm,
    );
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
    var stridesUsed = week.phase != _Phase.build || week.index < 2;
    for (final i in easyIndexes) {
      final share = easyWeight <= 0
          ? minEasyKm
          : leftover * weights[i] / easyWeight;
      final wantsStrides = !stridesUsed && week.roles[i] == _SessionRole.easy;
      if (wantsStrides) stridesUsed = true;
      built[i] = make(i, share.clamp(minEasyKm, easyCap), wantsStrides);
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
      case _SessionRole.interval:
        return _interval(
          day: day,
          weekKm: week.weekKm,
          warmupKm: warmup,
          cooldownKm: cooldown,
          templateMeters:
              template.performanceIntervalMeters ??
              _defaultIntervalMeters(template.goalKind),
          desiredReps: _desiredReps(template, config, week.index, week.phase),
          book: book,
          soft: soft,
        );
      case _SessionRole.tempo:
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
        return _hills(
          day: day,
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
    // Bone and tendon adaptation lags the cardiovascular system, so a beginner
    // progression spreads its days instead of running the block Mon–Fri.
    final days = _spacedDays(config.availableDays);
    final book = _PaceBook(
      config.calibration?.paces,
      RunPaceCalculator.fiveKMeters,
    );
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
      // Late phase: one continuous easy run replaces a run/walk session so the
      // athlete practices sustained running before graduating.
      final introduceContinuous =
          w >= work.length - 2 && config.sessionsPerWeek >= 3;
      weeks.add([
        for (var s = 0; s < config.sessionsPerWeek; s++)
          if (introduceContinuous && s == 0)
            _easy(days[s], (2.0 + w * 0.25) * config.volumeFactor, book)
          else
            RunPlanTemplateWorkout(
              name: 'Corrida e caminhada',
              kind: RunWorkoutKind.easy,
              dayOfWeek: days[s],
              effortZone: 'RPE 3–4',
              notes: 'Corra confortável e caminhe antes de perder a forma.',
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
    return window == null ? base : '$base Faixa fácil: $window.';
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
        name: recovery ? 'Regenerativo' : 'Rodagem leve',
        kind: recovery ? RunWorkoutKind.recovery : RunWorkoutKind.easy,
        dayOfWeek: day,
        targetDistanceMeters: _meters(km),
        targetPaceSecPerKm: book.easy,
        effortZone: recovery ? 'Z1 / RPE 2' : 'Z1–Z2 / RPE 2–4',
        notes: _easyNote(
          recovery
              ? 'Muito leve. Acelera a recuperação entre estímulos de qualidade.'
              : 'Ritmo de conversa. Cerca de 80% do volume deve ficar aqui — '
                    'correr o fácil rápido demais é o erro mais comum.',
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
      name: 'Rodagem leve + $strides educativos',
      kind: RunWorkoutKind.easy,
      dayOfWeek: day,
      targetDistanceMeters: _meters(steadyKm + strideKm),
      targetPaceSecPerKm: book.easy,
      effortZone: 'Z1–Z2 / RPE 2–4 + educativos',
      notes: _easyNote(
        'Rodagem tranquila e, no fim, $strides tiros soltos de ${strideSec}s '
        '(não é tiro forçado): melhora economia de corrida e recruta fibras '
        'rápidas sem custo de recuperação.',
        book,
      ),
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
    name: 'Longão aeróbico',
    kind: RunWorkoutKind.long,
    dayOfWeek: day,
    targetDistanceMeters: _meters(km),
    targetPaceSecPerKm: book.easy,
    effortZone: 'Z2 / RPE 3–4',
    notes: _easyNote(
      taper
          ? 'Volume reduzido para o polimento — corte a distância, não o ritmo.'
          : 'Ritmo de conversa. Base aeróbica: o volume fácil impulsiona a '
                'maioria dos ganhos.',
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
    final blocks = km >= 24 ? 3 : 2;
    final blockKm = (km * 0.12).clamp(2.0, 5.0);
    final easyKm = math.max(km - blocks * (blockKm + 1.0) - 1.0, 3.0);
    return RunPlanTemplateWorkout(
      name: 'Longão com blocos no ritmo de prova',
      kind: RunWorkoutKind.progression,
      dayOfWeek: day,
      targetDistanceMeters: _meters(easyKm + blocks * (blockKm + 1.0) + 1.0),
      targetPaceSecPerKm: book.easy,
      effortZone: 'Z2 → ritmo de prova',
      notes:
          'A maior parte fácil e $blocks blocos no ritmo-alvo já cansado. '
          'É o treino que mais transfere para o dia da prova: ensina o corpo a '
          'poupar glicogênio e a manter a técnica em fadiga.',
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
          value: 1000,
          repeatGroup: 1,
          repeatCount: blocks,
          targetPaceMinSecPerKm: book.easyFast,
          targetPaceMaxSecPerKm: book.easySlow,
        ),
        const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
      ],
    );
  }

  static RunPlanTemplateWorkout _race(
    int day,
    double km,
    _PaceBook book,
    RunPlanGoalKind goal,
  ) => RunPlanTemplateWorkout(
    name: 'Corrida-alvo',
    kind: RunWorkoutKind.race,
    dayOfWeek: day,
    targetDistanceMeters: _meters(km),
    // Race pace for THIS distance, re-derived from fitness — never the pace of
    // the calibration race.
    targetPaceSecPerKm: book.goalRace,
    effortZone: goal == RunPlanGoalKind.marathon ? 'RPE 7–8' : 'RPE 8–9',
    notes:
        'Prova ou simulado. Saia no ritmo treinado, não no ritmo da largada.',
  );

  /// Race-week sharpener: enough to stay sharp, too little to cost anything.
  static RunPlanTemplateWorkout _sharpen(int day, double km, _PaceBook book) {
    final racePace = book.goalRace;
    final band = racePace == null ? null : RunPaceCalculator.band(racePace);
    final warmup = (km * 0.35).clamp(1.0, 2.5);
    final cooldown = (km * 0.25).clamp(0.8, 1.5);
    const reps = 3;
    return RunPlanTemplateWorkout(
      name: 'Ativação · $reps×400 m no ritmo de prova',
      kind: RunWorkoutKind.interval,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmup + reps * 0.6 + cooldown),
      targetPaceSecPerKm: racePace,
      effortZone: 'RPE 6–7',
      notes:
          'Semana de prova: o objetivo é lembrar o ritmo, não treinar. '
          'Tem que terminar com a sensação de que sobrou muito.',
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
    required double weekKm,
    required double warmupKm,
    required double cooldownKm,
    required int templateMeters,
    required int desiredReps,
    required _PaceBook book,
    required bool soft,
  }) {
    // Daniels caps VO2max work near 8% of weekly volume (10 km absolute).
    final maxWorkKm = math.min(weekKm * 0.08, 10.0);

    // A low-volume week gets shorter reps rather than an unrunnable rep count.
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
      name: '$reps×$meters m (VO₂)',
      kind: RunWorkoutKind.interval,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + workKm + restKm + cooldownKm),
      targetPaceSecPerKm: book.interval,
      effortZone: soft ? 'RPE 7–8' : 'RPE 8–9',
      notes:
          'Tiros no ritmo de VO₂máx com ${restSec}s de trote — a recuperação '
          'acompanha a duração do tiro para que todos saiam iguais. Volume '
          'forte limitado a ~8% da semana.',
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
        name: 'Limiar · $reps×${repMinutes.round()} min',
        kind: RunWorkoutKind.tempo,
        dayOfWeek: day,
        targetDistanceMeters: _meters(warmupKm + workKm + restKm + cooldownKm),
        targetPaceSecPerKm: book.tempo,
        effortZone: soft ? 'RPE 6–7' : 'RPE 7',
        notes:
            'Blocos de limiar com ${restSec}s de trote entre eles. Fracionar '
            'acima de 20 min sustenta o ritmo certo por mais tempo: mesmo '
            'estímulo, menos queda de pace no fim.',
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
      name: 'Limiar · $minutes min',
      kind: RunWorkoutKind.tempo,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + workKm + cooldownKm),
      targetPaceSecPerKm: book.tempo,
      effortZone: soft ? 'RPE 6–7' : 'RPE 7',
      notes:
          'Ritmo de limiar: sustentável, só dá para falar frases curtas. '
          'Empurra o ponto em que o lactato começa a acumular — o que mais '
          'melhora o pace que você consegue segurar numa prova.',
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
      name: 'Fartlek · $reps×${workSec}s',
      kind: RunWorkoutKind.fartlek,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmup + surgeKm + restKm + cooldown),
      targetPaceSecPerKm: book.tempo,
      effortZone: soft ? 'RPE 6' : 'RPE 7',
      notes:
          'Variações de ritmo entre limiar e VO₂. Melhora economia e a troca '
          'de marcha sem o custo de recuperação de um tiro cronometrado.',
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
    required double warmupKm,
    required double cooldownKm,
    required double workBudgetKm,
    required int reps,
    required _PaceBook book,
    required bool soft,
  }) {
    // 45–60 s uphill is the range that builds specific strength without
    // turning into a sprint; 30 s reps never accumulate enough work.
    final workSec = soft ? 45 : 60;
    final restSec = (workSec * 1.6).round();
    // On a small week the budget, not the rotation, decides the rep count —
    // the session must stay shorter than the long run. Four is the floor.
    final repKm = workSec / book.estTempo + restSec / book.estEasy;
    reps = math.min(reps, (workBudgetKm / repKm).floor()).clamp(4, 10);
    // Uphill reps plus the jog back down, so the session reports the distance
    // it actually covers rather than the budget it was handed.
    final workKm = reps * workSec / book.estTempo;
    final restKm = reps * restSec / book.estEasy;
    return RunPlanTemplateWorkout(
      name: 'Morros · $reps×${workSec}s',
      kind: RunWorkoutKind.hills,
      dayOfWeek: day,
      targetDistanceMeters: _meters(warmupKm + workKm + restKm + cooldownKm),
      // Deliberately no pace target: the same effort uphill is 30–60 s/km
      // slower, so a flat-ground pace here would be either impossible or a
      // licence to overreach. Hills are prescribed by effort.
      effortZone: soft ? 'RPE 7' : 'RPE 8',
      notes:
          'Subida forte por ${workSec}s — esforço, não pace: no morro o ritmo '
          'cai naturalmente. Volte trotando. Força específica e técnica com '
          'menos impacto que tiros no plano.',
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
      name: 'Progressivo · ${km.toStringAsFixed(0)} km',
      kind: RunWorkoutKind.progression,
      dayOfWeek: day,
      targetDistanceMeters: _meters(km),
      targetPaceSecPerKm: midPace,
      effortZone: 'RPE 5 → 7',
      notes:
          'Comece fácil e feche mais rápido. Treina distribuição de esforço e '
          'ensina a acelerar já cansado.',
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
    final blockKm = switch (goal) {
      RunPlanGoalKind.marathon || RunPlanGoalKind.half => 3.0,
      RunPlanGoalKind.tenK => 2.0,
      _ => 1.0,
    };
    // Race-pace work is aerobic, so it tolerates more volume than VO2max work.
    final blocks = math
        .min(weekKm * 0.15 / blockKm, workBudget * 0.7 / blockKm)
        .floor()
        .clamp(2, 6);
    final restSec = goal == RunPlanGoalKind.fiveK ? 90 : 120;
    final restKm = blocks * restSec / book.estEasy;
    return RunPlanTemplateWorkout(
      name: 'Ritmo de prova · $blocks×${blockKm.toStringAsFixed(0)} km',
      kind: RunWorkoutKind.tempo,
      dayOfWeek: day,
      targetDistanceMeters: _meters(
        warmupKm + blocks * blockKm + restKm + cooldownKm,
      ),
      targetPaceSecPerKm: racePace,
      effortZone: goal == RunPlanGoalKind.marathon ? 'RPE 6–7' : 'RPE 7–8',
      notes:
          'Blocos exatamente no ritmo-alvo da prova. Especificidade: calibra '
          'passada, respiração e cabeça no pace que você vai precisar segurar.',
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
