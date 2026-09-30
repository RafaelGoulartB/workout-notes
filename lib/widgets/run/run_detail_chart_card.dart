import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_elevation_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/widgets/run/run_elevation_chart.dart';
import 'package:workout_notes/widgets/run/run_pace_chart.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

enum RunChartTab { pace, elevation }

/// Pace / elevation charts of a run in one card: a pill toggle switches the
/// chart, both share [selectedDistance] with the map.
class RunDetailChartCard extends StatefulWidget {
  final RunPaceAnalytics analytics;
  final double? avgPaceSecPerKm;
  final RunElevationProfile elevation;

  /// Totals shown under the elevation chart; fall back to [elevation] when
  /// null so the card agrees with the summary above it.
  final double? gainMeters;
  final double? lossMeters;
  final ValueNotifier<double?>? selectedDistance;

  const RunDetailChartCard({
    super.key,
    required this.analytics,
    required this.avgPaceSecPerKm,
    required this.elevation,
    this.gainMeters,
    this.lossMeters,
    this.selectedDistance,
  });

  @override
  State<RunDetailChartCard> createState() => _RunDetailChartCardState();
}

class _RunDetailChartCardState extends State<RunDetailChartCard> {
  RunChartTab _tab = RunChartTab.pace;

  bool get _hasPace => widget.analytics.hasChart;
  bool get _hasElevation => widget.elevation.hasData;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final showElevation =
        _hasElevation && (_tab == RunChartTab.elevation || !_hasPace);
    final tabs = _hasPace && _hasElevation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tabs)
          Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 10),
            child: AppSegmentedTabs<RunChartTab>(
              values: RunChartTab.values,
              selected: _tab,
              labelOf: (tab) => switch (tab) {
                RunChartTab.pace => loc.runDetailChartTabPace,
                RunChartTab.elevation => loc.runDetailChartTabElevation,
              },
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          )
        else
          AppSectionHeader(
            showElevation
                ? loc.runDetailChartTabElevation
                : loc.runDetailPaceSection,
          ),
        AppSectionCard(
          padding: const EdgeInsets.fromLTRB(8, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 10),
                child: showElevation
                    ? _ChartCaption(unit: 'm')
                    : _ChartCaption(
                        unit: 'min/km',
                        legend: widget.avgPaceSecPerKm == null
                            ? null
                            : AppLegendItem(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.75,
                                ),
                                dashed: true,
                                label: loc.runDetailChartAverage(
                                  RunFormatters.paceShort(
                                    widget.avgPaceSecPerKm,
                                  ),
                                ),
                              ),
                      ),
              ),
              if (showElevation)
                RunElevationChart(
                  profile: widget.elevation,
                  selectedDistance: widget.selectedDistance,
                )
              else
                RunPaceChart(
                  samples: widget.analytics.samples,
                  avgPaceSecPerKm: widget.avgPaceSecPerKm,
                  emptyLabel: loc.runDetailPaceChartEmpty,
                  selectedDistance: widget.selectedDistance,
                ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'km',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (widget.selectedDistance != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Center(
                    child: Text(
                      loc.runDetailChartHint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              if (showElevation) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _ElevationSummary(
                    profile: widget.elevation,
                    gainMeters: widget.gainMeters,
                    lossMeters: widget.lossMeters,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChartCaption extends StatelessWidget {
  final String unit;
  final Widget? legend;

  const _ChartCaption({required this.unit, this.legend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          unit,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        ?legend,
      ],
    );
  }
}

class _ElevationSummary extends StatelessWidget {
  final RunElevationProfile profile;
  final double? gainMeters;
  final double? lossMeters;

  const _ElevationSummary({
    required this.profile,
    required this.gainMeters,
    required this.lossMeters,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final gain = gainMeters ?? profile.gainMeters;
    final loss = lossMeters ?? profile.lossMeters;
    return AppStatRow(
      children: [
        AppStatTile(
          icon: Icons.trending_up_rounded,
          color: colors.primary,
          value: '${gain.round()}',
          unit: 'm',
          label: loc.runDetailElevationGain,
        ),
        AppStatTile(
          icon: Icons.trending_down_rounded,
          color: colors.tertiary,
          value: '${loss.round()}',
          unit: 'm',
          label: loc.runDetailElevationLoss,
        ),
        AppStatTile(
          value: '${(profile.maxAltitudeMeters ?? 0).round()}',
          unit: 'm',
          label: loc.runDetailElevationHigh,
        ),
        AppStatTile(
          value: '${(profile.minAltitudeMeters ?? 0).round()}',
          unit: 'm',
          label: loc.runDetailElevationLow,
        ),
      ],
    );
  }
}
