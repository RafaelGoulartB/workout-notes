import 'dart:math' as math;

import 'package:workout_notes/services/run_pace_calculator.dart';

/// How a plan week went, from what was actually run.
enum RunWeekOutcome {
  /// ≥80% of the planned kilometres.
  full,

  /// 50–80%: most of the week, not all of it.
  partial,

  /// <50%: the week effectively did not happen.
  missed,
}

/// One past plan week, planned against actual.
class RunPlanWeekReview {
  final int weekIndex;
  final DateTime weekStart;
  final double plannedKm;

  /// Every run recorded that calendar week — linked to the plan or not. A
  /// runner who did the long run without starting it from the plan still
  /// ran it.
  final double doneKm;
  final int plannedSessions;
  final int doneSessions;
  final int qualityPlanned;
  final int qualityDone;

  /// Mean RPE of the easy runs that carried one (1–10), if any.
  final double? easyRpe;

  /// Runs rated at RPE ≥9 that were not races or tests.
  final int maxedOutRuns;

  /// Runs with a feeling rating of 1–2 (out of 5).
  final int badFeelingRuns;

  const RunPlanWeekReview({
    required this.weekIndex,
    required this.weekStart,
    required this.plannedKm,
    required this.doneKm,
    required this.plannedSessions,
    required this.doneSessions,
    this.qualityPlanned = 0,
    this.qualityDone = 0,
    this.easyRpe,
    this.maxedOutRuns = 0,
    this.badFeelingRuns = 0,
  });

  double get adherence =>
      plannedKm <= 0 ? 1 : (doneKm / plannedKm).clamp(0.0, 2.0);

  RunWeekOutcome get outcome => adherence >= 0.8
      ? RunWeekOutcome.full
      : adherence >= 0.5
      ? RunWeekOutcome.partial
      : RunWeekOutcome.missed;

  /// The body is telling the plan it is too much: easy runs are not easy,
  /// or several runs were all-out.
  bool get fatigued =>
      (easyRpe != null && easyRpe! >= 6.5) ||
      maxedOutRuns >= 2 ||
      badFeelingRuns >= 2;
}

/// Where a fitness estimate came from.
enum RunFitnessSource { test, race, workout, bestEffort }

/// A fitness estimate (Daniels VDOT) taken from something the athlete ran.
class RunFitnessSample {
  final DateTime date;
  final double vdot;
  final RunFitnessSource source;

  const RunFitnessSample({
    required this.date,
    required this.vdot,
    required this.source,
  });

  /// VDOT from a time trial or race result.
  static RunFitnessSample? fromResult({
    required DateTime date,
    required double distanceMeters,
    required int seconds,
    required RunFitnessSource source,
  }) {
    if (!RunPaceCalculator.isPlausibleRace(
      distanceMeters: distanceMeters,
      timeSeconds: seconds,
    )) {
      return null;
    }
    if (distanceMeters < 1500) return null;
    return RunFitnessSample(
      date: date,
      vdot: RunPaceCalculator.vdotFor(
        distanceMeters: distanceMeters,
        timeSeconds: seconds,
      ),
      source: source,
    );
  }

  /// VDOT implied by the pace actually held in quality reps.
  ///
  /// Interval reps are prescribed at ~98% VO2max and threshold at ~88%; the
  /// fitness that makes the achieved pace sit at that intensity is the
  /// estimate. Needs at least three measured reps — one rep is noise.
  static RunFitnessSample? fromWorkPaces({
    required DateTime date,
    required List<double> paces,
    required double fractionOfVo2Max,
  }) {
    final valid = [
      for (final p in paces)
        if (p >= RunPaceCalculator.minPlausibleSecPerKm &&
            p <= RunPaceCalculator.maxPlausibleSecPerKm)
          p,
    ]..sort();
    if (valid.length < 3) return null;
    final median = valid[valid.length ~/ 2];
    final metresPerMinute = 60000 / median;
    final cost =
        -4.60 +
        0.182258 * metresPerMinute +
        0.000104 * metresPerMinute * metresPerMinute;
    final vdot = cost / fractionOfVo2Max;
    if (!vdot.isFinite || vdot < 15 || vdot > 90) return null;
    return RunFitnessSample(
      date: date,
      vdot: vdot,
      source: RunFitnessSource.workout,
    );
  }
}

