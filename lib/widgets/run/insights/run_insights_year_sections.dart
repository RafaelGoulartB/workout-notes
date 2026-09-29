import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
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
    final colors = Theme.of(context).colorScheme;

    return RunInsightCard(
      icon: Icons.local_fire_department_outlined,
      title: loc.runInsightsConsistencyTitle,
      subtitle: consistency.weeksConsidered > 0
          ? loc.runInsightsWeeksWithRuns(
              (consistency.weeksWithRunsShare * 100).round(),
              consistency.weeksConsidered,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunMetricGrid(
            children: [
              RunMetricBox(
                label: loc.runInsightsDayStreak,
                value: '${consistency.currentDayStreak}',
                caption: loc.runInsightsBest(
                  loc.runInsightsDaysValue(consistency.longestDayStreak),
                ),
              ),
              RunMetricBox(
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
          ],
        ],
      ),
    );
  }
}

// ===================== EFFORT & FEELING =====================

enum _EffortTab { rpe, feeling }

/// One chart at a time: perceived effort or feeling, per week.
class RunEffortSection extends StatefulWidget {
  final List<RunWeeklyEffort> weeks;

  const RunEffortSection({super.key, required this.weeks});

  @override
  State<RunEffortSection> createState() => _RunEffortSectionState();
}

class _RunEffortSectionState extends State<RunEffortSection> {
  _EffortTab _tab = _EffortTab.rpe;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final weeks = widget.weeks;
    final hasRpe = weeks.any((w) => w.avgRpe != null);
    final hasFeeling = weeks.any((w) => w.avgFeeling != null);
    final starts = [for (final w in weeks) w.weekStart];
    final tab = !hasRpe
        ? _EffortTab.feeling
        : !hasFeeling
        ? _EffortTab.rpe
        : _tab;

    return RunInsightCard(
      icon: Icons.sentiment_satisfied_alt_outlined,
      title: loc.runInsightsEffortTitle,
      child: !hasRpe && !hasFeeling
          ? RunInsightsNote(loc.runInsightsEffortEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasRpe && hasFeeling) ...[
                  RunSegmentedTabs<_EffortTab>(
                    values: _EffortTab.values,
                    selected: tab,
                    labelOf: (t) => t == _EffortTab.rpe
                        ? loc.runInsightsRpeLabel
                        : loc.runInsightsFeelingLabel,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: 14),
                ],
                if (tab == _EffortTab.rpe)
                  RunWeeklyLineChart(
                    weeks: starts,
                    values: [for (final w in weeks) w.avgRpe],
                    minY: 0,
                    maxY: 10,
                    interval: 2,
                    color: colors.error,
                    format: (v) => RunFormatters.decimal(v, 1),
                  )
                else
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
            ),
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
    return RunInsightCard(
      icon: Icons.calendar_month_outlined,
      title: loc.runInsightsHeatmapTitle,
      child: RunHeatmap(year: year, daily: daily, today: today),
    );
  }
}

// ===================== MONTHLY / CUMULATIVE =====================

enum _VolumeTab { monthly, cumulative }

/// Monthly bars or the year-to-date line against last year, one at a time.
class RunVolumeSection extends StatefulWidget {
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
  State<RunVolumeSection> createState() => _RunVolumeSectionState();
}

class _RunVolumeSectionState extends State<RunVolumeSection> {
  _VolumeTab _tab = _VolumeTab.monthly;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    // Compare like with like: total so far against the same month-end of
    // last year, only for the year in progress.
    final monthIndex = widget.year == widget.today.year
        ? widget.today.month - 1
        : 11;
    final now = widget.thisYear[monthIndex];
    final before = widget.lastYear[monthIndex];
    String? delta;
    if (now != null && before != null && before > 0) {
      final diff = now - before;
      if (diff.abs() < 50) {
        delta = loc.runInsightsCumulativeSame;
      } else if (diff > 0) {
        delta = loc.runInsightsCumulativeAhead(
          RunFormatters.distanceWithUnit(diff),
        );
      } else {
        delta = loc.runInsightsCumulativeBehind(
          RunFormatters.distanceWithUnit(-diff),
        );
      }
    }

    return RunInsightCard(
      icon: Icons.bar_chart_rounded,
      title: loc.runInsightsVolumeTitle,
      subtitle: delta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunSegmentedTabs<_VolumeTab>(
            values: _VolumeTab.values,
            selected: _tab,
            labelOf: (t) => t == _VolumeTab.monthly
                ? loc.runInsightsVolumeTabMonthly
                : loc.runInsightsVolumeTabCumulative,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 14),
          if (_tab == _VolumeTab.monthly)
            RunMonthlyChart(
              months: widget.months,
              emptyLabel: loc.runInsightsReviewEmpty('${widget.year}'),
            )
          else
            RunCumulativeChart(
              year: widget.year,
              thisYear: widget.thisYear,
              lastYear: widget.lastYear,
            ),
        ],
      ),
    );
  }
}

// ===================== YEAR IN REVIEW =====================

/// Headline of the selected year: total distance, then a grid of the year's
/// notable numbers (elevation included).
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
      return RunInsightCard(
        icon: Icons.auto_awesome_outlined,
        title: title,
        child: RunInsightsNote(loc.runInsightsReviewEmpty('${review.year}')),
      );
    }

    String cap(String text) => toBeginningOfSentenceCase(text);
    final longest = review.longestRun;
    final fastest = review.fastest5kRun;
    final month = review.mostActiveMonth;
    final weekday = review.favoriteWeekday;
    final part = review.favoriteDayPart;
    final elevation = review.elevation;
    final highest = elevation.highest;

    return RunHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const RunIconBadge(Icons.auto_awesome_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 4),
          Text(
            '${loc.runInsightsShoesRuns(review.runCount)} · '
            '${RunFormatters.durationHoursMinutes(review.totalMovingSeconds)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          RunMetricGrid(
            children: [
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
              if (elevation.hasData)
                GestureDetector(
                  onTap: highest == null ? null : () => onOpenRun(highest.id),
                  child: RunMetricBox(
                    icon: Icons.terrain_rounded,
                    label: loc.runInsightsReviewClimb,
                    value: '${elevation.totalGainMeters.round()}',
                    unit: 'm',
                    caption: highest?.elevationGainMeters == null
                        ? null
                        : loc.runInsightsReviewClimbBest(
                            RunFormatters.elevation(
                              highest!.elevationGainMeters,
                            ),
                          ),
                  ),
                ),
              if (weekday != null || part != null)
                RunMetricBox(
                  icon: Icons.schedule_outlined,
                  label: loc.runInsightsReviewHabit,
                  value: weekday != null
                      ? cap(
                          DateFormat.EEEE(
                            locale,
                          ).format(DateTime(2024, 1, weekday)),
                        )
                      : _dayPart(loc, part!),
                  caption: weekday != null && part != null
                      ? _dayPart(loc, part)
                      : null,
                ),
            ],
          ),
        ],
      ),
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

    return RunInsightCard(
      icon: Icons.directions_walk_rounded,
      title: loc.runInsightsShoesTitle,
      onTap: onOpen,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      child: shoes.isEmpty
          ? RunInsightsNote(loc.runInsightsShoesEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < shoes.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _ShoeRow(usage: shoes[i]),
                ],
              ],
            ),
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
