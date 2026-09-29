import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_progress_charts.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Colour of a pace zone: a cool-to-warm ramp (blue → teal → amber →
/// orange → red) so neighbouring zones stay distinguishable in stacked bars.
/// Lightness follows the theme brightness.
Color runZoneColor(ColorScheme colors, RunZone zone) {
  const hues = {
    RunZone.z1: 205.0,
    RunZone.z2: 165.0,
    RunZone.z3: 45.0,
    RunZone.z4: 22.0,
    RunZone.z5: 355.0,
  };
  final dark = colors.brightness == Brightness.dark;
  return HSLColor.fromAHSL(
    1,
    hues[zone]!,
    dark ? 0.62 : 0.58,
    dark ? 0.64 : 0.48,
  ).toColor();
}

String runZoneName(AppLocalizations loc, RunZone zone) => switch (zone) {
  RunZone.z1 => loc.runInsightsZone1,
  RunZone.z2 => loc.runInsightsZone2,
  RunZone.z3 => loc.runInsightsZone3,
  RunZone.z4 => loc.runInsightsZone4,
  RunZone.z5 => loc.runInsightsZone5,
};

// ===================== FITNESS EVOLUTION =====================

/// VDOT per month as a line, one point for every month with data.
class RunVdotChart extends StatelessWidget {
  final List<RunVdotPoint> points;
  final String emptyLabel;
  final double height;

  const RunVdotChart({
    super.key,
    required this.points,
    required this.emptyLabel,
    this.height = RunChartStyle.height,
  });

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return RunChartEmpty(label: emptyLabel);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();

    final first = points.first.month;
    double xOf(DateTime month) =>
        ((month.year - first.year) * 12 + month.month - first.month).toDouble();
    final maxX = xOf(points.last.month);
    var minV = points.first.vdot;
    var maxV = points.first.vdot;
    for (final p in points) {
      minV = math.min(minV, p.vdot);
      maxV = math.max(maxV, p.vdot);
    }
    final pad = math.max(1.0, (maxV - minV) * 0.25);
    final minY = (minV - pad).floorToDouble();
    final maxY = (maxV + pad).ceilToDouble();
    final interval = math.max(1.0, ((maxY - minY) / 4).ceilToDouble());
    final tickEvery = math.max(1, (maxX / 4).ceil());

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: -0.3,
          maxX: maxX + 0.3,
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceContainerHighest,
              getTooltipItems: (touched) => [
                for (final t in touched)
                  LineTooltipItem(
                    '${DateFormat.yMMM(locale).format(points[t.spotIndex].month)}\n'
                    '${RunFormatters.decimal(points[t.spotIndex].vdot, 1)}',
                    RunChartStyle.tooltip(theme),
                  ),
              ],
            ),
          ),
          gridData: FlGridData(
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
                reservedSize: 32,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  if (value <= minY || value >= maxY) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      RunFormatters.decimal(value, 0),
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
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (value != i.toDouble() ||
                      i < 0 ||
                      i > maxX ||
                      (maxX - i) % tickEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  final month = DateTime(first.year, first.month + i);
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      DateFormat.MMM(locale).format(month),
                      style: RunChartStyle.axis(theme),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in points) FlSpot(xOf(p.month), p.vdot)],
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: colors.primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 3.5,
                      color: colors.primary,
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
                    colors.primary.withValues(alpha: 0.2),
                    colors.primary.withValues(alpha: 0.02),
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

// ===================== TRAINING LOAD =====================

/// Acute (7-day) against chronic (28-day) daily load.
class RunLoadChart extends StatelessWidget {
  final List<RunLoadDay> days;

