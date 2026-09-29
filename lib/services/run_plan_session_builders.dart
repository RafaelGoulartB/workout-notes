part of 'run_plan_composer.dart';

/// Builds one concrete session (easy, long, intervals, tempo, ...) and the
/// run/walk progressions from the paces, volumes and language of a week.
abstract final class _SessionBuilders {
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
          score += _WeekPlanner._circularGap(day, s);
          if (_WeekPlanner._adjacent(day, s)) score -= 4;
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
