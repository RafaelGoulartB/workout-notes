import 'dart:math' as math;

/// Coaching pace targets derived from a known race or a goal race time.
///
/// Uses a Daniels-style VO2 / VDOT approximation so easy, threshold (tempo)
/// and interval paces stay consistent with each other. Values are estimates
/// for planning — not GPS prescriptions.
class RunPaces {
  /// Conversational aerobic pace (E).
  final double easySecPerKm;

  /// Threshold / tempo pace (T).
  final double tempoSecPerKm;

  /// Interval / hard repeat pace (I).
  final double intervalSecPerKm;

  /// Pace of the calibration race (or goal race).
  final double raceSecPerKm;

  const RunPaces({
    required this.easySecPerKm,
    required this.tempoSecPerKm,
    required this.intervalSecPerKm,
    required this.raceSecPerKm,
  });
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
    final vdot = _vdot(distanceMeters, timeSeconds);
    return RunPaces(
      easySecPerKm: _paceAtPercentVo2(vdot, 0.70),
      tempoSecPerKm: _paceAtPercentVo2(vdot, 0.88),
      intervalSecPerKm: _paceAtPercentVo2(vdot, 0.98),
      raceSecPerKm: racePace,
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

  /// ±[pct] band around a target pace for step min/max ranges.
  static (double min, double max) band(double secPerKm, {double pct = 0.03}) {
    final delta = secPerKm * pct;
    return (secPerKm - delta, secPerKm + delta);
  }

  static double _vo2Cost(double velocityMPerMin) =>
      -4.60 +
      0.182258 * velocityMPerMin +
      0.000104 * velocityMPerMin * velocityMPerMin;

  static double _percentVo2Max(double tMin) =>
      0.8 +
      0.1894393 * math.exp(-0.012778 * tMin) +
      0.2989558 * math.exp(-0.1932605 * tMin);

  static double _vdot(double distanceMeters, int timeSeconds) {
    final tMin = timeSeconds / 60.0;
    final velocity = distanceMeters / tMin;
    return _vo2Cost(velocity) / _percentVo2Max(tMin);
  }

  static double _paceAtPercentVo2(double vdot, double pct) {
    final targetVo2 = vdot * pct;
    const a = 0.000104;
    const b = 0.182258;
    final c = -4.60 - targetVo2;
    final disc = b * b - 4 * a * c;
    final velocity = (-b + math.sqrt(disc)) / (2 * a);
    if (velocity <= 0) return 600;
    return 1000 / (velocity / 60);
  }
}
