import 'package:flutter/material.dart';

/// Section header rendered above a group of settings.
///
/// Uses an uppercase tracked label in the muted [onSurfaceVariant]
/// color so it reads as a divider/category marker rather than a heading.
/// Matches the canonical pattern used across all settings screens.
class SettingsSectionHeader extends StatelessWidget {
  final String text;

  const SettingsSectionHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Grouped card container used to gather related settings tiles.
///
/// Always renders as a flat outlined card (no elevation). When [title]
/// is provided a small icon-led header is rendered inside the card; the
/// children are appended below it.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  final IconData? icon;

  const SettingsCard({
    super.key,
    required this.children,
    this.title,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// Horizontal divider used between rows inside a [SettingsCard]. The
/// left indent keeps the line aligned under the row's title text, past
/// the leading icon container.
class SettingsCardDivider extends StatelessWidget {
  const SettingsCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
    );
  }
}

/// Inline empty-state hint rendered inside a card (no surrounding
/// container). Use for "nothing configured yet" messages that should
/// live between card rows.
class SettingsEmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const SettingsEmptyHint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}