import 'package:flutter/material.dart';

/// AppBar used by settings surfaces. Renders the title with
/// `titleMedium + w600` left-aligned (no centerTitle) to match the
/// canonical pattern. Use [showBackButton] to toggle the automatic
/// back button (defaults to true).
class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final List<Widget>? actions;

  const SettingsAppBar({
    super.key,
    required this.title,
    this.showBackButton = true,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: showBackButton,
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: false,
      actions: actions,
    );
  }
}