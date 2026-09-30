// Read-only tool queries may use the database directly (documented exception
// to the repository-only rule): they only shape data for the model.
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Running and cardio tools.
List<AiToolSpec> runToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'get_cardio_summary',
    description:
        'Resumo de corridas GPS, bicicleta estacionária e cardio legado, com distância, duração, ritmo, velocidade e esforço.',
    properties: {
      'weeks_back': {'type': 'integer', 'default': 4},
    },
    handler: (a) async {
      final weeks = a.boundedInt('weeks', 4, 2, 16);
      final summaries = await Future.wait([
        d.runs.cardioSummary(weeks: weeks),
        d.workouts.cardioSummary(weeks: weeks),
      ]);
      return aiToolOk({
        ...summaries[0],
        'legacyAerobicWorkoutData': summaries[1],
        'sourceNote':
            'recorded activities come from run_activities; legacy aerobic sets are reported separately',
      });
    },
  ),
  AiToolSpec(
    name: 'list_run_activities',
    description:
        'Lista corridas GPS ou sessões de bicicleta registradas, com distância, tempo, pace, calorias, RPE, sensação e melhores esforços.',
    properties: {
      'start_date': {
        'type': 'string',
        'description': 'Data inicial yyyy-MM-dd.',
      },
      'end_date': {'type': 'string', 'description': 'Data final yyyy-MM-dd.'},
      'activity_type': {
        'type': 'string',
        'enum': ['running', 'stationary_bike', 'all'],
        'default': 'running',
      },
      'page': {'type': 'integer', 'default': 1},
      'page_size': {'type': 'integer', 'default': 20},
    },
    handler: (a) async => aiToolOk(
      await d.runs.listActivities(
        startDate: a.isoDate('start_date'),
        endDate: a.isoDate('end_date'),
        activityType: a.string('activity_type') ?? 'running',
        page: a.boundedInt('page', 1, 1, 100000),
        pageSize: a.boundedInt('page_size', 20, 1, 50),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_run_activity_detail',
    description:
        'Detalha uma corrida ou pedal registrado: métricas, rota agregada, plano associado e comparação planejado versus realizado por etapa.',
    properties: {
      'activity_id': {'type': 'string'},
    },
    required: const ['activity_id'],
    handler: (a) async =>
        aiToolOk(await d.runs.activityDetail(a.requiredString('activity_id'))),
  ),
  AiToolSpec(
    name: 'get_run_progress',
    description:
        'Analisa evolução de corrida: volume, frequência, ritmo, comparação com período anterior, sequência semanal e tendências.',
    properties: {
      'period': {
        'type': 'string',
        'enum': ['4_weeks', '12_weeks', 'year', 'all'],
        'default': '12_weeks',
      },
    },
    handler: (a) async => aiToolOk(
      await d.runs.progress(period: a.string('period') ?? '12_weeks'),
    ),
  ),
  AiToolSpec(
    name: 'get_run_achievements',
    description:
        'Retorna recordes e pódios de corrida: maior distância/duração, melhor pace, split e esforços de 1 km a maratona.',
    handler: (a) async => aiToolOk(await d.runs.achievements()),
  ),
  AiToolSpec(
    name: 'list_run_plans',
    description:
        'Lista planos de corrida com ativação, semana atual, objetivo, progresso, sessões concluídas, puladas e pendentes.',
    properties: {
      'include_archived': {'type': 'boolean', 'default': false},
    },
    handler: (a) async => aiToolOk(
      await d.runs.listPlans(
        includeArchived:
            a['include_archived'] as bool? ??
            a['includeArchived'] as bool? ??
            false,
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_run_plan_detail',
    description:
        'Detalha um plano de corrida: progresso e aderência, semanas, treinos e etapas (aquecimento, tiros, recuperação e desaquecimento).',
    properties: {
      'plan_id': {'type': 'string'},
    },
    required: const ['plan_id'],
    handler: (a) async =>
        aiToolOk(await d.runs.planDetail(a.requiredString('plan_id'))),
  ),
  AiToolSpec(
    name: 'get_run_schedule',
    description:
        'Corridas planejadas em um intervalo de datas, com status e a '
        'corrida registrada quando já foi concluída.',
    properties: {
      'start_date': {
        'type': 'string',
        'description': 'yyyy-MM-dd. Padrão: hoje.',
      },
      'end_date': {
        'type': 'string',
        'description': 'yyyy-MM-dd. Padrão: 4 semanas à frente.',
      },
    },
    handler: (a) async => aiToolOk(
      await d.runs.schedule(
        startDate: a.string('start_date'),
        endDate: a.string('end_date'),
      ),
    ),
  ),
];