/// What the weekly review proposes.
enum RunPlanAdjustment {
  /// Nothing to change in volume.
  none,

  /// Partial week or fatigue: repeat this level instead of progressing.
  hold,

  /// One week missed: resume a notch below the last solid week.
  stepBack,

  /// Two or more weeks missed: rebuild from a clearly lower volume.
  rebuild,
}

/// A proposed re-plan for the rest of a plan.
class RunPlanAdaptationProposal {
  /// Current plan week (zero-based) when the review ran.
  final int weekIndex;

  /// First week that will be re-planned.
  final int fromWeek;

  final RunPlanAdjustment adjustment;

  /// The week(s) the decision is based on, most recent last.
  final List<RunPlanWeekReview> reviews;

  /// Consecutive missed weeks right before now.
  final int missedWeeks;

  /// Weekly volume the re-planned part opens with, in km.
  final double? baselineKm;

  /// Fitness the plan expected by now, and the new estimate (VDOT). Equal
  /// when paces stay as they are.
  final double? expectedVdot;
  final double? newVdot;
  final RunFitnessSource? paceSource;

  /// Long break: a return-to-running plan is the safer path.
  final bool suggestReturnPlan;

  /// Weeks the re-planned part should last when there is no race date
  /// (missed weeks extend the plan instead of being skipped).
  final int? remainingWeeks;

  const RunPlanAdaptationProposal({
    required this.weekIndex,
    required this.fromWeek,
    required this.adjustment,
    required this.reviews,
    this.missedWeeks = 0,
    this.baselineKm,
    this.expectedVdot,
    this.newVdot,
    this.paceSource,
    this.suggestReturnPlan = false,
    this.remainingWeeks,
  });

  bool get changesPace =>
      expectedVdot != null &&
      newVdot != null &&
      (newVdot! - expectedVdot!).abs() >= 0.5;

  bool get pacesUp => changesPace && newVdot! > expectedVdot!;

  bool get isEmpty => adjustment == RunPlanAdjustment.none && !changesPace;

  RunPlanWeekReview? get lastWeek => reviews.isEmpty ? null : reviews.last;
}

