import 'package:intl/intl.dart';
import 'package:workout_notes/models/goal.dart';

/// Format helpers for goal values, periods, etc.
class GoalFormatters {
  /// Formats a raw value into a human-friendly string with the right unit.
  static String formatValue(GoalMetric metric, double value, {bool isKm = true}) {
    switch (metric) {
      case GoalMetric.volume:
        if (value >= 1000) {
          return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}t';
        }
        return '${value.toStringAsFixed(0)} kg';
      case GoalMetric.days:
        return value.toStringAsFixed(0);
      case GoalMetric.distance:
        return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${isKm ? 'km' : 'mi'}';
      case GoalMetric.time:
        return _formatDuration(value.toInt());
    }
  }

  /// Short version of [formatValue] (used inside the ring).
  static String formatValueShort(GoalMetric metric, double value, {bool isKm = true}) {
    switch (metric) {
      case GoalMetric.volume:
        if (value >= 1000) {
          return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}t';
        }
        return '${value.toStringAsFixed(0)}kg';
      case GoalMetric.days:
        return '${value.toStringAsFixed(0)}d';
      case GoalMetric.distance:
        return '${value.toStringAsFixed(value >= 100 ? 0 : 1)}${isKm ? 'k' : 'm'}';
      case GoalMetric.time:
        final totalSec = value.toInt();
        if (totalSec >= 3600) {
          final h = totalSec ~/ 3600;
          final m = (totalSec % 3600) ~/ 60;
          return m == 0 ? '${h}h' : '${h}h${m}m';
        }
        if (totalSec >= 60) {
          return '${totalSec ~/ 60}m';
        }
        return '${totalSec}s';
    }
  }

  /// Period label (e.g. "Semana" / "Mês" / "Week" / "Month").
  static String periodLabel(GoalPeriod period, {required bool isPortuguese}) {
    if (isPortuguese) {
      return period == GoalPeriod.weekly ? 'Semanal' : 'Mensal';
    }
    return period == GoalPeriod.weekly ? 'Weekly' : 'Monthly';
  }

  /// Period range label (e.g. "01–07 Jun" or "Junho 2026").
  static String periodRangeLabel(GoalPeriod period, DateTime start, DateTime end,
      {bool isPortuguese = true}) {
    final loc = isPortuguese ? 'pt_BR' : 'en_US';
    if (period == GoalPeriod.weekly) {
      final fmt = DateFormat('d MMM', loc);
      return '${fmt.format(start)} – ${fmt.format(end)}';
    } else {
      return DateFormat('MMMM yyyy', loc).format(start);
    }
  }

  /// Short period label (e.g. "Jun 2026" or "W23 Jun").
  static String shortPeriodLabel(GoalPeriod period, DateTime start,
      {bool isPortuguese = true}) {
    final loc = isPortuguese ? 'pt_BR' : 'en_US';
    if (period == GoalPeriod.weekly) {
      return DateFormat('d MMM', loc).format(start);
    }
    return DateFormat('MMM yyyy', loc).format(start);
  }

  /// Returns a motivational hint based on completion percentage.
  static String motivation(double percent) {
    if (percent >= 1.0) return 'goalMotivationDone';
    if (percent >= 0.7) return 'goalMotivationNear';
    if (percent >= 0.3) return 'goalMotivationMid';
    return 'goalMotivationEarly';
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return m == 0 ? '${h}h' : '${h}h${m}m';
    return '${m}min';
  }
}
