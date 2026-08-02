import 'package:uuid/uuid.dart';

import '../models/traditional_alarm.dart';
import 'base_repository.dart';

class TraditionalAlarmRepository extends BaseRepository {
  static const _uuid = Uuid();

  Future<List<TraditionalAlarm>> getAll() async {
    final rows = await (await db).query(
      'traditional_alarms',
      orderBy: 'hour ASC, minute ASC, created_at ASC',
    );
    return rows
        .map((row) => TraditionalAlarm.fromMap(Map<String, Object?>.from(row)))
        .toList();
  }

  Future<TraditionalAlarm> insert({
    required int hour,
    required int minute,
    required List<int> weekdays,
    required bool snoozeEnabled,
    required int snoozeMinutes,
    required bool requiresMission,
  }) async {
    final now = DateTime.now();
    final draft = TraditionalAlarm(
      id: _uuid.v4(),
      hour: hour,
      minute: minute,
      weekdays: List<int>.from(weekdays)..sort(),
      enabled: true,
      snoozeEnabled: snoozeEnabled,
      snoozeMinutes: snoozeMinutes,
      requiresMission: requiresMission,
      nextTriggerAt: null,
      createdAt: now,
      updatedAt: now,
    );
    final alarm = draft.copyWith(nextTriggerAt: draft.nextOccurrence(now: now));
    await (await db).insert('traditional_alarms', alarm.toMap());
    return alarm;
  }

  Future<void> update(TraditionalAlarm alarm) async {
    await (await db).update(
      'traditional_alarms',
      alarm.toMap(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }

  Future<void> updateNativeSchedule(
    String id, {
    required bool enabled,
    DateTime? nextTriggerAt,
  }) async {
    await (await db).update(
      'traditional_alarms',
      {
        'enabled': enabled ? 1 : 0,
        'next_trigger_at': nextTriggerAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    await (await db).delete(
      'traditional_alarms',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
