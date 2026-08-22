import '../database/database_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/ai_message_role.dart';
import '../models/nutrition/ai_food_label_draft.dart';
import '../models/nutrition/ai_manual_food_proposal.dart';
import '../repositories/goal_repository.dart';
import 'ai_nutrition_tool_service.dart';
import 'ai_sleep_tool_service.dart';
import 'ai_wellness_analytics_service.dart';
import 'ai_workout_tool_service.dart';

class AiToolRegistry {
  final DatabaseHelper db;
  final GoalRepository goalRepo;
  final AiWellnessAnalyticsService wellness;
  final AiNutritionToolService nutrition;
  final AiSleepToolService sleep;
  final AiWorkoutToolService workouts;
  final Map<String, Map<String, dynamic>> _schemaCache = {};
  AiToolRegistry({
    DatabaseHelper? db,
    GoalRepository? goalRepo,
    AiWellnessAnalyticsService? wellness,
    AiNutritionToolService? nutrition,
    AiSleepToolService? sleep,
    AiWorkoutToolService? workouts,
  }) : db = db ?? DatabaseHelper.instance,
       goalRepo = goalRepo ?? GoalRepository(),
       wellness = wellness ?? AiWellnessAnalyticsService(db: db),
       nutrition = nutrition ?? AiNutritionToolService(db: db),
       sleep = sleep ?? AiSleepToolService(db: db),
       workouts = workouts ?? AiWorkoutToolService(db: db);

  /// OpenAI function-calling JSON schemas for all read tools.
  List<Map<String, dynamic>> openAiReadToolsSchema({Iterable<String>? names}) {
    final selected = names?.toSet();
    return _tools
        .where((tool) => selected == null || selected.contains(tool['name']))
        .map((tool) => _schemaFor(tool['name'] as String))
        .toList();
  }

  /// All tools available during a chat turn, including guarded proposals.
  List<Map<String, dynamic>> openAiChatToolsSchema({
    Iterable<String>? names,
    bool includeRoutineProposal = true,
    bool includeCapabilityDiscovery = true,
  }) {
    final selected = names?.toSet();
    return [
      ...openAiReadToolsSchema(names: names),
      if (includeCapabilityDiscovery) _schemaFor('discover_app_capabilities'),
      if (selected == null || selected.contains('propose_manual_food_creation'))
        _schemaFor('propose_manual_food_creation'),
      if (includeRoutineProposal) _schemaFor('propose_routine_change'),
    ];
  }

