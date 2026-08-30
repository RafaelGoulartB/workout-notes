import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/services/run_route_codec.dart';
import 'package:workout_notes/utils/run_effort_analytics.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

class RunRepository extends BaseRepository {
  static const _uuid = Uuid();

  Future<List<RunActivity>> listActivities({
    int limit = 50,
    int offset = 0,
    CardioActivityType? activityType = CardioActivityType.running,
  }) async {
    final database = await db;
    final rows = await database.query(
      'run_activities',
      where: activityType == null
          ? 'status = ?'
          : 'status = ? AND activity_type = ?',
      whereArgs: activityType == null
          ? ['completed']
          : ['completed', activityType.databaseValue],
      orderBy: 'started_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(RunActivity.fromMap).toList();
  }

  Future<RunActivity?> getActivity(String id) async {
    final database = await db;
    final rows = await database.query(
      'run_activities',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RunActivity.fromMap(rows.first);
  }

  Future<List<RunTrackPoint>> getTrackPoints(String activityId) async {
    final database = await db;
    if (await _tableExists(database, 'run_route_data')) {
      final compact = await database.query(
        'run_route_data',
        columns: ['payload', 'checksum'],
        where: 'activity_id = ?',
        whereArgs: [activityId],
        limit: 1,
      );
      if (compact.isNotEmpty) {
        try {
          final rawPayload = compact.first['payload'];
          final payload = rawPayload is Uint8List
              ? rawPayload
              : Uint8List.fromList((rawPayload as List).cast<int>());
          return RunRouteCodec.decode(
            activityId: activityId,
            payload: payload,
            expectedChecksum: (compact.first['checksum'] as num).toInt(),
          );
        } on FormatException {
          // A legacy copy is deliberately retained until compact persistence
          // succeeds. If an externally-restored blob is corrupt, fall back to
          // those rows rather than hiding the route.
        }
      }
    }
    return _getLegacyTrackPoints(database, activityId);
  }

  Future<List<RunTrackPoint>> _getLegacyTrackPoints(
    DatabaseExecutor database,
    String activityId,
  ) async {
    final rows = await database.query(
      'run_track_points',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'seq ASC',
    );
    return rows.map(RunTrackPoint.fromMap).toList();
  }

  Future<List<RunSplit>> getSplits(String activityId) async {
    final database = await db;
    if (await _tableExists(database, 'run_splits')) {
      final rows = await database.query(
        'run_splits',
        where: 'activity_id = ?',
        whereArgs: [activityId],
        orderBy: 'split_index ASC',
      );
      if (rows.isNotEmpty) {
        return rows
            .map(
              (row) => RunSplit(
                km: (row['split_index'] as num).toInt(),
                distanceMeters: (row['distance_meters'] as num).toDouble(),
                durationSeconds: (row['duration_seconds'] as num).toInt(),
                paceSecPerKm: (row['pace_sec_per_km'] as num?)?.toDouble(),
                isPartial: (row['is_partial'] as num).toInt() == 1,
              ),
            )
            .toList();
      }
    }
    final points = await getTrackPoints(activityId);
    return RunPaceAnalytics.fromTrackPoints(points).splits;
  }

  Future<void> updateActivityMeta({
    required String id,
    String? title,
    String? notes,
    double? rpe,
    int? feelingRating,
  }) async {
    final database = await db;
    await database.update(
      'run_activities',
      {
        'title': ?title,
        'notes': ?notes,
        'rpe': ?rpe,
        'feeling_rating': ?feelingRating,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteActivity(String id) async {
    final database = await db;
    // The FK only nulls `run_activity_id`, which would leave a plan session
    // counted as completed with no run behind it. Put it back to planned so
    // the plan's progress keeps matching reality.
    if (await _tableExists(database, 'scheduled_runs')) {
      await database.update(
        'scheduled_runs',
        {
          'status': 'planned',
          'run_activity_id': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'run_activity_id = ?',
        whereArgs: [id],
      );
    }
    await database.delete('run_activities', where: 'id = ?', whereArgs: [id]);
  }

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

  /// Monthly aggregation for the home hero card — pure run data.
  /// Returns `total_distance_meters`, `total_moving_time`, `total_duration`
  /// and `run_count` for the calendar month of [month].
  /// Uses `started_at` range so it matches the `run_activities` storage
  /// format (ISO-8601 with `T` separator).
  Future<Map<String, dynamic>> getMonthlyRunSummary(
    DateTime month, {
    CardioActivityType? activityType = CardioActivityType.running,
  }) async {
    final database = await db;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(distance_meters), 0) AS total_distance_meters,
        COALESCE(SUM(moving_time_seconds), 0) AS total_moving_time,
        COALESCE(SUM(duration_seconds), 0) AS total_duration,
        COUNT(*) AS run_count
      FROM run_activities
      WHERE status = 'completed' AND started_at >= ? AND started_at < ?
        ${activityType == null ? '' : 'AND activity_type = ?'}
      ''',
      [
        start.toIso8601String(),
        end.toIso8601String(),
        if (activityType != null) activityType.databaseValue,
      ],
    );
    return rows.first;
  }

  /// Completed runs of a calendar month, for the calendar view.
  /// Keyed by `yyyy-MM-dd` of the local start date.
  Future<Map<String, List<RunActivity>>> getActivitiesByMonth(
    int year,
    int month,
  ) async {
    final database = await db;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final rows = await database.query(
      'run_activities',
      where: 'status = ? AND started_at >= ? AND started_at < ?',
      whereArgs: ['completed', start.toIso8601String(), end.toIso8601String()],
      orderBy: 'started_at ASC',
    );
    final grouped = <String, List<RunActivity>>{};
    for (final row in rows) {
      final activity = RunActivity.fromMap(row);
      final key = activity.startedAt.toIso8601String().substring(0, 10);
      grouped.putIfAbsent(key, () => []).add(activity);
    }
    return grouped;
  }

  /// Computes and persists GPS effort metrics for [activityId] when missing.
  /// Returns the refreshed activity (or null if not found).
  Future<RunActivity?> ensureEffortMetrics(String activityId) async {
    final activity = await getActivity(activityId);
    if (activity == null) return null;
    if (!activity.isRun) return activity;
    if (activity.effortsComputed) return activity;

    final points = await getTrackPoints(activityId);
    final metrics = RunEffortAnalytics.fromTrackPoints(points);
    final now = DateTime.now();
    final updated = RunActivity(
      id: activity.id,
      startedAt: activity.startedAt,
      endedAt: activity.endedAt,
      durationSeconds: activity.durationSeconds,
      movingTimeSeconds: activity.movingTimeSeconds,
      distanceMeters: activity.distanceMeters,
      avgPaceSecPerKm: activity.avgPaceSecPerKm,
      maxPaceSecPerKm: activity.maxPaceSecPerKm,
      calories: activity.calories,
      title: activity.title,
      notes: activity.notes,
      rpe: activity.rpe,
      feelingRating: activity.feelingRating,
      status: activity.status,
      polylineSummary: activity.polylineSummary,
      createdAt: activity.createdAt,
      updatedAt: now,
      bestSplitPaceSecPerKm: metrics.bestSplitPaceSecPerKm,
      bestEffort1kSec: metrics.bestEffort1kSec,
      bestEffort3kSec: metrics.bestEffort3kSec,
      bestEffort5kSec: metrics.bestEffort5kSec,
      bestEffort10kSec: metrics.bestEffort10kSec,
      bestEffortHalfSec: metrics.bestEffortHalfSec,
      bestEffortMarathonSec: metrics.bestEffortMarathonSec,
      effortsComputed: true,
    );
    await _persistEffortMetrics(updated);
    return updated;
  }

  /// Backfills effort metrics for activities that still need computation.
  /// Returns how many rows were updated.
  Future<int> backfillMissingEfforts({int limit = 40}) async {
    final database = await db;
    final rows = await database.query(
      'run_activities',
      columns: ['id'],
      where:
          "status = ? AND activity_type = ? AND IFNULL(efforts_computed, 0) = 0",
      whereArgs: ['completed', CardioActivityType.running.databaseValue],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    var updated = 0;
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final result = await ensureEffortMetrics(id);
      if (result != null) updated++;
    }
    return updated;
  }

  Future<void> _persistEffortMetrics(RunActivity activity) async {
    final database = await db;
    await database.update(
      'run_activities',
      {
        'best_split_pace_sec_per_km': activity.bestSplitPaceSecPerKm,
        'best_effort_1k_sec': activity.bestEffort1kSec,
        'best_effort_3k_sec': activity.bestEffort3kSec,
        'best_effort_5k_sec': activity.bestEffort5kSec,
        'best_effort_10k_sec': activity.bestEffort10kSec,
        'best_effort_half_sec': activity.bestEffortHalfSec,
        'best_effort_marathon_sec': activity.bestEffortMarathonSec,
        'efforts_computed': activity.effortsComputed ? 1 : 0,
        'updated_at': activity.updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [activity.id],
    );
  }

  /// Imports a native JSON spool atomically. Idempotent per activity id.
  Future<RunActivity> importNativeSpool(Map<String, dynamic> spool) async {
    final rawActivity = Map<String, dynamic>.from(
      spool['activity'] as Map? ?? const {},
    );
    final id = rawActivity['id'] as String? ?? _uuid.v4();
    final existing = await getActivity(id);
    if (existing != null) return existing;

    final bodyWeightKg = await _latestBodyWeightKg();
    final decoded = _decodeNativeSpool(
      spool,
      id: id,
      bodyWeightKg: bodyWeightKg,
    );
    final activity = decoded.activity;
    final points = decoded.points;
    final hasCompactRoutes = await _tableExists(await db, 'run_route_data');
    final encoded = hasCompactRoutes && points.isNotEmpty
        ? RunRouteCodec.encode(points)
        : null;
    if (encoded != null) _validateEncoding(activity.id, points, encoded);
    final pace = RunPaceAnalytics.fromTrackPoints(
      points,
      activityAvgPaceSecPerKm: activity.avgPaceSecPerKm,
    );
    final summary = _RouteSummary.fromPoints(points);

    final database = await db;
    await database.transaction((txn) async {
      await txn.insert('run_activities', activity.toMap());
      if (encoded != null) {
        await _storeCompactRoute(
          txn,
          activityId: activity.id,
          encoded: encoded,
          splits: pace.splits,
          summary: summary,
        );
      } else {
        for (final point in points) {
          await txn.insert('run_track_points', point.toMap());
        }
      }
    });

    return activity;
  }

  /// Converts a bounded number of legacy point-row activities. Each activity
  /// is independently transactional, so process death can only postpone work.
  Future<int> migrateLegacyRoutes({int limit = 5}) async {
    final database = await db;
    if (!await _tableExists(database, 'run_route_data')) return 0;
    final rows = await database.rawQuery(
      '''
      SELECT a.id
      FROM run_activities a
      WHERE EXISTS (
        SELECT 1 FROM run_track_points p WHERE p.activity_id = a.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM run_route_data r WHERE r.activity_id = a.id
      )
      ORDER BY a.started_at DESC
      LIMIT ?
      ''',
      [limit.clamp(1, 50)],
    );
    var migrated = 0;
    for (final row in rows) {
      final activityId = row['id'] as String;
      final points = await _getLegacyTrackPoints(database, activityId);
      if (points.isEmpty) continue;
      final encoded = RunRouteCodec.encode(points);
      _validateEncoding(activityId, points, encoded);
      final pace = RunPaceAnalytics.fromTrackPoints(points);
      final efforts = RunEffortAnalytics.fromTrackPoints(points);
      final summary = _RouteSummary.fromPoints(points);
      await database.transaction((txn) async {
        await _storeCompactRoute(
          txn,
          activityId: activityId,
          encoded: encoded,
          splits: pace.splits,
          summary: summary,
        );
        await txn.update(
          'run_activities',
          {
            'best_split_pace_sec_per_km': efforts.bestSplitPaceSecPerKm,
            'best_effort_1k_sec': efforts.bestEffort1kSec,
            'best_effort_3k_sec': efforts.bestEffort3kSec,
            'best_effort_5k_sec': efforts.bestEffort5kSec,
            'best_effort_10k_sec': efforts.bestEffort10kSec,
            'best_effort_half_sec': efforts.bestEffortHalfSec,
            'best_effort_marathon_sec': efforts.bestEffortMarathonSec,
            'efforts_computed': 1,
          },
          where: 'id = ?',
          whereArgs: [activityId],
        );
        await txn.delete(
          'run_track_points',
          where: 'activity_id = ?',
          whereArgs: [activityId],
        );
      });
      migrated++;
    }
    return migrated;
  }

  /// Applies the lower-detail archival profile only when route payloads exceed
  /// [thresholdBytes], unless [force] is explicitly requested by the user.
  Future<int> optimizeOldRoutes({
    DateTime? olderThan,
    int thresholdBytes = 150 * 1024 * 1024,
    int limit = 20,
    bool force = false,
  }) async {
    final database = await db;
    if (!await _tableExists(database, 'run_route_data')) return 0;
    final sizeRows = await database.rawQuery(
      'SELECT COALESCE(SUM(length(payload)), 0) AS bytes FROM run_route_data',
    );
    final bytes = (sizeRows.first['bytes'] as num?)?.toInt() ?? 0;
    if (!force && bytes < thresholdBytes) return 0;
    final cutoff =
        olderThan ?? DateTime.now().subtract(const Duration(days: 90));
    final rows = await database.rawQuery(
      '''
      SELECT r.activity_id, r.payload, r.checksum
      FROM run_route_data r
      JOIN run_activities a ON a.id = r.activity_id
      WHERE r.quality != ? AND a.started_at < ?
      ORDER BY a.started_at ASC
      LIMIT ?
      ''',
      [
        RunRouteQuality.archived.databaseValue,
        cutoff.toIso8601String(),
        limit.clamp(1, 100),
      ],
    );
    var optimized = 0;
    for (final row in rows) {
      final activityId = row['activity_id'] as String;
      final rawPayload = row['payload'];
      final payload = rawPayload is Uint8List
          ? rawPayload
          : Uint8List.fromList((rawPayload as List).cast<int>());
      final points = RunRouteCodec.decode(
        activityId: activityId,
        payload: payload,
        expectedChecksum: (row['checksum'] as num).toInt(),
      );
      final encoded = RunRouteCodec.encode(
        points,
        quality: RunRouteQuality.archived,
      );
      await database.transaction((txn) async {
        await txn.update(
          'run_route_data',
          {
            'codec_version': RunRouteCodec.version,
            'quality': encoded.quality.databaseValue,
            'point_count': encoded.storedPointCount,
            'payload': encoded.payload,
            'checksum': encoded.checksum,
            'compacted_at': DateTime.now().toIso8601String(),
          },
          where: 'activity_id = ?',
          whereArgs: [activityId],
        );
        await txn.update(
          'run_activities',
          {
            'stored_point_count': encoded.storedPointCount,
            'route_quality': encoded.quality.databaseValue,
            'route_codec_version': RunRouteCodec.version,
          },
          where: 'id = ?',
          whereArgs: [activityId],
        );
      });
      optimized++;
    }
    return optimized;
  }

  Future<void> reclaimIncrementalVacuumPages({int pages = 256}) async {
    final database = await db;
    final modeRows = await database.rawQuery('PRAGMA auto_vacuum');
    final mode = modeRows.isEmpty
        ? 0
        : (modeRows.first.values.first as num?)?.toInt() ?? 0;
    if (mode == 2) {
      await database.execute(
        'PRAGMA incremental_vacuum(${pages.clamp(1, 4096)})',
      );
    }
  }

  static Future<void> _storeCompactRoute(
    Transaction txn, {
    required String activityId,
    required EncodedRunRoute encoded,
    required List<RunSplit> splits,
    required _RouteSummary summary,
  }) async {
    await txn.insert('run_route_data', {
      'activity_id': activityId,
      'codec_version': RunRouteCodec.version,
      'quality': encoded.quality.databaseValue,
      'point_count': encoded.storedPointCount,
      'original_point_count': encoded.originalPointCount,
      'payload': encoded.payload,
      'checksum': encoded.checksum,
      'compacted_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.delete(
      'run_splits',
      where: 'activity_id = ?',
      whereArgs: [activityId],
    );
    for (final split in splits) {
      await txn.insert('run_splits', {
        'activity_id': activityId,
        'split_index': split.km,
        'distance_meters': split.distanceMeters,
        'duration_seconds': split.durationSeconds,
        'pace_sec_per_km': split.paceSecPerKm,
        'is_partial': split.isPartial ? 1 : 0,
      });
    }
    await txn.update(
      'run_activities',
      {
        'elevation_gain_meters': summary.elevationGain,
        'elevation_loss_meters': summary.elevationLoss,
        'minimum_altitude_meters': summary.minimumAltitude,
        'maximum_altitude_meters': summary.maximumAltitude,
        'gps_accuracy_mean_meters': summary.meanAccuracy,
        'gps_accuracy_good_fraction': summary.goodAccuracyFraction,
        'raw_point_count': encoded.originalPointCount,
        'stored_point_count': encoded.storedPointCount,
        'route_quality': encoded.quality.databaseValue,
        'route_codec_version': RunRouteCodec.version,
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
  }

  static void _validateEncoding(
    String activityId,
    List<RunTrackPoint> original,
    EncodedRunRoute encoded,
  ) {
    final decoded = RunRouteCodec.decode(
      activityId: activityId,
      payload: encoded.payload,
      expectedChecksum: encoded.checksum,
    );
    if (decoded.isEmpty || original.isEmpty) {
      if (decoded.length != original.length) {
        throw const FormatException('run_route_validation_failed');
      }
      return;
    }
    final ordered = List<RunTrackPoint>.of(original)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final firstError = RunPaceAnalytics.haversineMeters(
      lat1: decoded.first.lat,
      lng1: decoded.first.lng,
      lat2: ordered.first.lat,
      lng2: ordered.first.lng,
    );
    final lastError = RunPaceAnalytics.haversineMeters(
      lat1: decoded.last.lat,
      lng1: decoded.last.lng,
      lat2: ordered.last.lat,
      lng2: ordered.last.lng,
    );
    if (firstError > 0.25 ||
        lastError > 0.25 ||
        decoded.first.recordedAt.millisecondsSinceEpoch !=
            ordered.first.recordedAt.millisecondsSinceEpoch ||
        decoded.last.recordedAt.millisecondsSinceEpoch !=
            ordered.last.recordedAt.millisecondsSinceEpoch) {
      throw const FormatException('run_route_validation_failed');
    }
  }

  /// Builds the exact activity that would be imported, without touching
  /// SQLite. Used by the post-run review and achievement preview.
  RunActivity previewNativeSpool(Map<String, dynamic> spool) {
    final rawActivity = Map<String, dynamic>.from(
      spool['activity'] as Map? ?? const {},
    );
    final id = rawActivity['id'] as String? ?? _uuid.v4();
    return _decodeNativeSpool(spool, id: id).activity;
  }

  /// Builds a preview using the latest registered body weight. The pure,
  /// synchronous [previewNativeSpool] remains available for callers that do
  /// not have database access and uses the 70 kg fallback.
  Future<RunActivity> previewNativeSpoolUsingLatestWeight(
    Map<String, dynamic> spool,
  ) async {
    final rawActivity = Map<String, dynamic>.from(
      spool['activity'] as Map? ?? const {},
    );
    final id = rawActivity['id'] as String? ?? _uuid.v4();
    final bodyWeightKg = await _latestBodyWeightKg();
    return _decodeNativeSpool(
      spool,
      id: id,
      bodyWeightKg: bodyWeightKg,
    ).activity;
  }

  ({RunActivity activity, List<RunTrackPoint> points}) _decodeNativeSpool(
    Map<String, dynamic> spool, {
    required String id,
    double bodyWeightKg = 70,
  }) {
    final rawActivity = Map<String, dynamic>.from(
      spool['activity'] as Map? ?? const {},
    );
    final rawPoints = (spool['points'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final now = DateTime.now();
    final startedAt =
        DateTime.tryParse(rawActivity['started_at'] as String? ?? '') ?? now;
    final endedAt = DateTime.tryParse(rawActivity['ended_at'] as String? ?? '');
    final status = rawActivity['status'] as String? ?? 'completed';
    final activityType = CardioActivityType.fromDatabase(
      rawActivity['activity_type'],
    );
    if (status == 'discarded') {
      throw StateError('discarded_spool');
    }

    final distanceMeters =
        (rawActivity['distance_meters'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (rawActivity['duration_seconds'] as num?)?.toInt() ?? 0;
    final movingTimeSeconds =
        (rawActivity['moving_time_seconds'] as num?)?.toInt() ??
        durationSeconds;
    final avgPace = (rawActivity['avg_pace_sec_per_km'] as num?)?.toDouble();
    final maxPace = (rawActivity['max_pace_sec_per_km'] as num?)?.toDouble();
    final calories =
        (rawActivity['calories'] as num?)?.toInt() ??
        _estimateCalories(
          activityType: activityType,
          distanceMeters: distanceMeters,
          durationSeconds: movingTimeSeconds,
          bodyWeightKg: bodyWeightKg,
        );
    final title = rawActivity['title'] as String?;
    final notes = rawActivity['notes'] as String?;
    final rpe = (rawActivity['rpe'] as num?)?.toDouble();
    final feelingRating = (rawActivity['feeling_rating'] as num?)?.toInt();
    final polyline =
        rawActivity['polyline_summary'] as String? ??
        _buildPolylineSummary(rawPoints);

    final points = <RunTrackPoint>[];
    for (var i = 0; i < rawPoints.length; i++) {
      final row = rawPoints[i];
      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(
        RunTrackPoint(
          id: row['id'] as String? ?? _uuid.v4(),
          activityId: id,
          seq: (row['seq'] as num?)?.toInt() ?? i,
          lat: lat,
          lng: lng,
          altitude: (row['altitude'] as num?)?.toDouble(),
          accuracy: (row['accuracy'] as num?)?.toDouble(),
          speed: (row['speed'] as num?)?.toDouble(),
          recordedAt:
              DateTime.tryParse(row['recorded_at'] as String? ?? '') ??
              startedAt.add(Duration(seconds: i)),
        ),
      );
    }

    final efforts = activityType == CardioActivityType.running
        ? RunEffortAnalytics.fromTrackPoints(points)
        : const RunEffortMetrics();

    final activity = RunActivity(
      id: id,
      activityType: activityType,
      startedAt: startedAt,
      endedAt: endedAt ?? now,
      durationSeconds: durationSeconds,
      movingTimeSeconds: movingTimeSeconds,
      distanceMeters: distanceMeters,
      avgPaceSecPerKm: activityType == CardioActivityType.running
          ? avgPace ?? _avgPace(distanceMeters, movingTimeSeconds)
          : null,
      maxPaceSecPerKm: activityType == CardioActivityType.running
          ? maxPace
          : null,
      calories: calories,
      title: title,
      notes: notes,
      rpe: rpe,
      feelingRating: feelingRating,
      status: 'completed',
      polylineSummary: polyline,
      createdAt: now,
      updatedAt: now,
      bestSplitPaceSecPerKm: efforts.bestSplitPaceSecPerKm,
      bestEffort1kSec: efforts.bestEffort1kSec,
      bestEffort3kSec: efforts.bestEffort3kSec,
      bestEffort5kSec: efforts.bestEffort5kSec,
      bestEffort10kSec: efforts.bestEffort10kSec,
      bestEffortHalfSec: efforts.bestEffortHalfSec,
      bestEffortMarathonSec: efforts.bestEffortMarathonSec,
      effortsComputed: true,
    );

    return (activity: activity, points: points);
  }

  Future<double> _latestBodyWeightKg() async {
    try {
      final latest = await BodyMeasurementRepository().getLatestWeightKg();
      return latest ?? 70;
    } catch (_) {
      // Lightweight repository tests and partially recovered databases may not
      // have the optional body-measurement table yet.
      return 70;
    }
  }

  static int _estimateCalories({
    required CardioActivityType activityType,
    required double distanceMeters,
    required int durationSeconds,
    required double bodyWeightKg,
  }) {
    if (activityType == CardioActivityType.stationaryBike) {
      // Moderate stationary cycling is approximately 7 MET. This is an
      // estimate until heart-rate or machine power data is available.
      final minutes = durationSeconds / 60.0;
      return (7.0 * 3.5 * bodyWeightKg / 200 * minutes).round().clamp(
        0,
        100000,
      );
    }
    // Running costs approximately 1 kcal per kg per kilometer.
    final km = distanceMeters / 1000.0;
    return (km * bodyWeightKg).round().clamp(0, 100000);
  }

  static double? _avgPace(double distanceMeters, int movingTimeSeconds) {
    if (distanceMeters < 1 || movingTimeSeconds <= 0) return null;
    return movingTimeSeconds / (distanceMeters / 1000.0);
  }

  static String? _buildPolylineSummary(List<Map<String, dynamic>> points) {
    if (points.isEmpty) return null;
    final step = points.length <= 100 ? 1 : (points.length / 100).ceil();
    final buffer = StringBuffer();
    for (var i = 0; i < points.length; i += step) {
      final lat = (points[i]['lat'] as num?)?.toDouble();
      final lng = (points[i]['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (buffer.isNotEmpty) buffer.write(';');
      buffer.write('${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}');
    }
    return buffer.isEmpty ? null : buffer.toString();
  }
}

class _RouteSummary {
  final double? elevationGain;
  final double? elevationLoss;
  final double? minimumAltitude;
  final double? maximumAltitude;
  final double? meanAccuracy;
  final double? goodAccuracyFraction;

  const _RouteSummary({
    this.elevationGain,
    this.elevationLoss,
    this.minimumAltitude,
    this.maximumAltitude,
    this.meanAccuracy,
    this.goodAccuracyFraction,
  });

  factory _RouteSummary.fromPoints(List<RunTrackPoint> points) {
    final altitudes = points
        .map((point) => point.altitude)
        .whereType<double>()
        .toList();
    var gain = 0.0;
    var loss = 0.0;
    for (var index = 1; index < altitudes.length; index++) {
      final delta = altitudes[index] - altitudes[index - 1];
      // Ignore sub-metre sensor noise while retaining meaningful terrain.
      if (delta >= 1) gain += delta;
      if (delta <= -1) loss += -delta;
    }
    final accuracies = points
        .map((point) => point.accuracy)
        .whereType<double>()
        .where((value) => value.isFinite && value >= 0)
        .toList();
    return _RouteSummary(
      elevationGain: altitudes.isEmpty ? null : gain,
      elevationLoss: altitudes.isEmpty ? null : loss,
      minimumAltitude: altitudes.isEmpty
          ? null
          : altitudes.reduce((a, b) => a < b ? a : b),
      maximumAltitude: altitudes.isEmpty
          ? null
          : altitudes.reduce((a, b) => a > b ? a : b),
      meanAccuracy: accuracies.isEmpty
          ? null
          : accuracies.reduce((a, b) => a + b) / accuracies.length,
      goodAccuracyFraction: accuracies.isEmpty
          ? null
          : accuracies.where((value) => value <= 20).length / accuracies.length,
    );
  }
}
