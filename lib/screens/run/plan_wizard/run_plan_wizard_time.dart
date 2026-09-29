import 'package:workout_notes/services/run_pace_calculator.dart';

/// Parses a race time typed by a person, or null when it is not a plausible
/// time for [distanceMeters].
///
/// Accepts `h:mm:ss`, `mm:ss` and a bare number of minutes (`25` is a 25
/// minute 5K, never 25 seconds). A two-part entry that makes no sense as
/// minutes:seconds for a long race is read as hours:minutes (`1:55` for a
/// half marathon).
int? parseRaceTime(String raw, double distanceMeters) {
  final text = raw.trim().replaceAll('.', ':').replaceAll(',', ':');
  if (text.isEmpty) return null;
  bool plausible(int seconds) => RunPaceCalculator.isPlausibleRace(
    distanceMeters: distanceMeters,
    timeSeconds: seconds,
  );
  final parts = text.split(':');
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((n) => n == null || n < 0)) return null;
  int? result;
  switch (numbers.length) {
    case 1:
      result = numbers[0]! * 60;
    case 2:
      final (a, b) = (numbers[0]!, numbers[1]!);
      if (b >= 60) return null;
      final asMinutes = a * 60 + b;
      final asHours = a * 3600 + b * 60;
      result = plausible(asMinutes) || !plausible(asHours)
          ? asMinutes
          : asHours;
    case 3:
      final (h, m, s) = (numbers[0]!, numbers[1]!, numbers[2]!);
      if (m >= 60 || s >= 60) return null;
      result = h * 3600 + m * 60 + s;
    default:
      return null;
  }
  return plausible(result) ? result : null;
}
