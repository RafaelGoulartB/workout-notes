import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

/// How hard the athlete wants to push weekly volume and quality load.
enum RunPlanIntensity { conservative, standard, aggressive }

/// Finish the distance vs chase a personal best.
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

enum _SessionRole { interval, tempo, easy, recovery, long, race }

/// Builds a full progressive schedule from a template blueprint + coach config.
abstract final class RunPlanComposer {
  static List<List<RunPlanTemplateWorkout>> compose(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    config.validate();
    final wantQuality = _wantsQuality(template, config);
    final soft = template.style == RunPlanTemplateStyle.performance &&
        config.intent == RunPlanIntent.finish;
    final dayByRole = _assignDays(
      available: config.availableDays,
      wantQuality: wantQuality,
      qualitySlots: !wantQuality
          ? 0
          : soft
          ? 1
          : (config.sessionsPerWeek >= 4 ? 2 : 1),
    );

    return switch (template.style) {
      RunPlanTemplateStyle.runWalk =>
        _composeRunWalk(template, config),
      RunPlanTemplateStyle.continuous =>
        _composeContinuous(template, config, dayByRole, wantQuality),
      RunPlanTemplateStyle.performance =>
        _composePerformance(template, config, dayByRole, soft),
    };
  }

  static bool _wantsQuality(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
  ) {
    if (template.style == RunPlanTemplateStyle.runWalk) return false;
    if (template.style == RunPlanTemplateStyle.continuous) {
      return config.intent == RunPlanIntent.pb && config.sessionsPerWeek >= 4;
    }
    return true;
  }

  static List<_SessionRole> _rolesForWeek({
    required int sessions,
    required bool wantQuality,
    required int weekIndex,
    required bool isRaceWeek,
    bool softFinish = false,
  }) {
    if (!wantQuality) {
      return [
        for (var i = 0; i < sessions - 1; i++) _SessionRole.easy,
        isRaceWeek ? _SessionRole.race : _SessionRole.long,
      ];
    }
    final longOrRace = isRaceWeek ? _SessionRole.race : _SessionRole.long;
    if (softFinish) {
      return switch (sessions) {
        3 => [_SessionRole.tempo, _SessionRole.easy, longOrRace],
        5 => [
          _SessionRole.tempo,
          _SessionRole.easy,
          _SessionRole.easy,
          _SessionRole.recovery,
          longOrRace,
        ],
        _ => [
          _SessionRole.tempo,
          _SessionRole.easy,
          _SessionRole.easy,
          longOrRace,
        ],
      };
    }
    switch (sessions) {
      case 3:
        final quality = weekIndex.isOdd
            ? _SessionRole.tempo
            : _SessionRole.interval;
        return [quality, _SessionRole.easy, longOrRace];
      case 5:
        return [
          _SessionRole.interval,
          _SessionRole.easy,
          _SessionRole.tempo,
          _SessionRole.recovery,
          longOrRace,
        ];
      default:
        return [
          _SessionRole.interval,
          _SessionRole.easy,
          _SessionRole.tempo,
          longOrRace,
        ];
    }
  }

