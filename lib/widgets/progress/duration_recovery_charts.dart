import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/progress_helpers.dart';

/// Displays duration/efficiency and recovery/feeling sections.
class DurationRecoveryCharts extends StatelessWidget {
  final List<Map<String, dynamic>> durationTrend;
  final List<Map<String, dynamic>> densityData;
  final List<Map<String, dynamic>> feelingTrend;
  final List<Map<String, dynamic>> feelingVsVolume;

  const DurationRecoveryCharts({
    super.key,
    required this.durationTrend,
    required this.densityData,
    required this.feelingTrend,
    required this.feelingVsVolume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration
        if (durationTrend.isNotEmpty) ...[
          Text(
            loc.progressDuration,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _DurationChart(data: durationTrend),
          const SizedBox(height: 16),
        ],

        // Density
        if (densityData.isNotEmpty) ...[
          Text(
            loc.progressDensity,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _DensityChart(data: densityData),
          const SizedBox(height: 16),
        ],

        // Feeling
        if (feelingTrend.isNotEmpty) ...[
          Text(
            loc.progressRecoveryFeeling,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _FeelingChart(data: feelingTrend),
          const SizedBox(height: 16),
        ],

        // Feeling vs Volume
        if (feelingVsVolume.isNotEmpty) ...[
          Text(
            loc.progressRecoveryFeelingVsVolume,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _FeelingVsVolumeChart(data: feelingVsVolume),
        ],
      ],
    );
  }
}

/// Workout duration line chart.
class _DurationChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _DurationChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final reversed = data.reversed.toList();
    final values =
        reversed.map((d) => ((d['duration_seconds'] as int?) ?? 0) / 60.0).toList();
    final maxVal = values.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxVal <= 0) return const SizedBox.shrink();

    final avg = values.fold<double>(0, (a, b) => a + b) / values.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  loc.progressAverage(avg.toStringAsFixed(0)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxVal * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        niceInterval(maxVal / 4),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}min',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        interval:
                            data.length > 10 ? 2 : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 ||
                              idx >= reversed.length) {
                            return const SizedBox.shrink();
                          }
                          final d = reversed[idx]['date']
                                  as String? ??
                              '';
                          return Text(
                            d.length >= 10
                                ? d.substring(5)
                                : d,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 7),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: values.asMap().entries.map((e) =>
                          FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: Colors.purple,
                      barWidth: 2.5,
                      dotData: FlDotData(
                          show: values.length <= 20),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.purple.withAlpha(25),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData:
                        LineTouchTooltipData(
                      getTooltipItems: (spots) =>
                          spots.map((s) {
                        final idx = s.spotIndex;
                        final d = idx < reversed.length
                            ? (reversed[idx]['date']
                                    as String? ??
                                '')
                            : '';
                        return LineTooltipItem(
                          '$d\n${s.y.toStringAsFixed(0)}min',
                          TextStyle(
                            color:
                                theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
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
}

/// Workout density bar chart.
class _DensityChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _DensityChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final reversed = data.reversed.toList();
    final densities = reversed.map((d) {
      final vol = (d['volume'] as num?)?.toDouble() ?? 0;
      final dur = (d['duration_seconds'] as int?) ?? 1;
      return dur > 0 ? vol / dur : 0.0;
    }).toList();

    if (densities.isEmpty) return const SizedBox.shrink();
    final maxVal =
        densities.fold<double>(0, (a, b) => a > b ? a : b);
    final avg =
        densities.fold<double>(0, (a, b) => a + b) / densities.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  loc.progressDensityAverage(
                      avg.toStringAsFixed(1)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment:
                      BarChartAlignment.spaceAround,
                  maxY: maxVal * 1.2,
                  barTouchData:
                      BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(0),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 16,
                        interval: data.length > 10
                            ? 2
                            : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 ||
                              idx >= reversed.length) {
                            return const SizedBox.shrink();
                          }
                          final d = reversed[idx]['date']
                                  as String? ??
                              '';
                          return Text(
                            d.length >= 10
                                ? d.substring(5)
                                : d,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 7),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        niceInterval(maxVal / 4),
                  ),
                  barGroups:
                      densities.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: Colors.purple.shade300,
                          width: 10,
                          borderRadius:
                              const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight:
                                Radius.circular(3),
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
      ),
    );
  }
}

/// Feeling rating bar chart.
class _FeelingChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _FeelingChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final reversed = data.reversed.toList();
    final values = reversed
        .map((d) => (d['feeling_rating'] as int?)?.toDouble() ?? 0)
        .toList();

    if (values.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 130,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 5.5,
              minY: 0.5,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) {
                    final d = reversed[gi];
                    final date =
                        d['date'] as String? ?? '';
                    final feeling =
                        d['feeling_rating'] as int? ?? 0;
                    return BarTooltipItem(
                      '$date\n${'★' * feeling}',
                      TextStyle(
                        color:
                            theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      if (v < 1) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '★' * v.toInt(),
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.amber,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 16,
                    interval:
                        data.length > 12 ? 2 : 1,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 ||
                          idx >= reversed.length) {
                        return const SizedBox.shrink();
                      }
                      final d = reversed[idx]['date']
                              as String? ??
                          '';
                      return Text(
                        d.length >= 10
                            ? d.substring(5)
                            : d,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 7),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles:
                        SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles:
                        SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
              ),
              barGroups:
                  values.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value,
                      color: e.value >= 4
                          ? Colors.green
                          : e.value >= 3
                              ? Colors.amber
                              : Colors.red.shade300,
                      width: 10,
                      borderRadius:
                          const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        topRight: Radius.circular(3),
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

/// Feeling vs Volume bar chart.
class _FeelingVsVolumeChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _FeelingVsVolumeChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final maxVol = data.fold<double>(0, (a, b) {
      final v = (b['avg_volume'] as num?)?.toDouble() ?? 0;
      return a > v ? a : v;
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVol * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) {
                    final d = data[gi];
                    final feeling =
                        d['feeling_rating'] as int? ?? 0;
                    final vol =
                        (d['avg_volume'] as num?)?.toDouble() ?? 0;
                    final count =
                        d['workout_count'] as int? ?? 0;
                    return BarTooltipItem(
                      '${'★' * feeling}\n${loc.commonVolume}: ${formatVolume(vol)}\n$count ${loc.progressWorkouts}',
                      TextStyle(
                        color:
                            theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
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
                    reservedSize: 20,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 ||
                          idx >= data.length) {
                        return const SizedBox.shrink();
                      }
                      final feeling = data[idx]
                              ['feeling_rating']
                          as int? ?? 0;
                      return Text(
                        '★' * feeling,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    getTitlesWidget: (v, _) => Text(
                      formatVolume(v),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontSize: 8),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles:
                        SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles:
                        SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval:
                    niceInterval(maxVol / 4),
              ),
              barGroups: data.asMap().entries.map((e) {
                final vol =
                    (e.value['avg_volume'] as num?)?.toDouble() ??
                        0;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: vol,
                      color: Colors.red.shade300,
                      width: 24,
                      borderRadius:
                          const BorderRadius.only(
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
