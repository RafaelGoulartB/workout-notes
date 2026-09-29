import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Horizontal week picker. Every tile shows the planned volume as a ghost bar
/// and the kilometres actually run as a filled bar on top of it, so the ramp,
/// the taper and the adherence are visible while picking a week.
class RunPlanWeekStrip extends StatelessWidget {
  static const tileWidth = 58.0;

  final RunPlan plan;
  final ScrollController controller;
  final int selectedWeek;

  /// Week running today (zero-based), when the plan is followed.
  final int? currentWeek;
  final Set<int> scheduledWeeks;

  /// Kilometres run per week (meters), aligned with the plan weeks.
  final List<double> doneMeters;

  /// Weeks whose every session is done.
  final Set<int> completedWeeks;
  final ValueChanged<int> onSelect;

  const RunPlanWeekStrip({
    super.key,
    required this.plan,
    required this.controller,
    required this.selectedWeek,
    required this.currentWeek,
    required this.scheduledWeeks,
    required this.doneMeters,
    required this.completedWeeks,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final volumes = [
      for (var week = 0; week < plan.weeks; week++)
        plan.weeklyDistanceMeters(week),
    ];
    final peak = volumes.fold<double>(0, (max, v) => v > max ? v : max);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunSectionHeader(
          loc.runPlanWeeklyVolumeTitle,
          padding: const EdgeInsets.fromLTRB(2, 0, 0, 8),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RunLegendItem(
                color: scheme.primary,
                label: loc.runPlanDetailLegendDone,
              ),
              const SizedBox(width: 12),
              RunLegendItem(
                color: scheme.primary.withAlpha(70),
                label: loc.runPlanDetailLegendPlanned,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            controller: controller,
            scrollDirection: Axis.horizontal,
            itemCount: plan.weeks,
            itemExtent: tileWidth,
            itemBuilder: (context, week) => _WeekTile(
              week: week,
              planned: volumes[week],
              done: week < doneMeters.length ? doneMeters[week] : 0,
              peak: peak,
              selected: week == selectedWeek,
              current: week == currentWeek,
              scheduled: scheduledWeeks.contains(week),
              completed: completedWeeks.contains(week),
              onTap: () => onSelect(week),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekTile extends StatelessWidget {
  final int week;
  final double planned;
  final double done;
  final double peak;
  final bool selected;
  final bool current;
  final bool scheduled;
  final bool completed;
  final VoidCallback onTap;

  const _WeekTile({
    required this.week,
    required this.planned,
    required this.done,
    required this.peak,
    required this.selected,
    required this.current,
    required this.scheduled,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    // Never a fixed bar height: the text around it grows with the system font
    // scale, and the bar is the part that can afford to shrink.
    final plannedFill = peak <= 0 ? 0.04 : (planned / peak).clamp(0.04, 1.0);
    final doneFill = planned <= 0 ? 0.0 : (done / planned).clamp(0.0, 1.0);

    return Semantics(
      button: true,
      selected: selected,
      label: loc.runPlanDetailWeekTileSemantics(
        week + 1,
        RunPlanUi.kmValue(done),
        RunPlanUi.kmValue(planned),
      ),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withAlpha(70),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: current && !selected
                ? BorderSide(color: scheme.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                children: [
                  Text(
                    planned <= 0 ? '—' : RunPlanUi.kmValue(planned),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: FractionallySizedBox(
                      alignment: Alignment.bottomCenter,
                      heightFactor: plannedFill,
                      child: Container(
                        width: 18,
                        decoration: BoxDecoration(
                          color: scheme.primary.withAlpha(selected ? 90 : 60),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                        child: doneFill <= 0
                            ? null
                            : FractionallySizedBox(
                                alignment: Alignment.bottomCenter,
                                heightFactor: doneFill,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(
                                        doneFill >= 1 ? 3 : 0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${week + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : current
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                      ),
                      if (completed) ...[
                        const SizedBox(width: 3),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: scheme.tertiary,
                        ),
                      ] else if (scheduled) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.circle, size: 5, color: scheme.tertiary),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
