import 'package:flutter/material.dart';

/// Shared surface for progress charts — matches volume/run card styling.
class ProgressChartCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ProgressChartCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Accent bar + title used above chart blocks inside a tab.
class ProgressSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;

  const ProgressSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              ?subtitle == null
                  ? null
                  : Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Larger in-tab group label when multiple domains share one tab.
class ProgressGroupLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  /// Optional summary/action rendered at the end of the label row.
  final Widget? trailing;

  const ProgressGroupLabel({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withAlpha(28),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
