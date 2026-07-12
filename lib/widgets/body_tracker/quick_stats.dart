import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

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
      (
        loc.bodyTrackerMin,
        minValue?.toStringAsFixed(1) ?? '--',
        Icons.trending_down,
        Colors.blueGrey,
      ),
      (
        loc.bodyTrackerMax,
        maxValue?.toStringAsFixed(1) ?? '--',
        Icons.trending_up,
        typeColor,
      ),
      (
        loc.bodyTrackerAverage,
        avgValue?.toStringAsFixed(1) ?? '--',
        Icons.show_chart,
        typeColor.withAlpha(200),
      ),
      (
        loc.bodyTrackerEntries,
        '$totalCount',
        Icons.receipt_long,
        theme.colorScheme.secondary,
      ),
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
