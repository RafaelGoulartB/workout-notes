import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/goals/goals_section.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/insights/strength_charts.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';

/// Period chips (4 weeks / 12 weeks / year).
class StrengthPeriodSelector extends StatelessWidget {
  final StrengthPeriod selected;
  final ValueChanged<StrengthPeriod> onChanged;

  const StrengthPeriodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    String label(StrengthPeriod p) => switch (p) {
      StrengthPeriod.weeks4 => loc.strengthInsightsPeriod4w,
      StrengthPeriod.weeks12 => loc.strengthInsightsPeriod12w,
      StrengthPeriod.year => loc.strengthInsightsPeriodYear,
    };
    return Wrap(
      spacing: 8,
      children: [
        for (final p in StrengthPeriod.values)
          ChoiceChip(
            label: Text(label(p)),
            showCheckmark: false,
            selected: p == selected,
            onSelected: (_) => onChanged(p),
          ),
      ],
    );
  }
}

// ===================== GOALS =====================

/// Anaerobic goals, so they stay reachable from the analysis.
class StrengthGoalsCard extends StatefulWidget {
  const StrengthGoalsCard({super.key});

  @override
  State<StrengthGoalsCard> createState() => _StrengthGoalsCardState();
}

class _StrengthGoalsCardState extends State<StrengthGoalsCard> {
  int _achieved = 0;
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return RunInsightCard(
      icon: Icons.flag_outlined,
      title: loc.progressGoals,
      subtitle: _total == 0
          ? loc.progressGoalsSubtitle
          : loc.progressGoalsAchieved(_achieved, _total),
      child: GoalsSection(
        db: DatabaseHelper.instance,
        settingsRepo: DatabaseHelper.instance.settingsRepo,
        allowedScopes: const [GoalScope.anaerobic],
        framed: false,
        onSummaryChanged: (achieved, total) {
          if (!mounted || (achieved == _achieved && total == _total)) return;
          setState(() {
            _achieved = achieved;
            _total = total;
          });
        },
      ),
    );
  }
}

// ===================== PERIOD SUMMARY =====================

class StrengthSummaryCard extends StatelessWidget {
  final StrengthPeriod period;
  final StrengthTotals current;
  final StrengthTotals previous;

  const StrengthSummaryCard({
    super.key,
    required this.period,
    required this.current,
    required this.previous,
  });

