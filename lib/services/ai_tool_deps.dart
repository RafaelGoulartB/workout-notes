import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/services/ai_goal_tool_service.dart';
import 'package:workout_notes/services/ai_nutrition_tool_service.dart';
import 'package:workout_notes/services/ai_planning_tool_service.dart';
import 'package:workout_notes/services/ai_profile_tool_service.dart';
import 'package:workout_notes/services/ai_run_tool_service.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_wellness_analytics_service.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';

/// Services the tool handlers read from. Built once by the registry.
///
/// Kept apart from `ai_tool_spec.dart` so a service only depends on the
/// argument readers and never on the other services.
class AiToolDeps {
  final DatabaseHelper db;
  final GoalRepository goalRepo;
  final AiGoalToolService goals;
  final AiWellnessAnalyticsService wellness;
  final AiNutritionToolService nutrition;
  final AiSleepToolService sleep;
  final AiWorkoutToolService workouts;
  final AiRunToolService runs;
  final AiPlanningToolService planning;
  final AiProfileToolService profile;

  const AiToolDeps({
    required this.db,
    required this.goalRepo,
    required this.goals,
    required this.wellness,
    required this.nutrition,
    required this.sleep,
    required this.workouts,
    required this.runs,
    required this.planning,
    required this.profile,
  });
}
