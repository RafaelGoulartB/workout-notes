import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/body_progress_analytics.dart';

Map<String, dynamic> _row(String date, double value) => {
  'date': date,
  'value': value,
};

/// Wednesday 2026-08-19; the week containing it opens on Sunday 2026-08-16.
final _now = DateTime(2026, 8, 19);

void main() {
  group('weekly buckets', () {
    test('weeks start on Sunday and average the daily values', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [
          // Week of Sun 2026-08-09 .. Sat 2026-08-15
          _row('2026-08-09', 80.0),
          _row('2026-08-12', 79.0),
          // Week of Sun 2026-08-16 .. Sat 2026-08-22
          _row('2026-08-16', 78.0),
          _row('2026-08-18', 77.0),
        ],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      final withData = analytics.weeks.where((w) => w.hasData).toList();
      expect(withData.length, 2);
      expect(withData.first.weekStart, DateTime(2026, 8, 9));
      expect(withData.first.average, closeTo(79.5, 0.001));
      expect(withData.last.weekStart, DateTime(2026, 8, 16));
      expect(withData.last.average, closeTo(77.5, 0.001));
      expect(withData.last.deltaVsPreviousWeek, closeTo(-2.0, 0.001));
      // The current week is always the last bucket, even mid-week.
      expect(analytics.weeks.last.weekStart, DateTime(2026, 8, 16));
    });

    test('several entries on one day count as a single day average', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [
          _row('2026-08-17', 76.0),
          _row('2026-08-17', 78.0),
          _row('2026-08-18', 77.0),
        ],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      final week = analytics.weeks.last;
      expect(week.dayCount, 2);
      expect(week.entryCount, 3);
      // 77 (the 17th's average) and 77 -> 77, not skewed by the extra entry.
      expect(week.average, closeTo(77.0, 0.001));
      expect(analytics.entryCount, 3);
      expect(analytics.dayCount, 2);
    });

    test('empty weeks are kept as gaps between weeks with data', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-08-02', 80.0), _row('2026-08-17', 78.0)],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      // The 4-week window is Sunday-aligned: Jul 26, Aug 2, Aug 9, Aug 16.
      expect(analytics.weeks.length, 4);
      expect(analytics.weeks.map((w) => w.hasData).toList(), [
        false,
        true,
        false,
        true,
      ]);
      expect(analytics.weeksWithData, 2);
    });

    test('rows outside the period and in the future are ignored', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [
          _row('2026-05-01', 90.0), // before the 4-week window
          _row('2026-08-17', 78.0),
          _row('2026-09-01', 70.0), // future
        ],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      expect(analytics.entryCount, 1);
      expect(analytics.lastValue, closeTo(78.0, 0.001));
      expect(analytics.firstValue, closeTo(78.0, 0.001));
    });
  });

  group('week comparison', () {
    test('compares the current week with the previous one', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-08-10', 80.0), _row('2026-08-17', 78.0)],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      final comparison = analytics.weekComparison;
      expect(comparison.current.weekStart, DateTime(2026, 8, 16));
      expect(comparison.reference?.weekStart, DateTime(2026, 8, 9));
      expect(comparison.referenceIsAdjacent, isTrue);
      expect(comparison.delta, closeTo(-2.0, 0.001));
      expect(comparison.percent, closeTo(-2.5, 0.001));
    });

    test('falls back to the closest earlier week with data', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-08-03', 80.0), _row('2026-08-17', 79.0)],
        period: BodyStatsPeriod.weeks12,
        now: _now,
      );

      final comparison = analytics.weekComparison;
      expect(comparison.reference?.weekStart, DateTime(2026, 8, 2));
      expect(comparison.referenceIsAdjacent, isFalse);
      expect(comparison.delta, closeTo(-1.0, 0.001));
    });

    test('no delta when the current week has no entry', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-08-10', 80.0)],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      expect(analytics.weekComparison.current.hasData, isFalse);
      expect(analytics.weekComparison.delta, isNull);
    });
  });

  group('rate of change', () {
    test('fits a weekly slope over the period', () {
      // Exactly -0.5 per week for four weeks.
      final analytics = BodyProgressAnalytics.fromRows(
        [
          _row('2026-07-22', 80.0),
          _row('2026-07-29', 79.5),
          _row('2026-08-05', 79.0),
          _row('2026-08-12', 78.5),
          _row('2026-08-19', 78.0),
        ],
        period: BodyStatsPeriod.weeks12,
        now: _now,
      );

      expect(analytics.ratePerWeek, closeTo(-0.5, 0.0001));
      expect(analytics.ratePercentPerWeek, closeTo(-0.5 / 78 * 100, 0.001));
      expect(analytics.totalChange, closeTo(-2.0, 0.001));
      expect(analytics.projectedValue(4), closeTo(76.0, 0.001));
    });

    test('needs three days spanning a week', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-08-17', 80.0), _row('2026-08-18', 79.0)],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      expect(analytics.ratePerWeek, isNull);
      expect(analytics.projectedValue(4), isNull);
    });
  });

  group('consistency', () {
    test('streak counts back from the current week', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [
          _row('2026-07-27', 80.0), // week of Jul 26
          _row('2026-08-03', 80.0), // week of Aug 2
          _row('2026-08-10', 79.0), // week of Aug 9
          _row('2026-08-17', 78.0), // week of Aug 16 (current)
        ],
        period: BodyStatsPeriod.weeks12,
        now: _now,
      );

      expect(analytics.weekStreak, 4);
      expect(analytics.daysSinceLast, 2);
      expect(analytics.entriesPerWeek, closeTo(4 / analytics.weeks.length, 0.001));
    });

    test('a current week with nothing logged yet does not break the streak', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-08-03', 80.0), _row('2026-08-10', 79.0)],
        period: BodyStatsPeriod.weeks12,
        now: _now,
      );

      expect(analytics.weekStreak, 2);
    });

    test('a gap resets the streak', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [_row('2026-07-20', 80.0), _row('2026-08-17', 78.0)],
        period: BodyStatsPeriod.weeks12,
        now: _now,
      );

      expect(analytics.weekStreak, 1);
    });
  });

  group('monthly buckets', () {
    test('groups by calendar month with a delta against the month before', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [
          _row('2026-07-05', 81.0),
          _row('2026-07-20', 79.0),
          _row('2026-08-05', 78.0),
          _row('2026-08-15', 78.0),
        ],
        period: BodyStatsPeriod.weeks26,
        now: _now,
      );

      expect(analytics.months.length, 2);
      expect(analytics.months.first.monthStart, DateTime(2026, 7));
      expect(analytics.months.first.average, closeTo(80.0, 0.001));
      expect(analytics.months.first.deltaVsPreviousMonth, isNull);
      expect(analytics.months.last.average, closeTo(78.0, 0.001));
      expect(analytics.months.last.deltaVsPreviousMonth, closeTo(-2.0, 0.001));
    });
  });

  group('smoothing', () {
    test('trailing mean never looks ahead', () {
      final analytics = BodyProgressAnalytics.fromRows(
        [
          _row('2026-08-15', 80.0),
          _row('2026-08-16', 78.0),
          _row('2026-08-17', 79.0),
        ],
        period: BodyStatsPeriod.weeks4,
        now: _now,
      );

      expect(analytics.smoothed.length, 3);
      expect(analytics.smoothed[0], closeTo(80.0, 0.001));
      expect(analytics.smoothed[1], closeTo(79.0, 0.001));
      expect(analytics.smoothed[2], closeTo(79.0, 0.001));
    });
  });

  group('goal progress', () {
    test('tracks a weight-loss target from the start value', () {
      final progress = BodyGoalProgress(
        startValue: 82,
        currentValue: 78,
        targetValue: 76,
        ratePerWeek: -0.5,
      );

      expect(progress.remaining, closeTo(2.0, 0.001));
      expect(progress.fraction, closeTo(4 / 6, 0.001));
      expect(progress.onTrack, isTrue);
      expect(progress.weeksToTarget, closeTo(4.0, 0.001));
      expect(
        progress.etaFrom(_now),
        DateTime(2026, 8, 19).add(const Duration(days: 28)),
      );
      expect(progress.reached, isFalse);
    });

    test('no ETA when the trend moves away from the target', () {
      final progress = BodyGoalProgress(
        startValue: 82,
        currentValue: 78,
        targetValue: 76,
        ratePerWeek: 0.3,
      );

      expect(progress.onTrack, isFalse);
      expect(progress.weeksToTarget, isNull);
      expect(progress.etaFrom(_now), isNull);
    });

    test('overshooting the target reads as achieved', () {
      final progress = BodyGoalProgress(
        startValue: 82,
        currentValue: 75,
        targetValue: 76,
        ratePerWeek: -0.5,
      );

      expect(progress.fraction, 1.0);
      expect(progress.reached, isFalse);
      expect(progress.passed, isTrue);
      expect(progress.achieved, isTrue);
      // Still losing weight past the target is not a deviation.
      expect(progress.onTrack, isTrue);
      expect(progress.remaining, closeTo(1.0, 0.001));
    });

    test('a target not yet crossed is not passed', () {
      final progress = BodyGoalProgress(
        startValue: 82,
        currentValue: 78,
        targetValue: 76,
        ratePerWeek: -0.5,
      );

      expect(progress.passed, isFalse);
      expect(progress.achieved, isFalse);
    });

    test('moving away from the start counts as zero progress', () {
      final progress = BodyGoalProgress(
        startValue: 82,
        currentValue: 84,
        targetValue: 76,
        ratePerWeek: 0.5,
      );

      expect(progress.fraction, 0.0);
    });
  });

  test('empty input yields an empty analytics object', () {
    final analytics = BodyProgressAnalytics.fromRows(
      const [],
      period: BodyStatsPeriod.weeks12,
      now: _now,
    );

    expect(analytics.isEmpty, isTrue);
    expect(analytics.weekComparison.current.weekStart, DateTime(2026, 8, 16));
    expect(analytics.weekComparison.delta, isNull);
    expect(analytics.ratePerWeek, isNull);
    expect(analytics.consistency, 0);
  });
}
