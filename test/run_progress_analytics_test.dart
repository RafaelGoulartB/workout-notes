import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

RunActivity _run({
  required String id,
  required DateTime startedAt,
  required double distanceMeters,
  required int movingTimeSeconds,
  double? avgPaceSecPerKm,
  int calories = 0,
  CardioActivityType type = CardioActivityType.running,
}) {
  final pace =
      avgPaceSecPerKm ??
      (distanceMeters >= 1
          ? movingTimeSeconds / (distanceMeters / 1000.0)
          : null);
  return RunActivity(
    id: id,
    activityType: type,
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

  test('compares the period against the previous window of same length', () {
    final activities = [
      // Previous 4-week window (2026-06-25 .. 2026-07-22).
      _run(
        id: 'prev',
        startedAt: DateTime(2026, 7, 10, 7),
        distanceMeters: 10000,
        movingTimeSeconds: 3600, // 6:00 /km
      ),
      // Current 4-week window.
      _run(
        id: 'cur',
        startedAt: DateTime(2026, 8, 5, 7),
        distanceMeters: 15000,
        movingTimeSeconds: 4500, // 5:00 /km
      ),
    ];

    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks4,
      now: now,
    );

    expect(stats.hasPreviousPeriod, isTrue);
    expect(stats.previousPeriod.runCount, 1);
    expect(stats.previousPeriod.distanceMeters, 10000);
    expect(stats.previousPeriod.avgPaceSecPerKm, closeTo(360, 0.01));
    expect(stats.distanceRatioVsPreviousPeriod, closeTo(0.5, 0.0001));
    expect(stats.paceDeltaVsPreviousPeriod, closeTo(-60, 0.01));
  });

  test('all-time period has nothing to compare against', () {
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'a',
          startedAt: DateTime(2026, 8, 18, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
      ],
      period: RunStatsPeriod.all,
      now: now,
    );

    expect(stats.hasPreviousPeriod, isFalse);
    expect(stats.previousPeriod.isEmpty, isTrue);
    expect(stats.distanceRatioVsPreviousPeriod, isNull);
    expect(stats.paceDeltaVsPreviousPeriod, isNull);
  });

  test('buckets the current week by weekday', () {
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'tue',
          startedAt: DateTime(2026, 8, 18, 7),
          distanceMeters: 6000,
          movingTimeSeconds: 1800,
        ),
        _run(
          id: 'wed',
          startedAt: DateTime(2026, 8, 19, 7),
          distanceMeters: 3000,
          movingTimeSeconds: 900,
        ),
        _run(
          id: 'wed2',
          startedAt: DateTime(2026, 8, 19, 19),
          distanceMeters: 2000,
          movingTimeSeconds: 600,
        ),
        _run(
          id: 'lastweek',
          startedAt: DateTime(2026, 8, 12, 7),
          distanceMeters: 9000,
          movingTimeSeconds: 2700,
        ),
      ],
      period: RunStatsPeriod.weeks12,
      now: now,
    );

    expect(stats.thisWeekDays.length, 7);
    expect(stats.thisWeekDays.first.date, DateTime(2026, 8, 17)); // Monday
    expect(stats.thisWeekDays[0].hasRun, isFalse);
    expect(stats.thisWeekDays[1].distanceMeters, 6000);
    expect(stats.thisWeekDays[2].runCount, 2);
    expect(stats.thisWeekDays[2].distanceMeters, 5000);
    expect(stats.thisWeekDays.skip(3).every((d) => !d.hasRun), isTrue);
  });

  test('week streak counts back and tolerates a week still in progress', () {
    // Runs in the two weeks before the current one, none yet this week.
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'w1',
          startedAt: DateTime(2026, 8, 11, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
        _run(
          id: 'w2',
          startedAt: DateTime(2026, 8, 4, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
        // Gap on the week of 2026-07-27, so the streak stops at 2.
        _run(
          id: 'w4',
          startedAt: DateTime(2026, 7, 21, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
      ],
      period: RunStatsPeriod.weeks12,
      now: now,
    );

    expect(stats.weekStreak, 2);
  });

  test('weekly average and this-week ratio use the period window', () {
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'a',
          startedAt: DateTime(2026, 8, 18, 7),
          distanceMeters: 8000,
          movingTimeSeconds: 2400,
        ),
        _run(
          id: 'b',
          startedAt: DateTime(2026, 8, 11, 7),
          distanceMeters: 4000,
          movingTimeSeconds: 1200,
        ),
      ],
      period: RunStatsPeriod.weeks4,
      now: now,
    );

    // 12 km over a 4-week window.
    expect(stats.avgWeeklyDistanceMeters, closeTo(3000, 0.01));
    expect(stats.thisWeekVsAverageRatio, closeTo(8000 / 3000, 0.0001));
  });

  test('best km split takes the fastest split in the period', () {
    final fast = _run(
      id: 'fast',
      startedAt: DateTime(2026, 8, 18, 7),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
    ).copyWith(bestSplitPaceSecPerKm: 280);
    final slow = _run(
      id: 'slow',
      startedAt: DateTime(2026, 8, 19, 7),
      distanceMeters: 5000,
      movingTimeSeconds: 1600,
    ).copyWith(bestSplitPaceSecPerKm: 310);

    final stats = RunProgressAnalytics.fromActivities(
      [fast, slow],
      period: RunStatsPeriod.weeks4,
      now: now,
    );

    expect(stats.bestKmSplitSecPerKm, 280);
  });

  test('treadmill counts toward volume but not GPS-only metrics', () {
    final gps = _run(
      id: 'gps',
      startedAt: DateTime(2026, 8, 18, 7),
      distanceMeters: 5000,
      movingTimeSeconds: 1600, // 5:20 /km
    );
    final treadmill = _run(
      id: 'tm',
      startedAt: DateTime(2026, 8, 19, 7),
      distanceMeters: 8000,
      movingTimeSeconds: 2000, // 4:10 /km, would win best pace
      type: CardioActivityType.treadmill,
    ).copyWith(bestSplitPaceSecPerKm: 200);

    final stats = RunProgressAnalytics.fromActivities(
      [gps, treadmill],
      period: RunStatsPeriod.weeks4,
      now: now,
    );

    expect(stats.runCount, 2);
    expect(stats.totalDistanceMeters, 13000);
    expect(stats.totalMovingTimeSeconds, 3600);
    expect(stats.thisWeekRunCount, 2);
    expect(stats.fastestRun?.id, 'gps');
    expect(stats.bestPaceSecPerKm, closeTo(320, 0.01));
    expect(stats.bestKmSplitSecPerKm, isNull);
    expect(stats.bestKmSplitRun, isNull);
    expect(stats.paceTrend.map((p) => p.distanceMeters), [5000]);
  });

  test('ignores non-running activities entirely', () {
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'bike',
          startedAt: DateTime(2026, 8, 18, 7),
          distanceMeters: 20000,
          movingTimeSeconds: 3000,
          type: CardioActivityType.stationaryBike,
        ),
      ],
      period: RunStatsPeriod.weeks4,
      now: now,
    );
    expect(stats.isEmpty, isTrue);
  });

  test('bestKmSplitRun points at the run holding the best split', () {
    final fast = _run(
      id: 'fast',
      startedAt: DateTime(2026, 8, 18, 7),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
    ).copyWith(bestSplitPaceSecPerKm: 280);
    final slow = _run(
      id: 'slow',
      startedAt: DateTime(2026, 8, 19, 7),
      distanceMeters: 5000,
      movingTimeSeconds: 1600,
    ).copyWith(bestSplitPaceSecPerKm: 310);
    final stats = RunProgressAnalytics.fromActivities(
      [slow, fast],
      period: RunStatsPeriod.weeks4,
      now: now,
    );
    expect(stats.bestKmSplitRun?.id, 'fast');
  });

  test('weekly averages share one basis and match the buckets', () {
    // 4 runs over a 12-week window: 4 / 12 runs a week, 12 km / 12 weeks.
    final activities = [
      for (var i = 0; i < 4; i++)
        _run(
          id: 'r$i',
          startedAt: DateTime(2026, 8, 18).subtract(Duration(days: 14 * i)),
          distanceMeters: 3000,
          movingTimeSeconds: 900,
        ),
    ];
    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks12,
      now: now,
    );
    expect(stats.periodWeekCount, 12);
    expect(stats.weeklyBuckets.length, stats.periodWeekCount);
    expect(stats.avgRunsPerWeek, closeTo(4 / 12, 1e-9));
    expect(stats.avgWeeklyDistanceMeters, closeTo(1000, 1e-9));
    expect(
      stats.weeklyBuckets.fold<double>(0, (a, b) => a + b.distanceMeters),
      stats.totalDistanceMeters,
    );
  });

  test('a run in the oldest week of the window is in totals and buckets', () {
    // 12 weeks back from the week of 2026-08-17 starts on 2026-06-01.
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'edge',
          startedAt: DateTime(2026, 6, 2, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
      ],
      period: RunStatsPeriod.weeks12,
      now: now,
    );
    expect(stats.runCount, 1);
    expect(stats.weeklyBuckets.first.distanceMeters, 5000);
  });

  test('all-time keeps every week and groups long ranges by month', () {
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'old',
          startedAt: DateTime(2024, 3, 5, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
        _run(
          id: 'new',
          startedAt: DateTime(2026, 8, 18, 7),
          distanceMeters: 7000,
          movingTimeSeconds: 2100,
        ),
      ],
      period: RunStatsPeriod.all,
      now: now,
    );

    // 2024-03-04 to 2026-08-17 is far more than the old 52-week cap.
    expect(stats.weeklyBuckets.length, greaterThan(100));
    expect(stats.periodWeekCount, stats.weeklyBuckets.length);
    expect(
      stats.weeklyBuckets.fold<double>(0, (a, b) => a + b.distanceMeters),
      stats.totalDistanceMeters,
    );
    expect(stats.trendIsMonthly, isTrue);
    expect(stats.trendBuckets.first.weekStart, DateTime(2024, 3));
    expect(stats.trendBuckets.last.weekStart, DateTime(2026, 8));
    expect(
      stats.trendBuckets.fold<double>(0, (a, b) => a + b.distanceMeters),
      12000,
    );
    expect(
      stats.avgWeeklyDistanceMeters,
      closeTo(12000 / stats.periodWeekCount, 1e-9),
    );
  });

  test('week comparison is absent when neither week has a run', () {
    final stats = RunProgressAnalytics.fromActivities(
      [
        _run(
          id: 'old',
          startedAt: DateTime(2026, 7, 1, 7),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
      ],
      period: RunStatsPeriod.weeks12,
      now: now,
    );
    expect(stats.thisWeekDistanceMeters, 0);
    expect(stats.lastWeekDistanceMeters, 0);
    expect(stats.hasWeekComparison, isFalse);
  });

  test('sums elevation gain and fits a pace trend line', () {
    final activities = [
      for (var i = 0; i < 4; i++)
        RunActivity(
          id: 'e$i',
          startedAt: DateTime(2026, 8, 3 + i * 4, 7),
          endedAt: null,
          durationSeconds: 1500,
          movingTimeSeconds: 1500,
          distanceMeters: 5000,
          // 6:00 improving by 10 s/km every 4 days.
          avgPaceSecPerKm: 360.0 - i * 10,
          maxPaceSecPerKm: null,
          calories: null,
          title: null,
          notes: null,
          status: 'completed',
          polylineSummary: null,
          createdAt: DateTime(2026, 8, 3),
          updatedAt: DateTime(2026, 8, 3),
          elevationGainMeters: 40,
        ),
    ];
    final stats = RunProgressAnalytics.fromActivities(
      activities,
      period: RunStatsPeriod.weeks4,
      now: now,
    );
    expect(stats.totalElevationGainMeters, 160);
    final perMonth = stats.paceTrendPerMonthSec!;
    // -10 s/km every 4 days is -75 s/km per 30 days.
    expect(perMonth, closeTo(-75, 0.5));
  });
}
