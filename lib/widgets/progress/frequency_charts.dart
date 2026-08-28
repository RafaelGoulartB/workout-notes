import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
import 'package:workout_notes/widgets/progress/progress_chart_shell.dart';
import 'package:workout_notes/widgets/workout_heatmap.dart';

/// Displays frequency section: yearly heatmap, weekly bar chart,
/// day-of-week distribution, and time-of-day pie chart.
class FrequencyCharts extends StatelessWidget {
  final Map<String, int> heatmapData;
  final List<Map<String, dynamic>> workoutDates;
  final int year;

  const FrequencyCharts({
    super.key,
    required this.heatmapData,
    required this.workoutDates,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProgressChartCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProgressSectionHeader(
                title: loc.progressYearHeatmap,
                subtitle: '$year',
                accent: Colors.green.shade600,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: WorkoutHeatmap(dailyData: heatmapData, year: year),
              ),
              const SizedBox(height: 8),
              Row(children: [const Spacer(), _buildLegend(theme, loc)]),
            ],
          ),
        ),
        if (workoutDates.isNotEmpty) ...[
          const SizedBox(height: 12),
          _WeeklyFrequencyChart(workoutDates: workoutDates),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _DayOfWeekChart(workoutDates: workoutDates)),
              const SizedBox(width: 10),
              Expanded(child: _TimeOfDayChart(workoutDates: workoutDates)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLegend(ThemeData theme, AppLocalizations loc) {
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 10,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(loc.progressHeatmapLess, style: style),
        const SizedBox(width: 6),
        _legendDot(theme.colorScheme.surfaceContainerHighest.withAlpha(120)),
        _legendDot(Colors.green.shade200),
        _legendDot(Colors.green.shade400),
        _legendDot(Colors.green.shade600),
        _legendDot(Colors.green.shade800),
        const SizedBox(width: 6),
        Text(loc.progressHeatmapMore, style: style),
      ],
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 9,
      height: 9,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _WeeklyFrequencyChart extends StatelessWidget {
  final List<Map<String, dynamic>> workoutDates;

  const _WeeklyFrequencyChart({required this.workoutDates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final weeks = <_WeekBar>[];

    for (int i = 11; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (i * 7)));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final startStr = weekStart.toIso8601String().substring(0, 10);
      final endStr = weekEnd.toIso8601String().substring(0, 10);

      var count = 0;
      for (final wd in workoutDates) {
        final d = wd['date'] as String? ?? '';
        if (d.compareTo(startStr) >= 0 && d.compareTo(endStr) <= 0) {
          count++;
        }
      }
      weeks.add(
        _WeekBar(weekLabel(weekStart, loc.progressWeekAbbreviation), count),
      );
    }

    final maxCount = weeks.fold<int>(0, (a, b) => a > b.count ? a : b.count);
    final total = weeks.fold<int>(0, (a, b) => a + b.count);
    final avg = total / weeks.length;

    return ProgressChartCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressSectionHeader(
            title: loc.progressWeeklyFrequency,
            subtitle: loc.progressAverageWorkouts(avg.toStringAsFixed(1)),
            accent: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxCount < 5 ? 5 : maxCount * 1.25,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBorderRadius: BorderRadius.circular(10),
                    getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                    getTooltipItem: (g, gi, r, ri) {
                      final w = weeks[gi];
                      return BarTooltipItem(
                        '${w.label}\n${w.count} ${loc.progressWorkouts}',
                        TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= weeks.length) {
                          return const SizedBox.shrink();
                        }
                        if (weeks.length > 6 && idx % 2 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            weeks[idx].label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        if (v == 0 || v % 1 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          '${v.toInt()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 9,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: niceInterval(
                    maxCount > 0 ? maxCount / 4 : 1,
                  ),
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: theme.colorScheme.outlineVariant.withAlpha(60),
                    strokeWidth: 1,
                  ),
                ),
                barGroups: weeks.asMap().entries.map((e) {
                  final intensity = maxCount == 0
                      ? 0.4
                      : (0.45 + 0.55 * (e.value.count / maxCount));
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.count.toDouble(),
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            theme.colorScheme.primary.withValues(
                              alpha: intensity * 0.55,
                            ),
                            theme.colorScheme.primary.withValues(
                              alpha: intensity,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayOfWeekChart extends StatelessWidget {
  final List<Map<String, dynamic>> workoutDates;

  const _DayOfWeekChart({required this.workoutDates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final dowCount = <int, int>{0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};
    for (final wd in workoutDates) {
      final dow = wd['day_of_week'] as int? ?? 0;
      dowCount[dow] = (dowCount[dow] ?? 0) + 1;
    }

    final labels = [
      loc.calendarSun,
      loc.calendarMon,
      loc.calendarTue,
      loc.calendarWed,
      loc.calendarThu,
      loc.calendarFri,
      loc.calendarSat,
    ];
    final maxVal = dowCount.values.fold<int>(0, (a, b) => a > b ? a : b);

    return ProgressChartCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressSectionHeader(
            title: loc.progressDayOfWeek,
            accent: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal < 3 ? 3 : maxVal * 1.25,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBorderRadius: BorderRadius.circular(8),
                    getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                    getTooltipItem: (g, gi, r, ri) {
                      return BarTooltipItem(
                        '${labels[gi]}: ${dowCount[gi] ?? 0}',
                        TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= 7) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          labels[idx],
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 9,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: List.generate(7, (i) {
                  final isWeekend = i == 0 || i == 6;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (dowCount[i] ?? 0).toDouble(),
                        color: isWeekend
                            ? Colors.orange.shade400
                            : theme.colorScheme.primary,
                        width: 11,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeOfDayChart extends StatelessWidget {
  final List<Map<String, dynamic>> workoutDates;

  const _TimeOfDayChart({required this.workoutDates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final periods = <String, int>{
      'manhã': 0,
      'tarde': 0,
      'noite': 0,
      'madrugada': 0,
    };
    for (final wd in workoutDates) {
      final startTime = wd['start_time'] as String?;
      if (startTime == null) continue;
      try {
        final hour = DateTime.parse(startTime).hour;
        if (hour < 6) {
          periods['madrugada'] = periods['madrugada']! + 1;
        } else if (hour < 12) {
          periods['manhã'] = periods['manhã']! + 1;
        } else if (hour < 18) {
          periods['tarde'] = periods['tarde']! + 1;
        } else {
          periods['noite'] = periods['noite']! + 1;
        }
      } catch (_) {}
    }

    final total = periods.values.fold<int>(0, (a, b) => a + b);
    final colors = [
      Colors.orange.shade400,
      Colors.amber.shade600,
      Colors.indigo.shade400,
      Colors.deepPurple.shade300,
    ];
    final labels = [
      loc.progressMorning,
      loc.progressAfternoon,
      loc.progressEvening,
      loc.progressDawn,
    ];
    final values = [
      periods['manhã']!,
      periods['tarde']!,
      periods['noite']!,
      periods['madrugada']!,
    ];

    return ProgressChartCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProgressSectionHeader(
            title: loc.progressTimeOfDay,
            accent: Colors.indigo,
          ),
          const SizedBox(height: 10),
          if (total == 0)
            SizedBox(
              height: 132,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 28,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(90),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      loc.progressNoData,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 28,
                      sections: [
                        for (var i = 0; i < 4; i++)
                          if (values[i] > 0)
                            PieChartSectionData(
                              color: colors[i],
                              value: values[i].toDouble(),
                              title: '${(values[i] / total * 100).round()}%',
                              titleStyle: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              radius: 26,
                            ),
                      ],
                    ),
                  ),
                  Text(
                    '$total',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...List.generate(4, (i) {
              if (values[i] == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        labels[i],
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${values[i]}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _WeekBar {
  final String label;
  final int count;
  _WeekBar(this.label, this.count);
}
