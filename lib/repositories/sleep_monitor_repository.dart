import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/sleep_entry.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';
import '../models/sleep_night_summary.dart';
import '../models/sleep_stage_summary.dart';
import 'base_repository.dart';
import '../services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';

/// SQLite persistence and native-spool import for sleep monitoring.
class SleepMonitorRepository extends BaseRepository {
  static const _minimumSleepEntryDuration = Duration(minutes: 1);

  final SleepEntryRepositoryAdapter _sleepEntries =
      SleepEntryRepositoryAdapter();

  Future<List<SleepMonitorSession>> getUnestimatedSessions() async {
    final database = await db;
    if (!await _tableExists(database, 'sleep_monitor_sessions')) {
      return const [];
    }
    final rows = await database.query(
      'sleep_monitor_sessions',
      where:
          'sleep_entry_id IS NULL AND algorithm_version IN '
          '(${List.filled(SleepWakeEngine.featureVersions.length, '?').join(', ')}) '
          'AND status IN (?, ?)',
      whereArgs: [
        ...SleepWakeEngine.featureVersions,
        SleepMonitorSession.completed,
        SleepMonitorSession.interrupted,
      ],
      orderBy: 'started_at DESC',
      limit: 5,
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

  Future<List<SleepNightSummary>> getNightSummaries({
    int? limit,
    int? offset,
  }) async {
    final database = await db;
    final entryRows = await database.query(
      'sleep_entries',
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
      offset: offset,
    );
    final entries = entryRows.map(SleepEntry.fromMap).toList(growable: false);
    if (entries.isEmpty) return const [];

    final entryIds = entries.map((entry) => entry.id).toList(growable: false);
    final placeholders = List.filled(entryIds.length, '?').join(',');
    final sessionRows = await database.query(
      'sleep_monitor_sessions',
      where: 'sleep_entry_id IN ($placeholders)',
      whereArgs: entryIds,
      orderBy: 'started_at DESC',
    );
    final sessionsByEntry = <String, SleepMonitorSession>{};
    for (final row in sessionRows) {
      final session = SleepMonitorSession.fromMap(row);
      final entryId = session.sleepEntryId;
      if (entryId != null) sessionsByEntry.putIfAbsent(entryId, () => session);
    }

    return entries
        .map((entry) {
          return SleepNightSummary(
            entry: entry,
            session: sessionsByEntry[entry.id],
          );
        })
        .toList(growable: false);
  }

  Future<void> deleteSession(String sessionId) async {
    await (await db).delete(
      'sleep_monitor_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
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
    Map<String, dynamic> spool, {
    String? expectedStageVersion,
  }) async {
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
    final bedside = SleepWakeEngine.supports(recovered);
    final sessionEnd = recovered.endedAt ?? recovered.startedAt;
    // Only bedside feature nights (audio-features-v3/v4) are staged; older
    // recordings keep the legacy status and no inference.
    SleepStageSummary? stageSummary;
    if (bedside && rawSegments.any((segment) => segment.hasSpectralFeatures)) {
      final engineResult = const SleepWakeEngine().run(
        session: recovered,
        segments: rawSegments,
      );
      if (engineResult.ran) {
        stageSummary = const SleepStageAnalysisService().summarize(
          sessionStart: recovered.startedAt,
          sessionEnd: sessionEnd,
          epochs: engineResult.epochs,
        );
      }
    }
    final sufficientlyClassified =
        stageSummary != null &&
        stageSummary.unknownMinutes <= (recovered.timeInBedMinutes ?? 0) * 0.2;
    final estimatedSleepMinutes = bedside
        ? (sufficientlyClassified ? stageSummary.estimatedSleepMinutes : null)
        : recovered.estimatedSleepMinutes;
    final importedSession = recovered.copyWith(
      estimatedSleepMinutes: estimatedSleepMinutes,
      analysisStatus: stageSummary != null
          ? SleepMonitorSession.analysisAvailable
          : bedside
          ? SleepMonitorSession.analysisInsufficient
          : SleepMonitorSession.analysisLegacyUnavailable,
      sleepOnsetAt: stageSummary?.sleepOnsetAt,
      finalWakeAt: stageSummary?.finalWakeAt,
      sleepLatencyMinutes: stageSummary?.sleepOnsetAt == null
          ? null
          : stageSummary?.sleepLatencyMinutes,
      awakeMinutes: stageSummary?.awakeMinutes,
      sleepingMinutes: stageSummary?.sleepingMinutes,
      unknownMinutes: stageSummary?.unknownMinutes,
      awakeningCount: stageSummary?.awakeningCount,
      sleepEfficiency: sufficientlyClassified
          ? stageSummary.sleepEfficiency
          : null,
      stageAlgorithmVersion: stageSummary?.algorithmVersion,
    );
    final database = await db;

    SleepMonitorSession? imported;
    await database.transaction((txn) async {
      if (expectedStageVersion != null) {
        final existing = await txn.query(
          'sleep_monitor_sessions',
          columns: ['id'],
          where:
              'id = ? AND stage_algorithm_version = ? AND sleep_entry_id IS NULL AND estimated_sleep_minutes IS NULL',
          whereArgs: [recovered.id, expectedStageVersion],
        );
        if (existing.isEmpty) {
          throw StateError('session_changed_during_reanalysis');
        }
      }
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
          (!bedside || importedSession.estimatedSleepMinutes != null) &&
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
        } else if (expectedStageVersion == null) {
          // Archived reanalysis preserves any entry created since that night.
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
      // Segments and stage epochs are transient calculation material. They
      // were consumed above to produce the session aggregates and are never
      // persisted, so the database only stores the nightly summary.
      imported = session;
    });
    return imported!;
  }

  /// Repairs only incomplete v1-v4 results that still have capture data.
  /// Database metadata wins over the archive, including later alarm dismissal.
  Future<SleepMonitorSession?> reprocessDiagnostic(
    Map<String, dynamic> archive,
  ) async {
    final raw = archive['session'];
    if (raw is! Map || raw['id'] is! String) return null;
    final current = await getSession(raw['id'] as String);
    if (current == null ||
        current.sleepEntryId != null ||
        current.estimatedSleepMinutes != null ||
        !SleepWakeEngine.supports(current) ||
        !{
          SleepMonitorSession.completed,
          SleepMonitorSession.interrupted,
        }.contains(current.status) ||
        !{
          'sleep-wake-bedside-v1',
          'sleep-wake-bedside-v2',
          'sleep-wake-bedside-v3',
          'sleep-wake-bedside-v4',
        }.contains(current.stageAlgorithmVersion) ||
        DateTime.tryParse(raw['started_at']?.toString() ?? '') !=
            current.startedAt ||
        DateTime.tryParse(raw['ended_at']?.toString() ?? '') !=
            current.endedAt ||
        archive['segments'] is! List) {
      return null;
    }
    return importNativeSpool({
      'session': {...raw, ...current.toMap()},
      'segments': archive['segments'],
    }, expectedStageVersion: current.stageAlgorithmVersion);
  }

  Future<SleepEntry?> getSleepEntry(String id) async =>
      _sleepEntries.getById(await db, id);

  static Future<bool> _tableExists(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }
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