/// The weekly coach: looks at what was actually run and decides how the rest
/// of the plan should change. Pure — the data comes in, a proposal comes out.
///
/// Principles:
/// - A partial week is not a failure; the next week repeats that level
///   instead of stacking the planned progression on an incomplete base.
/// - One missed week costs little fitness (detraining is minimal under two
///   weeks) but the next week resumes a notch lower. Two weeks: clearly
///   lower. Three or more: rebuild, and suggest a return-to-running plan.
/// - Missed weeks push the end of a plan without a race; with a race date the
///   remaining weeks are compressed instead (the composer handles that).
/// - Paces follow evidence, not hope: a time trial counts most, then the
///   pace held in quality reps, then GPS best efforts (which can only raise
///   the estimate — nobody runs faster than their fitness allows).
abstract final class RunPlanAdaptationEngine {
  static RunPlanAdaptationProposal propose({
    required int currentWeek,
    required int planWeeks,
    required bool currentWeekStarted,
    required List<RunPlanWeekReview> pastWeeks,
    double? expectedVdot,
    List<RunFitnessSample> fitness = const [],
    required DateTime now,
    double? fallbackBaselineKm,
  }) {
    final fromWeek = currentWeekStarted ? currentWeek + 1 : currentWeek;
    final past = [...pastWeeks]
      ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
    final recent = past.where((w) => w.weekIndex < currentWeek).toList();

    var missed = 0;
    for (final week in recent.reversed) {
      if (week.outcome != RunWeekOutcome.missed) break;
      missed++;
    }
    RunPlanWeekReview? lastSolid;
    for (final week in recent.reversed) {
      if (week.outcome == RunWeekOutcome.full) {
        lastSolid = week;
        break;
      }
    }
    final last = recent.isEmpty ? null : recent.last;
    final reference =
        lastSolid?.doneKm ?? fallbackBaselineKm ?? last?.plannedKm ?? 0;

    var adjustment = RunPlanAdjustment.none;
    double? baseline;
    var extension = 0;
    if (last != null) {
      if (missed >= 2) {
        adjustment = RunPlanAdjustment.rebuild;
        baseline = reference * (missed >= 3 ? 0.6 : 0.75);
        extension = missed;
      } else if (missed == 1) {
        adjustment = RunPlanAdjustment.stepBack;
        baseline = reference * 0.9;
        extension = 1;
      } else if (last.outcome == RunWeekOutcome.partial) {
        adjustment = RunPlanAdjustment.hold;
        baseline = last.doneKm;
        extension = 1;
      } else if (last.fatigued) {
        adjustment = RunPlanAdjustment.hold;
        baseline = math.min(last.doneKm, last.plannedKm);
        extension = 1;
      }
    }

    final (newVdot, source) = _fitness(
      expectedVdot: expectedVdot,
      samples: fitness,
      now: now,
      fatigued: last?.fatigued ?? false,
    );

    final remaining = planWeeks - fromWeek;
    return RunPlanAdaptationProposal(
      weekIndex: currentWeek,
      fromWeek: fromWeek,
      adjustment: remaining <= 0 ? RunPlanAdjustment.none : adjustment,
      reviews: recent.length > 3 ? recent.sublist(recent.length - 3) : recent,
      missedWeeks: missed,
      baselineKm: baseline == null || baseline <= 0 ? null : baseline,
      expectedVdot: expectedVdot,
      newVdot: remaining <= 0 ? expectedVdot : newVdot,
      paceSource: source,
      suggestReturnPlan: missed >= 3,
      remainingWeeks: remaining <= 0
          ? null
          : remaining + math.min(extension, 3),
    );
  }

  /// New fitness estimate, or the expected one when the evidence does not
  /// justify a change.
  static (double?, RunFitnessSource?) _fitness({
    required double? expectedVdot,
    required List<RunFitnessSample> samples,
    required DateTime now,
    required bool fatigued,
  }) {
    if (expectedVdot == null) return (null, null);
    final window = now.subtract(const Duration(days: 21));
    final recent = samples.where((s) => s.date.isAfter(window)).toList();

    final tests =
        recent
            .where(
              (s) =>
                  s.source == RunFitnessSource.test ||
                  s.source == RunFitnessSource.race,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (tests.isNotEmpty) {
      // A maximal effort is the best evidence there is; still moved in
      // bounded steps so one bad (or great) day does not rewrite the plan.
      final delta = (tests.last.vdot - expectedVdot).clamp(-2.5, 2.5);
      return delta.abs() < 0.5
          ? (expectedVdot, null)
          : (expectedVdot + delta, tests.last.source);
    }

    final workouts =
        recent
            .where((s) => s.source == RunFitnessSource.workout)
            .map((s) => s.vdot)
            .toList()
          ..sort();
    if (workouts.length >= 2) {
      final median = workouts[workouts.length ~/ 2];
      var delta = (median - expectedVdot).clamp(-1.5, 1.5);
      // Quality reps done faster than prescribed while the body complains
      // are not a reason to speed the plan up.
      if (fatigued && delta > 0) delta = 0;
      if (delta.abs() >= 0.5) {
        return (expectedVdot + delta, RunFitnessSource.workout);
      }
    }

    final efforts = recent
        .where((s) => s.source == RunFitnessSource.bestEffort)
        .map((s) => s.vdot);
    if (efforts.isNotEmpty && !fatigued) {
      final best = efforts.reduce(math.max);
      // Only upwards, and only half the gap.
      final delta = ((best - expectedVdot) * 0.5).clamp(0.0, 1.0);
      if (delta >= 0.5) {
        return (expectedVdot + delta, RunFitnessSource.bestEffort);
      }
    }
    return (expectedVdot, null);
  }
}
