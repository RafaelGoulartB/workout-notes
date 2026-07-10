import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiToolRegistry registry;

  setUp(() async {
    db = await installAiTestDb();
    registry = AiToolRegistry();
  });

  tearDown(() async {
    await uninstallAiTestDb();
  });

  test('openAiReadToolsSchema returns 13 tools with valid shape', () {
    final tools = registry.openAiReadToolsSchema();
    expect(tools.length, 13);
    for (final t in tools) {
      expect(t['type'], 'function');
      expect(t['function'], isA<Map>());
      final fn = t['function'] as Map;
      expect(fn['name'], isA<String>());
      expect(fn['parameters'], isA<Map>());
    }
  });

  test('humanLabel returns a label for every registered tool', () {
    for (final t in registry.openAiReadToolsSchema()) {
      final name = (t['function'] as Map)['name'] as String;
      expect(registry.humanLabel(name), isNotEmpty);
    }
  });

  test('executeRead on unknown tool returns unknown_tool', () async {
    final r = await registry.executeRead(toolName: 'no_such_tool', args: const {});
    expect(r.ok, isFalse);
    expect(r.code, 'unknown_tool');
  });

  test('list_recent_workouts returns empty list on empty DB', () async {
    final r = await registry.executeRead(
      toolName: 'list_recent_workouts',
      args: const {'limit': 5},
    );
    expect(r.ok, isTrue);
    expect((r.data as Map)['workouts'], isA<List>());
  });

  test('list_recent_workouts computes volume from sets', () async {
    final now = DateTime.now().toIso8601String();
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Peito',
      'color': 0xFFE53935,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercises', {
      'id': 'bench_press',
      'name': 'Supino Reto',
      'category_id': 'chest',
      'type': 'weightReps',
      'is_favorite': 0,
      'created_at': now,
    });
    await db.insert('workouts', {
      'id': 'w_recent',
      'date': '2024-06-01',
      'start_time': now,
      'duration_seconds': 3600,
      'feeling_rating': 4,
      'is_from_routine': 0,
      'created_at': now,
    });
    await db.insert('exercise_entries', {
      'id': 'ee_recent',
      'workout_id': 'w_recent',
      'exercise_id': 'bench_press',
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 's_recent_1',
      'exercise_entry_id': 'ee_recent',
      'weight': 60.0,
      'reps': 10,
      'is_complete': 1,
      'is_warmup': 0,
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 's_recent_2',
      'exercise_entry_id': 'ee_recent',
      'weight': 60.0,
      'reps': 8,
      'is_complete': 1,
      'is_warmup': 1, // warmup, ignored
      'order_index': 1,
    });
    final r = await registry.executeRead(
      toolName: 'list_recent_workouts',
      args: const {'limit': 5},
    );
    expect(r.ok, isTrue);
    final workouts = (r.data as Map)['workouts'] as List;
    expect(workouts, hasLength(1));
    final w = workouts.first as Map;
    expect(w['id'], 'w_recent');
    expect(w['volumeKg'], 60.0 * 10);
    expect(w['exerciseCount'], 1);
  });

  test('list_exercises returns exercise list', () async {
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Peito',
      'color': 0xFFE53935,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercises', {
      'id': 'bench_press',
      'name': 'Supino Reto',
      'category_id': 'chest',
      'type': 'weightReps',
      'is_favorite': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    final r = await registry.executeRead(
      toolName: 'list_exercises',
      args: const {'is_favorite': true},
    );
    expect(r.ok, isTrue);
    final list = (r.data as Map)['exercises'] as List;
    expect(list, hasLength(1));
    final first = list.first as Map;
    expect(first['name'], 'Supino Reto');
    expect(first['isFavorite'], true);
  });

  test('get_workout_detail returns exercise with sets', () async {
    final now = DateTime.now().toIso8601String();
    await db.insert('exercises', {
      'id': 'sq',
      'name': 'Agachamento',
      'category_id': 'legs',
      'type': 'weightReps',
      'is_favorite': 0,
      'created_at': now,
    });
    await db.insert('workouts', {
      'id': 'w_detail',
      'date': '2024-06-01',
      'duration_seconds': 1800,
      'is_from_routine': 0,
      'created_at': now,
    });
    await db.insert('exercise_entries', {
      'id': 'ee_detail',
      'workout_id': 'w_detail',
      'exercise_id': 'sq',
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 's_detail_1',
      'exercise_entry_id': 'ee_detail',
      'weight': 100.0,
      'reps': 5,
      'is_complete': 1,
      'is_warmup': 0,
      'order_index': 0,
    });
    final r = await registry.executeRead(
      toolName: 'get_workout_detail',
      args: const {'workout_id': 'w_detail'},
    );
    expect(r.ok, isTrue);
    final data = r.data as Map;
    expect(data['id'], 'w_detail');
    expect(data['exercises'], isA<List>());
    final exs = data['exercises'] as List;
    expect(exs, hasLength(1));
    final ex = exs.first as Map;
    expect(ex['exerciseId'], 'sq');
    final sets = ex['sets'] as List;
    expect(sets, hasLength(1));
  });

  test('list_goals returns empty list on empty DB', () async {
    final r = await registry.executeRead(
      toolName: 'list_goals',
      args: const {},
    );
    expect(r.ok, isTrue);
    final list = (r.data as Map)['goals'] as List;
    expect(list, isEmpty);
  });
}
