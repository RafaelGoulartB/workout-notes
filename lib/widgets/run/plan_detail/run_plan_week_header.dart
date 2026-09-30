import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Header of the selected week: name, dates, totals and the one place where
/// the week is scheduled (a button while it is not, a badge once it is).
class RunPlanWeekHeader extends StatelessWidget {
  final RunPlan plan;
  final int week;

  /// Monday of the week when the plan is followed.
  final DateTime? weekStart;
  final bool isCurrent;
  final bool scheduled;
  final double doneMeters;
  final VoidCallback onSchedule;
  final VoidCallback? onCopy;

  const RunPlanWeekHeader({
    super.key,
    required this.plan,
    required this.week,
    required this.weekStart,
    required this.isCurrent,
    required this.scheduled,
    required this.doneMeters,
    required this.onSchedule,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final sessions = plan.workoutsForWeek(week);
    final longRun = plan.longRunForWeek(week);
    final quality = plan.qualitySessionsForWeek(week);
    final planned = plan.weeklyDistanceMeters(week);
    final start = weekStart;
    String? range;
    if (start != null) {
      final end = DateTime(start.year, start.month, start.day + 6);
      final startText = start.month == end.month
          ? DateFormat('d', locale).format(start)
          : DateFormat('d MMM', locale).format(start);
      range = '$startText – ${DateFormat('d MMM', locale).format(end)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: loc.runPlanWeekLabel(week + 1)),
                    if (range != null)
                      TextSpan(
                        text: '   $range',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (isCurrent)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: AppPill(label: loc.runPlanDetailCurrentWeekMark),
              ),
            if (scheduled)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: AppPill(
                  icon: Icons.event_available,
                  label: loc.runPlanWeekScheduled,
                  color: scheme.tertiary,
                ),
              ),
            if (onCopy != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                onSelected: (_) => onCopy!(),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'copy',
                    child: Text(loc.runPlanCopyWeek),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AppPill(
              icon: Icons.straighten,
              color: scheme.onSurfaceVariant,
              label: loc.runPlanWeekSummary(
                RunPlanUi.kmValue(planned),
                sessions.length,
              ),
            ),
            if (doneMeters > 0)
              AppPill(
                icon: Icons.check_circle_outline_rounded,
                label: loc.runPlanDetailWeekProgress(
                  RunPlanUi.kmValue(doneMeters),
                  RunPlanUi.kmValue(planned),
                ),
              ),
            if (longRun != null)
              AppPill(
                icon: Icons.timeline,
                color: scheme.onSurfaceVariant,
                label:
                    '${loc.runPlanLongRun} '
                    '${RunPlanUi.distanceLabel(longRun.plannedDistanceMeters)}',
              ),
            if (quality > 0)
              AppPill(
                icon: Icons.bolt,
                label: loc.runPlanQualityCount(quality),
              ),
          ],
        ),
        if (!scheduled && sessions.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onSchedule,
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text(loc.runPlanScheduleWeek),
            ),
          ),
        ],
      ],
    );
  }
}
