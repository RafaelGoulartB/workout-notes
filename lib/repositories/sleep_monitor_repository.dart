import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_night_summary.dart';
import 'package:workout_notes/models/sleep_stage_summary.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// SQLite persistence and native-spool import for sleep monitoring.
class SleepMonitorRepository extends BaseRepository {
  static const _minimumSleepEntryDuration = Duration(minutes: 1);

  final SleepEntryRepositoryAdapter _sleepEntries =
      SleepEntryRepositoryAdapter();

  Future<List<SleepMonitorSession>> getUnestimatedSessions() async {
    final database = await db;
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

  /// Saves the morning answer to "how did you wake up?" (1-3).
  Future<void> setWakeFeeling(String sessionId, int feeling) async {
    await (await db).update(
      'sleep_monitor_sessions',
      {
        'wake_feeling': feeling.clamp(
          SleepMonitorSession.feelingTired,
          SleepMonitorSession.feelingRefreshed,
        ),
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
    // Only bedside feature nights (audio-features-v3/v4/v5) are staged; older
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
      restlessSleepMinutes: stageSummary?.restlessSleepMinutes,
      snoreMinutes: stageSummary?.snoreMinutes,
      awakeningCount: stageSummary?.awakeningCount,
      sleepEfficiency: sufficientlyClassified
          ? stageSummary.sleepEfficiency
          : null,
      stageAlgorithmVersion: stageSummary?.algorithmVersion,
      stageTimeline: stageSummary?.timeline?.encode(),
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
      final localDate = dayOf(wallClockEnd);
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
      await txn.insert(
        'sleep_monitor_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Segments and stage epochs are transient calculation material. They
      // were consumed above to produce the session aggregates and are never
      // persisted, so the database only stores the nightly summary.
      imported = session;
    });
    return imported!;
  }

  /// Repairs only incomplete v1-v5 results that still have capture data.
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
          'sleep-wake-bedside-v5',
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

  /// Recent bedside nights whose analysis predates the current engine or has
  /// no night timeline; [refreshAnalysis] can upgrade them from an archive.
  Future<List<SleepMonitorSession>> getSessionsNeedingAnalysisRefresh({
    int limit = 14,
  }) async {
    final rows = await (await db).query(
      'sleep_monitor_sessions',
      where:
          'algorithm_version IN '
          '(${List.filled(SleepWakeEngine.featureVersions.length, '?').join(', ')}) '
          'AND status IN (?, ?) '
          'AND (stage_algorithm_version IS NULL OR stage_algorithm_version != ? '
          'OR stage_timeline IS NULL)',
      whereArgs: [
        ...SleepWakeEngine.featureVersions,
        SleepMonitorSession.completed,
        SleepMonitorSession.interrupted,
        SleepWakeEngine.algorithmVersion,
      ],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(SleepMonitorSession.fromMap).toList();
  }

  /// Re-stages an already imported night from its diagnostic archive with the
  /// current engine. Only the session's analysis changes; the linked sleep
  /// entry follows only while it still carries this session's untouched
  /// estimate (a manual correction or a longer night on the same date wins).
  /// Returns null when nothing was updated.
  Future<SleepMonitorSession?> refreshAnalysis(
    Map<String, dynamic> archive,
  ) async {
    final raw = archive['session'];
    if (raw is! Map || raw['id'] is! String || archive['segments'] is! List) {
      return null;
    }
    final current = await getSession(raw['id'] as String);
    if (current == null ||
        !SleepWakeEngine.supports(current) ||
        (current.stageAlgorithmVersion == SleepWakeEngine.algorithmVersion &&
            current.stageTimeline != null) ||
        !{
          SleepMonitorSession.completed,
          SleepMonitorSession.interrupted,
        }.contains(current.status) ||
        DateTime.tryParse(raw['started_at']?.toString() ?? '') !=
            current.startedAt ||
        DateTime.tryParse(raw['ended_at']?.toString() ?? '') !=
            current.endedAt) {
      return null;
    }
    final segments = (archive['segments'] as List)
        .whereType<Map>()
        .map(
          (row) => SleepMonitorSegment.fromMap(Map<String, dynamic>.from(row)),
        )
        .where((segment) => segment.sessionId == current.id)
        .toList();
    final end = current.endedAt;
    if (end == null || !segments.any((s) => s.hasSpectralFeatures)) {
      return null;
    }
    final result = const SleepWakeEngine().run(
      session: current,
      segments: segments,
    );
    if (!result.ran) return null;
    final summary = const SleepStageAnalysisService().summarize(
      sessionStart: current.startedAt,
      sessionEnd: end,
      epochs: result.epochs,
    );
    // Never trade an existing estimate for an incomplete one.
    if (summary == null ||
        summary.unknownMinutes > (current.timeInBedMinutes ?? 0) * 0.2) {
      return null;
    }
    final refreshed = current.copyWith(
      analysisStatus: SleepMonitorSession.analysisAvailable,
      estimatedSleepMinutes: summary.estimatedSleepMinutes,
      sleepOnsetAt: summary.sleepOnsetAt,
      finalWakeAt: summary.finalWakeAt,
      sleepLatencyMinutes: summary.sleepOnsetAt == null
          ? null
          : summary.sleepLatencyMinutes,
      awakeMinutes: summary.awakeMinutes,
      sleepingMinutes: summary.sleepingMinutes,
      unknownMinutes: summary.unknownMinutes,
      restlessSleepMinutes: summary.restlessSleepMinutes,
      snoreMinutes: summary.snoreMinutes,
      awakeningCount: summary.awakeningCount,
      sleepEfficiency: summary.sleepEfficiency,
      stageAlgorithmVersion: summary.algorithmVersion,
      stageTimeline: summary.timeline?.encode(),
    );
    await (await db).transaction((txn) async {
      await txn.update(
        'sleep_monitor_sessions',
        {
          ...refreshed.toMap(),
          // copyWith cannot clear a value; a night without a final wake
          // must not keep the previous engine's.
          'final_wake_at': summary.finalWakeAt?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [current.id],
      );
      final entryId = current.sleepEntryId;
      final previous = current.estimatedSleepMinutes;
      if (entryId == null || previous == null) return;
      final entry = await _sleepEntries.getById(txn, entryId);
      if (entry == null ||
          entry.source != 'monitored' ||
          entry.estimatedSleepMinutes != previous) {
        return;
      }
      await txn.update(
        'sleep_entries',
        {
          'estimated_sleep_minutes': summary.estimatedSleepMinutes,
          if (entry.sleepMinutes == previous)
            'sleep_minutes': summary.estimatedSleepMinutes,
        },
        where: 'id = ?',
        whereArgs: [entryId],
      );
    });
    return refreshed;
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
    final value = dateKey(date);
    final rows = await database.query(
      'sleep_entries',
      where: 'date = ?',
      whereArgs: [value],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }

  Future<SleepEntry?> getById(DatabaseExecutor database, String id) async {
    final rows = await database.query(
      'sleep_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }
}
