import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// How the chat shows a tool call: a localized noun-phrase label, an icon and
/// a one-line summary of the arguments (`last 7 days`, `2026-09-01 → 09-30`,
/// `page 2`). Replaces the old `humanLabel` extension and its Portuguese
/// fallback table; tools it does not know get a generic label.
abstract final class AiToolPresentation {
  /// Label of [toolName], for example "Sleep" or "Workout history". Covers
  /// the read tools and every proposal / memory tool name.
  static String label(String toolName, AppLocalizations l10n) =>
      switch (toolName) {
        'get_workout_history' => l10n.aiToolWorkoutHistory,
        'get_workout_detail' => l10n.aiToolGetWorkoutDetail,
        'list_exercises' => l10n.aiToolListExercises,
        'get_exercise_history' => l10n.aiToolGetExerciseHistory,
        'get_personal_records' => l10n.aiToolGetExerciseRecords,
        'get_training_summary' => l10n.aiToolTrainingSummary,
        'list_routines' => l10n.aiToolListRoutines,
        'get_routine_detail' => l10n.aiToolGetRoutineDetail,
        'list_body_measurements' => l10n.aiToolBodyMeasurements,
        'get_profile' => l10n.aiToolProfile,
        'list_run_activities' => l10n.aiToolListRunActivities,
        'get_run_activity_detail' => l10n.aiToolRunActivityDetail,
        'get_run_progress' => l10n.aiToolRunProgress,
        'get_cardio_summary' => l10n.aiToolCardioSummary,
        'get_run_achievements' => l10n.aiToolRunAchievements,
        'get_run_plan' => l10n.aiToolRunPlan,
        'get_run_schedule' => l10n.aiToolRunSchedule,
        'list_goals' => l10n.aiToolListGoals,
        'get_sleep' => l10n.aiToolSleep,
        'get_nutrition' => l10n.aiToolNutrition,
        'search_food_library' => l10n.aiToolSearchFoodLibrary,
        'list_saved_meals' => l10n.aiToolListSavedMeals,
        'analyze_sleep_performance' => l10n.aiToolSleepPerformance,
        'analyze_nutrition_body_trend' => l10n.aiToolNutritionBodyTrend,
        'get_weekly_recovery_trend' => l10n.aiToolRecoveryTrend,
        'get_training_plan' => l10n.aiToolTrainingPlan,
        'propose_routine_change' => l10n.aiToolProposeRoutineChange,
        'propose_manual_food_creation' => l10n.aiToolProposeManualFoodCreation,
        'propose_meal_log' => l10n.aiToolProposeMealLog,
        'propose_body_measurement' => l10n.aiToolProposeBodyMeasurement,
        'propose_goal' => l10n.aiToolProposeGoal,
        'propose_nutrition_goal' => l10n.aiToolProposeNutritionGoal,
        'propose_workout_schedule' => l10n.aiToolProposeWorkoutSchedule,
        'propose_run_plan_adjustment' => l10n.aiToolProposeRunPlanAdjustment,
        'save_memory' => l10n.aiToolSaveMemory,
        'delete_memory' => l10n.aiToolDeleteMemory,
        _ => l10n.aiToolGeneric,
      };

  /// Icon of [toolName]; unknown tools get a generic search icon.
  static IconData icon(String toolName) => switch (toolName) {
    'get_workout_history' => Icons.history_rounded,
    'get_workout_detail' => Icons.fitness_center_rounded,
    'list_exercises' => Icons.sports_gymnastics_rounded,
    'get_exercise_history' => Icons.show_chart_rounded,
    'get_personal_records' => Icons.emoji_events_rounded,
    'get_training_summary' => Icons.insights_rounded,
    'list_routines' => Icons.view_list_rounded,
    'get_routine_detail' => Icons.checklist_rounded,
    'list_body_measurements' => Icons.monitor_weight_rounded,
    'get_profile' => Icons.person_rounded,
    'list_run_activities' => Icons.directions_run_rounded,
    'get_run_activity_detail' => Icons.route_rounded,
    'get_run_progress' => Icons.trending_up_rounded,
    'get_cardio_summary' => Icons.monitor_heart_rounded,
    'get_run_achievements' => Icons.military_tech_rounded,
    'get_run_plan' => Icons.event_note_rounded,
    'get_run_schedule' => Icons.calendar_month_rounded,
    'list_goals' => Icons.flag_rounded,
    'get_sleep' => Icons.bedtime_rounded,
    'get_nutrition' => Icons.restaurant_rounded,
    'search_food_library' => Icons.local_dining_rounded,
    'list_saved_meals' => Icons.bookmark_rounded,
    'analyze_sleep_performance' => Icons.nights_stay_rounded,
    'analyze_nutrition_body_trend' => Icons.scale_rounded,
    'get_weekly_recovery_trend' => Icons.battery_charging_full_rounded,
    'get_training_plan' => Icons.timeline_rounded,
    'propose_routine_change' => Icons.edit_note_rounded,
    'propose_manual_food_creation' => Icons.add_circle_outline_rounded,
    'propose_meal_log' => Icons.restaurant_menu_rounded,
    'propose_body_measurement' => Icons.straighten_rounded,
    'propose_goal' => Icons.flag_circle_rounded,
    'propose_nutrition_goal' => Icons.track_changes_rounded,
    'propose_workout_schedule' => Icons.event_available_rounded,
    'propose_run_plan_adjustment' => Icons.tune_rounded,
    'save_memory' => Icons.bookmark_add_rounded,
    'delete_memory' => Icons.bookmark_remove_rounded,
    _ => Icons.search_rounded,
  };

