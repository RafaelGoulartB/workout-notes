import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Repository for body measurements CRUD and analytics operations.
class BodyMeasurementRepository extends BaseRepository {
  Future<void> addBodyMeasurement(
    String type,
    double value,
    String unit, {
    double? secondaryValue,
    DateTime? date,
    String? comment,
    String? timeOfDay,
    bool isFasted = false,
    List<String>? photosPaths,
    String? side,
  }) async {
    final db = await this.db;
    await db.insert('body_measurements', {
      'id': const Uuid().v4(),
      'type': type,
      'value': value,
      'secondary_value': secondaryValue,
      'unit': unit,
      'date': dateKey(date ?? DateTime.now()),
      'comment': comment,
      'time_of_day': timeOfDay,
      'is_fasted': isFasted ? 1 : 0,
      'photos_paths': photosPaths != null && photosPaths.isNotEmpty
          ? jsonEncode(photosPaths)
          : null,
      'side': side,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> addBodyMeasurementsBatch(
    List<Map<String, dynamic>> measurements,
  ) async {
    final db = await this.db;
    for (final m in measurements) {
      await db.insert('body_measurements', {
        'id': const Uuid().v4(),
        'type': m['type'],
        'value': m['value'],
        'secondary_value': m['secondary_value'],
        'unit': m['unit'],
        'date': m['date'] ?? dateKey(DateTime.now()),
        'comment': m['comment'],
        'time_of_day': m['time_of_day'],
        'is_fasted': (m['is_fasted'] as bool?) == true ? 1 : 0,
        'photos_paths': m['photos_paths'] != null
            ? jsonEncode(m['photos_paths'])
            : null,
        'side': m['side'],
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Inserts [measurements] on [executor] (so callers can fold them into their
  /// own transaction). Every row must carry its `id`: callers that need
  /// idempotent writes derive it from what they are applying, and a repeated
  /// insert then fails on the primary key instead of duplicating.
  Future<void> insertMeasurementsIn(
    DatabaseExecutor executor,
    List<Map<String, dynamic>> measurements,
  ) async {
    final createdAt = DateTime.now().toIso8601String();
    for (final m in measurements) {
      await executor.insert('body_measurements', {
        'id': m['id'],
        'type': m['type'],
        'value': m['value'],
        'secondary_value': m['secondary_value'],
        'unit': m['unit'],
        'date': m['date'] ?? dateKey(DateTime.now()),
        'comment': m['comment'],
        'time_of_day': m['time_of_day'],
        'is_fasted': (m['is_fasted'] as bool?) == true ? 1 : 0,
        'side': m['side'],
        'created_at': createdAt,
      });
    }
  }

  /// The most recent measurement of [type] (and [side], when given) on or
  /// before [onOrBefore] (`yyyy-MM-dd`), or null.
  Future<Map<String, dynamic>?> latestMeasurementOf(
    DatabaseExecutor executor, {
    required String type,
    String? side,
    String? onOrBefore,
  }) async {
    final rows = await executor.query(
      'body_measurements',
      where:
          'type = ?${side == null ? '' : ' AND side = ?'}'
          '${onOrBefore == null ? '' : ' AND date <= ?'}',
      whereArgs: [type, ?side, ?onOrBefore],
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Measurements of [type] already logged on [date] (`yyyy-MM-dd`).
  Future<List<Map<String, dynamic>>> measurementsOn(
    DatabaseExecutor executor, {
    required String type,
    required String date,
  }) => executor.query(
    'body_measurements',
    where: 'type = ? AND date = ?',
    whereArgs: [type, date],
    orderBy: 'created_at ASC',
  );

  Future<List<Map<String, dynamic>>> getBodyMeasurements({
    String? type,
    int? limit,
  }) async {
    final db = await this.db;
    var where = '';
    var args = <dynamic>[];
    if (type != null) {
      where = 'WHERE type = ?';
      args = [type];
    }
    var query = 'SELECT * FROM body_measurements $where ORDER BY date DESC';
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    return db.rawQuery(query, args);
  }

  /// Returns the most recent body weight normalized to kilograms.
  Future<double?> getLatestWeightKg() async {
    final db = await this.db;
    final rows = await db.query(
      'body_measurements',
      where: 'type = ?',
      whereArgs: ['weight'],
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final value = (rows.first['value'] as num?)?.toDouble();
    if (value == null || value <= 0) return null;

    final unit = (rows.first['unit'] as String? ?? 'kg').toLowerCase();
    if (unit == 'lb' || unit == 'lbs' || unit == 'pound' || unit == 'pounds') {
      return value * 0.45359237;
    }
    if (unit == 'kg' || unit.isEmpty) return value;
    return null;
  }

  Future<void> deleteBodyMeasurement(String id) async {
    final db = await this.db;
    await db.delete('body_measurements', where: 'id = ?', whereArgs: [id]);
  }

  /// Returns the latest measurement for each type.
  Future<List<Map<String, dynamic>>> getBodyMeasurementsSummary() async {
    final db = await this.db;
    return db.rawQuery('''
      SELECT bm.* FROM body_measurements bm
      INNER JOIN (
        SELECT type, MAX(date || ' ' || created_at) as max_dt
        FROM body_measurements
        GROUP BY type
      ) latest ON bm.type = latest.type
        AND (bm.date || ' ' || bm.created_at) = latest.max_dt
      ORDER BY bm.type
    ''');
  }

  /// Returns body composition data (weight + body fat) for trend analysis.
  Future<List<Map<String, dynamic>>> getBodyCompositionTrend({
    int months = 6,
  }) async {
    final db = await this.db;
    final start = dateKey(DateTime.now().subtract(Duration(days: months * 30)));
    return db.rawQuery(
      '''
      SELECT w.date, w.value as weight,
        (SELECT value FROM body_measurements WHERE type = 'bodyFat' AND date = w.date LIMIT 1) as body_fat,
        (SELECT value FROM body_measurements WHERE type = 'waist' AND date = w.date LIMIT 1) as waist,
        (SELECT value FROM body_measurements WHERE type = 'chest' AND date = w.date LIMIT 1) as chest,
        (SELECT value FROM body_measurements WHERE type = 'hip' AND date = w.date LIMIT 1) as hip
      FROM body_measurements w
      WHERE w.type = 'weight' AND w.date >= ?
      ORDER BY w.date ASC
    ''',
      [start],
    );
  }
}
