import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Shared sizing, colours and tick helpers so every running chart looks and
/// behaves alike.
abstract final class RunChartStyle {
  static const double height = 200;
  static const double emptyHeight = 160;

  static Color grid(ColorScheme colors) =>
      colors.outlineVariant.withValues(alpha: 0.35);

  static Color track(ColorScheme colors) =>
      colors.surfaceContainerHighest.withValues(alpha: 0.35);

  static TextStyle? axis(ThemeData theme) => theme.textTheme.labelSmall
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

  static TextStyle tooltip(ThemeData theme) => TextStyle(
    color: theme.colorScheme.onSurface,
    fontWeight: FontWeight.w700,
    fontSize: 12,
  );

  static FlLine gridLine(ColorScheme colors) =>
      FlLine(color: grid(colors), strokeWidth: 1);

  static const FlTitlesData noSideTitles = FlTitlesData(
    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );

  static double barWidth(int count) {
    if (count > 26) return 5;
    if (count > 20) return 6;
    if (count > 12) return 9;
    return 14;
  }

  /// Ticks are spaced counting back from the newest bucket, so the most
  /// recent label is always shown and never collides with its neighbour.
  static bool showBucketTick(int index, int length, {int maxTicks = 6}) {
    if (index < 0 || index >= length) return false;
    final step = (length / maxTicks).ceil().clamp(1, length);
    return (length - 1 - index) % step == 0;
  }

  /// Round gridline step (km, minutes...) with roughly four to six lines.
  static double niceInterval(double maxY) {
    if (maxY <= 2) return 0.5;
    if (maxY <= 5) return 1;
    if (maxY <= 10) return 2;
    if (maxY <= 25) return 5;
    if (maxY <= 60) return 10;
    if (maxY <= 120) return 20;
    if (maxY <= 300) return 50;
    return 100;
  }

  /// Pace steps in seconds, chosen so at most ~4 gridlines are drawn.
  static double nicePaceInterval(double range) {
    const steps = <double>[10, 15, 30, 60, 120, 300, 600];
    for (final step in steps) {
      if (range / step <= 4) return step;
    }
    return (range / 4).ceilToDouble();
  }

  static String axisNumber(double value) => RunFormatters.decimal(
    value,
    value >= 10 || value == value.roundToDouble() ? 0 : 1,
  );
}

/// Placeholder shown by a chart with too little data.
class RunChartEmpty extends StatelessWidget {
  final String label;

