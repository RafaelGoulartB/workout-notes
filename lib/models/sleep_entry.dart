/// A nightly sleep record.
///
/// [sleepMinutes] is the user's primary duration (time recorded as sleep).
/// [actualSleepMinutes] is optional and represents the time actually asleep.
class SleepEntry {
  final String id;
  final DateTime date;
  final int sleepMinutes;
  final int? actualSleepMinutes;
  final int? bedtimeMinutes;
  final int? wakeTimeMinutes;
  final String? comment;
  final String source;
  final int? timeInBedMinutes;
  final int? estimatedSleepMinutes;
  final DateTime createdAt;

  const SleepEntry({
    required this.id,
    required this.date,
    required this.sleepMinutes,
    this.actualSleepMinutes,
    this.bedtimeMinutes,
    this.wakeTimeMinutes,
    this.comment,
    this.source = 'manual',
    this.timeInBedMinutes,
    this.estimatedSleepMinutes,
    required this.createdAt,
  });

  SleepEntry copyWith({
    String? id,
    DateTime? date,
    int? sleepMinutes,
    Object? actualSleepMinutes = _sentinel,
    Object? bedtimeMinutes = _sentinel,
    Object? wakeTimeMinutes = _sentinel,
    Object? comment = _sentinel,
    String? source,
    Object? timeInBedMinutes = _sentinel,
    Object? estimatedSleepMinutes = _sentinel,
    DateTime? createdAt,
  }) {
    return SleepEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
      actualSleepMinutes: identical(actualSleepMinutes, _sentinel)
          ? this.actualSleepMinutes
          : actualSleepMinutes as int?,
      bedtimeMinutes: identical(bedtimeMinutes, _sentinel)
          ? this.bedtimeMinutes
          : bedtimeMinutes as int?,
      wakeTimeMinutes: identical(wakeTimeMinutes, _sentinel)
          ? this.wakeTimeMinutes
          : wakeTimeMinutes as int?,
      comment: identical(comment, _sentinel)
          ? this.comment
          : comment as String?,
      source: source ?? this.source,
      timeInBedMinutes: identical(timeInBedMinutes, _sentinel)
          ? this.timeInBedMinutes
          : timeInBedMinutes as int?,
      estimatedSleepMinutes: identical(estimatedSleepMinutes, _sentinel)
          ? this.estimatedSleepMinutes
          : estimatedSleepMinutes as int?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': _dateString(date),
      'sleep_minutes': sleepMinutes,
      'actual_sleep_minutes': actualSleepMinutes,
      'bedtime_minutes': bedtimeMinutes,
      'wake_time_minutes': wakeTimeMinutes,
      'comment': comment,
      'source': source,
      'time_in_bed_minutes': timeInBedMinutes,
      'estimated_sleep_minutes': estimatedSleepMinutes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SleepEntry.fromMap(Map<String, dynamic> map) {
    return SleepEntry(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      sleepMinutes: (map['sleep_minutes'] as num).toInt(),
      actualSleepMinutes: (map['actual_sleep_minutes'] as num?)?.toInt(),
      bedtimeMinutes: (map['bedtime_minutes'] as num?)?.toInt(),
      wakeTimeMinutes: (map['wake_time_minutes'] as num?)?.toInt(),
      comment: map['comment'] as String?,
      source: (map['source'] as String?) ?? 'manual',
      timeInBedMinutes: (map['time_in_bed_minutes'] as num?)?.toInt(),
      estimatedSleepMinutes: (map['estimated_sleep_minutes'] as num?)?.toInt(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  double? get efficiency {
    if (actualSleepMinutes == null || sleepMinutes <= 0) return null;
    return actualSleepMinutes! / sleepMinutes * 100;
  }

  static String _dateString(DateTime value) =>
      value.toIso8601String().substring(0, 10);
}

class SleepDashboardStats {
  final SleepEntry? latest;
  final double? average7Days;
  final double? average30Days;
  final double? actualAverage7Days;
  final double? actualAverage30Days;
  final int? minimum30Days;
  final int? maximum30Days;
  final int recordedDays7Days;
  final int recordedDays30Days;
  final double? efficiency7Days;
  final double? efficiency30Days;

  const SleepDashboardStats({
    required this.latest,
    required this.average7Days,
    required this.average30Days,
    required this.actualAverage7Days,
    required this.actualAverage30Days,
    required this.minimum30Days,
    required this.maximum30Days,
    required this.recordedDays7Days,
    required this.recordedDays30Days,
    required this.efficiency7Days,
    required this.efficiency30Days,
  });
}

const _sentinel = Object();
