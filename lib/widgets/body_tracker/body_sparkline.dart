import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// A small sparkline chart shown in the summary card header.
class BodySparkline extends StatelessWidget {
  final List<Map<String, dynamic>> measurements;
  final Color lineColor;

  const BodySparkline({
    super.key,
    required this.measurements,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final reversed = measurements.reversed.toList();
    final values =
        reversed.map((m) => (m['value'] as num).toDouble()).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    return LineChart(
      LineChartData(
        minY: minVal - range * 0.1,
        maxY: maxVal + range * 0.1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: values.asMap().entries
                .map((e) => FlSpot(e.key.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: lineColor.withAlpha(180),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withAlpha(50),
                  lineColor.withAlpha(0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
