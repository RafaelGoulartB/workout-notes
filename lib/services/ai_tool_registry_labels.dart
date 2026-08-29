part of 'ai_tool_registry.dart';

/// Presentation labels live outside the registry's dispatch and schemas.
extension AiToolRegistryLabels on AiToolRegistry {
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
        case 'list_run_activities':
          return l10n.aiToolListRunActivities;
        case 'get_run_activity_detail':
          return l10n.aiToolRunActivityDetail;
        case 'get_run_progress':
          return l10n.aiToolRunProgress;
        case 'get_run_achievements':
          return l10n.aiToolRunAchievements;
        case 'list_run_plans':
          return l10n.aiToolListRunPlans;
        case 'get_run_plan_detail':
          return l10n.aiToolRunPlanDetail;
        case 'get_run_schedule':
          return l10n.aiToolRunSchedule;
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
      case 'list_run_activities':
        return 'Consultando corridas registradas';
      case 'get_run_activity_detail':
        return 'Detalhando corrida';
      case 'get_run_progress':
        return 'Analisando evolução na corrida';
      case 'get_run_achievements':
        return 'Consultando recordes de corrida';
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
}
