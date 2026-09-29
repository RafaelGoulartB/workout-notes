import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_route_sketch.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Latest runs, each with a route thumbnail (icon for treadmill or runs
/// without a usable route), title, date, distance and pace.
class RunRecentRuns extends StatelessWidget {
  final List<RunActivity> activities;
  final RunAchievementBoard board;
  final ValueChanged<String> onOpen;

  const RunRecentRuns({
    super.key,
    required this.activities,
    required this.board,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final format = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm();

    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: RunDividedList(
        children: [
          for (final activity in activities)
            RunListRow(
              leading: RunRunThumbnail(activity: activity),
              title: activity.title?.trim().isNotEmpty == true
                  ? activity.title!.trim()
                  : activity.isTreadmill
                  ? loc.runDetailTreadmillUntitled
                  : loc.runDetailUntitled,
              titleTrailing: board.forActivity(activity.id).isEmpty
                  ? null
                  : RunMedalDot(
                      tier: board.forActivity(activity.id).first.tier,
                      size: 14,
                    ),
              subtitle: format.format(activity.startedAt.toLocal()),
              value: RunFormatters.distanceWithUnit(activity.distanceMeters),
              valueCaption: RunFormatters.paceWithUnit(
                activity.avgPaceSecPerKm,
              ),
              onTap: () => onOpen(activity.id),
            ),
        ],
      ),
    );
  }
}

/// 44 dp tile: the GPS trail when there is one, otherwise a type icon.
class RunRunThumbnail extends StatelessWidget {
  final RunActivity activity;
  final double size;

  const RunRunThumbnail({super.key, required this.activity, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final points = activity.isRun
        ? RunRouteSketch.parse(activity.polylineSummary)
        : const <Offset>[];
    final hasRoute = RunRouteSketch.hasShape(points);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: hasRoute
          ? RunRouteSketch.fromSummary(
              activity.polylineSummary,
              size: size - 12,
              color: colors.primary,
              endColor: colors.tertiary,
            )
          : Icon(
              activity.isIndoor ? Icons.fitness_center : Icons.directions_run,
              size: 22,
              color: colors.onPrimaryContainer,
            ),
    );
  }
}
