// Read-only tool queries may use the database directly (documented exception
// to the repository-only rule): they only shape data for the model.
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Strength-training tools: workouts, exercises, routines, body measurements.
List<AiToolSpec> workoutToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'list_recent_workouts',
    description:
        'Lista os treinos mais recentes com volume, sensação e contagem de exercícios.',
    properties: {
      'limit': {
        'type': 'integer',
        'description': 'Quantos treinos retornar (padrão 8).',
        'default': 8,
      },
    },
    handler: (a) async => aiToolOk(
      await d.workouts.recent(limit: a.boundedInt('limit', 8, 1, 20)),
    ),
  ),
  AiToolSpec(
    name: 'get_workout_history',
    description:
        'Histórico paginado de treinos, inclusive períodos antigos. Permite filtrar por data e status; cada item distingue treino concluído, em andamento e planejado e resume somente séries concluídas sem aquecimento.',
    properties: {
      'start_date': {
        'type': 'string',
        'description': 'Primeiro dia em YYYY-MM-DD.',
      },
      'end_date': {
        'type': 'string',
        'description': 'Último dia em YYYY-MM-DD.',
      },
      'status': {
        'type': 'string',
        'enum': ['all', 'completed', 'in_progress', 'planned'],
        'default': 'all',
      },
      'page': {'type': 'integer', 'minimum': 1, 'default': 1},
      'page_size': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 50,
        'default': 20,
      },
    },
    handler: (a) async => aiToolOk(
      await d.workouts.history(
        startDate: a.isoDate('start_date'),
        endDate: a.isoDate('end_date'),
        status: a.string('status') ?? 'all',
        page: a.boundedInt('page', 1, 1, 100000),
        pageSize: a.boundedInt('page_size', 20, 1, 50),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_workout_detail',
    description:
        'Retorna todos os exercícios e séries de um treino específico.',
    properties: {
      'workout_id': {'type': 'string', 'description': 'UUID do treino.'},
    },
    required: ['workout_id'],
    handler: (a) async {
      final detail = await d.workouts.workoutDetail(
        a.requiredString('workout_id'),
      );
      if (detail == null) {
        return const AiToolResult(
          ok: false,
          code: 'not_found',
          message: 'Treino não encontrado.',
        );
      }
      return aiToolOk(detail);
    },
  ),
  AiToolSpec(
    name: 'list_exercises',
    description:
        'Lista os exercícios cadastrados, opcionalmente filtrando por categoria, nome ou favoritos.',
    properties: {
      'name_contains': {'type': 'string'},
      'category_id': {'type': 'string'},
      'is_favorite': {'type': 'boolean'},
      'limit': {'type': 'integer', 'default': 20},
    },
    handler: (a) async => aiToolOk(
      await d.workouts.listExercises(
        categoryId: a.string('category_id'),
        search: a.string('name_contains', alt: 'search'),
        favorites: a['is_favorite'] as bool?,
        limit: a.boundedInt('limit', 20, 1, 50),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_exercise_detail',
    description:
        'Perfil completo de um exercício: categoria, sistema energético, tipo, equipamento, notas, favorito, descanso padrão, incremento de carga e estatísticas de uso concluído.',
    properties: {
      'exercise_id': {'type': 'string'},
    },
    required: ['exercise_id'],
    handler: (a) async {
      final detail = await d.workouts.exerciseDetail(
        a.requiredString('exercise_id'),
      );
      if (detail == null) {
        return const AiToolResult(
          ok: false,
          code: 'not_found',
          message: 'Exercício não encontrado.',
        );
      }
      return aiToolOk(detail);
    },
  ),
  AiToolSpec(
    name: 'get_exercise_history',
    description:
        'Histórico de séries de um exercício, com top sets, médias e totais.',
    properties: {
      'exercise_id': {'type': 'string'},
      'limit': {'type': 'integer', 'default': 12},
      'start_date': {'type': 'string'},
      'end_date': {'type': 'string'},
    },
    required: ['exercise_id'],
    handler: (a) async => aiToolOk(
      await d.workouts.exerciseHistory(
        a.requiredString('exercise_id'),
        startDate: a.isoDate('start_date'),
        endDate: a.isoDate('end_date'),
        limit: a.boundedInt('limit', 12, 1, 40),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_exercise_personal_records',
    description: 'Recordes pessoais (PRs) de um exercício.',
    properties: {
      'exercise_id': {'type': 'string'},
    },
    required: ['exercise_id'],
    handler: (a) async => aiToolOk(
      await d.workouts.exerciseRecords(a.requiredString('exercise_id')),
    ),
  ),
  AiToolSpec(
    name: 'get_weekly_volume_breakdown',
    description:
        'Volume semanal agrupado por categoria, nas últimas N semanas.',
    properties: {
      'weeks_back': {'type': 'integer', 'default': 8},
    },
    handler: (a) async => aiToolOk(
      await d.workouts.weeklyVolume(weeks: a.boundedInt('weeks', 8, 2, 16)),
    ),
  ),
  AiToolSpec(
    name: 'get_progress_trend',
    description:
        'Tendência de progressão (peso, reps, volume) de um exercício nas últimas N semanas.',
    properties: {
      'exercise_id': {'type': 'string'},
      'weeks_back': {'type': 'integer', 'default': 8},
    },
    required: ['exercise_id'],
    handler: (a) async => aiToolOk(
      await d.workouts.progressTrend(
        a.requiredString('exercise_id'),
        weeks: a.boundedInt('weeks', 8, 2, 16),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_training_summary',
    description:
        'Analisa um período de treino: frequência e status, duração, calorias, sensação, séries, volume, repetições, distância, tempo, RPE, densidade, categorias e exercícios mais usados. Métricas de desempenho usam apenas treinos e séries concluídos, sem aquecimento.',
    properties: {
      'days': {'type': 'integer', 'minimum': 1, 'maximum': 366, 'default': 30},
      'start_date': {'type': 'string'},
      'end_date': {'type': 'string'},
    },
    handler: (a) async {
      final endDate = a.isoDate('end_date');
      final explicitStart = a.isoDate('start_date');
      final days = a.boundedInt('days', 30, 1, 366);
      final effectiveEnd = DateTime.tryParse(endDate ?? '') ?? DateTime.now();
      final effectiveStart =
          explicitStart ??
          dateKey(effectiveEnd.subtract(Duration(days: days - 1)));
      return aiToolOk(
        await d.workouts.trainingSummary(
          startDate: effectiveStart,
          endDate: endDate ?? dateKey(effectiveEnd),
        ),
      );
    },
  ),
  AiToolSpec(
    name: 'list_routines',
    description: 'Lista todas as rotinas com contagem de dias e exercícios.',
    properties: {
      'name_contains': {'type': 'string'},
    },
    handler: (a) async => aiToolOk(await _listRoutines(d, a)),
  ),
  AiToolSpec(
    name: 'get_routine_detail',
    description: 'Detalha uma rotina: dias, exercícios e séries predefinidas.',
    properties: {
      'routine_id': {'type': 'string'},
    },
    required: ['routine_id'],
    handler: (a) async => aiToolOk(await _getRoutineDetail(d, a)),
  ),
  AiToolSpec(
    name: 'list_body_measurements',
    description:
        'Lista medidas corporais (peso, circunferências, etc.) com data e valor.',
    properties: {
      'type': {
        'type': 'string',
        'description': 'Tipo de medida. Vazio = todas.',
      },
      'limit': {'type': 'integer', 'default': 20},
    },
    handler: (a) async {
      final type = a['type'] as String?;
      final rows = await d.db.bodyMeasurementRepo.getBodyMeasurements(
        type: type,
        limit: a.boundedInt('limit', 20, 1, 50),
      );
      return aiToolOk({
        'type': type,
        'measurements': rows
            .map(
              (m) => {
                'id': m['id'],
                'type': m['type'],
                'value': m['value'],
                'unit': m['unit'],
                'date': m['date'],
                'timeOfDay': m['time_of_day'],
                'comment': m['comment'],
              },
            )
            .toList(),
      });
    },
  ),
];

Future<Map<String, dynamic>> _listRoutines(AiToolDeps d, AiToolArgs a) async {
  final search = (a['name_contains'] as String?)?.toLowerCase();
  final rawDb = await d.db.database;
  final rows = await rawDb.rawQuery(
    '''
      SELECT r.id, r.name, r.notes,
        COUNT(DISTINCT rd.id) AS day_count,
        COUNT(DISTINCT re.id) AS exercise_count
      FROM routines r
      LEFT JOIN routine_days rd ON rd.routine_id = r.id
      LEFT JOIN routine_exercises re ON re.routine_day_id = rd.id
      WHERE (? IS NULL OR LOWER(r.name) LIKE ?)
      GROUP BY r.id
      ORDER BY r.created_at DESC
    ''',
    [search, search == null ? null : '%$search%'],
  );
  final out = rows
      .map(
        (r) => {
          'id': r['id'],
          'name': r['name'],
          'notes': r['notes'],
          'dayCount': (r['day_count'] as num?)?.toInt() ?? 0,
          'exerciseCount': (r['exercise_count'] as num?)?.toInt() ?? 0,
        },
      )
      .toList();
  return {'routines': out};
}

Future<Map<String, dynamic>> _getRoutineDetail(
  AiToolDeps d,
  AiToolArgs a,
) async {
  final id = (a['routine_id'] as String?) ?? (a['routineId'] as String?);
  if (id == null) return {'error': 'routine_id é obrigatório'};
  final r = await d.db.routineRepo.getRoutine(id);
  if (r == null) return {'error': 'rotina não encontrada'};
  final rawDb = await d.db.database;
  final rows = await rawDb.rawQuery(
    '''
      SELECT rd.id AS day_id, rd.name AS day_name, rd.order_index AS day_order,
        rd.notes AS day_notes, re.id AS routine_exercise_id, re.exercise_id,
        e.name AS exercise_name, e.type AS exercise_type,
        re.order_index AS exercise_order, re.rest_time_seconds,
        re.superset_group_id, ps.id AS set_id, ps.weight, ps.reps,
        ps.distance, ps.time_seconds, ps.is_warmup
      FROM routine_days rd
      LEFT JOIN routine_exercises re ON re.routine_day_id = rd.id
      LEFT JOIN exercises e ON e.id = re.exercise_id
      LEFT JOIN predefined_sets ps ON ps.routine_exercise_id = re.id
      WHERE rd.routine_id = ?
      ORDER BY rd.order_index ASC, re.order_index ASC, ps.order_index ASC
    ''',
    [id],
  );
  final byDay = <String, Map<String, dynamic>>{};
  final byExercise = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final dayId = row['day_id'] as String;
    final day = byDay.putIfAbsent(
      dayId,
      () => {
        'id': dayId,
        'source_day_id': dayId,
        'name': row['day_name'],
        'order': row['day_order'],
        'notes': row['day_notes'],
        'exercises': <Map<String, dynamic>>[],
      },
    );
    final exerciseId = row['routine_exercise_id'] as String?;
    if (exerciseId == null) continue;
    final exercise = byExercise.putIfAbsent(exerciseId, () {
      final value = <String, dynamic>{
        'routineExerciseId': exerciseId,
        'source_routine_exercise_id': exerciseId,
        'exerciseId': row['exercise_id'],
        'exerciseName': row['exercise_name'],
        'exerciseType': row['exercise_type'],
        'order': row['exercise_order'],
        'restTimeSeconds': row['rest_time_seconds'],
        'supersetGroupId': row['superset_group_id'],
        'predefinedSets': <Map<String, dynamic>>[],
      };
      (day['exercises'] as List<Map<String, dynamic>>).add(value);
      return value;
    });
    if (row['set_id'] != null) {
      (exercise['predefinedSets'] as List<Map<String, dynamic>>).add({
        'id': row['set_id'],
        'source_set_id': row['set_id'],
        'weight': row['weight'],
        'reps': row['reps'],
        'distance': row['distance'],
        'timeSeconds': row['time_seconds'],
        'isWarmup': (row['is_warmup'] as int? ?? 0) == 1,
      });
    }
  }
  final daysOut = byDay.values.toList();
  return {'id': id, 'name': r['name'], 'notes': r['notes'], 'days': daysOut};
}
