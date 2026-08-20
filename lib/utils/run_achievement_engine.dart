import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';

/// Pure all-time ranking of run personal records (top 3 per category).
abstract final class RunAchievementEngine {
  static const double minPaceDistanceMeters = 1000.0;

  static const List<RunAchievementKind> kindOrder = RunAchievementKind.values;

  static RunAchievementBoard build(List<RunActivity> activities) {
    final completed = activities.where((a) => a.isCompleted).toList();
    final categories = <RunAchievementCategory>[];
    final byActivity = <String, List<RunAchievementPlacement>>{};

    for (final kind in kindOrder) {
      final ranked = _rank(completed, kind);
      if (ranked.isEmpty) {
        categories.add(RunAchievementCategory(kind: kind, placements: const []));
        continue;
      }

      final placements = <RunAchievementPlacement>[];
      for (var i = 0; i < ranked.length && i < 3; i++) {
        final tier = RunMedalTier.values[i];
        final entry = ranked[i];
        final placement = RunAchievementPlacement(
          kind: kind,
          tier: tier,
          activity: entry.activity,
          value: entry.value,
        );
        placements.add(placement);
        byActivity
            .putIfAbsent(entry.activity.id, () => <RunAchievementPlacement>[])
            .add(placement);
      }
      categories.add(
        RunAchievementCategory(kind: kind, placements: placements),
      );
    }

    // Prefer showing gold before silver/bronze on badges; stable kind order.
    for (final list in byActivity.values) {
      list.sort((a, b) {
        final tierCmp = a.tier.index.compareTo(b.tier.index);
        if (tierCmp != 0) return tierCmp;
        return a.kind.index.compareTo(b.kind.index);
      });
    }

    return RunAchievementBoard(
      categories: categories,
      byActivityId: byActivity,
    );
  }

  static List<({RunActivity activity, double value})> _rank(
    List<RunActivity> activities,
    RunAchievementKind kind,
  ) {
    final higherIsBetter = switch (kind) {
      RunAchievementKind.longestDistance ||
      RunAchievementKind.longestDuration =>
        true,
      _ => false,
    };

    final scored = <({RunActivity activity, double value})>[];
    for (final activity in activities) {
      final value = _valueFor(activity, kind);
      if (value == null) continue;
      scored.add((activity: activity, value: value));
    }

    scored.sort((a, b) {
      final cmp = higherIsBetter
          ? b.value.compareTo(a.value)
          : a.value.compareTo(b.value);
      if (cmp != 0) return cmp;
      // Tie-break: earlier run wins the higher medal.
      return a.activity.startedAt.compareTo(b.activity.startedAt);
    });
    return scored;
  }

  static double? _valueFor(RunActivity activity, RunAchievementKind kind) {
    switch (kind) {
      case RunAchievementKind.longestDistance:
        if (activity.distanceMeters <= 0) return null;
        return activity.distanceMeters;
      case RunAchievementKind.longestDuration:
        final seconds = activity.movingTimeSeconds > 0
            ? activity.movingTimeSeconds
            : activity.durationSeconds;
        if (seconds <= 0) return null;
        return seconds.toDouble();
      case RunAchievementKind.bestAvgPace:
        final pace = activity.avgPaceSecPerKm;
        if (pace == null ||
            !pace.isFinite ||
            pace <= 0 ||
            activity.distanceMeters < minPaceDistanceMeters) {
          return null;
        }
        return pace;
      case RunAchievementKind.bestKmSplit:
        final pace = activity.bestSplitPaceSecPerKm;
        if (pace == null || !pace.isFinite || pace <= 0) return null;
        return pace;
      case RunAchievementKind.bestEffort1k:
        return _effort(activity.bestEffort1kSec);
      case RunAchievementKind.bestEffort3k:
        return _effort(activity.bestEffort3kSec);
      case RunAchievementKind.bestEffort5k:
        return _effort(activity.bestEffort5kSec);
      case RunAchievementKind.bestEffort10k:
        return _effort(activity.bestEffort10kSec);
      case RunAchievementKind.bestEffortHalf:
        return _effort(activity.bestEffortHalfSec);
      case RunAchievementKind.bestEffortMarathon:
        return _effort(activity.bestEffortMarathonSec);
    }
  }

  static double? _effort(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    return seconds.toDouble();
  }

  /// Formats the ranked value for display.
  static String formatValue(RunAchievementKind kind, double value) {
    switch (kind) {
      case RunAchievementKind.longestDistance:
        final km = value / 1000.0;
        if (km < 10) return '${km.toStringAsFixed(2)} km';
        if (km < 100) return '${km.toStringAsFixed(1)} km';
        return '${km.toStringAsFixed(0)} km';
      case RunAchievementKind.longestDuration:
      case RunAchievementKind.bestEffort1k:
      case RunAchievementKind.bestEffort3k:
      case RunAchievementKind.bestEffort5k:
      case RunAchievementKind.bestEffort10k:
      case RunAchievementKind.bestEffortHalf:
      case RunAchievementKind.bestEffortMarathon:
        return _formatDuration(value.round());
      case RunAchievementKind.bestAvgPace:
      case RunAchievementKind.bestKmSplit:
        return '${_formatPace(value)} /km';
    }
  }

  static String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatPace(double secPerKm) {
    final total = secPerKm.round().clamp(0, 99 * 60 + 59);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
