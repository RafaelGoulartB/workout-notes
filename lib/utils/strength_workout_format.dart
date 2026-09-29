import 'package:workout_notes/utils/run_formatters.dart';

/// Number formatting shared by the strength workout screens (history, detail,
/// finish summary). Decimals follow the app locale like [RunFormatters].
abstract final class StrengthWorkoutFormat {
  /// A load in kg without useless decimals: `80`, `82,5`, `82,25`.
  static String weight(double kg) {
    if (!kg.isFinite) return '--';
    final rounded1 = (kg * 10).round() / 10;
    if ((kg - kg.roundToDouble()).abs() < 0.005) {
      return RunFormatters.decimal(kg.roundToDouble(), 0);
    }
    if ((kg - rounded1).abs() < 0.005) return RunFormatters.decimal(kg, 1);
    return RunFormatters.decimal(kg, 2);
  }

  /// `82,5 kg`.
  static String weightKg(double kg) => '${weight(kg)} kg';

  /// Total volume: kilograms below a tonne, tonnes with one decimal above.
  static String volume(double kg) {
    if (!kg.isFinite || kg <= 0) return '0 kg';
    if (kg >= 1000) return '${RunFormatters.decimal(kg / 1000, 1)} t';
    return '${RunFormatters.decimal(kg.roundToDouble(), 0)} kg';
  }

  /// Signed volume difference: `+1,2 t`, `-300 kg`, `0 kg`.
  static String signedVolume(double delta) {
    if (delta.abs() < 0.5) return '0 kg';
    final sign = delta > 0 ? '+' : '-';
    return '$sign${volume(delta.abs())}';
  }

  static String signedInt(int value) =>
      value > 0 ? '+$value' : value.toString();

  /// Signed duration difference: `+5min`, `-1h 05min`, `0min`.
  static String signedDuration(int seconds) {
    if (seconds.abs() < 30) return '0min';
    final sign = seconds > 0 ? '+' : '-';
    return '$sign${RunFormatters.durationHoursMinutes(seconds.abs())}';
  }

  /// `82,5 kg × 5`.
  static String setLabel(double kg, int reps) => '${weightKg(kg)} × $reps';
}
