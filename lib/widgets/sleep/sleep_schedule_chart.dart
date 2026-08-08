import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';

class SleepScheduleChart extends StatelessWidget {
  final List<SleepEntry> entries;
  final List<DateTime> days;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;

  const SleepScheduleChart({
    super.key,
    required this.entries,
    required this.days,
    required this.onPreviousWeek,
    required this.onNextWeek,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final byDate = {
      for (final entry in entries) _dateString(entry.date): entry,
    };
    final windows = <({int index, double start, double end})>[];
    for (var index = 0; index < days.length; index++) {
      final entry = byDate[_dateString(days[index])];
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
    final minY = windows.isEmpty ? 18.0 : _minY(windows);
    final maxY = windows.isEmpty ? 34.0 : _maxY(windows);
    final windowsByIndex = {for (final window in windows) window.index: window};
    final groups = List.generate(days.length, (index) {
      final window = windowsByIndex[index];
      final hasWindow = window != null;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            fromY: hasWindow ? window.start : minY,
            toY: hasWindow ? window.end : minY + .01,
            width: 20,
            color: hasWindow ? null : Colors.transparent,
            gradient: hasWindow
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colors.primary, colors.tertiary],
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              fromY: minY,
              toY: maxY,
              color: colors.surfaceContainerHighest,
            ),
          ),
        ],
      );
    });

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bedtime_rounded, color: colors.primary, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.sleepScheduleChart,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatRange(days.first, days.last),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('sleep-previous-week'),
                  tooltip: loc.sleepPreviousWeek,
                  visualDensity: VisualDensity.compact,
                  onPressed: onPreviousWeek,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  key: const Key('sleep-next-week'),
                  tooltip: loc.sleepNextWeek,
                  visualDensity: VisualDensity.compact,
                  onPressed: onNextWeek,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (windows.isEmpty)
              _EmptyChart(message: loc.sleepScheduleNoTimes)
            else
              Semantics(
                key: const Key('sleep-schedule-chart'),
                container: true,
                label: loc.sleepScheduleSemantics(windows.length),
                child: SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      minY: minY,
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      barTouchData: BarTouchData(
                        enabled: true,
                        handleBuiltInTouches: true,
                        // The background rod represents the whole day column.
                        // Let it receive touches too, so a tap on a day without
                        // a recorded window still explains that there is no
                        // sleep record instead of doing nothing.
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
                            final entry = byDate[_dateString(days[index])];
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
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 2,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: colors.outlineVariant.withAlpha(120),
                          strokeWidth: 1,
                          dashArray: [4, 5],
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
                            reservedSize: 39,
                            interval: 2,
                            getTitlesWidget: (value, meta) => Text(
                              _formatHour(value),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= days.length) {
                                return const SizedBox();
                              }
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  DateFormat(
                                    'E',
                                    Intl.defaultLocale,
                                  ).format(days[index]).substring(0, 1),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

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
    lines.add('${loc.sleepBedtime}: ${_formatTime(entry.bedtimeMinutes)}');
    lines.add('${loc.sleepWakeTime}: ${_formatTime(entry.wakeTimeMinutes)}');
    lines.add(
      '${loc.sleepChartRecorded}: ${_formatMinutes(entry.sleepMinutes, loc)}',
    );
    final actual = entry.actualSleepMinutes ?? entry.estimatedSleepMinutes;
    if (actual != null) {
      lines.add(
        '${loc.sleepChartActualOrEstimated}: ${_formatMinutes(actual, loc)}',
      );
    }
    return lines.join('\n');
  }

  static double _minY(List<({int index, double start, double end})> windows) {
    final minimum = windows.map((window) => window.start).reduce(math.min);
    return math.max(12, (minimum / 2).floorToDouble() * 2 - 2);
  }

  static double _maxY(List<({int index, double start, double end})> windows) {
    final maximum = windows.map((window) => window.end).reduce(math.max);
    return math.min(40, (maximum / 2).ceilToDouble() * 2 + 2);
  }

  static String _formatRange(DateTime start, DateTime end) {
    final startText = DateFormat.MMMd(Intl.defaultLocale).format(start);
    final endText = DateFormat.yMMMd(Intl.defaultLocale).format(end);
    return '$startText - $endText';
  }

  static String _formatHour(double value) {
    final minutes = (value * 60).round() % 1440;
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    if (minute == 0) return '${hour.toString().padLeft(2, '0')}h';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String _formatTime(int? minutes) {
    if (minutes == null) return '--';
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static String _formatMinutes(int minutes, AppLocalizations loc) {
    return loc.sleepDurationValue(minutes ~/ 60, minutes % 60);
  }

  static String _dateString(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

class _EmptyChart extends StatelessWidget {
  final String message;

  const _EmptyChart({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      width: double.infinity,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
