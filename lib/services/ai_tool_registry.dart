import '../database/database_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/ai_message_role.dart';
import '../repositories/goal_repository.dart';

class AiToolRegistry {
  final DatabaseHelper db;
  final GoalRepository goalRepo;
  AiToolRegistry({DatabaseHelper? db, GoalRepository? goalRepo})
    : db = db ?? DatabaseHelper.instance,
      goalRepo = goalRepo ?? GoalRepository();

  /// OpenAI function-calling JSON schemas for all read tools.
  List<Map<String, dynamic>> openAiReadToolsSchema() {
    return _tools.map((t) => _schemaFor(t['name'] as String)).toList();
  }

  /// Human-friendly label for a tool name (used in chat bubbles).
  String humanLabel(String toolName, [AppLocalizations? l10n]) {
    if (l10n != null) {
      switch (toolName) {
        case 'list_recent_workouts':
          return l10n.aiToolListRecentWorkouts;
        case 'get_workout_detail':
          return l10n.aiToolGetWorkoutDetail;
        case 'list_exercises':
          return l10n.aiToolListExercises;
        case 'get_exercise_history':
          return l10n.aiToolGetExerciseHistory;
        case 'get_exercise_personal_records':
          return l10n.aiToolGetExerciseRecords;
        case 'get_weekly_volume_breakdown':
          return l10n.aiToolWeeklyVolume;
        case 'get_progress_trend':
          return l10n.aiToolProgressTrend;
        case 'list_routines':
          return l10n.aiToolListRoutines;
        case 'get_routine_detail':
          return l10n.aiToolGetRoutineDetail;
        case 'list_body_measurements':
          return l10n.aiToolBodyMeasurements;
        case 'get_cardio_summary':
          return l10n.aiToolCardioSummary;
        case 'list_goals':
          return l10n.aiToolListGoals;
        case 'get_goal_progress_history':
          return l10n.aiToolGoalHistory;
      }
    }
    switch (toolName) {
      case 'list_recent_workouts':
        return 'Listando treinos recentes';
      case 'get_workout_detail':
        return 'Detalhando treino';
      case 'list_exercises':
        return 'Buscando exercícios';
      case 'get_exercise_history':
        return 'Histórico do exercício';
      case 'get_exercise_personal_records':
        return 'Recordes pessoais';
      case 'get_weekly_volume_breakdown':
        return 'Volume semanal';
      case 'get_progress_trend':
        return 'Tendência de progressão';
      case 'list_routines':
        return 'Listando rotinas';
      case 'get_routine_detail':
        return 'Detalhando rotina';
      case 'list_body_measurements':
        return 'Medidas corporais';
      case 'get_cardio_summary':
        return 'Resumo de cardio';
      case 'list_goals':
        return 'Metas ativas';
      case 'get_goal_progress_history':
        return 'Histórico da meta';
      default:
        return toolName;
    }
  }

