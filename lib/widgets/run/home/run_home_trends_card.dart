import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_progress_charts.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

enum _RunChartTab { volume, pace, frequency }

/// Volume / pace / frequency charts for the selected period in one card.
class RunTrendsCard extends StatefulWidget {
  final RunProgressAnalytics analytics;

  const RunTrendsCard({super.key, required this.analytics});

  @override
  State<RunTrendsCard> createState() => _RunTrendsCardState();
}

class _RunTrendsCardState extends State<RunTrendsCard> {
  _RunChartTab _tab = _RunChartTab.volume;

  String _tabLabel(AppLocalizations loc, _RunChartTab tab) => switch (tab) {
    _RunChartTab.volume => loc.runStatsChartTabVolume,
    _RunChartTab.pace => loc.runStatsChartTabPace,
    _RunChartTab.frequency => loc.runStatsChartTabFrequency,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final analytics = widget.analytics;
    final monthly = analytics.trendIsMonthly;

    final chart = switch (_tab) {
      _RunChartTab.volume => RunWeeklyDistanceChart(
        buckets: analytics.trendBuckets,
        emptyLabel: loc.runStatsChartEmpty,
        averageMeters: analytics.trendAvgDistanceMeters,
        averageLabel: monthly
            ? loc.runStatsChartAvgMonthly(
                RunFormatters.distanceWithUnit(
                  analytics.trendAvgDistanceMeters,
                ),
              )
            : loc.runStatsWeeklyAverageValue(
                RunFormatters.distanceWithUnit(
                  analytics.trendAvgDistanceMeters,
                ),
              ),
      ),
      _RunChartTab.pace => _PaceTab(analytics: analytics),
      _RunChartTab.frequency => RunWeeklyFrequencyChart(
        buckets: analytics.trendBuckets,
        emptyLabel: loc.runStatsChartEmpty,
        averageRuns: analytics.trendAvgRuns,
        averageLabel: monthly
            ? loc.runStatsRunsPerMonthValue(
                RunFormatters.decimal(analytics.trendAvgRuns, 1),
              )
            : loc.runStatsRunsPerWeekValue(
                RunFormatters.decimal(analytics.trendAvgRuns, 1),
              ),
      ),
    };

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmentedTabs<_RunChartTab>(
            values: _RunChartTab.values,
            selected: _tab,
            labelOf: (tab) => _tabLabel(loc, tab),
            onChanged: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: 14),
          chart,
        ],
      ),
    );
  }
}

class _PaceTab extends StatelessWidget {
  final RunProgressAnalytics analytics;

  const _PaceTab({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final perMonth = analytics.paceTrendPerMonthSec;
    String? trendText;
    if (perMonth != null) {
      final delta = '${perMonth.abs().round()} s/km';
      trendText = perMonth.abs() < 3
          ? loc.runStatsPaceTrendSteady
          : perMonth < 0
          ? loc.runStatsPaceTrendFaster(delta)
          : loc.runStatsPaceTrendSlower(delta);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trendText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              trendText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        RunPaceTrendChart(
          points: analytics.paceTrend,
          emptyLabel: loc.runStatsPaceChartEmpty,
          trend: analytics.paceTrendFit,
        ),
        const SizedBox(height: 6),
        Text(
          loc.runStatsPaceTrendHint,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
