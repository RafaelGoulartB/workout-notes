import 'package:intl/intl.dart';

/// Shared formatting for running screens. Decimals follow the app locale
/// (`Intl.defaultLocale`), so Portuguese shows `3,27 km` and English `3.27 km`.
class RunFormatters {
  static String _fixed(double value, int digits) {
    final format = NumberFormat.decimalPatternDigits(
      locale: Intl.defaultLocale,
      decimalDigits: digits,
    );
    return format.format(value);
  }

  /// Locale-aware number with a fixed number of decimals (no grouping for
  /// values below 10 000 so charts and tiles stay compact).
  static String decimal(double value, [int digits = 1]) {
    if (!value.isFinite) return '--';
    return _fixed(value, digits);
  }

  static String distanceKm(double meters) {
    final km = meters / 1000.0;
    if (km < 10) return _fixed(km, 2);
    if (km < 100) return _fixed(km, 1);
    return _fixed(km, 0);
  }

  /// Compact km for chart axes and tooltips: `3,2`, `12`, `140`.
  static String distanceKmShort(double meters) {
    final km = meters / 1000.0;
    if (km < 10) return _fixed(km, 1);
    return _fixed(km, 0);
  }

  static String duration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Long durations for totals: `12h 05min`, `45min`.
  static String durationHoursMinutes(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours == 0) return '${minutes}min';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }

  static String pace(double? secPerKm) {
    if (secPerKm == null || secPerKm <= 0 || !secPerKm.isFinite) {
      return '--:--';
    }
    final total = secPerKm.round().clamp(0, 99 * 60 + 59);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Pace for axes and compact labels: `5:42` (no leading zero).
  static String paceShort(double? secPerKm) {
    if (secPerKm == null || secPerKm <= 0 || !secPerKm.isFinite) {
      return '--:--';
    }
    final total = secPerKm.round().clamp(0, 99 * 60 + 59);
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// Signed pace difference: `+0:12`, `-0:05`, `0:00`.
  static String paceDelta(double deltaSecPerKm) {
    final total = deltaSecPerKm.round();
    final sign = total > 0
        ? '+'
        : total < 0
        ? '-'
        : '';
    final abs = total.abs();
    return '$sign${abs ~/ 60}:${(abs % 60).toString().padLeft(2, '0')}';
  }

  static String speedKmh(double? kmh) {
    if (kmh == null || !kmh.isFinite || kmh <= 0) return '--';
    return _fixed(kmh, 1);
  }

  static String elevation(double? meters) {
    if (meters == null || !meters.isFinite) return '--';
    return '${meters.round()} m';
  }

  static String distanceWithUnit(double meters) => '${distanceKm(meters)} km';

  static String paceWithUnit(double? secPerKm) => '${pace(secPerKm)} /km';
}