  /// Selects a compact tool catalog for the current user request.
  Set<String> toolNamesForQuery(String query) {
    final text = query.toLowerCase();
    final selected = <String>{};
    bool hasAny(Iterable<String> terms) => terms.any(text.contains);

    final foodCreationIntent =
        RegExp(
          r'\b(criar|crie|cria|cadastrar|cadastre|cadastra|adicionar|adicione|adiciona|incluir|inclua|registrar|registre|salvar|salve|create|register|add)\b',
          caseSensitive: false,
        ).hasMatch(text) &&
        RegExp(
          r'\b(alimento|alimentos|comida|comidas|food|foods|produto alimenticio|produto alimentício)\b',
          caseSensitive: false,
        ).hasMatch(text);
    final manualFoodIntent =
        hasAny(['alimento manual', 'comida manual', 'manual food']) &&
        hasAny(['novo', 'nova', 'adicionar', 'incluir', 'add']);
    if (foodCreationIntent || manualFoodIntent) {
      return {'propose_manual_food_creation'};
    }

    final nutritionTerms = [
      'nutri',
      'caloria',
      'macro',
      'proteina',
      'proteína',
      'carbo',
      'gordura',
      'comida',
      'dieta',
      'ingestao',
      'ingestão',
      'refeicao',
      'refeição',
      'alimento',
      'alimenta',
      'comi',
      'comer',
    ];
    final nutritionIntent = hasAny(nutritionTerms);
    final diaryIntent =
        hasAny([
          'diario alimentar',
          'diário alimentar',
          'diario de alimentacao',
          'diário de alimentação',
          'o que comi',
          'o que eu comi',
          'comi hoje',
          'comi ontem',
          'refeicoes de hoje',
          'refeições de hoje',
          'meal diary',
          'food diary',
        ]) ||
        (nutritionIntent &&
            (hasAny(['hoje', 'ontem', 'nesse dia', 'neste dia']) ||
                RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(text)));
    if (diaryIntent) {
      // The diary already carries day totals, goal, meals, items and every
      // tracked nutrient. Going through the aggregate summary or capability
      // discovery first only adds provider round-trips and failure points.
      return {'get_nutrition_diary_day'};
    }

    final sleepIntent = hasAny([
      'sono',
      'sleep',
      'dormi',
      'dormir',
      'insonia',
      'insônia',
      'acordei',
      'acordar',
      'despertar',
      'despertares',
      'latencia',
      'latência',
      'barulho',
      'ruido',
      'ruído',
      'ronc',
      'ronq',
      'qualidade da gravacao',
      'qualidade da gravação',
    ]);
    final workoutIntent = hasAny([
      'treino',
      'workout',
      'sessao',
      'sessão',
      'musculacao',
      'musculação',
      'academia',
      'malhei',
      'malhar',
    ]);
    final sleepPerformanceIntent =
        workoutIntent ||
        hasAny(['desempenho', 'performance', 'volume', 'carga']);
    final sleepDetailIntent =
        sleepIntent &&
        (hasAny([
              'hoje',
              'ontem',
              'esta noite',
              'essa noite',
              'ultima noite',
              'última noite',
              'nesse dia',
              'neste dia',
              'profundo',
              'acordei',
              'acordar',
              'despert',
              'latencia',
              'latência',
              'barulho',
              'ruido',
              'ruído',
              'ronc',
              'ronq',
              'gravacao',
              'gravação',
            ]) ||
            RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(text));
    final sleepHistoryIntent =
        sleepIntent &&
        hasAny([
          'historico',
          'histórico',
          'noite por noite',
          'ultimas noites',
          'últimas noites',
          'por dia',
        ]);
    final sleepProfileIntent =
        sleepIntent &&
        hasAny([
          'meta',
          'objetivo',
          'configuracao',
          'configuração',
          'modo de monitoramento',
          'perfil',
        ]);
    if (sleepProfileIntent &&
        !sleepPerformanceIntent &&
        !sleepHistoryIntent &&
        !sleepDetailIntent) {
      return {'get_sleep_profile'};
    }
    if (sleepHistoryIntent &&
        !sleepPerformanceIntent &&
        !sleepProfileIntent &&
        !sleepDetailIntent) {
      return {'get_sleep_history'};
    }
    if (sleepIntent) {
      if (sleepDetailIntent) {
        selected.add('get_sleep_night_detail');
      } else {
        selected.add('get_sleep_summary');
      }
      if (sleepHistoryIntent) selected.add('get_sleep_history');
      if (sleepProfileIntent) selected.add('get_sleep_profile');
      if (sleepPerformanceIntent) {
        selected.add('analyze_sleep_performance');
      }
      if (sleepDetailIntent && !sleepPerformanceIntent) return selected;
    }
    if (nutritionIntent) {
      selected.add('get_nutrition_summary');
    }
    if (hasAny([
      'micronutriente',
      'vitamina',
      'mineral',
      'fibra',
      'acucar',
      'açúcar',
      'sodio',
      'sódio',
      'potassio',
      'potássio',
      'calcio',
      'cálcio',
      'ferro',
      'magnesio',
      'magnésio',
      'zinco',
      'b12',
    ])) {
      selected.add('get_micronutrient_summary');
    }
    if (nutritionIntent &&
        hasAny([
          'historico',
          'histórico',
          'ultimos dias',
          'últimos dias',
          'por dia',
          'evolucao',
          'evolução',
          'tendencia',
          'tendência',
        ])) {
      selected.add('get_nutrition_history');
    }
    if (hasAny([
      'biblioteca de alimentos',
      'meus alimentos',
      'alimento favorito',
      'alimentos favoritos',
      'alimento recente',
      'alimentos recentes',
      'food library',
    ])) {
      selected.add('search_food_library');
    }
    if (hasAny([
      'refeicao salva',
      'refeição salva',
      'refeicoes salvas',
      'refeições salvas',
      'saved meal',
      'saved meals',
    ])) {
      selected.add('list_saved_meals');
    }
    if (nutritionIntent &&
        hasAny(['meta', 'objetivo', 'configuracao', 'configuração'])) {
      selected.add('get_nutrition_profile');
    }
    if (hasAny(['recuper', 'fadiga', 'cansa', 'readiness', 'descanso'])) {
      selected.addAll({
        'get_weekly_recovery_trend',
        'get_sleep_summary',
        'get_nutrition_summary',
        'list_recent_workouts',
      });
    }
    if (hasAny([
      'peso',
      'weight',
      'medida',
      'corpo',
      'composicao',
      'composição',
    ])) {
      selected.addAll({
        'list_body_measurements',
        'analyze_nutrition_body_trend',
      });
    }
    if (hasAny(['rotina', 'routine', 'ficha', 'divisao', 'divisão'])) {
      selected.addAll({
        'list_routines',
        'get_routine_detail',
        'list_exercises',
      });
    }
    final workoutHistoryIntent =
        workoutIntent &&
        (hasAny([
              'historico',
              'histórico',
              'periodo',
              'período',
              'ultimos treinos',
              'últimos treinos',
              'entre ',
              'por dia',
              'planejado',
              'planejados',
              'em andamento',
            ]) ||
            RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(text));
    final trainingAnalysisIntent =
        workoutIntent &&
        hasAny([
          'rpe',
          'esforco',
          'esforço',
          'densidade',
          'frequencia',
          'frequência',
          'consistencia',
          'consistência',
          'duracao',
          'duração',
          'volume',
          'grupo muscular',
          'categoria',
          'resumo',
          'analise',
          'análise',
        ]);
    if (workoutIntent) {
      if (workoutHistoryIntent) {
        selected.addAll({'get_workout_history', 'get_workout_detail'});
      } else {
        selected.addAll({'list_recent_workouts', 'get_workout_detail'});
      }
      if (trainingAnalysisIntent) selected.add('get_training_summary');
    }
    final exerciseIntent = hasAny([
      'exercicio',
      'exercício',
      'serie',
      'série',
      'carga',
      'repeticao',
      'repetição',
      'superset',
      'aquecimento',
    ]);
    if (exerciseIntent) {
      selected.addAll({
        'list_exercises',
        'get_exercise_detail',
        'get_exercise_history',
      });
    }
    if (hasAny([
      'equipamento',
      'descanso padrao',
      'descanso padrão',
      'incremento de carga',
      'nota do exercicio',
      'nota do exercício',
    ])) {
      selected.addAll({'list_exercises', 'get_exercise_detail'});
    }
    if (hasAny(['recorde', 'record', 'pr ', '1rm'])) {
      selected.addAll({'list_exercises', 'get_exercise_personal_records'});
    }
    if (hasAny(['volume'])) {
      selected.addAll({'get_weekly_volume_breakdown', 'get_training_summary'});
    }
    if (hasAny([
      'progresso',
      'progressao',
      'progressão',
      'evolucao',
      'evolução',
    ])) {
      selected.addAll({'list_exercises', 'get_progress_trend'});
    }
    if (hasAny(['cardio', 'corrida', 'correr', 'distancia', 'distância'])) {
      selected.add('get_cardio_summary');
    }
    if (hasAny([
      'plano de corrida',
      'planos de corrida',
      'longao',
      'longão',
      'tiro',
      'tiros',
      'intervalado',
      'fartlek',
      'meia maratona',
      'maratona',
      'run plan',
      'long run',
    ])) {
      selected.addAll({
        'list_run_plans',
        'get_run_plan_detail',
        'get_run_schedule',
      });
    }
    if (!sleepIntent &&
        !nutritionIntent &&
        hasAny(['meta', 'goal', 'objetivo'])) {
      selected.addAll({'list_goals', 'get_goal_progress_history'});
    }
    if (hasAny([
      'como estou',
      'meus dados',
      'meu desempenho',
      'resumo geral',
      'visao geral',
      'visão geral',
    ])) {
      selected.addAll({
        'list_recent_workouts',
        'get_sleep_summary',
        'get_nutrition_summary',
        'get_weekly_recovery_trend',
        'list_goals',
      });
    }
    return selected;
  }

  /// Returns only tools that can naturally continue the calls just executed.
  /// This avoids billing the entire first-round schema catalog repeatedly.
  Set<String> followUpToolNames(
    Iterable<String> calledNames, {
    required bool routineIntent,
  }) {
    final next = <String>{};
    for (final name in calledNames) {
      switch (name) {
        case 'list_recent_workouts':
        case 'get_workout_history':
          next.add('get_workout_detail');
          break;
        case 'list_exercises':
          if (routineIntent) {
            next.addAll({'list_routines', 'get_routine_detail'});
          } else {
            next.addAll({
              'get_exercise_detail',
              'get_exercise_history',
              'get_exercise_personal_records',
              'get_progress_trend',
            });
          }
          break;
        case 'list_routines':
          next.add('get_routine_detail');
          break;
        case 'list_run_plans':
          next.addAll({'get_run_plan_detail', 'get_run_schedule'});
          break;
        case 'get_run_plan_detail':
          next.add('get_run_schedule');
          break;
        case 'get_cardio_summary':
          next.add('get_run_schedule');
          break;
        case 'get_routine_detail':
          next.add('list_exercises');
          break;
        case 'list_goals':
          next.add('get_goal_progress_history');
          break;
        case 'get_sleep_summary':
          next.addAll({
            'get_sleep_night_detail',
            'get_sleep_history',
            'get_sleep_profile',
          });
          break;
        case 'get_sleep_history':
          next.add('get_sleep_night_detail');
          break;
        case 'get_nutrition_summary':
          next.addAll({
            'get_nutrition_diary_day',
            'get_nutrition_history',
            'get_micronutrient_summary',
            'get_nutrition_profile',
          });
          break;
        case 'get_nutrition_diary_day':
        case 'search_food_library':
          next.add('get_food_detail');
          break;
        case 'list_saved_meals':
          next.add('get_saved_meal_detail');
          break;
      }
    }
    return next;
  }

