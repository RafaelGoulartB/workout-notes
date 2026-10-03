import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/app_number_format.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

  test('English keeps the dot and matches toStringAsFixed', () {
    Intl.defaultLocale = 'en';
    expect(AppNumberFormat.decimal(3.456, 1), '3.5');
    expect(AppNumberFormat.decimal(3, 2), '3.00');
    expect(AppNumberFormat.decimal(12345.6, 0), '12346');
    expect(AppNumberFormat.decimal(2500, 0), '2500');
  });

  test('Portuguese uses the comma without grouping', () {
    Intl.defaultLocale = 'pt_BR';
    expect(AppNumberFormat.decimal(3.456, 1), '3,5');
    expect(AppNumberFormat.decimal(3, 2), '3,00');
    expect(AppNumberFormat.decimal(2500.5, 1), '2500,5');
  });

  test('the cache follows a locale change', () {
    Intl.defaultLocale = 'en';
    expect(AppNumberFormat.decimal(1.5, 1), '1.5');
    Intl.defaultLocale = 'pt_BR';
    expect(AppNumberFormat.decimal(1.5, 1), '1,5');
  });

  test('trimZeros drops trailing zeros and the separator', () {
    Intl.defaultLocale = 'pt_BR';
    expect(AppNumberFormat.decimal(2.5, 2, trimZeros: true), '2,5');
    expect(AppNumberFormat.decimal(2.0, 2, trimZeros: true), '2');
    expect(AppNumberFormat.decimal(0.75, 2, trimZeros: true), '0,75');
  });

  test('non-finite values print as a dash placeholder', () {
    expect(AppNumberFormat.decimal(double.nan, 1), '--');
    expect(AppNumberFormat.decimal(double.infinity, 1), '--');
  });

  test('compact and decimalOrDash', () {
    Intl.defaultLocale = 'pt_BR';
    expect(AppNumberFormat.compact(12), '12');
    expect(AppNumberFormat.compact(12.5), '12,5');
    expect(AppNumberFormat.decimalOrDash(null, 1), '-');
    expect(AppNumberFormat.decimalOrDash(null, 1, fallback: ''), '');
    expect(AppNumberFormat.decimalOrDash(7, 1), '7,0');
  });
}
