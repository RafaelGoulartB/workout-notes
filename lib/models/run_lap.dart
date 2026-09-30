/// A manual lap marked by the runner during a recording.
class RunLap {
  final int index;

  /// Activity distance when the lap started.
  final double startDistanceMeters;
  final double distanceMeters;
  final int durationSeconds;
  final double? paceSecPerKm;

  const RunLap({
    required this.index,
    required this.startDistanceMeters,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecPerKm,
  });

  factory RunLap.fromMap(Map<String, dynamic> map) {
    return RunLap(
      index: (map['lap_index'] as num?)?.toInt() ?? 0,
      startDistanceMeters:
          (map['start_distance_meters'] as num?)?.toDouble() ?? 0,
      distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      paceSecPerKm: (map['pace_sec_per_km'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap(String activityId) => {
    'activity_id': activityId,
    'lap_index': index,
    'start_distance_meters': startDistanceMeters,
    'distance_meters': distanceMeters,
    'duration_seconds': durationSeconds,
    'pace_sec_per_km': paceSecPerKm,
  };
}
