import '../database/database_helper.dart';
import '../models/ai_provider.dart';

/// Builds a JSON snapshot of the user's data to inject into the system prompt.
/// Read-only, in-memory. Same role as `ai_context_service.dart` in `gastos`.
class AiContextService {
  final DatabaseHelper db;

  AiContextService({DatabaseHelper? db}) : db = db ?? DatabaseHelper.instance;

  static const Duration _kTtl = Duration(seconds: 60);

  _AiContextCache? _cache;

  Future<Map<String, dynamic>> build({required AiContextMode mode}) async {
    final now = DateTime.now();
    if (_cache != null &&
        now.difference(_cache!.builtAt) < _kTtl &&
        _cache!.mode == mode) {
      return _cache!.json;
    }
    final json = await _buildFresh(mode: mode, now: now);
    _cache = _AiContextCache(builtAt: now, mode: mode, json: json);
    return json;
  }

  void invalidate() {
    _cache = null;
  }

  Future<Map<String, dynamic>> _buildFresh({
    required AiContextMode mode,
    required DateTime now,
  }) async {
    final parts = await Future.wait<Map<String, dynamic>>([
      _safeMap(() => db.getWorkoutOverviewStats()),
      _loadBaseCounts(),
      if (mode != AiContextMode.minimal) _loadDataAvailability(now),
    ]);
    final overview = parts[0];
    final counts = parts[1];
    final availability = mode == AiContextMode.minimal
        ? const <String, dynamic>{}
        : parts[2];

    final summary = <String, dynamic>{
      'totals': {
        'workouts': (overview['total_workouts'] as int?) ?? 0,
        'sets': (overview['total_sets'] as int?) ?? 0,
        'totalVolume': (overview['total_volume'] as num?)?.toDouble() ?? 0.0,
        'exercises': counts['exercises'] ?? 0,
        'routines': counts['routines'] ?? 0,
        'bodyMeasurements': counts['bodyMeasurements'] ?? 0,
        'activeGoals': counts['activeGoals'] ?? 0,
      },
      'currentStreakDays': (overview['current_streak'] as int?) ?? 0,
    };

    if (mode == AiContextMode.standard || mode == AiContextMode.full) {
      summary['dataAvailability'] = availability;
    }

    if (mode == AiContextMode.full) {
      summary['availableDomains'] = const [
        'workouts',
        'exercises',
        'routines',
        'goals',
        'body_measurements',
        'sleep',
        'nutrition',
        'recovery_analytics',
      ];
    }

    return {
      'metadata': {
        'app': 'workout_notes',
        'locale': 'pt_BR',
        'generated_at': now.toIso8601String(),
        'mode': mode.storageKey,
      },
      'summary': summary,
    };
  }

  Future<Map<String, dynamic>> _loadDataAvailability(DateTime now) async {
    try {
      final rawDb = await db.database;
      final start7 = now
          .subtract(const Duration(days: 6))
          .toIso8601String()
          .substring(0, 10);
      final start30 = now
          .subtract(const Duration(days: 29))
          .toIso8601String()
          .substring(0, 10);
      final rows = await rawDb.rawQuery(
        '''
        SELECT
          (SELECT COUNT(*) FROM sleep_entries WHERE date >= ?) AS sleep_7d,
          (SELECT COUNT(DISTINCT ml.date) FROM meal_logs ml
            JOIN meal_log_items mli ON mli.meal_log_id = ml.id
            WHERE ml.date >= ?) AS nutrition_7d,
          (SELECT COUNT(*) FROM workouts WHERE date >= ?) AS workouts_30d,
          (SELECT COUNT(*) FROM body_measurements
            WHERE type = ? AND date >= ?) AS weight_30d
      ''',
        [start7, start7, start30, 'weight', start30],
      );
      final row = rows.first;
      return {
        'sleepNights7d': (row['sleep_7d'] as num?)?.toInt() ?? 0,
        'nutritionDays7d': (row['nutrition_7d'] as num?)?.toInt() ?? 0,
        'workouts30d': (row['workouts_30d'] as num?)?.toInt() ?? 0,
        'weightMeasurements30d': (row['weight_30d'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, int>> _loadBaseCounts() async {
    try {
      final rawDb = await db.database;
      final rows = await rawDb.rawQuery('''
        SELECT
          (SELECT COUNT(*) FROM exercises) AS exercises,
          (SELECT COUNT(*) FROM routines) AS routines,
          (SELECT COUNT(*) FROM body_measurements) AS body_measurements,
          (SELECT COUNT(*) FROM user_goals WHERE is_active = 1) AS active_goals
      ''');
      final row = rows.first;
      return {
        'exercises': (row['exercises'] as num?)?.toInt() ?? 0,
        'routines': (row['routines'] as num?)?.toInt() ?? 0,
        'bodyMeasurements': (row['body_measurements'] as num?)?.toInt() ?? 0,
        'activeGoals': (row['active_goals'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, dynamic>> _safeMap(
    Future<Map<String, dynamic>> Function() f,
  ) async {
    try {
      return await f();
    } catch (_) {
      return const {};
    }
  }
}

class _AiContextCache {
  final DateTime builtAt;
  final AiContextMode mode;
  final Map<String, dynamic> json;
  _AiContextCache({
    required this.builtAt,
    required this.mode,
    required this.json,
  });
}
