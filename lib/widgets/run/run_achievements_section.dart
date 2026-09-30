import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';

String runAchievementKindLabel(AppLocalizations loc, RunAchievementKind kind) {
  return switch (kind) {
    RunAchievementKind.longestDistance => loc.runAchievementLongestDistance,
    RunAchievementKind.longestDuration => loc.runAchievementLongestDuration,
    RunAchievementKind.bestAvgPace => loc.runAchievementBestAvgPace,
    RunAchievementKind.bestKmSplit => loc.runAchievementBestKmSplit,
    RunAchievementKind.bestEffort1k => loc.runAchievementBestEffort1k,
    RunAchievementKind.bestEffort3k => loc.runAchievementBestEffort3k,
    RunAchievementKind.bestEffort5k => loc.runAchievementBestEffort5k,
    RunAchievementKind.bestEffort10k => loc.runAchievementBestEffort10k,
    RunAchievementKind.bestEffortHalf => loc.runAchievementBestEffortHalf,
    RunAchievementKind.bestEffortMarathon =>
      loc.runAchievementBestEffortMarathon,
  };
}

String runAchievementKindShortLabel(
  AppLocalizations loc,
  RunAchievementKind kind,
) {
  return switch (kind) {
    RunAchievementKind.longestDistance => loc.runAchievementShortDistance,
    RunAchievementKind.longestDuration => loc.runAchievementShortDuration,
    RunAchievementKind.bestAvgPace => loc.runAchievementShortAvgPace,
    RunAchievementKind.bestKmSplit => loc.runAchievementShortKmSplit,
    RunAchievementKind.bestEffort1k => loc.runAchievementShort1k,
    RunAchievementKind.bestEffort3k => loc.runAchievementShort3k,
    RunAchievementKind.bestEffort5k => loc.runAchievementShort5k,
    RunAchievementKind.bestEffort10k => loc.runAchievementShort10k,
    RunAchievementKind.bestEffortHalf => loc.runAchievementShortHalf,
    RunAchievementKind.bestEffortMarathon => loc.runAchievementShortMarathon,
  };
}

/// Medals earned by a single activity (detail screen).
class RunActivityAchievementsBlock extends StatelessWidget {
  final List<RunAchievementPlacement> placements;

  const RunActivityAchievementsBlock({super.key, required this.placements});

  @override
  Widget build(BuildContext context) {
    if (placements.isEmpty) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loc.runAchievementSectionTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in placements)
              RunMedalBadge(
                tier: p.tier,
                label:
                    '${_tierLabel(loc, p.tier)} · ${runAchievementKindShortLabel(loc, p.kind)}',
              ),
          ],
        ),
      ],
    );
  }

  String _tierLabel(AppLocalizations loc, RunMedalTier tier) {
    return switch (tier) {
      RunMedalTier.gold => loc.runAchievementTierGold,
      RunMedalTier.silver => loc.runAchievementTierSilver,
      RunMedalTier.bronze => loc.runAchievementTierBronze,
    };
  }
}
