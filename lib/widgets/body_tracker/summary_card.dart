import 'package:flutter/material.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/body_tracker/body_sparkline.dart';
import 'package:workout_notes/widgets/body_tracker_badges.dart';

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
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: deltaColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: deltaColor.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                            color: deltaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
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
            if (value != null && measurements.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formatDate(measurements.first['date'] as String? ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                      fontSize: 11,
                    ),
                  ),
                  if ((measurements.first['time_of_day'] as String?)
                          ?.isNotEmpty ==
                      true) ...[
                    const SizedBox(width: 8),
                    TimeOfDayBadge(
                      tod: measurements.first['time_of_day'] as String,
                    ),
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
