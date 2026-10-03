import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Periodization tool: the active plan and its weekly review.
List<AiToolSpec> planningToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'get_training_plan',
    description:
        'Active periodization plan on a date: phases, current phase/week, day '
        'target, template week, next routine and run. review adds metrics.',
    domain: AiToolDomain.planning,
    properties: {
      'date': AiParam.date('Day, default today'),
      'review': AiParam.enumOf(const ['week', 'phase'], 'Add metrics.'),
    },
    handler: (a) async {
      final date = a.date('date');
      return aiToolOk(
        await d.planning.trainingPlan(
          date: date == null ? d.planning.now() : DateTime.parse(date),
          review: a.enumValue('review', const ['week', 'phase']),
        ),
      );
    },
  ),
];
