import 'package:workout_notes/services/ai_tool_spec.dart';

/// Cross-domain analytics tools (sleep x training, nutrition x body, recovery).
List<AiToolSpec> wellnessToolSpecs(AiToolDeps d) => [
  AiToolSpec.window(
    name: 'analyze_sleep_performance',
    description:
        'Calcula associações observacionais entre sono e volume/sensação dos treinos em datas pareadas. Não implica causalidade.',
    defaultValue: 42,
    minimum: 7,
    maximum: 90,
    handler: (a) async => aiToolOk(
      await d.wellness.sleepPerformance(days: a.boundedInt('days', 42, 7, 90)),
    ),
  ),
  AiToolSpec.window(
    name: 'analyze_nutrition_body_trend',
    description:
        'Relaciona ingestão semanal de calorias/macros com medidas de peso corporal e informa cobertura dos dados.',
    defaultValue: 84,
    minimum: 14,
    maximum: 180,
    handler: (a) async => aiToolOk(
      await d.wellness.nutritionBodyTrend(
        days: a.boundedInt('days', 84, 14, 180),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_weekly_recovery_trend',
    description:
        'Tendência semanal não clínica de recuperação, combinando apenas componentes disponíveis de sono, regularidade e sensação dos treinos.',
    properties: {
      'weeks': {
        'type': 'integer',
        'description': 'Semanas (2 a 12; padrão 8).',
        'default': 8,
        'minimum': 2,
        'maximum': 12,
      },
    },
    handler: (a) async => aiToolOk(
      await d.wellness.weeklyRecoveryTrend(
        weeks: a.boundedInt('weeks', 8, 2, 12),
      ),
    ),
  ),
];
