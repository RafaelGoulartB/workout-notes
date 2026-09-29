import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/run/run_progress_charts.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// One bar: bottom [label], [value] and the multi-line [tooltip].
class StrengthBarPoint {
  final String label;
  final double value;
  final String tooltip;

  const StrengthBarPoint({
    required this.label,
    required this.value,
    required this.tooltip,
  });
}

/// Bars over consecutive weeks/months, styled like the running charts. The
/// last bar is the period in progress and is highlighted; [average] draws a
/// dashed reference line whose legend is [averageLabel].
class StrengthBarChart extends StatelessWidget {
  final List<StrengthBarPoint> points;
  final String unit;
  final String emptyLabel;
  final double? average;
  final String? averageLabel;
  final Color? color;

  /// Whole-number axis (sessions, sets) instead of a rounded scale.
  final bool integerAxis;

  const StrengthBarChart({
    super.key,
    required this.points,
    required this.unit,
    required this.emptyLabel,
    this.average,
    this.averageLabel,
    this.color,
    this.integerAxis = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!points.any((p) => p.value > 0)) {
      return RunChartEmpty(label: emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final barColor = color ?? colors.primary;

    final maxValue = points.fold<double>(
      0,
      (a, p) => p.value > a ? p.value : a,
    );
    final maxY = integerAxis
        ? (maxValue.ceil() + 1).toDouble().clamp(3.0, double.infinity)
        : maxValue * 1.2;
    final interval = integerAxis
        ? (maxY > 8 ? 2.0 : 1.0)
        : StrengthFormat.niceInterval(maxY);
    final avg = average ?? 0;
    final showAverage = avg > 0 && avg < maxY;
    final averageColor = colors.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(unit),
        SizedBox(
          height: RunChartStyle.height,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceContainerHighest,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (groupIndex < 0 || groupIndex >= points.length) {
                      return null;
                    }
                    return BarTooltipItem(
                      points[groupIndex].tooltip,
                      RunChartStyle.tooltip(theme),
                    );
                  },
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (showAverage)
                    HorizontalLine(
                      y: avg,
                      color: averageColor.withValues(alpha: 0.8),
                      strokeWidth: 1.4,
                      dashArray: const [5, 4],
                    ),
                ],
              ),
              titlesData: FlTitlesData(
                topTitles: RunChartStyle.noSideTitles.topTitles,
                rightTitles: RunChartStyle.noSideTitles.rightTitles,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0 ||
                          value >= maxY ||
                          (integerAxis && value != value.roundToDouble())) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          StrengthFormat.axis(value),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (!RunChartStyle.showBucketTick(i, points.length)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          points[i].label,
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].value,
                        width: RunChartStyle.barWidth(points.length),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        color: i == points.length - 1
                            ? barColor
                            : barColor.withValues(alpha: 0.5),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxY,
                          color: RunChartStyle.track(colors),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (showAverage && averageLabel != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: RunLegendItem(
              color: averageColor,
              label: averageLabel!,
              dashed: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// One point of a [StrengthTrendChart].
class StrengthTrendPoint {
  final DateTime date;
  final double value;
  final String tooltip;

  const StrengthTrendPoint({
    required this.date,
    required this.value,
    required this.tooltip,
  });
}

/// Values over time with a real date axis (dd/MM), area fill, tooltips and an
/// optional dashed trend line, styled like the running pace chart.
class StrengthTrendChart extends StatelessWidget {
  final List<StrengthTrendPoint> points;
  final String unit;
  final String emptyLabel;
  final Color? color;
  final String? pointsLabel;
  final String? trendLabel;

  /// Draw a least-squares trend line (needs at least three points).
  final bool showTrend;

  /// Y scale starts at zero (volume, reps) instead of hugging the data.
  final bool zeroBased;

  /// Fixed scale, e.g. 1 to 5 for a rating.
  final double? fixedMin;
  final double? fixedMax;

  const StrengthTrendChart({
    super.key,
    required this.points,
    required this.unit,
    required this.emptyLabel,
    this.color,
    this.pointsLabel,
    this.trendLabel,
    this.showTrend = false,
    this.zeroBased = false,
    this.fixedMin,
    this.fixedMax,
  });

  static const _dayMs = 86400000.0;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return RunChartEmpty(label: emptyLabel);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final lineColor = color ?? colors.primary;
    final trendColor = colors.tertiary;

    final originMs = points.first.date.millisecondsSinceEpoch.toDouble();
    double xOf(DateTime d) => (d.millisecondsSinceEpoch - originMs) / _dayMs;
    final maxX = xOf(points.last.date) < 1 ? 1.0 : xOf(points.last.date);
    final xPad = maxX * 0.03;

    final xs = [for (final p in points) xOf(p.date)];
    final ys = [for (final p in points) p.value];
    final fit = showTrend && points.length >= 3
        ? RunLinearFit.fit(xs, ys)
        : null;

    var lo = ys.reduce((a, b) => a < b ? a : b);
    var hi = ys.reduce((a, b) => a > b ? a : b);
    if (fit != null) {
      for (final x in [0.0, maxX]) {
        final v = fit.at(x);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    final span = (hi - lo).abs();
    final pad = span == 0 ? (hi.abs() * 0.1).clamp(1.0, 50.0) : span * 0.18;
    var minY = fixedMin ?? (zeroBased ? 0.0 : (lo - pad).clamp(0.0, hi));
    var maxY = fixedMax ?? hi + pad;
    if (maxY <= minY) maxY = minY + 1;
    final interval = StrengthFormat.niceInterval(maxY - minY);
    // Start on a gridline so labels read round.
    if (fixedMin == null && !zeroBased) {
      minY = (minY / interval).floor() * interval;
    }
    final dateFormat = maxX > 200
        ? DateFormat.yMMM(locale)
        : DateFormat('dd/MM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(unit),
        SizedBox(
          height: RunChartStyle.height,
          child: LineChart(
            LineChartData(
              minX: -xPad,
              maxX: maxX + xPad,
              minY: minY,
              maxY: maxY,
              clipData: const FlClipData.all(),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceContainerHighest,
                  getTooltipItems: (touched) => touched.map((t) {
                    if (t.barIndex != 0) return null;
                    final i = t.spotIndex;
                    if (i < 0 || i >= points.length) return null;
                    return LineTooltipItem(
                      points[i].tooltip,
                      RunChartStyle.tooltip(theme),
                    );
                  }).toList(),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: RunChartStyle.noSideTitles.topTitles,
                rightTitles: RunChartStyle.noSideTitles.rightTitles,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value < minY - 0.001 || value > maxY - interval / 2) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          StrengthFormat.axis(value),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: maxX / 4,
                    getTitlesWidget: (value, meta) {
                      if (value < -0.001 || value > maxX + 0.001) {
                        return const SizedBox.shrink();
                      }
                      final date = points.first.date.add(
                        Duration(minutes: (value * 24 * 60).round()),
                      );
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          dateFormat.format(date),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(xs[i], ys[i]),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.2,
                  preventCurveOverShooting: true,
                  color: lineColor,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: points.length <= 24,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                          radius: 3.5,
                          color: lineColor,
                          strokeWidth: 1.5,
                          strokeColor: colors.surface,
                        ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: 0.2),
                        lineColor.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
                if (fit != null)
                  LineChartBarData(
                    spots: [FlSpot(0, fit.at(0)), FlSpot(maxX, fit.at(maxX))],
                    color: trendColor.withValues(alpha: 0.9),
                    barWidth: 1.6,
                    dashArray: const [6, 4],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        if (pointsLabel != null || (fit != null && trendLabel != null)) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (pointsLabel != null)
                RunLegendItem(color: lineColor, label: pointsLabel!),
              if (fit != null && trendLabel != null)
                RunLegendItem(
                  color: trendColor,
                  label: trendLabel!,
                  dashed: true,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tiny trend line for list rows: no axes, the last point highlighted.
class StrengthSparkline extends StatelessWidget {
  final List<double> values;
  final Color? color;
  final double width;
  final double height;

  const StrengthSparkline({
    super.key,
    required this.values,
    this.color,
    this.width = 64,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(values, tint, Theme.of(context).colorScheme),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final ColorScheme scheme;

  const _SparklinePainter(this.values, this.color, this.scheme);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      // A single session is only a dot.
      if (values.length == 1) {
        canvas.drawCircle(
          Offset(size.width - 3, size.height / 2),
          3,
          Paint()..color = color,
        );
      }
      return;
    }
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    const inset = 3.0;
    Offset at(int i) => Offset(
      inset + (size.width - 2 * inset) * i / (values.length - 1),
      inset + (size.height - 2 * inset) * (1 - (values[i] - lo) / span),
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final last = at(values.length - 1);
    canvas.drawCircle(last, 3.2, Paint()..color = color);
    canvas.drawCircle(
      last,
      3.2,
      Paint()
        ..color = scheme.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}
