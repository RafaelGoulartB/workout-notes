import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/sleep_entry.dart';
import 'base_repository.dart';

/// Persistence and dashboard queries for nightly sleep records.
class SleepRepository extends BaseRepository {
  Future<SleepEntry?> getByDate(DateTime date) async {
    final rows = await _queryRange(date, date);
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }

  Future<List<SleepEntry>> getEntries({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final rows = await _queryRange(from, to, limit: limit);
    return rows.map(SleepEntry.fromMap).toList();
  }

  Future<SleepEntry?> getLatest() async {
    final rows = await (await db).query(
      'sleep_entries',
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }

  /// Inserts or replaces the single record associated with [entry.date].
  Future<void> save(SleepEntry entry) async {
    _validate(entry);
    await (await db).insert(
      'sleep_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> add({
    required DateTime date,
    required int sleepMinutes,
    int? actualSleepMinutes,
    int? bedtimeMinutes,
    int? wakeTimeMinutes,
    String? comment,
  }) async {
    await save(
      SleepEntry(
        id: const Uuid().v4(),
        date: _dateOnly(date),
        sleepMinutes: sleepMinutes,
        actualSleepMinutes: actualSleepMinutes,
        bedtimeMinutes: bedtimeMinutes,
        wakeTimeMinutes: wakeTimeMinutes,
        comment: _cleanComment(comment),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> delete(String id) async {
    await (await db).delete('sleep_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<SleepDashboardStats> getDashboardStats({
    DateTime? referenceDate,
  }) async {
    final end = _dateOnly(referenceDate ?? DateTime.now());
    final entries7 = await getEntries(
      from: end.subtract(const Duration(days: 6)),
      to: end,
    );
    final entries30 = await getEntries(
      from: end.subtract(const Duration(days: 29)),
      to: end,
    );

    return SleepDashboardStats(
      latest: await getLatest(),
      average7Days: _average(entries7.map((e) => e.sleepMinutes)),
      average30Days: _average(entries30.map((e) => e.sleepMinutes)),
      actualAverage7Days: _average(
        entries7
            .where((e) => e.actualSleepMinutes != null)
            .map((e) => e.actualSleepMinutes!),
      ),
      actualAverage30Days: _average(
        entries30
            .where((e) => e.actualSleepMinutes != null)
            .map((e) => e.actualSleepMinutes!),
      ),
      minimum30Days: _minimum(entries30.map((e) => e.sleepMinutes)),
      maximum30Days: _maximum(entries30.map((e) => e.sleepMinutes)),
      recordedDays7Days: entries7.length,
      recordedDays30Days: entries30.length,
      efficiency7Days: _average(
        entries7.where((e) => e.efficiency != null).map((e) => e.efficiency!),
      ),
      efficiency30Days: _average(
        entries30.where((e) => e.efficiency != null).map((e) => e.efficiency!),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _queryRange(
    DateTime? from,
    DateTime? to, {
    int? limit,
  }) async {
    final database = await db;
    final where = <String>[];
    final args = <dynamic>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(_dateString(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(_dateString(to));
    }
    return database.query(
      'sleep_entries',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
  }

  static void _validate(SleepEntry entry) {
    if (entry.sleepMinutes <= 0 || entry.sleepMinutes > 24 * 60) {
      throw ArgumentError.value(entry.sleepMinutes, 'sleepMinutes');
    }
    final actual = entry.actualSleepMinutes;
    if (actual != null && (actual <= 0 || actual > entry.sleepMinutes)) {
      throw ArgumentError.value(actual, 'actualSleepMinutes');
    }
    for (final value in [entry.bedtimeMinutes, entry.wakeTimeMinutes]) {
      if (value != null && (value < 0 || value >= 24 * 60)) {
        throw ArgumentError.value(value, 'timeMinutes');
      }
    }
  }

  static double? _average(Iterable<num> values) {
    final list = values.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b).toDouble() / list.length;
  }

  static int? _minimum(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a < b ? a : b);
  }

  static int? _maximum(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a > b ? a : b);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      _dateOnly(value).toIso8601String().substring(0, 10);

  static String? _cleanComment(String? comment) {
    final value = comment?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}
