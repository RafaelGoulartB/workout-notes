import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late GoalRepository goals;

  setUp(() async {
    db = await installAiTestDb();
    goals = GoalRepository();
  });

  tearDown(uninstallAiTestDb);

  test('aerobic distance and time goals include tracked activities', () async {
    final now = DateTime.now();
    await _activity(db, 'run', now, meters: 5000, seconds: 1500);
    await _activity(
      db,
      'bike',
      now.subtract(const Duration(days: 1)),
      type: 'stationary_bike',
      meters: 12000,
      seconds: 1800,
    );

    final distance = await goals.getProgress(
      _goal(GoalMetric.distance, target: 20),
    );
    expect(distance.currentValue, 17.0);

    final time = await goals.getProgress(_goal(GoalMetric.time, target: 3600));
    expect(time.currentValue, 3300.0);

    final contributors = await goals.getContributingWorkouts(
      _goal(GoalMetric.distance, target: 20),
    );
    expect(
      contributors.map((value) => value.workoutId),
      containsAll(['run', 'bike']),
    );
  });

  test('aerobic days goal counts a calendar day only once', () async {
    final now = DateTime.now();
    await _activity(db, 'run-a', now, meters: 3000, seconds: 900);
    await _activity(db, 'run-b', now, meters: 2000, seconds: 600);

    final progress = await goals.getProgress(_goal(GoalMetric.days, target: 3));
    expect(progress.currentValue, 1.0);
  });
}

Goal _goal(GoalMetric metric, {required double target}) => Goal(
  id: 'goal-${metric.value}',
  title: 'Meta cardio',
  scope: GoalScope.aerobic,
  metric: metric,
  period: GoalPeriod.weekly,
  targetValue: target,
  createdAt: DateTime.now(),
);

Future<void> _activity(
  Database db,
  String id,
  DateTime date, {
  String type = 'running',
  required double meters,
  required int seconds,
}) => db.insert('run_activities', {
  'id': id,
  'activity_type': type,
  'started_at': date.toIso8601String(),
  'duration_seconds': seconds,
  'moving_time_seconds': seconds,
  'distance_meters': meters,
  'status': 'completed',
  'created_at': date.toIso8601String(),
  'updated_at': date.toIso8601String(),
});
