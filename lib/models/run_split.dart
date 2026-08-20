class RunSplit {
  final int km;
  final double distanceMeters;
  final int durationSeconds;
  final double? paceSecPerKm;
  final bool isPartial;

  const RunSplit({
    required this.km,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecPerKm,
    required this.isPartial,
  });

  factory RunSplit.fromMap(Map<String, dynamic> map) {
    return RunSplit(
      km: (map['km'] as num?)?.toInt() ?? 0,
      distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      paceSecPerKm: (map['pace_sec_per_km'] as num?)?.toDouble(),
      isPartial: map['is_partial'] as bool? ?? false,
    );
  }
}
