import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Card used by every analysis block: icon + title (+ short subtitle) in one
/// header row, an optional "how it works" button that moves long
/// explanations out of the way, then the content.
class RunInsightCard extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String? subtitle;

  /// Longer explanation shown in a bottom sheet from the info button.
  final String? info;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;

  const RunInsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.color,
    this.subtitle,
    this.info,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return AppSectionCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconBadge(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (info != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: loc.runInsightsHowItWorks,
                  icon: Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  onPressed: () => showRunInsightInfo(context, title, info!),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ],
      ),
    );
  }
}

/// Bottom sheet with the explanation behind an analysis card.
Future<void> showRunInsightInfo(
  BuildContext context,
  String title,
  String text,
) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(text, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );
}

/// Muted explanatory line.
class RunInsightsNote extends StatelessWidget {
  final String text;
  final Color? color;

  const RunInsightsNote(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Small subheading inside a card (e.g. "Your pace zones").
class RunInsightsSubheading extends StatelessWidget {
  final String text;

  const RunInsightsSubheading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
