import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/utils/pace_calculator.dart';
import 'package:workout_notes/utils/progress_helpers.dart';

/// Cardio section header — displayed above the charts.
class CardioHeader extends StatelessWidget {
  final double totalDistance;
  final double? avgPaceSeconds;
  final int totalTimeSeconds;
  final int sessionCount;

  const CardioHeader({
    super.key,
    required this.totalDistance,
    this.avgPaceSeconds,
    required this.totalTimeSeconds,
    required this.sessionCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final cardioColor = const Color(0xFFE53935);

    final timeStr = totalTimeSeconds >= 3600
        ? '${totalTimeSeconds ~/ 3600}h${(totalTimeSeconds % 3600) ~/ 60}min'
        : '${totalTimeSeconds ~/ 60}min';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cardioColor.withAlpha(30), cardioColor.withAlpha(10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardioColor.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cardioColor.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.directions_run, color: cardioColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.progressCardio,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cardioColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.progressCardioTotal(
                    PaceCalculator.formatDistance(totalDistance, isMile: false),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (avgPaceSeconds != null && avgPaceSeconds! > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    loc.progressCardioAvgPace(
                      PaceCalculator.formatPace(avgPaceSeconds),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cardioColor,
                ),
              ),
              Text(
                '$sessionCount ${loc.progressWorkouts.toLowerCase()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bar chart showing distance per week (last 12 weeks).
class WeeklyDistanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const WeeklyDistanceChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final cardioColor = const Color(0xFFE53935);

    if (data.isEmpty) return const SizedBox.shrink();

    final Map<String, double> weeklyTotals = {};
    for (final row in data) {
      final date = row['date'] as String? ?? '';
      final dist = (row['distance'] as num?)?.toDouble() ?? 0;
      if (date.length >= 10) {
        try {
          final dt = DateTime.parse(date);
          final weekKey = dt
              .subtract(Duration(days: dt.weekday - 1))
              .toIso8601String()
              .substring(0, 10);
          weeklyTotals.update(weekKey, (v) => v + dist, ifAbsent: () => dist);
        } catch (_) {}
      }
    }

    if (weeklyTotals.isEmpty) return const SizedBox.shrink();

    final sortedWeeks = weeklyTotals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final distances = sortedWeeks.map((e) => e.value).toList();
    final maxDist = distances.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxDist <= 0) return const SizedBox.shrink();

    // Show only last 12
    final display = sortedWeeks.length > 12
        ? sortedWeeks.sublist(sortedWeeks.length - 12)
        : sortedWeeks;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, size: 18, color: cardioColor),
                const SizedBox(width: 6),
                Text(
                  loc.progressCardioWeekly,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxDist * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        if (groupIndex >= display.length) return null;
                        final e = display[groupIndex];
                        return BarTooltipItem(
                          '${e.key.substring(5)}\n${PaceCalculator.formatDistance(e.value)}',
                          TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= display.length)
                            return const SizedBox.shrink();
                          final key = display[idx].key;
                          final parts = key.split('-');
                          if (parts.length < 3) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${parts[2]}/${parts[1]}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) {
                          if (v == 0) return const SizedBox.shrink();
                          return Text(
                            '${v.toInt()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
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
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxDist > 0
                        ? niceInterval(maxDist / 4)
                        : 1,
                  ),
                  barGroups: display.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final e = entry.value;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: cardioColor,
                          width: 14,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pie chart showing distance distribution by modality (running, cycling, etc.).
class DistanceByModalityChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const DistanceByModalityChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final valid = data
        .where((d) => ((d['total_distance'] as num?)?.toDouble() ?? 0) > 0)
        .toList();
    if (valid.isEmpty) return const SizedBox.shrink();

    final totalDist = valid.fold<double>(
      0,
      (sum, d) => sum + ((d['total_distance'] as num?)?.toDouble() ?? 0),
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pie_chart,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  loc.progressCardioByModality,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: valid.asMap().entries.map((entry) {
                          final d = entry.value;
                          final dist =
                              (d['total_distance'] as num?)?.toDouble() ?? 0;
                          final pct = totalDist > 0 ? dist / totalDist : 0.0;
                          final color = Color(
                            d['modality_color'] as int? ?? 0xFFE53935,
                          );
                          return PieChartSectionData(
                            value: dist,
                            color: color,
                            radius: 35,
                            title: '${(pct * 100).toStringAsFixed(0)}%',
                            titleStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: valid.map((d) {
                        final dist =
                            (d['total_distance'] as num?)?.toDouble() ?? 0;
                        final color = Color(
                          d['modality_color'] as int? ?? 0xFFE53935,
                        );
                        final name = ExerciseLocaleHelper.categoryNameFromId(
                          AppLocalizations.of(context)!,
                          d['id'] as String? ?? '',
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name.isNotEmpty
                                      ? name
                                      : (d['modality'] as String? ?? ''),
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                PaceCalculator.formatDistance(dist),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pace trend line chart for a selected cardio exercise.
class PaceTrendChart extends StatefulWidget {
  final List<Map<String, dynamic>> paceData;
  final bool isLoading;
  final String? selectedExerciseName;

  const PaceTrendChart({
    super.key,
    required this.paceData,
    this.isLoading = false,
    this.selectedExerciseName,
  });

  @override
  State<PaceTrendChart> createState() => _PaceTrendChartState();
}

class _PaceTrendChartState extends State<PaceTrendChart> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, size: 18, color: Colors.deepOrange),
                const SizedBox(width: 6),
                Text(
                  loc.progressCardioPace,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.isLoading)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (widget.paceData.isEmpty ||
                widget.selectedExerciseName == null)
              SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    loc.progressSelectExercise,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              _buildChart(theme, loc),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(ThemeData theme, AppLocalizations loc) {
    final paces = <double>[];
    final labels = <String>[];

    for (final row in widget.paceData) {
      final dist = (row['total_distance'] as num?)?.toDouble() ?? 0;
      final time = (row['total_time'] as int?) ?? 0;
      if (dist > 0 && time > 0) {
        final pace = time / dist;
        paces.add(pace);
        final date = (row['date'] as String? ?? '');
        labels.add(date.length >= 10 ? date.substring(5) : date);
      }
    }

    if (paces.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            loc.progressNoChartData,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final maxPace = paces.reduce((a, b) => a > b ? a : b);
    final minPace = paces.reduce((a, b) => a < b ? a : b);
    final range = (maxPace - minPace).clamp(5.0, double.infinity);

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minY: (minPace - range * 0.1).clamp(0, double.infinity),
          maxY: maxPace + range * 0.1,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((spot) {
                final pace = spot.y;
                final idx = spot.x.toInt();
                return LineTooltipItem(
                  '${idx >= 0 && idx < labels.length ? labels[idx] : ''}\n${PaceCalculator.formatPace(pace)}',
                  TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range > 0 ? niceInterval(range / 4) : 30,
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (paces.length / 5).ceilToDouble().clamp(
                  1,
                  double.infinity,
                ),
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= labels.length)
                    return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      labels[idx],
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) {
                  if (v <= 0) return const SizedBox.shrink();
                  return Text(
                    PaceCalculator.formatPace(v),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
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
              spots: paces
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                  .toList(),
              isCurved: true,
              color: const Color(0xFFE53935),
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 3,
                      color: const Color(0xFFE53935),
                      strokeWidth: 1,
                      strokeColor: Colors.white,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFFE53935).withAlpha(25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List of cardio personal records.
class CardioPRsCard extends StatelessWidget {
  final List<Map<String, dynamic>> prs;
  final bool isLoading;

  const CardioPRsCard({super.key, required this.prs, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final cardioColor = const Color(0xFFE53935);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events,
                  size: 18,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  loc.progressCardioPRs,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isLoading)
              const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (prs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  loc.progressCardioNoData,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...prs.take(10).map((pr) {
                final name = pr['exercise_name'] as String? ?? '';
                final bestDist = (pr['best_distance'] as num?)?.toDouble() ?? 0;
                final bestTime = (pr['best_time'] as int?) ?? 0;
                final bestPace = (pr['best_pace'] as num?)?.toDouble();
                final modalityColor = Color(
                  pr['modality_color'] as int? ?? 0xFFE53935,
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cardioColor.withAlpha(12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions_run,
                        size: 16,
                        color: modalityColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${loc.cardioLongestDistance}: ${PaceCalculator.formatDistance(bestDist)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (bestTime > 0)
                              Text(
                                '${loc.cardioLongestDuration}: ${bestTime >= 3600 ? "${bestTime ~/ 3600}h${(bestTime % 3600) ~/ 60}min" : "${bestTime ~/ 60}min"}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (bestPace != null && bestPace > 0)
                              Text(
                                '${loc.cardioBestPace}: ${PaceCalculator.formatPace(bestPace)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
