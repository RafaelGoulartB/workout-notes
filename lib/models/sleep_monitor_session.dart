import 'sleep_monitor_segment.dart';
import 'sleep_monitor_mode.dart';

/// Durable aggregate for one microphone monitoring session.
class SleepMonitorSession {
  static const defaultAlgorithmVersion = 'audio-noise-v1';
  static const defaultSensorMode = 'audio';

  static const analysisAvailable = 'available';
  static const analysisInsufficient = 'insufficient_data';
  static const analysisLegacyUnavailable = 'legacy_unavailable';
  static const analysisModelUnavailable = 'model_unavailable';
  static const analysisFailed = 'failed';

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
  static const endAlarm = 'alarm';

  static const dismissButton = 'button';
  static const dismissBarcode = 'barcode';
  static const dismissEmergency500Taps = 'emergency_500_taps';

  /// Previous values remain countable after changing the challenge limit.
  @Deprecated('Use dismissEmergency500Taps')
  static const dismissEmergency1000Taps = 'emergency_1000_taps';

  @Deprecated('Use dismissEmergency500Taps')
  static const dismissEmergency100Taps = 'emergency_100_taps';

  static const emergencyDismissMethods = <String>{
    dismissEmergency500Taps,
    dismissEmergency1000Taps,
    dismissEmergency100Taps,
  };

  final String id;
  final String? sleepEntryId;
  final String status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? alarmAt;
  final SleepMonitoringMode? monitorMode;
  final String? missionType;
  final String? alarmDismissMethod;
  final DateTime? alarmDismissedAt;
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
  final String? analysisStatus;
  final DateTime? sleepOnsetAt;
  final DateTime? finalWakeAt;
  final int? sleepLatencyMinutes;
  final int? awakeMinutes;
  final int? sleepingMinutes;
  final int? deepSleepMinutes;
  final int? unknownMinutes;
  final int? awakeningCount;
  final double? sleepEfficiency;
  final double? stageConfidence;
  final String? stageAlgorithmVersion;

  const SleepMonitorSession({
    required this.id,
    required this.sleepEntryId,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    this.alarmAt,
    this.monitorMode,
    this.missionType,
    this.alarmDismissMethod,
    this.alarmDismissedAt,
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
    this.analysisStatus,
    this.sleepOnsetAt,
    this.finalWakeAt,
    this.sleepLatencyMinutes,
    this.awakeMinutes,
    this.sleepingMinutes,
    this.deepSleepMinutes,
    this.unknownMinutes,
    this.awakeningCount,
    this.sleepEfficiency,
    this.stageConfidence,
    this.stageAlgorithmVersion,
  });

  bool get hasSleepStages =>
      analysisStatus == analysisAvailable &&
      sleepingMinutes != null &&
      deepSleepMinutes != null;

  bool get isActive =>
      status == starting || status == running || status == stopping;

  SleepMonitoringMode get mode =>
      monitorMode ??
      (alarmAt == null
          ? SleepMonitoringMode.monitoringOnly
          : SleepMonitoringMode.alarmWithoutMission);