  /// Dispatch a read tool call to the right DB query.
  Future<AiToolResult> executeRead({
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    try {
      switch (toolName) {
        case 'list_recent_workouts':
          return _ok(await _listRecentWorkouts(args));
        case 'get_workout_detail':
          return _ok(await _getWorkoutDetail(args));
        case 'list_exercises':
          return _ok(await _listExercises(args));
        case 'get_exercise_history':
          return _ok(await _getExerciseHistory(args));
        case 'get_exercise_personal_records':
          return _ok(await _getExercisePRs(args));
        case 'get_weekly_volume_breakdown':
          return _ok(await _getWeeklyVolumeBreakdown(args));
        case 'get_progress_trend':
          return _ok(await _getProgressTrend(args));
        case 'list_routines':
          return _ok(await _listRoutines(args));
        case 'get_routine_detail':
          return _ok(await _getRoutineDetail(args));
        case 'list_body_measurements':
          return _ok(await _listBodyMeasurements(args));
        case 'get_cardio_summary':
          return _ok(await _getCardioSummary(args));
        case 'list_goals':
          return _ok(await _listGoals(args));
        case 'get_goal_progress_history':
          return _ok(await _getGoalProgressHistory(args));
        default:
          return AiToolResult(
            ok: false,
            code: 'unknown_tool',
            message: 'Tool "$toolName" não reconhecida.',
          );
      }
    } catch (e) {
      return AiToolResult(ok: false, code: 'error', message: e.toString());
    }
  }

  // ===========================================================================
  // TOOL IMPLEMENTATIONS
  // ===========================================================================

  Future<Map<String, dynamic>> _listRecentWorkouts(
    Map<String, dynamic> args,
  ) async {
    final limit = (args['limit'] as int?) ?? 10;
    final rows = await db.getWorkouts(limit: limit);
    final out = <Map<String, dynamic>>[];
    for (final w in rows) {
      final id = w['id'] as String;
      final entries = await db.getWorkoutExercises(id);
      double vol = 0;
      for (final e in entries) {
        final sets = await db.getExerciseSets(e['id'] as String);
        for (final s in sets) {
          if ((s['is_warmup'] as int? ?? 0) == 1) continue;
          final wt = (s['weight'] as num?)?.toDouble() ?? 0;
          final reps = (s['reps'] as num?)?.toInt() ?? 0;
          vol += wt * reps;
        }
      }
      out.add({
        'id': id,
        'date': w['date'],
        'durationSeconds': w['duration_seconds'],
        'feeling': w['feeling_rating'],
        'exerciseCount': entries.length,
        'volumeKg': vol,
        'comment': w['comment'],
      });
    }
    return {'workouts': out};
  }

  Future<Map<String, dynamic>> _getWorkoutDetail(
    Map<String, dynamic> args,
  ) async {
    final id =
        (args['workout_id'] as String?) ?? (args['workoutId'] as String?);
    if (id == null) {
      return {'error': 'workout_id é obrigatório'};
    }
    final w = await db.getWorkout(id);
    if (w == null) return {'error': 'workout não encontrado'};
    final entries = await db.getWorkoutExercises(id);
    final out = <Map<String, dynamic>>[];
    for (final e in entries) {
      final sets = await db.getExerciseSets(e['id'] as String);
      out.add({
        'exerciseId': e['exercise_id'],
        'exerciseName': e['exercise_name'],
        'order': e['order_index'],
        'sets': sets
            .map(
              (s) => {
                'weight': s['weight'],
                'reps': s['reps'],
                'distance': s['distance'],
                'timeSeconds': s['time_seconds'],
                'isWarmup': (s['is_warmup'] as int? ?? 0) == 1,
                'isComplete': (s['is_complete'] as int? ?? 0) == 1,
                'rpe': s['rpe'],
                'comment': s['comment'],
              },
            )
            .toList(),
      });
    }
    return {
      'id': id,
      'date': w['date'],
      'durationSeconds': w['duration_seconds'],
      'feeling': w['feeling_rating'],
      'comment': w['comment'],
      'exercises': out,
    };
  }

  Future<Map<String, dynamic>> _listExercises(Map<String, dynamic> args) async {
    final rows = await db.getExercises(
      categoryId: args['category_id'] as String?,
      search: args['name_contains'] as String?,
      favorites: args['is_favorite'] as bool?,
    );
    final compact = rows
        .map(
          (e) => {
            'id': e['id'],
            'name': e['name'],
            'categoryId': e['category_id'],
            'type': e['type'],
            'isFavorite': (e['is_favorite'] as int? ?? 0) == 1,
          },
        )
        .toList();
    return {'exercises': compact};
  }

  Future<Map<String, dynamic>> _getExerciseHistory(
    Map<String, dynamic> args,
  ) async {
    final id =
        (args['exercise_id'] as String?) ?? (args['exerciseId'] as String?);
    if (id == null) return {'error': 'exercise_id é obrigatório'};
    final limit = (args['limit'] as int?) ?? 20;
    final history = await db.getExerciseHistory(id, limit: limit);
    return {
      'exerciseId': id,
      'topSets': history['topSets'] ?? const [],
      'avgWeight': history['avgWeight'],
      'avgReps': history['avgReps'],
      'totalSets': history['totalSets'],
      'history': history['history'] ?? const [],
    };
  }

  Future<Map<String, dynamic>> _getExercisePRs(
    Map<String, dynamic> args,
  ) async {
    final id =
        (args['exercise_id'] as String?) ?? (args['exerciseId'] as String?);
    if (id == null) return {'error': 'exercise_id é obrigatório'};
    final prs = await db.getPersonalRecords(limit: 50);
    final filtered = prs.where((p) => p['exercise_id'] == id).toList();
    return {'exerciseId': id, 'records': filtered};
  }

  Future<Map<String, dynamic>> _getWeeklyVolumeBreakdown(
    Map<String, dynamic> args,
  ) async {
    final weeks =
        (args['weeks_back'] as int?) ?? (args['weeksBack'] as int?) ?? 8;
    final byCategory = await db.getWeeklyVolumeByCategory(weeks: weeks);
    return {'weeksBack': weeks, 'byCategory': byCategory};
  }

  Future<Map<String, dynamic>> _getProgressTrend(
    Map<String, dynamic> args,
  ) async {
    final id =
        (args['exercise_id'] as String?) ?? (args['exerciseId'] as String?);
    if (id == null) return {'error': 'exercise_id é obrigatório'};
    final weeks =
        (args['weeks_back'] as int?) ?? (args['weeksBack'] as int?) ?? 8;
    final history = await db.getExerciseHistory(id, limit: weeks * 5);
    return {
      'exerciseId': id,
      'weeksBack': weeks,
      'dataPoints': history['history'] ?? const [],
    };
  }

  Future<Map<String, dynamic>> _listRoutines(Map<String, dynamic> args) async {
    final routines = await db.getRoutines();
    final search = (args['name_contains'] as String?)?.toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final r in routines) {
      if (search != null &&
          !(r['name'] as String).toLowerCase().contains(search)) {
        continue;
      }
      final days = await db.getRoutineDays(r['id'] as String);
      int exCount = 0;
      for (final d in days) {
        final exs = await db.getRoutineExercises(d['id'] as String);
        exCount += exs.length;
      }
      out.add({
        'id': r['id'],
        'name': r['name'],
        'notes': r['notes'],
        'dayCount': days.length,
        'exerciseCount': exCount,
      });
    }
    return {'routines': out};
  }

