import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_review_insights.dart';

RunActivity _run(
  String id,
  DateTime at, {
  double meters = 5000,
  double pace = 360,
  int? effort5k,
  CardioActivityType type = CardioActivityType.running,
}) {
  return RunActivity(
    id: id,
    activityType: type,
    startedAt: at,
    endedAt: at.add(const Duration(minutes: 30)),
    durationSeconds: 1800,
    movingTimeSeconds: 1800,
    distanceMeters: meters,
    avgPaceSecPerKm: pace,
    maxPaceSecPerKm: null,
    calories: null,
    title: null,
    notes: null,
    status: 'completed',
    polylineSummary: null,
    createdAt: at,
    updatedAt: at,
    bestEffort5kSec: effort5k,
  );
}

void main() {
  // Wednesday 2026-09-09; the ISO week starts Monday 2026-09-07.
  final wednesday = DateTime(2026, 9, 9, 7);

  test('week starts on Monday', () {
    expect(
      RunReviewInsights.weekStart(DateTime(2026, 9, 13, 20)),
      DateTime(2026, 9, 7),
    );
    expect(
      RunReviewInsights.weekStart(DateTime(2026, 9, 7)),
      DateTime(2026, 9, 7),
    );
  });

  test('sums the week including the draft and ignores other weeks', () {
    final draft = _run('draft', wednesday, meters: 4000);
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: [draft],
      recent: [
        _run('mon', DateTime(2026, 9, 7, 7), meters: 6000),
        _run('last-sun', DateTime(2026, 9, 6, 7), meters: 9000),
        _run(
          'tread',
          DateTime(2026, 9, 8, 7),
          meters: 3000,
          type: CardioActivityType.treadmill,
        ),
      ],
    );
    expect(insights.weekMeters, 13000);
    expect(insights.weekRunCount, 3);
  });

  test('flags the longest run of the month when it beats the others', () {
    final draft = _run('draft', wednesday, meters: 12000);
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: [draft],
      recent: [
        _run('a', DateTime(2026, 9, 1, 7), meters: 8000),
        _run('b', DateTime(2026, 8, 30, 7), meters: 30000), // other month
      ],
    );
    expect(insights.longestOfMonth, isTrue);
  });

  test('no month highlight when it is the first run of the month', () {
    final draft = _run('draft', wednesday, meters: 12000);
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: [draft],
      recent: [_run('old', DateTime(2026, 8, 20, 7), meters: 3000)],
    );
    expect(insights.longestOfMonth, isFalse);
    expect(insights.fastestOfMonth, isFalse);
  });

  test('flags the fastest average pace of the month', () {
    final draft = _run('draft', wednesday, pace: 300);
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: [draft],
      recent: [
        _run('a', DateTime(2026, 9, 1, 7), pace: 330),
        _run('b', DateTime(2026, 9, 3, 7), pace: 345),
      ],
    );
    expect(insights.fastestOfMonth, isTrue);
  });

  test('ranks the draft against the whole history for medals', () {
    final draft = _run('draft', wednesday, effort5k: 1500);
    final ranking = [
      _run('gold', DateTime(2026, 1, 1), effort5k: 1400),
      _run('bronze', DateTime(2026, 2, 1), effort5k: 1600),
    ];
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: ranking,
      recent: const [],
    );
    final effort = insights.placements.firstWhere(
      (p) => p.kind == RunAchievementKind.bestEffort5k,
    );
    expect(effort.tier, RunMedalTier.silver);
    expect(insights.hasHighlights, isTrue);
  });

  test('treadmill runs get no medal placements', () {
    final draft = _run(
      'draft',
      wednesday,
      type: CardioActivityType.treadmill,
      effort5k: 1000,
    );
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: const [],
      recent: const [],
    );
    expect(insights.placements, isEmpty);
    expect(insights.weekMeters, 5000);
  });

  test('a first ever run is recognised', () {
    final draft = _run('draft', wednesday);
    final insights = RunReviewInsights.compute(
      draft: draft,
      ranking: [draft],
      recent: [draft],
    );
    expect(insights.isFirstRun, isTrue);
  });
}
