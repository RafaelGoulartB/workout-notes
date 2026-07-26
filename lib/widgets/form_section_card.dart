import 'package:flutter/material.dart';

/// A grouped form section: a card with a small icon-led header at the top
/// and a list of field widgets below.
///
/// Use this to break long forms into logical groups (e.g. "Basics",
/// "Defaults") so the screen is easier to scan and matches the rest of
/// the app's card-based visual style.
class FormSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const FormSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Small field label rendered above a form input. Uses the muted
/// onSurfaceVariant color so it reads as a sub-label rather than a
/// floating `InputDecoration` label.
class FormFieldLabel extends StatelessWidget {
  final String text;
  const FormFieldLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
