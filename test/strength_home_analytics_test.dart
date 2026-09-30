import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';

StrengthWorkoutSummary _w(
  String date, {
  double volume = 1000,
  int sets = 10,
  int seconds = 3600,
  List<String> categories = const ['chest'],
}) {
  final d = DateTime.parse(date);
  return StrengthWorkoutSummary(
    id: date,
    date: DateTime(d.year, d.month, d.day),
    durationSeconds: seconds,
    volumeKg: volume,
    workingSets: sets,
    exerciseCount: 3,
    categoryIds: categories,
  );
}

void main() {
  // Tuesday 2026-09-29: this week starts Monday 2026-09-28.
  final now = DateTime(2026, 9, 29, 12);

  group('StrengthWeekAnalytics', () {
    test('this week only counts sessions from Monday on', () {
      final analytics = StrengthWeekAnalytics.fromWorkouts(
        [
          _w('2026-09-27', volume: 500), // last Sunday
          _w('2026-09-28', volume: 2000, sets: 12, categories: ['legs']),
          _w('2026-09-29', volume: 1000, sets: 8, categories: ['chest']),
        ],
        period: RunStatsPeriod.weeks4,
        now: now,
      );

      expect(analytics.thisWeekSessions, 2);
      expect(analytics.thisWeekSets, 20);
      expect(analytics.thisWeekVolumeKg, 3000);
      expect(analytics.lastWeekSessions, 1);
      expect(analytics.lastWeekVolumeKg, 500);
      expect(analytics.thisWeekDays.first.date, DateTime(2026, 9, 28));
      expect(analytics.thisWeekDays.first.categoryId, 'legs');
      expect(analytics.thisWeekDays[1].categoryId, 'chest');
      expect(analytics.thisWeekDays.last.hasSession, isFalse);
    });

    test('future dated workouts are never counted', () {
      final analytics = StrengthWeekAnalytics.fromWorkouts(
        [_w('2026-09-30')],
        period: RunStatsPeriod.weeks4,
        now: now,
      );
      expect(analytics.totals.sessions, 0);
      expect(analytics.thisWeekSessions, 0);
    });

    test('totals, average duration and previous period trend', () {
      final analytics = StrengthWeekAnalytics.fromWorkouts(
        [
          // Previous 4 weeks (2026-08-03 .. 2026-08-30).
          _w('2026-08-10', volume: 1000, seconds: 3000),
          _w('2026-08-24', volume: 1000, seconds: 3000),
          // Current 4 weeks (2026-09-07 .. ).
          _w('2026-09-08', volume: 2000, sets: 10, seconds: 3600),
          _w('2026-09-15', volume: 2000, sets: 20, seconds: 5400),
          _w('2026-09-22', volume: 2000, sets: 10, seconds: 1800),
        ],
        period: RunStatsPeriod.weeks4,
        now: now,
      );

      expect(analytics.totals.sessions, 3);
      expect(analytics.totals.volumeKg, 6000);
      expect(analytics.totals.workingSets, 40);
      expect(analytics.totals.durationSeconds, 10800);
      expect(analytics.totals.avgDurationSeconds, 3600);
      expect(analytics.periodWeekCount, 4);
      expect(analytics.avgWeeklySessions, closeTo(0.75, 1e-9));
      expect(analytics.hasPreviousPeriod, isTrue);
      expect(analytics.previous.sessions, 2);
      expect(analytics.volumeRatioVsPreviousPeriod, closeTo(2.0, 1e-9));
      expect(analytics.trendBuckets, hasLength(4));
      // The last bucket is the current week, still empty.
      expect(analytics.trendBuckets.last.sessions, 0);
      expect(analytics.trendBuckets[2].sessions, 1);
      expect(analytics.trendBuckets.first.volumeKg, 2000);
      expect(analytics.trendIsMonthly, isFalse);
    });

    test('all-time uses the first workout week and no previous period', () {
      final analytics = StrengthWeekAnalytics.fromWorkouts(
        [_w('2026-09-01'), _w('2026-09-29')],
        period: RunStatsPeriod.all,
        now: now,
      );
      expect(analytics.periodWeekCount, 5);
      expect(analytics.hasPreviousPeriod, isFalse);
      expect(analytics.volumeRatioVsPreviousPeriod, isNull);
      expect(analytics.totals.sessions, 2);
    });

    test('long histories fall back to monthly buckets', () {
      final analytics = StrengthWeekAnalytics.fromWorkouts(
        [_w('2023-01-10'), _w('2026-09-29')],
        period: RunStatsPeriod.all,
        now: now,
      );
      expect(analytics.trendIsMonthly, isTrue);
      expect(analytics.trendBuckets.first.start, DateTime(2023, 1));
      expect(analytics.trendBuckets.last.start, DateTime(2026, 9));
      expect(analytics.trendBuckets.first.sessions, 1);
      expect(analytics.trendBuckets.last.sessions, 1);
    });

    test('week streak survives an empty current week', () {
      final analytics = StrengthWeekAnalytics.fromWorkouts(
        [_w('2026-09-08'), _w('2026-09-16'), _w('2026-09-24')],
        period: RunStatsPeriod.weeks12,
        now: now,
      );
      // Weeks of 09-07, 09-14 and 09-21 in a row; this week still empty.
      expect(analytics.weekStreak, 3);

      final withGap = StrengthWeekAnalytics.fromWorkouts(
        [_w('2026-09-01'), _w('2026-09-24')],
        period: RunStatsPeriod.weeks12,
        now: now,
      );
      expect(withGap.weekStreak, 1);
    });
  });

  group('StrengthWeekGoal', () {
    test('plan beats the user goal which beats the average', () {
      expect(
        StrengthWeekGoal.resolve(
          planSessions: 4,
          userSessions: 3,
          averageSessions: 2,
        )?.source,
        StrengthWeekGoalSource.plan,
      );
      expect(
        StrengthWeekGoal.resolve(userSessions: 3, averageSessions: 2)?.source,
        StrengthWeekGoalSource.user,
      );
      final average = StrengthWeekGoal.resolve(averageSessions: 2.6);
      expect(average?.source, StrengthWeekGoalSource.average);
      expect(average?.sessions, 3);
      expect(StrengthWeekGoal.resolve(averageSessions: 0.2), isNull);
      expect(StrengthWeekGoal.resolve(), isNull);
    });
  });

  test('volume switches to tonnes from 10 t', () {
    expect(StrengthVolumeValue.of(850).unit, 'kg');
    expect(StrengthVolumeValue.of(9999).tonnes, isFalse);
    final t = StrengthVolumeValue.of(12300);
    expect(t.unit, 't');
    expect(t.value, closeTo(12.3, 1e-9));
  });

  group('WorkoutWeekOverview', () {
    test('combines gym and cardio of the current week and the streak', () {
      final overview = WorkoutWeekOverview.compute(
        gym: [
          StrengthWorkoutStamp(
            date: DateTime(2026, 9, 21),
            durationSeconds: 60,
          ),
          StrengthWorkoutStamp(
            date: DateTime(2026, 9, 28),
            durationSeconds: 3600,
          ),
        ],
        cardio: [
          WorkoutCardioStamp(
            date: DateTime(2026, 9, 29),
            durationSeconds: 1800,
            runDistanceMeters: 5000,
          ),
          // Bike: active time and streak, no kilometres run.
          WorkoutCardioStamp(date: DateTime(2026, 9, 14), durationSeconds: 900),
        ],
        now: now,
      );
      expect(overview.strengthSessions, 1);
      expect(overview.cardioSessions, 1);
      expect(overview.runMeters, 5000);
      expect(overview.activeSeconds, 5400);
      // Weeks of 09-28, 09-21 and 09-14 all have something.
      expect(overview.streakWeeks, 3);
      expect(overview.hasActivityThisWeek, isTrue);
    });

    test('empty history is all zeros', () {
      final overview = WorkoutWeekOverview.compute(
        gym: const [],
        cardio: const [],
        now: now,
      );
      expect(overview.streakWeeks, 0);
      expect(overview.hasActivityThisWeek, isFalse);
    });
  });
}
