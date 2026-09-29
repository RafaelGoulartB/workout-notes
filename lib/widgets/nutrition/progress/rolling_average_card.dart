import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/nutrition/progress/progress_shared.dart';

class RollingAverageCard extends StatelessWidget {
  final List<FlSpot> spots;
  final double? goal;
  final int windowDays;
  final DateTime startDate;

  const RollingAverageCard({
    super.key,
    required this.spots,
    required this.goal,
    required this.windowDays,
    required this.startDate,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasData = spots.isNotEmpty;
    final currentAvg = hasData ? spots.last.y : 0.0;
    final goalKcal = goal;
    final diff = (goalKcal != null && hasData) ? currentAvg - goalKcal : null;

    return ProgressSectionCard(
      icon: Icons.show_chart_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: loc.nutritionBalanceRollingTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasData)
            Row(
              children: [
                RollingStat(
                  label: loc.nutritionBalanceRollingCurrent,
                  value: '${currentAvg.round()} kcal',
                  color: diff == null
                      ? theme.colorScheme.onSurface
                      : diff < 0
                      ? kDeficitColor
                      : kSurplusColor,
                ),
                const SizedBox(width: 12),
                if (goalKcal != null)
                  RollingStat(
                    label: loc.nutritionBalanceGoalLabel,
                    value: '${goalKcal.round()} kcal',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 12),
                if (diff != null)
                  RollingStat(
                    label: loc.nutritionBalanceRollingDelta,
                    value: '${diff < 0 ? '' : '+'}${diff.round()} kcal',
                    color: diff < 0 ? kDeficitColor : kSurplusColor,
                  ),
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: hasData
                ? RollingLineChart(
                    spots: spots,
                    goal: goalKcal,
                    windowDays: windowDays,
                    startDate: startDate,
                  )
                : Center(
                    child: Text(
                      loc.nutritionBalanceRollingEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class RollingStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const RollingStat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class RollingLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final double? goal;
  final int windowDays;
  final DateTime startDate;

  const RollingLineChart({
    super.key,
    required this.spots,
    required this.goal,
    required this.windowDays,
    required this.startDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = spots.fold<double>(0, (acc, s) => s.y > acc ? s.y : acc);
    final chartMax = (maxY > (goal ?? 0) ? maxY : (goal ?? 0)) * 1.2;
    final safeMax = chartMax <= 0 ? 1000.0 : chartMax;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: safeMax,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItems: (spots) => spots.map((spot) {
              return LineTooltipItem(
                '${spot.y.round()} kcal',
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              );
            }).toList(),
          ),
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
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                return Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.round().toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: windowDays <= 7 ? 3 : 7,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                final isEdge = idx == 0 || idx == windowDays - 1;
                final isInterval = windowDays > 7 && idx % 7 == 0;
                if (!isEdge && !isInterval) {
                  return const SizedBox.shrink();
                }
                final date = startDate.add(Duration(days: idx));
                final label = DateFormat.Md(Intl.defaultLocale).format(date);
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
          drawVerticalLine: false,
          horizontalInterval: safeMax / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
            strokeWidth: 1,
            dashArray: const [3, 4],
          ),
        ),
        extraLinesData: goal == null
            ? const ExtraLinesData()
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: goal!,
                    color: theme.colorScheme.primary.withAlpha(180),
                    strokeWidth: 1.4,
                    dashArray: const [6, 4],
                  ),
                ],
              ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            barWidth: 2.6,
            color: theme.colorScheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withAlpha(70),
                  theme.colorScheme.primary.withAlpha(10),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }
}
