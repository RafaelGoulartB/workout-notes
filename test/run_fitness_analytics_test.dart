import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';

RunActivity _run(
  String id,
  DateTime startedAt, {
  double distanceMeters = 5000,
  int movingTimeSeconds = 1800,
  double? rpe,
  int? feeling,
  int? effort3k,
  int? effort5k,
  int? effort10k,
  double? elevation,
  CardioActivityType type = CardioActivityType.running,
}) => RunActivity(
  id: id,
  activityType: type,
  startedAt: startedAt,
  endedAt: startedAt.add(Duration(seconds: movingTimeSeconds)),
  durationSeconds: movingTimeSeconds,
  movingTimeSeconds: movingTimeSeconds,
  distanceMeters: distanceMeters,
  avgPaceSecPerKm: movingTimeSeconds / (distanceMeters / 1000),
  maxPaceSecPerKm: null,
  calories: null,
  title: id,
  notes: null,
  rpe: rpe,
  feelingRating: feeling,
  status: 'completed',
  polylineSummary: null,
  createdAt: startedAt,
  updatedAt: startedAt,
  bestEffort3kSec: effort3k,
  bestEffort5kSec: effort5k,
  bestEffort10kSec: effort10k,
  effortsComputed: true,
  elevationGainMeters: elevation,
);

