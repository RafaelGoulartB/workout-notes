import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/insights/strength_charts.dart';
import 'package:workout_notes/widgets/strength/insights/strength_heatmap.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';

/// Year chips for the calendar (shown only with more than one year of data).
class StrengthYearSelector extends StatelessWidget {
  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;

  const StrengthYearSelector({
    super.key,
    required this.years,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}

// ===================== HEATMAP =====================

class StrengthHeatmapCard extends StatelessWidget {
  final int year;
  final Map<DateTime, double> daily;
  final DateTime today;

  const StrengthHeatmapCard({
    super.key,
    required this.year,
    required this.daily,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return RunInsightCard(
      icon: Icons.calendar_month_outlined,
      title: loc.strengthInsightsHeatmapTitle,
      subtitle: loc.strengthInsightsHeatmapSubtitle,
      child: StrengthHeatmap(year: year, daily: daily, today: today),
    );
  }
}

// ===================== WORKOUTS PER WEEK =====================

class StrengthWeeklySessionsCard extends StatelessWidget {
  final StrengthInsightsData data;

  const StrengthWeeklySessionsCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final weeks = StrengthInsightsCalculator.weeklySessions(
      data.workouts,
      data.today,
    );
    final finished = weeks.sublist(0, weeks.length - 1);
    final average =
        finished.fold<int>(0, (a, b) => a + b.sessions) / finished.length;

    return RunInsightCard(
      icon: Icons.event_repeat_rounded,
      title: loc.strengthInsightsWeeklyTitle,
      subtitle: loc.strengthInsightsWeeklySubtitle,
      info: loc.strengthInsightsWeeklyInfo,
      child: StrengthBarChart(
        unit: loc.strengthInsightsMetricSessions,
        emptyLabel: loc.strengthInsightsMuscleEmpty,
        integerAxis: true,
        color: Theme.of(context).colorScheme.secondary,
        average: average,
        averageLabel: loc.strengthInsightsWeeklyAverage(
          RunFormatters.decimal(average, 1),
        ),
        points: [
          for (final w in weeks)
            StrengthBarPoint(
              label: w.label(locale),
              value: w.sessions.toDouble(),
              tooltip:
                  '${loc.runStatsChartTooltipWeek(DateFormat.MMMd(locale).format(w.start))}\n'
                  '${loc.strengthInsightsSessionsCount(w.sessions)}',
            ),
        ],
      ),
    );
  }
}

// ===================== CONSISTENCY =====================

class StrengthConsistencyCard extends StatelessWidget {
  final StrengthConsistency consistency;

  const StrengthConsistencyCard({super.key, required this.consistency});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    return RunInsightCard(
      icon: Icons.local_fire_department_outlined,
      title: loc.strengthInsightsConsistencyTitle,
      subtitle: consistency.weeksConsidered > 0
          ? loc.strengthInsightsConsistencyWeeks(
              (consistency.share * 100).round(),
              consistency.weeksConsidered,
            )
          : null,
      info: loc.strengthInsightsConsistencyInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunMetricGrid(
            children: [
              RunMetricBox(
                label: loc.runInsightsWeekStreak,
                value: '${consistency.currentWeekStreak}',
                caption: loc.runInsightsBest(
                  loc.runInsightsWeeksValue(consistency.longestWeekStreak),
                ),
              ),
              RunMetricBox(
                label: loc.strengthInsightsConsistencyPerWeek,
                value: RunFormatters.decimal(consistency.sessionsPerWeek, 1),
              ),
            ],
          ),
          if (consistency.weeksConsidered > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: consistency.share,
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ===================== WEEKDAY =====================

class StrengthWeekdayCard extends StatelessWidget {
  final List<int> counts;

  const StrengthWeekdayCard({super.key, required this.counts});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final peak = counts.fold<int>(0, (a, b) => b > a ? b : a);
    final favorite = counts.indexOf(peak);
    // 2024-01-01 is a Monday.
    String dayName(int i, {bool full = false}) {
      final date = DateTime(2024, 1, 1 + i);
      final text = full
          ? DateFormat.EEEE(locale).format(date)
          : DateFormat.E(locale).format(date).replaceAll('.', '');
      return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
    }

    const barArea = 84.0;
    return RunInsightCard(
      icon: Icons.today_rounded,
      title: loc.strengthInsightsWeekdayTitle,
      subtitle: peak > 0
          ? loc.strengthInsightsWeekdaySubtitle(dayName(favorite, full: true))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${counts[i]}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: peak == 0 ? 4 : 4 + barArea * counts[i] / peak,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: i == favorite && peak > 0
                          ? colors.primary
                          : colors.primary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dayName(i),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: i == favorite && peak > 0
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ===================== TIME OF DAY =====================

/// Shown only when workouts happen in at least two parts of the day; a single
/// bucket says nothing.
class StrengthDayPartCard extends StatelessWidget {
  final Map<StrengthDayPart, int> counts;

  const StrengthDayPartCard({super.key, required this.counts});

  static bool hasData(Map<StrengthDayPart, int> counts) =>
      counts.values.where((c) => c > 0).length >= 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    String label(StrengthDayPart p) => switch (p) {
      StrengthDayPart.morning => loc.progressMorning,
      StrengthDayPart.afternoon => loc.progressAfternoon,
      StrengthDayPart.evening => loc.progressEvening,
      StrengthDayPart.night => loc.progressDawn,
    };

    return RunInsightCard(
      icon: Icons.wb_twilight_rounded,
      title: loc.strengthInsightsDayPartTitle,
      subtitle: loc.strengthInsightsDayPartSubtitle,
      child: Column(
        children: [
          for (final part in StrengthDayPart.values)
            if (counts[part]! > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(
                        label(part),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: counts[part]! / total,
                          minHeight: 10,
                          backgroundColor: colors.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(counts[part]! / total * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: RunUi.tabular,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ===================== DURATION =====================

class StrengthDurationCard extends StatelessWidget {
  final StrengthInsightsData data;

  const StrengthDurationCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final weeks = StrengthInsightsCalculator.weeklyDuration(
      data.workouts,
      data.today,
    ).where((w) => w.value != null).toList();
    return RunInsightCard(
      icon: Icons.timer_outlined,
      title: loc.strengthInsightsDurationTitle,
      subtitle: loc.strengthInsightsDurationSubtitle,
      child: StrengthTrendChart(
        unit: loc.strengthInsightsDurationUnit,
        emptyLabel: loc.strengthInsightsDurationEmpty,
        zeroBased: true,
        points: [
          for (final w in weeks)
            StrengthTrendPoint(
              date: w.weekStart,
              value: w.value!,
              tooltip:
                  '${loc.runStatsChartTooltipWeek(DateFormat.MMMd(locale).format(w.weekStart))}\n'
                  '${RunFormatters.durationHoursMinutes((w.value! * 60).round())}',
            ),
        ],
      ),
    );
  }
}
