import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Uppercase, letter-spaced section label with an optional trailing action.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  /// Tighter spacing used by settings-style screens.
  static const EdgeInsets compactPadding = EdgeInsets.fromLTRB(4, 20, 4, 8);

  const AppSectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 22, 0, 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Icon-led bold title at the top of a card ("Basics", "Defaults").
class AppCardTitle extends StatelessWidget {
  final IconData? icon;
  final String title;

  const AppCardTitle({super.key, this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact text button used as a section header action ("See all").
class AppHeaderAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const AppHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// "Today · Tue, Sep 29" title row of the hub "today" cards.
class AppTodayHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  /// Appends today's date; off where the screen already shows it.
  final bool showDate;

  const AppTodayHeader({
    super.key,
    required this.title,
    this.icon = Icons.today_rounded,
    this.showDate = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).format(DateTime.now());
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        if (showDate)
          Expanded(
            child: Text(
              '· $date',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom row of a "today" card: where the session comes from on the left
/// and a compact start button on the right.
class AppTodayFooter extends StatelessWidget {
  final String? caption;
  final IconData captionIcon;
  final Key? actionKey;
  final String actionLabel;
  final VoidCallback onAction;

  const AppTodayFooter({
    super.key,
    this.caption,
    this.captionIcon = Icons.event_note_rounded,
    this.actionKey,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final button = FilledButton.icon(
      key: actionKey,
      onPressed: onAction,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    if (caption == null) {
      return Align(alignment: Alignment.centerRight, child: button);
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(captionIcon, size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
            child: button,
          ),
        ],
      ),
    );
  }
}
