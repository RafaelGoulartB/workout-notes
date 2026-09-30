import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// Compact week-by-week volume bars coloured by periodisation phase.
class RunPlanVolumeSparkline extends StatelessWidget {
  final List<RunPlanWeekOutline> weeks;

  /// Highlighted week (zero-based); the others are dimmed.
  final int? selected;

  /// Called with the zero-based week when a bar is tapped.
  final ValueChanged<int>? onSelect;

  const RunPlanVolumeSparkline({
    super.key,
    required this.weeks,
    this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final maxKm = weeks.fold<double>(
      1,
      (peak, week) => week.weekKm > peak ? week.weekKm : peak,
    );
    final phases = <RunPlanWeekPhase>{for (final week in weeks) week.phase};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 64,
          child: Semantics(
            label: loc.runPlanCustomizePreviewSparkline,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < weeks.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Tooltip(
                      message:
                          '${loc.runPlanWeeksValue(i + 1)} · '
                          '${RunFormatters.decimal(weeks[i].weekKm, 0)} km · '
                          '${phaseLabel(loc, weeks[i].phase)}',
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 1,
                          heightFactor: (weeks[i].weekKm / maxKm).clamp(
                            0.08,
                            1,
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onSelect == null ? null : () => onSelect!(i),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color:
                                    phaseColor(
                                      theme.colorScheme,
                                      weeks[i].phase,
                                    ).withValues(
                                      alpha: selected == null || selected == i
                                          ? 1
                                          : 0.45,
                                    ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final phase in RunPlanWeekPhase.values)
              if (phases.contains(phase))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: phaseColor(theme.colorScheme, phase),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      phaseLabel(loc, phase),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }

  static Color phaseColor(ColorScheme scheme, RunPlanWeekPhase phase) =>
      switch (phase) {
        RunPlanWeekPhase.build => scheme.primary,
        RunPlanWeekPhase.recovery => scheme.tertiary,
        RunPlanWeekPhase.taper => scheme.secondary,
        RunPlanWeekPhase.race => scheme.error,
      };

  static String phaseLabel(AppLocalizations loc, RunPlanWeekPhase phase) =>
      switch (phase) {
        RunPlanWeekPhase.build => loc.runPlanCustomizePhaseBuild,
        RunPlanWeekPhase.recovery => loc.runPlanCustomizePhaseRecovery,
        RunPlanWeekPhase.taper => loc.runPlanCustomizePhaseTaper,
        RunPlanWeekPhase.race => loc.runPlanCustomizePhaseRace,
      };
}
