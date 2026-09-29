import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';

/// Bulk reads that only the running insights screen needs.
class RunInsightsRepository extends BaseRepository {
  /// Per-kilometre splits of every completed run started at or after [from],
  /// keyed by activity id. Runs whose splits were never stored (treadmill,
  /// older imports) are simply absent; callers fall back to average pace.
  Future<Map<String, List<RunSplitSample>>> splitsSince(DateTime from) async {
    final database = await db;
    final table = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'run_splits'",
    );
    if (table.isEmpty) return const {};
    final rows = await database.rawQuery(
      '''
      SELECT s.activity_id, s.duration_seconds, s.pace_sec_per_km
      FROM run_splits s
      JOIN run_activities a ON a.id = s.activity_id
      WHERE a.status = 'completed' AND a.started_at >= ?
      ORDER BY s.activity_id, s.split_index
      ''',
      [from.toIso8601String()],
    );
    final result = <String, List<RunSplitSample>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['activity_id'] as String, () => [])
          .add(
            RunSplitSample(
              durationSeconds: (row['duration_seconds'] as num?)?.toInt() ?? 0,
              paceSecPerKm: (row['pace_sec_per_km'] as num?)?.toDouble(),
            ),
          );
    }
    return result;
  }
}
