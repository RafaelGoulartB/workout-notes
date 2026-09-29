import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// One card with the period highlights (longest run, best pace, best km) and
/// the most recent all-time medals that are not already listed above.
class RunRecordsSection extends StatelessWidget {
  final RunProgressAnalytics analytics;
  final RunAchievementBoard board;
  final ValueChanged<String> onOpenActivity;

  const RunRecordsSection({
    super.key,
    required this.analytics,
    required this.board,
    required this.onOpenActivity,
  });

  /// Medal the [activity] holds for [kind], if any.
  static RunAchievementPlacement? _medal(
    RunAchievementBoard board,
    RunActivity? activity,
    RunAchievementKind kind,
  ) {
    if (activity == null) return null;
    for (final placement in board.forActivity(activity.id)) {
      if (placement.kind == kind) return placement;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dateFormat = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    );

    final longest = analytics.longestRun;
    final fastest = analytics.fastestRun;
    final bestKm = analytics.bestKmSplitRun;

    Widget highlight({
      required IconData icon,
      required String label,
      required RunActivity run,
      required String value,
      required RunAchievementKind kind,
    }) {
      final medal = _medal(board, run, kind);
      return RunListRow(
        leading: RunIconBadge(icon),
        title: label,
        titleTrailing: medal == null
            ? null
            : RunMedalDot(tier: medal.tier, size: 14),
        subtitle: dateFormat.format(run.startedAt.toLocal()),
        value: value,
        onTap: () => onOpenActivity(run.id),
      );
    }

    final highlights = <Widget>[
      if (longest != null)
        highlight(
          icon: Icons.straighten_rounded,
          label: loc.runStatsLongestRun,
          run: longest,
          value: RunFormatters.distanceWithUnit(longest.distanceMeters),
          kind: RunAchievementKind.longestDistance,
        ),
      if (fastest != null)
        highlight(
          icon: Icons.bolt_rounded,
          label: loc.runStatsBestPace,
          run: fastest,
          value: RunFormatters.paceWithUnit(analytics.bestPaceSecPerKm),
          kind: RunAchievementKind.bestAvgPace,
        ),
      if (bestKm != null)
        highlight(
          icon: Icons.timer_outlined,
          label: loc.runStatsBestKmSplit,
          run: bestKm,
          value: RunFormatters.paceWithUnit(analytics.bestKmSplitSecPerKm),
          kind: RunAchievementKind.bestKmSplit,
        ),
    ];

    // Recent medals, skipping the ones the highlights above already show.
    final shown = <(RunAchievementKind, String)>{
      if (longest != null) (RunAchievementKind.longestDistance, longest.id),
      if (fastest != null) (RunAchievementKind.bestAvgPace, fastest.id),
      if (bestKm != null) (RunAchievementKind.bestKmSplit, bestKm.id),
    };
    final recent = [
      for (final p in board.recentAchievements(limit: 12))
        if (!shown.contains((p.kind, p.activity.id))) p,
    ].take(3).toList();

    if (highlights.isEmpty && recent.isEmpty) {
      return RunSectionCard(
        child: Text(
          loc.runAchievementEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }

    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlights.isNotEmpty) ...[
            _GroupLabel(loc.runHomeRecordsPeriodTag),
            RunDividedList(children: highlights),
          ],
          if (recent.isNotEmpty) ...[
            if (highlights.isNotEmpty)
              Divider(height: 1, color: RunUi.divider(colors)),
            _GroupLabel(loc.runHomeRecordsRecentTag),
            RunDividedList(
              children: [
                for (final placement in recent)
                  RunListRow(
                    leading: RunMedalDot(tier: placement.tier, size: 30),
                    title: runAchievementKindLabel(loc, placement.kind),
                    subtitle: dateFormat.format(
                      placement.activity.startedAt.toLocal(),
                    ),
                    value: RunAchievementEngine.formatValue(
                      placement.kind,
                      placement.value,
                    ),
                    onTap: () => onOpenActivity(placement.activity.id),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
