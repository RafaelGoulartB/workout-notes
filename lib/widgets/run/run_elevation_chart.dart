import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/utils/run_elevation_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_pace_chart.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Smoothed altitude profile over distance. Touching it reports the distance
/// through [selectedDistance], like [RunPaceChart].
class RunElevationChart extends StatelessWidget {
  final RunElevationProfile profile;
  final ValueNotifier<double?>? selectedDistance;

  const RunElevationChart({
    super.key,
    required this.profile,
    this.selectedDistance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = profile.samples;
    if (samples.length < 2) return const SizedBox(height: 220);

    final axis = RunElevationAxis.compute(profile);
    final maxKm = samples.last.distanceMeters / 1000.0;
    final maxX = maxKm <= 0 ? 1.0 : maxKm;
    final xInterval = RunPaceChart.niceKmInterval(maxX);
    final line = theme.colorScheme.tertiary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: axis.minAltitude,
          maxY: axis.maxAltitude,
          clipData: const FlClipData.all(),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchCallback: (event, response) {
              final notifier = selectedDistance;
              if (notifier == null) return;
              final spot = response?.lineBarSpots?.firstOrNull;
              if (!event.isInterestedForInteractions || spot == null) {
                notifier.value = null;
                return;
              }
              notifier.value = samples[spot.spotIndex].distanceMeters;
            },
            touchTooltipData: LineTouchTooltipData(
              tooltipBorderRadius: BorderRadius.circular(10),
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              getTooltipColor: (_) => line,
              getTooltipItems: (touched) => touched.map((spot) {
                final sample = samples[spot.spotIndex];
                return LineTooltipItem(
                  '${RunFormatters.elevation(sample.altitudeMeters)}\n'
                  '${RunFormatters.distanceKm(sample.distanceMeters)} km',
                  TextStyle(
                    color: theme.colorScheme.onTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.25,
                    fontFeatures: RunUi.tabular,
                  ),
                );
              }).toList(),
            ),
            getTouchedSpotIndicator: (bar, indexes) => indexes
                .map(
                  (i) => TouchedSpotIndicatorData(
                    FlLine(
                      color: theme.colorScheme.onSurface,
                      strokeWidth: 1.2,
                    ),
                    FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4.5,
                          color: theme.colorScheme.onSurface,
                          strokeWidth: 2,
                          strokeColor: line,
                        );
                      },
                    ),
                  ),
                )
                .toList(),
          ),
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
                reservedSize: 44,
                interval: axis.interval,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${value.round()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: xInterval,
                getTitlesWidget: (value, meta) {
                  if (value < 0 || value > maxX + 0.01) {
                    return const SizedBox.shrink();
                  }
                  if (value > 0.01 && (maxX - value) < xInterval * 0.3) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      RunFormatters.distanceKmShort(value * 1000),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: axis.interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final s in samples)
                  FlSpot(s.distanceMeters / 1000.0, s.altitudeMeters),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              barWidth: 2.4,
              color: line,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    line.withValues(alpha: 0.4),
                    line.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
