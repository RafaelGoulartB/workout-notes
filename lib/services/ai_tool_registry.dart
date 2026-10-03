import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/services/ai_goal_tool_service.dart';
import 'package:workout_notes/services/ai_nutrition_tool_service.dart';
import 'package:workout_notes/services/ai_planning_tool_service.dart';
import 'package:workout_notes/services/ai_profile_tool_service.dart';
import 'package:workout_notes/services/ai_run_tool_service.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/services/ai_tool_specs_body.dart';
import 'package:workout_notes/services/ai_tool_specs_goals.dart';
import 'package:workout_notes/services/ai_tool_specs_nutrition.dart';
import 'package:workout_notes/services/ai_tool_specs_planning.dart';
import 'package:workout_notes/services/ai_tool_specs_runs.dart';
import 'package:workout_notes/services/ai_tool_specs_sleep.dart';
import 'package:workout_notes/services/ai_tool_specs_wellness.dart';
import 'package:workout_notes/services/ai_tool_specs_workouts.dart';
import 'package:workout_notes/services/ai_wellness_analytics_service.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';

/// The model-facing read-tool catalog: an ordered table of [AiToolSpec]s
/// (schema + handler) grouped per domain in `ai_tool_specs_<domain>.dart`.
///
/// The model picks tools by their descriptions; there is no keyword routing.
/// Proposal tools live in `AiProposalService`, not here.
class AiToolRegistry {
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

  late final List<AiToolSpec> _specs;
  late final Map<String, AiToolSpec> _specsByName;
  final Map<String, List<Map<String, dynamic>>> _schemaCache = {};
  final Map<String, int> _schemaLengthCache = {};

  AiToolRegistry({
    DatabaseHelper? db,
    DateTime Function()? now,
    GoalRepository? goalRepo,
    AiGoalToolService? goals,
    AiWellnessAnalyticsService? wellness,
    AiNutritionToolService? nutrition,
    AiSleepToolService? sleep,
    AiWorkoutToolService? workouts,
    AiRunToolService? runs,
    AiPlanningToolService? planning,
    AiProfileToolService? profile,
  }) : db = db ?? DatabaseHelper.instance,
       goalRepo = goalRepo ?? (db ?? DatabaseHelper.instance).goalRepo,
       goals = goals ?? AiGoalToolService(db: db),
       wellness = wellness ?? AiWellnessAnalyticsService(db: db, now: now),
       nutrition = nutrition ?? AiNutritionToolService(db: db, now: now),
       sleep = sleep ?? AiSleepToolService(db: db, now: now),
       workouts = workouts ?? AiWorkoutToolService(db: db, now: now),
       runs = runs ?? AiRunToolService(db: db, now: now),
       planning = planning ?? AiPlanningToolService(db: db, now: now),
       profile = profile ?? AiProfileToolService(db: db, now: now) {
    final deps = AiToolDeps(
      db: this.db,
      goalRepo: this.goalRepo,
      goals: this.goals,
      wellness: this.wellness,
      nutrition: this.nutrition,
      sleep: this.sleep,
      workouts: this.workouts,
      runs: this.runs,
      planning: this.planning,
      profile: this.profile,
    );
    // Order is part of the contract: the catalog must stay byte-stable so the
    // provider's prompt cache keeps working.
    _specs = [
      ...workoutToolSpecs(deps),
      ...bodyToolSpecs(deps),
      ...runToolSpecs(deps),
      ...goalToolSpecs(deps),
      ...sleepToolSpecs(deps),
      ...nutritionToolSpecs(deps),
      ...wellnessToolSpecs(deps),
      ...planningToolSpecs(deps),
    ];
    _specsByName = {for (final spec in _specs) spec.name: spec};
  }

  /// Every read tool, in catalog order.
  List<AiToolSpec> get readSpecs => List.unmodifiable(_specs);

  /// Names of every read tool in the catalog.
  Set<String> get readToolNames => {for (final spec in _specs) spec.name};

  /// OpenAI function-calling schemas of the read tools of [domains] (null =
  /// all), in stable catalog order. Built once per domain set.
  List<Map<String, dynamic>> readToolsSchema({Set<AiToolDomain>? domains}) =>
      _schemaCache.putIfAbsent(
        _domainKey(domains),
        () => List.unmodifiable([
          for (final spec in _specs)
            if (domains == null || domains.contains(spec.domain)) spec.schema,
        ]),
      );

  /// Length of the JSON encoding of [readToolsSchema], measured once.
  int readToolsSchemaCharacters({Set<AiToolDomain>? domains}) =>
      _schemaLengthCache.putIfAbsent(
        _domainKey(domains),
        () => jsonEncode(readToolsSchema(domains: domains)).length,
      );

  static String _domainKey(Set<AiToolDomain>? domains) => domains == null
      ? '*'
      : (domains.map((domain) => domain.name).toList()..sort()).join(',');

  /// Dispatches a read tool call to its handler and shapes the result.
  ///
  /// Every failure has the same shape: `{ok:false, code, message, hint?,
  /// details?}` with `code` one of `unknown_tool`, `invalid_args`,
  /// `not_found`, `internal_error`. Nothing from an exception or SQL leaks to
  /// the model.
  Future<AiToolResult> executeRead({
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final spec = _specsByName[toolName];
    final handler = spec?.handler;
    if (spec == null || handler == null) {
      return AiToolResult(
        ok: false,
        code: 'unknown_tool',
        message: 'unknown tool "$toolName"',
        hint: 'use one of the tools in the catalog',
      );
    }
    try {
      final parsed = AiToolArgs(args);
      final result = await handler(parsed);
      if (!result.ok) return result;
      final data = result.data;
      if (data is! Map) return result;
      final map = Map<String, dynamic>.from(data);
      if (parsed.adjusted.isNotEmpty) {
        final applied = <String, dynamic>{
          ...?(map['applied'] as Map?)?.cast<String, dynamic>(),
          'adjusted': parsed.adjusted,
        };
        map['applied'] = applied;
      }
      return AiToolResult(
        ok: true,
        data: AiToolResultShaper(decimals: spec.decimals).shape(map),
      );
    } on AiToolArgException catch (error) {
      return error.toResult();
    } on AiToolNotFoundException catch (error) {
      return error.toResult();
    } catch (error, stack) {
      debugPrint('AI tool $toolName failed: $error\n$stack');
      return const AiToolResult(
        ok: false,
        code: 'internal_error',
        message: 'query failed',
      );
    }
  }
}
