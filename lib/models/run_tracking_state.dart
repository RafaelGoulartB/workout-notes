import 'package:workout_notes/models/run_split.dart';

class RunLatLng {
  final double lat;
  final double lng;

  const RunLatLng(this.lat, this.lng);
}

class RunTrackingState {
  static const idle = 'idle';
  static const starting = 'starting';
  static const recording = 'recording';
  static const paused = 'paused';
  static const stopping = 'stopping';
  static const completed = 'completed';
  static const discarded = 'discarded';

  final bool supported;
  final bool locationGranted;
  final String status;
  final String? activityId;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final double distanceMeters;
  final int durationSeconds;
  final int movingTimeSeconds;
  final double? currentPaceSecPerKm;
  final double? lat;
  final double? lng;
  final double? accuracyMeters;
  final List<RunLatLng> trail;
  final List<RunSplit> splits;
  final RunSplit? currentSplit;
  final String? errorCode;
  final String? errorMessage;

  const RunTrackingState({
    required this.supported,
    required this.locationGranted,
    required this.status,
    required this.activityId,
    required this.startedAt,
    required this.updatedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.movingTimeSeconds,
    required this.currentPaceSecPerKm,
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    required this.trail,
    required this.splits,
    required this.currentSplit,
    required this.errorCode,
    required this.errorMessage,
  });

  const RunTrackingState.initial({bool supported = false})
      : this(
          supported: supported,
          locationGranted: false,
          status: idle,
          activityId: null,
          startedAt: null,
          updatedAt: null,
          distanceMeters: 0,
          durationSeconds: 0,
          movingTimeSeconds: 0,
          currentPaceSecPerKm: null,
          lat: null,
          lng: null,
          accuracyMeters: null,
          trail: const [],
          splits: const [],
          currentSplit: null,
          errorCode: null,
          errorMessage: null,
        );

  bool get isActive =>
      status == starting || status == recording || status == paused;

  bool get isRecording => status == recording;

  bool get isPaused => status == paused;

  bool get hasWeakGps =>
      accuracyMeters != null && accuracyMeters! > 30;

  /// Completed km splits plus the in-progress partial (newest last).
  List<RunSplit> get displaySplits {
    if (currentSplit == null) return splits;
    return [...splits, currentSplit!];
  }

  factory RunTrackingState.fromMap(
    Map<String, dynamic> map, {
    List<RunLatLng>? trail,
  }) {
    final rawSplits = (map['splits'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => RunSplit.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final rawCurrent = map['current_split'];
    RunSplit? current;
    if (rawCurrent is Map) {
      current = RunSplit.fromMap(Map<String, dynamic>.from(rawCurrent));
    }
    return RunTrackingState(
      supported: map['supported'] as bool? ?? true,
      locationGranted: map['location_granted'] as bool? ?? false,
      status: map['status'] as String? ?? idle,
      activityId: map['activity_id'] as String?,
      startedAt: _parseDate(map['started_at']),
      updatedAt: _parseDate(map['updated_at']),
      distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      movingTimeSeconds: (map['moving_time_seconds'] as num?)?.toInt() ?? 0,
      currentPaceSecPerKm: (map['current_pace_sec_per_km'] as num?)?.toDouble(),
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      accuracyMeters: (map['accuracy_meters'] as num?)?.toDouble(),
      trail: trail ?? const [],
      splits: rawSplits,
      currentSplit: current,
      errorCode: map['error_code'] as String?,
      errorMessage: map['error_message'] as String?,
    );
  }

  RunTrackingState copyWith({
    bool? supported,
    bool? locationGranted,
    String? status,
    String? activityId,
    DateTime? startedAt,
    DateTime? updatedAt,
    double? distanceMeters,
    int? durationSeconds,
    int? movingTimeSeconds,
    double? currentPaceSecPerKm,
    double? lat,
    double? lng,
    double? accuracyMeters,
    List<RunLatLng>? trail,
    List<RunSplit>? splits,
    RunSplit? currentSplit,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RunTrackingState(
      supported: supported ?? this.supported,
      locationGranted: locationGranted ?? this.locationGranted,
      status: status ?? this.status,
      activityId: activityId ?? this.activityId,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      movingTimeSeconds: movingTimeSeconds ?? this.movingTimeSeconds,
      currentPaceSecPerKm: currentPaceSecPerKm ?? this.currentPaceSecPerKm,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      trail: trail ?? this.trail,
      splits: splits ?? this.splits,
      currentSplit: currentSplit ?? this.currentSplit,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
