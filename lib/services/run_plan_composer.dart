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

  const RunPlanBuildConfig({
    required this.sessionsPerWeek,
    required this.availableDays,
    this.intent = RunPlanIntent.finish,
    this.intensity = RunPlanIntensity.standard,
    this.calibration,
    this.raceDate,
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
  }
}

/// Internal session roles. Quality roles map onto [RunWorkoutKind] variety
/// used in evidence-based programs (VO2, threshold, neuromuscular, hills).
enum _SessionRole {
  interval,
  tempo,
  fartlek,
  hills,
  progression,
  easy,
  recovery,
  long,
  race,
}

bool _isQualityRole(_SessionRole role) =>
    role == _SessionRole.interval ||
    role == _SessionRole.tempo ||
    role == _SessionRole.fartlek ||
    role == _SessionRole.hills ||
    role == _SessionRole.progression;

/// Builds a full progressive schedule from a template blueprint + coach config.
///
/// Design follows polarized / pyramidal best practice (~80% easy, ~20% quality):
/// - Easy + long build aerobic base (Seiler / Zone 2)
/// - Intervals develop VO2max
/// - Tempo / cruise intervals develop lactate threshold
/// - Fartlek / hills / progression add economy and race-specific stimulus
/// - Recovery every 4th week; taper last 2 weeks
abstract final class RunPlanComposer {
  static List<List<RunPlanTemplateWorkout>> compose(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    config.validate();
    final qualitySlots = _qualitySlotCount(template, config);
    final dayByRole = _assignDays(
      available: config.availableDays,
      qualitySlots: qualitySlots,
    );

    return switch (template.style) {
      RunPlanTemplateStyle.runWalk => _composeRunWalk(template, config),
      RunPlanTemplateStyle.continuous =>
        _composeContinuous(template, config, dayByRole, qualitySlots),
      RunPlanTemplateStyle.performance =>
        _composePerformance(template, config, dayByRole),
    };
  }

  /// How many dedicated quality weekdays to reserve for the whole plan.
  static int _qualitySlotCount(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    if (template.style == RunPlanTemplateStyle.runWalk) return 0;
    // Return-to-running: ease back with fartlek only after intro — 1 slot.
    if (template.key == 'return') return 1;
    if (config.sessionsPerWeek >= 4) return 2;
    return 1;
  }

  /// True when this week should include structured quality (not all-easy).
  static bool _weekHasQuality({
    required RunPlanTemplate template,
    required int weekIndex,
    required int totalWeeks,
  }) {
    if (template.style == RunPlanTemplateStyle.runWalk) return false;
    if (template.style == RunPlanTemplateStyle.performance) return true;

    // Continuous: short aerobic intro, then quality. Return stays gentler longer.
    final introWeeks = template.key == 'return'
        ? (totalWeeks / 2).ceil().clamp(2, 4)
        : (totalWeeks / 4).ceil().clamp(1, 2);
    if (weekIndex < introWeeks) return false;
    // Taper / race week: keep light quality only if not the race week itself.
    if (template.raceFinish && weekIndex == totalWeeks - 1) return false;
    return true;
  }

  /// Polarized weekly shape with rotating quality stimuli.
  static List<_SessionRole> _rolesForWeek({
    required int sessions,
    required int weekIndex,
    required bool isRaceWeek,
    required bool hasQuality,
    required bool recoveryWeek,
    required bool taper,
  }) {
    final longOrRace = isRaceWeek ? _SessionRole.race : _SessionRole.long;
    if (!hasQuality) {
      return [
        for (var i = 0; i < sessions - 1; i++) _SessionRole.easy,
        longOrRace,
      ];
    }

    // Recovery / taper: one softer quality stimulus only.
    if (recoveryWeek || taper) {
      final softQ = weekIndex.isEven ? _SessionRole.fartlek : _SessionRole.tempo;
      return switch (sessions) {
        3 => [softQ, _SessionRole.recovery, longOrRace],
        5 => [
          softQ,
          _SessionRole.easy,
          _SessionRole.recovery,
          _SessionRole.recovery,
          longOrRace,
        ],
        _ => [softQ, _SessionRole.easy, _SessionRole.recovery, longOrRace],
      };
    }

    final primary = _primaryQuality(weekIndex);
    final secondary = _secondaryQuality(weekIndex);

    return switch (sessions) {
      3 => [primary, _SessionRole.easy, longOrRace],
      5 => [
        primary,
        _SessionRole.easy,
        secondary,
        _SessionRole.recovery,
        longOrRace,
      ],
      _ => [primary, _SessionRole.easy, secondary, longOrRace],
    };
  }

