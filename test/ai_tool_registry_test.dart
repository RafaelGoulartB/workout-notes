import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';

import 'support/ai_test_db.dart';

/// A workout service whose query blows up with a message that must never
/// reach the model.
class _ExplodingWorkoutService extends AiWorkoutToolService {
  @override
  Future<Map<String, dynamic>> history({
    String? startDate,
    String? endDate,
    String status = 'completed',
    int limit = 10,
    int page = 1,
  }) => throw StateError('no such table: secret_table (SELECT * FROM x)');
}

const _expectedTools = <String, AiToolDomain>{
  'get_workout_history': AiToolDomain.workouts,
  'get_workout_detail': AiToolDomain.workouts,
  'list_exercises': AiToolDomain.workouts,
  'get_exercise_history': AiToolDomain.workouts,
  'get_personal_records': AiToolDomain.workouts,
  'get_training_summary': AiToolDomain.workouts,
  'list_routines': AiToolDomain.workouts,
  'get_routine_detail': AiToolDomain.workouts,
  'list_body_measurements': AiToolDomain.body,
  'get_profile': AiToolDomain.body,
  'list_run_activities': AiToolDomain.running,
  'get_run_activity_detail': AiToolDomain.running,
  'get_run_progress': AiToolDomain.running,
  'get_cardio_summary': AiToolDomain.running,
  'get_run_achievements': AiToolDomain.running,
  'get_run_plan': AiToolDomain.running,
  'get_run_schedule': AiToolDomain.running,
  'list_goals': AiToolDomain.goals,
  'get_sleep': AiToolDomain.sleep,
  'analyze_sleep_performance': AiToolDomain.sleep,
  'get_weekly_recovery_trend': AiToolDomain.sleep,
  'get_nutrition': AiToolDomain.nutrition,
  'search_food_library': AiToolDomain.nutrition,
  'list_saved_meals': AiToolDomain.nutrition,
  'analyze_nutrition_body_trend': AiToolDomain.nutrition,
  'get_training_plan': AiToolDomain.planning,
};

