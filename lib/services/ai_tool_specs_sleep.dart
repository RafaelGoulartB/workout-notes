import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Sleep tools. Nights are dated by the wake-up day.
List<AiToolSpec> sleepToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'get_sleep',
    domain: AiToolDomain.sleep,
    description:
        'Sleep. detail: summary (averages, efficiency, regularity, goal), nightly '
        '(rows newest first; page back with next_end_date), night (one night '
        'in full).',
    properties: {
      'days': AiParam.days(14, 1, 90),
      'end_date': AiParam.endDate('wake-up date for night'),
      'detail': AiParam.enumOf(
        AiSleepToolService.detailModes,
        'Default summary.',
      ),
    },
    handler: (a) async {
      final detail =
          a.enumValue(
            'detail',
            AiSleepToolService.detailModes,
            fallback: AiSleepToolService.summaryDetail,
          ) ??
          AiSleepToolService.summaryDetail;
      final endDate = a.date('end_date', alt: 'date');
      if (detail == AiSleepToolService.nightDetailMode) {
        return aiToolOk(await d.sleep.nightDetail(date: endDate));
      }
      return aiToolOk(
        await d.sleep.sleep(
          days: a.integer('days', fallback: 14, min: 1, max: 90),
          endDate: endDate,
          detail: detail,
        ),
      );
    },
  ),
];