  /// Primary quality rotation — covers VO2, threshold, hills, neuromuscular.
  static _SessionRole _primaryQuality(int weekIndex) =>
      const [
        _SessionRole.interval,
        _SessionRole.tempo,
        _SessionRole.hills,
        _SessionRole.interval,
        _SessionRole.fartlek,
        _SessionRole.tempo,
      ][weekIndex % 6];

  /// Second quality slot (4–5 day weeks) — complementary, not duplicate.
  static _SessionRole _secondaryQuality(int weekIndex) =>
      const [
        _SessionRole.tempo,
        _SessionRole.fartlek,
        _SessionRole.tempo,
        _SessionRole.progression,
        _SessionRole.tempo,
        _SessionRole.hills,
      ][weekIndex % 6];

  /// Stable weekday map for the plan lifetime.
  static Map<_SessionRole, int> _assignDays({
    required List<int> available,
    required int qualitySlots,
  }) {
    final remaining = [...available]..sort();
    final assigned = <_SessionRole, int>{};

    int takePreferred(List<int> prefs) {
      for (final p in prefs) {
        final i = remaining.indexOf(p);
        if (i >= 0) return remaining.removeAt(i);
      }
      return remaining.removeLast();
    }

    final longDay = takePreferred(const [7, 6]);
    assigned[_SessionRole.long] = longDay;
    assigned[_SessionRole.race] = longDay;

    if (qualitySlots > 0) {
      final qualityDays = <int>[];
      for (var i = 0; i < qualitySlots; i++) {
        qualityDays.add(_pickQualityDay(remaining, longDay, qualityDays));
      }
      // All quality kinds share these reserved weekdays.
      final q0 = qualityDays.first;
      final q1 = qualityDays.length > 1 ? qualityDays[1] : q0;
      for (final role in const [
        _SessionRole.interval,
        _SessionRole.tempo,
        _SessionRole.fartlek,
        _SessionRole.hills,
        _SessionRole.progression,
      ]) {
        // Alternate primary → q0, secondary-ish → q1 by role family.
        assigned[role] = (role == _SessionRole.interval ||
                role == _SessionRole.hills ||
                role == _SessionRole.fartlek)
            ? q0
            : q1;
      }
      // Ensure interval always on q0 and tempo on q1 when two slots exist.
      assigned[_SessionRole.interval] = q0;
      assigned[_SessionRole.hills] = q0;
      assigned[_SessionRole.tempo] = q1;
      assigned[_SessionRole.progression] = q1;
      assigned[_SessionRole.fartlek] = qualitySlots > 1 ? q1 : q0;
    }

    remaining.sort();
    if (remaining.isNotEmpty) {
      assigned[_SessionRole.easy] = remaining.first;
    }
    if (remaining.length > 1) {
      assigned[_SessionRole.recovery] = remaining[1];
    } else if (remaining.isNotEmpty) {
      assigned[_SessionRole.recovery] = remaining.first;
    }
    assigned[_SessionRole.easy] = assigned[_SessionRole.easy] ?? longDay;
    return assigned;
  }

