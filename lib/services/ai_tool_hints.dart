/// Keyword routing that suggests which tools are most likely relevant to a
/// user message.
///
/// This is only a hint surfaced in the dynamic system block; it never
/// restricts the catalog sent to the model. A single
/// `propose_manual_food_creation` result marks a dedicated manual-food turn.
///
/// Keywords are matched as substrings of the lowercased query, in Portuguese
/// and English (with and without accents, as users type both).
abstract final class AiToolHints {
  static final RegExp _creationVerb = RegExp(
    r'\b(criar|crie|cria|cadastrar|cadastre|cadastra|adicionar|adicione|adiciona|incluir|inclua|registrar|registre|salvar|salve|create|register|add)\b',
    caseSensitive: false,
  );
  static final RegExp _foodNoun = RegExp(
    r'\b(alimento|alimentos|comida|comidas|food|foods|produto alimenticio|produto alimentício)\b',
    caseSensitive: false,
  );
  static final RegExp _isoDate = RegExp(r'\b\d{4}-\d{2}-\d{2}\b');

  static const _manualFood = [
    'alimento manual',
    'comida manual',
    'manual food',
  ];
  static const _manualFoodVerbs = [
    'novo',
    'nova',
    'adicionar',
    'incluir',
    'add',
  ];

  static const _nutrition = [
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
  static const _diary = [
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
  ];
  static const _relativeDay = ['hoje', 'ontem', 'nesse dia', 'neste dia'];

  static const _sleep = [
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
  ];
  static const _workout = [
    'treino',
    'workout',
    'sessao',
    'sessão',
    'musculacao',
    'musculação',
    'academia',
    'malhei',
    'malhar',
  ];
  static const _run = [
    'cardio',
    'corrida',
    'correr',
    'corri',
    'run ',
    'running',
    'pace',
    'ritmo',
    'split',
    'quilometragem',
    'km ',
    '5k',
    '10k',
    'meia maratona',
    'maratona',
    'pedal',
    'pedalei',
    'bicicleta',
    'bike',
  ];
  static const _bike = ['pedal', 'pedalei', 'bicicleta', 'bike', 'ciclismo'];
  static const _performance = ['desempenho', 'performance', 'volume', 'carga'];
  static const _sleepDetail = [
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
  ];
  static const _sleepHistory = [
    'historico',
    'histórico',
    'noite por noite',
    'ultimas noites',
    'últimas noites',
    'por dia',
  ];
  static const _sleepProfile = [
    'meta',
    'objetivo',
    'configuracao',
    'configuração',
    'modo de monitoramento',
    'perfil',
  ];
  static const _micronutrient = [
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
  ];
  static const _nutritionHistory = [
    'historico',
    'histórico',
    'ultimos dias',
    'últimos dias',
    'por dia',
    'evolucao',
    'evolução',
    'tendencia',
    'tendência',
  ];
  static const _foodLibrary = [
    'biblioteca de alimentos',
    'meus alimentos',
    'alimento favorito',
    'alimentos favoritos',
    'alimento recente',
    'alimentos recentes',
    'food library',
  ];
  static const _savedMeals = [
    'refeicao salva',
    'refeição salva',
    'refeicoes salvas',
    'refeições salvas',
    'saved meal',
    'saved meals',
  ];
  static const _goalWords = [
    'meta',
    'objetivo',
    'configuracao',
    'configuração',
  ];
  static const _recovery = [
    'recuper',
    'fadiga',
    'cansa',
    'readiness',
    'descanso',
  ];
  static const _body = [
    'peso',
    'weight',
    'medida',
    'corpo',
    'composicao',
    'composição',
  ];
  static const _routine = ['rotina', 'routine', 'ficha', 'divisao', 'divisão'];
  static const _workoutHistory = [
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
  ];
  static const _trainingAnalysis = [
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
  ];
  static const _exercise = [
    'exercicio',
    'exercício',
    'serie',
    'série',
    'carga',
    'repeticao',
    'repetição',
    'superset',
    'aquecimento',
  ];
  static const _exerciseCatalog = [
    'equipamento',
    'descanso padrao',
    'descanso padrão',
    'incremento de carga',
    'nota do exercicio',
    'nota do exercício',
  ];
  static const _records = ['recorde', 'record', 'pr ', '1rm'];
  static const _volume = ['volume'];
  static const _progress = [
    'progresso',
    'progressao',
    'progressão',
    'evolucao',
    'evolução',
  ];
  static const _runExtra = [
    'distancia corrida',
    'distância corrida',
    'atividade aerobica',
  ];
  static const _runProgress = [
    'progresso',
    'progressao',
    'progressão',
    'evolucao',
    'evolução',
    'tendencia',
    'tendência',
    'volume',
    'frequencia',
    'frequência',
    'consistencia',
    'consistência',
    'semana',
    'mes',
    'mês',
  ];
  static const _runAchievements = [
    'recorde',
    'record',
    'melhor tempo',
    'melhor pace',
    'mais rapida',
    'mais rápida',
    'mais longa',
    'conquista',
    'medalha',
    'pr ',
    '5k',
    '10k',
    'meia maratona',
    'maratona',
  ];
  static const _runPlans = [
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
  ];
  static const _goals = ['meta', 'goal', 'objetivo'];
  static const _overview = [
    'como estou',
    'meus dados',
    'meu desempenho',
    'resumo geral',
    'visao geral',
    'visão geral',
  ];

  static bool _any(String text, List<String> terms) {
    for (final term in terms) {
      if (text.contains(term)) return true;
    }
    return false;
  }

  /// Tools most likely relevant to [query]. Compute once per turn.
  static Set<String> forQuery(String query) {
    final text = query.toLowerCase();
    final selected = <String>{};
    bool hasAny(List<String> terms) => _any(text, terms);

    final foodCreationIntent =
        _creationVerb.hasMatch(text) && _foodNoun.hasMatch(text);
    final manualFoodIntent = hasAny(_manualFood) && hasAny(_manualFoodVerbs);
    if (foodCreationIntent || manualFoodIntent) {
      return {'propose_manual_food_creation'};
    }

    final hasIsoDate = _isoDate.hasMatch(text);
    final nutritionIntent = hasAny(_nutrition);
    final diaryIntent =
        hasAny(_diary) ||
        (nutritionIntent && (hasAny(_relativeDay) || hasIsoDate));
    if (diaryIntent) {
      // The diary already carries day totals, goal, meals, items and every
      // tracked nutrient. Going through the aggregate summary or capability
      // discovery first only adds provider round-trips and failure points.
      return {'get_nutrition_diary_day'};
    }

    final sleepIntent = hasAny(_sleep);
    final workoutIntent = hasAny(_workout);
    final runIntent = hasAny(_run);
    final bikeIntent = hasAny(_bike);
    final sleepPerformanceIntent = workoutIntent || hasAny(_performance);
    final sleepDetailIntent =
        sleepIntent && (hasAny(_sleepDetail) || hasIsoDate);
    final sleepHistoryIntent = sleepIntent && hasAny(_sleepHistory);
    final sleepProfileIntent = sleepIntent && hasAny(_sleepProfile);
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
    if (hasAny(_micronutrient)) {
      selected.add('get_micronutrient_summary');
    }
    if (nutritionIntent && hasAny(_nutritionHistory)) {
      selected.add('get_nutrition_history');
    }
    if (hasAny(_foodLibrary)) {
      selected.add('search_food_library');
    }
    if (hasAny(_savedMeals)) {
      selected.add('list_saved_meals');
    }
    if (nutritionIntent && hasAny(_goalWords)) {
      selected.add('get_nutrition_profile');
    }
    if (hasAny(_recovery)) {
      selected.addAll({
        'get_weekly_recovery_trend',
        'get_sleep_summary',
        'get_nutrition_summary',
        'list_recent_workouts',
      });
    }
    if (hasAny(_body)) {
      selected.addAll({
        'list_body_measurements',
        'analyze_nutrition_body_trend',
      });
    }
    if (hasAny(_routine)) {
      selected.addAll({
        'list_routines',
        'get_routine_detail',
        'list_exercises',
      });
    }
    final workoutHistoryIntent =
        workoutIntent && (hasAny(_workoutHistory) || hasIsoDate);
    final trainingAnalysisIntent = workoutIntent && hasAny(_trainingAnalysis);
    if (workoutIntent) {
      if (workoutHistoryIntent) {
        selected.addAll({'get_workout_history', 'get_workout_detail'});
      } else {
        selected.addAll({'list_recent_workouts', 'get_workout_detail'});
      }
      if (trainingAnalysisIntent) selected.add('get_training_summary');
    }
    if (hasAny(_exercise)) {
      selected.addAll({
        'list_exercises',
        'get_exercise_detail',
        'get_exercise_history',
      });
    }
    if (hasAny(_exerciseCatalog)) {
      selected.addAll({'list_exercises', 'get_exercise_detail'});
    }
    if (!runIntent && hasAny(_records)) {
      selected.addAll({'list_exercises', 'get_exercise_personal_records'});
    }
    if (!runIntent && hasAny(_volume)) {
      selected.addAll({'get_weekly_volume_breakdown', 'get_training_summary'});
    }
    if (!runIntent && hasAny(_progress)) {
      selected.addAll({'list_exercises', 'get_progress_trend'});
    }
    if (runIntent || hasAny(_runExtra)) {
      selected.addAll({
        'get_cardio_summary',
        'list_run_activities',
        'get_run_activity_detail',
      });
      if (!bikeIntent && hasAny(_runProgress)) {
        selected.add('get_run_progress');
      }
      if (!bikeIntent && hasAny(_runAchievements)) {
        selected.add('get_run_achievements');
      }
    }
    if (hasAny(_runPlans)) {
      selected.addAll({
        'list_run_plans',
        'get_run_plan_detail',
        'get_run_schedule',
      });
    }
    if (!sleepIntent && !nutritionIntent && hasAny(_goals)) {
      selected.addAll({'list_goals', 'get_goal_progress_history'});
    }
    if (hasAny(_overview)) {
      selected.addAll({
        'list_recent_workouts',
        'get_cardio_summary',
        'get_run_progress',
        'get_sleep_summary',
        'get_nutrition_summary',
        'get_weekly_recovery_trend',
        'list_goals',
      });
    }
    return selected;
  }
}
