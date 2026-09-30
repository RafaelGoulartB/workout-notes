import 'package:flutter/material.dart';

/// Header row rendered at the top of a bottom sheet (icon + title in
/// titleSmall + bold). Always followed by a 1px divider and the sheet's
/// action rows below.
class SettingsSheetTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const SettingsSheetTitle({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
