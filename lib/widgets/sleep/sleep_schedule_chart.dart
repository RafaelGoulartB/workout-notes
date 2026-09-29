import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

/// Weekly bed → wake windows, one column per day. Time runs downward (evening
/// at the top, morning at the bottom) and the dashed lines mark the average
/// bedtime and wake-up time of the week.
class SleepScheduleChart extends StatelessWidget {
  final List<SleepEntry> entries;
  final List<DateTime> days;

  const SleepScheduleChart({
    super.key,
    required this.entries,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final byDate = {
      for (final entry in entries) dateKey(entry.date): entry,
    };
    final windows = <({int index, double start, double end})>[];
    for (var index = 0; index < days.length; index++) {
      final entry = byDate[dateKey(days[index])];
      if (entry?.bedtimeMinutes == null || entry?.wakeTimeMinutes == null) {
        continue;
      }
      var start = entry!.bedtimeMinutes! / 60;
      if (start < 12) start += 24;
      var end = entry.wakeTimeMinutes! / 60;
      while (end <= start) {
        end += 24;
      }
      if (end - start <= 16) {
        windows.add((index: index, start: start, end: end));
      }
    }
    if (windows.isEmpty) {
      return SizedBox(
        height: 118,
        width: double.infinity,
        child: Center(
          child: Text(
            loc.sleepScheduleNoTimes,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Hours are negated so that later times sit lower on the chart.
    final earliest = _earliest(windows);
    final latest = _latest(windows);
    final avgStart =
        windows.map((w) => w.start).reduce((a, b) => a + b) / windows.length;
    final avgEnd =
        windows.map((w) => w.end).reduce((a, b) => a + b) / windows.length;
    final windowsByIndex = {for (final window in windows) window.index: window};
    final groups = List.generate(days.length, (index) {
      final window = windowsByIndex[index];
      final hasWindow = window != null;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            fromY: hasWindow ? -window.end : -earliest,
            toY: hasWindow ? -window.start : -earliest - .01,
            width: 18,
            color: hasWindow ? null : Colors.transparent,
            gradient: hasWindow
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colors.tertiary, colors.primary],
                  )
                : null,
            borderRadius: BorderRadius.circular(7),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              fromY: -latest,
              toY: -earliest,
              color: colors.surfaceContainerHighest.withAlpha(140),
            ),
          ),
        ],
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const Key('sleep-schedule-chart'),
          container: true,
          label: loc.sleepScheduleSemantics(windows.length),
          child: SizedBox(
            height: 210,
            child: BarChart(
              BarChartData(
                minY: -latest,
                maxY: -earliest,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  // The background rod represents the whole day column. Let it
                  // receive touches too, so a tap on a day without a recorded
                  // window still explains that there is no sleep record.
                  allowTouchBarBackDraw: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipPadding: const EdgeInsets.all(10),
                    tooltipMargin: 8,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => colors.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final index = group.x;
                      if (index < 0 || index >= days.length) return null;
                      final entry = byDate[dateKey(days[index])];
                      return BarTooltipItem(
                        _tooltipFor(loc, days[index], entry),
                        TextStyle(
                          color: colors.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.left,
                      );
                    },
                  ),
                ),
                barGroups: groups,
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    _averageLine(-avgStart, colors.tertiary),
                    _averageLine(-avgEnd, colors.primary),
                  ],
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.outlineVariant.withAlpha(70),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: 2,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          _formatHour(-value),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: RunUi.tabular,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) =>
                          SleepDayLabel(meta: meta, days: days, value: value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            RunLegendItem(
              color: colors.tertiary,
              dashed: true,
              label: loc.sleepAverageBedtime(
                SleepUi.clock((avgStart * 60).round()),
              ),
            ),
            RunLegendItem(
              color: colors.primary,
              dashed: true,
              label: loc.sleepAverageWake(SleepUi.clock((avgEnd * 60).round())),
            ),
          ],
        ),
      ],
    );
  }

  static HorizontalLine _averageLine(double y, Color color) => HorizontalLine(
    y: y,
    color: color.withAlpha(170),
    strokeWidth: 1.5,
    dashArray: [5, 4],
  );

  static String _tooltipFor(
    AppLocalizations loc,
    DateTime day,
    SleepEntry? entry,
  ) {
    final lines = <String>[DateFormat.MMMEd(Intl.defaultLocale).format(day)];
    if (entry == null) {
      lines.add(loc.sleepNoRecordForDay);
      return lines.join('\n');
    }
    lines.add('${loc.sleepBedtime}: ${SleepUi.clock(entry.bedtimeMinutes)}');
    lines.add('${loc.sleepWakeTime}: ${SleepUi.clock(entry.wakeTimeMinutes)}');
    lines.add(
      '${loc.sleepChartRecorded}: ${SleepUi.duration(loc, entry.sleepMinutes)}',
    );
    final actual = entry.actualSleepMinutes ?? entry.estimatedSleepMinutes;
    if (actual != null) {
      lines.add(
        '${loc.sleepChartActualOrEstimated}: ${SleepUi.duration(loc, actual)}',
      );
    }
    return lines.join('\n');
  }

  static double _earliest(
    List<({int index, double start, double end})> windows,
  ) {
    final minimum = windows.map((window) => window.start).reduce(math.min);
    return math.max(12, (minimum / 2).floorToDouble() * 2 - 1);
  }

  static double _latest(List<({int index, double start, double end})> windows) {
    final maximum = windows.map((window) => window.end).reduce(math.max);
    return math.min(40, (maximum / 2).ceilToDouble() * 2 + 1);
  }

  static String _formatHour(double value) {
    final minutes = (value * 60).round() % 1440;
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    if (minute == 0) return '${DurationFormat.twoDigits(hour)}h';
    return DurationFormat.hhmm(minutes);
  }
}

/// Two-line x-axis label for the weekly sleep charts: weekday initial over
/// the day of the month; today is highlighted.
class SleepDayLabel extends StatelessWidget {
  final TitleMeta meta;
  final List<DateTime> days;
  final double value;

  const SleepDayLabel({
    super.key,
    required this.meta,
    required this.days,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final index = value.toInt();
    if (index < 0 || index >= days.length || value != index) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final day = days[index];
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final weekday = DateFormat('E', Intl.defaultLocale).format(day);
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weekday.substring(0, 1).toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: isToday ? colors.primary : null,
            ),
          ),
          Text(
            '${day.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              height: 1.1,
              color: isToday ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
