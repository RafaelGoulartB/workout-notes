import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

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
            Row(
              children: [
                Expanded(
                  child: _BilateralSidePanel(
                    theme: theme,
                    sideLabel:
                        AppLocalizations.of(context)!.bodyTrackerLeft,
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
                    sideLabel:
                        AppLocalizations.of(context)!.bodyTrackerRight,
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
            : (isGood == false
                ? Colors.red
                : theme.colorScheme.onSurfaceVariant));

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
          Icon(Icons.compare_arrows,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            loc.bodyTrackerAsymmetry(
                diff.toStringAsFixed(1), larger, unit),
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
