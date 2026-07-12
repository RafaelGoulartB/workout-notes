import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
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
        // Heatmap
        Text(
          loc.progressYearHeatmap,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WorkoutHeatmap(dailyData: heatmapData, year: year),
        ),
        const SizedBox(height: 4),
        Row(children: [const Spacer(), _buildLegend()]),
        const SizedBox(height: 16),

        // Weekly frequency chart
        if (workoutDates.isNotEmpty) ...[
          Text(
            loc.progressWeeklyFrequency,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _WeeklyFrequencyChart(workoutDates: workoutDates),
          const SizedBox(height: 16),
        ],

        // Day of week + Time of day side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _DayOfWeekChart(workoutDates: workoutDates)),
            const SizedBox(width: 8),
            Expanded(child: _TimeOfDayChart(workoutDates: workoutDates)),
          ],
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendDot(Colors.green.shade200),
        _legendDot(Colors.green.shade400),
        _legendDot(Colors.green.shade600),
        _legendDot(Colors.green.shade800),
        const SizedBox(width: 4),
        Text('+ volume', style: TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

/// Weekly frequency bar chart showing last 12 weeks.
class _WeeklyFrequencyChart extends StatelessWidget {
  final List<Map<String, dynamic>> workoutDates;

  const _WeeklyFrequencyChart({required this.workoutDates});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final weeks = <_WeekBar>[];

    // Build last 12 weeks
    for (int i = 11; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (i * 7)));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final startStr = weekStart.toIso8601String().substring(0, 10);
      final endStr = weekEnd.toIso8601String().substring(0, 10);

      int count = 0;
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxCount < 5 ? 5 : maxCount * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) {
                    final w = weeks[gi];
                    return BarTooltipItem(
                      '${w.label}: ${w.count} ${loc.progressWorkouts}',
                      TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= weeks.length) {
                        return const SizedBox.shrink();
                      }
                      if (weeks.length > 6 && idx % 2 != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          weeks[idx].label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 8,
                          ),
                        ),
                      );
                    },
                    reservedSize: 20,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (v, _) {
                      if (v == 0) return const SizedBox.shrink();
                      return Text(
                        '${v.toInt()}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
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
              ),
              barGroups: weeks.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.count.toDouble(),
                      color: theme.colorScheme.primary,
                      width: 16,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Day-of-week distribution bar chart.
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.progressDayOfWeek,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal < 3 ? 3 : maxVal * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 16,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= 7) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            labels[idx],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 8,
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
                  gridData: FlGridData(show: false),
                  barGroups: List.generate(7, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: (dowCount[i] ?? 0).toDouble(),
                          color: _dowColor(i, theme),
                          width: 10,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(3),
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
      ),
    );
  }

  Color _dowColor(int dow, ThemeData theme) {
    if (dow == 0 || dow == 6) return Colors.orange.withAlpha(180);
    return theme.colorScheme.primary;
  }
}

/// Time-of-day pie chart (morning, afternoon, evening, dawn).
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

    if (total == 0) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text(
                loc.progressTimeOfDay,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                Icons.access_time,
                size: 24,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              ),
              Text(
                loc.progressNoData,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
              ),
            ],
          ),
        ),
      );
    }

    final colors = [
      Colors.orange,
      Colors.amber,
      Colors.indigo,
      Colors.deepPurple,
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.progressTimeOfDay,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 1,
                  centerSpaceRadius: 20,
                  sections: List.generate(4, (i) {
                    if (values[i] == 0) {
                      return PieChartSectionData(
                        color: Colors.transparent,
                        value: 0,
                        showTitle: false,
                      );
                    }
                    return PieChartSectionData(
                      color: colors[i],
                      value: values[i].toDouble(),
                      title: '${(values[i] / total * 100).toStringAsFixed(0)}%',
                      titleStyle: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      radius: 28,
                    );
                  }).where((s) => s.value > 0).toList(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...List.generate(4, (i) {
              if (values[i] == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${labels[i]}: ${values[i]}',
                      style: TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Helper class representing a week bar.
class _WeekBar {
  final String label;
  final int count;
  _WeekBar(this.label, this.count);
}
