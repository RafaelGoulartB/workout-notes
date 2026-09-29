import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/home/run_home_fitness_card.dart';
import 'package:workout_notes/widgets/run/run_insights_charts.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Small bold title inside an insights card, with an optional hint below.
class RunInsightsCardTitle extends StatelessWidget {
  final String title;
  final String? hint;

  const RunInsightsCardTitle(this.title, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Muted explanatory line.
class RunInsightsNote extends StatelessWidget {
  final String text;

  const RunInsightsNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ===================== FITNESS =====================

/// VDOT / VO2max estimate with its monthly evolution.
class RunFitnessSection extends StatelessWidget {
  final RunFitnessEstimate? estimate;
  final List<RunVdotPoint> evolution;

  const RunFitnessSection({
    super.key,
    required this.estimate,
    required this.evolution,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final fitness = estimate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsFitnessTitle),
        RunSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (fitness == null)
                RunInsightsNote(loc.runInsightsFitnessEmpty)
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RunValueUnit(
                      value: RunFormatters.decimal(fitness.vdot, 1),
                      valueStyle: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          loc.runHomeFitnessVo2,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                RunInsightsNote(
                  loc.runInsightsFitnessBasedOn(
                    runRaceDistanceLabel(loc, fitness.source.distanceMeters),
                    DateFormat.yMMMd(locale).format(fitness.source.date),
                  ),
                ),
                if (fitness.fromTrainingRuns) ...[
                  const SizedBox(height: 6),
                  Text(
                    loc.runInsightsFitnessFromTraining,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.tertiary,
                    ),
                  ),
                ] else if (fitness.isStale) ...[
                  const SizedBox(height: 6),
                  Text(
                    loc.runInsightsFitnessStale,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.tertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                RunInsightsCardTitle(loc.runInsightsFitnessEvolution),
                RunVdotChart(
                  points: evolution,
                  emptyLabel: loc.runInsightsFitnessEvolutionEmpty,
                ),
                const SizedBox(height: 10),
                RunInsightsNote(loc.runInsightsApproxNote),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== RACE PREDICTOR =====================

class RunPredictorSection extends StatelessWidget {
  final RunFitnessEstimate estimate;

  const RunPredictorSection({super.key, required this.estimate});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final head = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsPredictorTitle),
        RunSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(loc.runReviewDistance, style: head),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      loc.runRecordTime,
                      textAlign: TextAlign.end,
                      style: head,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      loc.runRecordPace,
                      textAlign: TextAlign.end,
                      style: head,
                    ),
                  ),
                ],
              ),
              Divider(height: 16, color: RunUi.divider(colors)),
              for (final p in estimate.predictions) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          runRaceDistanceLabel(loc, p.distanceMeters),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          RunFormatters.duration(p.timeSeconds),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: RunUi.tabular,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          RunFormatters.paceWithUnit(p.paceSecPerKm),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: RunUi.tabular,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              RunInsightsNote(loc.runInsightsPredictorNote),
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== TRAINING LOAD =====================

class RunLoadSection extends StatelessWidget {
  final RunTrainingLoad load;

  const RunLoadSection({super.key, required this.load});

  String _statusText(AppLocalizations loc) => switch (load.status) {
    RunLoadStatus.balanced => loc.runInsightsLoadTextBalanced,
    RunLoadStatus.rapidIncrease => loc.runInsightsLoadTextRapid,
    RunLoadStatus.detraining => loc.runInsightsLoadTextDetraining,
    RunLoadStatus.insufficientData => loc.runInsightsLoadTextInsufficient,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = runLoadStatusColor(colors, load.status);
    final growth = load.weeklyVolumeGrowth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsLoadTitle),
        RunSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  RunPill(
                    label: runLoadStatusLabel(loc, load.status),
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  if (load.acwr != null)
                    Expanded(
                      child: Text(
                        loc.runInsightsLoadRatio(
                          RunFormatters.decimal(load.acwr!, 2),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: RunUi.tabular,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_statusText(loc), style: theme.textTheme.bodyMedium),
              const SizedBox(height: 14),
              RunLoadChart(days: load.days),
              const SizedBox(height: 12),
              RunStatRow(
                children: [
                  RunStatTile(
                    label: loc.runInsightsWeeklyLoad,
                    value: RunFormatters.decimal(load.weeklyLoad, 0),
                  ),
                  RunStatTile(
                    label: loc.runInsightsLoadAcute,
                    value: RunFormatters.decimal(load.days.last.acute, 0),
                  ),
                  RunStatTile(
                    label: loc.runInsightsLoadChronic,
                    value: RunFormatters.decimal(load.days.last.chronic, 0),
                  ),
                ],
              ),
              if (load.volumeGrowthWarning) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(RunUi.tileRadius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          loc.runInsightsVolumeWarning((growth! * 100).round()),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (growth != null) ...[
                const SizedBox(height: 12),
                RunInsightsNote(
                  loc.runInsightsVolumeChange(
                    '${growth >= 0 ? '+' : '-'}${(growth.abs() * 100).round()}%',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              RunInsightsNote(loc.runInsightsLoadHelp),
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== INTENSITY =====================

class RunIntensitySection extends StatelessWidget {
  final RunIntensityDistribution? distribution;
  final RunZoneBounds? zones;

  const RunIntensitySection({
    super.key,
    required this.distribution,
    required this.zones,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = distribution;
    final bounds = zones;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsIntensityTitle),
        RunSectionCard(
          child: data == null || bounds == null || !data.hasData
              ? RunInsightsNote(loc.runInsightsIntensityEmpty)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RunInsightsNote(loc.runInsightsIntensityHelp),
                    const SizedBox(height: 12),
                    RunIntensityChart(weeks: data.weeks),
                    const SizedBox(height: 14),
                    Text(
                      loc.runInsightsIntensitySplit(
                        (data.easyShare * 100).round(),
                        (data.moderateShare * 100).round(),
                        (data.hardShare * 100).round(),
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.isPolarized
                          ? loc.runInsightsIntensityGood
                          : loc.runInsightsIntensityTooHard,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: data.isPolarized
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final zone in RunZone.values)
                      _ZoneRow(
                        zone: zone,
                        bounds: bounds,
                        share: data.totalSeconds <= 0
                            ? 0
                            : data.totalsPerZone[zone.index] /
                                  data.totalSeconds,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  final RunZone zone;
  final RunZoneBounds bounds;
  final double share;

  const _ZoneRow({
    required this.zone,
    required this.bounds,
    required this.share,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (slowest, fastest) = bounds.rangeOf(zone);
    // The open ends: Z1 is anything slower than the easy pace, Z5 anything
    // faster than the interval pace.
    final text = switch (zone) {
      RunZone.z1 => loc.runInsightsZoneRangeSlower(
        RunFormatters.paceShort(fastest),
      ),
      RunZone.z5 => loc.runInsightsZoneRangeFaster(
        RunFormatters.paceShort(slowest),
      ),
      _ => loc.runInsightsZoneRange(
        RunFormatters.paceShort(slowest),
        RunFormatters.paceShort(fastest),
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: runZoneColor(colors, zone),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(
              loc.runInsightsZoneLabel(zone.index + 1, runZoneName(loc, zone)),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              '$text /km',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ),
          Text(
            '${(share * 100).round()}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: RunUi.tabular,
            ),
          ),
        ],
      ),
    );
  }
}
