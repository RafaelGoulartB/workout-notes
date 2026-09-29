import 'dart:math' as math;

/// Small pure helpers shared by the AI tool services, so every tool rounds,
/// averages and formats dates the same way.
abstract final class AiToolMath {
  static final RegExp _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// `yyyy-MM-dd` for [value].
  static String isoDay(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  /// Returns [value] when it is a real `yyyy-MM-dd` calendar date; throws a
  /// [FormatException] otherwise (surfaced to the model as a tool error).
  static String validatedIsoDate(String value) {
    if (!_isoDatePattern.hasMatch(value)) {
      throw const FormatException('date must use YYYY-MM-DD');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || isoDay(parsed) != value) {
      throw const FormatException('date is invalid');
    }
    return value;
  }

  /// Rounds to one decimal place.
  static double round1(double value) => (value * 10).round() / 10;

  static double? round1OrNull(double? value) =>
      value == null ? null : round1(value);

  static double? average(Iterable<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double? minimum(List<double> values) =>
      values.isEmpty ? null : values.reduce(math.min);

  static double? maximum(List<double> values) =>
      values.isEmpty ? null : values.reduce(math.max);

  /// Mean of clock times in minutes since midnight, treating them as points
  /// on a circle so 23:50 and 00:10 average to midnight.
  static double circularMeanMinutes(List<double> values) {
    var sinSum = 0.0;
    var cosSum = 0.0;
    for (final value in values) {
      final angle = value / 1440 * 2 * math.pi;
      sinSum += math.sin(angle);
      cosSum += math.cos(angle);
    }
    var angle = math.atan2(sinSum, cosSum);
    if (angle < 0) angle += 2 * math.pi;
    return angle / (2 * math.pi) * 1440;
  }

  /// Shortest distance in minutes between two clock times.
  static double circularDistanceMinutes(double first, double second) {
    final direct = (first - second).abs();
    return math.min(direct, 1440 - direct);
  }
}
