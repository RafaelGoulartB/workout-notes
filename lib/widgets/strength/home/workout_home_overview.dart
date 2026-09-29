import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';

/// Compact "this week" overview of the Treino tab, across the gym and
/// running: strength sessions, kilometres run, active time and the week
/// streak.
class WorkoutWeekOverviewCard extends StatelessWidget {
  final WorkoutWeekOverview overview;

  const WorkoutWeekOverviewCard({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: RunStatRow(
        children: [
          RunStatTile(
            icon: Icons.fitness_center,
            color: colors.primary,
            label: loc.workoutHomeOverviewStrength,
            value: '${overview.strengthSessions}',
          ),
          RunStatTile(
            icon: Icons.directions_run,
            color: colors.tertiary,
            label: loc.workoutHomeOverviewRun,
            value: RunFormatters.distanceKm(overview.runMeters),
            unit: 'km',
          ),
          RunStatTile(
            icon: Icons.timer_outlined,
            color: colors.secondary,
            label: loc.workoutHomeOverviewTime,
            value: StrengthHomeFormat.duration(overview.activeSeconds),
          ),
          RunStatTile(
            icon: Icons.local_fire_department_rounded,
            color: Colors.orange,
            label: loc.workoutHomeOverviewStreak,
            value: '${overview.streakWeeks}',
            unit: loc.workoutHomeWeeksShort,
          ),
        ],
      ),
    );
  }
}

/// Large entry card to a training hub (Musculação or Corrida) with a short
/// summary and a start button.
class WorkoutHubCard extends StatelessWidget {
  final Key? actionKey;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? detail;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onOpen;
  final VoidCallback onAction;

  const WorkoutHubCard({
    super.key,
    this.actionKey,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.detail,
    required this.actionLabel,
    required this.actionIcon,
    required this.onOpen,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return RunSectionCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RunIconBadge(icon, color: color, size: 48, iconSize: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
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
          const SizedBox(height: 14),
          FilledButton.icon(
            key: actionKey,
            onPressed: onAction,
            icon: Icon(actionIcon),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
