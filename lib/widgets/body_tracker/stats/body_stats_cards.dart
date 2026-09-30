import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/body/body_stats_controller.dart';
import 'package:workout_notes/utils/body_progress_analytics.dart';
import 'package:workout_notes/widgets/body_tracker/body_stats_charts.dart';
import 'package:workout_notes/widgets/body_tracker/stats/body_stats_primitives.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Hero card: this week's average against the reference week, plus the
/// period's average / min / max / amplitude.
class BodyStatsWeekHero extends StatelessWidget {
  const BodyStatsWeekHero({
    super.key,
    required this.controller,
    required this.analytics,
  });

  final BodyStatsController controller;
  final BodyProgressAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = controller;
    final a = analytics;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final divider = colors.outlineVariant.withAlpha(80);
    final comparison = a.weekComparison;
    final week = comparison.current;
    final delta = comparison.delta;
    final percent = comparison.percent;

    final String subtitle;
    if (comparison.reference == null) {
      subtitle = loc.bodyStatsNoComparison;
    } else if (comparison.referenceIsAdjacent) {
      subtitle = loc.bodyStatsVsPreviousWeek;
    } else {
      subtitle = loc.bodyStatsVsWeekOf(
        bodyStatsShortDate(context, comparison.reference!.weekStart),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceContainerHighest.withAlpha(200),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.currentType.color.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_view_week_outlined,
                  size: 18,
                  color: c.currentType.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.bodyStatsWeeklyAverage,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      loc.bodyStatsWeekRange(
                        bodyStatsShortDate(context, week.weekStart),
                        bodyStatsShortDate(context, week.weekEnd),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        c.value(week.average),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        c.unit,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (delta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TrendPill(
                    label: '${c.signed(delta, decimals: c.decimals)} $c.unit',
                    icon: delta.abs() < 0.05
                        ? Icons.trending_flat_rounded
                        : delta > 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    positive: delta.abs() < 0.05 ? null : c.isGood(delta),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            week.hasData
                ? percent == null
                      ? subtitle
                      : '$subtitle · ${c.signed(percent, decimals: 1)}%'
                : loc.bodyStatsNoWeekData,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (week.hasData) ...[
            const SizedBox(height: 4),
            Text(
              loc.bodyStatsWeekEntries(week.entryCount, week.dayCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.show_chart_rounded,
                  color: c.currentType.color,
                  label: loc.bodyStatsPeriodAverage,
                  value: c.value(a.averageValue),
                ),
              ),
              AppStatDivider(height: 34, color: divider),
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.south_rounded,
                  color: colors.secondary,
                  label: loc.bodyStatsMin,
                  value: c.value(a.minValue),
                ),
              ),
              AppStatDivider(height: 34, color: divider),
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.north_rounded,
                  color: colors.tertiary,
                  label: loc.bodyStatsMax,
                  value: c.value(a.maxValue),
                ),
              ),
              AppStatDivider(height: 34, color: divider),
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.height_rounded,
                  color: colors.onSurfaceVariant,
                  label: loc.bodyStatsAmplitude,
                  value: c.value(a.amplitude),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chart card with the weekly / delta / daily tab switcher.
class BodyStatsChartCard extends StatelessWidget {
  const BodyStatsChartCard({
    super.key,
    required this.controller,
    required this.analytics,
  });

  final BodyStatsController controller;
  final BodyProgressAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = controller;
    final a = analytics;
    final theme = Theme.of(context);
    final labels = {
      BodyChartTab.weekly: loc.bodyStatsChartWeekly,
      BodyChartTab.delta: loc.bodyStatsChartDelta,
      BodyChartTab.daily: loc.bodyStatsChartDaily,
    };

    final chart = switch (c.chartTab) {
      BodyChartTab.weekly => BodyWeeklyAverageChart(
        weeks: a.weeks,
        averageValue: a.averageValue,
        color: c.currentType.color,
        unit: c.unit,
        emptyLabel: loc.bodyStatsChartWeeklyEmpty,
      ),
      BodyChartTab.delta => BodyWeeklyDeltaChart(
        weeks: a.weeks,
        isDecreasingGood: c.isDecreasingGood,
        unit: c.unit,
        emptyLabel: loc.bodyStatsChartDeltaEmpty,
      ),
      BodyChartTab.daily => BodyDailyTrendChart(
        daily: a.daily,
        smoothed: a.smoothed,
        color: c.currentType.color,
        unit: c.unit,
        emptyLabel: loc.bodyStatsChartDailyEmpty,
      ),
    };

    final legend = switch (c.chartTab) {
      BodyChartTab.weekly => loc.bodyStatsChartWeeklyLegend,
      BodyChartTab.delta => loc.bodyStatsChartDeltaLegend,
      BodyChartTab.daily => loc.bodyStatsChartDailyLegend,
    };

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChartTabBar(
              selected: c.chartTab,
              labels: labels,
              onChanged: c.setChartTab,
            ),
          ),
          const SizedBox(height: 14),
          chart,
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              legend,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rate of change per week, pace verdict, total change, projection and BMI.
class BodyStatsRateCard extends StatelessWidget {
  const BodyStatsRateCard({
    super.key,
    required this.controller,
    required this.analytics,
  });

  final BodyStatsController controller;
  final BodyProgressAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = controller;
    final a = analytics;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rate = a.ratePerWeek;
    final ratePercent = a.ratePercentPerWeek;

    final pace = BodyStatsController.paceFor(rate, ratePercent);
    final paceLabel = switch (pace) {
      null => null,
      BodyPace.stable => loc.bodyStatsPaceStable,
      BodyPace.aggressive => loc.bodyStatsPaceAggressive,
      BodyPace.sustainable => loc.bodyStatsPaceSustainable,
    };
    final paceGood = pace != BodyPace.aggressive;

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rate == null)
            Text(
              loc.bodyStatsRateUnavailable,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            c.signed(rate, decimals: 2),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            c.unit,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        ratePercent == null
                            ? loc.bodyStatsRatePerWeek
                            : '${loc.bodyStatsRatePerWeek} · '
                                  '${c.signed(ratePercent, decimals: 2)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (paceLabel != null)
                  TrendPill(
                    label: paceLabel,
                    icon: paceGood
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    positive: paceGood,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppStatTile(
                    dense: true,
                    icon: Icons.swap_vert_rounded,
                    color: c.currentType.color,
                    label: loc.bodyStatsTotalChange,
                    value: c.signed(a.totalChange, decimals: c.decimals),
                    unit: c.unit,
                  ),
                ),
                AppStatDivider(
                  height: 34,
                  color: colors.outlineVariant.withAlpha(80),
                ),
                Expanded(
                  child: AppStatTile(
                    dense: true,
                    icon: Icons.timeline_rounded,
                    color: colors.tertiary,
                    label: loc.bodyStatsProjection,
                    value: c.value(a.projectedValue(4)),
                    unit: c.unit,
                  ),
                ),
                if (c.bmi(a.lastValue) case final bmi?) ...[
                  AppStatDivider(
                    height: 34,
                    color: colors.outlineVariant.withAlpha(80),
                  ),
                  Expanded(
                    child: AppStatTile(
                      dense: true,
                      icon: Icons.accessibility_new_rounded,
                      color: colors.secondary,
                      label: loc.bodyStatsBmi,
                      value: bmi.toStringAsFixed(1),
                      unit: _bmiLabel(loc, bmi),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              loc.bodyStatsProjectionNote,
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

String _bmiLabel(AppLocalizations loc, double bmi) {
  return switch (BodyStatsController.bmiCategory(bmi)) {
    BmiCategory.under => loc.bodyStatsBmiUnder,
    BmiCategory.normal => loc.bodyStatsBmiNormal,
    BmiCategory.over => loc.bodyStatsBmiOver,
    BmiCategory.obese => loc.bodyStatsBmiObese,
  };
}

/// Progress toward the active phase's target weight.
class BodyStatsGoalCard extends StatelessWidget {
  const BodyStatsGoalCard({
    super.key,
    required this.controller,
    required this.analytics,
    required this.progress,
  });

  final BodyStatsController controller;
  final BodyProgressAnalytics analytics;
  final BodyGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = controller;
    final a = analytics;
    final phase = c.phase!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final eta = progress.etaFrom(a.now);

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.bodyStatsGoalPhase(phase.name),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TrendPill(
                label: progress.achieved
                    ? loc.bodyStatsGoalReached
                    : loc.bodyStatsGoalRemaining(
                        '${progress.remaining.toStringAsFixed(1)} $c.unit',
                      ),
                icon: progress.achieved
                    ? Icons.emoji_events_outlined
                    : Icons.flag_outlined,
                positive: progress.onTrack,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 10,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                progress.onTrack ? colors.primary : colors.error,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GoalAnchor(
                  label: loc.bodyStatsGoalStart,
                  value: '${c.value(progress.startValue)} $c.unit',
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              Expanded(
                child: GoalAnchor(
                  label: loc.bodyStatsGoalCurrent,
                  value: '${c.value(progress.currentValue)} $c.unit',
                  alignment: CrossAxisAlignment.center,
                  emphasized: true,
                ),
              ),
              Expanded(
                child: GoalAnchor(
                  label: loc.bodyStatsGoalTarget,
                  value: '${c.value(progress.targetValue)} $c.unit',
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          if (!progress.achieved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  eta == null
                      ? Icons.error_outline_rounded
                      : Icons.event_available_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    eta == null
                        ? loc.bodyStatsGoalOffTrack
                        : loc.bodyStatsGoalEta(
                            bodyStatsShortDate(context, eta),
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Logging consistency: weeks with data, streak, entries per week.
class BodyStatsConsistencyCard extends StatelessWidget {
  const BodyStatsConsistencyCard({
    super.key,
    required this.controller,
    required this.analytics,
  });

  final BodyStatsController controller;
  final BodyProgressAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = controller;
    final a = analytics;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final days = a.daysSinceLast;

    return AppSectionCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.event_repeat_outlined,
                  color: c.currentType.color,
                  label: loc.bodyStatsConsistencyWeeks,
                  value: '${a.weeksWithData}/${a.weeks.length}',
                ),
              ),
              AppStatDivider(
                height: 34,
                color: colors.outlineVariant.withAlpha(80),
              ),
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.local_fire_department_outlined,
                  color: Colors.deepOrange,
                  label: loc.bodyStatsStreak,
                  value: loc.bodyStatsStreakWeeks(a.weekStreak),
                ),
              ),
              AppStatDivider(
                height: 34,
                color: colors.outlineVariant.withAlpha(80),
              ),
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.receipt_long_outlined,
                  color: colors.secondary,
                  label: loc.bodyStatsEntriesPerWeek,
                  value: a.entriesPerWeek.toStringAsFixed(1),
                ),
              ),
              AppStatDivider(
                height: 34,
                color: colors.outlineVariant.withAlpha(80),
              ),
              Expanded(
                child: AppStatTile(
                  dense: true,
                  icon: Icons.history_toggle_off_outlined,
                  color: colors.tertiary,
                  label: loc.bodyStatsDaysSinceLast,
                  value: days == null
                      ? '--'
                      : days == 0
                      ? loc.bodyStatsToday
                      : '$days',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: a.consistency,
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(c.currentType.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Month-by-month averages with the change against the previous month.
class BodyStatsMonthlyCard extends StatelessWidget {
  const BodyStatsMonthlyCard({
    super.key,
    required this.controller,
    required this.analytics,
  });

  final BodyStatsController controller;
  final BodyProgressAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = controller;
    final a = analytics;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Newest first, capped so a long history does not dominate the screen.
    final months = a.months.reversed.take(12).toList();

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < months.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: colors.outlineVariant.withAlpha(60)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bodyStatsMonthLabel(context, months[i].monthStart),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          loc.bodyStatsMonthEntries(months[i].entryCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${c.value(months[i].average)} $c.unit',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        '${c.value(months[i].min)} – ${c.value(months[i].max)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (months[i].deltaVsPreviousMonth case final delta?) ...[
                    const SizedBox(width: 10),
                    DeltaBadge(
                      label: c.signed(delta, decimals: c.decimals),
                      positive: delta.abs() < 0.05 ? null : c.isGood(delta),
                    ),
                  ] else
                    const SizedBox(width: 10 + 46),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
