// Read-only tool queries may use the database directly (documented exception
// to the repository-only rule): they only shape data for the model.
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Running and cardio tools.
List<AiToolSpec> runToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'list_run_activities',
    domain: AiToolDomain.running,
    description:
        'Recorded runs or bike rides newest first: distance, time, pace, RPE.',
    properties: {
      'start_date': AiParam.date('From'),
      'end_date': AiParam.date('To'),
      'activity_type': AiParam.enumOf(const [
        'running',
        'stationary_bike',
        'all',
      ], 'Default running.'),
      'limit': AiParam.limit(15, 40),
      'page': AiParam.page(),
    },
    handler: (a) async => aiToolOk(
      await d.runs.listActivities(
        startDate: a.date('start_date'),
        endDate: a.date('end_date'),
        activityType:
            a.enumValue('activity_type', const [
              'running',
              'stationary_bike',
              'all',
            ], fallback: 'running') ??
            'running',
        limit: a.integer('limit', fallback: 15, min: 1, max: 40),
        page: a.integer('page', fallback: 1, min: 1),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_run_activity_detail',
    domain: AiToolDomain.running,
    description:
        'One run or ride: metrics, km splits, laps, best efforts, shoes, '
        'plan session and planned vs actual steps.',
    properties: {'activity_id': AiParam.string('Run activity id')},
    required: const ['activity_id'],
    handler: (a) async =>
        aiToolOk(await d.runs.activityDetail(a.requiredString('activity_id'))),
  ),
  AiToolSpec(
    name: 'get_run_progress',
    domain: AiToolDomain.running,
    description:
        'Running volume, pace, streak, weekly trend and change vs the '
        'previous period (negative pace change = faster).',
    properties: {
      'period': AiParam.enumOf(const [
        '4_weeks',
        '12_weeks',
        'year',
        'all',
      ], 'Default 12_weeks.'),
    },
    handler: (a) async => aiToolOk(
      await d.runs.progress(
        period:
            a.enumValue('period', const [
              '4_weeks',
              '12_weeks',
              'year',
              'all',
            ], fallback: '12_weeks') ??
            '12_weeks',
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_cardio_summary',
    domain: AiToolDomain.running,
    description:
        'Cardio totals by type (run, bike, gym), full weekly buckets, recent '
        'activity ids.',
    properties: {'days': AiParam.days(28, 7, 366)},
    handler: (a) async => aiToolOk(
      await d.runs.cardioSummary(
        days: a.integer('days', fallback: 28, min: 7, max: 366),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_run_achievements',
    domain: AiToolDomain.running,
    description:
        'Run records: top 3 per category (distance, duration, pace, best km, 1k '
        'to marathon) with activity ids.',
    handler: (a) async => aiToolOk(await d.runs.achievements()),
  ),
  AiToolSpec(
    name: 'get_run_plan',
    domain: AiToolDomain.running,
    description:
        'Running plans: no plan_id = all plans plus the followed one in detail '
        '(adherence, re-plan reviews, sessions with steps; page with from_week).',
    properties: {
      'plan_id': AiParam.string('Plan id.'),
      'from_week': AiParam.integer('First week (default current).', min: 1),
      'weeks': AiParam.integer('Weeks shown (default 2).', min: 1, max: 6),
    },
    handler: (a) async => aiToolOk(
      await d.runs.plan(
        planId: a.string('plan_id'),
        fromWeek: a.integerOrNull('from_week', min: 1),
        weeks: a.integer('weeks', fallback: 2, min: 1, max: 6),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_run_schedule',
    domain: AiToolDomain.running,
    description:
        'Scheduled runs by date, ascending: status, session target, recorded '
        'run when done.',
    properties: {
      'start_date': AiParam.date('From, default today'),
      'end_date': AiParam.date('To, default start + 27 days'),
      'limit': AiParam.limit(20, 40),
      'page': AiParam.page(),
    },
    handler: (a) async => aiToolOk(
      await d.runs.schedule(
        startDate: a.date('start_date'),
        endDate: a.date('end_date'),
        limit: a.integer('limit', fallback: 20, min: 1, max: 40),
        page: a.integer('page', fallback: 1, min: 1),
      ),
    ),
  ),
];