void main() {
  final now = DateTime(2026, 8, 19, 12); // Wednesday

  group('fitness estimate', () {
    test('uses the best recent effort and predicts races from it', () {
      final estimate = RunFitnessAnalytics.estimate([
        _run('a', DateTime(2026, 8, 1, 7), effort5k: 1500), // 25:00
        _run('b', DateTime(2026, 8, 10, 7), effort5k: 1560),
      ], now: now)!;

      final expected = RunPaceCalculator.vdotFor(
        distanceMeters: 5000,
        timeSeconds: 1500,
      );
      expect(estimate.vdot, closeTo(expected, 1e-9));
      expect(estimate.vdot, inInclusiveRange(37.5, 39.5));
      expect(estimate.source.activityId, 'a');
      expect(estimate.isStale, isFalse);
      expect(estimate.fromTrainingRuns, isFalse);

      expect(estimate.predictions.map((p) => p.distanceMeters), [
        5000,
        10000,
        RunPaceCalculator.halfMeters,
        RunPaceCalculator.marathonMeters,
      ]);
      // The 5K prediction reproduces the effort it came from.
      expect(estimate.predictions.first.timeSeconds, closeTo(1500, 2));
      final times = estimate.predictions.map((p) => p.timeSeconds).toList();
      expect([...times]..sort(), times, reason: 'longer race, longer time');
      final paces = estimate.predictions.map((p) => p.paceSecPerKm).toList();
      expect(paces[0], lessThan(paces[3]));
    });

    test('flags an effort older than the recent window as stale', () {
      final estimate = RunFitnessAnalytics.estimate([
        _run('old', DateTime(2026, 2, 1, 7), effort5k: 1500),
      ], now: now)!;
      expect(estimate.isStale, isTrue);
    });

    test('falls back to a training run and says so', () {
      final estimate = RunFitnessAnalytics.estimate([
        _run(
          'easy',
          DateTime(2026, 8, 10, 7),
          distanceMeters: 8000,
          movingTimeSeconds: 2880, // 6:00 /km
        ),
      ], now: now)!;
      expect(estimate.fromTrainingRuns, isTrue);
      expect(estimate.vdot, greaterThan(20));
    });

    test('is null without any usable run and ignores treadmill efforts', () {
      expect(RunFitnessAnalytics.estimate(const [], now: now), isNull);
      expect(
        RunFitnessAnalytics.estimate([
          _run('short', DateTime(2026, 8, 10, 7), distanceMeters: 1500),
          _run(
            'tm',
            DateTime(2026, 8, 11, 7),
            distanceMeters: 10000,
            movingTimeSeconds: 3000,
            effort5k: 1400,
            type: CardioActivityType.treadmill,
          ),
        ], now: now),
        isNull,
      );
    });

    test('vdotByMonth keeps the best effort of each month, oldest first', () {
      final points = RunFitnessAnalytics.vdotByMonth([
        _run('jun1', DateTime(2026, 6, 5, 7), effort5k: 1620),
        _run('jun2', DateTime(2026, 6, 20, 7), effort5k: 1560),
        _run('aug', DateTime(2026, 8, 5, 7), effort5k: 1500),
      ], now: now);
      expect(points.map((p) => p.month), [
        DateTime(2026, 6),
        DateTime(2026, 8),
      ]);
      expect(
        points[0].vdot,
        closeTo(
          RunPaceCalculator.vdotFor(distanceMeters: 5000, timeSeconds: 1560),
          1e-9,
        ),
      );
      expect(points[1].vdot, greaterThan(points[0].vdot));
    });
  });

  group('training load', () {
    List<RunActivity> steady({int days = 60, double rpe = 5}) => [
      for (var i = 0; i < days; i += 2)
        _run(
          'r$i',
          DateTime(2026, 8, 19, 7).subtract(Duration(days: i)),
          movingTimeSeconds: 3000,
          rpe: rpe,
        ),
    ];

    test('session load is minutes times RPE with a pace-based fallback', () {
      final rated = _run('rated', now, movingTimeSeconds: 3600, rpe: 6);
      expect(RunFitnessAnalytics.sessionLoad(rated, null), 360);

      final unrated = _run('unrated', now, movingTimeSeconds: 3600);
      expect(RunFitnessAnalytics.sessionLoad(unrated, null), 300); // RPE 5

      final zones = RunFitnessAnalytics.estimate([
        _run('e', DateTime(2026, 8, 1, 7), effort5k: 1500),
      ], now: now)!.zones;
      final slow = _run(
        'slow',
        now,
        movingTimeSeconds: 3600,
        distanceMeters: 8000, // 7:30 /km, far slower than easy pace
      );
      expect(RunFitnessAnalytics.fallbackRpe(slow, zones), 3);
      final fast = _run(
        'fast',
        now,
        movingTimeSeconds: 1200,
        distanceMeters: 5000, // 4:00 /km
      );
      expect(RunFitnessAnalytics.fallbackRpe(fast, zones), greaterThan(7));
    });

    test('steady training is balanced with a ratio near one', () {
      final load = RunFitnessAnalytics.trainingLoad(steady(), now: now);
      expect(load.days.length, 84);
      expect(load.acwr, closeTo(1.0, 0.15));
      expect(load.status, RunLoadStatus.balanced);
      expect(load.weeklyLoad, greaterThan(0));
    });

    test('a sudden jump in load is flagged as a rapid increase', () {
      final activities = [
        ...steady(rpe: 3),
        // A hard week on top of easy history.
        for (var i = 0; i < 6; i++)
          _run(
            'hard$i',
            DateTime(2026, 8, 19, 18).subtract(Duration(days: i)),
            movingTimeSeconds: 4200,
            rpe: 9,
          ),
      ];
      final load = RunFitnessAnalytics.trainingLoad(activities, now: now);
      expect(load.acwr, greaterThan(1.3));
      expect(load.status, RunLoadStatus.rapidIncrease);
    });

    test('stopping training reads as detraining', () {
      final activities = [
        // Solid month of running that ended ten days ago.
        for (var i = 10; i < 38; i += 2)
          _run(
            'r$i',
            DateTime(2026, 8, 19, 7).subtract(Duration(days: i)),
            movingTimeSeconds: 3600,
            rpe: 6,
          ),
        _run(
          'recent',
          DateTime(2026, 8, 18, 7),
          movingTimeSeconds: 900,
          rpe: 3,
        ),
      ];
      final load = RunFitnessAnalytics.trainingLoad(activities, now: now);
      expect(load.status, RunLoadStatus.detraining);
    });

    test('needs a few runs before judging the load', () {
      final load = RunFitnessAnalytics.trainingLoad([
        _run('one', DateTime(2026, 8, 18, 7)),
      ], now: now);
      expect(load.acwr, isNull);
      expect(load.status, RunLoadStatus.insufficientData);
    });

    test('warns when weekly volume grows more than 10 percent', () {
      List<RunActivity> week(DateTime end, double km, String tag) => [
        for (var i = 0; i < 2; i++)
          _run(
            '$tag$i',
            end.subtract(Duration(days: i * 3)),
            distanceMeters: km * 500,
          ),
      ];
      final grew = RunFitnessAnalytics.trainingLoad([
        ...week(DateTime(2026, 8, 19, 7), 24, 'now'), // 24 km
        ...week(DateTime(2026, 8, 12, 7), 20, 'prev'), // 20 km
      ], now: now);
      expect(grew.weeklyVolumeGrowth, closeTo(0.2, 1e-9));
      expect(grew.volumeGrowthWarning, isTrue);

      final flat = RunFitnessAnalytics.trainingLoad([
        ...week(DateTime(2026, 8, 19, 7), 21, 'now'),
        ...week(DateTime(2026, 8, 12, 7), 20, 'prev'),
      ], now: now);
      expect(flat.volumeGrowthWarning, isFalse);

      final tiny = RunFitnessAnalytics.trainingLoad([
        ...week(DateTime(2026, 8, 19, 7), 4, 'now'),
        ...week(DateTime(2026, 8, 12, 7), 2, 'prev'),
      ], now: now);
      expect(
        tiny.weeklyVolumeGrowth,
        isNull,
        reason: 'previous week too small',
      );
    });
  });

  group('intensity distribution', () {
    final zones = RunPaceCalculator.fromVdot(50); // ~easy 5:37, tempo 4:12
    final bounds = RunZoneBounds.fromPaces(zones);

    test('zone boundaries are ordered and classify paces', () {
      expect(bounds.easySecPerKm, greaterThan(bounds.marathonSecPerKm));
      expect(bounds.marathonSecPerKm, greaterThan(bounds.tempoSecPerKm));
      expect(bounds.tempoSecPerKm, greaterThan(bounds.intervalSecPerKm));
      expect(bounds.zoneFor(bounds.easySecPerKm + 30), RunZone.z1);
      expect(bounds.zoneFor(bounds.easySecPerKm - 5), RunZone.z2);
      expect(bounds.zoneFor(bounds.marathonSecPerKm - 5), RunZone.z3);
      expect(bounds.zoneFor(bounds.tempoSecPerKm - 5), RunZone.z4);
      expect(bounds.zoneFor(bounds.intervalSecPerKm - 5), RunZone.z5);
    });

    test('uses per-km splits when present and average pace otherwise', () {
      final easyPace = bounds.easySecPerKm + 20;
      final hardPace = bounds.intervalSecPerKm - 10;
      final withSplits = _run(
        'splits',
        DateTime(2026, 8, 18, 7),
        movingTimeSeconds: 1800,
      );
      final withoutSplits = _run(
        'plain',
        DateTime(2026, 8, 17, 7),
        distanceMeters: 5000,
        movingTimeSeconds: (easyPace * 5).round(),
      );

      final distribution = RunFitnessAnalytics.intensityDistribution(
        [withSplits, withoutSplits],
        zones: bounds,
        splits: {
          'splits': [
            RunSplitSample(durationSeconds: 600, paceSecPerKm: easyPace),
            RunSplitSample(durationSeconds: 300, paceSecPerKm: hardPace),
            const RunSplitSample(durationSeconds: 60, paceSecPerKm: null),
          ],
        },
        now: now,
      );

      final totals = distribution.totalsPerZone;
      expect(totals[RunZone.z1.index], closeTo(600 + easyPace * 5, 1));
      expect(totals[RunZone.z5.index], 300);
      expect(distribution.weeks.length, 12);
      expect(distribution.weeks.last.weekStart, DateTime(2026, 8, 17));
      expect(
        distribution.easyShare +
            distribution.moderateShare +
            distribution.hardShare,
        closeTo(1, 1e-9),
      );
      expect(distribution.isPolarized, isTrue);
    });

    test('mostly hard running is not polarized', () {
      final hard = _run(
        'hard',
        DateTime(2026, 8, 18, 7),
        distanceMeters: 5000,
        movingTimeSeconds: ((bounds.tempoSecPerKm - 10) * 5).round(),
      );
      final distribution = RunFitnessAnalytics.intensityDistribution(
        [hard],
        zones: bounds,
        now: now,
      );
      expect(distribution.hardShare, 1);
      expect(distribution.isPolarized, isFalse);
    });
  });

  group('calendar and volume', () {
    final runs = [
      _run('a', DateTime(2026, 1, 5, 7), distanceMeters: 5000),
      _run('b', DateTime(2026, 1, 5, 19), distanceMeters: 3000),
      _run('c', DateTime(2026, 3, 1, 7), distanceMeters: 10000),
      _run('d', DateTime(2025, 12, 31, 7), distanceMeters: 7000),
      _run('e', DateTime(2025, 2, 1, 7), distanceMeters: 4000),
    ];

    test('dailyDistance sums per local day and filters by year', () {
      final daily = RunFitnessAnalytics.dailyDistance(runs, year: 2026);
      expect(daily[DateTime(2026, 1, 5)], 8000);
      expect(daily[DateTime(2026, 3, 1)], 10000);
      expect(daily.containsKey(DateTime(2025, 12, 31)), isFalse);
    });

    test('heat levels are quartiles of the runner active days', () {
      final t = RunFitnessAnalytics.heatThresholds([1000, 2000, 3000, 4000, 0]);
      expect(RunFitnessAnalytics.heatLevel(0, t), 0);
      expect(RunFitnessAnalytics.heatLevel(1000, t), 1);
      expect(RunFitnessAnalytics.heatLevel(4000, t), 4);
      expect(RunFitnessAnalytics.heatThresholds(const []), [0, 0, 0]);
    });

    test('monthlyTotals covers the last months including empty ones', () {
      final months = RunFitnessAnalytics.monthlyTotals(runs, now: now);
      expect(months.length, 12);
      expect(months.first.month, DateTime(2025, 9));
      expect(months.last.month, DateTime(2026, 8));
      expect(
        months.firstWhere((m) => m.month == DateTime(2026, 1)).distanceMeters,
        8000,
      );
      expect(
        months.firstWhere((m) => m.month == DateTime(2026, 1)).runCount,
        2,
      );
      expect(
        months.firstWhere((m) => m.month == DateTime(2026, 5)).distanceMeters,
        0,
      );
    });

    test('cumulativeMonthly accumulates and stops after the current month', () {
      final cumulative = RunFitnessAnalytics.cumulativeMonthly(
        runs,
        2026,
        now: now,
      );
      expect(cumulative[0], 8000);
      expect(cumulative[1], 8000);
      expect(cumulative[2], 18000);
      expect(cumulative[7], 18000); // August
      expect(cumulative[8], isNull);
      final last = RunFitnessAnalytics.cumulativeMonthly(runs, 2025, now: now);
      expect(last[11], 11000);
      expect(last.every((v) => v != null), isTrue);
    });

    test('availableYears is newest first and always has the current year', () {
      expect(RunFitnessAnalytics.availableYears(runs, now: now), [2026, 2025]);
      expect(RunFitnessAnalytics.availableYears(const [], now: now), [2026]);
    });
  });

  group('consistency', () {
    test('counts current and longest day and week streaks', () {
      final consistency = RunFitnessAnalytics.consistency([
        // Current streak: yesterday and the day before (none yet today).
        _run('d1', DateTime(2026, 8, 18, 7)),
        _run('d2', DateTime(2026, 8, 17, 7)),
        // An older, longer streak of four days.
        for (var i = 0; i < 4; i++) _run('o$i', DateTime(2026, 7, 1 + i, 7)),
      ], now: now);

      expect(consistency.currentDayStreak, 2);
      expect(consistency.longestDayStreak, 4);
      // Weeks of 08-17 and 06-29 have runs, the ones between do not.
      expect(consistency.currentWeekStreak, 1);
      expect(consistency.longestWeekStreak, 1);
    });

    test(
      'share of weeks with a run never counts weeks before the first run',
      () {
        final consistency = RunFitnessAnalytics.consistency([
          _run('w0', DateTime(2026, 8, 18, 7)),
          _run('w1', DateTime(2026, 8, 11, 7)),
        ], now: now);
        expect(consistency.weeksConsidered, 2);
        expect(consistency.weeksWithRuns, 2);
        expect(consistency.weeksWithRunsShare, 1);

        final empty = RunFitnessAnalytics.consistency(const [], now: now);
        expect(empty.weeksConsidered, 0);
        expect(empty.weeksWithRunsShare, 0);
      },
    );
  });

  test('weeklyEffort averages RPE and feeling per week', () {
    final weeks = RunFitnessAnalytics.weeklyEffort([
      _run('a', DateTime(2026, 8, 18, 7), rpe: 4, feeling: 5),
      _run('b', DateTime(2026, 8, 19, 7), rpe: 6, feeling: 3),
      _run('c', DateTime(2026, 8, 12, 7), rpe: 8),
    ], now: now);
    expect(weeks.length, 12);
    expect(weeks.last.avgRpe, 5);
    expect(weeks.last.avgFeeling, 4);
    expect(weeks[10].avgRpe, 8);
    expect(weeks[10].avgFeeling, isNull);
    expect(weeks.first.avgRpe, isNull);
  });

  test('elevation summary totals gain and finds the biggest climb', () {
    final summary = RunFitnessAnalytics.elevation([
      _run('a', DateTime(2026, 8, 1, 7), elevation: 120),
      _run('b', DateTime(2026, 8, 2, 7), elevation: 300),
      _run('c', DateTime(2026, 8, 3, 7)),
    ]);
    expect(summary.totalGainMeters, 420);
    expect(summary.runsWithData, 2);
    expect(summary.avgGainPerRunMeters, 210);
    expect(summary.highest?.id, 'b');
    expect(RunFitnessAnalytics.elevation(const []).hasData, isFalse);
  });

  group('year review', () {
    test('summarises the year', () {
      final review = RunFitnessAnalytics.yearReview([
        // Two Saturday-morning runs in March, one Tuesday evening in May.
        _run(
          'm1',
          DateTime(2026, 3, 7, 7),
          distanceMeters: 10000,
          movingTimeSeconds: 3000,
          effort5k: 1450,
        ),
        _run(
          'm2',
          DateTime(2026, 3, 14, 8),
          distanceMeters: 12000,
          movingTimeSeconds: 3600,
          effort5k: 1400,
        ),
        _run(
          'may',
          DateTime(2026, 5, 5, 19),
          distanceMeters: 5000,
          movingTimeSeconds: 1500,
        ),
        _run('other-year', DateTime(2025, 5, 5, 19), distanceMeters: 30000),
      ], 2026);

      expect(review.year, 2026);
      expect(review.runCount, 3);
      expect(review.totalDistanceMeters, 27000);
      expect(review.totalMovingSeconds, 8100);
      expect(review.longestRun?.id, 'm2');
      expect(review.fastest5kRun?.id, 'm2');
      expect(review.mostActiveMonth, 3);
      expect(review.mostActiveMonthMeters, 22000);
      expect(review.favoriteWeekday, DateTime.saturday);
      expect(review.favoriteDayPart, RunDayPart.morning);
    });

    test('an empty year is flagged as empty', () {
      final review = RunFitnessAnalytics.yearReview(const [], 2026);
      expect(review.isEmpty, isTrue);
      expect(review.mostActiveMonth, isNull);
      expect(review.favoriteDayPart, isNull);
    });

    test('day parts split the day', () {
      expect(RunDayPart.forHour(6), RunDayPart.morning);
      expect(RunDayPart.forHour(14), RunDayPart.afternoon);
      expect(RunDayPart.forHour(19), RunDayPart.evening);
      expect(RunDayPart.forHour(23), RunDayPart.night);
      expect(RunDayPart.forHour(3), RunDayPart.night);
    });
  });
}
