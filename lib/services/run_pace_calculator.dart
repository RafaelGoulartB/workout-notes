import 'dart:math' as math;

/// Coaching pace targets derived from a known race or a goal race time.
///
/// Uses the Daniels/Gilbert VO2 (VDOT) model so easy, marathon, threshold,
/// interval and repetition paces stay consistent with each other and with the
/// race predictions used to set race-pace work.
///
/// Values are estimates for planning — not GPS prescriptions.
class RunPaces {
  /// Fitness index behind every pace here (Daniels' VDOT).
  final double vdot;

  /// Middle of the conversational aerobic range (E).
  final double easySecPerKm;

  /// Fast edge of the easy range (~70% VO2max). Running quicker than this
  /// stops being easy — the most common amateur mistake.
  final double easyFastSecPerKm;

  /// Slow edge of the easy range (~62% VO2max).
  final double easySlowSecPerKm;

  /// Marathon-effort pace (M) — the aerobic-specific stimulus.
  final double marathonSecPerKm;

  /// Threshold / tempo pace (T).
  final double tempoSecPerKm;

  /// Interval / VO2max repeat pace (I).
  final double intervalSecPerKm;

  /// Repetition pace (R) for strides and short neuromuscular work.
  final double repetitionSecPerKm;

  /// Pace actually run (or targeted) in the calibration effort. Only valid for
  /// the calibration distance — use [racePaceFor] for any other distance.
  final double raceSecPerKm;

  /// Distance the calibration effort was run over, in metres.
  final double calibrationDistanceMeters;

  const RunPaces({
    required this.vdot,
    required this.easySecPerKm,
    required this.easyFastSecPerKm,
    required this.easySlowSecPerKm,
    required this.marathonSecPerKm,
    required this.tempoSecPerKm,
    required this.intervalSecPerKm,
    required this.repetitionSecPerKm,
    required this.raceSecPerKm,
    required this.calibrationDistanceMeters,
  });

  /// Predicted race pace at [distanceMeters] for this fitness.
  ///
  /// A 25:00 5K runner is *not* a 5:00/km marathoner: every race-pace target
  /// has to be re-derived for the distance actually being trained for.
  double racePaceFor(double distanceMeters) =>
      RunPaceCalculator.racePaceFor(vdot, distanceMeters);
}

abstract final class RunPaceCalculator {
  static const fiveKMeters = 5000.0;
  static const tenKMeters = 10000.0;
  static const halfMeters = 21097.5;
  static const marathonMeters = 42195.0;

  /// Builds paces from a completed (or goal) race [distanceMeters] in [timeSeconds].
  static RunPaces fromRace({
    required double distanceMeters,
    required int timeSeconds,
  }) {
    if (distanceMeters <= 0 || timeSeconds <= 0) {
      throw ArgumentError('distance and time must be positive');
    }
    final racePace = timeSeconds / (distanceMeters / 1000);
    final vdot = vdotFor(
      distanceMeters: distanceMeters,
      timeSeconds: timeSeconds,
    );
    final interval = _paceAtPercentVo2(vdot, 0.98);
    return RunPaces(
      vdot: vdot,
      // Daniels' E zone is a window (59-74% VO2max), not a single number.
      // These three bounds reproduce his table to within a few s/km.
      easySecPerKm: _paceAtPercentVo2(vdot, 0.66),
      easyFastSecPerKm: _paceAtPercentVo2(vdot, 0.70),
      easySlowSecPerKm: _paceAtPercentVo2(vdot, 0.62),
      marathonSecPerKm: racePaceFor(vdot, marathonMeters),
      tempoSecPerKm: _paceAtPercentVo2(vdot, 0.88),
      intervalSecPerKm: interval,
      // Daniels' R pace sits ~6% faster than I pace.
      repetitionSecPerKm: interval * 0.94,
      raceSecPerKm: racePace,
      calibrationDistanceMeters: distanceMeters,
    );
  }

  /// Goal-time path: same math, labelled for the target race distance.
  static RunPaces fromGoalTime({
    required double goalDistanceMeters,
    required int goalTimeSeconds,
  }) => fromRace(
    distanceMeters: goalDistanceMeters,
    timeSeconds: goalTimeSeconds,
  );

  /// True when [goalTimeSeconds] at [goalDistanceMeters] is substantially
  /// faster than what [fitness] currently predicts for that distance.
  ///
  /// An 8% gap is about 2 minutes on a 25-minute 5K — enough that training
  /// paces taken from the goal would be unrunnable in week 1.
  static bool isOptimisticGoal({
    required RunPaces fitness,
    required double goalDistanceMeters,
    required int goalTimeSeconds,
    double fasterFraction = 0.08,
  }) {
    if (fitness.vdot <= 0 ||
        goalDistanceMeters <= 0 ||
        goalTimeSeconds <= 0 ||
        fasterFraction <= 0) {
      return false;
    }
    final predictedSeconds =
        fitness.racePaceFor(goalDistanceMeters) * (goalDistanceMeters / 1000);
    return goalTimeSeconds < predictedSeconds * (1 - fasterFraction);
  }

  /// ±[pct] band around a target pace for step min/max ranges.
  ///
  /// Always returns `min < max` in seconds per km, so the UI never renders an
  /// inverted range.
  static (double min, double max) band(double secPerKm, {double pct = 0.03}) {
    final delta = secPerKm.abs() * pct;
    return (secPerKm - delta, secPerKm + delta);
  }

  /// Sorts two pace bounds so the faster (smaller s/km) one is always `min`.
  static (double min, double max) orderedBand(double a, double b) =>
      a <= b ? (a, b) : (b, a);

  /// Daniels' VDOT for a race performance.
  static double vdotFor({
    required double distanceMeters,
    required int timeSeconds,
  }) {
    final tMin = timeSeconds / 60.0;
    final velocity = distanceMeters / tMin;
    return _vo2Cost(velocity) / _percentVo2Max(tMin);
  }

  /// Predicted race pace (s/km) at [distanceMeters] for a given [vdot].
  ///
  /// Solves `vo2Cost(v) = vdot * percentVo2Max(distance / v)` by bisection.
  /// Both sides rise with `v`, but the cost term grows quadratically while the
  /// sustainable fraction saturates near 1.29, so the root is unique.
  static double racePaceFor(double vdot, double distanceMeters) {
    if (vdot <= 0 || distanceMeters <= 0) return 600;
    var lo = 40.0, hi = 800.0; // metres per minute
    for (var i = 0; i < 90; i++) {
      final mid = (lo + hi) / 2;
      final residual =
          _vo2Cost(mid) - vdot * _percentVo2Max(distanceMeters / mid);
      if (residual > 0) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final velocity = (lo + hi) / 2;
    if (velocity <= 0) return 600;
    return 60000 / velocity;
  }

  static double _vo2Cost(double velocityMPerMin) =>
      -4.60 +
      0.182258 * velocityMPerMin +
      0.000104 * velocityMPerMin * velocityMPerMin;

  static double _percentVo2Max(double tMin) =>
      0.8 +
      0.1894393 * math.exp(-0.012778 * tMin) +
      0.2989558 * math.exp(-0.1932605 * tMin);

  static double _paceAtPercentVo2(double vdot, double pct) {
    final targetVo2 = vdot * pct;
    const a = 0.000104;
    const b = 0.182258;
    final c = -4.60 - targetVo2;
    final disc = b * b - 4 * a * c;
    if (disc <= 0) return 600;
    final velocity = (-b + math.sqrt(disc)) / (2 * a);
    if (velocity <= 0) return 600;
    return 60000 / velocity;
  }
}
