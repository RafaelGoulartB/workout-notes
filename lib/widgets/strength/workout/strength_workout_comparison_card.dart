import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Volume, sets and duration deltas against the previous comparable session.
class StrengthWorkoutComparisonCard extends StatelessWidget {
  final StrengthWorkoutDetail detail;

  const StrengthWorkoutComparisonCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final comparison = detail.comparison;
    final comparable = detail.comparable;
    if (comparison == null || comparable == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final previousDay = DateTime.tryParse(comparable.date);
    final date = previousDay == null
        ? comparable.date
        : DateFormat.MMMd(locale).format(previousDay);
    final name = detail.comparableName?.trim();
    final label =
        comparable.basis != WorkoutComparisonBasis.exercises &&
            name != null &&
            name.isNotEmpty
        ? loc.workoutDetailComparisonVsDay(name, date)
        : loc.workoutDetailComparisonVsSimilar(date);

    final volume = comparison.volumeDelta;
    final sets = comparison.setsDelta;
    final duration = comparison.durationDelta;
    final density = comparison.densityDelta;

    Widget trend(String title, String value, num delta) => delta == 0
        ? RunPill(
            label: '$title $value',
            icon: Icons.trending_flat_rounded,
            color: colors.onSurfaceVariant,
          )
        : RunPill.trend(
            context: context,
            label: '$title $value',
            positive: delta > 0,
          );

    return RunSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              trend(
                loc.commonVolume,
                StrengthWorkoutFormat.signedVolume(volume),
                volume.abs() < 0.5 ? 0 : volume,
              ),
              trend(
                loc.workoutDetailWorkingSets,
                StrengthWorkoutFormat.signedInt(sets),
                sets,
              ),
              if (duration != 0 &&
                  comparison.current.durationSeconds > 0 &&
                  comparison.previous.durationSeconds > 0)
                RunPill(
                  label:
                      '${loc.activeWorkoutTimerDuration} ${StrengthWorkoutFormat.signedDuration(duration)}',
                  icon: Icons.schedule_rounded,
                  color: colors.onSurfaceVariant,
                ),
              if (density != null)
                trend(
                  loc.workoutStatsDensity,
                  '${density > 0 ? '+' : ''}${RunFormatters.decimal(density, density.abs() >= 10 ? 0 : 1)} ${loc.workoutStatsKgPerMin}',
                  density,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
