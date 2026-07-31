import 'sleep_monitor_segment.dart';

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
