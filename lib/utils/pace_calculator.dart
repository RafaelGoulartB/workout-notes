/// Shared helpers for pace, speed, distance formatting and cardio type detection.
class PaceCalculator {
  static const _cardioTypes = {
    'distanceTime',
    'distanceOnly',
    'timeOnly',
    'repsTime',
    'repsDistance',
  };

  static bool isCardioType(String type) => _cardioTypes.contains(type);

  static bool isDistanceType(String type) =>
      type == 'distanceTime' ||
      type == 'distanceOnly' ||
      type == 'repsDistance';

  static bool isTimeType(String type) =>
      type == 'timeOnly' || type == 'repsTime' || type == 'distanceTime';

  /// Returns pace in seconds per km (or per mile).
  static double? paceSecondsPerUnit(
    double distanceKm,
    int timeSeconds, {
    bool isMile = false,
  }) {
    if (distanceKm <= 0 || timeSeconds <= 0) return null;
    final unit = isMile ? distanceKm * 0.621371 : distanceKm;
    return timeSeconds / unit;
  }

  /// Returns speed in km/h (or mph).
  static double? speedPerHour(
    double distanceKm,
    int timeSeconds, {
    bool isMile = false,
  }) {
    if (distanceKm <= 0 || timeSeconds <= 0) return null;
    final hours = timeSeconds / 3600;
    final dist = isMile ? distanceKm * 0.621371 : distanceKm;
    return dist / hours;
  }

  /// Formats pace seconds per unit to "5:42 /km" or "8:59 /mi".
  static String formatPace(
    double? paceSec, {
    bool isMile = false,
    bool showUnit = true,
  }) {
    if (paceSec == null || paceSec <= 0) return '--';
    final min = paceSec ~/ 60;
    final sec = paceSec.round() % 60;
    final secStr = sec.toString().padLeft(2, '0');
    final pace = '$min:$secStr';
    if (!showUnit) return pace;
    return '$pace /${isMile ? 'mi' : 'km'}';
  }

  /// Formats speed to "X.X km/h".
  static String formatSpeed(double? speed, {bool isMile = false}) {
    if (speed == null || speed <= 0) return '--';
    return '${speed.toStringAsFixed(1)} ${isMile ? 'mph' : 'km/h'}';
  }

  /// Formats distance with unit suffix.
  static String formatDistance(double km, {bool isMile = false}) {
    final val = isMile ? km * 0.621371 : km;
    return '${val.toStringAsFixed(2)} ${isMile ? 'mi' : 'km'}';
  }

  /// Converts string to the canonical unit name.
  static String unitLabel(bool isMile) => isMile ? 'mi' : 'km';
}
