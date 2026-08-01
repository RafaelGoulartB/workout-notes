import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/sleep_entry.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';
import 'base_repository.dart';

/// SQLite persistence and native-spool import for sleep monitoring.
class SleepMonitorRepository extends BaseRepository {
  static const _minimumSleepEntryDuration = Duration(minutes: 1);

  final SleepEntryRepositoryAdapter _sleepEntries =
      SleepEntryRepositoryAdapter();

  Future<List<SleepMonitorSession>> getSessions({int? limit}) async {
    final rows = await (await db).query(
      'sleep_monitor_sessions',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(SleepMonitorSession.fromMap).toList();
  }

  Future<SleepMonitorSession?> getSession(String id) async {
    final rows = await (await db).query(
      'sleep_monitor_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepMonitorSession.fromMap(rows.first);
  }

  Future<SleepMonitorSession?> getSessionForSleepEntry(String entryId) async {
    final rows = await (await db).query(
      'sleep_monitor_sessions',
      where: 'sleep_entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SleepMonitorSession.fromMap(rows.first);
  }

  Future<List<SleepMonitorSegment>> getSegments(String sessionId) async {
    final rows = await (await db).query(
      'sleep_monitor_segments',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'started_at ASC',
    );
    return rows.map(SleepMonitorSegment.fromMap).toList();
  }

  Future<void> deleteSession(String sessionId) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'sleep_monitor_segments',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'sleep_monitor_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<void> markAlarmDismissed(
    String sessionId,
    String method,
    DateTime dismissedAt,
  ) async {
    await (await db).update(
      'sleep_monitor_sessions',
      {
        'alarm_dismiss_method': method,
        'alarm_dismissed_at': dismissedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Imports a native spool atomically. Re-importing the same session replaces
  /// its aggregate rows and never creates a second sleep entry.
  Future<SleepMonitorSession> importNativeSpool(
    Map<String, dynamic> spool,
  ) async {
    final rawSession = Map<String, dynamic>.from(
      spool['session'] as Map? ?? spool,
    );
    final rawSegments = (spool['segments'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => SleepMonitorSegment.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
    final recovered = SleepMonitorSession.fromNative(rawSession, rawSegments);
    final database = await db;

    SleepMonitorSession? imported;
    await database.transaction((txn) async {
      final end = recovered.endedAt ?? recovered.startedAt;
      final offsetMinutes =
          recovered.utcOffsetEndMinutes ?? recovered.utcOffsetStartMinutes;
      final wallClockEnd = end.toUtc().add(Duration(minutes: offsetMinutes));
      final localDate = DateTime(
        wallClockEnd.year,
        wallClockEnd.month,
        wallClockEnd.day,
      );
      final duration = end.difference(recovered.startedAt);
      final canCreateSleepEntry =
          const {
            SleepMonitorSession.completed,
            SleepMonitorSession.interrupted,
          }.contains(recovered.status) &&
          duration >= _minimumSleepEntryDuration &&
          rawSegments.isNotEmpty &&
          (recovered.timeInBedMinutes ?? 0) > 0;

      SleepEntry? entry;
      if (canCreateSleepEntry) {
        entry = await _sleepEntries.getByDate(txn, localDate);
        if (entry == null) {
          entry = SleepEntry(
            id: const Uuid().v4(),
            date: localDate,
            sleepMinutes: recovered.timeInBedMinutes!,
            actualSleepMinutes: null,
            bedtimeMinutes: null,
            wakeTimeMinutes: wallClockEnd.hour * 60 + wallClockEnd.minute,
            comment: null,
            source: 'monitored',
            timeInBedMinutes: recovered.timeInBedMinutes,
            estimatedSleepMinutes: recovered.estimatedSleepMinutes,
            createdAt: recovered.createdAt,
          );
          await txn.insert('sleep_entries', entry.toMap());
        } else {
          entry = entry.copyWith(
            source: entry.source == 'manual' ? 'hybrid' : entry.source,
            timeInBedMinutes: recovered.timeInBedMinutes,
            estimatedSleepMinutes: recovered.estimatedSleepMinutes,
          );
          await txn.update(
            'sleep_entries',
            entry.toMap(),
            where: 'id = ?',
            whereArgs: [entry.id],
          );
        }
      }

      final session = entry == null
          ? recovered
          : recovered.copyWith(sleepEntryId: entry.id);
      final sessionColumns = (await txn.rawQuery(
        'PRAGMA table_info(sleep_monitor_sessions)',
      )).map((row) => row['name'] as String).toSet();
      final sessionMap = session.toMap()
        ..removeWhere((key, _) => !sessionColumns.contains(key));
      await txn.insert(
        'sleep_monitor_sessions',
        sessionMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'sleep_monitor_segments',
        where: 'session_id = ?',
        whereArgs: [session.id],
      );
      for (final segment in rawSegments) {
        await txn.insert('sleep_monitor_segments', segment.toMap());
      }
      imported = session;
    });
    return imported!;
  }

  Future<SleepEntry?> getSleepEntry(String id) async =>
      _sleepEntries.getById(await db, id);
}

/// Small transaction-aware adapter that keeps sleep merging inside the same
/// SQLite transaction as session import.
class SleepEntryRepositoryAdapter {
  Future<SleepEntry?> getByDate(
    DatabaseExecutor database,
    DateTime date,
  ) async {
    final value = date.toIso8601String().substring(0, 10);
    final rows = await database.query(
      'sleep_entries',
      where: 'date = ?',
      whereArgs: [value],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }

  Future<SleepEntry?> getById(Database database, String id) async {
    final rows = await database.query(
      'sleep_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }
}
