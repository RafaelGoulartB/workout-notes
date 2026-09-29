/// Language-independent clock formatting of whole seconds, shared by the
/// strength, sleep, rest-timer and run code. `RunFormatters` delegates to the
/// same functions, so a duration looks the same everywhere.
abstract final class DurationFormat {
  static String _two(int value) => value.toString().padLeft(2, '0');

  /// `m:ss` with the minutes unpadded: `5:42`, `95:05`.
  static String minSec(int totalSeconds) =>
      '${totalSeconds ~/ 60}:${_two(totalSeconds % 60)}';

  /// `mm:ss` with padded minutes: `05:42`.
  static String mmss(int totalSeconds) =>
      '${_two(totalSeconds ~/ 60)}:${_two(totalSeconds % 60)}';

  /// `h:mm:ss`: `1:05:09`.
  static String hms(int totalSeconds) =>
      '${totalSeconds ~/ 3600}:${_two((totalSeconds % 3600) ~/ 60)}:'
      '${_two(totalSeconds % 60)}';

  /// `hh:mm:ss` with padded hours: `01:05:09`.
  static String clock(Duration duration) =>
      '${_two(duration.inHours)}:${_two(duration.inMinutes % 60)}:'
      '${_two(duration.inSeconds % 60)}';

  /// `m:ss` from one minute up, plain seconds below: `1:30`, `45s`.
  static String minSecOrSeconds(int totalSeconds) =>
      totalSeconds >= 60 ? minSec(totalSeconds) : '${totalSeconds}s';

  /// Elapsed workout time: `mm:ss` under one hour, `1h05min` from then on.
  static String elapsed(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    if (hours > 0) return '${hours}h${_two((totalSeconds % 3600) ~/ 60)}min';
    return mmss(totalSeconds);
  }
}
