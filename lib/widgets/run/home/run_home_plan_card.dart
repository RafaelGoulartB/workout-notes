import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Active plan summary: name, week X of Y, progress and the next session.
/// Tapping opens the plan; "All plans" opens the library.
class RunActivePlanCard extends StatelessWidget {
  final RunPlanContext planContext;
  final RunPlannedSession? next;
  final DateTime today;
  final VoidCallback onOpenPlan;
  final VoidCallback onAllPlans;

  const RunActivePlanCard({
    super.key,
    required this.planContext,
    required this.next,
    required this.today,
    required this.onOpenPlan,
    required this.onAllPlans,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final plan = planContext.plan;
    final progress = planContext.progress;
    final weekNumber = planContext.weekNumber;
    final finished = plan.isFinishedOn(today);

    final subtitle = <String>[
      RunPlanUi.goalLabel(loc, plan.goalKind),
      if (weekNumber != null)
        loc.runHomePlanWeekOf(weekNumber, plan.weeks)
      else if (finished)
        loc.runHomePlanFinished,
    ].join(' · ');

    String? nextText;
    final upcoming = next;
    if (upcoming != null) {
      final day = DateFormat.E(
        Localizations.localeOf(context).toString(),
      ).format(upcoming.date);
      final distance = upcoming.workout.plannedDistanceMeters;
      nextText = loc.runHomePlanNext(
        distance > 0
            ? loc.runHomeTodayNextValue(
                toBeginningOfSentenceCase(day),
                upcoming.workout.name,
                RunPlanUi.distanceLabel(distance),
              )
            : loc.runHomeTodayNextValueNoDistance(
                toBeginningOfSentenceCase(day),
                upcoming.workout.name,
              ),
      );
    }

    return RunSectionCard(
      onTap: onOpenPlan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const RunIconBadge(Icons.route_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
          if (progress.totalSessions > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ],
          if (nextText != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  RunPlanUi.kindIcon(upcoming!.workout.kind),
                  size: 16,
                  color: RunPlanUi.kindColor(colors, upcoming.workout.kind),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nextText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          Row(
            children: [
              if (progress.totalSessions > 0)
                Expanded(
                  child: Text(
                    loc.runPlanProgressValue(
                      progress.completedSessions,
                      progress.totalSessions,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                )
              else
                const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: onAllPlans,
                child: Text(loc.runHomePlanAll),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
