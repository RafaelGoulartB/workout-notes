import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/services/ai_context_service.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiContextService context;

  setUp(() async {
    db = await installAiTestDb();
    context = AiContextService();
  });

  tearDown(() async {
    await uninstallAiTestDb();
  });

  test('build with empty DB returns a well-formed JSON envelope', () async {
    final json = await context.build(mode: AiContextMode.standard);
    expect(json['metadata'], isA<Map>());
    expect((json['metadata'] as Map)['app'], 'workout_notes');
    expect(json['summary'], isA<Map>());
    final summary = json['summary'] as Map;
    final totals = summary['totals'] as Map;
    expect(totals['workouts'], 0);
    expect(totals['exercises'], 0);
    expect(summary['currentStreakDays'], 0);
  });

  test('minimal mode does not include weekly volume', () async {
    final json = await context.build(mode: AiContextMode.minimal);
    final summary = json['summary'] as Map;
    expect(summary.containsKey('last4WeeksVolume'), isFalse);
    expect(summary.containsKey('topExercisesByVolume'), isFalse);
  });

  test('standard mode includes only compact data availability', () async {
    final json = await context.build(mode: AiContextMode.standard);
    final summary = json['summary'] as Map;
    expect(summary.containsKey('dataAvailability'), isTrue);
    expect(summary.containsKey('last4WeeksVolume'), isFalse);
    expect(summary.containsKey('topExercisesByVolume'), isFalse);
  });

  test('full mode advertises domains without injecting time series', () async {
    final json = await context.build(mode: AiContextMode.full);
    final summary = json['summary'] as Map;
    expect(summary['availableDomains'], contains('sleep'));
    expect(summary['availableDomains'], contains('nutrition'));
    expect(summary['availableDomains'], contains('running'));
    expect(summary['availableDomains'], contains('run_plans'));
    expect(summary.containsKey('categoryDistributionPct'), isFalse);
    expect(summary.containsKey('bodyTrend30d'), isFalse);
  });

  test('cache is invalidated on invalidate()', () async {
    final a = await context.build(mode: AiContextMode.standard);
    final b = await context.build(mode: AiContextMode.standard);
    expect(identical(a, b), isTrue, reason: 'second call should hit cache');
    context.invalidate();
    final c = await context.build(mode: AiContextMode.standard);
    expect(identical(a, c), isFalse);
  });

  test('totals reflect completed workout content', () async {
    await db.insert('exercises', {
      'id': 'e1',
      'name': 'A',
      'category_id': 'chest',
      'type': 'weightReps',
      'is_favorite': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    final now = DateTime.now().toIso8601String();
    await db.insert('workouts', {
      'id': 'w_ctx',
      'date': '2024-06-01',
      'start_time': now,
      'end_time': now,
      'is_from_routine': 0,
      'created_at': now,
    });
    await db.insert('run_activities', {
      'id': 'run_ctx',
      'activity_type': 'running',
      'started_at': now,
      'duration_seconds': 1200,
      'moving_time_seconds': 1100,
      'distance_meters': 3000.0,
      'status': 'completed',
      'created_at': now,
      'updated_at': now,
    });
    final json = await context.build(mode: AiContextMode.standard);
    final totals = (json['summary'] as Map)['totals'] as Map;
    expect(totals['workouts'], 1);
    expect(totals['exercises'], 1);
    expect(totals['recordedRuns'], 1);
  });
}
