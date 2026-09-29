import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Period selector chips (4 weeks / 12 weeks / year / all).
class RunPeriodChips extends StatelessWidget {
  final RunStatsPeriod selected;
  final ValueChanged<RunStatsPeriod> onChanged;

  const RunPeriodChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static String label(AppLocalizations loc, RunStatsPeriod period) =>
      switch (period) {
        RunStatsPeriod.weeks4 => loc.runStatsPeriod4Weeks,
        RunStatsPeriod.weeks12 => loc.runStatsPeriod12Weeks,
        RunStatsPeriod.year => loc.runStatsPeriodYear,
        RunStatsPeriod.all => loc.runStatsPeriodAll,
      };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final period in RunStatsPeriod.values) ...[
          if (period != RunStatsPeriod.values.first) const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              // The four periods share the row, so the label scales down
              // instead of being clipped on narrow screens.
              label: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label(loc, period), maxLines: 1),
                ),
              ),
              labelStyle: theme.textTheme.labelMedium,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              showCheckmark: false,
              selected: selected == period,
              onSelected: (_) => onChanged(period),
            ),
          ),
        ],
      ],
    );
  }
}

/// Headline numbers of the selected period: distance, trend against the
/// previous period and four stats (time, pace, runs, elevation gain).
class RunPeriodHero extends StatelessWidget {
  final RunProgressAnalytics analytics;

  const RunPeriodHero({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final ratio = analytics.distanceRatioVsPreviousPeriod;
    final paceDelta = analytics.paceDeltaVsPreviousPeriod;
    final start = analytics.periodStart;
    final range = start == null
        ? null
        : '${DateFormat.MMMd(locale).format(start)} – '
              '${DateFormat.MMMd(locale).format(analytics.now)}';
    final elevation = analytics.totalElevationGainMeters;

    return RunHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const RunIconBadge(Icons.directions_run),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The section header above already says "period
                    // summary"; the card names the actual date range.
                    Text(
                      range ?? loc.runStatsPeriodAll,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RunValueUnit(
                    value: RunFormatters.distanceKm(
                      analytics.totalDistanceMeters,
                    ),
                    unit: 'km',
                    valueStyle: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                    unitStyle: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (ratio != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: RunPill.trend(
                    context: context,
                    label:
                        '${ratio >= 0 ? '+' : '-'}'
                        '${(ratio.abs() * 100).round()}%',
                    positive: ratio >= 0,
                  ),
                ),
            ],
          ),
          if (analytics.hasPreviousPeriod)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                loc.runStatsVsPrevious,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 14),
          Divider(height: 1, color: RunUi.divider(colors)),
          const SizedBox(height: 12),
          RunStatRow(
            children: [
              RunStatTile(
                icon: Icons.timer_outlined,
                color: colors.secondary,
                label: loc.runRecordTime,
                value: RunFormatters.durationHoursMinutes(
                  analytics.totalMovingTimeSeconds,
                ),
              ),
              RunStatTile(
                icon: Icons.speed_rounded,
                color: colors.tertiary,
                label: loc.runHomeAvgPace,
                value: RunFormatters.pace(analytics.avgPaceSecPerKm),
                unit: '/km',
              ),
              RunStatTile(
                icon: Icons.flag_outlined,
                color: colors.primary,
                label: loc.runStatsRunCount,
                value: '${analytics.runCount}',
              ),
              RunStatTile(
                icon: Icons.terrain_rounded,
                color: colors.secondary,
                label: loc.runHomeElevationGain,
                value: elevation > 0 ? '${elevation.round()}' : '--',
                unit: elevation > 0 ? 'm' : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            [
              loc.runStatsWeeklyAverageValue(
                RunFormatters.distanceWithUnit(
                  analytics.avgWeeklyDistanceMeters,
                ),
              ),
              loc.runStatsRunsPerWeekValue(
                RunFormatters.decimal(analytics.avgRunsPerWeek, 1),
              ),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (paceDelta != null) ...[
            const SizedBox(height: 4),
            Text(
              paceDelta.abs() < 3
                  ? loc.runStatsPaceStable
                  : paceDelta < 0
                  ? loc.runStatsPaceFaster('${paceDelta.abs().round()} s/km')
                  : loc.runStatsPaceSlower('${paceDelta.abs().round()} s/km'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
