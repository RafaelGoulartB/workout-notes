import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/repositories/base_repository.dart';

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
    await database.delete('run_activities', where: 'id = ?', whereArgs: [id]);
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
    );

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
