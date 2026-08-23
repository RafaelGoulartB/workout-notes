import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';

String runAchievementKindLabel(
  AppLocalizations loc,
  RunAchievementKind kind,
) {
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

/// Compact highlight card: last [limit] medals attained (by run date).
class RunAchievementsSection extends StatelessWidget {
  final RunAchievementBoard board;
  final void Function(String activityId) onOpenActivity;
  final int limit;

  /// The stats dashboard already labels the card with a section header, so it
  /// hides the inner title and subtitle to avoid repeating them.
  final bool showTitle;

  const RunAchievementsSection({
    super.key,
    required this.board,
    required this.onOpenActivity,
    this.limit = 5,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final recent = board.recentAchievements(limit: limit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle) ...[
          Text(
            loc.runAchievementBoardTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            loc.runAchievementRecentSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (recent.isEmpty)
          Text(
            loc.runAchievementEmpty,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          )
        else
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.4),
              ),
            _RecentAchievementTile(
              placement: recent[i],
              locale: locale,
              onTap: () => onOpenActivity(recent[i].activity.id),
            ),
          ],
      ],
    );
  }
}

/// Medals earned by a single activity (detail screen).
class RunActivityAchievementsBlock extends StatelessWidget {
  final List<RunAchievementPlacement> placements;

  const RunActivityAchievementsBlock({
    super.key,
    required this.placements,
  });

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

class _RecentAchievementTile extends StatelessWidget {
  final RunAchievementPlacement placement;
  final String locale;
  final VoidCallback onTap;

  const _RecentAchievementTile({
    required this.placement,
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final colors = theme.colorScheme;
    final date = DateFormat.yMMMd(locale).format(
      placement.activity.startedAt.toLocal(),
    );
    final value = RunAchievementEngine.formatValue(
      placement.kind,
      placement.value,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            RunMedalDot(tier: placement.tier, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    runAchievementKindLabel(loc, placement.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$value · $date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
