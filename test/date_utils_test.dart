import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// These assertions hold in every time zone; they only exercise a 23 h or
/// 25 h local day when the machine zone has daylight saving (for example
/// `TZ=America/New_York flutter test test/date_utils_test.dart`).
void main() {
  group('daysBetween', () {
    test('counts calendar days across spring and fall transitions', () {
      for (final (from, to, days) in [
        (DateTime(2026, 3, 8), DateTime(2026, 3, 9), 1), // US spring forward
        (DateTime(2026, 3, 28), DateTime(2026, 3, 30), 2), // EU spring forward
        (DateTime(2026, 10, 25), DateTime(2026, 10, 26), 1), // EU fall back
        (DateTime(2026, 11, 1), DateTime(2026, 11, 2), 1), // US fall back
        (DateTime(2026, 3, 2), DateTime(2026, 3, 9), 7), // a week over a change
        (DateTime(2026, 1, 1), DateTime(2027, 1, 1), 365),
      ]) {
        expect(daysBetween(from, to), days, reason: '$from -> $to');
        expect(daysBetween(to, from), -days, reason: '$to -> $from');
      }
    });

    test('ignores the time of day', () {
      expect(
        daysBetween(DateTime(2026, 3, 8, 23, 30), DateTime(2026, 3, 9, 0, 10)),
        1,
      );
      expect(
        daysBetween(DateTime(2026, 3, 8, 0, 10), DateTime(2026, 3, 8, 23, 59)),
        0,
      );
    });

    test('agrees with addDays for every offset in a year', () {
      final start = DateTime(2026, 1, 1);
      for (var i = -400; i <= 400; i++) {
        expect(daysBetween(start, addDays(start, i)), i);
      }
    });
  });
}
