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

  tearDown(uninstallAiTestDb);

  test('recorded runs and stationary bike feed cardio tools', () async {
    final now = DateTime.now();
    await _insertActivity(
      db,
      id: 'run-1',
      startedAt: now.subtract(const Duration(days: 2)),
      distanceMeters: 5000,
      movingSeconds: 1500,
      rpe: 7,
      bestEffort5kSec: 1500,
    );
    await _insertActivity(
      db,
      id: 'bike-1',
      type: 'stationary_bike',
      startedAt: now.subtract(const Duration(days: 1)),
      distanceMeters: 12000,
      movingSeconds: 1800,
      rpe: 5,
    );

    final listed = await registry.executeRead(
      toolName: 'list_run_activities',
      args: {'activity_type': 'all'},
    );
    expect(listed.ok, isTrue);
    final listedData = listed.data as Map<String, dynamic>;
    expect(listedData['activities'], hasLength(2));

    final summary = await registry.executeRead(
      toolName: 'get_cardio_summary',
      args: {'weeks_back': 8},
    );
    final summaryData = summary.data as Map<String, dynamic>;
    expect(summaryData['weeksBack'], 8);
    expect(summaryData['recordedActivities'], 2);
    final types = (summaryData['byActivityType'] as List)
        .map((value) => (value as Map)['activityType'])
        .toSet();
    expect(types, {'running', 'stationary_bike'});
    expect(summaryData['legacyAerobicWorkoutData'], isA<Map>());
  });

  test(
    'run detail exposes route, plan and planned versus actual steps',
    () async {
      final now = DateTime.now();
      await _insertActivity(
        db,
        id: 'run-detail',
        startedAt: now,
        distanceMeters: 1000,
        movingSeconds: 300,
        planWorkoutId: 'session-1',
      );
      await db.insert('run_track_points', {
        'id': 'point-1',
        'activity_id': 'run-detail',
        'seq': 0,
        'lat': -23.0,
        'lng': -46.0,
        'altitude': 100.0,
        'recorded_at': now.toIso8601String(),
      });
      await db.insert('run_track_points', {
        'id': 'point-2',
        'activity_id': 'run-detail',
        'seq': 1,
        'lat': -23.001,
        'lng': -46.001,
        'altitude': 112.0,
        'recorded_at': now.add(const Duration(minutes: 5)).toIso8601String(),
      });
      await _insertPlanTree(db, now);
      await db.insert('scheduled_runs', {
        'id': 'scheduled-1',
        'date': _date(now),
        'run_plan_id': 'plan-1',
        'run_plan_workout_id': 'session-1',
        'status': 'completed',
        'run_activity_id': 'run-detail',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('run_activity_steps', {
        'id': 'actual-step-1',
        'run_activity_id': 'run-detail',
        'order_index': 0,
        'role': 'work',
        'rep_index': 1,
        'planned_metric': 'distance',
        'planned_value': 1000,
        'planned_pace_sec_per_km': 320.0,
        'actual_distance_meters': 1000.0,
        'actual_duration_seconds': 300,
        'actual_pace_sec_per_km': 300.0,
      });

      final result = await registry.executeRead(
        toolName: 'get_run_activity_detail',
        args: {'activity_id': 'run-detail'},
      );
      expect(result.ok, isTrue);
      final data = result.data as Map<String, dynamic>;
      expect(data['found'], isTrue);
      expect((data['plan'] as Map)['name'], 'Plano 5K');
      expect((data['routeSummary'] as Map)['elevationGainMeters'], 12.0);
      expect((data['stepResults'] as List).single['paceDeltaSecPerKm'], -20.0);
    },
  );

  test('progress, achievements and plan adherence use recorded runs', () async {
    final now = DateTime.now();
    await _insertActivity(
      db,
      id: 'run-fast',
      startedAt: now.subtract(const Duration(days: 2)),
      distanceMeters: 5000,
      movingSeconds: 1500,
      bestSplitPace: 285,
      bestEffort5kSec: 1500,
    );
    await _insertActivity(
      db,
      id: 'run-long',
      startedAt: now.subtract(const Duration(days: 8)),
      distanceMeters: 10000,
      movingSeconds: 3300,
      bestSplitPace: 300,
      bestEffort5kSec: 1600,
    );
    await _insertPlanTree(db, now);
    await db.insert('scheduled_runs', {
      'id': 'scheduled-complete',
      'date': _date(now),
      'run_plan_id': 'plan-1',
      'run_plan_workout_id': 'session-1',
      'status': 'completed',
      'run_activity_id': 'run-fast',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final progress = await registry.executeRead(
      toolName: 'get_run_progress',
      args: {'period': '12_weeks'},
    );
    final progressData = progress.data as Map<String, dynamic>;
    expect(progressData['runCount'], 2);
    expect(progressData['totalDistanceMeters'], 15000.0);
    expect(progressData['longestRun'], isA<Map>());

    final achievements = await registry.executeRead(
      toolName: 'get_run_achievements',
      args: const {},
    );
    final categories = (achievements.data as Map)['categories'] as List;
    expect(
      categories.map((value) => (value as Map)['kind']),
      containsAll(['longestDistance', 'bestEffort5k']),
    );

    final plans = await registry.executeRead(
      toolName: 'list_run_plans',
      args: const {},
    );
    final plan = ((plans.data as Map)['plans'] as List).single as Map;
    expect(plan['isActivated'], isTrue);
    expect((plan['progress'] as Map)['completedSessions'], 1);
    expect((plan['progress'] as Map)['completionFraction'], 1.0);

    final detail = await registry.executeRead(
      toolName: 'get_run_plan_detail',
      args: {'plan_id': 'plan-1'},
    );
    final adherence = (detail.data as Map)['adherence'] as Map;
    expect(adherence['performedDistanceMeters'], 5000.0);
    expect(adherence['distanceRatioForCompletedSessions'], 1.0);
  });
}

Future<void> _insertActivity(
  Database db, {
  required String id,
  required DateTime startedAt,
  required double distanceMeters,
  required int movingSeconds,
  String type = 'running',
  double? rpe,
  double? bestSplitPace,
  int? bestEffort5kSec,
  String? planWorkoutId,
}) async {
  await db.insert('run_activities', {
    'id': id,
    'activity_type': type,
    'started_at': startedAt.toIso8601String(),
    'ended_at': startedAt
        .add(Duration(seconds: movingSeconds))
        .toIso8601String(),
    'duration_seconds': movingSeconds,
    'moving_time_seconds': movingSeconds,
    'distance_meters': distanceMeters,
    'avg_pace_sec_per_km': type == 'running'
        ? movingSeconds / (distanceMeters / 1000)
        : null,
    'calories': 300,
    'rpe': rpe,
    'feeling_rating': 4,
    'status': 'completed',
    'created_at': startedAt.toIso8601String(),
    'updated_at': startedAt.toIso8601String(),
    'best_split_pace_sec_per_km': bestSplitPace,
    'best_effort_5k_sec': bestEffort5kSec,
    'efforts_computed': 1,
    'plan_workout_id': planWorkoutId,
  });
}

Future<void> _insertPlanTree(Database db, DateTime now) async {
  await db.insert('run_plans', {
    'id': 'plan-1',
    'name': 'Plano 5K',
    'goal_kind': '5k',
    'weeks': 1,
    'status': 'active',
    'activated_at': _date(now),
    'completion_count': 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
  await db.insert('run_plan_workouts', {
    'id': 'session-1',
    'run_plan_id': 'plan-1',
    'week_index': 0,
    'day_of_week': now.weekday,
    'order_index': 0,
    'kind': 'easy',
    'name': 'Rodagem',
    'target_distance_meters': 5000.0,
    'target_pace_sec_per_km': 320.0,
    'created_at': now.toIso8601String(),
  });
  await db.insert('run_workout_steps', {
    'id': 'step-1',
    'run_plan_workout_id': 'session-1',
    'order_index': 0,
    'role': 'work',
    'metric': 'distance',
    'value': 5000,
    'repeat_count': 1,
  });
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);
