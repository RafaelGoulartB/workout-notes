import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
import 'package:workout_notes/screens/workout/body_tracker_screen.dart';

/// Displays body measurement section: summary grid, composition chart,
/// weight-vs-volume chart, and link to body tracker.
class BodySectionCharts extends StatelessWidget {
  final List<Map<String, dynamic>> bodySummary;
  final List<Map<String, dynamic>> bodyComposition;
  final List<Map<String, dynamic>> bodyData;

  const BodySectionCharts({
    super.key,
    required this.bodySummary,
    required this.bodyComposition,
    required this.bodyData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // === Summary cards grid ===
        if (bodySummary.isNotEmpty) ...[
          _BodySummaryGrid(
            bodySummary: bodySummary,
            bodyComposition: bodyComposition,
          ),
          const SizedBox(height: 16),
        ],

        // === Body composition chart ===
        if (bodyComposition.isNotEmpty && bodyComposition.length >= 2) ...[
          Text(
            loc.progressBodyComposition,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _BodyCompositionChart(data: bodyComposition),
          const SizedBox(height: 16),
        ],

        // === Weight vs Volume chart ===
        if (bodyData.isNotEmpty) ...[
          Text(
            loc.progressBodyWeightVsVolume,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _BodyWeightChart(data: bodyData),
        ],

        // === Body measurements link ===
        const SizedBox(height: 12),
        _BodyTrackerLink(),
      ],
    );
  }
}

/// Grid of body measurement summary cards.
class _BodySummaryGrid extends StatelessWidget {
  final List<Map<String, dynamic>> bodySummary;
  final List<Map<String, dynamic>> bodyComposition;

