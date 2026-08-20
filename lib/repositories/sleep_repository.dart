import 'dart:math' as math;

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
    int? offset,
  }) async {
    final rows = await _queryRange(from, to, limit: limit, offset: offset);
    return rows.map(SleepEntry.fromMap).toList();
  }

  Future<int> getEntryCount() async {
    final result = await (await db).rawQuery(
      'SELECT COUNT(*) AS count FROM sleep_entries',
    );
    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<SleepEntry?> getLatest() async {
    final rows = await (await db).query(
      'sleep_entries',
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
  }

  Future<SleepEntry?> getById(String id) async {
    final rows = await (await db).query(
      'sleep_entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SleepEntry.fromMap(rows.first);
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
    final regularityEntries = entries7
        .where(
          (entry) =>
              entry.bedtimeMinutes != null && entry.wakeTimeMinutes != null,
        )
        .toList();

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
      regularity7Days: _regularityScore(regularityEntries),
      regularitySampleCount: regularityEntries.length,
    );
  }

  Future<List<Map<String, dynamic>>> _queryRange(
    DateTime? from,
    DateTime? to, {
    int? limit,
    int? offset,
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
      offset: offset,
    );
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

  /// Returns a non-clinical schedule consistency score for the last seven days.
  ///
  /// Bedtime and wake-up values are circular clock values, so 23:50 and 00:10
  /// remain close. The average deviation of both clock times is mapped to a
  /// 0-100 score, with deviations of three hours or more scoring zero.
  static double? _regularityScore(List<SleepEntry> entries) {
    if (entries.length < 2) return null;
    final bedtimes = entries.map((entry) => entry.bedtimeMinutes!).toList();
    final wakeTimes = entries.map((entry) => entry.wakeTimeMinutes!).toList();
    final bedtimeCenter = _circularCenter(bedtimes);
    final wakeTimeCenter = _circularCenter(wakeTimes);
    final bedtimeDeviation = _average(
      bedtimes.map((value) => _circularDistance(value, bedtimeCenter)),
    )!;
    final wakeTimeDeviation = _average(
      wakeTimes.map((value) => _circularDistance(value, wakeTimeCenter)),
    )!;
    final combinedDeviation = (bedtimeDeviation + wakeTimeDeviation) / 2;
    return (100 * (1 - math.min(combinedDeviation, 180) / 180)).clamp(0, 100);
  }

  static int _circularCenter(List<int> values) {
    var sinSum = 0.0;
    var cosSum = 0.0;
    for (final value in values) {
      final angle = value / 1440 * 2 * math.pi;
      sinSum += math.sin(angle);
      cosSum += math.cos(angle);
    }
    var angle = math.atan2(sinSum, cosSum);
    if (angle < 0) angle += 2 * math.pi;
    return (angle / (2 * math.pi) * 1440).round() % 1440;
  }

  static int _circularDistance(int first, int second) {
    final direct = (first - second).abs();
    return math.min(direct, 1440 - direct);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      _dateOnly(value).toIso8601String().substring(0, 10);
}
