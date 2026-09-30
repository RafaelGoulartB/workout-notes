import 'dart:convert';

/// A time of day at which a medication is taken.
class MedicationTime implements Comparable<MedicationTime> {
  const MedicationTime(this.hour, this.minute);

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(MedicationTime other) => minutesOfDay - other.minutesOfDay;

  @override
  bool operator ==(Object other) =>
      other is MedicationTime && other.minutesOfDay == minutesOfDay;

  @override
  int get hashCode => minutesOfDay;
}

/// A medication with one or more daily reminder times.
///
/// Weekdays use [DateTime.weekday] values (Monday = 1 … Sunday = 7); an empty
/// list means every day. When a dose is not confirmed within
/// [escalationMinutes] of its reminder, a sound alarm rings.
class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.notes,
    required this.times,
    required this.weekdays,
    required this.escalationMinutes,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  static const defaultEscalationMinutes = 30;

  final String id;
  final String name;
  final String? dosage;
  final String? notes;
  final List<MedicationTime> times;
  final List<int> weekdays;
  final int escalationMinutes;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get everyDay => weekdays.isEmpty || weekdays.length == 7;

  bool takesOn(DateTime day) => everyDay || weekdays.contains(day.weekday);

  /// Native reminder slot for one of the times (`<id>@0800`).
  String slotId(MedicationTime time) =>
      '$id@${time.hour.toString().padLeft(2, '0')}'
      '${time.minute.toString().padLeft(2, '0')}';

  /// Scheduled doses on [day], in time order (empty on days off).
  List<DateTime> dosesOn(DateTime day) {
    if (!takesOn(day)) return const [];
    return [
      for (final time in times)
        DateTime(day.year, day.month, day.day, time.hour, time.minute),
    ];
  }

  /// Identifies one scheduled dose; the Android side builds the same key.
  static String doseKey(DateTime scheduledAt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${scheduledAt.year.toString().padLeft(4, '0')}-'
        '${two(scheduledAt.month)}-${two(scheduledAt.day)}'
        'T${two(scheduledAt.hour)}:${two(scheduledAt.minute)}';
  }

  /// Parses a [doseKey] back into the local scheduled time.
  static DateTime? parseDoseKey(String key) => DateTime.tryParse(key);

  Medication copyWith({
    String? name,
    String? dosage,
    bool clearDosage = false,
    String? notes,
    bool clearNotes = false,
    List<MedicationTime>? times,
    List<int>? weekdays,
    int? escalationMinutes,
    bool? enabled,
    DateTime? updatedAt,
  }) => Medication(
    id: id,
    name: name ?? this.name,
    dosage: clearDosage ? null : (dosage ?? this.dosage),
    notes: clearNotes ? null : (notes ?? this.notes),
    times: times ?? this.times,
    weekdays: weekdays ?? this.weekdays,
    escalationMinutes: escalationMinutes ?? this.escalationMinutes,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'dosage': dosage,
    'notes': notes,
    'times_json': jsonEncode([
      for (final time in times) {'h': time.hour, 'm': time.minute},
    ]),
    'weekdays_json': jsonEncode(weekdays),
    'escalation_minutes': escalationMinutes,
    'enabled': enabled ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Medication.fromMap(Map<String, Object?> map) {
    final rawTimes = jsonDecode(map['times_json'] as String? ?? '[]') as List;
    final rawDays = jsonDecode(map['weekdays_json'] as String? ?? '[]') as List;
    return Medication(
      id: map['id']! as String,
      name: map['name']! as String,
      dosage: map['dosage'] as String?,
      notes: map['notes'] as String?,
      times: [
        for (final value in rawTimes)
          if (value is Map)
            MedicationTime(
              (value['h'] as num?)?.toInt() ?? 8,
              (value['m'] as num?)?.toInt() ?? 0,
            ),
      ]..sort(),
      weekdays: [for (final day in rawDays) (day as num).toInt()]..sort(),
      escalationMinutes:
          (map['escalation_minutes'] as num?)?.toInt() ??
          defaultEscalationMinutes,
      enabled: (map['enabled'] as num? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at']! as String),
      updatedAt: DateTime.parse(map['updated_at']! as String),
    );
  }
}

enum MedicationDoseStatus {
  taken,
  skipped;

  static MedicationDoseStatus parse(String? value) =>
      value == 'skipped' ? skipped : taken;
}

/// A logged answer for one scheduled dose.
class MedicationDose {
  const MedicationDose({
    required this.id,
    required this.medicationId,
    required this.doseKey,
    required this.scheduledAt,
    required this.status,
    required this.recordedAt,
  });

  final String id;
  final String medicationId;
  final String doseKey;
  final DateTime scheduledAt;
  final MedicationDoseStatus status;
  final DateTime recordedAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'medication_id': medicationId,
    'dose_key': doseKey,
    'scheduled_at': scheduledAt.toIso8601String(),
    'status': status.name,
    'recorded_at': recordedAt.toIso8601String(),
  };

  factory MedicationDose.fromMap(Map<String, Object?> map) => MedicationDose(
    id: map['id']! as String,
    medicationId: map['medication_id']! as String,
    doseKey: map['dose_key']! as String,
    scheduledAt: DateTime.parse(map['scheduled_at']! as String),
    status: MedicationDoseStatus.parse(map['status'] as String?),
    recordedAt: DateTime.parse(map['recorded_at']! as String),
  );
}
