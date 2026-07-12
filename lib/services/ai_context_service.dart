import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/ai_provider.dart';
import '../repositories/goal_repository.dart';

/// Builds a JSON snapshot of the user's data to inject into the system prompt.
/// Read-only, in-memory. Same role as `ai_context_service.dart` in `gastos`.
class AiContextService {
  final DatabaseHelper db;
  final GoalRepository goalRepo;

  AiContextService({DatabaseHelper? db, GoalRepository? goalRepo})
    : db = db ?? DatabaseHelper.instance,
      goalRepo = goalRepo ?? GoalRepository();

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
    final monthlyReport = await _safeMap(() async {
      try {
        return await db.getMonthlyReport(now.year, now.month);
      } catch (_) {
        return <String, dynamic>{};
      }
    });
    final last4Weeks = await _safeMap(() => db.getWeeklyVolume(weeks: 4));
    final byCategory = await _safeList(() => db.getVolumeByCategory());
    final topEx = await _safeList(() => db.getTopExercisesByVolume(limit: 8));
    final activeGoals = await _safeList(_loadActiveGoalsSummary);
    final bodyTrend = await _safeList(
      () => db.getBodyCompositionTrend(months: 1),
    );

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
      'thisMonth': monthlyReport,
    };

    if (mode == AiContextMode.standard || mode == AiContextMode.full) {
      summary['last4WeeksVolume'] = last4Weeks;
      summary['topExercisesByVolume'] = topEx;
      summary['activeGoals'] = activeGoals;
    }

    if (mode == AiContextMode.full) {
      summary['categoryDistributionPct'] = byCategory;
      summary['bodyTrend30d'] = bodyTrend;
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

  Future<List<Map<String, dynamic>>> _loadActiveGoalsSummary() async {
    final goals = await goalRepo.getAll(activeOnly: true);
    final out = <Map<String, dynamic>>[];
    for (final g in goals) {
      try {
        final progress = await goalRepo.getProgress(g);
        out.add({
          'id': g.id,
          'title': g.title,
          'scope': g.scope.value,
          'metric': g.metric.value,
          'period': g.period.value,
          'currentValue': progress.currentValue,
          'targetValue': progress.targetValue,
          'progressPct': progress.percent,
          'isComplete': progress.isComplete,
          'daysRemaining': progress.daysRemaining,
        });
      } catch (_) {
        out.add({
          'id': g.id,
          'title': g.title,
          'scope': g.scope.value,
          'metric': g.metric.value,
          'period': g.period.value,
          'targetValue': g.targetValue,
        });
      }
    }
    return out;
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

  Future<List<Map<String, dynamic>>> _safeList(
    Future<List<Map<String, dynamic>>> Function() f,
  ) async {
    try {
      return await f();
    } catch (_) {
      return const [];
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
