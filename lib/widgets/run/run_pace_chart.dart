import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Pace-over-distance area chart (faster pace at the top).
///
/// The Y axis ignores the extreme few percent of samples (see
/// [RunPaceAxis]) and values outside it are clipped to the edge, so a stop or
/// a GPS glitch cannot squash the rest of the curve. Touching the chart
/// reports the distance through [selectedDistance] so a map can follow.
class RunPaceChart extends StatelessWidget {
  final List<RunPaceSample> samples;
  final double? avgPaceSecPerKm;
  final String emptyLabel;
  final ValueNotifier<double?>? selectedDistance;

  const RunPaceChart({
    super.key,
    required this.samples,
    required this.avgPaceSecPerKm,
    required this.emptyLabel,
    this.selectedDistance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (samples.length < 2) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final avg = avgPaceSecPerKm != null && avgPaceSecPerKm!.isFinite
        ? avgPaceSecPerKm
        : null;
    final axis = RunPaceAxis.compute(samples, averagePace: avg);
    final maxKm = samples.last.distanceMeters / 1000.0;
    final maxX = maxKm <= 0 ? 1.0 : maxKm;
    final xInterval = niceKmInterval(maxX);

    // Negated so lower sec/km (faster) sits higher; clipped to the axis.
    final spots = [
      for (final s in samples)
        FlSpot(
          s.distanceMeters / 1000.0,
          -s.paceSecPerKm.clamp(axis.minPace, axis.maxPace),
        ),
    ];

    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: -axis.maxPace,
          maxY: -axis.minPace,
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
              getTooltipColor: (_) => primary,
              getTooltipItems: (touched) => touched.map((spot) {
                final sample = samples[spot.spotIndex];
                return LineTooltipItem(
                  '${RunFormatters.paceShort(sample.paceSecPerKm)} /km\n'
                  '${RunFormatters.distanceKm(sample.distanceMeters)} km',
                  TextStyle(
                    color: theme.colorScheme.onPrimary,
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
                          strokeColor: primary,
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
                getTitlesWidget: (value, meta) {
                  final pace = -value;
                  if (pace < axis.minPace - 1 || pace > axis.maxPace + 1) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      RunFormatters.paceShort(pace),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontFeatures: RunUi.tabular,
                      ),
                    ),
                  );
                },
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
                  // Skip a label that would collide with the last tick.
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
            drawHorizontalLine: true,
            drawVerticalLine: false,
            horizontalInterval: axis.interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          extraLinesData: avg == null
              ? const ExtraLinesData()
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: -avg.clamp(axis.minPace, axis.maxPace),
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                      strokeWidth: 1.2,
                      dashArray: const [6, 4],
                    ),
                  ],
                ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              barWidth: 2.4,
              color: primary,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primary.withValues(alpha: 0.4),
                    primary.withValues(alpha: 0.05),
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

  /// Km tick spacing that keeps the axis to about 4-6 labels.
  static double niceKmInterval(double maxKm) {
    const steps = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
    for (final step in steps) {
      if (maxKm / step <= 6) return step;
    }
    return 50;
  }
}
