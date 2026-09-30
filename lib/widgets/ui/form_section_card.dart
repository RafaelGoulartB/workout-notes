import 'package:flutter/material.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

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
    return AppSectionCard(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCardTitle(icon: icon, title: title),
          const SizedBox(height: 14),
          ...children,
        ],
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
