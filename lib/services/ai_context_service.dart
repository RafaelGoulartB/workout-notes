import 'package:sqflite/sqflite.dart';

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
    final overview = await _safeMap(() => db.getWorkoutOverviewStats());
    final counts = await _loadBaseCounts();
    final availability = await _loadDataAvailability(now);

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
      Future<int> count(String sql, List<Object?> args) async =>
          Sqflite.firstIntValue(await rawDb.rawQuery(sql, args)) ?? 0;
      return {
        'sleepNights7d': await count(
          'SELECT COUNT(*) FROM sleep_entries WHERE date >= ?',
          [start7],
        ),
        'nutritionDays7d': await count(
          'SELECT COUNT(DISTINCT ml.date) FROM meal_logs ml '
          'JOIN meal_log_items mli ON mli.meal_log_id = ml.id '
          'WHERE ml.date >= ?',
          [start7],
        ),
        'workouts30d': await count(
          'SELECT COUNT(*) FROM workouts WHERE date >= ?',
          [start30],
        ),
        'weightMeasurements30d': await count(
          'SELECT COUNT(*) FROM body_measurements '
          'WHERE type = ? AND date >= ?',
          ['weight', start30],
        ),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, int>> _loadBaseCounts() async {
    try {
      final rawDb = await db.database;
      final exercises =
          Sqflite.firstIntValue(
            await rawDb.rawQuery('SELECT COUNT(*) FROM exercises'),
          ) ??
          0;
      final routines =
          Sqflite.firstIntValue(
            await rawDb.rawQuery('SELECT COUNT(*) FROM routines'),
          ) ??
          0;
      final body =
          Sqflite.firstIntValue(
            await rawDb.rawQuery('SELECT COUNT(*) FROM body_measurements'),
          ) ??
          0;
      final goals =
          Sqflite.firstIntValue(
            await rawDb.rawQuery(
              'SELECT COUNT(*) FROM user_goals WHERE is_active = 1',
            ),
          ) ??
          0;
      return {
        'exercises': exercises,
        'routines': routines,
        'bodyMeasurements': body,
        'activeGoals': goals,
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
