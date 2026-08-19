import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

/// Compact body-weight summary shown at the top of the Tracking tab.
class BodyMeasurementsTeaserCard extends StatelessWidget {
  final double? weightKg;
  final String? unit;
  final double? delta;
  final String? date;
  final VoidCallback onOpen;

  const BodyMeasurementsTeaserCard({
    super.key,
    this.weightKg,
    this.unit,
    this.delta,
    this.date,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasWeight = weightKg != null;
    final displayUnit = (unit == null || unit!.isEmpty) ? 'kg' : unit!;

    final deltaValue = delta;
    final isGood = deltaValue != null && deltaValue < 0;
    final isBad = deltaValue != null && deltaValue > 0;
    final deltaColor = deltaValue == null || deltaValue == 0
        ? theme.colorScheme.onSurfaceVariant
        : (isGood
              ? Colors.green
              : isBad
              ? Colors.red
              : theme.colorScheme.onSurfaceVariant);

    return PeriodizationSurface(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.monitor_weight_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.trackingBodyWeight,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (hasWeight) ...[
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${weightKg!.toStringAsFixed(1)} $displayUnit',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (deltaValue != null && deltaValue != 0) ...[
                        const SizedBox(width: 8),
                        Icon(
                          deltaValue < 0
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 14,
                          color: deltaColor,
                        ),
                        Text(
                          '${deltaValue > 0 ? '+' : ''}${deltaValue.toStringAsFixed(1)}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: deltaColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (date != null && date!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatDate(date!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withAlpha(170),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ] else
                  Text(
                    loc.trackingNoWeight,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  loc.trackingOpenMeasurements,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
