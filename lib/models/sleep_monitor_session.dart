import 'sleep_monitor_segment.dart';

/// Durable aggregate for one microphone monitoring session.
class SleepMonitorSession {
  static const defaultAlgorithmVersion = 'audio-noise-v1';
  static const defaultSensorMode = 'audio';

  static const starting = 'starting';
  static const running = 'running';
  static const stopping = 'stopping';
  static const completed = 'completed';
  static const interrupted = 'interrupted';
  static const failed = 'failed';
  static const discarded = 'discarded';

  static const endUser = 'user';
  static const endNotificationAction = 'notification_action';
  static const endTimeLimit = 'time_limit';
  static const endServiceDestroyed = 'service_destroyed';
  static const endProcessRecovered = 'process_recovered';
  static const endPermissionRevoked = 'permission_revoked';
  static const endAudioError = 'audio_error';

  final String id;
  final String? sleepEntryId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int utcOffsetStartMinutes;
  final int? utcOffsetEndMinutes;
  final String sensorMode;
  final String algorithmVersion;
  final int? timeInBedMinutes;
  final int? quietMinutes;
  final int? noisyMinutes;
  final int? estimatedSleepMinutes;
  final int noiseEventCount;
  final double? signalQualityScore;
  final String? endReason;
  final DateTime createdAt;

  const SleepMonitorSession({
    required this.id,
    required this.sleepEntryId,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.utcOffsetStartMinutes,
    required this.utcOffsetEndMinutes,
    required this.sensorMode,
    required this.algorithmVersion,
    required this.timeInBedMinutes,
    required this.quietMinutes,
    required this.noisyMinutes,
    required this.estimatedSleepMinutes,
    required this.noiseEventCount,
    required this.signalQualityScore,
    required this.endReason,
    required this.createdAt,
  });

  bool get isActive =>
      status == starting || status == running || status == stopping;

  SleepMonitorSession copyWith({
    String? sleepEntryId,
    String? status,
    DateTime? endedAt,
    int? utcOffsetEndMinutes,
    int? timeInBedMinutes,
    int? quietMinutes,
    int? noisyMinutes,
    int? estimatedSleepMinutes,
    int? noiseEventCount,
    double? signalQualityScore,
    String? endReason,
  }) {
    return SleepMonitorSession(
      id: id,
      sleepEntryId: sleepEntryId ?? this.sleepEntryId,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      utcOffsetStartMinutes: utcOffsetStartMinutes,
      utcOffsetEndMinutes: utcOffsetEndMinutes ?? this.utcOffsetEndMinutes,
      sensorMode: sensorMode,
      algorithmVersion: algorithmVersion,
      timeInBedMinutes: timeInBedMinutes ?? this.timeInBedMinutes,
      quietMinutes: quietMinutes ?? this.quietMinutes,
      noisyMinutes: noisyMinutes ?? this.noisyMinutes,
      estimatedSleepMinutes:
          estimatedSleepMinutes ?? this.estimatedSleepMinutes,
      noiseEventCount: noiseEventCount ?? this.noiseEventCount,
      signalQualityScore: signalQualityScore ?? this.signalQualityScore,
      endReason: endReason ?? this.endReason,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sleep_entry_id': sleepEntryId,
    'status': status,
    'started_at': startedAt.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
    'utc_offset_start_minutes': utcOffsetStartMinutes,
    'utc_offset_end_minutes': utcOffsetEndMinutes,
    'sensor_mode': sensorMode,
    'algorithm_version': algorithmVersion,
    'time_in_bed_minutes': timeInBedMinutes,
    'quiet_minutes': quietMinutes,
    'noisy_minutes': noisyMinutes,
    'estimated_sleep_minutes': estimatedSleepMinutes,
    'noise_event_count': noiseEventCount,
    'signal_quality_score': signalQualityScore,
    'end_reason': endReason,
    'created_at': createdAt.toIso8601String(),
  };

  factory SleepMonitorSession.fromMap(Map<String, dynamic> map) {
    return SleepMonitorSession(
      id: map['id'] as String,
      sleepEntryId: map['sleep_entry_id'] as String?,
      status: map['status'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: (map['ended_at'] as String?) == null
          ? null
          : DateTime.parse(map['ended_at'] as String),
      utcOffsetStartMinutes: (map['utc_offset_start_minutes'] as num).toInt(),
      utcOffsetEndMinutes: (map['utc_offset_end_minutes'] as num?)?.toInt(),
      sensorMode: (map['sensor_mode'] as String?) ?? defaultSensorMode,
      algorithmVersion:
          (map['algorithm_version'] as String?) ?? defaultAlgorithmVersion,
      timeInBedMinutes: (map['time_in_bed_minutes'] as num?)?.toInt(),
      quietMinutes: (map['quiet_minutes'] as num?)?.toInt(),
      noisyMinutes: (map['noisy_minutes'] as num?)?.toInt(),
      estimatedSleepMinutes: (map['estimated_sleep_minutes'] as num?)?.toInt(),
      noiseEventCount: (map['noise_event_count'] as num?)?.toInt() ?? 0,
      signalQualityScore: (map['signal_quality_score'] as num?)?.toDouble(),
      endReason: map['end_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static SleepMonitorSession fromNative(
    Map<String, dynamic> map,
    List<SleepMonitorSegment> segments,
  ) {
    final normalized = Map<String, dynamic>.from(map);
    final start = DateTime.parse(normalized['started_at'] as String);
    final endText = normalized['ended_at'] as String?;
    final end = endText == null ? null : DateTime.parse(endText);
    final isUnfinished =
        end == null &&
        normalized['status'] != completed &&
        normalized['status'] != failed &&
        normalized['status'] != discarded;
    final recoveryEnd = segments.isEmpty
        ? start
        : segments.last.startedAt.add(
            Duration(seconds: segments.last.durationSeconds),
          );
    normalized['status'] = isUnfinished ? interrupted : normalized['status'];
    normalized['ended_at'] =
        end?.toIso8601String() ??
        (isUnfinished ? recoveryEnd.toIso8601String() : null);
    normalized['end_reason'] = isUnfinished
        ? endProcessRecovered
        : normalized['end_reason'];
    normalized['time_in_bed_minutes'] ??=
        ((DateTime.parse(
                  normalized['ended_at'] as String,
                ).difference(start).inSeconds) /
                60)
            .round();
    normalized['quiet_minutes'] ??=
        (segments
                    .where((segment) => segment.isQuiet)
                    .fold<int>(
                      0,
                      (sum, segment) => sum + segment.durationSeconds,
                    ) /
                60)
            .round();
    normalized['noisy_minutes'] ??=
        (segments
                    .where((segment) => segment.isNoise)
                    .fold<int>(
                      0,
                      (sum, segment) => sum + segment.durationSeconds,
                    ) /
                60)
            .round();
    normalized['noise_event_count'] ??= _eventCount(segments);
    normalized['signal_quality_score'] ??= segments.isEmpty
        ? 0.0
        : segments.fold<double>(
                0,
                (sum, segment) => sum + segment.validFraction,
              ) /
              segments.length;
    return SleepMonitorSession.fromMap(normalized);
  }

  static int _eventCount(List<SleepMonitorSegment> segments) {
    var events = 0;
    var inEvent = false;
    for (final segment in segments) {
      if (segment.isNoise && !inEvent) events++;
      inEvent = segment.isNoise;
    }
    return events;
  }
}
