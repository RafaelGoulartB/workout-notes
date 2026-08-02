import 'dart:convert';

/// A standalone wake-up alarm. Weekdays use [DateTime.weekday] values
/// (Monday = 1 through Sunday = 7); an empty list represents a one-shot alarm.
class TraditionalAlarm {
  const TraditionalAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.enabled,
    required this.snoozeEnabled,
    required this.snoozeMinutes,
    required this.maxSnoozes,
    required this.requiresMission,
    required this.nextTriggerAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final int hour;
  final int minute;
  final List<int> weekdays;
  final bool enabled;
  final bool snoozeEnabled;
  final int snoozeMinutes;
  final int maxSnoozes;
  final bool requiresMission;
  final DateTime? nextTriggerAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get repeats => weekdays.isNotEmpty;

  TraditionalAlarm copyWith({
    int? hour,
    int? minute,
    List<int>? weekdays,
    bool? enabled,
    bool? snoozeEnabled,
    int? snoozeMinutes,
    int? maxSnoozes,
    bool? requiresMission,
    DateTime? nextTriggerAt,
    bool clearNextTriggerAt = false,
    DateTime? updatedAt,
  }) => TraditionalAlarm(
    id: id,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    weekdays: weekdays ?? this.weekdays,
    enabled: enabled ?? this.enabled,
    snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
    snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    maxSnoozes: maxSnoozes ?? this.maxSnoozes,
    requiresMission: requiresMission ?? this.requiresMission,
    nextTriggerAt: clearNextTriggerAt
        ? null
        : (nextTriggerAt ?? this.nextTriggerAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Calculates the next occurrence strictly after [now].
  DateTime nextOccurrence({DateTime? now}) {
    final reference = now ?? DateTime.now();
    for (var offset = 0; offset <= 7; offset++) {
      final date = DateTime(
        reference.year,
        reference.month,
        reference.day,
      ).add(Duration(days: offset));
      final candidate = DateTime(date.year, date.month, date.day, hour, minute);
      if (candidate.isAfter(reference) &&
          (!repeats || weekdays.contains(candidate.weekday))) {
        return candidate;
      }
    }
    // An empty repeat selection is always resolved on the first iteration.
    return DateTime(
      reference.year,
      reference.month,
      reference.day + 1,
      hour,
      minute,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'hour': hour,
    'minute': minute,
    'weekdays_json': jsonEncode(weekdays),
    'enabled': enabled ? 1 : 0,
    'snooze_enabled': snoozeEnabled ? 1 : 0,
    'snooze_minutes': snoozeMinutes,
    'max_snoozes': maxSnoozes,
    'requires_mission': requiresMission ? 1 : 0,
    'next_trigger_at': nextTriggerAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory TraditionalAlarm.fromMap(Map<String, Object?> map) {
    final rawDays = map['weekdays_json'] as String? ?? '[]';
    final decoded = jsonDecode(rawDays) as List<dynamic>;
    return TraditionalAlarm(
      id: map['id']! as String,
      hour: map['hour']! as int,
      minute: map['minute']! as int,
      weekdays: decoded.map((value) => value as int).toList()..sort(),
      enabled: (map['enabled'] as int? ?? 0) == 1,
      snoozeEnabled: (map['snooze_enabled'] as int? ?? 0) == 1,
      snoozeMinutes: map['snooze_minutes'] as int? ?? 5,
      maxSnoozes: map['max_snoozes'] as int? ?? 3,
      requiresMission: (map['requires_mission'] as int? ?? 0) == 1,
      nextTriggerAt: DateTime.tryParse(map['next_trigger_at'] as String? ?? ''),
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }
}
