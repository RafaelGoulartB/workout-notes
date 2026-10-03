/// How readily the smart alarm takes a restless moment as the time to ring:
/// the probability of sleep under which it rings inside the window.
enum SmartWakeSensitivity {
  /// Rings at lighter restlessness; earlier on average.
  sensitive('sensitive', 0.7),

  /// Rings when the person is likely stirring.
  balanced('balanced', 0.5),

  /// Rings only when the person is likely awake already.
  conservative('conservative', 0.3);

  const SmartWakeSensitivity(this.wireValue, this.threshold);

  final String wireValue;
  final double threshold;

  static SmartWakeSensitivity fromWire(String? value) =>
      values.firstWhere((v) => v.wireValue == value, orElse: () => balanced);
}

/// Wake-up behaviour of the alarms: the smart window of the monitored sleep
/// alarm and the gentle volume rise shared by every wake-up alarm.
class AlarmWakeSettings {
  static const windowOptions = [0, 10, 20, 30, 45];
  static const rampOptions = [0, 30, 60, 120, 180, 300];
  static const defaultWindowMinutes = 30;
  static const defaultRampSeconds = 120;
  static const defaults = AlarmWakeSettings();

  /// Minutes before the wake time in which the sleep alarm may ring; 0 = off.
  final int windowMinutes;
  final SmartWakeSensitivity sensitivity;

  /// Length of the volume rise; 0 rings at full volume at once.
  final int rampSeconds;

  /// Raises the system alarm volume to its maximum once the rise ends.
  final bool boost;

  const AlarmWakeSettings({
    this.windowMinutes = defaultWindowMinutes,
    this.sensitivity = SmartWakeSensitivity.balanced,
    this.rampSeconds = defaultRampSeconds,
    this.boost = true,
  });

  bool get smartWindowEnabled => windowMinutes > 0;

  /// Start of the smart window for a wake time at [deadline]; null when off.
  DateTime? windowStartFor(DateTime deadline) => smartWindowEnabled
      ? deadline.subtract(Duration(minutes: windowMinutes))
      : null;

  AlarmWakeSettings copyWith({
    int? windowMinutes,
    SmartWakeSensitivity? sensitivity,
    int? rampSeconds,
    bool? boost,
  }) => AlarmWakeSettings(
    windowMinutes: windowMinutes ?? this.windowMinutes,
    sensitivity: sensitivity ?? this.sensitivity,
    rampSeconds: rampSeconds ?? this.rampSeconds,
    boost: boost ?? this.boost,
  );

  @override
  bool operator ==(Object other) =>
      other is AlarmWakeSettings &&
      other.windowMinutes == windowMinutes &&
      other.sensitivity == sensitivity &&
      other.rampSeconds == rampSeconds &&
      other.boost == boost;

  @override
  int get hashCode =>
      Object.hash(windowMinutes, sensitivity, rampSeconds, boost);
}
