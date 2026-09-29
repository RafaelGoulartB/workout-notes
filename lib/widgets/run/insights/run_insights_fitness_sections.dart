import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_training_load_analytics.dart';
import 'package:workout_notes/widgets/run/home/run_home_fitness_card.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/run/run_insights_charts.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

// ===================== FITNESS =====================

/// VDOT / VO2max estimate: the number, how it moved, and a compact trend.
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

    Widget? delta;
    if (evolution.length >= 2) {
      final change = evolution.last.vdot - evolution.first.vdot;
      final sign = change >= 0 ? '+' : '-';
      delta = RunPill.trend(
        context: context,
        positive: change >= 0,
        label: loc.runInsightsVdotSince(
          '$sign${RunFormatters.decimal(change.abs(), 1)}',
          DateFormat.MMM(locale).format(evolution.first.month),
        ),
      );
    }

    return RunInsightCard(
      icon: Icons.favorite_outline_rounded,
      title: loc.runInsightsFitnessTitle,
      subtitle: fitness == null
          ? null
          : loc.runInsightsFitnessBasedOn(
              runRaceDistanceLabel(loc, fitness.source.distanceMeters),
              DateFormat.MMMd(locale).format(fitness.source.date),
            ),
      info: loc.runInsightsApproxNote,
      child: fitness == null
          ? RunInsightsNote(loc.runInsightsFitnessEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      RunFormatters.decimal(fitness.vdot, 1),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: RunUi.tabular,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.runHomeFitnessVo2,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (delta != null) ...[
                            const SizedBox(height: 4),
                            delta,
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (fitness.fromTrainingRuns || fitness.isStale) ...[
                  const SizedBox(height: 10),
                  RunInsightsNote(
                    fitness.fromTrainingRuns
                        ? loc.runInsightsFitnessFromTraining
                        : loc.runInsightsFitnessStale,
                    color: colors.tertiary,
                  ),
                ],
                if (evolution.length >= 2) ...[
                  const SizedBox(height: 16),
                  RunInsightsSubheading(loc.runInsightsFitnessEvolution),
                  RunVdotChart(
                    points: evolution,
                    emptyLabel: loc.runInsightsFitnessEvolutionEmpty,
                    height: 130,
                  ),
                ],
              ],
            ),
    );
  }
}

// ===================== RACE PREDICTOR =====================

/// Predicted race times as a 2×2 grid: distance, time, pace.
class RunPredictorSection extends StatelessWidget {
  final RunFitnessEstimate estimate;

  const RunPredictorSection({super.key, required this.estimate});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return RunInsightCard(
      icon: Icons.emoji_events_outlined,
      title: loc.runInsightsPredictorTitle,
      subtitle: loc.runInsightsPredictorSubtitle,
      info: loc.runInsightsPredictorNote,
      child: RunMetricGrid(
        children: [
          for (final p in estimate.predictions) _PredictionTile(prediction: p),
        ],
      ),
    );
  }
}

class _PredictionTile extends StatelessWidget {
  final RunRacePrediction prediction;

