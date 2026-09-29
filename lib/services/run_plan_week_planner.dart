part of 'run_plan_composer.dart';

/// Turns a template + config into the week-by-week plan: periodisation phase,
/// volume budget, session roles, weekday slots, and then the materialised
/// sessions of every week.
abstract final class _WeekPlanner {
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
      final floorKm = RunPlanComposer._requiredPeakLongKm(
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
        return _SessionBuilders._easy(
          day,
          km,
          book,
          strides: withStrides ? _strideCount(config) : 0,
        );
      case _SessionRole.recovery:
        return _SessionBuilders._easy(day, km, book, recovery: true);
      case _SessionRole.long:
        return _SessionBuilders._long(
          day,
          km,
          book,
          taper: week.phase == _Phase.taper,
        );
      case _SessionRole.longRacePace:
        return _SessionBuilders._longRacePace(day, km, book);
      case _SessionRole.race:
        return _SessionBuilders._race(day, km, book, template.goalKind);
      case _SessionRole.sharpen:
        return _SessionBuilders._sharpen(day, km, book);
      case _SessionRole.test:
        return _SessionBuilders._test(
              day,
              book,
              template.goalKind,
              week.weekKm,
              week.longKm,
            ) ??
            _SessionBuilders._fartlek(
              day,
              km,
              book,
              weekKm: week.weekKm,
              soft: true,
            );
      case _SessionRole.interval:
        final maxWorkKm = _vo2WorkCapKm(week.weekKm, book);
        // Fewer than three 400 m reps is not a VO2 session; a fartlek gives
        // the same pace change without pretending otherwise.
        if (maxWorkKm < 1.2) {
          return _SessionBuilders._fartlek(
            day,
            km,
            book,
            weekKm: week.weekKm,
            soft: soft,
          );
        }
        return _SessionBuilders._interval(
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
          return _SessionBuilders._fartlek(
            day,
            km,
            book,
            weekKm: week.weekKm,
            soft: true,
          );
        }
        return _SessionBuilders._tempo(
          day: day,
          weekKm: week.weekKm,
          warmupKm: warmup,
          cooldownKm: cooldown,
          desiredMinutes: _desiredTempoMinutes(config, week.index, week.phase),
          book: book,
          soft: soft,
        );
      case _SessionRole.fartlek:
        return _SessionBuilders._fartlek(
          day,
          km,
          book,
          weekKm: week.weekKm,
          soft: soft,
        );
      case _SessionRole.hills:
        if (!config.includeHills) {
          return _SessionBuilders._fartlek(
            day,
            km,
            book,
            weekKm: week.weekKm,
            soft: soft,
          );
        }
        return _SessionBuilders._hills(
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
        return _SessionBuilders._progression(day, km, book);
      case _SessionRole.racePace:
        return _SessionBuilders._racePaceSession(
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
}
