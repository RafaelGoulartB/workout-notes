import 'package:intl/intl.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// Locale-aware display helpers shared by the routine screens.
abstract final class StrengthRoutineFormat {
  /// `80` -> `80`, `62.5` -> `62,5` (no trailing `,0`).
  static String kg(double value) {
    final rounded = (value * 10).round() / 10;
    final whole = rounded == rounded.truncateToDouble();
    return RunFormatters.decimal(rounded, whole ? 0 : 1);
  }

  /// Compact volume in kg: `950`, `1,2k`, `12k`.
  static String volume(double kgValue) {
    if (kgValue < 1000) return RunFormatters.decimal(kgValue, 0);
    if (kgValue < 10000) return '${RunFormatters.decimal(kgValue / 1000, 1)}k';
    return '${RunFormatters.decimal(kgValue / 1000, 0)}k';
  }

  /// Rest as `m:ss` (`90` -> `1:30`), language independent.
  static String rest(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// Short date such as `12 set` / `Sep 12`.
  static String shortDate(DateTime date, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final pattern = date.year == today.year ? 'd MMM' : 'd MMM y';
    return DateFormat(pattern, Intl.defaultLocale).format(date);
  }
}
