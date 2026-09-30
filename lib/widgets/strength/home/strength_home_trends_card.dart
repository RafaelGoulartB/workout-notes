import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_charts.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

enum _TrendTab { volume, frequency, duration }

/// Volume / frequency / duration charts for the selected period in one card.
class StrengthTrendsCard extends StatefulWidget {
  final StrengthWeekAnalytics analytics;

  const StrengthTrendsCard({super.key, required this.analytics});

  @override
  State<StrengthTrendsCard> createState() => _StrengthTrendsCardState();
}

class _StrengthTrendsCardState extends State<StrengthTrendsCard> {
  _TrendTab _tab = _TrendTab.volume;

  String _tabLabel(AppLocalizations loc, _TrendTab tab) => switch (tab) {
    _TrendTab.volume => loc.runStatsChartTabVolume,
    _TrendTab.frequency => loc.runStatsChartTabFrequency,
    _TrendTab.duration => loc.strengthHomeChartTabDuration,
  };

  Widget _volumeChart(AppLocalizations loc, StrengthWeekAnalytics analytics) {
    final buckets = analytics.trendBuckets;
    final maxKg = buckets.fold<double>(
      0,
      (m, b) => b.volumeKg > m ? b.volumeKg : m,
    );
    final tonnes = StrengthVolumeValue.of(maxKg).tonnes;
    final divisor = tonnes ? 1000.0 : 1.0;
    final avgLabel = analytics.trendIsMonthly
        ? loc.strengthHomeChartAvgVolumeMonthly
        : loc.strengthHomeChartAvgVolumeWeekly;
    return StrengthBucketBarChart(
      buckets: buckets,
      emptyLabel: loc.strengthHomeChartEmpty,
      unit: tonnes ? 't' : 'kg',
      valueOf: (b) => b.volumeKg / divisor,
      average: analytics.trendAvgVolumeKg / divisor,
      averageLabel: avgLabel(
        StrengthHomeFormat.volume(analytics.trendAvgVolumeKg),
      ),
      tooltipLines: (b) => [
        StrengthHomeFormat.volume(b.volumeKg),
        loc.strengthHomeWorkoutsCount(b.sessions),
        loc.strengthHomeSetsCount(b.workingSets),
      ],
    );
  }

  Widget _frequencyChart(
    AppLocalizations loc,
    StrengthWeekAnalytics analytics,
  ) {
    final monthly = analytics.trendIsMonthly;
    final value = RunFormatters.decimal(analytics.trendAvgSessions, 1);
    return StrengthBucketBarChart(
      buckets: analytics.trendBuckets,
      emptyLabel: loc.strengthHomeChartEmpty,
      unit: loc.strengthHomeChartUnitWorkouts,
      minStep: 1,
      valueOf: (b) => b.sessions.toDouble(),
      average: analytics.trendAvgSessions,
      averageLabel: monthly
          ? loc.strengthHomeChartAvgWorkoutsMonthly(value)
          : loc.strengthHomeChartAvgWorkoutsWeekly(value),
      tooltipLines: (b) => [
        loc.strengthHomeWorkoutsCount(b.sessions),
        if (b.durationSeconds > 0)
          StrengthHomeFormat.duration(b.durationSeconds),
      ],
    );
  }

  Widget _durationChart(AppLocalizations loc, StrengthWeekAnalytics analytics) {
    final avgSeconds = analytics.trendAvgDurationSeconds;
    return StrengthBucketBarChart(
      buckets: analytics.trendBuckets,
      emptyLabel: loc.strengthHomeChartEmpty,
      unit: loc.strengthHomeChartUnitMinutes,
      valueOf: (b) => b.avgDurationSeconds / 60,
      average: avgSeconds / 60,
      averageLabel: loc.strengthHomeChartAvgDuration(
        StrengthHomeFormat.duration(avgSeconds.round()),
      ),
      tooltipLines: (b) => [
        if (b.sessions > 0)
          StrengthHomeFormat.duration(b.avgDurationSeconds.round()),
        loc.strengthHomeWorkoutsCount(b.sessions),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final analytics = widget.analytics;
    final chart = switch (_tab) {
      _TrendTab.volume => _volumeChart(loc, analytics),
      _TrendTab.frequency => _frequencyChart(loc, analytics),
      _TrendTab.duration => _durationChart(loc, analytics),
    };

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmentedTabs<_TrendTab>(
            values: _TrendTab.values,
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
