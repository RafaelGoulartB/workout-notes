import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'base_repository.dart';

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
      'date': (date ?? DateTime.now()).toIso8601String().substring(0, 10),
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
        'date': m['date'] ?? DateTime.now().toIso8601String().substring(0, 10),
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

  /// Returns the previous measurement for a given type (before the latest).
  Future<Map<String, dynamic>?> getPreviousBodyMeasurement(
    String type, {
    String? beforeDate,
  }) async {
    final db = await this.db;
    return db
        .rawQuery(
          'SELECT * FROM body_measurements WHERE type = ? ORDER BY date DESC, created_at DESC LIMIT 1',
          [type],
        )
        .then((r) => r.isEmpty ? null : r.first);
  }

  /// Returns body measurements grouped by month for trend analysis.
  Future<List<Map<String, dynamic>>> getBodyMeasurementsTrend(
    String type, {
    int months = 6,
  }) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: months * 30))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery(
      '''
      SELECT date, value, unit, comment, time_of_day, is_fasted,
        (SELECT value FROM body_measurements bm2
         WHERE bm2.type = bm.type AND bm2.date < bm.date
         ORDER BY bm2.date DESC LIMIT 1) as prev_value
      FROM body_measurements bm
      WHERE type = ? AND date >= ?
      ORDER BY date ASC
    ''',
      [type, start],
    );
  }

  /// Returns all measurements for a specific date.
  Future<List<Map<String, dynamic>>> getBodyMeasurementsByDate(
    String date,
  ) async {
    final db = await this.db;
    return db.query(
      'body_measurements',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'type ASC',
    );
  }

  /// Returns body composition data (weight + body fat) for trend analysis.
  Future<List<Map<String, dynamic>>> getBodyCompositionTrend({
    int months = 6,
  }) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: months * 30))
        .toIso8601String()
        .substring(0, 10);
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

  /// Returns measurement count per month for consistency tracking.
  Future<Map<String, int>> getBodyMeasurementFrequency({int months = 6}) async {
    final db = await this.db;
    final start = DateTime.now()
        .subtract(Duration(days: months * 30))
        .toIso8601String()
        .substring(0, 10);
    final rows = await db.rawQuery(
      '''
      SELECT date, COUNT(*) as count
      FROM body_measurements
      WHERE date >= ?
      GROUP BY date
      ORDER BY date ASC
    ''',
      [start],
    );
    final Map<String, int> result = {};
    for (final row in rows) {
      result[row['date'] as String] = row['count'] as int;
    }
    return result;
  }

  /// Returns all measurements for a given type with their photo paths.
  Future<List<Map<String, dynamic>>> getBodyMeasurementsWithPhotos(
    String type, {
    int limit = 50,
  }) async {
    final db = await this.db;
    return db.rawQuery(
      'SELECT * FROM body_measurements WHERE type = ? AND photos_paths IS NOT NULL ORDER BY date DESC LIMIT ?',
      [type, limit],
    );
  }
}
