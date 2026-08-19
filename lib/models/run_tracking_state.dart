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
          errorCode: null,
          errorMessage: null,
        );

  bool get isActive =>
      status == starting || status == recording || status == paused;

  bool get isRecording => status == recording;

  bool get isPaused => status == paused;

  bool get hasWeakGps =>
      accuracyMeters != null && accuracyMeters! > 30;

  factory RunTrackingState.fromMap(
    Map<String, dynamic> map, {
    List<RunLatLng>? trail,
  }) {
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
