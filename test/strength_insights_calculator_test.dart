import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';

// "Today" is Tuesday 2026-09-29; the week started on Monday 2026-09-28.
final _today = DateTime(2026, 9, 29);

StrengthSetSample _set(
  String workout,
  DateTime date,
  String exercise,
  double weight,
  int reps, {
  String category = 'chest',
}) => StrengthSetSample(
  workoutId: workout,
  date: date,
  exerciseId: exercise,
  exerciseName: exercise,
  exerciseLocaleKey: null,
  categoryId: category,
  weight: weight,
  reps: reps,
);

StrengthWorkoutInfo _workout(
  String id,
  DateTime date, {
  int? minutes,
  int? feeling,
  bool hasTime = true,
}) => StrengthWorkoutInfo(
  id: id,
  date: date,
  durationSeconds: minutes == null ? null : minutes * 60,
  feeling: feeling,
  hasTime: hasTime,
);

void main() {
  group('ranges and totals', () {
    test('current and previous ranges are back to back', () {
      final now = StrengthInsightsCalculator.rangeFor(
        StrengthPeriod.weeks4,
        _today,
      );
      final before = StrengthInsightsCalculator.rangeFor(
        StrengthPeriod.weeks4,
        _today,
        previous: true,
      );
      expect(now.days, 28);
      expect(now.to, DateTime(2026, 9, 29));
      expect(before.to, now.from.subtract(const Duration(days: 1)));
      expect(before.days, 28);
    });

    test('totals count sets, volume, sessions and active days in range', () {
      final sets = [
        _set('a', DateTime(2026, 9, 28, 10), 'bench', 100, 10),
        _set('a', DateTime(2026, 9, 28, 10), 'bench', 100, 8),
        _set('b', DateTime(2026, 8, 1, 10), 'bench', 100, 10),
      ];
      final workouts = [
        _workout('a', DateTime(2026, 9, 28, 10)),
        _workout('b', DateTime(2026, 8, 1, 10)),
      ];
      final range = StrengthInsightsCalculator.rangeFor(
        StrengthPeriod.weeks4,
        _today,
      );
      final totals = StrengthInsightsCalculator.totals(sets, workouts, range);
      expect(totals.sets, 2);
      expect(totals.volume, 1800);
      expect(totals.sessions, 1);
      expect(totals.activeDays, 1);
    });
  });

  group('buckets', () {
    test('weekly buckets are Monday based, oldest first', () {
      final buckets = StrengthInsightsCalculator.weeklyBuckets(
        [
          _set('a', DateTime(2026, 9, 28), 'bench', 50, 10), // this week
          _set('b', DateTime(2026, 9, 21), 'bench', 60, 10), // last week
          _set('b', DateTime(2026, 9, 27), 'bench', 60, 10), // last Sunday
        ],
        [
          _workout('a', DateTime(2026, 9, 28)),
          _workout('b', DateTime(2026, 9, 21)),
        ],
        _today,
        count: 3,
      );
      expect(buckets.map((b) => b.start), [
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 28),
      ]);
      expect(buckets[1].volume, 1200);
      expect(buckets[1].sets, 2);
      expect(buckets[1].sessions, 1);
      expect(buckets[2].volume, 500);
      expect(buckets[0].sets, 0);
    });

    test('monthly buckets cross the year boundary', () {
      final buckets = StrengthInsightsCalculator.monthlyBuckets(
        [_set('a', DateTime(2025, 12, 31), 'bench', 50, 10)],
        const [],
        DateTime(2026, 2, 10),
        count: 3,
      );
      expect(buckets.map((b) => b.start.month), [12, 1, 2]);
      expect(buckets.first.volume, 500);
    });
  });

  group('muscle load', () {
    test('status compares average weekly sets with 10 to 20', () {
      final range = StrengthInsightsCalculator.rangeFor(
        StrengthPeriod.weeks4,
        _today,
      );
      final sets = [
        // 44 chest sets in 4 weeks = 11 / week (within).
        for (var i = 0; i < 44; i++)
          _set('c$i', DateTime(2026, 9, 20), 'bench', 50, 10),
        // 8 back sets = 2 / week (below).
        for (var i = 0; i < 8; i++)
          _set('r$i', DateTime(2026, 9, 21), 'row', 50, 10, category: 'back'),
        // 100 leg sets = 25 / week (above).
        for (var i = 0; i < 100; i++)
          _set('l$i', DateTime(2026, 9, 22), 'squat', 50, 10, category: 'legs'),
      ];
      final load = StrengthInsightsCalculator.muscleLoad(
        sets,
        range,
        categoryIds: const ['chest', 'back', 'legs', 'core'],
      );
      final byId = {for (final l in load) l.categoryId: l};
      expect(byId['chest']!.weeklySets, 11);
      expect(byId['chest']!.status, StrengthLoadStatus.within);
      expect(byId['back']!.status, StrengthLoadStatus.below);
      expect(byId['legs']!.status, StrengthLoadStatus.above);
      // Untrained groups still appear, as below.
      expect(byId['core']!.sets, 0);
      expect(byId['core']!.status, StrengthLoadStatus.below);
      expect(load.first.categoryId, 'legs');
    });
  });

  group('exercises', () {
    test('top exercises are ranked by volume and respect the range', () {
      final range = StrengthInsightsCalculator.rangeFor(
        StrengthPeriod.weeks4,
        _today,
      );
      final top = StrengthInsightsCalculator.topExercises([
        _set('a', DateTime(2026, 9, 20), 'bench', 100, 10),
        _set('a', DateTime(2026, 9, 20), 'row', 60, 10),
        _set('a', DateTime(2026, 9, 20), 'row', 60, 10),
        _set('o', DateTime(2026, 1, 1), 'squat', 300, 10),
      ], range);
      expect(top.map((e) => e.exerciseId), ['row', 'bench']);
      expect(top.first.volume, 1200);
      expect(top.first.sets, 2);
    });

    test('summary tracks the best e1RM per session and the trend', () {
      final summaries = StrengthInsightsCalculator.exerciseSummaries([
        _set('a', DateTime(2026, 9, 1), 'bench', 100, 1),
        _set('a', DateTime(2026, 9, 1), 'bench', 90, 8), // e1RM 114
        _set('b', DateTime(2026, 9, 8), 'bench', 100, 6), // e1RM 120
        _set('c', DateTime(2026, 9, 15), 'pullup', 0, 10),
      ]);
      final bench = summaries.firstWhere((s) => s.exerciseId == 'bench');
      expect(bench.sessions, 2);
      expect(bench.bestE1rm, closeTo(120, 0.01));
      expect(bench.e1rmSeries, hasLength(2));
      expect(bench.e1rmSeries.first, closeTo(114, 0.01));
      expect(bench.trendPercent, closeTo(5.26, 0.01));
      expect(bench.maxWeight, 100);
      final pullup = summaries.firstWhere((s) => s.exerciseId == 'pullup');
      expect(pullup.bestE1rm, isNull);
      expect(pullup.maxReps, 10);
      // Most recent first.
      expect(summaries.first.exerciseId, 'pullup');
    });
  });

  group('frequency', () {
    test('weekday counts start on Monday', () {
      final counts = StrengthInsightsCalculator.weekdayCounts([
        _workout('a', DateTime(2026, 9, 28)), // Monday
        _workout('b', DateTime(2026, 9, 21)), // Monday
        _workout('c', DateTime(2026, 9, 27)), // Sunday
      ]);
      expect(counts, [2, 0, 0, 0, 0, 0, 1]);
    });

    test('day parts ignore workouts without a start time', () {
      final parts = StrengthInsightsCalculator.dayPartCounts([
        _workout('a', DateTime(2026, 9, 28, 7)),
        _workout('b', DateTime(2026, 9, 28, 19)),
        _workout('c', DateTime(2026, 9, 28), hasTime: false),
      ]);
      expect(parts[StrengthDayPart.morning], 1);
      expect(parts[StrengthDayPart.evening], 1);
      expect(parts[StrengthDayPart.night], 0);
    });

    test('weekly duration averages only sessions with a duration', () {
      final weeks = StrengthInsightsCalculator.weeklyDuration(
        [
          _workout('a', DateTime(2026, 9, 28), minutes: 60),
          _workout('b', DateTime(2026, 9, 29), minutes: 40),
          _workout('c', DateTime(2026, 9, 30)),
        ],
        _today,
        count: 2,
      );
      expect(weeks.first.value, isNull);
      expect(weeks.last.value, 50);
    });

    test('daily sets and years', () {
      final daily = StrengthInsightsCalculator.dailySets([
        _set('a', DateTime(2026, 9, 28, 9), 'bench', 50, 10),
        _set('a', DateTime(2026, 9, 28, 9), 'bench', 50, 10),
        _set('b', DateTime(2025, 12, 31), 'bench', 50, 10),
      ], year: 2026);
      expect(daily, {DateTime(2026, 9, 28): 2});
      expect(
        StrengthInsightsCalculator.availableYears([
          _workout('b', DateTime(2024, 5, 1)),
        ], _today),
        [2026, 2024],
      );
    });
  });

  group('consistency', () {
    test('the week in progress does not break the streak', () {
      // Today is Tuesday 2026-09-29; trained last 3 weeks but not yet this one.
      final c = StrengthInsightsCalculator.consistency([
        _workout('a', DateTime(2026, 9, 22)),
        _workout('b', DateTime(2026, 9, 15)),
        _workout('c', DateTime(2026, 9, 8)),
        _workout('d', DateTime(2026, 8, 1)),
      ], _today);
      expect(c.currentWeekStreak, 3);
      expect(c.longestWeekStreak, 3);
      expect(c.weeksTrained, 4);
    });

    test('a missed full week resets the streak', () {
      final c = StrengthInsightsCalculator.consistency([
        _workout('a', DateTime(2026, 9, 8)),
        _workout('b', DateTime(2026, 9, 1)),
      ], _today);
      expect(c.currentWeekStreak, 0);
      expect(c.longestWeekStreak, 2);
    });

    test(
      'newcomers are judged only on the weeks since their first workout',
      () {
        final c = StrengthInsightsCalculator.consistency([
          _workout('a', DateTime(2026, 9, 15)),
          _workout('b', DateTime(2026, 9, 29)),
        ], _today);
        expect(c.weeksConsidered, 3);
        expect(c.weeksTrained, 2);
        expect(c.share, closeTo(2 / 3, 0.001));
        expect(c.sessionsPerWeek, closeTo(2 / 3, 0.001));
      },
    );

    test('no workouts gives an empty result', () {
      final c = StrengthInsightsCalculator.consistency(const [], _today);
      expect(c.weeksConsidered, 0);
      expect(c.share, 0);
    });
  });

  group('wellness', () {
    test('feeling versus volume averages the volume per rating', () {
      final result = StrengthInsightsCalculator.feelingVsVolume(
        [
          _workout('a', DateTime(2026, 9, 1), feeling: 4),
          _workout('b', DateTime(2026, 9, 2), feeling: 4),
          _workout('c', DateTime(2026, 9, 3), feeling: 2),
          _workout('d', DateTime(2026, 9, 4)),
        ],
        [
          _set('a', DateTime(2026, 9, 1), 'bench', 100, 10),
          _set('b', DateTime(2026, 9, 2), 'bench', 50, 10),
          _set('c', DateTime(2026, 9, 3), 'bench', 20, 10),
        ],
      );
      expect(result.map((r) => r.rating), [2, 4]);
      expect(result.last.averageVolume, 750);
      expect(result.last.sessions, 2);
    });
  });
}
