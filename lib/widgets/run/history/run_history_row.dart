import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_activity_filter.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_route_sketch.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

IconData runActivityTypeIcon(CardioActivityType type) => switch (type) {
  CardioActivityType.running => Icons.directions_run_rounded,
  CardioActivityType.treadmill => Icons.speed_rounded,
  CardioActivityType.stationaryBike => Icons.pedal_bike_rounded,
};

/// Month section header: month name on the left, totals on the right.
class RunHistoryMonthHeader extends StatelessWidget {
  final DateTime month;
  final RunActivityTotals? totals;

  const RunHistoryMonthHeader({super.key, required this.month, this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final label = DateFormat.yMMMM(locale).format(month);
    final totals = this.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              toBeginningOfSentenceCase(label, locale) ?? label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (totals != null)
            Text(
              loc.runHistoryMonthTotals(
                totals.count,
                RunFormatters.distanceWithUnit(totals.distanceMeters),
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: AppUi.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact activity row with a route thumbnail (icon fallback).
class RunHistoryRow extends StatelessWidget {
  final RunActivity activity;
  final List<RunAchievementPlacement> medals;
  final VoidCallback onTap;

  const RunHistoryRow({
    super.key,
    required this.activity,
    required this.medals,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat(
      'EEE, d MMM · HH:mm',
      locale,
    ).format(activity.startedAt.toLocal());
    final title = activity.title?.isNotEmpty == true
        ? activity.title!
        : loc.runDetailUntitled;
    final isBike = activity.activityType == CardioActivityType.stationaryBike;
    final caption = isBike
        ? RunFormatters.duration(activity.movingTimeSeconds)
        : '${RunFormatters.paceWithUnit(activity.avgPaceSecPerKm)} · '
              '${RunFormatters.duration(activity.movingTimeSeconds)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppUi.tileRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            _Thumbnail(activity: activity),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (activity.planWorkoutId != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.event_note_rounded,
                          size: 14,
                          color: colors.primary,
                          semanticLabel: loc.runHistoryPlanBadge,
                        ),
                      ],
                      if (medals.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _MedalMark(medals: medals),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  RunFormatters.distanceWithUnit(activity.distanceMeters),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final RunActivity activity;

  const _Thumbnail({required this.activity});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final points = RunRouteSketch.parse(activity.polylineSummary);
    final hasShape = RunRouteSketch.hasShape(points);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.primaryContainer.withAlpha(hasShape ? 90 : 255),
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
      ),
      child: hasShape
          ? Padding(
              padding: const EdgeInsets.all(6),
              child: RunRouteSketch(
                points: points,
                width: 36,
                height: 36,
                strokeWidth: 2.2,
              ),
            )
          : Icon(
              runActivityTypeIcon(activity.activityType),
              color: colors.onPrimaryContainer,
              size: 24,
            ),
    );
  }
}

/// Best medal of the run as one small dot, with the count when several.
class _MedalMark extends StatelessWidget {
  final List<RunAchievementPlacement> medals;

  const _MedalMark({required this.medals});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final best = medals.reduce((a, b) => a.tier.index <= b.tier.index ? a : b);
    return Semantics(
      label: loc.runHistoryMedalsSemantics(medals.length),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RunMedalDot(tier: best.tier, size: 14),
          if (medals.length > 1) ...[
            const SizedBox(width: 2),
            Text(
              '${medals.length}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ],
      ),
    );
  }
}
