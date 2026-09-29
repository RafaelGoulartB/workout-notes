import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/repositories/base_repository.dart';

/// Shoes / gear mileage and manual laps (schema v53).
///
/// Every query guards on the tables existing so older test schemas and
/// partially migrated databases degrade to "no gear" instead of throwing.
class RunGearRepository extends BaseRepository {
  static const _uuid = Uuid();

  Future<bool> _hasGear(DatabaseExecutor database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'run_gear'",
    );
    if (rows.isEmpty) return false;
    final columns = await database.rawQuery(
      'PRAGMA table_info(run_activities)',
    );
    return columns.any((c) => c['name'] == 'gear_id');
  }

  Future<bool> _hasLaps(DatabaseExecutor database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'run_laps'",
    );
    return rows.isNotEmpty;
  }

  Future<List<RunGearUsage>> listGearUsage({bool includeRetired = true}) async {
    final database = await db;
    if (!await _hasGear(database)) return const [];
    final rows = await database.rawQuery(
      '''
      SELECT g.*,
        COALESCE(SUM(a.distance_meters), 0) AS logged_distance_meters,
        COUNT(a.id) AS run_count,
        MAX(a.started_at) AS last_used_at
      FROM run_gear g
      LEFT JOIN run_activities a
        ON a.gear_id = g.id AND a.status = 'completed'
        AND a.activity_type IN (?, ?)
      ${includeRetired ? '' : 'WHERE g.retired_at IS NULL'}
      GROUP BY g.id
      ORDER BY (g.retired_at IS NOT NULL), g.is_default DESC, g.created_at DESC
      ''',
      [
        CardioActivityType.running.databaseValue,
        CardioActivityType.treadmill.databaseValue,
      ],
    );
    return rows
        .map(
          (row) => RunGearUsage(
            gear: RunGear.fromMap(row),
            loggedDistanceMeters:
                (row['logged_distance_meters'] as num?)?.toDouble() ?? 0,
            runCount: (row['run_count'] as num?)?.toInt() ?? 0,
            lastUsedAt: DateTime.tryParse(row['last_used_at'] as String? ?? ''),
          ),
        )
        .toList();
  }

  Future<RunGearUsage?> getUsage(String gearId) async {
    final all = await listGearUsage();
    for (final usage in all) {
      if (usage.gear.id == gearId) return usage;
    }
    return null;
  }

  /// The gear pre-selected for new runs, if any active one is marked default.
  Future<RunGear?> getDefaultGear() async {
    final database = await db;
    if (!await _hasGear(database)) return null;
    final rows = await database.query(
      'run_gear',
      where: 'is_default = 1 AND retired_at IS NULL',
      limit: 1,
    );
    return rows.isEmpty ? null : RunGear.fromMap(rows.first);
  }

  Future<RunGear> saveGear({
    String? id,
    required String name,
    String? brand,
    String? notes,
    double initialDistanceMeters = 0,
    double retireDistanceMeters = RunGear.defaultRetireDistanceMeters,
    bool isDefault = false,
  }) async {
    final database = await db;
    final now = DateTime.now();
    return database.transaction((txn) async {
      if (isDefault) {
        await txn.update('run_gear', {'is_default': 0});
      }
      final existing = id == null
          ? const <Map<String, Object?>>[]
          : await txn.query('run_gear', where: 'id = ?', whereArgs: [id]);
      final gear = RunGear(
        id: id ?? _uuid.v4(),
        name: name.trim(),
        brand: brand?.trim().isEmpty ?? true ? null : brand!.trim(),
        notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
        initialDistanceMeters: initialDistanceMeters,
        retireDistanceMeters: retireDistanceMeters,
        isDefault: isDefault,
        retiredAt: existing.isEmpty
            ? null
            : DateTime.tryParse(existing.first['retired_at'] as String? ?? ''),
        createdAt: existing.isEmpty
            ? now
            : DateTime.tryParse(
                    existing.first['created_at'] as String? ?? '',
                  ) ??
                  now,
        updatedAt: now,
      );
      await txn.insert(
        'run_gear',
        gear.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return gear;
    });
  }

  Future<void> setRetired(String gearId, bool retired) async {
    final database = await db;
    await database.update(
      'run_gear',
      {
        'retired_at': retired ? DateTime.now().toIso8601String() : null,
        if (retired) 'is_default': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [gearId],
    );
  }

  /// Deletes the gear and detaches it from its activities.
  Future<void> deleteGear(String gearId) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
        'run_activities',
        {'gear_id': null},
        where: 'gear_id = ?',
        whereArgs: [gearId],
      );
      await txn.delete('run_gear', where: 'id = ?', whereArgs: [gearId]);
    });
  }

  Future<void> setActivityGear(String activityId, String? gearId) async {
    final database = await db;
    if (!await _hasGear(database)) return;
    await database.update(
      'run_activities',
      {'gear_id': gearId},
      where: 'id = ?',
      whereArgs: [activityId],
    );
  }

  Future<List<RunLap>> getLaps(String activityId) async {
    final database = await db;
    if (!await _hasLaps(database)) return const [];
    final rows = await database.query(
      'run_laps',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'lap_index ASC',
    );
    return rows.map(RunLap.fromMap).toList();
  }

  /// Replaces the laps of [activityId]. Accepts a transaction so the
  /// activity import can write laps atomically with the activity row.
  Future<void> replaceLaps(
    String activityId,
    List<RunLap> laps, {
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? await db;
    if (!await _hasLaps(database)) return;
    await database.delete(
      'run_laps',
      where: 'activity_id = ?',
      whereArgs: [activityId],
    );
    for (final lap in laps) {
      await database.insert(
        'run_laps',
        lap.toMap(activityId),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}
