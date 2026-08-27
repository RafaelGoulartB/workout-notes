import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_plan_composer.dart';

/// Compact week-by-week volume bars coloured by periodisation phase.
class RunPlanVolumeSparkline extends StatelessWidget {
  final List<RunPlanWeekOutline> weeks;

  const RunPlanVolumeSparkline({super.key, required this.weeks});

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
                          '${weeks[i].weekKm.toStringAsFixed(0)} km · '
                          '${_phaseLabel(loc, weeks[i].phase)}',
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          widthFactor: 1,
                          heightFactor: (weeks[i].weekKm / maxKm).clamp(
                            0.08,
                            1,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: phaseColor(
                                theme.colorScheme,
                                weeks[i].phase,
                              ),
                              borderRadius: BorderRadius.circular(3),
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
                      _phaseLabel(loc, phase),
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

  static String _phaseLabel(AppLocalizations loc, RunPlanWeekPhase phase) =>
      switch (phase) {
        RunPlanWeekPhase.build => loc.runPlanCustomizePhaseBuild,
        RunPlanWeekPhase.recovery => loc.runPlanCustomizePhaseRecovery,
        RunPlanWeekPhase.taper => loc.runPlanCustomizePhaseTaper,
        RunPlanWeekPhase.race => loc.runPlanCustomizePhaseRace,
      };
}
