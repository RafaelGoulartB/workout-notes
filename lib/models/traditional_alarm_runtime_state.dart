class TraditionalAlarmRuntimeState {
  const TraditionalAlarmRuntimeState({
    required this.id,
    required this.enabled,
    required this.state,
    required this.alarmAt,
    required this.snoozeCount,
    required this.maxSnoozes,
    required this.requiresMission,
  });

  final String id;
  final bool enabled;
  final String state;
  final DateTime alarmAt;
  final int snoozeCount;
  final int maxSnoozes;
  final bool requiresMission;

  bool get isSnoozing => enabled && state == 'scheduled' && snoozeCount > 0;

  factory TraditionalAlarmRuntimeState.fromMap(Map<String, dynamic> map) {
    return TraditionalAlarmRuntimeState(
      id: map['id'] as String,
      enabled: map['enabled'] == true,
      state: map['state'] as String? ?? 'scheduled',
      alarmAt: DateTime.fromMillisecondsSinceEpoch(
        (map['alarm_at_epoch_ms'] as num).toInt(),
      ),
      snoozeCount: (map['snooze_count'] as num?)?.toInt() ?? 0,
      maxSnoozes: (map['max_snoozes'] as num?)?.toInt() ?? 0,
      requiresMission: map['requires_mission'] == true,
    );
  }
}
