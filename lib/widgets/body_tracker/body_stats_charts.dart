import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/body_progress_analytics.dart';

/// Weekly averages as a line, with the period average drawn as a dashed
/// reference. Weeks without data break the line instead of being interpolated.
class BodyWeeklyAverageChart extends StatelessWidget {
  final List<BodyWeekBucket> weeks;
  final double? averageValue;
  final Color color;
  final String unit;
  final String emptyLabel;

  const BodyWeeklyAverageChart({
    super.key,
    required this.weeks,
    required this.averageValue,
    required this.color,
    required this.unit,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final withData = <int>[
      for (var i = 0; i < weeks.length; i++)
        if (weeks[i].hasData) i,
    ];
    if (withData.length < 2) return BodyChartPlaceholder(label: emptyLabel);

    var minVal = weeks[withData.first].average!;
    var maxVal = minVal;
    for (final i in withData) {
      final v = weeks[i].average!;
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }
    final average = averageValue;
    if (average != null) {
      if (average < minVal) minVal = average;
      if (average > maxVal) maxVal = average;
    }
    final span = maxVal - minVal;
    final pad = span <= 0 ? math.max(maxVal.abs() * 0.02, 0.5) : span * 0.18;
    final minY = minVal - pad;
    final maxY = maxVal + pad;
    final interval = _niceInterval(maxY - minY);

    // Contiguous runs are drawn as separate lines so gaps stay visible.
    final segments = <List<FlSpot>>[];
    var current = <FlSpot>[];
    for (var i = 0; i < weeks.length; i++) {
      if (weeks[i].hasData) {
        current.add(FlSpot(i.toDouble(), weeks[i].average!));
      } else if (current.isNotEmpty) {
        segments.add(current);
        current = <FlSpot>[];
      }
    }
    if (current.isNotEmpty) segments.add(current);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: -_edgePad,
          maxX: (weeks.length - 1) + _edgePad,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.vertical(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (average != null && average > minY && average < maxY)
                HorizontalLine(
                  y: average,
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
                  strokeWidth: 1.4,
                  dashArray: const [5, 4],
                ),
            ],
          ),
          titlesData: _titles(
            context: context,
            interval: interval,
            length: weeks.length,
            labelAt: (i) => DateFormat.Md().format(weeks[i].weekStart),
            muted: muted,
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
              getTooltipItems: (touched) => touched.map((t) {
                final i = t.x.round();
                if (i < 0 || i >= weeks.length) return null;
                final w = weeks[i];
                final range =
                    '${DateFormat.Md().format(w.weekStart)} – '
                    '${DateFormat.Md().format(w.weekEnd)}';
                return LineTooltipItem(
                  '$range\n${t.y.toStringAsFixed(1)} $unit',
                  TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            for (final segment in segments)
              LineChartBarData(
                spots: segment,
                isCurved: segment.length > 2,
                curveSmoothness: 0.2,
                color: color,
                barWidth: 2.8,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: withData.length <= 20,
                  getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                    radius: 3.2,
                    color: color,
                    strokeWidth: 1.5,
                    strokeColor: theme.colorScheme.surface,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.22),
                      color.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Week-over-week change as diverging bars around zero. Bars are coloured by
/// whether the change moves in the direction the user wants.
class BodyWeeklyDeltaChart extends StatelessWidget {
  final List<BodyWeekBucket> weeks;
  final bool isDecreasingGood;
  final String unit;
  final String emptyLabel;

  const BodyWeeklyDeltaChart({
    super.key,
    required this.weeks,
    required this.isDecreasingGood,
    required this.unit,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;
    final indexed = <int>[
      for (var i = 0; i < weeks.length; i++)
        if (weeks[i].deltaVsPreviousWeek != null) i,
    ];
    if (indexed.isEmpty) return BodyChartPlaceholder(label: emptyLabel);

    var maxAbs = 0.0;
    for (final i in indexed) {
      final v = weeks[i].deltaVsPreviousWeek!.abs();
      if (v > maxAbs) maxAbs = v;
    }
    final bound = maxAbs <= 0 ? 1.0 : maxAbs * 1.25;
    final interval = _niceInterval(bound * 2);

    Color barColor(double delta) {
      if (delta.abs() < 0.001) return muted;
      final good = isDecreasingGood ? delta < 0 : delta > 0;
      return good ? colors.primary : colors.error;
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: -bound,
          maxY: bound,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceContainerHighest,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final i = group.x;
                if (i < 0 || i >= weeks.length) return null;
                final w = weeks[i];
                final delta = w.deltaVsPreviousWeek ?? 0;
                final sign = delta >= 0 ? '+' : '-';
                return BarTooltipItem(
                  '${DateFormat.Md().format(w.weekStart)}\n'
                  '$sign${delta.abs().toStringAsFixed(2)} $unit',
                  TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: value.abs() < 0.0001
                  ? colors.outlineVariant
                  : colors.outlineVariant.withValues(alpha: 0.3),
              strokeWidth: value.abs() < 0.0001 ? 1.4 : 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            context: context,
            interval: interval,
            length: weeks.length,
            labelAt: (i) => DateFormat.Md().format(weeks[i].weekStart),
            muted: muted,
            leftReserved: 40,
            leftFormatter: (v) => v == 0
                ? '0'
                : '${v > 0 ? '+' : '-'}${v.abs().toStringAsFixed(1)}',
          ),
          barGroups: [
            for (final i in indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    fromY: 0,
                    toY: weeks[i].deltaVsPreviousWeek!,
                    width: _barWidth(indexed.length),
                    borderRadius: BorderRadius.circular(3),
                    color: barColor(weeks[i].deltaVsPreviousWeek!),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Raw daily values with the trailing 7-day mean overlaid, so day-to-day
/// noise can be told apart from the underlying trend.
class BodyDailyTrendChart extends StatelessWidget {
  final List<BodyDailyPoint> daily;
  final List<double> smoothed;
  final Color color;
  final String unit;
  final String emptyLabel;

  const BodyDailyTrendChart({
    super.key,
    required this.daily,
    required this.smoothed,
    required this.color,
    required this.unit,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;
    if (daily.length < 2) return BodyChartPlaceholder(label: emptyLabel);

    var minVal = daily.first.value;
    var maxVal = minVal;
    for (final p in daily) {
      if (p.value < minVal) minVal = p.value;
      if (p.value > maxVal) maxVal = p.value;
    }
    final span = maxVal - minVal;
    final pad = span <= 0 ? math.max(maxVal.abs() * 0.02, 0.5) : span * 0.18;
    final minY = minVal - pad;
    final maxY = maxVal + pad;
    final interval = _niceInterval(maxY - minY);
    final hasSmoothed = smoothed.length == daily.length;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: -_edgePad,
          maxX: (daily.length - 1) + _edgePad,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.vertical(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colors.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            context: context,
            interval: interval,
            length: daily.length,
            labelAt: (i) => DateFormat.Md().format(daily[i].date),
            muted: muted,
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceContainerHighest,
              getTooltipItems: (touched) => touched.map((t) {
                if (t.barIndex != 0) return null;
                final i = t.x.round();
                if (i < 0 || i >= daily.length) return null;
                return LineTooltipItem(
                  '${DateFormat.MMMd().format(daily[i].date)}\n'
                  '${daily[i].value.toStringAsFixed(1)} $unit',
                  TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < daily.length; i++)
                  FlSpot(i.toDouble(), daily[i].value),
              ],
              isCurved: false,
              color: color.withValues(alpha: 0.35),
              barWidth: 1.4,
              dotData: FlDotData(
                show: daily.length <= 40,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: 2.2,
                  color: color.withValues(alpha: 0.55),
                  strokeWidth: 0,
                ),
              ),
            ),
            if (hasSmoothed)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < smoothed.length; i++)
                    FlSpot(i.toDouble(), smoothed[i]),
                ],
                isCurved: true,
                curveSmoothness: 0.2,
                color: color,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.18),
                      color.withValues(alpha: 0.01),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared empty state so every chart tab reserves the same height.
class BodyChartPlaceholder extends StatelessWidget {
  final String label;

  const BodyChartPlaceholder({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 200,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

FlTitlesData _titles({
  required BuildContext context,
  required double interval,
  required int length,
  required String Function(int index) labelAt,
  required Color muted,
  double leftReserved = 38,
  String Function(double value)? leftFormatter,
}) {
  final style = Theme.of(
    context,
  ).textTheme.labelSmall?.copyWith(color: muted, fontSize: 10);
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: leftReserved,
        interval: interval,
        getTitlesWidget: (value, meta) {
          if (value <= meta.min || value >= meta.max) {
            return const SizedBox.shrink();
          }
          final text =
              leftFormatter?.call(value) ??
              value.toStringAsFixed(value.abs() >= 100 ? 0 : 1);
          return SideTitleWidget(
            meta: meta,
            space: 6,
            child: Text(text, style: style),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if (!_showTick(i, length)) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            space: 6,
            fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
            child: Text(labelAt(i), style: style),
          );
        },
      ),
    ),
  );
}

/// Ticks are spaced counting back from the newest bucket, so the most recent
/// label is always shown and never collides with its neighbour.
bool _showTick(int index, int length, {int maxTicks = 5}) {
  if (index < 0 || index >= length) return false;
  final step = (length / maxTicks).ceil().clamp(1, length);
  return (length - 1 - index) % step == 0;
}

/// Domain padding, in index units, that keeps edge dots from being clipped.
const _edgePad = 0.2;

double _barWidth(int count) {
  if (count > 26) return 5;
  if (count > 20) return 6;
  if (count > 12) return 9;
  return 14;
}

/// Rounded gridline step so at most ~5 lines are drawn for [range].
double _niceInterval(double range) {
  if (range <= 0) return 1;
  const steps = <double>[
    0.1,
    0.2,
    0.25,
    0.5,
    1,
    2,
    2.5,
    5,
    10,
    20,
    25,
    50,
    100,
  ];
  for (final step in steps) {
    if (range / step <= 5) return step;
  }
  return (range / 5).ceilToDouble();
}
