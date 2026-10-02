import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Strength-training tools: workouts, exercises, records, summaries, routines.
List<AiToolSpec> workoutToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'get_workout_history',
    description:
        'Strength workouts newest first: duration, feeling, sets, volume. '
        'status planned = not started.',
    domain: AiToolDomain.workouts,
    properties: {
      'start_date': AiParam.startDate(),
      'end_date': AiParam.endDate(),
      'status': AiParam.enumOf(const [
        'completed',
        'in_progress',
        'planned',
        'all',
      ], 'Default completed.'),
      'limit': AiParam.limit(10, 30),
      'page': AiParam.page(),
    },
    handler: (a) async => aiToolOk(
      await d.workouts.history(
        startDate: a.date('start_date'),
        endDate: a.date('end_date'),
        status: a.enumValue('status', const [
          'completed',
          'in_progress',
          'planned',
          'all',
        ], fallback: 'completed')!,
        limit: a.integer('limit', fallback: 10, min: 1, max: 30),
        page: a.integer('page', fallback: 1, min: 1),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_workout_detail',
    description:
        'One workout: every exercise and set, records set, comparison with the '
        'previous similar session.',
    domain: AiToolDomain.workouts,
    properties: {'workout_id': AiParam.string('Id from get_workout_history.')},
    required: const ['workout_id'],
    handler: (a) async => aiToolOk(
      await d.workouts.workoutDetail(a.requiredString('workout_id')),
    ),
  ),
  AiToolSpec(
    name: 'list_exercises',
    description:
        'Exercises with sessions and last trained date. Name search works in '
        'English and Portuguese; sort=least_recent finds neglected ones.',
    domain: AiToolDomain.workouts,
    properties: {
      'name_contains': AiParam.string('Part of the name.'),
      'category_id': AiParam.string(
        'From get_training_summary group_by=category.',
      ),
      'sort': AiParam.enumOf(const [
        'name',
        'most_recent',
        'least_recent',
      ], 'Default name.'),
      'limit': AiParam.limit(20, 50),
    },
    handler: (a) async => aiToolOk(
      await d.workouts.listExercises(
        search: a.string('name_contains', alt: 'search'),
        categoryId: a.string('category_id'),
        favorites: null,
        sort: a.enumValue('sort', const [
          'name',
          'most_recent',
          'least_recent',
        ], fallback: 'name')!,
        limit: a.integer('limit', fallback: 20, min: 1, max: 50),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_exercise_history',
    description:
        'An exercise: profile, recent sessions (weightxreps) and trend (estimated '
        '1RM slope, best, change since first).',
    domain: AiToolDomain.workouts,
    properties: {
      'exercise_id': AiParam.string('Id from list_exercises.'),
      'days': AiParam.integer('Last N days (default all).', min: 1, max: 3650),
      'limit': AiParam.limit(8, 30),
    },
    required: const ['exercise_id'],
    handler: (a) async {
      final days = a.integerOrNull('days', min: 1, max: 3650);
      return aiToolOk(
        await d.workouts.exerciseHistory(
          a.requiredString('exercise_id'),
          startDate: days == null
              ? null
              : dateKey(addDays(d.workouts.now(), -(days - 1))),
          limit: a.integer('limit', fallback: 8, min: 1, max: 30),
        ),
      );
    },
  ),
  AiToolSpec(
    name: 'get_personal_records',
    description:
        'Personal records: recent across all exercises, or one exercise\'s '
        'all-time bests with exercise_id.',
    domain: AiToolDomain.workouts,
    properties: {
      'exercise_id': AiParam.string('Id from list_exercises.'),
      'days': AiParam.days(30, 1, 366),
      'limit': AiParam.limit(15, 40),
    },
    handler: (a) async => aiToolOk(
      await d.workouts.personalRecords(
        exerciseId: a.string('exercise_id'),
        window: AiToolMath.window(
          today: d.workouts.now(),
          days: a.integerOrNull('days', min: 1, max: 366),
          defaultDays: 30,
          maxDays: 366,
        ),
        limit: a.integer('limit', fallback: 15, min: 1, max: 40),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_training_summary',
    description:
        'Period summary: workouts, sets, volume, effort, top exercises, change vs '
        'previous period. group_by category lists untouched categories.',
    domain: AiToolDomain.workouts,
    properties: {
      'days': AiParam.days(30, 1, 366),
      'end_date': AiParam.endDate(),
      'group_by': AiParam.enumOf(const [
        'week',
        'category',
      ], 'Also break down by week or category.'),
    },
    handler: (a) async => aiToolOk(
      await d.workouts.trainingSummary(
        window: AiToolMath.window(
          today: d.workouts.now(),
          days: a.integerOrNull('days', min: 1, max: 366),
          endDate: a.date('end_date'),
          defaultDays: 30,
          maxDays: 366,
        ),
        groupBy: a.enumValue('group_by', const ['week', 'category']),
      ),
    ),
  ),
  AiToolSpec(
    name: 'list_routines',
    description: 'Routines with day and exercise counts and last used date.',
    domain: AiToolDomain.workouts,
    properties: {'name_contains': AiParam.string('Part of the name.')},
    handler: (a) async => aiToolOk(
      await d.workouts.listRoutines(nameContains: a.string('name_contains')),
    ),
  ),
  AiToolSpec(
    name: 'get_routine_detail',
    description:
        'Routine tree with source ids and revision for editing; long routines '
        'return the first days, the rest in more_days.',
    domain: AiToolDomain.workouts,
    properties: {
      'routine_id': AiParam.string('Id from list_routines.'),
      'day_id': AiParam.string('Only this source_day_id.'),
    },
    required: const ['routine_id'],
    handler: (a) async => aiToolOk(
      await d.workouts.routineDetail(
        a.requiredString('routine_id'),
        dayId: a.string('day_id'),
      ),
    ),
  ),
];
