import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/services/ai_nutrition_tool_service.dart';
import 'package:workout_notes/services/ai_run_tool_service.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_wellness_analytics_service.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';

/// A required argument was missing or blank. The registry turns this into an
/// `invalid_args` [AiToolResult] so handlers can stay linear.
class AiToolArgException implements Exception {
  final String key;
  const AiToolArgException(this.key);

  @override
  String toString() => '$key é obrigatório.';
}

/// Shared, forgiving argument readers for tool handlers.
///
/// Models are inconsistent about naming, so every reader accepts the
/// documented snake_case key and its camelCase spelling.
class AiToolArgs {
  final Map<String, dynamic> raw;
  const AiToolArgs(this.raw);

  dynamic operator [](String key) => raw[key];

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

  /// Trimmed non-empty string under [key], its camelCase spelling or [alt].
  String? string(String key, {String? alt}) => nullableString(
    raw[key] ?? raw[_camel(key)] ?? (alt == null ? null : raw[alt]),
  );

  /// Like [string], but throws [AiToolArgException] when missing.
  String requiredString(String key) {
    final value = string(key);
    if (value == null) throw AiToolArgException(key);
    return value;
  }

  /// `yyyy-MM-dd` for a parseable date under [key]; null otherwise.
  String? isoDate(String key) {
    final text = string(key);
    if (text == null) return null;
    final date = DateTime.tryParse(text);
    if (date == null) return null;
    return date.toIso8601String().substring(0, 10);
  }

  /// Integer clamped to [minimum]..[maximum]; also reads `${key}_back`.
  int boundedInt(String key, int fallback, int minimum, int maximum) {
    final value = raw[key] ?? raw['${key}_back'];
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback).clamp(minimum, maximum);
  }

  bool flag(String key) => raw[key] == true || raw[_camel(key)] == true;
}

String? nullableString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

AiToolResult aiToolOk(Map<String, dynamic> data) =>
    AiToolResult(ok: true, data: data);

typedef AiToolHandler = Future<AiToolResult> Function(AiToolArgs args);

/// One entry of the model-facing tool catalog: its OpenAI function schema and
/// the handler that executes it. Proposal tools that are not executed through
/// the registry have a null [handler].
class AiToolSpec {
  final String name;

  /// Full `{type: function, function: {...}}` entry, built once.
  final Map<String, dynamic> schema;
  final AiToolHandler? handler;

  /// True for tools that only prepare a guarded proposal (never read data).
  final bool proposal;

  const AiToolSpec._(this.name, this.schema, this.handler, this.proposal);

  factory AiToolSpec({
    required String name,
    required String description,
    Map<String, dynamic> properties = const <String, dynamic>{},
    List<String> required = const [],
    AiToolHandler? handler,
    bool proposal = false,
  }) => AiToolSpec._(
    name,
    {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': required,
        },
      },
    },
    handler,
    proposal,
  );

  /// Tool with a single `days` window argument.
  factory AiToolSpec.window({
    required String name,
    required String description,
    required int defaultValue,
    required int minimum,
    required int maximum,
    required AiToolHandler handler,
  }) => AiToolSpec(
    name: name,
    description: description,
    properties: {
      'days': {
        'type': 'integer',
        'description': 'Janela em dias ($minimum a $maximum).',
        'default': defaultValue,
        'minimum': minimum,
        'maximum': maximum,
      },
    },
    handler: handler,
  );
}

/// Services the tool handlers read from. Built once by the registry.
class AiToolDeps {
  final DatabaseHelper db;
  final GoalRepository goalRepo;
  final AiWellnessAnalyticsService wellness;
  final AiNutritionToolService nutrition;
  final AiSleepToolService sleep;
  final AiWorkoutToolService workouts;
  final AiRunToolService runs;

  const AiToolDeps({
    required this.db,
    required this.goalRepo,
    required this.wellness,
    required this.nutrition,
    required this.sleep,
    required this.workouts,
    required this.runs,
  });
}
