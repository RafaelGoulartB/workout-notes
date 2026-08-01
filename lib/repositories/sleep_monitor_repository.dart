import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/sleep_entry.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_diagnostics.dart';
import '../models/sleep_monitor_session.dart';
import 'base_repository.dart';
import '../services/sleep_inference_service.dart';

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

  /// Counts alarms completed through the emergency mission.
  ///
  /// Legacy methods remain included so changing the challenge to 500 taps
  /// does not hide completions already stored on the device.
  Future<int> getEmergencyDismissalCount() async {
    final rows = await (await db).rawQuery(
      'SELECT COUNT(*) AS count FROM sleep_monitor_sessions '
      'WHERE alarm_dismiss_method IN (?, ?, ?)',
      [
        SleepMonitorSession.dismissEmergency500Taps,
        SleepMonitorSession.dismissEmergency1000Taps,
        SleepMonitorSession.dismissEmergency100Taps,
      ],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
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
    final diagnostics = SleepMonitorDiagnostics.fromSession(
      recovered,
      rawSegments,
    );
    final inference = const SleepInferenceService().analyze(
      session: recovered,
      segments: rawSegments,
      diagnostics: diagnostics,
    );
    final estimatedSleepMinutes =
        recovered.estimatedSleepMinutes ??
        (inference.estimatedSleepSeconds == null
            ? null
            : (inference.estimatedSleepSeconds! / 60).round());
    final importedSession =
        estimatedSleepMinutes == null || recovered.estimatedSleepMinutes != null
        ? recovered
        : recovered.copyWith(estimatedSleepMinutes: estimatedSleepMinutes);
    final database = await db;

    SleepMonitorSession? imported;
    await database.transaction((txn) async {
      final end = importedSession.endedAt ?? importedSession.startedAt;
      final endOffsetMinutes =
          importedSession.utcOffsetEndMinutes ??
          importedSession.utcOffsetStartMinutes;
      final wallClockStart = importedSession.startedAt.toUtc().add(
        Duration(minutes: importedSession.utcOffsetStartMinutes),
      );
      final wallClockEnd = end.toUtc().add(Duration(minutes: endOffsetMinutes));
      final localDate = DateTime(
        wallClockEnd.year,
        wallClockEnd.month,
        wallClockEnd.day,
      );
      final duration = end.difference(importedSession.startedAt);
      final canCreateSleepEntry =
          const {
            SleepMonitorSession.completed,
            SleepMonitorSession.interrupted,
          }.contains(importedSession.status) &&
          duration >= _minimumSleepEntryDuration &&
          rawSegments.isNotEmpty &&
          (importedSession.timeInBedMinutes ?? 0) > 0;
      final bedtimeMinutes = wallClockStart.hour * 60 + wallClockStart.minute;
      final wakeTimeMinutes = wallClockEnd.hour * 60 + wallClockEnd.minute;
      final incomingTimeInBed =
          importedSession.timeInBedMinutes ?? duration.inMinutes;
      final incomingSleepMinutes =
          importedSession.estimatedSleepMinutes ?? incomingTimeInBed;

      SleepEntry? entry;
      if (canCreateSleepEntry) {
        entry = await _sleepEntries.getByDate(txn, localDate);
        if (entry == null) {
          entry = SleepEntry(
            id: const Uuid().v4(),
            date: localDate,
            sleepMinutes: incomingSleepMinutes,
            actualSleepMinutes: null,
            bedtimeMinutes: bedtimeMinutes,
            wakeTimeMinutes: wakeTimeMinutes,
            comment: null,
            source: 'monitored',
            timeInBedMinutes: incomingTimeInBed,
            estimatedSleepMinutes: importedSession.estimatedSleepMinutes,
            createdAt: importedSession.createdAt,
          );
          await txn.insert('sleep_entries', entry.toMap());
        } else {
          // A short test/recovery session must not replace a longer night
          // already recorded for the same local date.
          final existingDuration = entry.timeInBedMinutes ?? entry.sleepMinutes;
          final incomingIsAtLeastAsLong = incomingTimeInBed >= existingDuration;
          entry = entry.copyWith(
            source: 'monitored',
            sleepMinutes: incomingIsAtLeastAsLong
                ? incomingSleepMinutes
                : entry.sleepMinutes,
            bedtimeMinutes: incomingIsAtLeastAsLong
                ? bedtimeMinutes
                : entry.bedtimeMinutes,
            wakeTimeMinutes: incomingIsAtLeastAsLong
                ? wakeTimeMinutes
                : entry.wakeTimeMinutes,
            timeInBedMinutes: incomingIsAtLeastAsLong
                ? incomingTimeInBed
                : entry.timeInBedMinutes,
            estimatedSleepMinutes:
                incomingIsAtLeastAsLong &&
                    importedSession.estimatedSleepMinutes != null
                ? importedSession.estimatedSleepMinutes
                : entry.estimatedSleepMinutes,
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
          ? importedSession
          : importedSession.copyWith(sleepEntryId: entry.id);
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

  /// Backfills dashboard fields for entries imported by older app versions.
  ///
  /// Older imports linked a monitor session but left bedtime and wake-up time
  /// empty. When multiple sessions point to one date, the longest completed
  /// session is used so a short test run cannot replace the overnight window.
  Future<void> repairSleepEntriesFromSessions() async {
    final database = await db;
    await database.transaction((txn) async {
      final sessionRows = await txn.query(
        'sleep_monitor_sessions',
        where: 'sleep_entry_id IS NOT NULL AND ended_at IS NOT NULL',
      );
      final byEntry = <String, List<SleepMonitorSession>>{};
      for (final row in sessionRows) {
        final session = SleepMonitorSession.fromMap(row);
        if (!const {
          SleepMonitorSession.completed,
          SleepMonitorSession.interrupted,
        }.contains(session.status)) {
          continue;
        }
        final entryId = session.sleepEntryId;
        if (entryId == null) continue;
        byEntry.putIfAbsent(entryId, () => []).add(session);
      }

      for (final item in byEntry.entries) {
        final rows = await txn.query(
          'sleep_entries',
          where: 'id = ?',
          whereArgs: [item.key],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final entry = SleepEntry.fromMap(rows.first);
        final candidates = item.value
          ..sort((a, b) => _sessionDuration(b).compareTo(_sessionDuration(a)));
        final best = candidates.first;
        final end = best.endedAt ?? best.startedAt;
        final startWallClock = best.startedAt.toUtc().add(
          Duration(minutes: best.utcOffsetStartMinutes),
        );
        final endWallClock = end.toUtc().add(
          Duration(
            minutes: best.utcOffsetEndMinutes ?? best.utcOffsetStartMinutes,
          ),
        );
        final duration = best.timeInBedMinutes ?? _sessionDuration(best);
        final updates = <String, dynamic>{
          'bedtime_minutes': startWallClock.hour * 60 + startWallClock.minute,
          'wake_time_minutes': endWallClock.hour * 60 + endWallClock.minute,
        };
        if ((entry.timeInBedMinutes ?? 0) < duration) {
          updates['time_in_bed_minutes'] = duration;
        }
        if (entry.estimatedSleepMinutes == null &&
            best.estimatedSleepMinutes != null) {
          updates['estimated_sleep_minutes'] = best.estimatedSleepMinutes;
        }
        await txn.update(
          'sleep_entries',
          updates,
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
    });
  }

  static int _sessionDuration(SleepMonitorSession session) {
    final end = session.endedAt ?? session.startedAt;
    return end.difference(session.startedAt).inMinutes;
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
