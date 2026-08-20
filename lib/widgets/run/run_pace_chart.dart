import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

/// Pace-over-distance area chart (faster pace at the top).
class RunPaceChart extends StatelessWidget {
  final List<RunPaceSample> samples;
  final double? avgPaceSecPerKm;
  final String emptyLabel;

  const RunPaceChart({
    super.key,
    required this.samples,
    required this.avgPaceSecPerKm,
    required this.emptyLabel,
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

    // Plot negative pace so lower sec/km (faster) sits higher on the chart.
    final spots = [
      for (final s in samples)
        FlSpot(s.distanceMeters / 1000.0, -s.paceSecPerKm),
    ];

    var minPace = samples.first.paceSecPerKm;
    var maxPace = samples.first.paceSecPerKm;
    for (final s in samples) {
      if (s.paceSecPerKm < minPace) minPace = s.paceSecPerKm;
      if (s.paceSecPerKm > maxPace) maxPace = s.paceSecPerKm;
    }
    final avg = avgPaceSecPerKm;
    if (avg != null && avg.isFinite) {
      if (avg < minPace) minPace = avg;
      if (avg > maxPace) maxPace = avg;
    }

    final pad = ((maxPace - minPace) * 0.12).clamp(8.0, 60.0);
    final chartMinPace = (minPace - pad).clamp(30.0, maxPace);
    final chartMaxPace = maxPace + pad;
    final maxX = samples.last.distanceMeters / 1000.0;
    final xInterval = _xInterval(maxX);
    final yInterval = _yInterval(chartMaxPace - chartMinPace);

    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX <= 0 ? 1 : maxX,
          // Faster pace (lower sec/km) sits higher — plot negated Y.
          minY: -chartMaxPace,
          maxY: -chartMinPace,
          clipData: const FlClipData.all(),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              getTooltipColor: (_) => primary,
              getTooltipItems: (touched) => touched.map((spot) {
                final pace = -spot.y;
                final km = spot.x;
                return LineTooltipItem(
                  '${RunFormatters.pace(pace)} /km\n'
                  '${km.toStringAsFixed(km < 10 ? 2 : 1)} km',
                  TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.25,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
                reservedSize: 40,
                interval: yInterval,
                getTitlesWidget: (value, meta) {
                  final pace = -value;
                  if (pace < chartMinPace - 1 || pace > chartMaxPace + 1) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    RunFormatters.pace(pace),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
                  final nearEdge = value < 0.01 || (maxX - value).abs() < 0.01;
                  final onStep = (value / xInterval - (value / xInterval).round())
                          .abs() <
                      0.02;
                  if (!nearEdge && !onStep) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      value.toStringAsFixed(1),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                      ),
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
            drawVerticalLine: true,
            horizontalInterval: yInterval,
            verticalInterval: xInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              strokeWidth: 1,
            ),
          ),
          extraLinesData: avg == null || !avg.isFinite
              ? const ExtraLinesData()
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: -avg,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      strokeWidth: 1.2,
                      dashArray: const [6, 4],
                    ),
                  ],
                ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.18,
              preventCurveOverShooting: true,
              barWidth: 2.2,
              color: primary,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primary.withValues(alpha: 0.45),
                    primary.withValues(alpha: 0.08),
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

  static double _xInterval(double maxX) {
    if (maxX <= 1.2) return 0.5;
    if (maxX <= 3) return 0.5;
    if (maxX <= 8) return 1.0;
    if (maxX <= 20) return 2.0;
    return 5.0;
  }

  static double _yInterval(double spanSec) {
    if (spanSec <= 90) return 30;
    if (spanSec <= 180) return 60;
    if (spanSec <= 360) return 120;
    return 180;
  }
}
