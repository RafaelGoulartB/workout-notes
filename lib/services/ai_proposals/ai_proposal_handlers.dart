import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/body_measurement_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/goal_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/manual_food_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/meal_log_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/nutrition_goal_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/routine_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/run_plan_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/workout_schedule_proposal_handler.dart';

/// Every proposal handler, in the stable order their tools appear in the
/// model's catalog. Adding a kind means adding one handler here.
List<AiProposalHandler> defaultAiProposalHandlers({
  DatabaseHelper? db,
  DateTime Function()? now,
}) => [
  RoutineProposalHandler(db: db),
  ManualFoodProposalHandler(db: db),
  MealLogProposalHandler(db: db, now: now),
  BodyMeasurementProposalHandler(db: db, now: now),
  GoalProposalHandler(db: db),
  NutritionGoalProposalHandler(db: db, now: now),
  WorkoutScheduleProposalHandler(db: db, now: now),
  RunPlanProposalHandler(db: db, now: now),
];
