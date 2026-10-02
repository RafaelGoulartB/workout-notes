import 'package:intl/intl.dart';

/// Locale-aware numbers for user-visible text. Decimals follow the app locale
/// (`Intl.defaultLocale`), so Portuguese shows `3,5` and English `3.5`. Never
/// use it for storage, exports, AI payloads or SQL: those keep the invariant
/// `toStringAsFixed` / `toString` output.
class AppNumberFormat {
  const AppNumberFormat._();

  static final Map<String, NumberFormat> _cache = {};

  static NumberFormat _format(int digits, bool trimZeros) {
    final locale = Intl.defaultLocale ?? 'en_US';
    final key = '$locale|$digits|$trimZeros';
    return _cache.putIfAbsent(key, () {
      final fraction = digits <= 0
          ? ''
          : '.${(trimZeros ? '#' : '0') * digits}';
      // No grouping: values stay compact and match `toStringAsFixed`.
      return NumberFormat('0$fraction', locale);
    });
  }

  /// [value] with [digits] decimals (`3.50` / `3,50`). With [trimZeros] the
  /// trailing zeros and a dangling separator are dropped (`3.5`, `3`).
  /// Non-finite values print as `--`.
  static String decimal(num value, int digits, {bool trimZeros = false}) {
    if (!value.isFinite) return '--';
    return _format(digits, trimZeros).format(value);
  }

  /// [decimal] for a nullable number, or [fallback] when it is null.
  static String decimalOrDash(
    num? value,
    int digits, {
    String fallback = '-',
    bool trimZeros = false,
  }) => value == null
      ? fallback
      : decimal(value, digits, trimZeros: trimZeros);

  /// Whole numbers without decimals, otherwise one decimal (`12`, `12,5`).
  static String compact(double value) => value == value.roundToDouble()
      ? decimal(value, 0)
      : decimal(value, 1);
}
