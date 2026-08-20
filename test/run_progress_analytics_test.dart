import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

RunActivity _run({
  required String id,
  required DateTime startedAt,
  required double distanceMeters,
  required int movingTimeSeconds,
  double? avgPaceSecPerKm,
  int calories = 0,
}) {
  final pace = avgPaceSecPerKm ??
      (distanceMeters >= 1
          ? movingTimeSeconds / (distanceMeters / 1000.0)
          : null);
  return RunActivity(
    id: id,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: movingTimeSeconds)),
    durationSeconds: movingTimeSeconds,
    movingTimeSeconds: movingTimeSeconds,
    distanceMeters: distanceMeters,
    avgPaceSecPerKm: pace,
    maxPaceSecPerKm: pace,
    calories: calories,
    title: 'Run $id',
    notes: null,
    status: 'completed',
    polylineSummary: null,
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}

void main() {
  final now = DateTime(2026, 8, 19, 12); // Wednesday

  test('aggregates period totals and weighted avg pace', () {
    final activities = [
      _run(
        id: 'a',
        startedAt: DateTime(2026, 8, 10, 7),
        distanceMeters: 5000,
        movingTimeSeconds: 1500, // 5:00 /km
        calories: 300,
      ),
      _run(
        id: 'b',
        startedAt: DateTime(2026, 8, 17, 7),
        distanceMeters: 10000,
        movingTimeSeconds: 3600, // 6:00 /km
        calories: 600,
      ),
    ];

    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks12,
      now: now,
    );

    expect(stats.runCount, 2);
    expect(stats.totalDistanceMeters, 15000);
    expect(stats.totalMovingTimeSeconds, 5100);
    expect(stats.totalCalories, 900);
    // Weighted by distance: (5*300 + 10*360) / 15 = 340
    expect(stats.avgPaceSecPerKm, closeTo(340, 0.01));
    expect(stats.longestRun?.id, 'b');
    expect(stats.fastestRun?.id, 'a');
    expect(stats.bestPaceSecPerKm, closeTo(300, 0.01));
  });

  test('filters by lookback period', () {
    final activities = [
      _run(
        id: 'old',
        startedAt: DateTime(2026, 1, 1, 7),
        distanceMeters: 8000,
        movingTimeSeconds: 2400,
      ),
      _run(
        id: 'recent',
        startedAt: DateTime(2026, 8, 15, 7),
        distanceMeters: 5000,
        movingTimeSeconds: 1600,
      ),
    ];

    final fourWeeks = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks4,
      now: now,
    );
    expect(fourWeeks.runCount, 1);
    expect(fourWeeks.activities.single.id, 'recent');

    final all = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.all,
      now: now,
    );
    expect(all.runCount, 2);
  });

  test('computes this week vs last week distance', () {
    // this week starts Monday 2026-08-17
    final activities = [
      _run(
        id: 'last',
        startedAt: DateTime(2026, 8, 12, 7), // Tue last week
        distanceMeters: 4000,
        movingTimeSeconds: 1200,
      ),
      _run(
        id: 'this1',
        startedAt: DateTime(2026, 8, 18, 7), // Tue this week
        distanceMeters: 6000,
        movingTimeSeconds: 1800,
      ),
      _run(
        id: 'this2',
        startedAt: DateTime(2026, 8, 19, 7),
        distanceMeters: 3000,
        movingTimeSeconds: 900,
      ),
    ];

    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks12,
      now: now,
    );

    expect(stats.thisWeekRunCount, 2);
    expect(stats.thisWeekDistanceMeters, 9000);
    expect(stats.lastWeekRunCount, 1);
    expect(stats.lastWeekDistanceMeters, 4000);
    expect(stats.distanceDeltaVsLastWeek, 5000);
  });

  test('builds weekly buckets spanning selected period', () {
    final activities = [
      _run(
        id: 'a',
        startedAt: DateTime(2026, 8, 18, 7),
        distanceMeters: 5000,
        movingTimeSeconds: 1500,
      ),
    ];

    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks4,
      now: now,
    );

    expect(stats.weeklyBuckets.length, 4);
    expect(stats.weeklyBuckets.last.runCount, 1);
    expect(stats.weeklyBuckets.last.distanceMeters, 5000);
    expect(stats.weeklyBuckets.take(3).every((b) => b.runCount == 0), isTrue);
  });

  test('ignores sub-1km runs for pace trend and best pace', () {
    final activities = [
      _run(
        id: 'short',
        startedAt: DateTime(2026, 8, 18, 7),
        distanceMeters: 400,
        movingTimeSeconds: 60,
        avgPaceSecPerKm: 150, // unrealistically fast noise
      ),
      _run(
        id: 'real',
        startedAt: DateTime(2026, 8, 19, 7),
        distanceMeters: 5000,
        movingTimeSeconds: 1600,
      ),
    ];

    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks4,
      now: now,
    );

    expect(stats.fastestRun?.id, 'real');
    expect(stats.paceTrend.length, 1);
    expect(stats.paceTrend.single.paceSecPerKm, closeTo(320, 0.01));
  });
}
