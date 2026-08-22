import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/run_effort_analytics.dart';

class RunRepository extends BaseRepository {
  static const _uuid = Uuid();

  Future<List<RunActivity>> listActivities({int limit = 50, int offset = 0}) async {
    final database = await db;
    final rows = await database.query(
      'run_activities',
      where: "status = ?",
      whereArgs: ['completed'],
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
    final rows = await database.query(
      'run_track_points',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'seq ASC',
    );
    return rows.map(RunTrackPoint.fromMap).toList();
  }

  Future<void> updateActivityMeta({
    required String id,
    String? title,
    String? notes,
  }) async {
    final database = await db;
    await database.update(
      'run_activities',
      {
        'title': ?title,
        'notes': ?notes,
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
  Future<Map<String, dynamic>> getMonthlyRunSummary(DateTime month) async {
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
      ''',
      [start.toIso8601String(), end.toIso8601String()],
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
      where: "status = ? AND IFNULL(efforts_computed, 0) = 0",
      whereArgs: ['completed'],
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
    final rawPoints = (spool['points'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final id = rawActivity['id'] as String? ?? _uuid.v4();
    final existing = await getActivity(id);
    if (existing != null) return existing;

    final now = DateTime.now();
    final startedAt = DateTime.tryParse(rawActivity['started_at'] as String? ?? '') ??
        now;
    final endedAt = DateTime.tryParse(rawActivity['ended_at'] as String? ?? '');
    final status = rawActivity['status'] as String? ?? 'completed';
    if (status == 'discarded') {
      throw StateError('discarded_spool');
    }

    final distanceMeters =
        (rawActivity['distance_meters'] as num?)?.toDouble() ?? 0;
    final durationSeconds =
        (rawActivity['duration_seconds'] as num?)?.toInt() ?? 0;
    final movingTimeSeconds =
        (rawActivity['moving_time_seconds'] as num?)?.toInt() ?? durationSeconds;
    final avgPace = (rawActivity['avg_pace_sec_per_km'] as num?)?.toDouble();
    final maxPace = (rawActivity['max_pace_sec_per_km'] as num?)?.toDouble();
    final calories = (rawActivity['calories'] as num?)?.toInt() ??
        _estimateCalories(distanceMeters);
    final title = rawActivity['title'] as String?;
    final notes = rawActivity['notes'] as String?;
    final polyline = rawActivity['polyline_summary'] as String? ??
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
          recordedAt: DateTime.tryParse(row['recorded_at'] as String? ?? '') ??
              startedAt.add(Duration(seconds: i)),
        ),
      );
    }

    final efforts = RunEffortAnalytics.fromTrackPoints(points);

    final activity = RunActivity(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? now,
      durationSeconds: durationSeconds,
      movingTimeSeconds: movingTimeSeconds,
      distanceMeters: distanceMeters,
      avgPaceSecPerKm: avgPace ?? _avgPace(distanceMeters, movingTimeSeconds),
      maxPaceSecPerKm: maxPace,
      calories: calories,
      title: title,
      notes: notes,
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

    final database = await db;
    await database.transaction((txn) async {
      await txn.insert('run_activities', activity.toMap());
      for (final point in points) {
        await txn.insert('run_track_points', point.toMap());
      }
    });

    return activity;
  }

  static int _estimateCalories(double distanceMeters) {
    // ~1 kcal per kg per km; assume 70 kg default body weight.
    final km = distanceMeters / 1000.0;
    return (km * 70).round().clamp(0, 100000);
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