  static List<int> _aerobicDays(List<int> available) {
    final days = [...available]..sort();
    final weekend = days.where((d) => d == 7 || d == 6).toList();
    final longDay = weekend.isNotEmpty ? weekend.last : days.last;
    final easies = days.where((d) => d != longDay).toList()..sort();
    return [...easies, longDay];
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

  static int _dayFor(_SessionRole role, Map<_SessionRole, int> dayByRole) {
    if (dayByRole.containsKey(role)) return dayByRole[role]!;
    if (_isQualityRole(role)) {
      return dayByRole[_SessionRole.interval] ??
          dayByRole[_SessionRole.tempo] ??
          dayByRole[_SessionRole.easy]!;
    }
    switch (role) {
      case _SessionRole.race:
      case _SessionRole.long:
        return dayByRole[_SessionRole.race] ?? dayByRole[_SessionRole.long]!;
      case _SessionRole.easy:
        return dayByRole[_SessionRole.easy] ?? dayByRole.values.first;
      case _SessionRole.recovery:
        return dayByRole[_SessionRole.recovery] ??
            dayByRole[_SessionRole.easy] ??
            dayByRole.values.first;
      default:
        return dayByRole.values.first;
    }
  }

  // --- Continuous ----------------------------------------------------------

  static List<List<RunPlanTemplateWorkout>> _composeContinuous(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    Map<_SessionRole, int> dayByRole,
    int qualitySlots,
  ) {
    final km = template.continuousKm!;
    final paces = config.calibration?.paces;
    final aerobicDays = _aerobicDays(config.availableDays);
    final weeks = <List<RunPlanTemplateWorkout>>[];
    final leftoverDays = _leftoverDays(config.availableDays, dayByRole);

    // Derive a sensible interval length from the goal.
    final intervalMeters = switch (template.goalKind) {
      RunPlanGoalKind.fiveK => 400,
      RunPlanGoalKind.tenK => 800,
      RunPlanGoalKind.half || RunPlanGoalKind.marathon => 1000,
      _ => 400,
    };

    for (var w = 0; w < km.length; w++) {
      final row = km[w];
      final longKm = row.last * config.volumeFactor;
      final easyParts = row.length > 1 ? row.sublist(0, row.length - 1) : row;
      final easyBase =
          easyParts.reduce((a, b) => a + b) / easyParts.length;
      final isRaceWeek = template.raceFinish && w == km.length - 1;
      final taper = template.raceFinish && w >= km.length - 2 && !isRaceWeek;
      final recovery = w > 0 && w % 4 == 3 && !taper && !isRaceWeek;
      final hasQuality = _weekHasQuality(
        template: template,
        weekIndex: w,
        totalWeeks: km.length,
      );
      final roles = _rolesForWeek(
        sessions: config.sessionsPerWeek,
        weekIndex: w,
        isRaceWeek: isRaceWeek,
        hasQuality: hasQuality,
        recoveryWeek: recovery,
        taper: taper,
      );

      final reps = ((4 + (w ~/ 3)) * config.qualityFactor).round().clamp(3, 8);
      final tempoMin =
          ((12 + (w ~/ 3) * 3) * config.qualityFactor).round().clamp(8, 25);

      weeks.add(
        _buildWeek(
          roles: roles,
          dayByRole: dayByRole,
          aerobicDays: aerobicDays,
          leftoverDays: leftoverDays,
          hasQuality: hasQuality,
          easyKm: easyBase * config.volumeFactor * (recovery ? 0.85 : 1.0),
          longKm: longKm * (taper ? 0.75 : recovery ? 0.9 : 1.0),
          intervalMeters: intervalMeters,
          intervalReps: reps,
          tempoMinutes: tempoMin,
          taper: taper,
          paces: paces,
          softQuality: config.intent == RunPlanIntent.finish,
          weekIndex: w,
        ),
      );
    }
    return weeks;
  }

  // --- Performance ---------------------------------------------------------

  static List<List<RunPlanTemplateWorkout>> _composePerformance(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    Map<_SessionRole, int> dayByRole,
  ) {
    final longKm = template.performanceLongKm!;
    final easyKm = template.performanceEasyKm!;
    final intervalMeters = template.performanceIntervalMeters!;
    final baseReps = template.performanceBaseReps!;
    final paces = config.calibration?.paces;
    final raceDistanceKm = _raceDistanceKm(template.goalKind) ?? longKm.last;
    final weeks = <List<RunPlanTemplateWorkout>>[];
    final leftoverDays = _leftoverDays(config.availableDays, dayByRole);
    final aerobicDays = _aerobicDays(config.availableDays);

    for (var w = 0; w < longKm.length; w++) {
      final taper = w >= longKm.length - 2;
      final isRaceWeek = w == longKm.length - 1;
      final recovery = w > 0 && w % 4 == 3 && !taper;
      final weekFactor = config.volumeFactor *
          (recovery
              ? 0.8
              : taper
              ? 0.7
              : 1 + w * 0.015);
      final reps = ((taper ? baseReps : baseReps + (w ~/ 3).clamp(0, 3)) *
              config.qualityFactor)
          .round()
          .clamp(2, 12);
      final tempoMin = ((taper ? 12 : 15 + (w ~/ 3) * 5) * config.qualityFactor)
          .round()
          .clamp(8, 40);
      final roles = _rolesForWeek(
        sessions: config.sessionsPerWeek,
        weekIndex: w,
        isRaceWeek: isRaceWeek,
        hasQuality: true,
        recoveryWeek: recovery,
        taper: taper && !isRaceWeek,
      );

      weeks.add(
        _buildWeek(
          roles: roles,
          dayByRole: dayByRole,
          aerobicDays: aerobicDays,
          leftoverDays: leftoverDays,
          hasQuality: true,
          easyKm: easyKm * weekFactor,
          longKm: (isRaceWeek ? raceDistanceKm : longKm[w]) *
              (isRaceWeek ? 1.0 : config.volumeFactor) *
              (taper && !isRaceWeek
                  ? 0.7
                  : recovery
                  ? 0.9
                  : 1.0),
          intervalMeters: intervalMeters,
          intervalReps: reps,
          tempoMinutes: tempoMin,
          taper: taper,
          paces: paces,
          softQuality: config.intent == RunPlanIntent.finish,
          weekIndex: w,
        ),
      );
    }
    return weeks;
  }

  static List<int> _leftoverDays(
    List<int> available,
    Map<_SessionRole, int> dayByRole,
  ) {
    final used = dayByRole.values.toSet();
    return ([...available]..sort()).where((d) => !used.contains(d)).toList();
  }

  static List<RunPlanTemplateWorkout> _buildWeek({
    required List<_SessionRole> roles,
    required Map<_SessionRole, int> dayByRole,
    required List<int> aerobicDays,
    required List<int> leftoverDays,
    required bool hasQuality,
    required double easyKm,
    required double longKm,
    required int intervalMeters,
    required int intervalReps,
    required int tempoMinutes,
    required bool taper,
    required RunPaces? paces,
    required bool softQuality,
    required int weekIndex,
  }) {
    var easySlot = 0;
    final week = <RunPlanTemplateWorkout>[];
    for (final role in roles) {
      int day;
      if (!hasQuality) {
        day = aerobicDays[
            (role == _SessionRole.long || role == _SessionRole.race)
                ? aerobicDays.length - 1
                : (easySlot++).clamp(0, aerobicDays.length - 2)];
      } else if (role == _SessionRole.easy) {
        if (easySlot == 0 && dayByRole.containsKey(_SessionRole.easy)) {
          day = dayByRole[_SessionRole.easy]!;
        } else if (easySlot > 0 && leftoverDays.isNotEmpty) {
          day = leftoverDays[(easySlot - 1).clamp(0, leftoverDays.length - 1)];
        } else if (dayByRole.containsKey(_SessionRole.recovery) &&
            easySlot > 0) {
          day = dayByRole[_SessionRole.recovery]!;
        } else {
          day = dayByRole[_SessionRole.easy] ?? dayByRole.values.first;
        }
        easySlot++;
      } else {
        day = _dayFor(role, dayByRole);
      }

      // Occasional progression finish on the long run (science: race-pace
      // specificity without a full second quality day).
      final longAsProgression = role == _SessionRole.long &&
          !taper &&
          weekIndex > 2 &&
          weekIndex % 5 == 4;

      week.add(
        _sessionForRole(
          role: longAsProgression ? _SessionRole.progression : role,
          dayOfWeek: day,
          easyKm: easyKm,
          longKm: longKm,
          intervalMeters: intervalMeters,
          intervalReps: intervalReps,
          tempoMinutes: tempoMinutes,
          taper: taper,
          paces: paces,
          softQuality: softQuality,
          asLongProgression: longAsProgression,
        ),
      );
    }
    return week;
  }

  // --- Run / walk ----------------------------------------------------------

  static List<List<RunPlanTemplateWorkout>> _composeRunWalk(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    final work = template.runWalkWork!;
    final rest = template.runWalkRest!;
    final reps = template.runWalkReps!;
    final days = [...config.availableDays]..sort();
    final weeks = <List<RunPlanTemplateWorkout>>[];

    for (var w = 0; w < work.length; w++) {
      final sessionReps = (reps[w] *
              (config.intensity == RunPlanIntensity.aggressive
                  ? 1.1
                  : config.intensity == RunPlanIntensity.conservative
                  ? 0.9
                  : 1.0))
          .round()
          .clamp(2, 12);
      // Late phase: one continuous easy run replaces a run/walk session so the
      // athlete practices sustained running before graduating.
      final introduceContinuous = w >= work.length - 2 &&
          config.sessionsPerWeek >= 3;
      weeks.add([
        for (var s = 0; s < config.sessionsPerWeek; s++)
          if (introduceContinuous && s == 0)
            _easy(
              days[s],
              (2.0 + w * 0.25) * config.volumeFactor,
              paces: config.calibration?.paces,
            )
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

  static RunPlanTemplateWorkout _sessionForRole({
    required _SessionRole role,
    required int dayOfWeek,
    required double easyKm,
    required double longKm,
    required int intervalMeters,
    required int intervalReps,
    required int tempoMinutes,
    required bool taper,
    required RunPaces? paces,
    required bool softQuality,
    bool asLongProgression = false,
  }) {
    switch (role) {
      case _SessionRole.easy:
        return _easy(dayOfWeek, easyKm, paces: paces);
      case _SessionRole.recovery:
        return _easy(dayOfWeek, easyKm * 0.75, recovery: true, paces: paces);
      case _SessionRole.long:
        return RunPlanTemplateWorkout(
          name: 'Longão aeróbico',
          kind: RunWorkoutKind.long,
          dayOfWeek: dayOfWeek,
          targetDistanceMeters: _meters(longKm),
          targetPaceSecPerKm: paces?.easySecPerKm,
          effortZone: 'Z2 / RPE 3–4',
          notes: taper
              ? 'Reduza o volume e preserve a leveza.'
              : 'Ritmo de conversa. Base aeróbica: o volume fácil impulsiona a maioria dos ganhos.',
        );
      case _SessionRole.race:
        return RunPlanTemplateWorkout(
          name: 'Corrida-alvo',
          kind: RunWorkoutKind.race,
          dayOfWeek: dayOfWeek,
          targetDistanceMeters: _meters(longKm),
          targetPaceSecPerKm: paces?.raceSecPerKm,
          effortZone: 'RPE 8–9',
          notes: 'Prova ou simulado. Confie no ritmo treinado.',
        );
      case _SessionRole.interval:
        return _interval(
          dayOfWeek,
          intervalMeters,
          intervalReps,
          softQuality || taper,
          paces: paces,
        );
      case _SessionRole.tempo:
        return _tempo(
          dayOfWeek,
          tempoMinutes,
          softQuality || taper,
          paces: paces,
        );
      case _SessionRole.fartlek:
        return _fartlek(
          dayOfWeek,
          easyKm * 1.05,
          softQuality || taper,
          paces: paces,
        );
      case _SessionRole.hills:
        return _hills(
          dayOfWeek,
          intervalReps.clamp(4, 10),
          softQuality || taper,
          paces: paces,
        );
      case _SessionRole.progression:
        return asLongProgression
            ? _progressionLong(dayOfWeek, longKm, paces: paces)
            : _progression(
                dayOfWeek,
                easyKm * 1.1,
                softQuality || taper,
                paces: paces,
              );
    }
  }

  static double _meters(double km) => (km * 100).round() * 10;

  static double? _raceDistanceKm(RunPlanGoalKind goal) => switch (goal) {
    RunPlanGoalKind.fiveK => 5.0,
    RunPlanGoalKind.tenK => 10.0,
    RunPlanGoalKind.half => 21.1,
    RunPlanGoalKind.marathon => 42.195,
    _ => null,
  };

  static RunPlanTemplateWorkout _easy(
    int day,
    double km, {
    bool recovery = false,
    RunPaces? paces,
  }) => RunPlanTemplateWorkout(
    name: recovery ? 'Regenerativo' : 'Rodagem leve',
    kind: recovery ? RunWorkoutKind.recovery : RunWorkoutKind.easy,
    dayOfWeek: day,
    targetDistanceMeters: _meters(km),
    targetPaceSecPerKm: paces?.easySecPerKm,
    effortZone: recovery ? 'Z1 / RPE 2' : 'Z1–Z2 / RPE 2–4',
    notes: recovery
        ? 'Muito leve. Acelera a recuperação entre estímulos de qualidade.'
        : 'Ritmo de conversa (Z1–Z2). Cerca de 80% do volume deve ficar aqui.',
  );

  static RunPlanTemplateWorkout _interval(
    int day,
    int meters,
    int reps,
    bool soft, {
    RunPaces? paces,
  }) {
    final band = paces == null
        ? null
        : RunPaceCalculator.band(paces.intervalSecPerKm);
    return RunPlanTemplateWorkout(
      name: '$reps×$meters m (VO₂)',
      kind: RunWorkoutKind.interval,
      dayOfWeek: day,
      targetPaceSecPerKm: paces?.intervalSecPerKm,
      effortZone: soft ? 'RPE 7' : 'RPE 8–9',
      notes:
          'Tiros no ritmo de VO₂máx. Recuperação completa o bastante para manter a qualidade — não o volume.',
      steps: [
        const RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
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
          value: meters >= 800 ? 120 : 90,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
      ],
    );
  }

  static RunPlanTemplateWorkout _tempo(
    int day,
    int minutes,
    bool soft, {
    RunPaces? paces,
  }) {
    final band = paces == null
        ? null
        : RunPaceCalculator.band(paces.tempoSecPerKm);
    return RunPlanTemplateWorkout(
      name: 'Limiar · $minutes min',
      kind: RunWorkoutKind.tempo,
      dayOfWeek: day,
      targetPaceSecPerKm: paces?.tempoSecPerKm,
      effortZone: soft ? 'RPE 6' : 'RPE 7',
      notes:
          'Ritmo de limiar (tempo). Sustentável, frases curtas — melhora a capacidade de manter pace de prova.',
      steps: [
        const RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          metric: RunIntervalMetric.time,
          value: minutes * 60,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
      ],
    );
  }

  static RunPlanTemplateWorkout _fartlek(
    int day,
    double km,
    bool soft, {
    RunPaces? paces,
  }) {
    final workSec = soft ? 45 : 60;
    final reps = soft ? 6 : 8;
    final band = paces == null
        ? null
        : RunPaceCalculator.band(
            (paces.intervalSecPerKm + paces.tempoSecPerKm) / 2,
          );
    return RunPlanTemplateWorkout(
      name: 'Fartlek · $reps×${workSec}s',
      kind: RunWorkoutKind.fartlek,
      dayOfWeek: day,
      targetDistanceMeters: _meters(km),
      targetPaceSecPerKm: paces?.tempoSecPerKm,
      effortZone: soft ? 'RPE 6' : 'RPE 7',
      notes:
          'Variações de ritmo. Melhora economia e adapta o corpo a mudanças de pace sem o custo de um tiro clássico.',
      steps: [
        const RunPlanTemplateStep(role: RunStepRole.warmup, value: 1200),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          metric: RunIntervalMetric.time,
          value: workSec,
          repeatGroup: 1,
          repeatCount: reps,
          targetPaceMinSecPerKm: band?.$1,
          targetPaceMaxSecPerKm: band?.$2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: soft ? 75 : 60,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 800),
      ],
    );
  }

  static RunPlanTemplateWorkout _hills(
    int day,
    int reps,
    bool soft, {
    RunPaces? paces,
  }) {
    final workSec = soft ? 30 : 45;
    return RunPlanTemplateWorkout(
      name: 'Morros · $reps×${workSec}s',
      kind: RunWorkoutKind.hills,
      dayOfWeek: day,
      effortZone: soft ? 'RPE 7' : 'RPE 8',
      notes:
          'Subidas curtas: força específica, técnica e potência sem impacto alto de tiros em plano.',
      steps: [
        const RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          metric: RunIntervalMetric.time,
          value: workSec,
          repeatGroup: 1,
          repeatCount: reps,
          targetPaceMinSecPerKm: paces?.intervalSecPerKm,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: workSec + 30,
          repeatGroup: 1,
          repeatCount: reps,
        ),
        const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
      ],
    );
  }

  static RunPlanTemplateWorkout _progression(
    int day,
    double km,
    bool soft, {
    RunPaces? paces,
  }) {
    final third = _meters(km / 3);
    return RunPlanTemplateWorkout(
      name: 'Progressivo · ${_meters(km) ~/ 1000} km',
      kind: RunWorkoutKind.progression,
      dayOfWeek: day,
      targetDistanceMeters: _meters(km),
      targetPaceSecPerKm: paces?.tempoSecPerKm,
      effortZone: soft ? 'RPE 5–6' : 'RPE 5–7',
      notes:
          'Comece fácil e feche mais rápido. Ensina distribuição de esforço e pace de prova.',
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.warmup,
          value: third.round(),
          targetPaceMinSecPerKm: paces?.easySecPerKm,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          value: third.round(),
          targetPaceMinSecPerKm: paces == null
              ? null
              : (paces.easySecPerKm + paces.tempoSecPerKm) / 2,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: third.round(),
          targetPaceMinSecPerKm: paces?.tempoSecPerKm,
          targetPaceMaxSecPerKm: paces?.intervalSecPerKm,
        ),
      ],
    );
  }

  static RunPlanTemplateWorkout _progressionLong(
    int day,
    double km, {
    RunPaces? paces,
  }) {
    final easy = _meters(km * 0.7);
    final pickUp = _meters(km * 0.3);
    return RunPlanTemplateWorkout(
      name: 'Longão progressivo',
      kind: RunWorkoutKind.progression,
      dayOfWeek: day,
      targetDistanceMeters: _meters(km),
      targetPaceSecPerKm: paces?.easySecPerKm,
      effortZone: 'Z2 → limiar leve',
      notes:
          'Maior parte fácil; últimos ~30% um pouco mais firmes. Especificidade de prova sem destruir a recuperação.',
      steps: [
        RunPlanTemplateStep(
          role: RunStepRole.steady,
          value: easy.round(),
          targetPaceMinSecPerKm: paces?.easySecPerKm,
        ),
        RunPlanTemplateStep(
          role: RunStepRole.work,
          value: pickUp.round(),
          targetPaceMinSecPerKm: paces?.tempoSecPerKm,
        ),
      ],
    );
  }
}
