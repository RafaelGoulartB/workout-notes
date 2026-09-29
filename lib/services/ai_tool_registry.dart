import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/services/ai_nutrition_tool_service.dart';
import 'package:workout_notes/services/ai_run_tool_service.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_tool_hints.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/services/ai_tool_specs_goals.dart';
import 'package:workout_notes/services/ai_tool_specs_nutrition.dart';
import 'package:workout_notes/services/ai_tool_specs_proposals.dart';
import 'package:workout_notes/services/ai_tool_specs_runs.dart';
import 'package:workout_notes/services/ai_tool_specs_sleep.dart';
import 'package:workout_notes/services/ai_tool_specs_wellness.dart';
import 'package:workout_notes/services/ai_tool_specs_workouts.dart';
import 'package:workout_notes/services/ai_wellness_analytics_service.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';

part 'ai_tool_registry_labels.dart';

/// The model-facing tool catalog: an ordered table of [AiToolSpec]s (schema +
/// handler) grouped per domain in `ai_tool_specs_<domain>.dart`.
class AiToolRegistry {
  final DatabaseHelper db;
  final GoalRepository goalRepo;
  final AiWellnessAnalyticsService wellness;
  final AiNutritionToolService nutrition;
  final AiSleepToolService sleep;
  final AiWorkoutToolService workouts;
  final AiRunToolService runs;
  late final List<AiToolSpec> _specs;
  late final Map<String, AiToolSpec> _specsByName;

  AiToolRegistry({
    DatabaseHelper? db,
    GoalRepository? goalRepo,
    AiWellnessAnalyticsService? wellness,
    AiNutritionToolService? nutrition,
    AiSleepToolService? sleep,
    AiWorkoutToolService? workouts,
    AiRunToolService? runs,
  }) : db = db ?? DatabaseHelper.instance,
       goalRepo = goalRepo ?? GoalRepository(),
       wellness = wellness ?? AiWellnessAnalyticsService(db: db),
       nutrition = nutrition ?? AiNutritionToolService(db: db),
       sleep = sleep ?? AiSleepToolService(db: db),
       workouts = workouts ?? AiWorkoutToolService(db: db),
       runs = runs ?? AiRunToolService(db: db) {
    final deps = AiToolDeps(
      db: this.db,
      goalRepo: this.goalRepo,
      wellness: this.wellness,
      nutrition: this.nutrition,
      sleep: this.sleep,
      workouts: this.workouts,
      runs: this.runs,
    );
    // Order is part of the contract: reads first, then the proposal tools.
    _specs = [
      ...workoutToolSpecs(deps),
      ...runToolSpecs(deps),
      ...goalToolSpecs(deps),
      ...sleepToolSpecs(deps),
      ...nutritionToolSpecs(deps),
      ...wellnessToolSpecs(deps),
      ...proposalToolSpecs(),
    ];
    _specsByName = {for (final spec in _specs) spec.name: spec};
  }

  /// OpenAI function-calling JSON schemas for all read tools.
  List<Map<String, dynamic>> openAiReadToolsSchema({Iterable<String>? names}) {
    final selected = names?.toSet();
    return [
      for (final spec in _specs)
        if (!spec.proposal &&
            (selected == null || selected.contains(spec.name)))
          spec.schema,
    ];
  }

  /// All tools available during a chat turn, including guarded proposals.
  ///
  /// The chat sends this full catalog on every request. A stable catalog lets
  /// the model pick by description, re-call a tool with other parameters and
  /// cross domains mid-turn, and keeps the request prefix cacheable by the
  /// provider. Pass [names] only for dedicated flows that intentionally
  /// expose a single tool.
  List<Map<String, dynamic>> openAiChatToolsSchema({
    Iterable<String>? names,
    bool includeRoutineProposal = true,
  }) {
    final selected = names?.toSet();
    return [
      ...openAiReadToolsSchema(names: names),
      if (selected == null || selected.contains('propose_manual_food_creation'))
        _specsByName['propose_manual_food_creation']!.schema,
      if (includeRoutineProposal)
        _specsByName['propose_routine_change']!.schema,
    ];
  }

  /// Names of every read tool in the catalog.
  Set<String> get readToolNames => {
    for (final spec in _specs)
      if (!spec.proposal) spec.name,
  };

  /// Suggests the tools most likely relevant to [query]; see [AiToolHints].
  Set<String> toolNamesForQuery(String query) => AiToolHints.forQuery(query);

  /// Dispatch a read tool call to its handler.
  Future<AiToolResult> executeRead({
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    try {
      final handler = _specsByName[toolName]?.handler;
      if (handler == null) {
        return AiToolResult(
          ok: false,
          code: 'unknown_tool',
          message: 'Tool "$toolName" não reconhecida.',
        );
      }
      return await handler(AiToolArgs(args));
    } on AiToolArgException catch (e) {
      return AiToolResult(ok: false, code: 'invalid_args', message: '$e');
    } catch (e) {
      return AiToolResult(ok: false, code: 'error', message: e.toString());
    }
  }
}
