import 'package:workout_notes/utils/run_formatters.dart';

/// Number formatting shared by the strength analysis, records and exercise
/// screens. Decimals follow the app locale.
abstract final class StrengthFormat {
  /// Load in kg: `80` or `82,5`.
  static String weight(double kg) =>
      RunFormatters.decimal(kg, kg == kg.roundToDouble() ? 0 : 1);

  /// Big totals, same scale as the gym hub: `850` kg below 10 t, then
  /// tonnes (`12,3`). Pair with [volumeUnit].
  static String volume(double kg) {
    if (kg >= 10000) return RunFormatters.decimal(kg / 1000, 1);
    return RunFormatters.decimal(kg, 0);
  }

  static String volumeUnit(double kg) => kg >= 10000 ? 't' : 'kg';

  /// `850 kg`, `12,3 t`.
  static String volumeWithUnit(double kg) => '${volume(kg)} ${volumeUnit(kg)}';

  /// Short axis label: `500`, `1,5k`.
  static String axis(double value) {
    if (value >= 1000) {
      final k = value / 1000;
      return '${RunFormatters.decimal(k, k == k.roundToDouble() ? 0 : 1)}k';
    }
    return RunFormatters.decimal(
      value,
      value == value.roundToDouble() || value >= 10 ? 0 : 1,
    );
  }

  /// Round gridline step giving at most about [lines] lines up to [maxY].
  static double niceInterval(double maxY, {int lines = 4}) {
    if (maxY <= 0) return 1;
    final rough = maxY / lines;
    var magnitude = 1.0;
    var value = rough;
    while (value >= 10) {
      value /= 10;
      magnitude *= 10;
    }
    while (value < 1) {
      value *= 10;
      magnitude /= 10;
    }
    final step = value <= 1
        ? 1
        : value <= 2
        ? 2
        : value <= 5
        ? 5
        : 10;
    return step * magnitude;
  }

  /// Signed percent change: `+12%`, `-3%`. Null when there is no baseline.
  static String? percentDelta(double current, double previous) {
    if (previous <= 0) return null;
    final pct = ((current - previous) / previous * 100).round();
    return '${pct > 0 ? '+' : ''}$pct%';
  }

  /// Signed integer change: `+3`, `-2`, `0`.
  static String signed(int delta) => delta > 0 ? '+$delta' : '$delta';
}