  const RunLoadChart({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    if (days.length < 2) return const SizedBox.shrink();

    var maxV = 0.0;
    for (final d in days) {
      maxV = math.max(maxV, math.max(d.acute, d.chronic));
    }
    final maxY = math.max(10.0, maxV * 1.15);
    final interval = RunChartStyle.niceInterval(maxY);
    final acuteColor = colors.primary;
    final chronicColor = colors.tertiary;
    final tickEvery = math.max(7, (days.length / 5).ceil());

    LineChartBarData line(double Function(RunLoadDay) value, Color color) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < days.length; i++)
              FlSpot(i.toDouble(), value(days[i])),
          ],
          isCurved: true,
          curveSmoothness: 0.15,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 2.2,
          dotData: const FlDotData(show: false),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(loc.runInsightsLoadUnit),
        SizedBox(
          height: RunChartStyle.height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (days.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceContainerHighest,
                  getTooltipItems: (touched) => [
                    for (final t in touched)
                      LineTooltipItem(
                        t.barIndex == 0
                            ? '${DateFormat.MMMd(locale).format(days[t.spotIndex].date)}\n'
                                  '${loc.runInsightsLoadAcute}: '
                                  '${RunFormatters.decimal(t.y, 0)}'
                            : '${loc.runInsightsLoadChronic}: '
                                  '${RunFormatters.decimal(t.y, 0)}',
                        RunChartStyle.tooltip(theme),
                      ),
                  ],
                ),
              ),
              gridData: FlGridData(
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
                          RunFormatters.decimal(value, 0),
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
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (value != i.toDouble() ||
                          i < 0 ||
                          i >= days.length ||
                          (days.length - 1 - i) % tickEvery != 0) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          DateFormat.Md(locale).format(days[i].date),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                line((d) => d.acute, acuteColor),
                line((d) => d.chronic, chronicColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            RunLegendItem(color: acuteColor, label: loc.runInsightsLoadAcute),
            RunLegendItem(
              color: chronicColor,
              label: loc.runInsightsLoadChronic,
            ),
          ],
        ),
      ],
    );
  }
}

// ===================== INTENSITY =====================

/// Weekly time per pace zone as stacked bars (minutes).
class RunIntensityChart extends StatelessWidget {
  final List<RunWeekZones> weeks;

  const RunIntensityChart({super.key, required this.weeks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    var maxMinutes = 0.0;
    for (final w in weeks) {
      maxMinutes = math.max(maxMinutes, w.totalSeconds / 60);
    }
    final maxY = math.max(30.0, maxMinutes * 1.15);
    final interval = RunChartStyle.niceInterval(maxY);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RunChartUnit('min'),
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
                    final w = weeks[groupIndex];
                    final lines = [
                      loc.runStatsChartTooltipWeek(
                        DateFormat.MMMd(locale).format(w.weekStart),
                      ),
                      for (final zone in RunZone.values)
                        if (w.secondsPerZone[zone.index] > 0)
                          loc.runInsightsZoneMinutes(
                            zone.index + 1,
                            runZoneName(loc, zone),
                            (w.secondsPerZone[zone.index] / 60).round(),
                          ),
                    ];
                    return BarTooltipItem(
                      lines.join('\n'),
                      RunChartStyle.tooltip(theme),
                    );
                  },
                ),
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
                          RunFormatters.decimal(value, 0),
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
                      if (!RunChartStyle.showBucketTick(i, weeks.length)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          DateFormat.Md(locale).format(weeks[i].weekStart),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < weeks.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      () {
                        var from = 0.0;
                        final items = <BarChartRodStackItem>[];
                        for (final zone in RunZone.values) {
                          final minutes =
                              weeks[i].secondsPerZone[zone.index] / 60;
                          if (minutes <= 0) continue;
                          items.add(
                            BarChartRodStackItem(
                              from,
                              from + minutes,
                              runZoneColor(colors, zone),
                            ),
                          );
                          from += minutes;
                        }
                        return BarChartRodData(
                          toY: from,
                          width: RunChartStyle.barWidth(weeks.length),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          rodStackItems: items,
                          color: Colors.transparent,
                        );
                      }(),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===================== MONTHLY VOLUME =====================

/// Distance per month as bars (last twelve months or a whole year).
class RunMonthlyChart extends StatelessWidget {
  final List<RunMonthTotal> months;
  final String emptyLabel;

  const RunMonthlyChart({
    super.key,
    required this.months,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!months.any((m) => m.distanceMeters > 0)) {
      return RunChartEmpty(label: emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final maxKm = months
        .map((m) => m.distanceMeters / 1000)
        .fold<double>(0, math.max);
    final maxY = math.max(1.0, maxKm * 1.2);
    final interval = RunChartStyle.niceInterval(maxY);

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
                    final m = months[groupIndex];
                    return BarTooltipItem(
                      loc.runInsightsMonthTooltip(
                        DateFormat.yMMM(locale).format(m.month),
                        RunFormatters.distanceWithUnit(m.distanceMeters),
                        loc.runHomeWeekRunCount(m.runCount),
                      ),
                      RunChartStyle.tooltip(theme),
                    );
                  },
                ),
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
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }
                      final label = DateFormat.MMM(
                        locale,
                      ).format(months[i].month);
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          label.isEmpty
                              ? ''
                              : label.substring(0, 1).toUpperCase(),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: months[i].distanceMeters / 1000,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        color: i == months.length - 1
                            ? colors.primary
                            : colors.primary.withValues(alpha: 0.55),
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
      ],
    );
  }
}