  /// Human-friendly label for a tool name (used in chat bubbles).
  String humanLabel(String toolName, [AppLocalizations? l10n]) {
    if (l10n != null) {
      switch (toolName) {
        case 'list_recent_workouts':
          return l10n.aiToolListRecentWorkouts;
        case 'get_workout_history':
          return l10n.aiToolWorkoutHistory;
        case 'get_workout_detail':
          return l10n.aiToolGetWorkoutDetail;
        case 'list_exercises':
          return l10n.aiToolListExercises;
        case 'get_exercise_detail':
          return l10n.aiToolExerciseDetail;
        case 'get_exercise_history':
          return l10n.aiToolGetExerciseHistory;
        case 'get_exercise_personal_records':
          return l10n.aiToolGetExerciseRecords;
        case 'get_weekly_volume_breakdown':
          return l10n.aiToolWeeklyVolume;
        case 'get_training_summary':
          return l10n.aiToolTrainingSummary;
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
        case 'get_sleep_summary':
          return l10n.aiToolSleepSummary;
        case 'get_sleep_night_detail':
          return l10n.aiToolSleepNightDetail;
        case 'get_sleep_history':
          return l10n.aiToolSleepHistory;
        case 'get_sleep_profile':
          return l10n.aiToolSleepProfile;
        case 'get_nutrition_summary':
          return l10n.aiToolNutritionSummary;
        case 'get_nutrition_diary_day':
          return l10n.aiToolNutritionDiaryDay;
        case 'get_nutrition_history':
          return l10n.aiToolNutritionHistory;
        case 'get_micronutrient_summary':
          return l10n.aiToolMicronutrientSummary;
        case 'search_food_library':
          return l10n.aiToolSearchFoodLibrary;
        case 'get_food_detail':
          return l10n.aiToolFoodDetail;
        case 'list_saved_meals':
          return l10n.aiToolListSavedMeals;
        case 'get_saved_meal_detail':
          return l10n.aiToolSavedMealDetail;
        case 'get_nutrition_profile':
          return l10n.aiToolNutritionProfile;
        case 'analyze_sleep_performance':
          return l10n.aiToolSleepPerformance;
        case 'analyze_nutrition_body_trend':
          return l10n.aiToolNutritionBodyTrend;
        case 'get_weekly_recovery_trend':
          return l10n.aiToolRecoveryTrend;
        case 'propose_routine_change':
          return l10n.aiToolProposeRoutineChange;
        case 'propose_manual_food_creation':
          return l10n.aiToolProposeManualFoodCreation;
        case 'discover_app_capabilities':
          return l10n.aiToolDiscoverAppCapabilities;
      }
    }
    switch (toolName) {
      case 'list_recent_workouts':
        return 'Listando treinos recentes';
      case 'get_workout_history':
        return 'Consultando histórico de treinos';
      case 'get_workout_detail':
        return 'Detalhando treino';
      case 'list_exercises':
        return 'Buscando exercícios';
      case 'get_exercise_detail':
        return 'Detalhando exercício';
      case 'get_exercise_history':
        return 'Histórico do exercício';
      case 'get_exercise_personal_records':
        return 'Recordes pessoais';
      case 'get_weekly_volume_breakdown':
        return 'Volume semanal';
      case 'get_training_summary':
        return 'Analisando período de treinos';
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
      case 'list_run_plans':
        return 'Listando planos de corrida';
      case 'get_run_plan_detail':
        return 'Detalhando plano de corrida';
      case 'get_run_schedule':
        return 'Consultando corridas planejadas';
      case 'list_goals':
        return 'Metas ativas';
      case 'get_goal_progress_history':
        return 'Histórico da meta';
      case 'get_sleep_summary':
        return 'Analisando sono recente';
      case 'get_sleep_night_detail':
        return 'Consultando detalhes da noite';
      case 'get_sleep_history':
        return 'Consultando histórico de sono';
      case 'get_sleep_profile':
        return 'Consultando perfil de sono';
      case 'get_nutrition_summary':
        return 'Analisando nutrição';
      case 'get_nutrition_diary_day':
        return 'Consultando diário alimentar';
      case 'get_nutrition_history':
        return 'Consultando histórico nutricional';
      case 'get_micronutrient_summary':
        return 'Analisando micronutrientes';
      case 'search_food_library':
        return 'Buscando alimentos';
      case 'get_food_detail':
        return 'Detalhando alimento';
      case 'list_saved_meals':
        return 'Listando refeições salvas';
      case 'get_saved_meal_detail':
        return 'Detalhando refeição salva';
      case 'get_nutrition_profile':
        return 'Consultando perfil nutricional';
      case 'analyze_sleep_performance':
        return 'Relacionando sono e desempenho';
      case 'analyze_nutrition_body_trend':
        return 'Relacionando ingestão e peso';
      case 'get_weekly_recovery_trend':
        return 'Calculando recuperação semanal';
      case 'propose_routine_change':
        return 'Preparando proposta de rotina';
      case 'propose_manual_food_creation':
        return 'Preparando alimento manual';
      case 'discover_app_capabilities':
        return 'Selecionando recursos do app';
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
        case 'discover_app_capabilities':
          return _ok(_discoverAppCapabilities(args));
        case 'propose_manual_food_creation':
          return _prepareManualFoodProposal(args);
        case 'list_recent_workouts':
          return _ok(await _listRecentWorkouts(args));
        case 'get_workout_history':
          return _ok(await _getWorkoutHistory(args));
        case 'get_workout_detail':
          final id = _nullableString(args['workout_id'] ?? args['workoutId']);
          if (id == null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'workout_id é obrigatório.',
            );
          }
          final detail = await workouts.workoutDetail(id);
          if (detail == null) {
            return const AiToolResult(
              ok: false,
              code: 'not_found',
              message: 'Treino não encontrado.',
            );
          }
          return _ok(detail);
        case 'list_exercises':
          return _ok(await _listExercises(args));
        case 'get_exercise_detail':
          final id = _nullableString(args['exercise_id'] ?? args['exerciseId']);
          if (id == null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'exercise_id é obrigatório.',
            );
          }
          final detail = await workouts.exerciseDetail(id);
          if (detail == null) {
            return const AiToolResult(
              ok: false,
              code: 'not_found',
              message: 'Exercício não encontrado.',
            );
          }
          return _ok(detail);
        case 'get_exercise_history':
          if (_nullableString(args['exercise_id'] ?? args['exerciseId']) ==
              null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'exercise_id é obrigatório.',
            );
          }
          return _ok(await _getExerciseHistory(args));
        case 'get_exercise_personal_records':
          if (_nullableString(args['exercise_id'] ?? args['exerciseId']) ==
              null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'exercise_id é obrigatório.',
            );
          }
          return _ok(await _getExercisePRs(args));
        case 'get_weekly_volume_breakdown':
          return _ok(await _getWeeklyVolumeBreakdown(args));
        case 'get_progress_trend':
          if (_nullableString(args['exercise_id'] ?? args['exerciseId']) ==
              null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'exercise_id é obrigatório.',
            );
          }
          return _ok(await _getProgressTrend(args));
        case 'get_training_summary':
          return _ok(await _getTrainingSummary(args));
        case 'list_routines':
          return _ok(await _listRoutines(args));
        case 'get_routine_detail':
          return _ok(await _getRoutineDetail(args));
        case 'list_body_measurements':
          return _ok(await _listBodyMeasurements(args));
        case 'get_cardio_summary':
          return _ok(await _getCardioSummary(args));
        case 'list_run_plans':
          return _ok(
            await workouts.listRunPlans(
              includeArchived:
                  args['include_archived'] as bool? ??
                  args['includeArchived'] as bool? ??
                  false,
            ),
          );
        case 'get_run_plan_detail':
          final planId = _nullableString(args['plan_id'] ?? args['planId']);
          if (planId == null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'plan_id é obrigatório.',
            );
          }
          return _ok(await workouts.runPlanDetail(planId));
        case 'get_run_schedule':
          return _ok(
            await workouts.runSchedule(
              startDate: _nullableString(
                args['start_date'] ?? args['startDate'],
              ),
              endDate: _nullableString(args['end_date'] ?? args['endDate']),
            ),
          );
        case 'list_goals':
          return _ok(await _listGoals(args));
        case 'get_goal_progress_history':
          return _ok(await _getGoalProgressHistory(args));
        case 'get_sleep_summary':
          return _ok(
            await wellness.sleepSummary(
              days: _boundedInt(args, 'days', 14, 3, 90),
            ),
          );
        case 'get_sleep_night_detail':
          return _ok(
            await sleep.nightDetail(
              date: _nullableString(args['date'] ?? args['day']),
            ),
          );
        case 'get_sleep_history':
          return _ok(
            await sleep.history(
              days: _boundedInt(args, 'days', 30, 1, 31),
              endDate: _nullableString(args['end_date'] ?? args['endDate']),
            ),
          );
        case 'get_sleep_profile':
          return _ok(await sleep.profile());
        case 'get_nutrition_summary':
          return _ok(
            await wellness.nutritionSummary(
              days: _boundedInt(args, 'days', 14, 3, 90),
            ),
          );
        case 'get_nutrition_diary_day':
          return _ok(
            await nutrition.diaryDay(
              date: _nullableString(args['date'] ?? args['day']),
            ),
          );
        case 'get_nutrition_history':
          return _ok(
            await nutrition.history(
              days: _boundedInt(args, 'days', 30, 1, 31),
              endDate: _nullableString(args['end_date'] ?? args['endDate']),
            ),
          );
        case 'get_micronutrient_summary':
          return _ok(
            await nutrition.micronutrientSummary(
              days: _boundedInt(args, 'days', 30, 1, 90),
            ),
          );
        case 'search_food_library':
          return _ok(
            await nutrition.searchFoods(
              query: _nullableString(args['query'] ?? args['search']),
              favoritesOnly:
                  args['favorites_only'] == true ||
                  args['favoritesOnly'] == true,
              recentOnly:
                  args['recent_only'] == true || args['recentOnly'] == true,
              limit: _boundedInt(args, 'limit', 15, 1, 30),
            ),
          );
        case 'get_food_detail':
          final foodId = _nullableString(args['food_id'] ?? args['foodId']);
          if (foodId == null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'food_id é obrigatório.',
            );
          }
          return _ok(await nutrition.foodDetail(foodId));
        case 'list_saved_meals':
          return _ok(
            await nutrition.listSavedMeals(
              limit: _boundedInt(args, 'limit', 20, 1, 50),
            ),
          );
        case 'get_saved_meal_detail':
          final savedMealId = _nullableString(
            args['saved_meal_id'] ?? args['savedMealId'],
          );
          if (savedMealId == null) {
            return const AiToolResult(
              ok: false,
              code: 'invalid_args',
              message: 'saved_meal_id é obrigatório.',
            );
          }
          return _ok(await nutrition.savedMealDetail(savedMealId));
        case 'get_nutrition_profile':
          return _ok(await nutrition.profile());
        case 'analyze_sleep_performance':
          return _ok(
            await wellness.sleepPerformance(
              days: _boundedInt(args, 'days', 42, 7, 90),
            ),
          );
        case 'analyze_nutrition_body_trend':
          return _ok(
            await wellness.nutritionBodyTrend(
              days: _boundedInt(args, 'days', 84, 14, 180),
            ),
          );
        case 'get_weekly_recovery_trend':
          return _ok(
            await wellness.weeklyRecoveryTrend(
              weeks: _boundedInt(args, 'weeks', 8, 2, 12),
            ),
          );
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
    return workouts.recent(limit: _boundedInt(args, 'limit', 8, 1, 20));
  }

  Future<Map<String, dynamic>> _getWorkoutHistory(Map<String, dynamic> args) =>
      workouts.history(
        startDate: _isoDate(args['start_date'] ?? args['startDate']),
        endDate: _isoDate(args['end_date'] ?? args['endDate']),
        status: _nullableString(args['status']) ?? 'all',
        page: _boundedInt(args, 'page', 1, 1, 100000),
        pageSize: _boundedInt(args, 'page_size', 20, 1, 50),
      );

  Future<Map<String, dynamic>> _listExercises(Map<String, dynamic> args) async {
    return workouts.listExercises(
      categoryId: _nullableString(args['category_id'] ?? args['categoryId']),
      search: _nullableString(args['name_contains'] ?? args['search']),
      favorites: args['is_favorite'] as bool?,
      limit: _boundedInt(args, 'limit', 20, 1, 50),
    );
  }

  Future<Map<String, dynamic>> _getExerciseHistory(
    Map<String, dynamic> args,
  ) async {
    return workouts.exerciseHistory(
      _nullableString(args['exercise_id'] ?? args['exerciseId']) ?? '',
      startDate: _isoDate(args['start_date'] ?? args['startDate']),
      endDate: _isoDate(args['end_date'] ?? args['endDate']),
      limit: _boundedInt(args, 'limit', 12, 1, 40),
    );
  }

  Future<Map<String, dynamic>> _getExercisePRs(
    Map<String, dynamic> args,
  ) async {
    return workouts.exerciseRecords(
      _nullableString(args['exercise_id'] ?? args['exerciseId']) ?? '',
    );
  }

  Future<Map<String, dynamic>> _getWeeklyVolumeBreakdown(
    Map<String, dynamic> args,
  ) async {
    return workouts.weeklyVolume(weeks: _boundedInt(args, 'weeks', 8, 2, 16));
  }

  Future<Map<String, dynamic>> _getProgressTrend(
    Map<String, dynamic> args,
  ) async {
    return workouts.progressTrend(
      _nullableString(args['exercise_id'] ?? args['exerciseId']) ?? '',
      weeks: _boundedInt(args, 'weeks', 8, 2, 16),
    );
  }

  Future<Map<String, dynamic>> _getTrainingSummary(Map<String, dynamic> args) {
    final endDate = _isoDate(args['end_date'] ?? args['endDate']);
    final explicitStart = _isoDate(args['start_date'] ?? args['startDate']);
    final days = _boundedInt(args, 'days', 30, 1, 366);
    final effectiveEnd = DateTime.tryParse(endDate ?? '') ?? DateTime.now();
    final effectiveStart =
        explicitStart ??
        effectiveEnd
            .subtract(Duration(days: days - 1))
            .toIso8601String()
            .substring(0, 10);
    return workouts.trainingSummary(
      startDate: effectiveStart,
      endDate: endDate ?? effectiveEnd.toIso8601String().substring(0, 10),
    );
  }

  Future<Map<String, dynamic>> _listRoutines(Map<String, dynamic> args) async {
    final search = (args['name_contains'] as String?)?.toLowerCase();
    final rawDb = await db.database;
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
    Map<String, dynamic> args,
  ) async {
    final id =
        (args['routine_id'] as String?) ?? (args['routineId'] as String?);
    if (id == null) return {'error': 'routine_id é obrigatório'};
    final r = await db.getRoutine(id);
    if (r == null) return {'error': 'rotina não encontrada'};
    final rawDb = await db.database;
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

  Future<Map<String, dynamic>> _listBodyMeasurements(
    Map<String, dynamic> args,
  ) async {
    final type = args['type'] as String?;
    final limit = _boundedInt(args, 'limit', 20, 1, 50);
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
    return workouts.cardioSummary(weeks: _boundedInt(args, 'weeks', 4, 2, 16));
  }

  Future<Map<String, dynamic>> _listGoals(Map<String, dynamic> args) async {
    final scope = args['scope'] as String?;
    final metric = args['metric'] as String?;
    final activeOnly = (args['is_active'] as bool?) ?? true;
    final goals = await goalRepo.getAll(activeOnly: activeOnly);
    final filtered = goals.where(
      (g) =>
          (scope == null || g.scope.value == scope) &&
          (metric == null || g.metric.value == metric),
    );
    final out = await Future.wait(
      filtered.map((g) async {
        try {
          final p = await goalRepo.getProgress(g);
          return <String, dynamic>{
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
          };
        } catch (_) {
          return <String, dynamic>{
            'id': g.id,
            'title': g.title,
            'scope': g.scope.value,
            'metric': g.metric.value,
            'period': g.period.value,
            'targetValue': g.targetValue,
          };
        }
      }),
    );
    return {'goals': out};
  }

  Future<Map<String, dynamic>> _getGoalProgressHistory(
    Map<String, dynamic> args,
  ) async {
    final id = (args['goal_id'] as String?) ?? (args['goalId'] as String?);
    if (id == null) return {'error': 'goal_id é obrigatório'};
    final periods = _boundedInt(args, 'periods', 6, 1, 12);
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

  Map<String, dynamic> _discoverAppCapabilities(Map<String, dynamic> args) {
    final requested = (args['capabilities'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final names = <String>{};
    for (final capability in requested) {
      names.addAll(switch (capability) {
        'workouts' => {
          'list_recent_workouts',
          'get_workout_history',
          'get_workout_detail',
          'get_weekly_volume_breakdown',
          'get_training_summary',
        },
        'exercises' => {
          'list_exercises',
          'get_exercise_detail',
          'get_exercise_history',
          'get_exercise_personal_records',
          'get_progress_trend',
        },
        'routines' => {'list_routines', 'get_routine_detail'},
        'body' => {'list_body_measurements'},
        'cardio' => {'get_cardio_summary'},
        'run_plans' => {
          'list_run_plans',
          'get_run_plan_detail',
          'get_run_schedule',
        },
        'goals' => {'list_goals', 'get_goal_progress_history'},
        'sleep' => {
          'get_sleep_summary',
          'get_sleep_night_detail',
          'get_sleep_history',
          'get_sleep_profile',
          'analyze_sleep_performance',
        },
        'nutrition' => {
          'get_nutrition_summary',
          'get_nutrition_diary_day',
          'get_nutrition_history',
          'get_micronutrient_summary',
          'get_nutrition_profile',
          'analyze_nutrition_body_trend',
        },
        'nutrition_diary' => {
          'get_nutrition_diary_day',
          'get_nutrition_history',
        },
        'micronutrients' => {'get_micronutrient_summary'},
        'food_library' => {'search_food_library', 'get_food_detail'},
        'saved_meals' => {'list_saved_meals', 'get_saved_meal_detail'},
        'food_creation' => {'propose_manual_food_creation'},
        'recovery' => {
          'get_weekly_recovery_trend',
          'get_sleep_summary',
          'get_nutrition_summary',
          'list_recent_workouts',
        },
        'routine_changes' => {
          'list_exercises',
          'list_routines',
          'get_routine_detail',
          'propose_routine_change',
        },
        _ => const <String>{},
      });
    }
    return {
      'capabilities': requested.toList(),
      'tools': names.toList(),
      'instruction':
          'Use as ferramentas retornadas que forem necessárias para concluir a solicitação.',
    };
  }

  // ===========================================================================
  // SCHEMA GENERATION
  // ===========================================================================

  Map<String, dynamic> _schemaFor(String name) =>
      _schemaCache.putIfAbsent(name, () => _buildSchemaFor(name));

  Map<String, dynamic> _buildSchemaFor(String name) {
    switch (name) {
      case 'discover_app_capabilities':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Descobre ferramentas do app por capacidade. Use quando dados do app ou uma ação ajudariam, mas a ferramenta necessária ainda não estiver disponível.',
            'parameters': {
              'type': 'object',
              'properties': {
                'capabilities': {
                  'type': 'array',
                  'items': {
                    'type': 'string',
                    'enum': [
                      'workouts',
                      'exercises',
                      'routines',
                      'body',
                      'cardio',
                      'run_plans',
                      'goals',
                      'sleep',
                      'nutrition',
                      'nutrition_diary',
                      'micronutrients',
                      'food_library',
                      'saved_meals',
                      'food_creation',
                      'recovery',
                      'routine_changes',
                    ],
                  },
                  'description':
                      'Uma ou mais capacidades relevantes para a tarefa.',
                },
              },
              'required': ['capabilities'],
            },
          },
        };
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
                  'description': 'Quantos treinos retornar (padrão 8).',
                  'default': 8,
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_workout_history':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Histórico paginado de treinos, inclusive períodos antigos. Permite filtrar por data e status; cada item distingue treino concluído, em andamento e planejado e resume somente séries concluídas sem aquecimento.',
            'parameters': {
              'type': 'object',
              'properties': {
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
                'limit': {'type': 'integer', 'default': 20},
              },
              'required': const [],
            },
          },
        };
      case 'get_exercise_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Perfil completo de um exercício: categoria, sistema energético, tipo, equipamento, notas, favorito, descanso padrão, incremento de carga e estatísticas de uso concluído.',
            'parameters': {
              'type': 'object',
              'properties': {
                'exercise_id': {'type': 'string'},
              },
              'required': ['exercise_id'],
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
                'limit': {'type': 'integer', 'default': 12},
                'start_date': {'type': 'string'},
                'end_date': {'type': 'string'},
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
      case 'get_training_summary':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Analisa um período de treino: frequência e status, duração, calorias, sensação, séries, volume, repetições, distância, tempo, RPE, densidade, categorias e exercícios mais usados. Métricas de desempenho usam apenas treinos e séries concluídos, sem aquecimento.',
            'parameters': {
              'type': 'object',
              'properties': {
                'days': {
                  'type': 'integer',
                  'minimum': 1,
                  'maximum': 366,
                  'default': 30,
                },
                'start_date': {'type': 'string'},
                'end_date': {'type': 'string'},
              },
              'required': const [],
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
                'limit': {'type': 'integer', 'default': 20},
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
      case 'list_run_plans':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Lista planos de corrida (longão, tiros, ritmo) com objetivo '
                'e número de semanas.',
            'parameters': {
              'type': 'object',
              'properties': {
                'include_archived': {'type': 'boolean', 'default': false},
              },
              'required': const [],
            },
          },
        };
      case 'get_run_plan_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Detalha um plano de corrida: semanas, treinos e etapas '
                '(aquecimento, tiros, recuperação, desaquecimento).',
            'parameters': {
              'type': 'object',
              'properties': {
                'plan_id': {'type': 'string'},
              },
              'required': const ['plan_id'],
            },
          },
        };
      case 'get_run_schedule':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Corridas planejadas em um intervalo de datas, com status e a '
                'corrida registrada quando já foi concluída.',
            'parameters': {
              'type': 'object',
              'properties': {
                'start_date': {
                  'type': 'string',
                  'description': 'yyyy-MM-dd. Padrão: hoje.',
                },
                'end_date': {
                  'type': 'string',
                  'description': 'yyyy-MM-dd. Padrão: 4 semanas à frente.',
                },
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
      case 'get_sleep_summary':
        return _windowToolSchema(
          name,
          'Resumo agregado do sono recente: duração, eficiência, cobertura e regularidade de horários. Use antes de opinar sobre sono.',
          defaultValue: 14,
          minimum: 3,
          maximum: 90,
        );
      case 'get_sleep_night_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Detalha uma noite de sono por data local: duração registrada, real, estimada e efetiva com sua origem; horários; tempo na cama; comentário; estágios; latência; despertares; eficiência; confiança; ruído e qualidade do sinal. Use para perguntas sobre hoje, ontem ou uma noite específica. Dados acústicos são estimativas não clínicas e não diagnosticam ronco ou apneia.',
            'parameters': {
              'type': 'object',
              'properties': {
                'date': {
                  'type': 'string',
                  'description':
                      'Data local no formato YYYY-MM-DD. Se omitida, usa a data local atual.',
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_sleep_history':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Histórico diário paginado do sono. Retorna todas as noites registradas na janela, durações separadas e sua origem efetiva, horários, eficiência e disponibilidade de estágios. Datas sem registro ficam ausentes.',
            'parameters': {
              'type': 'object',
              'properties': {
                'days': {
                  'type': 'integer',
                  'minimum': 1,
                  'maximum': 31,
                  'default': 30,
                },
                'end_date': {
                  'type': 'string',
                  'description':
                      'Último dia da janela em YYYY-MM-DD; o padrão é hoje.',
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_sleep_profile':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Retorna a meta diária de sono, modo padrão de monitoramento, contagens de noites manuais e monitoradas, cobertura de estágios e comparação da média com a meta em todo o histórico e nos últimos 30 dias. Não expõe segredos de missões ou alarmes.',
            'parameters': {
              'type': 'object',
              'properties': const <String, dynamic>{},
              'required': const [],
            },
          },
        };
      case 'get_nutrition_summary':
        return _windowToolSchema(
          name,
          'Resumo agregado de calorias, macros, gorduras, fibras, açúcares e micronutrientes, com meta ativa, cobertura e qualidade dos registros. Para itens/refeições de um dia use get_nutrition_diary_day.',
          defaultValue: 14,
          minimum: 3,
          maximum: 90,
        );
      case 'get_nutrition_diary_day':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Retorna o diário alimentar completo de um dia: refeições, alimentos, quantidades, origem, calorias, macros, gorduras, fibras, açúcares, sódio e todos os micronutrientes registrados. Preserva null como valor não informado.',
            'parameters': {
              'type': 'object',
              'properties': {
                'date': {
                  'type': 'string',
                  'description':
                      'Data local no formato YYYY-MM-DD. O padrão é hoje.',
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_nutrition_history':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Histórico diário completo de nutrientes. Retorna totais e cobertura por nutriente para cada dia registrado; dias sem registro ficam ausentes. Use end_date para paginar janelas antigas.',
            'parameters': {
              'type': 'object',
              'properties': {
                'days': {
                  'type': 'integer',
                  'minimum': 1,
                  'maximum': 31,
                  'default': 30,
                },
                'end_date': {
                  'type': 'string',
                  'description':
                      'Último dia da janela em YYYY-MM-DD; padrão hoje.',
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_micronutrient_summary':
        return _windowToolSchema(
          name,
          'Análise dedicada de fibras, açúcares, sódio, potássio, cálcio, ferro, magnésio, zinco e vitaminas A, C, D e B12. Inclui cobertura, médias somente em dias reportados e principais alimentos-fonte.',
          defaultValue: 30,
          minimum: 1,
          maximum: 90,
        );
      case 'search_food_library':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Busca na biblioteca local de alimentos do usuário. Retorna IDs, origem, favorito, uso recente e a variante nutricional principal. Use get_food_detail com o ID para todas as variantes e porções.',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': 'Nome ou marca; vazio lista a biblioteca.',
                },
                'favorites_only': {'type': 'boolean', 'default': false},
                'recent_only': {'type': 'boolean', 'default': false},
                'limit': {
                  'type': 'integer',
                  'minimum': 1,
                  'maximum': 30,
                  'default': 15,
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_food_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Detalha um alimento da biblioteca pelo ID: metadados, todas as variantes, nutrientes padronizados, nutrientes extras e porções/conversões.',
            'parameters': {
              'type': 'object',
              'properties': {
                'food_id': {
                  'type': 'string',
                  'description': 'ID retornado por search_food_library.',
                },
              },
              'required': ['food_id'],
            },
          },
        };
      case 'list_saved_meals':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Lista refeições-modelo salvas pelo usuário, com totais nutricionais atuais e IDs para detalhamento.',
            'parameters': {
              'type': 'object',
              'properties': {
                'limit': {
                  'type': 'integer',
                  'minimum': 1,
                  'maximum': 50,
                  'default': 20,
                },
              },
              'required': const [],
            },
          },
        };
      case 'get_saved_meal_detail':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Detalha uma refeição salva: porções, ingredientes, quantidades, referências de alimento e todos os nutrientes calculáveis.',
            'parameters': {
              'type': 'object',
              'properties': {
                'saved_meal_id': {
                  'type': 'string',
                  'description': 'ID retornado por list_saved_meals.',
                },
              },
              'required': ['saved_meal_id'],
            },
          },
        };
      case 'get_nutrition_profile':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Retorna a meta diária ativa e seu histórico, perfil usado na sugestão de meta (idade, sexo, altura, peso, atividade e razões de macros), tipos de refeição e contagens do diário, biblioteca e refeições salvas.',
            'parameters': {
              'type': 'object',
              'properties': const <String, dynamic>{},
              'required': const [],
            },
          },
        };
      case 'analyze_sleep_performance':
        return _windowToolSchema(
          name,
          'Calcula associações observacionais entre sono e volume/sensação dos treinos em datas pareadas. Não implica causalidade.',
          defaultValue: 42,
          minimum: 7,
          maximum: 90,
        );
      case 'analyze_nutrition_body_trend':
        return _windowToolSchema(
          name,
          'Relaciona ingestão semanal de calorias/macros com medidas de peso corporal e informa cobertura dos dados.',
          defaultValue: 84,
          minimum: 14,
          maximum: 180,
        );
      case 'get_weekly_recovery_trend':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Tendência semanal não clínica de recuperação, combinando apenas componentes disponíveis de sono, regularidade e sensação dos treinos.',
            'parameters': {
              'type': 'object',
              'properties': {
                'weeks': {
                  'type': 'integer',
                  'description': 'Semanas (2 a 12; padrão 8).',
                  'default': 8,
                  'minimum': 2,
                  'maximum': 12,
                },
              },
              'required': const [],
            },
          },
        };
      case 'propose_routine_change':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'PREPARE A PROPOSTA quando o usuário pedir explicitamente para criar ou editar uma rotina. Não aplica dados: o app mostrará a prévia para aprovação. Para criar, primeiro use list_exercises e use IDs retornados. Para editar, primeiro use list_routines e get_routine_detail; mantenha os source_*_id retornados. Envie a árvore final inteira da rotina.',
            'parameters': {
              'type': 'object',
              'properties': {
                'action': {
                  'type': 'string',
                  'enum': ['create', 'update'],
                },
                'routine_id': {'type': 'string'},
                'routine': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'notes': {'type': 'string'},
                    'days': {
                      'type': 'array',
                      'items': {
                        'type': 'object',
                        'properties': {
                          'source_day_id': {'type': 'string'},
                          'name': {'type': 'string'},
                          'notes': {'type': 'string'},
                          'exercises': {
                            'type': 'array',
                            'items': {
                              'type': 'object',
                              'properties': {
                                'source_routine_exercise_id': {
                                  'type': 'string',
                                },
                                'exercise_id': {'type': 'string'},
                                'rest_time_seconds': {'type': 'integer'},
                                'superset_group_id': {'type': 'string'},
                                'sets': {
                                  'type': 'array',
                                  'items': {
                                    'type': 'object',
                                    'properties': {
                                      'source_set_id': {'type': 'string'},
                                      'weight': {'type': 'number'},
                                      'reps': {'type': 'integer'},
                                      'distance': {'type': 'number'},
                                      'time_seconds': {'type': 'integer'},
                                      'is_warmup': {'type': 'boolean'},
                                    },
                                    'required': const [],
                                  },
                                },
                              },
                              'required': ['exercise_id', 'sets'],
                            },
                          },
                        },
                        'required': ['name', 'exercises'],
                      },
                    },
                  },
                  'required': ['name', 'days'],
                },
              },
              'required': ['action', 'routine'],
            },
          },
        };
      case 'propose_manual_food_creation':
        return {
          'type': 'function',
          'function': {
            'name': name,
            'description':
                'Prepare a prévia de um NOVO ALIMENTO MANUAL quando o usuário pedir para criar ou cadastrar um alimento. Identifique o alimento descrito e preencha o máximo possível de calorias, macronutrientes, gorduras, fibras, açúcares, sódio, micronutrientes e porções usuais. Use valores típicos estimados quando não houver rótulo exato e deixe de fora somente o que não puder ser identificado com segurança. Não salva nada: o app exibirá uma prévia e, após aprovação, abrirá o formulário manual preenchido para revisão e salvamento pelo usuário.',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {
                  'type': 'string',
                  'description': 'Nome claro e específico do alimento.',
                },
                'brand': {
                  'type': 'string',
                  'description':
                      'Marca somente quando informada ou identificada; omita se desconhecida.',
                },
                'barcode': {
                  'type': 'string',
                  'description':
                      'Código de barras somente quando informado; nunca invente.',
                },
                'reference_amount': {
                  'type': 'number',
                  'description':
                      'Quantidade à qual todos os nutrientes se referem; prefira 100.',
                },
                'reference_unit': {
                  'type': 'string',
                  'description':
                      'Unidade da referência; prefira g ou ml conforme o alimento.',
                },
                'per': {
                  'type': 'object',
                  'properties': _manualFoodNutrientProperties,
                  'required': const [],
                },
                'servings': {
                  'type': 'array',
                  'description':
                      'Porções comuns úteis para registrar o alimento.',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'label': {'type': 'string'},
                      'quantity': {'type': 'number'},
                      'unit': {'type': 'string'},
                      'grams_equivalent': {'type': 'number'},
                      'ml_equivalent': {'type': 'number'},
                    },
                    'required': ['label', 'quantity', 'unit'],
                  },
                },
                'notes': {
                  'type': 'string',
                  'description':
                      'Resumo curto das estimativas, preparo ou variedade assumidos; não exponha raciocínio interno.',
                },
              },
              'required': [
                'name',
                'reference_amount',
                'reference_unit',
                'per',
                'servings',
              ],
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

  Map<String, dynamic> _windowToolSchema(
    String name,
    String description, {
    required int defaultValue,
    required int minimum,
    required int maximum,
  }) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': {
          'days': {
            'type': 'integer',
            'description': 'Janela em dias ($minimum a $maximum).',
            'default': defaultValue,
            'minimum': minimum,
            'maximum': maximum,
          },
        },
        'required': const [],
      },
    },
  };

  int _boundedInt(
    Map<String, dynamic> args,
    String key,
    int fallback,
    int minimum,
    int maximum,
  ) {
    final raw = args[key] ?? args['${key}_back'];
    final value = raw is num ? raw.toInt() : int.tryParse('$raw');
    return (value ?? fallback).clamp(minimum, maximum);
  }

  String? _isoDate(Object? value) {
    final text = _nullableString(value);
    if (text == null) return null;
    final date = DateTime.tryParse(text);
    if (date == null) return null;
    return date.toIso8601String().substring(0, 10);
  }

  AiToolResult _ok(Map<String, dynamic> data) =>
      AiToolResult(ok: true, data: data);

  AiToolResult _prepareManualFoodProposal(Map<String, dynamic> args) {
    try {
      final draft = AiFoodLabelDraft.fromJson(args);
      if (draft.referenceAmount <= 0 || draft.referenceUnit.trim().isEmpty) {
        return const AiToolResult(
          ok: false,
          code: 'invalid_args',
          message: 'A referência nutricional deve ter quantidade e unidade.',
        );
      }
      final proposal = AiManualFoodProposal(
        draft: draft,
        notes: _nullableString(args['notes']),
      );
      return _ok(proposal.toJson());
    } on FormatException catch (error) {
      return AiToolResult(
        ok: false,
        code: 'invalid_args',
        message: error.message,
      );
    }
  }

  // ===========================================================================
  // TOOL CATALOG
  // ===========================================================================

  static const List<Map<String, String>> _tools = [
    {'name': 'list_recent_workouts', 'description': 'List recent workouts'},
    {'name': 'get_workout_history', 'description': 'Paginated workout history'},
    {'name': 'get_workout_detail', 'description': 'Get workout details'},
    {'name': 'list_exercises', 'description': 'List exercises'},
    {'name': 'get_exercise_detail', 'description': 'Exercise profile'},
    {'name': 'get_exercise_history', 'description': 'Exercise history'},
    {'name': 'get_exercise_personal_records', 'description': 'Exercise PRs'},
    {
      'name': 'get_weekly_volume_breakdown',
      'description': 'Weekly volume by category',
    },
    {'name': 'get_progress_trend', 'description': 'Exercise progress trend'},
    {'name': 'get_training_summary', 'description': 'Training period summary'},
    {'name': 'list_routines', 'description': 'List routines'},
    {'name': 'get_routine_detail', 'description': 'Routine details'},
    {'name': 'list_body_measurements', 'description': 'List body measurements'},
    {'name': 'get_cardio_summary', 'description': 'Cardio summary'},
    {'name': 'list_run_plans', 'description': 'List running plans'},
    {'name': 'get_run_plan_detail', 'description': 'Running plan details'},
    {'name': 'get_run_schedule', 'description': 'Planned runs in a window'},
    {'name': 'list_goals', 'description': 'List active goals'},
    {
      'name': 'get_goal_progress_history',
      'description': 'Goal progress history',
    },
    {'name': 'get_sleep_summary', 'description': 'Recent sleep summary'},
    {'name': 'get_sleep_night_detail', 'description': 'Sleep night details'},
    {'name': 'get_sleep_history', 'description': 'Paginated sleep history'},
    {'name': 'get_sleep_profile', 'description': 'Sleep goal and profile'},
    {
      'name': 'get_nutrition_summary',
      'description': 'Complete nutrition summary',
    },
    {'name': 'get_nutrition_diary_day', 'description': 'Nutrition diary day'},
    {'name': 'get_nutrition_history', 'description': 'Nutrition history'},
    {
      'name': 'get_micronutrient_summary',
      'description': 'Micronutrient summary',
    },
    {'name': 'search_food_library', 'description': 'Search food library'},
    {'name': 'get_food_detail', 'description': 'Food details'},
    {'name': 'list_saved_meals', 'description': 'List saved meals'},
    {'name': 'get_saved_meal_detail', 'description': 'Saved meal details'},
    {'name': 'get_nutrition_profile', 'description': 'Nutrition profile'},
    {
      'name': 'analyze_sleep_performance',
      'description': 'Sleep and workout performance association',
    },
    {
      'name': 'analyze_nutrition_body_trend',
      'description': 'Nutrition and body-weight trend',
    },
    {
      'name': 'get_weekly_recovery_trend',
      'description': 'Weekly recovery trend',
    },
  ];

  static const Map<String, dynamic> _manualFoodNutrientProperties = {
    'calories': {'type': 'number'},
    'protein_g': {'type': 'number'},
    'carbs_g': {'type': 'number'},
    'fat_g': {'type': 'number'},
    'saturated_fat_g': {'type': 'number'},
    'monounsaturated_fat_g': {'type': 'number'},
    'polyunsaturated_fat_g': {'type': 'number'},
    'trans_fat_g': {'type': 'number'},
    'fiber_g': {'type': 'number'},
    'sugars_g': {'type': 'number'},
    'sodium_mg': {'type': 'number'},
    'potassium_mg': {'type': 'number'},
    'calcium_mg': {'type': 'number'},
    'iron_mg': {'type': 'number'},
    'magnesium_mg': {'type': 'number'},
    'zinc_mg': {'type': 'number'},
    'vitamin_a_ug': {'type': 'number'},
    'vitamin_c_mg': {'type': 'number'},
    'vitamin_d_ug': {'type': 'number'},
    'vitamin_b12_ug': {'type': 'number'},
  };
}

String? _nullableString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
