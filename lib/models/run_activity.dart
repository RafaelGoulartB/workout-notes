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

  /// Fastest completed 1 km split (sec/km). Null if not computed or unavailable.
  final double? bestSplitPaceSecPerKm;

  /// Fastest contiguous effort times in seconds for fixed distances.
  final int? bestEffort1kSec;
  final int? bestEffort3kSec;
  final int? bestEffort5kSec;
  final int? bestEffort10kSec;
  final int? bestEffortHalfSec;
  final int? bestEffortMarathonSec;

  /// 1 once GPS effort metrics have been computed (even if all null).
  final bool effortsComputed;

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
    this.bestSplitPaceSecPerKm,
    this.bestEffort1kSec,
    this.bestEffort3kSec,
    this.bestEffort5kSec,
    this.bestEffort10kSec,
    this.bestEffortHalfSec,
    this.bestEffortMarathonSec,
    this.effortsComputed = false,
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
      bestSplitPaceSecPerKm:
          (map['best_split_pace_sec_per_km'] as num?)?.toDouble(),
      bestEffort1kSec: (map['best_effort_1k_sec'] as num?)?.toInt(),
      bestEffort3kSec: (map['best_effort_3k_sec'] as num?)?.toInt(),
      bestEffort5kSec: (map['best_effort_5k_sec'] as num?)?.toInt(),
      bestEffort10kSec: (map['best_effort_10k_sec'] as num?)?.toInt(),
      bestEffortHalfSec: (map['best_effort_half_sec'] as num?)?.toInt(),
      bestEffortMarathonSec:
          (map['best_effort_marathon_sec'] as num?)?.toInt(),
      effortsComputed: (map['efforts_computed'] as num?)?.toInt() == 1,
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
        'best_split_pace_sec_per_km': bestSplitPaceSecPerKm,
        'best_effort_1k_sec': bestEffort1kSec,
        'best_effort_3k_sec': bestEffort3kSec,
        'best_effort_5k_sec': bestEffort5kSec,
        'best_effort_10k_sec': bestEffort10kSec,
        'best_effort_half_sec': bestEffortHalfSec,
        'best_effort_marathon_sec': bestEffortMarathonSec,
        'efforts_computed': effortsComputed ? 1 : 0,
      };

  RunActivity copyWith({
    String? title,
    String? notes,
    DateTime? updatedAt,
    double? bestSplitPaceSecPerKm,
    int? bestEffort1kSec,
    int? bestEffort3kSec,
    int? bestEffort5kSec,
    int? bestEffort10kSec,
    int? bestEffortHalfSec,
    int? bestEffortMarathonSec,
    bool? effortsComputed,
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
      bestSplitPaceSecPerKm:
          bestSplitPaceSecPerKm ?? this.bestSplitPaceSecPerKm,
      bestEffort1kSec: bestEffort1kSec ?? this.bestEffort1kSec,
      bestEffort3kSec: bestEffort3kSec ?? this.bestEffort3kSec,
      bestEffort5kSec: bestEffort5kSec ?? this.bestEffort5kSec,
      bestEffort10kSec: bestEffort10kSec ?? this.bestEffort10kSec,
      bestEffortHalfSec: bestEffortHalfSec ?? this.bestEffortHalfSec,
      bestEffortMarathonSec:
          bestEffortMarathonSec ?? this.bestEffortMarathonSec,
      effortsComputed: effortsComputed ?? this.effortsComputed,
    );
  }
}
