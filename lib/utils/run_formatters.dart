class RunFormatters {
  static String distanceKm(double meters) {
    final km = meters / 1000.0;
    if (km < 10) return km.toStringAsFixed(2);
    if (km < 100) return km.toStringAsFixed(1);
    return km.toStringAsFixed(0);
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

  static String pace(double? secPerKm) {
    if (secPerKm == null || secPerKm <= 0 || !secPerKm.isFinite) {
      return '--:--';
    }
    final total = secPerKm.round().clamp(0, 99 * 60 + 59);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String distanceWithUnit(double meters) => '${distanceKm(meters)} km';

  static String paceWithUnit(double? secPerKm) => '${pace(secPerKm)} /km';
}