/// Year-to-date cumulative distance, this year against last year.
class RunCumulativeChart extends StatelessWidget {
  final int year;
  final List<double?> thisYear;
  final List<double?> lastYear;

  const RunCumulativeChart({
    super.key,
    required this.year,
    required this.thisYear,
    required this.lastYear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    var maxKm = 0.0;
    for (final v in [...thisYear, ...lastYear]) {
      if (v != null) maxKm = math.max(maxKm, v / 1000);
    }
    final maxY = math.max(1.0, maxKm * 1.15);
    final interval = RunChartStyle.niceInterval(maxY);
    final currentColor = colors.primary;
    final previousColor = colors.onSurfaceVariant.withValues(alpha: 0.7);

    LineChartBarData line(
      List<double?> values,
      Color color, {
      bool dashed = false,
    }) {
      return LineChartBarData(
        spots: [
          for (var m = 0; m < values.length; m++)
            if (values[m] != null) FlSpot(m.toDouble(), values[m]! / 1000),
        ],
        isCurved: false,
        color: color,
        barWidth: dashed ? 1.8 : 2.6,
        dashArray: dashed ? const [5, 4] : null,
        dotData: FlDotData(show: !dashed),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(loc.runStatsChartUnitKm),
        SizedBox(
          height: RunChartStyle.height,
          child: LineChart(
            LineChartData(
              minX: -0.3,
              maxX: 11.3,
              minY: 0,
              maxY: maxY,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceContainerHighest,
                  getTooltipItems: (touched) => [
                    for (final t in touched)
                      LineTooltipItem(
                        '${t.barIndex == 0 ? year : year - 1} · '
                        '${DateFormat.MMM(locale).format(DateTime(year, t.x.round() + 1))}\n'
                        '${RunFormatters.decimal(t.y, 1)} km',
                        RunChartStyle.tooltip(theme),
                      ),
                  ],
                ),
              ),
              gridData: FlGridData(
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
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (value != i.toDouble() || i < 0 || i > 11) {
                        return const SizedBox.shrink();
                      }
                      final label = DateFormat.MMM(
                        locale,
                      ).format(DateTime(year, i + 1));
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          label.isEmpty
                              ? ''
                              : label.substring(0, 1).toUpperCase(),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                line(thisYear, currentColor),
                line(lastYear, previousColor, dashed: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          children: [
            RunLegendItem(color: currentColor, label: '$year'),
            RunLegendItem(
              color: previousColor,
              label: '${year - 1}',
              dashed: true,
            ),
          ],
        ),
      ],
    );
  }
}

// ===================== WEEKLY LINE (RPE / FEELING) =====================

/// Compact weekly line with an optional gap for weeks without data.
class RunWeeklyLineChart extends StatelessWidget {
  final List<DateTime> weeks;
  final List<double?> values;
  final double minY;
  final double maxY;
  final double interval;
  final Color color;
  final String Function(double value) format;

  const RunWeeklyLineChart({
    super.key,
    required this.weeks,
    required this.values,
    required this.minY,
    required this.maxY,
    required this.interval,
    required this.color,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    return SizedBox(
      height: 130,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (weeks.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceContainerHighest,
              getTooltipItems: (touched) => [
                for (final t in touched)
                  LineTooltipItem(
                    loc.runInsightsWeeklyAverageTooltip(
                      DateFormat.MMMd(locale).format(weeks[t.spotIndex]),
                      format(t.y),
                    ),
                    RunChartStyle.tooltip(theme),
                  ),
              ],
            ),
          ),
          gridData: FlGridData(
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
                reservedSize: 24,
                interval: interval,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    RunFormatters.decimal(value, 0),
                    style: RunChartStyle.axis(theme),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (value != i.toDouble() ||
                      !RunChartStyle.showBucketTick(
                        i,
                        weeks.length,
                        maxTicks: 4,
                      )) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      DateFormat.Md(locale).format(weeks[i]),
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
                for (var i = 0; i < values.length; i++)
                  values[i] == null
                      ? FlSpot.nullSpot
                      : FlSpot(i.toDouble(), values[i]!),
              ],
              isCurved: false,
              color: color,
              barWidth: 2.4,
              dotData: FlDotData(
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 3,
                      color: color,
                      strokeWidth: 1.2,
                      strokeColor: colors.surface,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
