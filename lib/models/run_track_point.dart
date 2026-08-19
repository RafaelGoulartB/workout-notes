class RunTrackPoint {
  final String id;
  final String activityId;
  final int seq;
  final double lat;
  final double lng;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final DateTime recordedAt;

  const RunTrackPoint({
    required this.id,
    required this.activityId,
    required this.seq,
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.recordedAt,
  });

  factory RunTrackPoint.fromMap(Map<String, dynamic> map) {
    return RunTrackPoint(
      id: map['id'] as String,
      activityId: map['activity_id'] as String,
      seq: (map['seq'] as num).toInt(),
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'activity_id': activityId,
        'seq': seq,
        'lat': lat,
        'lng': lng,
        'altitude': altitude,
        'accuracy': accuracy,
        'speed': speed,
        'recorded_at': recordedAt.toIso8601String(),
      };
}
