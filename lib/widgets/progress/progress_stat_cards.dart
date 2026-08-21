import 'package:flutter/material.dart';

/// A compact stat card used in the progress overview.
class ProgressStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const ProgressStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withAlpha(18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withAlpha(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mini stat row used in the monthly report card.
class ProgressMiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ThemeData theme;
  final int? delta;

  const ProgressMiniStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (delta != null && delta != 0)
            Text(
              '${delta! > 0 ? '+' : ''}$delta',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: delta! > 0 ? Colors.green : Colors.red,
              ),
            ),
        ],
      ),
    );
  }
}
