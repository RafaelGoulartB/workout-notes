import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';

/// Full-size trend chart for the selected measurement type.
class BodyChartCard extends StatelessWidget {
  final List<Map<String, dynamic>> measurements;
  final MeasureType type;

  const BodyChartCard({
    super.key,
    required this.measurements,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final reversed = measurements.reversed.toList();
    final values = reversed.map((m) => (m['value'] as num).toDouble()).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  loc.bodyTrackerTrendLine,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: minVal - range * 0.15,
                    maxY: maxVal + range * 0.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: range > 0
                          ? niceInterval(range / 4)
                          : 1,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: theme.colorScheme.outlineVariant.withAlpha(40),
                        strokeWidth: 0.5,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(v >= 100 ? 0 : 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: reversed.length > 10 ? 2 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= reversed.length) {
                              return const SizedBox.shrink();
                            }
                            final d = reversed[idx]['date'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                d.length >= 10 ? d.substring(5) : d,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9,
                                ),
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
                    lineBarsData: [
                      LineChartBarData(
                        spots: values
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: type.color,
                        barWidth: 3,
                        dotData: FlDotData(
                          show: values.length <= 30,
                          getDotPainter: (s, p, b, i) =>
                              FlDotCirclePainter(radius: 3, color: type.color),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              type.color.withAlpha(40),
                              type.color.withAlpha(0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final idx = s.spotIndex;
                          final date = idx < reversed.length
                              ? (reversed[idx]['date'] as String? ?? '')
                              : '';
                          return LineTooltipItem(
                            '$date\n${s.y.toStringAsFixed(1)} ${type.unit}',
                            TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
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
      ),
    );
  }
}

/// Chart showing both left and right trends overlaid for comparison.
class BodyBilateralChartCard extends StatelessWidget {
  final List<Map<String, dynamic>> leftMeasurements;
  final List<Map<String, dynamic>> rightMeasurements;
  final MeasureType type;

  const BodyBilateralChartCard({
    super.key,
    required this.leftMeasurements,
    required this.rightMeasurements,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final leftRev = leftMeasurements.reversed.toList();
    final rightRev = rightMeasurements.reversed.toList();
    final leftValues = leftRev
        .map((m) => (m['value'] as num).toDouble())
        .toList();
    final rightValues = rightRev
        .map((m) => (m['value'] as num).toDouble())
        .toList();
    final allValues = [...leftValues, ...rightValues];
    final minVal = allValues.reduce((a, b) => a < b ? a : b);
    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;
    final maxLen = leftValues.length > rightValues.length
        ? leftValues.length
        : rightValues.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  loc.bodyTrackerTrendLine,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Legend
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    _legendDot(Colors.blue, loc.bodyTrackerLeft),
                    const SizedBox(width: 16),
                    _legendDot(Colors.red, loc.bodyTrackerRight),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: minVal - range * 0.15,
                    maxY: maxVal + range * 0.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: range > 0
                          ? niceInterval(range / 4)
                          : 1,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: theme.colorScheme.outlineVariant.withAlpha(40),
                        strokeWidth: 0.5,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(v >= 100 ? 0 : 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: maxLen > 10 ? 2 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= maxLen) {
                              return const SizedBox.shrink();
                            }
                            final leftDate = idx < leftRev.length
                                ? (leftRev[idx]['date'] as String? ?? '')
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                leftDate.length >= 10
                                    ? leftDate.substring(5)
                                    : leftDate,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9,
                                ),
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
                    lineBarsData: [
                      // Left line
                      LineChartBarData(
                        spots: leftValues
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                      // Right line
                      LineChartBarData(
                        spots: rightValues
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: Colors.red,
                        barWidth: 3,
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final isLeft = s.barIndex == 0;
                          final idx = s.spotIndex;
                          final date = isLeft
                              ? (idx < leftRev.length
                                    ? (leftRev[idx]['date'] as String? ?? '')
                                    : '')
                              : (idx < rightRev.length
                                    ? (rightRev[idx]['date'] as String? ?? '')
                                    : '');
                          final side = isLeft
                              ? loc.bodyTrackerLeft
                              : loc.bodyTrackerRight;
                          return LineTooltipItem(
                            '$date\n$side: ${s.y.toStringAsFixed(1)} ${type.unit}',
                            TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
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
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11)),
      ],
    );
  }
}

/// Nice interval helper for chart axis spacing.
double niceInterval(double range) {
  if (range <= 0) return 1;
  final rough = range / 5;
  double magnitude = 1;
  double temp = rough;
  while (temp >= 10) {
    temp /= 10;
    magnitude *= 10;
  }
  while (temp < 1) {
    temp *= 10;
    magnitude /= 10;
  }
  if (temp <= 1) {
    temp = 1;
  } else if (temp <= 2) {
    temp = 2;
  } else if (temp <= 5) {
    temp = 5;
  } else {
    temp = 10;
  }
  final result = temp * magnitude;
  return result < 0.5 ? 0.5 : result;
}
