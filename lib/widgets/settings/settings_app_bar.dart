import 'package:flutter/material.dart';

/// AppBar used by settings surfaces. Renders the title with
/// `titleMedium + w600` left-aligned (no centerTitle) to match the
/// canonical pattern.
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  const SettingsAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: false,
    );
  }
}