  Future<Map<String, dynamic>> _getRoutineDetail(
    Map<String, dynamic> args,
  ) async {
    final id =
        (args['routine_id'] as String?) ?? (args['routineId'] as String?);
    if (id == null) return {'error': 'routine_id é obrigatório'};
    final r = await db.getRoutine(id);
    if (r == null) return {'error': 'rotina não encontrada'};
    final days = await db.getRoutineDays(id);
    final daysOut = <Map<String, dynamic>>[];
    for (final d in days) {
      final exs = await db.getRoutineExercises(d['id'] as String);
      final exsOut = <Map<String, dynamic>>[];
      for (final e in exs) {
        final sets = await db.getPredefinedSets(e['id'] as String);
        exsOut.add({
          'exerciseId': e['exercise_id'],
          'order': e['order_index'],
          'restTimeSeconds': e['rest_time_seconds'],
          'predefinedSets': sets
              .map(
                (s) => {
                  'weight': s['weight'],
                  'reps': s['reps'],
                  'distance': s['distance'],
                  'timeSeconds': s['time_seconds'],
                  'isWarmup': (s['is_warmup'] as int? ?? 0) == 1,
                },
              )
              .toList(),
        });
      }
      daysOut.add({
        'id': d['id'],
        'name': d['name'],
        'order': d['order_index'],
        'notes': d['notes'],
        'exercises': exsOut,
      });
    }
    return {'id': id, 'name': r['name'], 'notes': r['notes'], 'days': daysOut};
  }

  Future<Map<String, dynamic>> _listBodyMeasurements(
    Map<String, dynamic> args,
  ) async {
    final type = args['type'] as String?;
    final limit = (args['limit'] as int?) ?? 30;
    final rows = await db.getBodyMeasurements(type: type, limit: limit);
    return {
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
    };
  }

