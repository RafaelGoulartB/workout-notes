import 'dart:math' as math;

import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// A resolved, inclusive calendar window.
class AiDateWindow {
  final DateTime start;
  final DateTime end;

  /// The window was shortened to the tool's maximum length.
  final bool capped;

  const AiDateWindow(this.start, this.end, {this.capped = false});

  String get startKey => dateKey(start);
  String get endKey => dateKey(end);

  /// Number of calendar days, both ends included.
  int get days {
    var count = 0;
    var cursor = start;
    // Day-by-day so a DST change never skews the length.
    while (!cursor.isAfter(end)) {
      count++;
      cursor = addDays(cursor, 1);
    }
    return count;
  }

  /// Echoed under `applied` so the model knows the window it actually got.
  Map<String, dynamic> toApplied() => {
    'start_date': startKey,
    'end_date': endKey,
    'days': days,
    if (capped) 'capped': true,
  };
}

/// Small pure helpers shared by the AI tool services, so every tool rounds,
/// averages and resolves date windows the same way.
abstract final class AiToolMath {
  /// Resolves a look-back window.
  ///
  /// - [startDate] and [endDate] given: that range (at most [maxDays] long;
  ///   longer ranges keep their end and are capped).
  /// - Only [endDate]: [days] (default [defaultDays]) ending there.
  /// - Only [startDate]: from there until today (at most [maxDays] long).
  /// - Neither: [days] ending today.
  static AiDateWindow window({
    required DateTime today,
    int? days,
    String? startDate,
    String? endDate,
    required int defaultDays,
    required int maxDays,
  }) {
    final todayDay = dayOf(today);
    final start = startDate == null ? null : DateTime.parse(startDate);
    final end = endDate == null ? null : DateTime.parse(endDate);
    if (start != null && end != null) {
      if (start.isAfter(end)) {
        throw AiToolArgException.conflict(
          'start_date',
          'must not be after end_date',
        );
      }
      final earliest = addDays(end, -(maxDays - 1));
      return start.isBefore(earliest)
          ? AiDateWindow(earliest, end, capped: true)
          : AiDateWindow(start, end);
    }
    if (start != null) {
      final latest = addDays(start, maxDays - 1);
      var until = todayDay.isBefore(start) ? start : todayDay;
      var capped = false;
      if (until.isAfter(latest)) {
        until = latest;
        capped = true;
      }
      return AiDateWindow(start, until, capped: capped);
    }
    final last = end ?? todayDay;
    final length = (days ?? defaultDays).clamp(1, maxDays);
    return AiDateWindow(addDays(last, -(length - 1)), last);
  }

  /// Rounds to one decimal place.
  static double round1(double value) => (value * 10).round() / 10;

  static double? round1OrNull(double? value) =>
      value == null ? null : round1(value);

  static double? average(Iterable<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double? minimum(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce(math.min);

  static double? maximum(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce(math.max);

  /// Least-squares slope of [values] against their index (units per step), or
  /// null with fewer than 2 points.
  static double? slope(List<double> values) {
    final n = values.length;
    if (n < 2) return null;
    final meanX = (n - 1) / 2;
    final meanY = values.reduce((a, b) => a + b) / n;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < n; i++) {
      numerator += (i - meanX) * (values[i] - meanY);
      denominator += (i - meanX) * (i - meanX);
    }
    return denominator == 0 ? null : numerator / denominator;
  }

  /// Least-squares slope of `y` against `x` for [points] given as (x, y), or
  /// null with fewer than 2 distinct x values.
  static double? slopeXY(List<(double, double)> points) {
    final n = points.length;
    if (n < 2) return null;
    final meanX = points.fold<double>(0, (sum, p) => sum + p.$1) / n;
    final meanY = points.fold<double>(0, (sum, p) => sum + p.$2) / n;
    var numerator = 0.0;
    var denominator = 0.0;
    for (final point in points) {
      numerator += (point.$1 - meanX) * (point.$2 - meanY);
      denominator += (point.$1 - meanX) * (point.$1 - meanX);
    }
    return denominator == 0 ? null : numerator / denominator;
  }

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

  /// `HH:mm` of a minutes-after-midnight value (wraps past 24 h).
  static String? clock(Object? raw) {
    final minutes = (raw as num?)?.toInt();
    if (minutes == null) return null;
    final normalized = minutes % 1440;
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  /// Percentage change from [from] to [to]; null when [from] is not positive.
  static double? percentChange(double? from, double? to) {
    if (from == null || to == null || from <= 0) return null;
    return (to - from) / from * 100;
  }

  /// A time-bound value as `int` when it is whole, `null` otherwise.
  static int? asInt(Object? value) => (value as num?)?.toInt();

  static double? asDouble(Object? value) => (value as num?)?.toDouble();
}
