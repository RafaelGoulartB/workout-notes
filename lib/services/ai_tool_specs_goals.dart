import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

const _scopes = ['anaerobic', 'aerobic'];
const _metrics = ['volume', 'days', 'distance', 'time'];

/// Goal tools.
List<AiToolSpec> goalToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'list_goals',
    description:
        'Weekly/monthly goals: unit, target, current value, progress_pct. '
        'history_periods adds past periods per goal.',
    domain: AiToolDomain.goals,
    properties: {
      'scope': AiParam.enumOf(_scopes, 'Strength or cardio.'),
      'metric': AiParam.enumOf(_metrics, 'Goal metric.'),
      'history_periods': AiParam.integer(
        'Past periods (default 0).',
        min: 0,
        max: 12,
      ),
    },
    handler: (a) async => aiToolOk(
      await d.goals.listGoals(
        scope: a.enumValue('scope', _scopes),
        metric: a.enumValue('metric', _metrics),
        activeOnly: true,
        historyPeriods: a.integer(
          'history_periods',
          fallback: 0,
          min: 0,
          max: 12,
        ),
      ),
    ),
  ),
];