  Widget _delta(BuildContext context, String? label, bool positive) {
    if (label == null) return const SizedBox(height: 26);
    return RunPill.trend(context: context, label: label, positive: positive);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    String? percent(double now, double before) =>
        StrengthFormat.percentDelta(now, before);

    final sessionDelta = current.sessions - previous.sessions;
    return RunInsightCard(
      icon: Icons.insights_rounded,
      title: loc.strengthInsightsSummaryTitle,
      subtitle: loc.strengthInsightsSummarySubtitle(period.days),
      info: loc.strengthInsightsSummaryInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunStatRow(
            children: [
              Column(
                children: [
                  RunStatTile(
                    label: loc.strengthInsightsMetricVolume,
                    value: StrengthFormat.volume(current.volume),
                    unit: StrengthFormat.volumeUnit(current.volume),
                  ),
                  const SizedBox(height: 8),
                  _delta(
                    context,
                    percent(current.volume, previous.volume),
                    current.volume >= previous.volume,
                  ),
                ],
              ),
              Column(
                children: [
                  RunStatTile(
                    label: loc.strengthInsightsMetricSets,
                    value: '${current.sets}',
                  ),
                  const SizedBox(height: 8),
                  _delta(
                    context,
                    percent(current.sets.toDouble(), previous.sets.toDouble()),
                    current.sets >= previous.sets,
                  ),
                ],
              ),
              Column(
                children: [
                  RunStatTile(
                    label: loc.strengthInsightsMetricSessions,
                    value: '${current.sessions}',
                  ),
                  const SizedBox(height: 8),
                  _delta(
                    context,
                    previous.sessions == 0 && current.sessions == 0
                        ? null
                        : StrengthFormat.signed(sessionDelta),
                    sessionDelta >= 0,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(child: RunInsightsNote(loc.strengthInsightsVsPrevious)),
        ],
      ),
    );
  }
}

// ===================== VOLUME TREND =====================

enum _TrendMetric { volume, sets }

class StrengthVolumeTrendCard extends StatefulWidget {
  final StrengthInsightsData data;
  final StrengthPeriod period;

  const StrengthVolumeTrendCard({
    super.key,
    required this.data,
    required this.period,
  });

  @override
  State<StrengthVolumeTrendCard> createState() =>
      _StrengthVolumeTrendCardState();
}

class _StrengthVolumeTrendCardState extends State<StrengthVolumeTrendCard> {
  _TrendMetric _metric = _TrendMetric.volume;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final data = widget.data;
    final monthly = widget.period == StrengthPeriod.year;
    final buckets = monthly
        ? StrengthInsightsCalculator.monthlyBuckets(
            data.sets,
            data.workouts,
            data.today,
          )
        : StrengthInsightsCalculator.weeklyBuckets(
            data.sets,
            data.workouts,
            data.today,
            count: widget.period == StrengthPeriod.weeks4 ? 8 : 12,
          );
    final byVolume = _metric == _TrendMetric.volume;
    double valueOf(StrengthVolumeBucket b) =>
        byVolume ? b.volume : b.sets.toDouble();

    // Average of the finished buckets; the current one is still in progress.
    final finished = buckets.length > 1
        ? buckets.sublist(0, buckets.length - 1)
        : const <StrengthVolumeBucket>[];
    final average = finished.isEmpty
        ? null
        : finished.map(valueOf).reduce((a, b) => a + b) / finished.length;

    final points = [
      for (final b in buckets)
        StrengthBarPoint(
          label: b.label(locale),
          value: valueOf(b),
          tooltip: [
            b.monthly
                ? DateFormat.yMMM(locale).format(b.start)
                : loc.runStatsChartTooltipWeek(
                    DateFormat.MMMd(locale).format(b.start),
                  ),
            StrengthFormat.volumeWithUnit(b.volume),
            loc.strengthInsightsSetsCount(b.sets),
            loc.strengthInsightsSessionsCount(b.sessions),
          ].join('\n'),
        ),
    ];

    return RunInsightCard(
      icon: Icons.bar_chart_rounded,
      title: loc.strengthInsightsVolumeTrendTitle,
      subtitle: monthly
          ? loc.strengthInsightsVolumeTrendMonthly
          : loc.strengthInsightsVolumeTrendWeekly,
      info: loc.strengthInsightsVolumeTrendInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunSegmentedTabs<_TrendMetric>(
            values: _TrendMetric.values,
            selected: _metric,
            labelOf: (m) => m == _TrendMetric.volume
                ? loc.strengthInsightsMetricVolume
                : loc.strengthInsightsMetricSets,
            onChanged: (m) => setState(() => _metric = m),
          ),
          const SizedBox(height: 14),
          StrengthBarChart(
            points: points,
            unit: byVolume ? 'kg' : loc.strengthInsightsMetricSets,
            emptyLabel: loc.strengthInsightsMuscleEmpty,
            integerAxis: !byVolume,
            average: average,
            averageLabel: average == null
                ? null
                : loc.strengthInsightsAverageLegend(
                    byVolume
                        ? StrengthFormat.volumeWithUnit(average)
                        : RunFormatters.decimal(average, 0),
                  ),
          ),
        ],
      ),
    );
  }
}

// ===================== SETS PER MUSCLE =====================

class StrengthMuscleLoadCard extends StatelessWidget {
  final StrengthInsightsData data;
  final StrengthPeriod period;

