class RunActivity {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final int movingTimeSeconds;
  final double distanceMeters;
  final double? avgPaceSecPerKm;
  final double? maxPaceSecPerKm;
  final int? calories;
  final String? title;
  final String? notes;
  final String status;
  final String? polylineSummary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RunActivity({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.movingTimeSeconds,
    required this.distanceMeters,
    required this.avgPaceSecPerKm,
    required this.maxPaceSecPerKm,
    required this.calories,
    required this.title,
    required this.notes,
    required this.status,
    required this.polylineSummary,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCompleted => status == 'completed';

  factory RunActivity.fromMap(Map<String, dynamic> map) {
    return RunActivity(
      id: map['id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: map['ended_at'] != null
          ? DateTime.parse(map['ended_at'] as String)
          : null,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      movingTimeSeconds: (map['moving_time_seconds'] as num?)?.toInt() ?? 0,
      distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0,
      avgPaceSecPerKm: (map['avg_pace_sec_per_km'] as num?)?.toDouble(),
      maxPaceSecPerKm: (map['max_pace_sec_per_km'] as num?)?.toDouble(),
      calories: (map['calories'] as num?)?.toInt(),
      title: map['title'] as String?,
      notes: map['notes'] as String?,
      status: map['status'] as String? ?? 'completed',
      polylineSummary: map['polyline_summary'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'moving_time_seconds': movingTimeSeconds,
        'distance_meters': distanceMeters,
        'avg_pace_sec_per_km': avgPaceSecPerKm,
        'max_pace_sec_per_km': maxPaceSecPerKm,
        'calories': calories,
        'title': title,
        'notes': notes,
        'status': status,
        'polyline_summary': polylineSummary,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  RunActivity copyWith({
    String? title,
    String? notes,
    DateTime? updatedAt,
  }) {
    return RunActivity(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
      movingTimeSeconds: movingTimeSeconds,
      distanceMeters: distanceMeters,
      avgPaceSecPerKm: avgPaceSecPerKm,
      maxPaceSecPerKm: maxPaceSecPerKm,
      calories: calories,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      status: status,
      polylineSummary: polylineSummary,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
