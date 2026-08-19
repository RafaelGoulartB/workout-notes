import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/body_tracker_badges.dart';

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
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: onLongPress,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Date column
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('d', 'pt_BR').format(DateTime.parse(date)),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'pt_BR').format(DateTime.parse(date)),
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
                            formatMeasurementValue(measurement, type),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (side != null && type.isBilateral) ...[
                            const SizedBox(width: 6),
                            SideBadge(side: side),
                          ],
                          if (timeOfDay != null && timeOfDay.isNotEmpty) ...[
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
                            color: theme.colorScheme.onSurfaceVariant.withAlpha(
                              180,
                            ),
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
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (isGood == true ? Colors.green : Colors.red)
                          .withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (isGood == true ? Colors.green : Colors.red)
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
                          color: isGood == true ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          delta!.abs().toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isGood == true ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