  SleepMonitorSession copyWith({
    String? sleepEntryId,
    String? status,
    DateTime? endedAt,
    DateTime? alarmAt,
    SleepMonitoringMode? monitorMode,
    String? missionType,
    String? alarmDismissMethod,
    DateTime? alarmDismissedAt,
    int? utcOffsetEndMinutes,
    int? timeInBedMinutes,
    int? quietMinutes,
    int? noisyMinutes,
    int? estimatedSleepMinutes,
    int? noiseEventCount,
    double? signalQualityScore,
    String? endReason,
    String? analysisStatus,
    DateTime? sleepOnsetAt,
    DateTime? finalWakeAt,
    int? sleepLatencyMinutes,
    int? awakeMinutes,
    int? sleepingMinutes,
    int? deepSleepMinutes,
    int? unknownMinutes,
    int? awakeningCount,
    double? sleepEfficiency,
    double? stageConfidence,
    String? stageAlgorithmVersion,
  }) {
    return SleepMonitorSession(
      id: id,
      sleepEntryId: sleepEntryId ?? this.sleepEntryId,
      status: status ?? this.status,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      alarmAt: alarmAt ?? this.alarmAt,
      monitorMode: monitorMode ?? this.monitorMode,
      missionType: missionType ?? this.missionType,
      alarmDismissMethod: alarmDismissMethod ?? this.alarmDismissMethod,
      alarmDismissedAt: alarmDismissedAt ?? this.alarmDismissedAt,
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
      analysisStatus: analysisStatus ?? this.analysisStatus,
      sleepOnsetAt: sleepOnsetAt ?? this.sleepOnsetAt,
      finalWakeAt: finalWakeAt ?? this.finalWakeAt,
      sleepLatencyMinutes: sleepLatencyMinutes ?? this.sleepLatencyMinutes,
      awakeMinutes: awakeMinutes ?? this.awakeMinutes,
      sleepingMinutes: sleepingMinutes ?? this.sleepingMinutes,
      deepSleepMinutes: deepSleepMinutes ?? this.deepSleepMinutes,
      unknownMinutes: unknownMinutes ?? this.unknownMinutes,
      awakeningCount: awakeningCount ?? this.awakeningCount,
      sleepEfficiency: sleepEfficiency ?? this.sleepEfficiency,
      stageConfidence: stageConfidence ?? this.stageConfidence,
      stageAlgorithmVersion:
          stageAlgorithmVersion ?? this.stageAlgorithmVersion,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'sleep_entry_id': sleepEntryId,
      'status': status,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'alarm_at': alarmAt?.toIso8601String(),
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
    // Keep compatibility with pre-v23 test databases and old diagnostic
    // consumers: optional metadata is emitted only when it is present.
    if (monitorMode != null) map['monitor_mode'] = monitorMode!.wireValue;
    if (missionType != null) map['mission_type'] = missionType;
    if (alarmDismissMethod != null) {
      map['alarm_dismiss_method'] = alarmDismissMethod;
    }
    if (alarmDismissedAt != null) {
      map['alarm_dismissed_at'] = alarmDismissedAt!.toIso8601String();
    }
    if (analysisStatus != null) map['analysis_status'] = analysisStatus;
    if (sleepOnsetAt != null) {
      map['sleep_onset_at'] = sleepOnsetAt!.toIso8601String();
    }
    if (finalWakeAt != null) {
      map['final_wake_at'] = finalWakeAt!.toIso8601String();
    }
    if (sleepLatencyMinutes != null) {
      map['sleep_latency_minutes'] = sleepLatencyMinutes;
    }
    if (awakeMinutes != null) map['awake_minutes'] = awakeMinutes;
    if (sleepingMinutes != null) map['sleeping_minutes'] = sleepingMinutes;
    if (deepSleepMinutes != null) {
      map['deep_sleep_minutes'] = deepSleepMinutes;
    }
    if (unknownMinutes != null) map['unknown_minutes'] = unknownMinutes;
    if (awakeningCount != null) map['awakening_count'] = awakeningCount;
    if (sleepEfficiency != null) map['sleep_efficiency'] = sleepEfficiency;
    if (stageConfidence != null) map['stage_confidence'] = stageConfidence;
    if (stageAlgorithmVersion != null) {
      map['stage_algorithm_version'] = stageAlgorithmVersion;
    }
    return map;
  }

  factory SleepMonitorSession.fromMap(Map<String, dynamic> map) {
    return SleepMonitorSession(
      id: map['id'] as String,
      sleepEntryId: map['sleep_entry_id'] as String?,
      status: map['status'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: (map['ended_at'] as String?) == null
          ? null
          : DateTime.parse(map['ended_at'] as String),
      alarmAt: (map['alarm_at'] as String?) == null
          ? null
          : DateTime.parse(map['alarm_at'] as String),
      monitorMode: map['monitor_mode'] == null
          ? null
          : SleepMonitoringMode.fromWire(map['monitor_mode']),
      missionType: map['mission_type'] as String?,
      alarmDismissMethod: map['alarm_dismiss_method'] as String?,
      alarmDismissedAt: (map['alarm_dismissed_at'] as String?) == null
          ? null
          : DateTime.parse(map['alarm_dismissed_at'] as String),
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
      analysisStatus: map['analysis_status'] as String?,
      sleepOnsetAt: (map['sleep_onset_at'] as String?) == null
          ? null
          : DateTime.parse(map['sleep_onset_at'] as String),
      finalWakeAt: (map['final_wake_at'] as String?) == null
          ? null
          : DateTime.parse(map['final_wake_at'] as String),
      sleepLatencyMinutes: (map['sleep_latency_minutes'] as num?)?.toInt(),
      awakeMinutes: (map['awake_minutes'] as num?)?.toInt(),
      sleepingMinutes: (map['sleeping_minutes'] as num?)?.toInt(),
      deepSleepMinutes: (map['deep_sleep_minutes'] as num?)?.toInt(),
      unknownMinutes: (map['unknown_minutes'] as num?)?.toInt(),
      awakeningCount: (map['awakening_count'] as num?)?.toInt(),
      sleepEfficiency: (map['sleep_efficiency'] as num?)?.toDouble(),
      stageConfidence: (map['stage_confidence'] as num?)?.toDouble(),
      stageAlgorithmVersion: map['stage_algorithm_version'] as String?,
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
    normalized['monitor_mode'] ??= normalized['alarm_at'] == null
        ? SleepMonitoringMode.monitoringOnly.wireValue
        : SleepMonitoringMode.alarmWithoutMission.wireValue;
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
