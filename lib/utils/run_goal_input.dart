import 'package:workout_notes/utils/run_formatters.dart';

/// Parsing for the free-text goal fields of the record screen (custom
/// distance, custom time, pace goal). Accepts both `,` and `.` decimals.
class RunGoalInput {
  static const minDistanceMeters = 100;
  static const maxDistanceMeters = 500000;
  static const minTimeSeconds = 60;
  static const maxTimeSeconds = 24 * 3600;
  static const minPaceSecPerKm = 120; // 2:00 /km
  static const maxPaceSecPerKm = 1200; // 20:00 /km

  /// `5`, `5,5`, `21.1` (kilometers) -> meters. Null when empty/invalid/out of
  /// range.
  static int? distanceMeters(String raw) {
    final km = _decimal(raw);
    if (km == null) return null;
    final meters = (km * 1000).round();
    if (meters < minDistanceMeters || meters > maxDistanceMeters) return null;
    return meters;
  }

  /// `45` (minutes), `37.5`, or `1:15` (h:mm) -> seconds.
  static int? timeSeconds(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    int? seconds;
    if (text.contains(':')) {
      final parts = text.split(':');
      if (parts.length != 2) return null;
      final hours = int.tryParse(parts[0].trim());
      final minutes = int.tryParse(parts[1].trim());
      if (hours == null || minutes == null || minutes < 0 || minutes > 59) {
        return null;
      }
      seconds = hours * 3600 + minutes * 60;
    } else {
      final minutes = _decimal(text);
      if (minutes == null) return null;
      seconds = (minutes * 60).round();
    }
    if (seconds < minTimeSeconds || seconds > maxTimeSeconds) return null;
    return seconds;
  }

  /// `5:30` (minutes:seconds per km) -> seconds per km. Only the `m:ss` form
  /// is accepted, so `5.5` is never read as 5 min 30 s by accident.
  static int? paceSecPerKm(String raw) {
    final text = raw.trim();
    final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(text);
    if (match == null) return null;
    final total = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
    if (total < minPaceSecPerKm || total > maxPaceSecPerKm) return null;
    return total;
  }

  /// `5:30` for 330 s/km, the editable form of [paceSecPerKm].
  static String paceText(int secPerKm) => RunFormatters.minSec(secPerKm);

  static double? _decimal(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }
}
