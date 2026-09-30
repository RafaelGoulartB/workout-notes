import 'package:workout_notes/services/ai_tool_spec.dart';

/// Sleep tools.
List<AiToolSpec> sleepToolSpecs(AiToolDeps d) => [
  AiToolSpec.window(
    name: 'get_sleep_summary',
    description:
        'Resumo agregado do sono recente: duração, eficiência, cobertura e regularidade de horários. Use antes de opinar sobre sono.',
    defaultValue: 14,
    minimum: 3,
    maximum: 90,
    handler: (a) async => aiToolOk(
      await d.wellness.sleepSummary(days: a.boundedInt('days', 14, 3, 90)),
    ),
  ),
  AiToolSpec(
    name: 'get_sleep_night_detail',
    description:
        'Detalha uma noite de sono por data local: duração registrada, real, estimada e efetiva com sua origem; horários; tempo na cama; comentário; estágios; latência; despertares; eficiência; confiança; ruído e qualidade do sinal. Use para perguntas sobre hoje, ontem ou uma noite específica. Dados acústicos são estimativas não clínicas e não diagnosticam ronco ou apneia.',
    properties: {
      'date': {
        'type': 'string',
        'description':
            'Data local no formato YYYY-MM-DD. Se omitida, usa a data local atual.',
      },
    },
    handler: (a) async =>
        aiToolOk(await d.sleep.nightDetail(date: a.string('date', alt: 'day'))),
  ),
  AiToolSpec(
    name: 'get_sleep_history',
    description:
        'Histórico diário paginado do sono. Retorna todas as noites registradas na janela, durações separadas e sua origem efetiva, horários, eficiência e disponibilidade de estágios. Datas sem registro ficam ausentes.',
    properties: {
      'days': {'type': 'integer', 'minimum': 1, 'maximum': 31, 'default': 30},
      'end_date': {
        'type': 'string',
        'description': 'Último dia da janela em YYYY-MM-DD; o padrão é hoje.',
      },
    },
    handler: (a) async => aiToolOk(
      await d.sleep.history(
        days: a.boundedInt('days', 30, 1, 31),
        endDate: a.string('end_date'),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_sleep_profile',
    description:
        'Retorna a meta diária de sono, modo padrão de monitoramento, contagens de noites manuais e monitoradas, cobertura de estágios e comparação da média com a meta em todo o histórico e nos últimos 30 dias. Não expõe segredos de missões ou alarmes.',
    handler: (a) async => aiToolOk(await d.sleep.profile()),
  ),
];
