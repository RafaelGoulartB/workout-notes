import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only goal queries for the AI Coach.
class AiGoalToolService {
  final DatabaseHelper db;
  final GoalRepository goals;

  AiGoalToolService({DatabaseHelper? db, GoalRepository? goals})
    : db = db ?? DatabaseHelper.instance,
      goals = goals ?? (db ?? DatabaseHelper.instance).goalRepo;

  /// Goals with their progress in the current period. [historyPeriods] > 0
  /// adds the results of that many past periods per goal (newest first).
  ///
  /// Values are in the goal's unit: `kg` of volume, `days`, `s` of time, and
  /// distance in the user's distance unit setting (`km` or `mi`).
  Future<Map<String, dynamic>> listGoals({
    String? scope,
    String? metric,
    bool activeOnly = true,
    int historyPeriods = 0,
  }) async {
    final all = await goals.getAll(activeOnly: activeOnly);
    final selected = [
      for (final goal in all)
        if ((scope == null || goal.scope.value == scope) &&
            (metric == null || goal.metric.value == metric))
          goal,
    ].take(20).toList();
    final distanceUnit = await db.settingsRepo.getIsDistanceKm() ? 'km' : 'mi';
    final progress = await goals.getProgressForGoals(selected);
    final rows = <Map<String, dynamic>>[];
    for (final goal in selected) {
      final current = progress[goal.id];
      final unit = switch (goal.metric) {
        GoalMetric.volume => 'kg',
        GoalMetric.days => 'days',
        GoalMetric.distance => distanceUnit,
        GoalMetric.time => 's',
      };
      List<Map<String, dynamic>>? history;
      if (historyPeriods > 0) {
        final (_, past) = await goals.getProgressWithHistory(
          goal,
          historyCount: historyPeriods,
        );
        history = [
          for (final result in past)
            {
              'start': dateKey(result.start),
              'end': dateKey(result.end),
              'value': result.value,
              'achieved': result.wasCompleted,
            },
        ];
      }
      rows.add({
        'id': goal.id,
        'title': goal.title,
        'scope': goal.scope.value,
        'metric': goal.metric.value,
        'period': goal.period.value,
        'unit': unit,
        'target': goal.targetValue,
        'current': current?.currentValue,
        'progress_pct': current == null || goal.targetValue <= 0
            ? null
            : current.currentValue / goal.targetValue * 100,
        'complete': current?.isComplete,
        'period_start': current == null ? null : dateKey(current.periodStart),
        'period_end': current == null ? null : dateKey(current.periodEnd),
        'days_remaining': current?.daysRemaining,
        'active': goal.isActive ? null : false,
        'history': history,
      });
    }
    return {
      'applied': {
        'scope': scope,
        'metric': metric,
        'active_only': activeOnly,
        'history_periods': historyPeriods > 0 ? historyPeriods : null,
      },
      'goals': rows,
    };
  }
}
