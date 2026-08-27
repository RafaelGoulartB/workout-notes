import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_history.dart';

RunActivity _run({
  required DateTime startedAt,
  required double km,
  required int seconds,
  CardioActivityType type = CardioActivityType.running,
  String status = 'completed',
}) {
  final now = DateTime(2026, 8, 26);
  return RunActivity(
    id: '${startedAt.millisecondsSinceEpoch}-$km',
    activityType: type,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(seconds: seconds)),
    durationSeconds: seconds,
    movingTimeSeconds: seconds,
    distanceMeters: km * 1000,
    avgPaceSecPerKm: seconds / km,
    maxPaceSecPerKm: null,
    calories: null,
    title: null,
    notes: null,
    status: status,
    polylineSummary: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final now = DateTime(2026, 8, 26, 10); // Wednesday
  // Complete weeks end the Monday of this week: 2026-08-24.
  DateTime monday(int weeksAgo) =>
      DateTime(2026, 8, 24).subtract(Duration(days: 7 * weeksAgo));

  test('median weekly km ignores the current partial week', () {
    final activities = [
      _run(startedAt: now, km: 40, seconds: 40 * 330), // this week — ignored
      _run(
        startedAt: monday(1).add(const Duration(days: 1)),
        km: 20,
        seconds: 20 * 330,
      ),
      _run(
        startedAt: monday(1).add(const Duration(days: 3)),
        km: 10,
        seconds: 10 * 330,
      ),
      _run(
        startedAt: monday(2).add(const Duration(days: 1)),
        km: 32,
        seconds: 32 * 330,
      ),
      _run(
        startedAt: monday(3).add(const Duration(days: 1)),
        km: 28,
        seconds: 28 * 330,
      ),
    ];
    final insights = RunPlanHistoryInsights.from(activities, now: now);
    expect(insights.medianWeekCount, 3);
    expect(insights.medianWeeklyKm, closeTo(30, 0.05)); // 30, 32, 28
  });

  test('returns null volume when no complete week has a run', () {
    final insights = RunPlanHistoryInsights.from([
      _run(startedAt: now, km: 8, seconds: 8 * 330),
    ], now: now);
    expect(insights.medianWeeklyKm, isNull);
  });

  test('suggests the fastest run near the goal distance', () {
    final activities = [
      _run(
        startedAt: now.subtract(const Duration(days: 10)),
        km: 5.1,
        seconds: 28 * 60,
      ),
      _run(
        startedAt: now.subtract(const Duration(days: 12)),
        km: 5.2,
        seconds: 26 * 60,
      ),
      _run(
        startedAt: now.subtract(const Duration(days: 8)),
        km: 12,
        seconds: 70 * 60,
      ),
    ];
    final insights = RunPlanHistoryInsights.from(
      activities,
      now: now,
      goalDistanceMeters: RunPaceCalculator.fiveKMeters,
    );
    expect(insights.suggestedRace, isNotNull);
    expect(insights.suggestedRace!.distanceMeters, closeTo(5200, 1));
    expect(insights.suggestedRace!.timeSeconds, 26 * 60);
  });

  test('falls back to the closest distance when nothing is near the goal', () {
    final insights = RunPlanHistoryInsights.from(
      [
        _run(
          startedAt: now.subtract(const Duration(days: 4)),
          km: 8,
          seconds: 45 * 60,
        ),
        _run(
          startedAt: now.subtract(const Duration(days: 6)),
          km: 3.2,
          seconds: 20 * 60,
        ),
      ],
      now: now,
      goalDistanceMeters: RunPaceCalculator.halfMeters,
    );
    expect(insights.suggestedRace!.distanceMeters, closeTo(8000, 1));
  });

  test('ignores short jogs, bikes and incomplete activities', () {
    final insights = RunPlanHistoryInsights.from([
      _run(
        startedAt: now.subtract(const Duration(days: 3)),
        km: 2.4,
        seconds: 15 * 60,
      ),
      _run(
        startedAt: now.subtract(const Duration(days: 3)),
        km: 10,
        seconds: 50 * 60,
        type: CardioActivityType.stationaryBike,
      ),
      _run(
        startedAt: now.subtract(const Duration(days: 3)),
        km: 10,
        seconds: 50 * 60,
        status: 'draft',
      ),
    ], now: now);
    expect(insights.suggestedRace, isNull);
  });
}