  const _PredictionTile({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(RunUi.tileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            runRaceDistanceLabel(loc, prediction.distanceMeters),
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              RunFormatters.duration(prediction.timeSeconds),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ),
          Text(
            RunFormatters.paceWithUnit(prediction.paceSecPerKm),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontFeatures: RunUi.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== TRAINING LOAD =====================

/// Load status first (one clear sentence), then the acute/chronic chart.
class RunLoadSection extends StatelessWidget {
  final RunTrainingLoad load;

  const RunLoadSection({super.key, required this.load});

  String _statusText(AppLocalizations loc) => switch (load.status) {
    RunLoadStatus.balanced => loc.runInsightsLoadTextBalanced,
    RunLoadStatus.rapidIncrease => loc.runInsightsLoadTextRapid,
    RunLoadStatus.detraining => loc.runInsightsLoadTextDetraining,
    RunLoadStatus.insufficientData => loc.runInsightsLoadTextInsufficient,
  };

  /// Drops the leading stretch with no load at all (e.g. before the first
  /// run) so the chart spends its width on real data; keeps at least 4 weeks.
  static List<RunLoadDay> _visibleDays(List<RunLoadDay> days) {
    final first = days.indexWhere((d) => d.acute > 0 || d.chronic > 0);
    if (first <= 0) return days;
    final start = (first - 7).clamp(
      0,
      (days.length - 28).clamp(0, days.length),
    );
    return days.sublist(start);
  }

  IconData get _statusIcon => switch (load.status) {
    RunLoadStatus.balanced => Icons.check_circle_outline_rounded,
    RunLoadStatus.rapidIncrease => Icons.trending_up_rounded,
    RunLoadStatus.detraining => Icons.trending_down_rounded,
    RunLoadStatus.insufficientData => Icons.hourglass_empty_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = runLoadStatusColor(colors, load.status);
    final growth = load.weeklyVolumeGrowth;
    final acwr = load.acwr;
    final info = [
      loc.runInsightsLoadHelp,
      if (acwr != null)
        loc.runInsightsLoadRatio(RunFormatters.decimal(acwr, 2)),
    ].join('\n\n');

    return RunInsightCard(
      icon: Icons.speed_rounded,
      title: loc.runInsightsLoadTitle,
      subtitle: loc.runInsightsLoadSubtitle,
      info: info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(28),
              borderRadius: BorderRadius.circular(RunUi.tileRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        runLoadStatusLabel(loc, load.status),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_statusText(loc), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (load.volumeGrowthWarning) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: colors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RunInsightsNote(
                    loc.runInsightsVolumeWarning((growth! * 100).round()),
                    color: colors.error,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          RunLoadChart(days: _visibleDays(load.days)),
          if (!load.volumeGrowthWarning && growth != null) ...[
            const SizedBox(height: 10),
            RunInsightsNote(
              loc.runInsightsVolumeChange(
                '${growth >= 0 ? '+' : '-'}${(growth.abs() * 100).round()}%',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===================== INTENSITY =====================

/// Easy / moderate / hard split as one bar with the 80/20 verdict; zone
/// ranges below and the weekly chart on demand.
class RunIntensitySection extends StatefulWidget {
  final RunIntensityDistribution? distribution;
  final RunZoneBounds? zones;

  const RunIntensitySection({
    super.key,
    required this.distribution,
    required this.zones,
  });

  @override
  State<RunIntensitySection> createState() => _RunIntensitySectionState();
}

class _RunIntensitySectionState extends State<RunIntensitySection> {
  bool _showWeeks = false;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = widget.distribution;
    final bounds = widget.zones;
    final ready = data != null && bounds != null && data.hasData;

    return RunInsightCard(
      icon: Icons.stacked_bar_chart_rounded,
      title: loc.runInsightsIntensityTitle,
      subtitle: loc.runInsightsIntensitySubtitle,
      info: loc.runInsightsIntensityHelp,
      child: !ready
          ? RunInsightsNote(loc.runInsightsIntensityEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(data.easyShare * 100).round()}%',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: RunUi.tabular,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          loc.runInsightsIntensityEasyHeadline,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _IntensityBar(distribution: data),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          RunLegendItem(
                            color: runZoneColor(colors, RunZone.z2),
                            label:
                                '${loc.runInsightsIntensityEasy} '
                                '${(data.easyShare * 100).round()}%',
                          ),
                          RunLegendItem(
                            color: runZoneColor(colors, RunZone.z3),
                            label:
                                '${loc.runInsightsIntensityModerate} '
                                '${(data.moderateShare * 100).round()}%',
                          ),
                          RunLegendItem(
                            color: runZoneColor(colors, RunZone.z5),
                            label:
                                '${loc.runInsightsIntensityHard} '
                                '${(data.hardShare * 100).round()}%',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      data.isPolarized
                          ? Icons.check_circle_outline_rounded
                          : Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: data.isPolarized
                          ? colors.primary
                          : colors.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data.isPolarized
                            ? loc.runInsightsIntensityGood
                            : loc.runInsightsIntensityTooHard,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                Divider(height: 28, color: RunUi.divider(colors)),
                RunInsightsSubheading(loc.runInsightsZonesTitle),
                for (final zone in RunZone.values)
                  _ZoneRow(
                    zone: zone,
                    bounds: bounds,
                    share: data.totalSeconds <= 0
                        ? 0
                        : data.totalsPerZone[zone.index] / data.totalSeconds,
                  ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setState(() => _showWeeks = !_showWeeks),
                    icon: Icon(
                      _showWeeks
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text(
                      _showWeeks
                          ? loc.runInsightsHideWeeks
                          : loc.runInsightsShowWeeks,
                    ),
                  ),
                ),
                if (_showWeeks) ...[
                  const SizedBox(height: 8),
                  RunIntensityChart(weeks: data.weeks),
                ],
              ],
            ),
    );
  }
}

/// One 100% bar split into easy / moderate / hard.
class _IntensityBar extends StatelessWidget {
  final RunIntensityDistribution distribution;

  const _IntensityBar({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final parts = [
      (distribution.easyShare, runZoneColor(colors, RunZone.z2)),
      (distribution.moderateShare, runZoneColor(colors, RunZone.z3)),
      (distribution.hardShare, runZoneColor(colors, RunZone.z5)),
    ].where((p) => p.$1 > 0).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (parts[i].$1 * 1000).round().clamp(1, 1000),
                child: ColoredBox(color: parts[i].$2),
              ),
            ],
          ],
        ),
      ),
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
    final range = switch (zone) {
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 30,
            decoration: BoxDecoration(
              color: runZoneColor(colors, zone),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.runInsightsZoneLabel(
                    zone.index + 1,
                    runZoneName(loc, zone),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$range /km',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: RunUi.tabular,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${(share * 100).round()}%',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: RunUi.tabular,
            ),
          ),
        ],
      ),
    );
  }
}