  Future<Map<String, dynamic>> _getCardioSummary(
    Map<String, dynamic> args,
  ) async {
    final weeks =
        (args['weeks_back'] as int?) ?? (args['weeksBack'] as int?) ?? 4;
    final weekly = await db.getCardioWeeklyDistance(weeks: weeks);
    final byModality = await db.getCardioDistanceByModality();
    return {
      'weeksBack': weeks,
      'weeklyDistance': weekly,
      'byModality': byModality,
    };
  }

  Future<Map<String, dynamic>> _listGoals(Map<String, dynamic> args) async {
    final scope = args['scope'] as String?;
    final metric = args['metric'] as String?;
    final activeOnly = (args['is_active'] as bool?) ?? true;
    final goals = await goalRepo.getAll(activeOnly: activeOnly);
    final out = <Map<String, dynamic>>[];
    for (final g in goals) {
      if (scope != null && g.scope.value != scope) continue;
      if (metric != null && g.metric.value != metric) continue;
      try {
        final p = await goalRepo.getProgress(g);
        out.add({
          'id': g.id,
          'title': g.title,
          'scope': g.scope.value,
          'metric': g.metric.value,
          'period': g.period.value,
          'currentValue': p.currentValue,
          'targetValue': p.targetValue,
          'progressPct': p.percent,
          'isComplete': p.isComplete,
          'daysRemaining': p.daysRemaining,
        });
      } catch (_) {
        out.add({
          'id': g.id,
          'title': g.title,
          'scope': g.scope.value,
          'metric': g.metric.value,
          'period': g.period.value,
          'targetValue': g.targetValue,
        });
      }
    }
    return {'goals': out};
  }

  Future<Map<String, dynamic>> _getGoalProgressHistory(
    Map<String, dynamic> args,
  ) async {
    final id = (args['goal_id'] as String?) ?? (args['goalId'] as String?);
    if (id == null) return {'error': 'goal_id é obrigatório'};
    final periods = (args['periods_back'] as int?) ?? 6;
    final goal = await goalRepo.getById(id);
    if (goal == null) return {'error': 'meta não encontrada'};
    final (current, history) = await goalRepo.getProgressWithHistory(
      goal,
      historyCount: periods,
    );
    return {
      'goalId': id,
      'title': goal.title,
      'current': {
        'currentValue': current.currentValue,
        'targetValue': current.targetValue,
        'progressPct': current.percent,
        'isComplete': current.isComplete,
        'daysRemaining': current.daysRemaining,
      },
      'history': history
          .map(
            (r) => {
              'start': r.start.toIso8601String().substring(0, 10),
              'end': r.end.toIso8601String().substring(0, 10),
              'value': r.value,
              'targetValue': r.targetValue,
              'wasCompleted': r.wasCompleted,
            },
          )
          .toList(),
    };
  }

  // ===========================================================================
  // SCHEMA GENERATION
  // ===========================================================================

