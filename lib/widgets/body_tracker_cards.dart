import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/body_tracker_badges.dart';

// ═══════════════════════════════════════════════════════════════════════
// SPARKLINE (mini chart in summary card)
// ═══════════════════════════════════════════════════════════════════════

/// A small sparkline chart shown in the summary card header.
class BodySparkline extends StatelessWidget {
  final List<Map<String, dynamic>> measurements;
  final Color lineColor;

  const BodySparkline({
    super.key,
    required this.measurements,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final reversed = measurements.reversed.toList();
    final values =
        reversed.map((m) => (m['value'] as num).toDouble()).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    return LineChart(
      LineChartData(
        minY: minVal - range * 0.1,
        maxY: maxVal + range * 0.1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: values.asMap().entries
                .map((e) => FlSpot(e.key.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: lineColor.withAlpha(180),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withAlpha(50),
                  lineColor.withAlpha(0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUMMARY CARD (hero card with current value + sparkline)
// ═══════════════════════════════════════════════════════════════════════

/// Hero card showing the current value, delta, and sparkline.
class BodySummaryCard extends StatelessWidget {
  final MeasureType type;
  final double? value;
  final double? delta;
  final bool isDecreasingGood;
  final List<Map<String, dynamic>> measurements;

  const BodySummaryCard({
    super.key,
    required this.type,
    required this.value,
    required this.delta,
    required this.isDecreasingGood,
    required this.measurements,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localDelta = delta;

    final isGood = isDecreasingGood
        ? (localDelta != null && localDelta < 0)
        : (localDelta != null && localDelta > 0);
    final isBad = isDecreasingGood
        ? (localDelta != null && localDelta > 0)
        : (localDelta != null && localDelta < 0);
    final deltaColor = delta == null
        ? Colors.transparent
        : (isGood
            ? Colors.green
            : isBad
                ? Colors.red
                : theme.colorScheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: type.color.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(type.icon, size: 18, color: type.color),
                ),
                const SizedBox(width: 10),
                Text(
                  typeName(type.id, context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (delta != null && delta != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: deltaColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: deltaColor.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta! > 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 14,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${delta! > 0 ? '+' : ''}${delta!.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: deltaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Big value
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value != null ? value!.toStringAsFixed(1) : '--',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -2,
                    fontSize: 42,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      type.unit,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Sparkline
            if (measurements.length >= 3) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: BodySparkline(
                  measurements: measurements,
                  lineColor: type.color,
                ),
              ),
            ],

            // Last measurement info
            if (value != null && measurements.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant
                        .withAlpha(140),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatDate(
                        measurements.first['date'] as String? ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withAlpha(160),
                      fontSize: 11,
                    ),
                  ),
                  if ((measurements.first['time_of_day']
                          as String?)
                          ?.isNotEmpty ==
                      true) ...[
                    const SizedBox(width: 8),
                    TimeOfDayBadge(
                        tod: measurements.first['time_of_day']
                            as String),
                  ],
                  if ((measurements.first['is_fasted'] as int?) == 1) ...[
                    const SizedBox(width: 8),
                    const FastedBadge(),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// QUICK STATS ROW
// ═══════════════════════════════════════════════════════════════════════

/// Row of mini stat cards (min, max, average, total count).
class BodyQuickStats extends StatelessWidget {
  final double? minValue;
  final double? maxValue;
  final double? avgValue;
  final int totalCount;
  final Color typeColor;

  const BodyQuickStats({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.avgValue,
    required this.totalCount,
    required this.typeColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final statItems = [
      (loc.bodyTrackerMin, minValue?.toStringAsFixed(1) ?? '--',
          Icons.trending_down, Colors.blueGrey),
      (loc.bodyTrackerMax, maxValue?.toStringAsFixed(1) ?? '--',
          Icons.trending_up, typeColor),
      (loc.bodyTrackerAverage, avgValue?.toStringAsFixed(1) ?? '--',
          Icons.show_chart, typeColor.withAlpha(200)),
      (loc.bodyTrackerEntries, '$totalCount', Icons.receipt_long,
          theme.colorScheme.secondary),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: statItems.map((s) {
          final (label, value, icon, color) = s;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withAlpha(50),
                ),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 14, color: color.withAlpha(200)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BILATERAL SUMMARY CARD (side-by-side L/R values)
// ═══════════════════════════════════════════════════════════════════════

/// Hero card showing current values for both left and right sides.
class BodyBilateralSummaryCard extends StatelessWidget {
  final MeasureType type;
  final double? leftValue;
  final double? rightValue;
  final double? leftDelta;
  final double? rightDelta;
  final bool isDecreasingGood;
  final List<Map<String, dynamic>> leftMeasurements;
  final List<Map<String, dynamic>> rightMeasurements;

  const BodyBilateralSummaryCard({
    super.key,
    required this.type,
    required this.leftValue,
    required this.rightValue,
    required this.leftDelta,
    required this.rightDelta,
    required this.isDecreasingGood,
    required this.leftMeasurements,
    required this.rightMeasurements,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: type.color.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(type.icon, size: 18, color: type.color),
                ),
                const SizedBox(width: 10),
                Text(
                  typeName(type.id, context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Left / Right side-by-side
            Row(
              children: [
                Expanded(
                  child: _BilateralSidePanel(
                    theme: theme,
                    sideLabel: AppLocalizations.of(context)!.bodyTrackerLeft,
                    sideAbbr: 'L',
                    value: leftValue,
                    delta: leftDelta,
                    unit: type.unit,
                    isDecreasingGood: isDecreasingGood,
                    color: Colors.blue,
                    measurements: leftMeasurements,
                    icon: Icons.arrow_back,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BilateralSidePanel(
                    theme: theme,
                    sideLabel: AppLocalizations.of(context)!.bodyTrackerRight,
                    sideAbbr: 'R',
                    value: rightValue,
                    delta: rightDelta,
                    unit: type.unit,
                    isDecreasingGood: isDecreasingGood,
                    color: Colors.red,
                    measurements: rightMeasurements,
                    icon: Icons.arrow_forward,
                  ),
                ),
              ],
            ),

            // Asymmetry indicator
            if (leftValue != null && rightValue != null) ...[
              const SizedBox(height: 12),
              _AsymmetryIndicator(
                theme: theme,
                leftValue: leftValue!,
                rightValue: rightValue!,
                unit: type.unit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Panel showing one side's value in the bilateral summary card.
class _BilateralSidePanel extends StatelessWidget {
  final ThemeData theme;
  final String sideLabel;
  final String sideAbbr;
  final double? value;
  final double? delta;
  final String unit;
  final bool isDecreasingGood;
  final Color color;
  final List<Map<String, dynamic>> measurements;
  final IconData icon;

  const _BilateralSidePanel({
    required this.theme,
    required this.sideLabel,
    required this.sideAbbr,
    required this.value,
    required this.delta,
    required this.unit,
    required this.isDecreasingGood,
    required this.color,
    required this.measurements,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isGood = delta != null
        ? (isDecreasingGood ? delta! < 0 : delta! > 0)
        : null;
    final deltaColor = delta == null
        ? Colors.transparent
        : (isGood == true
            ? Colors.green
            : (isGood == false ? Colors.red : theme.colorScheme.onSurfaceVariant));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withAlpha(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Side header
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                sideLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Value + unit
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value != null ? value!.toStringAsFixed(1) : '--',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                  color: theme.colorScheme.onSurface,
                  fontSize: 32,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Delta
          if (delta != null && delta != 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  delta! > 0 ? Icons.trending_up : Icons.trending_down,
                  size: 14,
                  color: deltaColor,
                ),
                const SizedBox(width: 2),
                Text(
                  '${delta! > 0 ? '+' : ''}${delta!.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: deltaColor,
                  ),
                ),
              ],
            ),
          ],

          // Latest date
          if (measurements.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              formatDate(measurements.first['date'] as String? ?? ''),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the difference between left and right, highlighting asymmetry.
class _AsymmetryIndicator extends StatelessWidget {
  final ThemeData theme;
  final double leftValue;
  final double rightValue;
  final String unit;

  const _AsymmetryIndicator({
    required this.theme,
    required this.leftValue,
    required this.rightValue,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final diff = (leftValue - rightValue).abs();
    final larger = leftValue > rightValue ? 'L' : 'R';
    final loc = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
      ),
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            loc.bodyTrackerAsymmetry(diff.toStringAsFixed(1), larger, unit),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CHART CARD (full line chart)
// ═══════════════════════════════════════════════════════════════════════

/// Full-size trend chart for the selected measurement type.
class BodyChartCard extends StatelessWidget {
  final List<Map<String, dynamic>> measurements;
  final MeasureType type;

  const BodyChartCard({
    super.key,
    required this.measurements,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final reversed = measurements.reversed.toList();
    final values =
        reversed.map((m) => (m['value'] as num).toDouble()).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  loc.bodyTrackerTrendLine,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: minVal - range * 0.15,
                    maxY: maxVal + range * 0.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval:
                          range > 0 ? niceInterval(range / 4) : 1,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: theme.colorScheme.outlineVariant
                            .withAlpha(40),
                        strokeWidth: 0.5,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(v >= 100 ? 0 : 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: reversed.length > 10 ? 2 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= reversed.length) {
                              return const SizedBox.shrink();
                            }
                            final d = reversed[idx]['date'] as String? ?? '';
                            return Text(
                              d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 8,
                                color:
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: values.asMap().entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: type.color,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: values.length <= 25,
                          getDotPainter: (s, p, b, i) =>
                              FlDotCirclePainter(
                            radius: 3,
                            color: type.color,
                            strokeWidth: 1.5,
                            strokeColor: theme.colorScheme.surface,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              type.color.withAlpha(40),
                              type.color.withAlpha(5),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final idx = s.spotIndex;
                          final d = idx < reversed.length
                              ? formatDate(
                                  reversed[idx]['date'] as String? ?? '')
                              : '';
                          return LineTooltipItem(
                            '$d\n${s.y.toStringAsFixed(1)} ${type.unit}',
                            TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BILATERAL CHART CARD (two lines for L/R comparison)
// ═══════════════════════════════════════════════════════════════════════

/// Chart showing both left and right trends overlaid for comparison.
class BodyBilateralChartCard extends StatelessWidget {
  final List<Map<String, dynamic>> leftMeasurements;
  final List<Map<String, dynamic>> rightMeasurements;
  final MeasureType type;

  const BodyBilateralChartCard({
    super.key,
    required this.leftMeasurements,
    required this.rightMeasurements,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final leftReversed = leftMeasurements.reversed.toList();
    final rightReversed = rightMeasurements.reversed.toList();
    final allValues = [
      ...leftReversed.map((m) => (m['value'] as num).toDouble()),
      ...rightReversed.map((m) => (m['value'] as num).toDouble()),
    ];

    if (allValues.isEmpty) return const SizedBox.shrink();

    final minVal = allValues.reduce((a, b) => a < b ? a : b);
    final maxVal = allValues.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    // Build spots aligned by index; if counts differ, pad with null
    // We align by date instead of index for accuracy
    final allDates = <String>{};
    for (final m in leftReversed) {
      allDates.add(m['date'] as String);
    }
    for (final m in rightReversed) {
      allDates.add(m['date'] as String);
    }
    final sortedDates = allDates.toList()..sort();

    final leftSpots = <FlSpot>[];
    final rightSpots = <FlSpot>[];
    final dateIndexMap = <String, int>{};
    for (int i = 0; i < sortedDates.length; i++) {
      dateIndexMap[sortedDates[i]] = i;
    }
    for (final m in leftReversed) {
      final idx = dateIndexMap[m['date'] as String] ?? 0;
      leftSpots.add(FlSpot(idx.toDouble(), (m['value'] as num).toDouble()));
    }
    for (final m in rightReversed) {
      final idx = dateIndexMap[m['date'] as String] ?? 0;
      rightSpots.add(FlSpot(idx.toDouble(), (m['value'] as num).toDouble()));
    }

    // Legend item
    Widget legendItem(Color color, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Text(
                      loc.bodyTrackerTrendComparison,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    legendItem(Colors.blue, loc.bodyTrackerLeft),
                    const SizedBox(width: 12),
                    legendItem(Colors.red, loc.bodyTrackerRight),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: minVal - range * 0.15,
                    maxY: maxVal + range * 0.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval:
                          range > 0 ? niceInterval(range / 4) : 1,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: theme.colorScheme.outlineVariant.withAlpha(40),
                        strokeWidth: 0.5,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(v >= 100 ? 0 : 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: sortedDates.length > 10 ? 2 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= sortedDates.length) {
                              return const SizedBox.shrink();
                            }
                            final d = sortedDates[idx];
                            return Text(
                              d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 8,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      // Left line
                      LineChartBarData(
                        spots: leftSpots,
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: leftSpots.length <= 25,
                          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                            radius: 3,
                            color: Colors.blue,
                            strokeWidth: 1.5,
                            strokeColor: theme.colorScheme.surface,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.withAlpha(30),
                              Colors.blue.withAlpha(3),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      // Right line
                      LineChartBarData(
                        spots: rightSpots,
                        isCurved: true,
                        color: Colors.red,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: rightSpots.length <= 25,
                          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                            radius: 3,
                            color: Colors.red,
                            strokeWidth: 1.5,
                            strokeColor: theme.colorScheme.surface,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.withAlpha(30),
                              Colors.red.withAlpha(3),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final idx = s.spotIndex;
                          final date = idx < sortedDates.length
                              ? formatDate(sortedDates[idx])
                              : '';
                          final isLeft = s.barIndex == 0;
                          return LineTooltipItem(
                            '${isLeft ? "L" : "R"} · $date\n${s.y.toStringAsFixed(1)} ${type.unit}',
                            TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DERIVED STATS CARD (body composition estimates)
// ═══════════════════════════════════════════════════════════════════════

/// Card showing estimated body composition (lean mass, fat mass, WHR).
class BodyDerivedStatsCard extends StatelessWidget {
  final double weight;
  final Map<String, Map<String, dynamic>?> latestByType;

  const BodyDerivedStatsCard({
    super.key,
    required this.weight,
    required this.latestByType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final bodyFatLatest = latestByType['bodyFat'];
    final bodyFatVal = bodyFatLatest != null
        ? (bodyFatLatest['value'] as num?)?.toDouble()
        : null;
    final waistLatest = latestByType['waist'];
    final hipLatest = latestByType['hip'];
    final waistVal = waistLatest != null
        ? (waistLatest['value'] as num?)?.toDouble()
        : null;
    final hipVal = hipLatest != null
        ? (hipLatest['value'] as num?)?.toDouble()
        : null;
    final whr = (waistVal != null && hipVal != null && hipVal > 0)
        ? waistVal / hipVal
        : null;
    final leanMass =
        (bodyFatVal != null) ? weight * (1 - bodyFatVal / 100) : null;
    final fatMass =
        (bodyFatVal != null) ? weight * (bodyFatVal / 100) : null;

    final stats = <DerivedStat>[];
    if (leanMass != null) {
      stats.add(DerivedStat(
        loc.bodyTrackerLeanMass,
        '${leanMass.toStringAsFixed(1)} kg',
        Icons.fitness_center,
        Colors.green,
      ));
    }
    if (fatMass != null) {
      stats.add(DerivedStat(
        loc.bodyTrackerFatMass,
        '${fatMass.toStringAsFixed(1)} kg',
        Icons.water_drop,
        Colors.orange,
      ));
    }
    if (whr != null) {
      final whrEval = whr < 0.9
          ? loc.bodyTrackerHealthy
          : whr < 1.0
              ? loc.bodyTrackerModerate
              : loc.bodyTrackerHigh;
      stats.add(DerivedStat(
        loc.bodyTrackerWHR,
        '${whr.toStringAsFixed(2)} · $whrEval',
        Icons.monitor_weight,
        Colors.teal,
      ));
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.bodyTrackerEstimatedComposition,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: stats
                    .map((s) => Expanded(
                          child: Column(
                            children: [
                              Icon(s.icon,
                                  size: 20, color: s.color.withAlpha(200)),
                              const SizedBox(height: 4),
                              Text(
                                s.value,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                s.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9,
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MEASUREMENT CARD (single history item)
// ═══════════════════════════════════════════════════════════════════════

/// A single measurement entry in the history list.
class BodyMeasurementCard extends StatelessWidget {
  final Map<String, dynamic> measurement;
  final MeasureType type;
  final double? delta;
  final bool isDecreasingGood;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const BodyMeasurementCard({
    super.key,
    required this.measurement,
    required this.type,
    required this.delta,
    required this.isDecreasingGood,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final value = (measurement['value'] as num).toDouble();
    final date = measurement['date'] as String? ?? '';
    final comment = measurement['comment'] as String?;
    final timeOfDay = measurement['time_of_day'] as String?;
    final isFasted = (measurement['is_fasted'] as int?) == 1;
    final side = measurement['side'] as String?;

    final isGood = delta != null && delta != 0
        ? (isDecreasingGood ? delta! < 0 : delta! > 0)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(60)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: onLongPress,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Date column
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('d', 'pt_BR')
                            .format(DateTime.parse(date)),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'pt_BR')
                            .format(DateTime.parse(date)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Value + metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${value.toStringAsFixed(1)} ${type.unit}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (side != null && type.isBilateral) ...[
                            const SizedBox(width: 6),
                            SideBadge(side: side),
                          ],
                          if (timeOfDay != null &&
                              timeOfDay.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            TimeOfDayBadge(tod: timeOfDay),
                          ],
                          if (isFasted) ...[
                            const SizedBox(width: 4),
                            const FastedBadge(),
                          ],
                        ],
                      ),
                      if (comment != null && comment.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          comment,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant
                                .withAlpha(180),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Delta badge
                if (delta != null && delta != 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isGood == true
                              ? Colors.green
                              : Colors.red)
                          .withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (isGood == true
                                ? Colors.green
                                : Colors.red)
                            .withAlpha(60),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta! > 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 10,
                          color: isGood == true
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          delta!.abs().toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isGood == true
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                Icon(Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant
                        .withAlpha(100)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
