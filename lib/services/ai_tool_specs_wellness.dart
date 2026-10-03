import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Cross-domain analytics tools (sleep x training, nutrition x body, recovery).
List<AiToolSpec> wellnessToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'analyze_sleep_performance',
    domain: AiToolDomain.sleep,
    description:
        'Sleep vs same-day training: correlations of sleep with volume and feeling, plus recent pairs.',
    properties: {'days': AiParam.days(42, 7, 90)},
    handler: (a) async => aiToolOk(
      await d.wellness.sleepPerformance(
        days: a.integer('days', fallback: 42, min: 7, max: 90),
      ),
    ),
  ),
  AiToolSpec(
    name: 'analyze_nutrition_body_trend',
    domain: AiToolDomain.nutrition,
    description:
        'Weekly mean calories/macros next to body weight over full weeks, with weight change and calories-vs-weight correlation.',
    properties: {'days': AiParam.days(84, 14, 180)},
    handler: (a) async => aiToolOk(
      await d.wellness.nutritionBodyTrend(
        days: a.integer('days', fallback: 84, min: 14, max: 180),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_weekly_recovery_trend',
    domain: AiToolDomain.sleep,
    description:
        'Weekly 0-100 recovery score (sleep, efficiency, regularity, workout feeling) over full weeks, with trend direction.',
    properties: {
      'weeks': AiParam.integer('Weeks (default 8).', min: 2, max: 12),
    },
    handler: (a) async => aiToolOk(
      await d.wellness.weeklyRecoveryTrend(
        weeks: a.integer('weeks', fallback: 8, min: 2, max: 12),
      ),
    ),
  ),
];
