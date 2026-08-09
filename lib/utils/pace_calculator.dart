/// Shared helpers for pace and distance formatting.
class PaceCalculator {
  /// Formats pace seconds per unit to "5:42 /km" or "8:59 /mi".
  static String formatPace(double? paceSec, {bool isMile = false, bool showUnit = true}) {
    if (paceSec == null || paceSec <= 0) return '--';
    final min = paceSec ~/ 60;
    final sec = paceSec.round() % 60;
    final secStr = sec.toString().padLeft(2, '0');
    final pace = '$min:$secStr';
    if (!showUnit) return pace;
    return '$pace /${isMile ? 'mi' : 'km'}';
  }

  /// Formats distance with unit suffix.
  static String formatDistance(double km, {bool isMile = false}) {
    final val = isMile ? km * 0.621371 : km;
    return '${val.toStringAsFixed(2)} ${isMile ? 'mi' : 'km'}';
  }
}
