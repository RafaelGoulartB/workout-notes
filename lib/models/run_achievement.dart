import 'package:workout_notes/models/run_activity.dart';

/// Personal-record categories ranked all-time (gold / silver / bronze).
enum RunAchievementKind {
  longestDistance,
  longestDuration,
  bestAvgPace,
  bestKmSplit,
  bestEffort1k,
  bestEffort3k,
  bestEffort5k,
  bestEffort10k,
  bestEffortHalf,
  bestEffortMarathon,
}

enum RunMedalTier {
  gold,
  silver,
  bronze,
}

extension RunMedalTierRank on RunMedalTier {
  /// 1 = gold, 2 = silver, 3 = bronze.
  int get place => index + 1;
}

class RunAchievementPlacement {
  final RunAchievementKind kind;
  final RunMedalTier tier;
  final RunActivity activity;

  /// Sort key used for ranking (meters, seconds, or sec/km depending on kind).
  final double value;

  const RunAchievementPlacement({
    required this.kind,
    required this.tier,
    required this.activity,
    required this.value,
  });
}

class RunAchievementCategory {
  final RunAchievementKind kind;
  final List<RunAchievementPlacement> placements;

  const RunAchievementCategory({
    required this.kind,
    required this.placements,
  });

  bool get isEmpty => placements.isEmpty;
}

/// Full all-time board + per-activity medal lookup for list badges.
class RunAchievementBoard {
  final List<RunAchievementCategory> categories;
  final Map<String, List<RunAchievementPlacement>> byActivityId;

  const RunAchievementBoard({
    required this.categories,
    required this.byActivityId,
  });

  static const empty = RunAchievementBoard(
    categories: [],
    byActivityId: {},
  );

  List<RunAchievementPlacement> forActivity(String activityId) =>
      byActivityId[activityId] ?? const [];

  List<RunAchievementCategory> get nonEmptyCategories =>
      categories.where((c) => c.placements.isNotEmpty).toList();

  /// Most recently attained medals (by run date), newest first.
  List<RunAchievementPlacement> recentAchievements({int limit = 5}) {
    final all = <RunAchievementPlacement>[
      for (final category in categories) ...category.placements,
    ];
    all.sort((a, b) {
      final dateCmp = b.activity.startedAt.compareTo(a.activity.startedAt);
      if (dateCmp != 0) return dateCmp;
      final tierCmp = a.tier.index.compareTo(b.tier.index);
      if (tierCmp != 0) return tierCmp;
      return a.kind.index.compareTo(b.kind.index);
    });
    if (all.length <= limit) return all;
    return all.take(limit).toList();
  }
}