  /// Stable weekday map for the plan lifetime (build config 2A).
  static Map<_SessionRole, int> _assignDays({
    required List<int> available,
    required bool wantQuality,
    int qualitySlots = 0,
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

    if (wantQuality && qualitySlots > 0) {
      final qualityDays = <int>[];
      for (var i = 0; i < qualitySlots; i++) {
        qualityDays.add(_pickQualityDay(remaining, longDay, qualityDays));
      }
      assigned[_SessionRole.interval] = qualityDays.first;
      assigned[_SessionRole.tempo] =
          qualityDays.length > 1 ? qualityDays[1] : qualityDays.first;
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

  /// Weekday list for aerobic-only weeks: easies first, long last.
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

  static int _dayFor(
    _SessionRole role,
    Map<_SessionRole, int> dayByRole,
  ) {
    switch (role) {
      case _SessionRole.race:
      case _SessionRole.long:
        return dayByRole[_SessionRole.race] ?? dayByRole[_SessionRole.long]!;
      case _SessionRole.interval:
        return dayByRole[_SessionRole.interval] ??
            dayByRole[_SessionRole.tempo] ??
            dayByRole[_SessionRole.easy]!;
      case _SessionRole.tempo:
        return dayByRole[_SessionRole.tempo] ??
            dayByRole[_SessionRole.interval] ??
            dayByRole[_SessionRole.easy]!;
      case _SessionRole.easy:
        return dayByRole[_SessionRole.easy] ?? dayByRole.values.first;
      case _SessionRole.recovery:
        return dayByRole[_SessionRole.recovery] ??
            dayByRole[_SessionRole.easy] ??
            dayByRole.values.first;
    }
  }

  // --- Continuous ----------------------------------------------------------

  static List<List<RunPlanTemplateWorkout>> _composeContinuous(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    Map<_SessionRole, int> dayByRole,
    bool wantQuality,
  ) {
    final km = template.continuousKm!;
    final paces = config.calibration?.paces;
    final aerobicDays = _aerobicDays(config.availableDays);
    final weeks = <List<RunPlanTemplateWorkout>>[];

    for (var w = 0; w < km.length; w++) {
      final row = km[w];
      final longKm = row.last * config.volumeFactor;
      final easyParts = row.length > 1 ? row.sublist(0, row.length - 1) : row;
      final easyBase =
          easyParts.reduce((a, b) => a + b) / easyParts.length;
      final isRaceWeek = template.raceFinish && w == km.length - 1;
      final roles = _rolesForWeek(
        sessions: config.sessionsPerWeek,
        wantQuality: wantQuality,
        weekIndex: w,
        isRaceWeek: isRaceWeek,
      );
      var easySlot = 0;
      final week = <RunPlanTemplateWorkout>[];
      for (final role in roles) {
        final day = !wantQuality
            ? aerobicDays[
                (role == _SessionRole.long || role == _SessionRole.race)
                    ? aerobicDays.length - 1
                    : (easySlot++).clamp(0, aerobicDays.length - 2)]
            : _dayFor(role, dayByRole);
        week.add(
          _sessionForRole(
            role: role,
            dayOfWeek: day,
            easyKm: easyBase * config.volumeFactor,
            longKm: longKm,
            intervalMeters: 400,
            intervalReps: 4,
            tempoMinutes: 12,
            taper: false,
            paces: paces,
            softQuality: true,
          ),
        );
      }
      weeks.add(week);
    }
    return weeks;
  }

  // --- Performance ---------------------------------------------------------

  static List<List<RunPlanTemplateWorkout>> _composePerformance(
    RunPlanTemplate template,
    RunPlanBuildConfig config,
    Map<_SessionRole, int> dayByRole,
    bool soft,
  ) {
    final longKm = template.performanceLongKm!;
    final easyKm = template.performanceEasyKm!;
    final intervalMeters = template.performanceIntervalMeters!;
    final baseReps = template.performanceBaseReps!;
    final paces = config.calibration?.paces;
    final raceDistanceKm = _raceDistanceKm(template.goalKind) ?? longKm.last;
    final weeks = <List<RunPlanTemplateWorkout>>[];
    final leftoverDays = () {
      final used = dayByRole.values.toSet();
      return ([...config.availableDays]..sort())
          .where((d) => !used.contains(d))
          .toList();
    }();

    for (var w = 0; w < longKm.length; w++) {
      final taper = w >= longKm.length - 2;
      final recovery = w > 0 && w % 4 == 3;
      final weekFactor = config.volumeFactor *
          (recovery
              ? 0.8
              : taper
              ? 0.7
              : 1 + w * 0.015);
      final reps = taper
          ? baseReps
          : (baseReps +
                    (w ~/ 3).clamp(0, 3) +
                    (config.intensity == RunPlanIntensity.aggressive ? 1 : 0))
                .clamp(2, 12);
      final tempoMin = taper
          ? 12
          : ((15 + (w ~/ 3) * 5) *
                    (config.intensity == RunPlanIntensity.conservative
                        ? 0.85
                        : 1.0))
                .round()
                .clamp(8, 40);
      final isRaceWeek = w == longKm.length - 1;
      final roles = _rolesForWeek(
        sessions: config.sessionsPerWeek,
        wantQuality: true,
        weekIndex: w,
        isRaceWeek: isRaceWeek,
        softFinish: soft,
      );

      var easySlot = 0;
      final week = <RunPlanTemplateWorkout>[];
      for (final role in roles) {
        int day;
        if (role == _SessionRole.easy) {
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
        week.add(
          _sessionForRole(
            role: role,
            dayOfWeek: day,
            easyKm: easyKm * weekFactor,
            longKm: (isRaceWeek ? raceDistanceKm : longKm[w]) *
                (isRaceWeek ? 1.0 : config.volumeFactor) *
                (taper && !isRaceWeek
                    ? 0.7
                    : recovery && !isRaceWeek
                    ? 0.9
                    : 1.0),
            intervalMeters: intervalMeters,
            intervalReps: reps,
            tempoMinutes: soft
                ? (tempoMin * 0.85).round().clamp(8, 30)
                : tempoMin,
            taper: taper,
            paces: paces,
            softQuality: soft,
          ),
        );
      }
      weeks.add(week);
    }
    return weeks;
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
      weeks.add([
        for (var s = 0; s < config.sessionsPerWeek; s++)
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
  }) {
    switch (role) {
      case _SessionRole.easy:
        return _easy(dayOfWeek, easyKm, paces: paces);
      case _SessionRole.recovery:
        return _easy(dayOfWeek, easyKm * 0.75, recovery: true, paces: paces);
      case _SessionRole.long:
        return RunPlanTemplateWorkout(
          name: 'Longão leve',
          kind: RunWorkoutKind.long,
          dayOfWeek: dayOfWeek,
          targetDistanceMeters: _meters(longKm),
          targetPaceSecPerKm: paces?.easySecPerKm,
          effortZone: 'Z2 / RPE 3–4',
          notes: taper
              ? 'Reduza o volume e preserve a leveza.'
              : 'Ritmo de conversa; não transforme o longão em prova.',
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
          taper || softQuality,
          paces: paces,
        );
      case _SessionRole.tempo:
        return _tempo(
          dayOfWeek,
          tempoMinutes,
          taper || softQuality,
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
    notes: 'Ritmo confortável, respirando com controle.',
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
      name: '$reps×$meters m controlados',
      kind: RunWorkoutKind.interval,
      dayOfWeek: day,
      targetPaceSecPerKm: paces?.intervalSecPerKm,
      effortZone: soft ? 'RPE 7' : 'RPE 8',
      notes:
          'Corra forte e uniforme; preserve a técnica até a última repetição.',
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
      name: 'Ritmo controlado · $minutes min',
      kind: RunWorkoutKind.tempo,
      dayOfWeek: day,
      targetPaceSecPerKm: paces?.tempoSecPerKm,
      effortZone: soft ? 'RPE 6' : 'RPE 7',
      notes: 'Esforço sustentado: frases curtas, sem sprintar.',
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
}