  /// One-line summary of the call's arguments, or null when nothing useful
  /// would be shown (ids and opaque values are never listed).
  static String? argsSummary(
    String toolName,
    Map<String, dynamic> args,
    AppLocalizations l10n,
  ) {
    // Proposal arguments are shown by the proposal card itself.
    if (toolName.startsWith('propose_')) return null;
    String? text(String key) {
      final value = args[key] ?? args[_camel(key)];
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    int? number(String key) {
      final value = args[key] ?? args[_camel(key)];
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    bool flag(String key) {
      final value = args[key] ?? args[_camel(key)];
      return value == true || value == 'true';
    }

    final parts = <String>[];
    final detail = text('detail');
    final startDate = text('start_date');
    final endDate = text('end_date') ?? text('date');
    final days = number('days');
    final weeks = number('weeks');
    final page = number('page');

    // Window: a range wins over a day count; a single day stands alone.
    if (startDate != null && endDate != null) {
      parts.add('$startDate → ${_shortEnd(startDate, endDate)}');
    } else if (startDate != null) {
      parts.add(l10n.aiToolArgsFrom(startDate));
    } else if (days != null && endDate == null) {
      parts.add(l10n.aiToolArgsLastDays(days));
    } else if (days != null) {
      parts.add(l10n.aiToolArgsLastDays(days));
      parts.add(l10n.aiToolArgsUntil(endDate!));
    } else if (endDate != null) {
      final single =
          toolName == 'get_nutrition' && detail == 'day' ||
          toolName == 'get_sleep' && detail == 'night' ||
          toolName == 'get_training_plan';
      parts.add(single ? endDate : l10n.aiToolArgsUntil(endDate));
    }
    if (weeks != null) parts.add(l10n.aiToolArgsLastWeeks(weeks));

    switch (text('period')) {
      case '4_weeks':
        parts.add(l10n.aiToolArgsLastWeeks(4));
      case '12_weeks':
        parts.add(l10n.aiToolArgsLastWeeks(12));
      case 'year':
        parts.add(l10n.aiToolArgsLastYear);
      case 'all':
        parts.add(l10n.aiToolArgsAllTime);
    }

    switch (text('status')) {
      case 'planned':
        parts.add(l10n.aiToolArgsStatusPlanned);
      case 'in_progress':
        parts.add(l10n.aiToolArgsStatusInProgress);
      case 'all':
        parts.add(l10n.aiToolArgsStatusAll);
    }
    switch (text('activity_type')) {
      case 'stationary_bike':
        parts.add(l10n.aiToolArgsStationaryBike);
      case 'all':
        parts.add(l10n.aiToolArgsAllActivities);
    }
    switch (text('group_by')) {
      case 'week':
        parts.add(l10n.aiToolArgsByWeek);
      case 'category':
        parts.add(l10n.aiToolArgsByCategory);
    }
    switch (text('sort')) {
      case 'least_recent':
        parts.add(l10n.aiToolArgsLeastRecent);
      case 'most_recent':
        parts.add(l10n.aiToolArgsMostRecent);
    }
    switch (detail) {
      case 'nightly':
        parts.add(l10n.aiToolArgsNightly);
      case 'daily':
        parts.add(l10n.aiToolArgsDaily);
      case 'micros':
        parts.add(l10n.aiToolArgsMicros);
      case 'foods':
        parts.add(l10n.aiToolArgsTopFoods);
    }
    switch (text('review')) {
      case 'week':
        parts.add(l10n.aiToolArgsWeekReview);
      case 'phase':
        parts.add(l10n.aiToolArgsPhaseReview);
    }
    if (flag('latest_per_type')) parts.add(l10n.aiToolArgsLatestValues);
    final periods = number('history_periods');
    if (periods != null && periods > 0) {
      parts.add(l10n.aiToolArgsPeriods(periods));
    }

    for (final key in const ['query', 'name_contains']) {
      final value = text(key);
      if (value != null) {
        parts.add('"$value"');
        break;
      }
    }
    if (page != null && page > 1) parts.add(l10n.aiToolArgsPage(page));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// `2026-09-30` shown as `09-30` when it falls in the same year as [start].
  static String _shortEnd(String start, String end) =>
      start.length >= 4 &&
          end.length > 5 &&
          start.substring(0, 4) == end.substring(0, 4)
      ? end.substring(5)
      : end;

  static String _camel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts
            .skip(1)
            .map(
              (p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}',
            )
            .join();
  }
}
