import 'package:workout_notes/services/ai_tool_spec.dart';

/// Goal tools.
List<AiToolSpec> goalToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'list_goals',
    description: 'Lista metas (goals) ativas com progresso atual.',
    properties: {
      'scope': {'type': 'string', 'description': 'anaerobic ou aerobic.'},
      'metric': {
        'type': 'string',
        'description': 'volume, days, distance ou time.',
      },
      'is_active': {'type': 'boolean', 'default': true},
    },
    handler: (a) async {
      final scope = a['scope'] as String?;
      final metric = a['metric'] as String?;
      final activeOnly = (a['is_active'] as bool?) ?? true;
      final goals = await d.goalRepo.getAll(activeOnly: activeOnly);
      final filtered = goals.where(
        (g) =>
            (scope == null || g.scope.value == scope) &&
            (metric == null || g.metric.value == metric),
      );
      final out = await Future.wait(
        filtered.map((g) async {
          try {
            final p = await d.goalRepo.getProgress(g);
            return <String, dynamic>{
              'id': g.id,
              'title': g.title,
              'scope': g.scope.value,
              'metric': g.metric.value,
              'period': g.period.value,
              'currentValue': p.currentValue,
              'targetValue': p.targetValue,
              'progressPct': p.percent,
              'isComplete': p.isComplete,
              'daysRemaining': p.daysRemaining,
            };
          } catch (_) {
            return <String, dynamic>{
              'id': g.id,
              'title': g.title,
              'scope': g.scope.value,
              'metric': g.metric.value,
              'period': g.period.value,
              'targetValue': g.targetValue,
            };
          }
        }),
      );
      return aiToolOk({'goals': out});
    },
  ),
  AiToolSpec(
    name: 'get_goal_progress_history',
    description: 'Progresso de uma meta nos últimos N períodos.',
    properties: {
      'goal_id': {'type': 'string'},
      'periods_back': {'type': 'integer', 'default': 6},
    },
    required: ['goal_id'],
    handler: (a) async {
      final id = (a['goal_id'] as String?) ?? (a['goalId'] as String?);
      if (id == null) return aiToolOk({'error': 'goal_id é obrigatório'});
      final periods = a.boundedInt('periods', 6, 1, 12);
      final goal = await d.goalRepo.getById(id);
      if (goal == null) return aiToolOk({'error': 'meta não encontrada'});
      final (current, history) = await d.goalRepo.getProgressWithHistory(
        goal,
        historyCount: periods,
      );
      return aiToolOk({
        'goalId': id,
        'title': goal.title,
        'current': {
          'currentValue': current.currentValue,
          'targetValue': current.targetValue,
          'progressPct': current.percent,
          'isComplete': current.isComplete,
          'daysRemaining': current.daysRemaining,
        },
        'history': history
            .map(
              (r) => {
                'start': r.start.toIso8601String().substring(0, 10),
                'end': r.end.toIso8601String().substring(0, 10),
                'value': r.value,
                'targetValue': r.targetValue,
                'wasCompleted': r.wasCompleted,
              },
            )
            .toList(),
      });
    },
  ),
];