  const _BodySummaryGrid({
    required this.bodySummary,
    required this.bodyComposition,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final types = [
      {
        'id': 'weight',
        'name': loc.bodyTrackerWeight,
        'unit': 'kg',
        'color': Colors.indigo,
        'icon': Icons.monitor_weight
      },
      {
        'id': 'bodyFat',
        'name': loc.bodyTrackerBodyFat,
        'unit': '%',
        'color': Colors.orange,
        'icon': Icons.water_drop
      },
      {
        'id': 'waist',
        'name': loc.bodyTrackerWaist,
        'unit': 'cm',
        'color': Colors.teal,
        'icon': Icons.straighten
      },
      {
        'id': 'chest',
        'name': loc.bodyTrackerChest,
        'unit': 'cm',
        'color': Colors.blue,
        'icon': Icons.straighten
      },
      {
        'id': 'arm',
        'name': loc.bodyTrackerArm,
        'unit': 'cm',
        'color': Colors.purple,
        'icon': Icons.straighten
      },
      {
        'id': 'hip',
        'name': loc.bodyTrackerHip,
        'unit': 'cm',
        'color': Colors.cyan,
        'icon': Icons.straighten
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: types.length,
      itemBuilder: (ctx, i) {
        final t = types[i];
        final typeId = t['id'] as String;
        final color = t['color'] as Color;
        final icon = t['icon'] as IconData;
        final unit = t['unit'] as String;

        Map<String, dynamic>? latest;
        Map<String, dynamic>? previous;
        try {
          latest = bodySummary.firstWhere((s) => s['type'] == typeId);
        } catch (_) {}

        if (latest != null && bodyComposition.isNotEmpty) {
          final latestDate = latest['date'] as String? ?? '';
          for (final bc in bodyComposition) {
            final bcDate = bc['date'] as String? ?? '';
            if (bcDate.compareTo(latestDate) < 0) {
              previous = bc;
              break;
            }
          }
        }

        final currentValue =
            latest != null ? (latest['value'] as num?)?.toDouble() : null;
        final prevValue =
            previous != null ? (previous[typeId] as num?)?.toDouble() : null;

        double? delta;
        if (currentValue != null &&
            prevValue != null &&
            prevValue > 0) {
          delta = currentValue - prevValue;
        }

        return Card(
          elevation: 0,
          color: color.withAlpha(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withAlpha(40)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 4),
                Text(
                  currentValue != null
                      ? '${currentValue.toStringAsFixed(1)}${delta != null && delta != 0 ? " ${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}$unit" : ""}'
                      : '--',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: currentValue != null
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  t['name'] as String,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Body composition multi-line chart (weight, body fat, waist, chest).
class _BodyCompositionChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _BodyCompositionChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final bodyFats = data
        .map((d) => (d['body_fat'] as num?)?.toDouble())
        .where((v) => v != null && v > 0)
        .toList();
    final waists = data
        .map((d) => (d['waist'] as num?)?.toDouble())
        .where((v) => v != null && v > 0)
        .toList();
    final chests = data
        .map((d) => (d['chest'] as num?)?.toDouble())
        .where((v) => v != null && v > 0)
        .toList();

    final validData = data.where((d) {
      final w = (d['weight'] as num?)?.toDouble() ?? 0;
      return w > 0;
    }).toList();

    if (validData.length < 2) return const SizedBox.shrink();

    final maxWeight = validData
        .map((d) => (d['weight'] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendDot(Colors.indigo, loc.bodyTrackerWeight),
                if (bodyFats.isNotEmpty)
                  _legendDot(Colors.orange, loc.bodyTrackerBodyFat),
                if (waists.isNotEmpty)
                  _legendDot(Colors.teal, loc.bodyTrackerWaist),
                if (chests.isNotEmpty)
                  _legendDot(Colors.blue, loc.bodyTrackerChest),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxWeight * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        niceInterval(maxWeight / 4),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(
                          v > 100
                              ? '${(v / 1000).toStringAsFixed(0)}k'
                              : v.toStringAsFixed(0),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        interval: validData.length > 8
                            ? 2
                            : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 ||
                              idx >= validData.length) {
                            return const SizedBox.shrink();
                          }
                          final d = validData[idx]['date']
                                  as String? ??
                              '';
                          return Text(
                            d.length >= 10
                                ? d.substring(5)
                                : d,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 7),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // Weight
                    LineChartBarData(
                      spots: validData.asMap().entries.map((e) {
                        final w =
                            (e.value['weight'] as num?)?.toDouble() ?? 0;
                        return FlSpot(
                            e.key.toDouble(), w);
                      }).toList(),
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (s, p, b, i) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: Colors.indigo,
                        ),
                      ),
                      belowBarData:
                          BarAreaData(show: false),
                    ),
                    // Body fat
                    if (bodyFats.length >= 2)
                      LineChartBarData(
                        spots: validData
                            .asMap()
                            .entries
                            .map((e) {
                          final bf = (e.value['body_fat']
                                  as num?)
                              ?.toDouble();
                          return FlSpot(e.key.toDouble(),
                              bf ?? 0);
                        }).where((s) => s.y > 0).toList(),
                        isCurved: true,
                        color: Colors.orange,
                        barWidth: 2,
                        dashArray: [6, 3],
                        dotData:
                            FlDotData(show: false),
                        belowBarData:
                            BarAreaData(show: false),
                      ),
                    // Waist
                    if (waists.length >= 2)
                      LineChartBarData(
                        spots: validData
                            .asMap()
                            .entries
                            .map((e) {
                          final w =
                              (e.value['waist'] as num?)
                                  ?.toDouble();
                          return FlSpot(e.key.toDouble(),
                              w ?? 0);
                        }).where((s) => s.y > 0).toList(),
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 2,
                        dashArray: [3, 3],
                        dotData:
                            FlDotData(show: false),
                        belowBarData:
                            BarAreaData(show: false),
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData:
                        LineTouchTooltipData(
                      getTooltipItems: (spots) =>
                          spots.map((s) {
                        final idx = s.spotIndex;
                        final d = idx < validData.length
                            ? (validData[idx]['date']
                                    as String? ??
                                '')
                            : '';
                        String label;
                        if (s.barIndex == 0) {
                          label =
                              '${loc.bodyTrackerWeight}: ${s.y.toStringAsFixed(1)}kg';
                        } else if (s.barIndex == 1) {
                          label =
                              '${loc.bodyTrackerBodyFat}: ${s.y.toStringAsFixed(1)}%';
                        } else {
                          label =
                              '${loc.bodyTrackerWaist}: ${s.y.toStringAsFixed(1)}cm';
                        }
                        return LineTooltipItem(
                          '$d\n$label',
                          TextStyle(
                            color: theme
                                .colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10)),
      ],
    );
  }
}

/// Weight vs Volume dual-line chart.
class _BodyWeightChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _BodyWeightChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (data.isEmpty) return const SizedBox.shrink();

    final weights = data
        .map((d) => (d['weight'] as num?)?.toDouble() ?? 0)
        .toList();
    final volumes = data
        .map((d) => (d['volume'] as num?)?.toDouble() ?? 0)
        .toList();
    final maxWeight =
        weights.fold<double>(0, (a, b) => a > b ? a : b);
    final maxVolume =
        volumes.fold<double>(0, (a, b) => a > b ? a : b);

    if (maxWeight <= 0) return const SizedBox.shrink();

    final maxY =
        maxWeight > maxVolume ? maxWeight * 1.15 : maxVolume * 1.15;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _legendDot(Colors.indigo, loc.progressBodyWeight),
                const SizedBox(width: 16),
                _legendDot(Colors.teal, loc.commonVolume),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: niceInterval(
                        (maxWeight > maxVolume
                                ? maxWeight
                                : maxVolume) /
                            4),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(
                          v > 100
                              ? '${(v / 1000).toStringAsFixed(0)}k'
                              : v.toStringAsFixed(0),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 20,
                        interval: data.length > 8
                            ? 2
                            : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 ||
                              idx >= data.length) {
                            return const SizedBox.shrink();
                          }
                          final d = data[idx]['date']
                                  as String? ??
                              '';
                          return Text(
                            d.length >= 10
                                ? d.substring(5)
                                : d,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 7),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles:
                            SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // Weight line
                    LineChartBarData(
                      spots: weights
                          .asMap()
                          .entries
                          .map((e) => FlSpot(
                              e.key.toDouble(), e.value))
                          .toList(),
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (s, p, b, i) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: Colors.indigo,
                        ),
                      ),
                      belowBarData:
                          BarAreaData(show: false),
                    ),
                    // Volume line
                    if (maxVolume > 0)
                      LineChartBarData(
                        spots: volumes
                            .asMap()
                            .entries
                            .map((e) => FlSpot(e.key
                                .toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 2,
                        dashArray: [6, 3],
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (s, p, b, i) =>
                              FlDotCirclePainter(
                            radius: 3,
                            color: Colors.teal,
                          ),
                        ),
                        belowBarData:
                            BarAreaData(show: false),
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData:
                        LineTouchTooltipData(
                      getTooltipItems: (spots) =>
                          spots.map((s) {
                        final idx = s.spotIndex;
                        final d = idx < data.length
                            ? (data[idx]['date']
                                    as String? ??
                                '')
                            : '';
                        final isWeight =
                            s.barIndex == 0;
                        return LineTooltipItem(
                          '$d\n${isWeight ? '${loc.progressBodyWeight}: ${s.y.toStringAsFixed(1)}${loc.workoutDetailKg}' : '${loc.commonVolume}: ${formatVolume(s.y)}'}',
                          TextStyle(
                            color: theme
                                .colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10)),
      ],
    );
  }
}

/// Card linking to the Body Tracker full screen.
class _BodyTrackerLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BodyTrackerScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.accessibility_new,
                    size: 20, color: Colors.indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.progressBodyMeasurements,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(
                              fontWeight:
                                  FontWeight.w600),
                    ),
                    Text(
                      loc.progressBodyMeasurementsSubtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(
                        color: theme
                            .colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
