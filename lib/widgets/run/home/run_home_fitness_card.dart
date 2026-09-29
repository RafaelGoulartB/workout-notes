import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_training_load_analytics.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Human label for a training-load status (short form used on the home).
String runLoadStatusLabel(AppLocalizations loc, RunLoadStatus status) =>
    switch (status) {
      RunLoadStatus.balanced => loc.runHomeLoadBalanced,
      RunLoadStatus.rapidIncrease => loc.runHomeLoadRapid,
      RunLoadStatus.detraining => loc.runHomeLoadDetraining,
      RunLoadStatus.insufficientData => loc.runHomeLoadInsufficient,
    };

/// Colour of a training-load status: green-ish when balanced, error when the
/// load is climbing too fast, muted otherwise.
Color runLoadStatusColor(ColorScheme colors, RunLoadStatus status) =>
    switch (status) {
      RunLoadStatus.balanced => colors.primary,
      RunLoadStatus.rapidIncrease => colors.error,
      RunLoadStatus.detraining => colors.tertiary,
      RunLoadStatus.insufficientData => colors.onSurfaceVariant,
    };

/// Short label of a predictor distance (`5K`, `10K`, `Meia`, `Maratona`).
String runRaceDistanceLabel(AppLocalizations loc, double meters) {
  if (meters <= 3000) return loc.runAchievementShort3k;
  if (meters <= 5000) return loc.runAchievementShort5k;
  if (meters <= 10000) return loc.runAchievementShort10k;
  if (meters < 30000) return loc.runAchievementShortHalf;
  return loc.runAchievementShortMarathon;
}

/// "Current fitness": estimated VDOT, race predictions and load status, with
/// a link to the full analysis.
class RunFitnessCard extends StatelessWidget {
  final RunFitnessEstimate? estimate;
  final RunTrainingLoad load;
  final VoidCallback onSeeAll;

  const RunFitnessCard({
    super.key,
    required this.estimate,
    required this.load,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fitness = estimate;

    return RunSectionCard(
      onTap: onSeeAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fitness == null)
            Row(
              children: [
                const RunIconBadge(Icons.favorite_border_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.runHomeFitnessEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RunValueUnit(
                  value: RunFormatters.decimal(fitness.vdot, 1),
                  valueStyle: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      loc.runHomeFitnessVo2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            RunStatRow(
              children: [
                for (final prediction in fitness.predictions)
                  RunStatTile(
                    label: runRaceDistanceLabel(loc, prediction.distanceMeters),
                    value: RunFormatters.duration(prediction.timeSeconds),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: RunUi.divider(colors)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.runHomeLoadLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              RunPill(
                label: runLoadStatusLabel(loc, load.status),
                color: runLoadStatusColor(colors, load.status),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: RunHeaderAction(
              label: loc.runHomeFitnessSeeAll,
              onPressed: onSeeAll,
            ),
          ),
        ],
      ),
    );
  }
}
