import 'sleep_monitor_segment.dart';
import 'sleep_monitor_mode.dart';

class SleepMonitorState {
  static const idle = 'idle';
  static const starting = 'starting';
  static const running = 'running';
  static const stopping = 'stopping';
  static const completed = 'completed';
  static const interrupted = 'interrupted';
  static const failed = 'failed';

  final bool supported;
  final bool microphoneGranted;
  final String status;
  final String? sessionId;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? alarmAt;
  final SleepMonitoringMode mode;
  final SleepMissionStatus missionStatus;
  final bool alarmRinging;
  final bool alarmSnoozing;
  final String? alarmState;
  final int snoozeCount;
  final int maxSnoozes;
  final int emergencyTaps;
  final String? alarmDismissMethod;
  final String? endReason;
  final bool exactAlarmGranted;
  final bool fullScreenIntentGranted;
  final bool alarmDismissed;
  final SleepMonitorSegment? latestSegment;
  final double? currentNoiseScore;
  final String? errorCode;
  final String? errorMessage;

  const SleepMonitorState({
    required this.supported,
    required this.microphoneGranted,
    required this.status,
    required this.sessionId,
    required this.startedAt,
    required this.updatedAt,
    this.alarmAt,
    this.mode = SleepMonitoringMode.alarmWithoutMission,
    this.missionStatus = SleepMissionStatus.unconfigured,
    this.alarmRinging = false,
    this.alarmSnoozing = false,
    this.alarmState,
    this.snoozeCount = 0,
    this.maxSnoozes = 0,
    this.emergencyTaps = 0,
    this.alarmDismissMethod,
    this.endReason,
    this.exactAlarmGranted = false,
    this.fullScreenIntentGranted = false,
    this.alarmDismissed = false,
    required this.latestSegment,
    required this.currentNoiseScore,
    required this.errorCode,
    required this.errorMessage,
  });

  const SleepMonitorState.initial({bool supported = false})
    : this(
        supported: supported,
        microphoneGranted: false,
        status: idle,
        sessionId: null,
        startedAt: null,
        updatedAt: null,
        alarmAt: null,
        mode: SleepMonitoringMode.alarmWithoutMission,
        missionStatus: SleepMissionStatus.unconfigured,
        alarmRinging: false,
        alarmSnoozing: false,
        alarmState: null,
        snoozeCount: 0,
        maxSnoozes: 0,
        emergencyTaps: 0,
        alarmDismissMethod: null,
        endReason: null,
        exactAlarmGranted: false,
        fullScreenIntentGranted: false,
        alarmDismissed: false,
        latestSegment: null,
        currentNoiseScore: null,
        errorCode: null,
        errorMessage: null,
      );

  bool get isActive =>
      status == starting || status == running || status == stopping;

  bool get isAlarmSnoozing =>
      !alarmDismissed &&
      snoozeCount > 0 &&
      (alarmSnoozing || alarmState == 'scheduled');

  Duration get elapsed {
    if (startedAt == null) return Duration.zero;
    final end = isActive ? DateTime.now() : (updatedAt ?? DateTime.now());
    final value = end.difference(startedAt!);
    return value.isNegative ? Duration.zero : value;
  }

  SleepMonitorState copyWith({
    bool? supported,
    bool? microphoneGranted,
    String? status,
    String? sessionId,
    DateTime? startedAt,
    DateTime? updatedAt,
    DateTime? alarmAt,
    SleepMonitoringMode? mode,
    SleepMissionStatus? missionStatus,
    bool? alarmRinging,
    bool? alarmSnoozing,
    String? alarmState,
    int? snoozeCount,
    int? maxSnoozes,
    int? emergencyTaps,
    String? alarmDismissMethod,
    String? endReason,
    bool? exactAlarmGranted,
    bool? fullScreenIntentGranted,
    bool? alarmDismissed,
    SleepMonitorSegment? latestSegment,
    double? currentNoiseScore,
    String? errorCode,
    String? errorMessage,
  }) {
    return SleepMonitorState(
      supported: supported ?? this.supported,
      microphoneGranted: microphoneGranted ?? this.microphoneGranted,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      alarmAt: alarmAt ?? this.alarmAt,
      mode: mode ?? this.mode,
      missionStatus: missionStatus ?? this.missionStatus,
      alarmRinging: alarmRinging ?? this.alarmRinging,
      alarmSnoozing: alarmSnoozing ?? this.alarmSnoozing,
      alarmState: alarmState ?? this.alarmState,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      maxSnoozes: maxSnoozes ?? this.maxSnoozes,
      emergencyTaps: emergencyTaps ?? this.emergencyTaps,
      alarmDismissMethod: alarmDismissMethod ?? this.alarmDismissMethod,
      endReason: endReason ?? this.endReason,
      exactAlarmGranted: exactAlarmGranted ?? this.exactAlarmGranted,
      fullScreenIntentGranted:
          fullScreenIntentGranted ?? this.fullScreenIntentGranted,
      alarmDismissed: alarmDismissed ?? this.alarmDismissed,
      latestSegment: latestSegment ?? this.latestSegment,
      currentNoiseScore: currentNoiseScore ?? this.currentNoiseScore,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  factory SleepMonitorState.fromMap(Map<String, dynamic> map) {
    final startedText = map['started_at'] as String?;
    final updatedText = map['updated_at'] as String?;
    final alarmText = map['alarm_at'] as String?;
    final segment = map['latest_segment'];
    return SleepMonitorState(
      supported: map['supported'] as bool? ?? true,
      microphoneGranted: map['microphone_granted'] as bool? ?? false,
      status: map['status'] as String? ?? idle,
      sessionId: map['session_id'] as String?,
      startedAt: startedText == null ? null : DateTime.parse(startedText),
      updatedAt: updatedText == null ? null : DateTime.parse(updatedText),
      alarmAt: alarmText == null ? null : DateTime.parse(alarmText),
      mode: SleepMonitoringMode.fromWire(map['monitor_mode']),
      missionStatus: SleepMissionStatus.fromWire(map['mission_status']),
      alarmRinging: map['alarm_ringing'] as bool? ?? false,
      alarmSnoozing: map['alarm_snoozing'] as bool? ?? false,
      alarmState: map['alarm_state'] as String?,
      snoozeCount: (map['snooze_count'] as num?)?.toInt() ?? 0,
      maxSnoozes: (map['max_snoozes'] as num?)?.toInt() ?? 0,
      emergencyTaps: (map['emergency_taps'] as num?)?.toInt() ?? 0,
      alarmDismissMethod: map['alarm_dismiss_method'] as String?,
      endReason: map['end_reason'] as String?,
      exactAlarmGranted: map['exact_alarm_granted'] as bool? ?? false,
      fullScreenIntentGranted:
          map['full_screen_intent_granted'] as bool? ?? false,
      alarmDismissed: map['alarm_dismissed'] as bool? ?? false,
      latestSegment: segment is Map
          ? SleepMonitorSegment.fromMap(Map<String, dynamic>.from(segment))
          : null,
      currentNoiseScore: (map['current_noise_score'] as num?)?.toDouble(),
      errorCode: map['error_code'] as String?,
      errorMessage: map['error_message'] as String?,
    );
  }
}