  Map<String, dynamic> _schemaFor(String name) {
    switch (name) {
      case 'list_recent_workouts':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Lista os treinos mais recentes com volume, sensação e contagem de exercícios.',
            'parameters': {
              'type': 'object',
              'properties': {
                'limit': {
                  'type': 'integer',
                  'description': 'Quantos treinos retornar (padrão 10).',
                  'default': 10,
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_workout_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Retorna todos os exercícios e séries de um treino específico.',
            'parameters': {
              'type': 'object',
              'properties': {
                'workout_id': {
                  'type': 'string',
                  'description': 'UUID do treino.',
                },
              },
              'required': ['workout_id'],
            },
          },
        };
      case 'list_exercises':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Lista os exercícios cadastrados, opcionalmente filtrando por categoria, nome ou favoritos.',
            'parameters': {
              'type': 'object',
              'properties': {
                'name_contains': {'type': 'string'},
                'category_id': {'type': 'string'},
                'is_favorite': {'type': 'boolean'},
              },
              'required': const [],
            },
          },
        };
      case 'get_exercise_history':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Histórico de séries de um exercício, com top sets, médias e totais.',
            'parameters': {
              'type': 'object',
              'properties': {
                'exercise_id': {'type': 'string'},
                'limit': {'type': 'integer', 'default': 20},
              },
              'required': ['exercise_id'],
            },
          },
        };
      case 'get_exercise_personal_records':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description': 'Recordes pessoais (PRs) de um exercício.',
            'parameters': {
              'type': 'object',
              'properties': {
                'exercise_id': {'type': 'string'},
              },
              'required': ['exercise_id'],
            },
          },
        };
      case 'get_weekly_volume_breakdown':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Volume semanal agrupado por categoria, nas últimas N semanas.',
            'parameters': {
              'type': 'object',
              'properties': {
                'weeks_back': {'type': 'integer', 'default': 8},
              },
              'required': const [],
            },
          },
        };
      case 'get_progress_trend':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Tendência de progressão (peso, reps, volume) de um exercício nas últimas N semanas.',
            'parameters': {
              'type': 'object',
              'properties': {
                'exercise_id': {'type': 'string'},
                'weeks_back': {'type': 'integer', 'default': 8},
              },
              'required': ['exercise_id'],
            },
          },
        };
      case 'list_routines':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Lista todas as rotinas com contagem de dias e exercícios.',
            'parameters': {
              'type': 'object',
              'properties': {
                'name_contains': {'type': 'string'},
              },
              'required': const [],
            },
          },
        };
      case 'get_routine_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Detalha uma rotina: dias, exercícios e séries predefinidas.',
            'parameters': {
              'type': 'object',
              'properties': {
                'routine_id': {'type': 'string'},
              },
              'required': ['routine_id'],
            },
          },
        };
      case 'list_body_measurements':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Lista medidas corporais (peso, circunferências, etc.) com data e valor.',
            'parameters': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'description': 'Tipo de medida. Vazio = todas.',
                },
                'limit': {'type': 'integer', 'default': 30},
              },
              'required': const [],
            },
          },
        };
      case 'get_cardio_summary':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Resumo de cardio: distância semanal por modalidade.',
            'parameters': {
              'type': 'object',
              'properties': {
                'weeks_back': {'type': 'integer', 'default': 4},
              },
              'required': const [],
            },
          },
        };
      case 'list_goals':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description': 'Lista metas (goals) ativas com progresso atual.',
            'parameters': {
              'type': 'object',
              'properties': {
                'scope': {
                  'type': 'string',
                  'description': 'anaerobic ou aerobic.',
                },
                'metric': {
                  'type': 'string',
                  'description': 'volume, days, distance ou time.',
                },
                'is_active': {'type': 'boolean', 'default': true},
              },
              'required': const [],
            },
          },
        };
      case 'get_goal_progress_history':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description': 'Progresso de uma meta nos últimos N períodos.',
            'parameters': {
              'type': 'object',
              'properties': {
                'goal_id': {'type': 'string'},
                'periods_back': {'type': 'integer', 'default': 6},
              },
              'required': ['goal_id'],
            },
          },
        };
      default:
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description': 'Tool sem schema definido.',
            'parameters': {
              'type': 'object',
              'properties': const {},
              'required': const [],
            },
          },
        };
    }
  }

  AiToolResult _ok(Map<String, dynamic> data) =>
      AiToolResult(ok: true, data: data);

  // ===========================================================================
  // TOOL CATALOG
  // ===========================================================================

  static const List<Map<String, String>> _tools = [
    {'name': 'list_recent_workouts', 'description': 'List recent workouts'},
    {'name': 'get_workout_detail', 'description': 'Get workout details'},
    {'name': 'list_exercises', 'description': 'List exercises'},
    {'name': 'get_exercise_history', 'description': 'Exercise history'},
    {'name': 'get_exercise_personal_records', 'description': 'Exercise PRs'},
    {
      'name': 'get_weekly_volume_breakdown',
      'description': 'Weekly volume by category',
    },
    {'name': 'get_progress_trend', 'description': 'Exercise progress trend'},
    {'name': 'list_routines', 'description': 'List routines'},
    {'name': 'get_routine_detail', 'description': 'Routine details'},
    {'name': 'list_body_measurements', 'description': 'List body measurements'},
    {'name': 'get_cardio_summary', 'description': 'Cardio summary'},
    {'name': 'list_goals', 'description': 'List active goals'},
    {
      'name': 'get_goal_progress_history',
      'description': 'Goal progress history',
    },
  ];
}