  const StrengthMuscleLoadCard({
    super.key,
    required this.data,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final range = StrengthInsightsCalculator.rangeFor(period, data.today);
    final load = StrengthInsightsCalculator.muscleLoad(
      data.sets,
      range,
      categoryIds: [for (final c in data.categories) c['id'] as String],
    );
    const min = StrengthInsightsCalculator.recommendedMinWeeklySets;
    const max = StrengthInsightsCalculator.recommendedMaxWeeklySets;
    final peak = load.fold<double>(
      0,
      (a, l) => l.weeklySets > a ? l.weeklySets : a,
    );
    final axisMax = peak > max ? peak * 1.1 : max * 1.25;

    return RunInsightCard(
      icon: Icons.accessibility_new_rounded,
      title: loc.strengthInsightsMuscleTitle,
      subtitle: loc.strengthInsightsMuscleSubtitle(min, max),
      info: loc.strengthInsightsMuscleInfo(min, max),
      child: load.every((l) => l.sets == 0)
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RunInsightsNote(loc.strengthInsightsMuscleEmpty),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, l) in load.indexed) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _MuscleRow(
                    name: data.categoryName(loc, l.categoryId),
                    color: data.categoryColor(l.categoryId),
                    load: l,
                    axisMax: axisMax,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.18,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${loc.strengthInsightsMuscleLegend} ($min-$max)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _MuscleRow extends StatelessWidget {
  final String name;
  final Color color;
  final StrengthMuscleLoad load;
  final double axisMax;

  const _MuscleRow({
    required this.name,
    required this.color,
    required this.load,
    required this.axisMax,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final (statusColor, statusLabel) = switch (load.status) {
      StrengthLoadStatus.below => (
        colors.tertiary,
        loc.strengthInsightsStatusBelow,
      ),
      StrengthLoadStatus.within => (
        colors.primary,
        loc.strengthInsightsStatusWithin,
      ),
      StrengthLoadStatus.above => (
        colors.error,
        loc.strengthInsightsStatusAbove,
      ),
    };
    const min = StrengthInsightsCalculator.recommendedMinWeeklySets;
    const max = StrengthInsightsCalculator.recommendedMaxWeeklySets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              loc.strengthInsightsMuscleRow(
                load.sets,
                RunFormatters.decimal(load.weeklySets, 1),
              ),
              maxLines: 1,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final fill =
                      (load.weeklySets / axisMax).clamp(0.0, 1.0) * width;
                  return SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        Positioned(
                          left: min / axisMax * width,
                          width: (max - min) / axisMax * width,
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.onSurface.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          width: fill,
                          top: 1.5,
                          bottom: 1.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 82,
              child: Align(
                alignment: Alignment.centerRight,
                child: RunPill(label: statusLabel, color: statusColor),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ===================== TOP EXERCISES =====================

class StrengthTopExercisesCard extends StatelessWidget {
  final StrengthInsightsData data;
  final StrengthPeriod period;

  const StrengthTopExercisesCard({
    super.key,
    required this.data,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final range = StrengthInsightsCalculator.rangeFor(period, data.today);
    final top = StrengthInsightsCalculator.topExercises(data.sets, range);

    return RunInsightCard(
      icon: Icons.emoji_events_outlined,
      title: loc.strengthInsightsTopTitle,
      subtitle: loc.strengthInsightsTopSubtitle,
      child: top.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RunInsightsNote(loc.strengthInsightsTopEmpty),
            )
          : RunDividedList(
              children: [
                for (final e in top)
                  RunListRow(
                    leading: RunIconBadge(
                      Icons.fitness_center_rounded,
                      color: data.categoryColor(e.categoryId),
                    ),
                    title: ExerciseLocaleHelper.exerciseName(
                      loc,
                      e.exerciseRow,
                    ),
                    subtitle: data.categoryName(loc, e.categoryId),
                    value: e.volume > 0
                        ? StrengthFormat.volumeWithUnit(e.volume)
                        : loc.strengthInsightsSetsCount(e.sets),
                    valueCaption: e.volume > 0
                        ? loc.strengthInsightsSetsCount(e.sets)
                        : null,
                    onTap: () => openStrengthExercise(
                      context,
                      exerciseId: e.exerciseId,
                      exerciseRow: e.exerciseRow,
                    ),
                  ),
              ],
            ),
    );
  }
}
