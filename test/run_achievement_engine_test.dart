import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';

RunActivity _run({
  required String id,
  required DateTime startedAt,
  double distanceMeters = 5000,
  int movingTimeSeconds = 1800,
  double? avgPaceSecPerKm,
  double? bestSplitPaceSecPerKm,
  int? bestEffort1kSec,
  int? bestEffort5kSec,
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
    maxPaceSecPerKm: null,
    calories: 300,
    title: id,
    notes: null,
    status: 'completed',
    polylineSummary: null,
    createdAt: startedAt,
    updatedAt: startedAt,
    bestSplitPaceSecPerKm: bestSplitPaceSecPerKm,
    bestEffort1kSec: bestEffort1kSec,
    bestEffort5kSec: bestEffort5kSec,
    effortsComputed: true,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);
  final t2 = DateTime.utc(2026, 1, 3);
  final t3 = DateTime.utc(2026, 1, 4);

  test('ranks distance gold silver bronze all-time', () {
    final board = RunAchievementEngine.build([
      _run(id: 'a', startedAt: t0, distanceMeters: 8000),
      _run(id: 'b', startedAt: t1, distanceMeters: 12000),
      _run(id: 'c', startedAt: t2, distanceMeters: 10000),
      _run(id: 'd', startedAt: t3, distanceMeters: 9000),
    ]);

    final distance = board.categories
        .firstWhere((c) => c.kind == RunAchievementKind.longestDistance);
    expect(distance.placements.map((p) => p.activity.id), ['b', 'c', 'd']);
    expect(distance.placements.map((p) => p.tier), [
      RunMedalTier.gold,
      RunMedalTier.silver,
      RunMedalTier.bronze,
    ]);
  });

  test('best avg pace excludes sub-1km runs', () {
    final board = RunAchievementEngine.build([
      _run(
        id: 'short',
        startedAt: t0,
        distanceMeters: 400,
        movingTimeSeconds: 80,
        avgPaceSecPerKm: 200,
      ),
      _run(
        id: 'fast',
        startedAt: t1,
        distanceMeters: 5000,
        movingTimeSeconds: 1500,
        avgPaceSecPerKm: 300,
      ),
      _run(
        id: 'slow',
        startedAt: t2,
        distanceMeters: 5000,
        movingTimeSeconds: 2000,
        avgPaceSecPerKm: 400,
      ),
    ]);

    final pace = board.categories
        .firstWhere((c) => c.kind == RunAchievementKind.bestAvgPace);
    expect(pace.placements.map((p) => p.activity.id), ['fast', 'slow']);
  });

  test('earlier run wins tie for higher medal', () {
    final board = RunAchievementEngine.build([
      _run(id: 'later', startedAt: t1, distanceMeters: 10000),
      _run(id: 'earlier', startedAt: t0, distanceMeters: 10000),
    ]);
    final distance = board.categories
        .firstWhere((c) => c.kind == RunAchievementKind.longestDistance);
    expect(distance.placements.first.activity.id, 'earlier');
    expect(distance.placements.first.tier, RunMedalTier.gold);
  });

  test('same activity can hold multiple medals', () {
    final board = RunAchievementEngine.build([
      _run(
        id: 'pr',
        startedAt: t0,
        distanceMeters: 10000,
        movingTimeSeconds: 3000,
        avgPaceSecPerKm: 300,
        bestSplitPaceSecPerKm: 280,
        bestEffort5kSec: 1400,
      ),
      _run(
        id: 'other',
        startedAt: t1,
        distanceMeters: 5000,
        movingTimeSeconds: 2000,
        avgPaceSecPerKm: 400,
        bestSplitPaceSecPerKm: 350,
        bestEffort5kSec: 1600,
      ),
    ]);

    final medals = board.forActivity('pr');
    expect(medals.length, greaterThanOrEqualTo(3));
    expect(medals.any((m) => m.kind == RunAchievementKind.longestDistance), true);
    expect(medals.any((m) => m.kind == RunAchievementKind.bestEffort5k), true);
  });

  test('hides empty effort categories from nonEmptyCategories', () {
    final board = RunAchievementEngine.build([
      _run(id: 'a', startedAt: t0, distanceMeters: 2000),
    ]);
    expect(
      board.nonEmptyCategories.any(
        (c) => c.kind == RunAchievementKind.bestEffortMarathon,
      ),
      false,
    );
  });

  test('recentAchievements returns newest medal runs first, capped', () {
    final board = RunAchievementEngine.build([
      _run(id: 'old', startedAt: t0, distanceMeters: 12000, bestEffort5kSec: 1600),
      _run(id: 'mid', startedAt: t1, distanceMeters: 8000, bestEffort5kSec: 1500),
      _run(id: 'new', startedAt: t3, distanceMeters: 10000, bestEffort5kSec: 1400),
      _run(id: 'also', startedAt: t2, distanceMeters: 9000, avgPaceSecPerKm: 280),
    ]);

    final recent = board.recentAchievements(limit: 5);
    expect(recent.length, lessThanOrEqualTo(5));
    expect(recent, isNotEmpty);
    // Newest run date should appear first among the highlight list.
    expect(
      recent.first.activity.startedAt.isAfter(recent.last.activity.startedAt) ||
          recent.first.activity.startedAt == recent.last.activity.startedAt,
      true,
    );
    for (var i = 1; i < recent.length; i++) {
      expect(
        recent[i - 1].activity.startedAt
                .compareTo(recent[i].activity.startedAt) >=
            0,
        true,
      );
    }
  });
}
