import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_context_service.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiContextService context;
  final today = DateTime(2026, 9, 30, 15, 42);
  const all = {...AiToolDomain.values};

  setUp(() async {
    db = await installAiTestDb();
    context = AiContextService(now: () => today);
  });

  tearDown(() async {
    await uninstallAiTestDb();
  });

  test('empty database: date, weekday and units only', () async {
    final snapshot = await context.buildSnapshot(domains: all);
    expect(snapshot, startsWith('today: 2026-09-30 (Wednesday)'));
    expect(snapshot, contains('units: kg, km'));
    expect(snapshot, isNot(contains('15:42')), reason: 'no time of day');
  });

  test('summarizes the latest activity, weight and last night', () async {
    const now = '2026-09-29T07:00:00.000';
    await db.insert('routines', {
      'id': 'r',
      'name': 'Upper/Lower',
      'created_at': now,
    });
    await db.insert('workouts', {
      'id': 'w',
      'date': '2026-09-29',
      'start_time': now,
      'end_time': '2026-09-29T08:00:00.000',
      'duration_seconds': 3600,
      'is_from_routine': 1,
      'routine_id': 'r',
      'created_at': now,
    });
    // Planned for the future: never reported as done.
    await db.insert('workouts', {
      'id': 'planned',
      'date': '2026-10-02',
      'is_from_routine': 1,
      'routine_id': 'r',
      'created_at': now,
    });
    await db.insert('run_activities', {
      'id': 'run',
      'activity_type': 'running',
      'started_at': '2026-09-28T06:30:00.000',
      'duration_seconds': 1800,
      'moving_time_seconds': 1750,
      'distance_meters': 5200.0,
      'status': 'completed',
      'created_at': now,
      'updated_at': now,
    });
    for (final (date, value) in [('2026-08-25', 82.0), ('2026-09-30', 80.5)]) {
      await db.insert('body_measurements', {
        'id': 'm$date',
        'type': 'weight',
        'value': value,
        'unit': 'kg',
        'date': date,
        'created_at': now,
      });
    }
    await db.insert('sleep_entries', {
      'id': 's',
      'date': '2026-09-30',
      'sleep_minutes': 450,
      'actual_sleep_minutes': 412,
      'created_at': now,
    });

    final snapshot = await context.buildSnapshot(domains: all);
    expect(
      snapshot,
      contains('last strength workout: 2026-09-29 "Upper/Lower"'),
    );
    expect(snapshot, contains('strength workouts last 7 days: 1'));
    expect(snapshot, contains('next planned/in-progress workout: 2026-10-02'));
    expect(snapshot, contains('last run: 2026-09-28, 5.2 km, 29 min'));
    expect(snapshot, contains('latest weight: 80.5 kg on 2026-09-30 (-1.5'));
    expect(snapshot, contains('last sleep entry: 2026-09-30, 06:52 asleep'));
  });

  test('switched-off domains are left out', () async {
    await db.insert('sleep_entries', {
      'id': 's',
      'date': '2026-09-30',
      'sleep_minutes': 450,
      'created_at': '2026-09-30T07:00:00.000',
    });
    final snapshot = await context.buildSnapshot(
      domains: {AiToolDomain.core, AiToolDomain.workouts},
    );
    expect(snapshot, isNot(contains('sleep')));
  });

  test('cached for a minute, rebuilt after invalidate', () async {
    final a = await context.buildSnapshot(domains: all);
    await db.insert('sleep_entries', {
      'id': 's',
      'date': '2026-09-30',
      'sleep_minutes': 400,
      'created_at': '2026-09-30T07:00:00.000',
    });
    expect(await context.buildSnapshot(domains: all), a);
    context.invalidate();
    expect(await context.buildSnapshot(domains: all), contains('sleep'));
  });
}
