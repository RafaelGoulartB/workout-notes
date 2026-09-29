import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/insights/run_insights_fitness_sections.dart';
import 'package:workout_notes/widgets/run/run_heatmap.dart';
import 'package:workout_notes/widgets/run/run_insights_charts.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

// ===================== CONSISTENCY =====================

class RunConsistencySection extends StatelessWidget {
  final RunConsistency consistency;

  const RunConsistencySection({super.key, required this.consistency});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsConsistencyTitle),
        RunSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RunMetricGrid(
                children: [
                  RunMetricBox(
                    icon: Icons.local_fire_department_outlined,
                    label: loc.runInsightsDayStreak,
                    value: '${consistency.currentDayStreak}',
                    caption: loc.runInsightsBest(
                      loc.runInsightsDaysValue(consistency.longestDayStreak),
                    ),
                  ),
                  RunMetricBox(
                    icon: Icons.date_range_outlined,
                    label: loc.runInsightsWeekStreak,
                    value: '${consistency.currentWeekStreak}',
                    caption: loc.runInsightsBest(
                      loc.runInsightsWeeksValue(consistency.longestWeekStreak),
                    ),
                  ),
                ],
              ),
              if (consistency.weeksConsidered > 0) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: consistency.weeksWithRunsShare,
                    minHeight: 6,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 6),
                RunInsightsNote(
                  loc.runInsightsWeeksWithRuns(
                    (consistency.weeksWithRunsShare * 100).round(),
                    consistency.weeksConsidered,
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

// ===================== EFFORT & FEELING =====================

class RunEffortSection extends StatelessWidget {
  final List<RunWeeklyEffort> weeks;

  const RunEffortSection({super.key, required this.weeks});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasRpe = weeks.any((w) => w.avgRpe != null);
    final hasFeeling = weeks.any((w) => w.avgFeeling != null);
    final starts = [for (final w in weeks) w.weekStart];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsEffortTitle),
        RunSectionCard(
          child: !hasRpe && !hasFeeling
              ? RunInsightsNote(loc.runInsightsEffortEmpty)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasRpe) ...[
                      RunInsightsCardTitle(loc.runInsightsRpeLabel),
                      RunWeeklyLineChart(
                        weeks: starts,
                        values: [for (final w in weeks) w.avgRpe],
                        minY: 0,
                        maxY: 10,
                        interval: 2,
                        color: colors.error,
                        format: (v) => RunFormatters.decimal(v, 1),
                      ),
                    ],
                    if (hasRpe && hasFeeling) const SizedBox(height: 18),
                    if (hasFeeling) ...[
                      RunInsightsCardTitle(loc.runInsightsFeelingLabel),
                      RunWeeklyLineChart(
                        weeks: starts,
                        values: [for (final w in weeks) w.avgFeeling],
                        minY: 0,
                        maxY: 5,
                        interval: 1,
                        color: colors.primary,
                        format: (v) => RunFormatters.decimal(v, 1),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

// ===================== YEAR SELECTOR =====================

class RunYearSelector extends StatelessWidget {
  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;

  const RunYearSelector({
    super.key,
    required this.years,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsYearSection),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: years.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text('${years[i]}'),
              showCheckmark: false,
              selected: years[i] == selected,
              onSelected: (_) => onChanged(years[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ===================== HEATMAP =====================

class RunHeatmapSection extends StatelessWidget {
  final int year;
  final Map<DateTime, double> daily;
  final DateTime today;

  const RunHeatmapSection({
    super.key,
    required this.year,
    required this.daily,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsHeatmapTitle),
        RunSectionCard(
          child: RunHeatmap(year: year, daily: daily, today: today),
        ),
      ],
    );
  }
}

// ===================== MONTHLY / CUMULATIVE =====================

class RunVolumeSection extends StatelessWidget {
  final int year;
  final List<RunMonthTotal> months;
  final List<double?> thisYear;
  final List<double?> lastYear;
  final DateTime today;

  const RunVolumeSection({
    super.key,
    required this.year,
    required this.months,
    required this.thisYear,
    required this.lastYear,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Compare like with like: total so far against the same month-end of
    // last year, only for the year in progress.
    final monthIndex = year == today.year ? today.month - 1 : 11;
    final now = thisYear[monthIndex];
    final before = lastYear[monthIndex];
    String? delta;
    Color? deltaColor;
    if (now != null && before != null && before > 0) {
      final diff = now - before;
      if (diff.abs() < 50) {
        delta = loc.runInsightsCumulativeSame;
      } else if (diff > 0) {
        delta = loc.runInsightsCumulativeAhead(
          RunFormatters.distanceWithUnit(diff),
        );
        deltaColor = colors.primary;
      } else {
        delta = loc.runInsightsCumulativeBehind(
          RunFormatters.distanceWithUnit(-diff),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsMonthlyTitle),
        RunSectionCard(
          child: RunMonthlyChart(
            months: months,
            emptyLabel: loc.runInsightsReviewEmpty('$year'),
          ),
        ),
        const SizedBox(height: 12),
        RunSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RunInsightsCardTitle(loc.runInsightsCumulativeTitle),
              RunCumulativeChart(
                year: year,
                thisYear: thisYear,
                lastYear: lastYear,
              ),
              if (delta != null) ...[
                const SizedBox(height: 10),
                Text(
                  delta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: deltaColor ?? colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
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

// ===================== ELEVATION =====================

class RunElevationSection extends StatelessWidget {
  final int year;
  final RunElevationSummary elevation;
  final ValueChanged<String> onOpenRun;

  const RunElevationSection({
    super.key,
    required this.year,
    required this.elevation,
    required this.onOpenRun,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final best = elevation.highest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(loc.runInsightsElevationTitle),
        RunSectionCard(
          onTap: best == null ? null : () => onOpenRun(best.id),
          child: !elevation.hasData
              ? RunInsightsNote(loc.runInsightsElevationEmpty('$year'))
              : RunStatRow(
                  children: [
                    RunStatTile(
                      icon: Icons.terrain_rounded,
                      label: loc.runInsightsElevationTotal,
                      value: '${elevation.totalGainMeters.round()}',
                      unit: 'm',
                    ),
                    RunStatTile(
                      icon: Icons.show_chart_rounded,
                      label: loc.runInsightsElevationAvg,
                      value: '${elevation.avgGainPerRunMeters!.round()}',
                      unit: 'm',
                    ),
                    RunStatTile(
                      icon: Icons.landscape_outlined,
                      label: loc.runInsightsElevationBest,
                      value: '${best!.elevationGainMeters!.round()}',
                      unit: 'm',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ===================== YEAR IN REVIEW =====================

class RunYearReviewSection extends StatelessWidget {
  final RunYearReview review;
  final ValueChanged<String> onOpenRun;

  const RunYearReviewSection({
    super.key,
    required this.review,
    required this.onOpenRun,
  });

  String _dayPart(AppLocalizations loc, RunDayPart part) => switch (part) {
    RunDayPart.morning => loc.runInsightsDayPartMorning,
    RunDayPart.afternoon => loc.runInsightsDayPartAfternoon,
    RunDayPart.evening => loc.runInsightsDayPartEvening,
    RunDayPart.night => loc.runInsightsDayPartNight,
  };

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final title = loc.runInsightsReviewTitle('${review.year}');

    if (review.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunSectionHeader(title),
          RunSectionCard(
            child: RunInsightsNote(
              loc.runInsightsReviewEmpty('${review.year}'),
            ),
          ),
        ],
      );
    }

    String cap(String text) => toBeginningOfSentenceCase(text);
    final longest = review.longestRun;
    final fastest = review.fastest5kRun;
    final month = review.mostActiveMonth;
    final weekday = review.favoriteWeekday;
    final part = review.favoriteDayPart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(title),
        RunHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.runInsightsReviewTotalKm,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              RunValueUnit(
                value: RunFormatters.distanceKm(review.totalDistanceMeters),
                unit: 'km',
                valueStyle: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
                unitStyle: theme.textTheme.titleMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              RunMetricGrid(
                children: [
                  RunMetricBox(
                    icon: Icons.flag_outlined,
                    label: loc.runStatsRunCount,
                    value: '${review.runCount}',
                  ),
                  RunMetricBox(
                    icon: Icons.timer_outlined,
                    label: loc.runRecordTime,
                    value: RunFormatters.durationHoursMinutes(
                      review.totalMovingSeconds,
                    ),
                  ),
                  if (longest != null)
                    GestureDetector(
                      onTap: () => onOpenRun(longest.id),
                      child: RunMetricBox(
                        icon: Icons.straighten_rounded,
                        label: loc.runStatsLongestRun,
                        value: RunFormatters.distanceKm(longest.distanceMeters),
                        unit: 'km',
                      ),
                    ),
                  if (fastest != null)
                    GestureDetector(
                      onTap: () => onOpenRun(fastest.id),
                      child: RunMetricBox(
                        icon: Icons.bolt_rounded,
                        label: loc.runInsightsReviewFastest5k,
                        value: RunFormatters.duration(fastest.bestEffort5kSec!),
                      ),
                    ),
                  if (month != null)
                    RunMetricBox(
                      icon: Icons.calendar_month_outlined,
                      label: loc.runInsightsReviewMonth,
                      value: cap(
                        DateFormat.MMMM(locale).format(DateTime(2024, month)),
                      ),
                      caption: RunFormatters.distanceWithUnit(
                        review.mostActiveMonthMeters,
                      ),
                    ),
                  if (weekday != null)
                    RunMetricBox(
                      icon: Icons.today_outlined,
                      label: loc.runInsightsReviewWeekday,
                      value: cap(
                        DateFormat.EEEE(
                          locale,
                        ).format(DateTime(2024, 1, weekday)),
                      ),
                    ),
                  if (part != null)
                    RunMetricBox(
                      icon: Icons.schedule_outlined,
                      label: loc.runInsightsReviewDayPart,
                      value: _dayPart(loc, part),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===================== SHOES =====================

class RunShoesSection extends StatelessWidget {
  final List<RunGearUsage> shoes;
  final VoidCallback onOpen;

  const RunShoesSection({super.key, required this.shoes, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunSectionHeader(
          loc.runInsightsShoesTitle,
          trailing: RunHeaderAction(
            label: loc.runGearManage,
            onPressed: onOpen,
          ),
        ),
        RunSectionCard(
          onTap: onOpen,
          child: shoes.isEmpty
              ? Row(
                  children: [
                    const RunIconBadge(Icons.directions_walk),
                    const SizedBox(width: 12),
                    Expanded(child: RunInsightsNote(loc.runInsightsShoesEmpty)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < shoes.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _ShoeRow(usage: shoes[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ShoeRow extends StatelessWidget {
  final RunGearUsage usage;

  const _ShoeRow({required this.usage});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final barColor = usage.needsReplacement
        ? colors.error
        : usage.nearingReplacement
        ? colors.tertiary
        : colors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                usage.gear.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              loc.runInsightsShoesRuns(usage.runCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: usage.wearRatio.clamp(0.0, 1.0),
            minHeight: 6,
            color: barColor,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          loc.runGearDistanceOf(
            RunFormatters.distanceWithUnit(usage.totalDistanceMeters),
            RunFormatters.distanceWithUnit(usage.gear.retireDistanceMeters),
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: usage.needsReplacement
                ? colors.error
                : colors.onSurfaceVariant,
            fontFeatures: RunUi.tabular,
          ),
        ),
      ],
    );
  }
}