void main() {
  late AiToolRegistry registry;

  setUp(() async {
    await installAiTestDb();
    registry = AiToolRegistry();
  });

  tearDown(uninstallAiTestDb);

  group('catalog', () {
    test('has the consolidated read tools, each in its domain', () {
      expect(registry.readSpecs, hasLength(_expectedTools.length));
      expect(registry.readToolNames, _expectedTools.keys.toSet());
      for (final spec in registry.readSpecs) {
        expect(spec.proposal, isFalse, reason: spec.name);
        expect(spec.handler, isNotNull, reason: spec.name);
        expect(spec.domain, _expectedTools[spec.name], reason: spec.name);
        expect(spec.domain, isNot(AiToolDomain.core), reason: spec.name);
      }
    });

    test('tool names are snake_case verb_noun', () {
      final pattern = RegExp(r'^(get|list|search|analyze)(_[a-z]+)+$');
      for (final name in registry.readToolNames) {
        expect(pattern.hasMatch(name), isTrue, reason: name);
      }
    });

    test('every schema is portable and fully described', () {
      for (final tool in registry.readToolsSchema()) {
        expect(tool['type'], 'function');
        final function = tool['function'] as Map<String, dynamic>;
        final name = function['name'] as String;
        expect(function['description'], isA<String>(), reason: name);
        expect((function['description'] as String).length, lessThan(260));
        final parameters = function['parameters'] as Map<String, dynamic>?;
        if (parameters == null) continue; // no-argument tool
        expect(parameters['type'], 'object', reason: name);
        final properties = parameters['properties'] as Map<String, dynamic>;
        expect(properties, isNotEmpty, reason: '$name: omit empty parameters');
        if (parameters.containsKey('required')) {
          final required = (parameters['required'] as List).cast<String>();
          expect(required, isNotEmpty, reason: '$name: omit empty required');
          expect(properties.keys, containsAll(required), reason: name);
        }
        for (final entry in properties.entries) {
          final spec = entry.value as Map<String, dynamic>;
          final where = '$name.${entry.key}';
          expect(RegExp(r'^[a-z]+(_[a-z]+)*$').hasMatch(entry.key), isTrue);
          expect(spec['description'], isA<String>(), reason: where);
          expect(spec.containsKey('default'), isFalse, reason: where);
          expect(spec['type'], isA<String>(), reason: where);
          if (spec.containsKey('enum')) {
            expect(spec['enum'], isA<List>(), reason: where);
            expect(spec['enum'], isNotEmpty, reason: where);
          }
          if (entry.key.endsWith('_date') || entry.key == 'date') {
            expect(
              (spec['description'] as String).contains('YYYY-MM-DD'),
              isTrue,
              reason: '$where must say YYYY-MM-DD',
            );
          }
          if (entry.key == 'limit') {
            expect(spec['maximum'], isA<int>(), reason: where);
          }
          if (entry.key == 'days') {
            expect(spec['minimum'], isA<int>(), reason: where);
            expect(spec['maximum'], isA<int>(), reason: where);
          }
        }
      }
    });

    test('parameter names are consistent across tools', () {
      const vocabulary = {
        'days',
        'weeks',
        'start_date',
        'end_date',
        'date',
        'limit',
        'page',
        'detail',
        'status',
        'type',
        'period',
        'review',
        'group_by',
        'sort',
        'query',
        'name_contains',
        'latest_per_type',
        'favorites_only',
        'history_periods',
        'from_week',
        'activity_type',
        'scope',
        'metric',
      };
      for (final tool in registry.readToolsSchema()) {
        final function = tool['function'] as Map<String, dynamic>;
        final properties =
            ((function['parameters'] as Map?)?['properties'] as Map?)
                ?.cast<String, dynamic>() ??
            const {};
        for (final key in properties.keys) {
          final isId = key.endsWith('_id');
          expect(
            isId || vocabulary.contains(key),
            isTrue,
            reason: '${function['name']} has an off-vocabulary param "$key"',
          );
        }
      }
    });

    test('body measurement types and goal filters are enums', () {
      Map<String, dynamic> properties(String tool) {
        final spec = registry.readSpecs.firstWhere((s) => s.name == tool);
        final function = spec.schema['function'] as Map<String, dynamic>;
        return ((function['parameters'] as Map)['properties'] as Map)
            .cast<String, dynamic>();
      }

      expect(
        (properties('list_body_measurements')['type'] as Map)['enum'],
        containsAll(['weight', 'bodyFat', 'waist', 'bloodPressure']),
      );
      expect(
        (properties('list_goals')['scope'] as Map)['enum'],
        ['anaerobic', 'aerobic'],
      );
      expect(
        (properties('list_goals')['metric'] as Map)['enum'],
        ['volume', 'days', 'distance', 'time'],
      );
    });

    test('readToolsSchema filters by domain, is stable and cached', () {
      final all = registry.readToolsSchema();
      expect(all, hasLength(_expectedTools.length));
      expect(identical(all, registry.readToolsSchema()), isTrue);
      final names = [
        for (final tool in all) (tool['function'] as Map)['name'] as String,
      ];
      expect(names, [for (final spec in registry.readSpecs) spec.name]);

      final sleepOnly = registry.readToolsSchema(
        domains: {AiToolDomain.sleep},
      );
      expect(
        sleepOnly.map((tool) => (tool['function'] as Map)['name']),
        [
          'get_sleep',
          'analyze_sleep_performance',
          'get_weekly_recovery_trend',
        ],
      );
      expect(
        identical(
          sleepOnly,
          registry.readToolsSchema(domains: {AiToolDomain.sleep}),
        ),
        isTrue,
      );
      expect(registry.readToolsSchema(domains: const {}), isEmpty);
      final bodyAndGoals = registry.readToolsSchema(
        domains: {AiToolDomain.goals, AiToolDomain.body},
      );
      expect(
        bodyAndGoals.map((tool) => (tool['function'] as Map)['name']),
        ['list_body_measurements', 'get_profile', 'list_goals'],
      );
    });

    test('the whole compact catalog stays within 11000 characters', () {
      final length = jsonEncode(registry.readToolsSchema()).length;
      expect(length, lessThanOrEqualTo(11000), reason: '$length chars');
      expect(registry.readToolsSchemaCharacters(), length);
    });
  });

  group('error contract', () {
    test('unknown tool', () async {
      final result = await registry.executeRead(
        toolName: 'no_such_tool',
        args: const {},
      );
      expect(result.ok, isFalse);
      expect(result.code, 'unknown_tool');
      expect(result.message, contains('no_such_tool'));
    });

    test('bad date: invalid_args with param, expected and received', () async {
      final result = await registry.executeRead(
        toolName: 'get_workout_history',
        args: const {'start_date': '01/09/2026'},
      );
      expect(result.ok, isFalse);
      expect(result.code, 'invalid_args');
      expect(
        result.message,
        'start_date: expected YYYY-MM-DD, got "01/09/2026"',
      );
      expect(result.details, {
        'param': 'start_date',
        'expected': 'YYYY-MM-DD',
        'received': '01/09/2026',
      });
    });

    test('bad enum and wrong types never leak a Dart error', () async {
      final status = await registry.executeRead(
        toolName: 'get_workout_history',
        args: const {'status': 'weird'},
      );
      expect(status.code, 'invalid_args');
      expect(status.details?['expected'], contains('completed'));

      final count = await registry.executeRead(
        toolName: 'get_workout_history',
        args: const {'limit': 'lots'},
      );
      expect(count.code, 'invalid_args');
      expect(count.message, isNot(contains('subtype')));

      final flag = await registry.executeRead(
        toolName: 'list_body_measurements',
        args: const {'latest_per_type': 'maybe'},
      );
      expect(flag.code, 'invalid_args');
    });

    test('missing required argument', () async {
      final result = await registry.executeRead(
        toolName: 'get_workout_detail',
        args: const {'workout_id': ''},
      );
      expect(result.code, 'invalid_args');
      expect(result.details?['param'], 'workout_id');
    });

    test('unknown ids are not_found with a hint', () async {
      final expectations = {
        'get_workout_detail': {'workout_id': 'nope'},
        'get_exercise_history': {'exercise_id': 'nope'},
        'get_routine_detail': {'routine_id': 'nope'},
        'get_run_activity_detail': {'activity_id': 'nope'},
        'get_run_plan': {'plan_id': 'nope'},
      };
      for (final entry in expectations.entries) {
        final result = await registry.executeRead(
          toolName: entry.key,
          args: entry.value,
        );
        expect(result.ok, isFalse, reason: entry.key);
        expect(result.code, 'not_found', reason: entry.key);
        expect(result.hint, startsWith('call '), reason: entry.key);
      }
      final routine = await registry.executeRead(
        toolName: 'get_routine_detail',
        args: const {'routine_id': 'nope'},
      );
      expect(routine.toMap(), {
        'ok': false,
        'code': 'not_found',
        'message': 'routine not found',
        'hint': 'call list_routines to get valid ids',
      });
    });

    test('unexpected failures are internal_error without leaking', () async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      addTearDown(() => debugPrint = original);
      final failing = AiToolRegistry(workouts: _ExplodingWorkoutService());
      final result = await failing.executeRead(
        toolName: 'get_workout_history',
        args: const {},
      );
      expect(result.toMap(), {
        'ok': false,
        'code': 'internal_error',
        'message': 'query failed',
      });
      expect(printed.join('\n'), contains('secret_table'));
    });

    test('out-of-range integers are clamped and reported', () async {
      final result = await registry.executeRead(
        toolName: 'get_workout_history',
        args: const {'limit': 500},
      );
      expect(result.ok, isTrue);
      final applied = (result.data as Map)['applied'] as Map;
      expect(applied['limit'], 30);
      expect(applied['adjusted'], {
        'limit': {'requested': 500, 'used': 30},
      });
    });

    test('blank strings mean absent', () async {
      final result = await registry.executeRead(
        toolName: 'list_body_measurements',
        args: const {'type': '', 'start_date': ' ', 'limit': 5},
      );
      expect(result.ok, isTrue);
    });
  });

  test('results never carry null values or boilerplate keys', () async {
    final result = await registry.executeRead(
      toolName: 'get_profile',
      args: const {},
    );
    final encoded = jsonEncode(result.toMap());
    for (final key in const [
      'nullSemantics',
      'dataSemantics',
      'interpretationWarning',
      'privacy',
      'pairingRule',
    ]) {
      expect(encoded, isNot(contains(key)));
    }
    expect(encoded, isNot(contains('null')));
  });
}