  const RunChartEmpty({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: RunChartStyle.emptyHeight,
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Small unit caption drawn above the plot ("km", "min/km", "corridas").
class RunChartUnit extends StatelessWidget {
  final String unit;

  const RunChartUnit(this.unit, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        unit,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bottom label of a bucket: `d/M` for weeks, the month for month buckets.
String runBucketLabel(RunWeekBucket bucket, String locale) => bucket.isMonthly
    ? DateFormat.MMM(locale).format(bucket.weekStart)
    : DateFormat.Md(locale).format(bucket.weekStart);

/// Tooltip heading of a bucket.
String runBucketHeading(
  AppLocalizations loc,
  RunWeekBucket bucket,
  String locale,
) => bucket.isMonthly
    ? DateFormat.yMMM(locale).format(bucket.weekStart)
    : loc.runStatsChartTooltipWeek(
        DateFormat.MMMd(locale).format(bucket.weekStart),
      );

/// Weekly (or monthly) distance bars. The last bar is the period in progress
/// and is highlighted; [averageMeters] draws a dashed reference line whose
/// legend is [averageLabel].
class RunWeeklyDistanceChart extends StatelessWidget {
  final List<RunWeekBucket> buckets;
  final String emptyLabel;
  final double? averageMeters;
  final String? averageLabel;

  const RunWeeklyDistanceChart({
    super.key,
    required this.buckets,
    required this.emptyLabel,
    this.averageMeters,
    this.averageLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!buckets.any((b) => b.distanceMeters > 0)) {
      return RunChartEmpty(label: emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final maxKm = buckets
        .map((b) => b.distanceMeters / 1000.0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = (maxKm * 1.2).clamp(1.0, double.infinity);
    final interval = RunChartStyle.niceInterval(maxY);
    final averageKm = (averageMeters ?? 0) / 1000.0;
    final showAverage = averageKm > 0 && averageKm < maxY;
    final averageColor = colors.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(loc.runStatsChartUnitKm),
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
                    if (groupIndex < 0 || groupIndex >= buckets.length) {
                      return null;
                    }
                    final b = buckets[groupIndex];
                    final lines = [
                      runBucketHeading(loc, b, locale),
                      RunFormatters.distanceWithUnit(b.distanceMeters),
                      loc.runHomeWeekRunCount(b.runCount),
                      if (b.movingTimeSeconds > 0)
                        RunFormatters.durationHoursMinutes(b.movingTimeSeconds),
                    ];
                    return BarTooltipItem(
                      lines.join('\n'),
                      RunChartStyle.tooltip(theme),
                    );
                  },
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (showAverage)
                    HorizontalLine(
                      y: averageKm,
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
                    reservedSize: 34,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0 || value >= maxY) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          RunChartStyle.axisNumber(value),
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
                      if (!RunChartStyle.showBucketTick(i, buckets.length)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          runBucketLabel(buckets[i], locale),
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
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[i].distanceMeters / 1000.0,
                        width: RunChartStyle.barWidth(buckets.length),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        color: i == buckets.length - 1
                            ? colors.primary
                            : colors.primary.withValues(alpha: 0.5),
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

/// Pace over time: a real date axis, faster pace higher, a dashed linear
/// trend line and a legend.
class RunPaceTrendChart extends StatelessWidget {
  final List<RunPacePoint> points;
  final String emptyLabel;

  /// Fit of the points in days since the first point; null hides the line.
  final RunLinearFit? trend;

  const RunPaceTrendChart({
    super.key,
    required this.points,
    required this.emptyLabel,
    this.trend,
  });

  static const _dayMs = 86400000.0;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return RunChartEmpty(label: emptyLabel);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final originMs = points.first.date.millisecondsSinceEpoch.toDouble();
    double xOf(DateTime date) =>
        (date.millisecondsSinceEpoch - originMs) / _dayMs;
    final spanDays = xOf(points.last.date);
    // A single day of history would collapse the axis.
    final maxX = spanDays < 1 ? 1.0 : spanDays;
    final xPad = maxX * 0.03;

    var minPace = points.first.paceSecPerKm;
    var maxPace = points.first.paceSecPerKm;
    for (final p in points) {
      if (p.paceSecPerKm < minPace) minPace = p.paceSecPerKm;
      if (p.paceSecPerKm > maxPace) maxPace = p.paceSecPerKm;
    }
    final fit = trend;
    if (fit != null) {
      for (final x in [0.0, maxX]) {
        final v = fit.at(x);
        if (v < minPace) minPace = v;
        if (v > maxPace) maxPace = v;
      }
    }
    final pad = ((maxPace - minPace) * 0.15).clamp(10.0, 60.0);
    final chartMin = (minPace - pad).clamp(30.0, maxPace);
    final chartMax = maxPace + pad;
    final range = (chartMax - chartMin).abs();
    final paceInterval = RunChartStyle.nicePaceInterval(range);
    final edgeGuard = range * 0.08;
    final dateFormat = maxX > 200
        ? DateFormat.yMMM(locale)
        : maxX > 45
        ? DateFormat.MMM(locale)
        : DateFormat.Md(locale);

    final spots = [
      for (final p in points) FlSpot(xOf(p.date), -p.paceSecPerKm),
    ];
    final primary = colors.primary;
    final trendColor = colors.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RunChartUnit('min/km'),
        SizedBox(
          height: RunChartStyle.height,
          child: LineChart(
            LineChartData(
              minX: -xPad,
              maxX: maxX + xPad,
              minY: -chartMax,
              maxY: -chartMin,
              clipData: const FlClipData.all(),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceContainerHighest,
                  getTooltipItems: (touched) {
                    return touched.map((t) {
                      if (t.barIndex != 0) return null;
                      final i = t.spotIndex;
                      if (i < 0 || i >= points.length) return null;
                      final p = points[i];
                      return LineTooltipItem(
                        '${DateFormat.yMMMd(locale).format(p.date)}\n'
                        '${RunFormatters.paceWithUnit(p.paceSecPerKm)}\n'
                        '${RunFormatters.distanceWithUnit(p.distanceMeters)}',
                        RunChartStyle.tooltip(theme),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: paceInterval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: RunChartStyle.noSideTitles.topTitles,
                rightTitles: RunChartStyle.noSideTitles.rightTitles,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: paceInterval,
                    getTitlesWidget: (value, meta) {
                      final pace = -value;
                      if (pace < chartMin + edgeGuard ||
                          pace > chartMax - edgeGuard) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          RunFormatters.paceShort(pace),
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
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.2,
                  preventCurveOverShooting: true,
                  color: primary,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: points.length <= 24,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                          radius: 3.5,
                          color: primary,
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
                        primary.withValues(alpha: 0.2),
                        primary.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
                if (fit != null)
                  LineChartBarData(
                    spots: [FlSpot(0, -fit.at(0)), FlSpot(maxX, -fit.at(maxX))],
                    color: trendColor.withValues(alpha: 0.9),
                    barWidth: 1.6,
                    dashArray: const [6, 4],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            RunLegendItem(color: primary, label: loc.runStatsChartRunsLegend),
            if (fit != null)
              RunLegendItem(
                color: trendColor,
                label: loc.runStatsChartTrendLine,
                dashed: true,
              ),
          ],
        ),
      ],
    );
  }
}

/// Weekly (or monthly) run-count bars.
class RunWeeklyFrequencyChart extends StatelessWidget {
  final List<RunWeekBucket> buckets;
  final String emptyLabel;
  final double? averageRuns;
  final String? averageLabel;

  const RunWeeklyFrequencyChart({
    super.key,
    required this.buckets,
    required this.emptyLabel,
    this.averageRuns,
    this.averageLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!buckets.any((b) => b.runCount > 0)) {
      return RunChartEmpty(label: emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final maxCount = buckets
        .map((b) => b.runCount)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount + 1).toDouble().clamp(3.0, double.infinity);
    final countInterval = maxY > 8 ? 2.0 : 1.0;
    final average = averageRuns ?? 0;
    final showAverage = average > 0 && average < maxY;
    final averageColor = colors.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(loc.runStatsChartUnitRuns),
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
                    if (groupIndex < 0 || groupIndex >= buckets.length) {
                      return null;
                    }
                    final b = buckets[groupIndex];
                    return BarTooltipItem(
                      '${runBucketHeading(loc, b, locale)}\n'
                      '${loc.runHomeWeekRunCount(b.runCount)}',
                      RunChartStyle.tooltip(theme),
                    );
                  },
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (showAverage)
                    HorizontalLine(
                      y: average,
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
                    reservedSize: 26,
                    interval: countInterval,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0 || value != value.roundToDouble()) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          value.toInt().toString(),
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
                      if (!RunChartStyle.showBucketTick(i, buckets.length)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          runBucketLabel(buckets[i], locale),
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
                horizontalInterval: countInterval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[i].runCount.toDouble(),
                        width: RunChartStyle.barWidth(buckets.length),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        color: i == buckets.length - 1
                            ? colors.secondary
                            : colors.secondary.withValues(alpha: 0.5),
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
