import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Body measurements and the user profile.
List<AiToolSpec> bodyToolSpecs(AiToolDeps d) {
  final types = [for (final type in kBodyMeasureTypes) type.id];
  return [
    AiToolSpec(
      name: 'list_body_measurements',
      description:
          'Body measurements newest first (blood pressure secondary_value = '
          'diastolic; limbs have side). latest_per_type: current of each.',
      domain: AiToolDomain.body,
      properties: {
        'type': AiParam.enumOf(types, 'Default all.'),
        'start_date': AiParam.startDate(),
        'end_date': AiParam.endDate(),
        'latest_per_type': AiParam.boolean('Latest per type.'),
        'limit': AiParam.limit(20, 60),
      },
      handler: (a) async => aiToolOk(
        await d.profile.measurements(
          type: a.enumValue('type', types),
          startDate: a.date('start_date'),
          endDate: a.date('end_date'),
          latestPerType: a.flag('latest_per_type'),
          limit: a.integer('limit', fallback: 20, min: 1, max: 60),
        ),
      ),
    ),
    AiToolSpec(
      name: 'get_profile',
      description:
          'Sex, age, height, weight, units, nutrition goal, sleep goal, meal '
          'types.',
      domain: AiToolDomain.body,
      handler: (a) async => aiToolOk(await d.profile.profile()),
    ),
  ];
}
