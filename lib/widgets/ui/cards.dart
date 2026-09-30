import 'package:flutter/material.dart';

import 'package:workout_notes/widgets/ui/app_ui.dart';

/// Flat outlined surface card used for every section.
class AppSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  /// Outer spacing; none by default so lists control their own gaps.
  final EdgeInsetsGeometry margin;
  final double radius;

  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.margin = EdgeInsets.zero,
    this.radius = AppUi.cardRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: AppUi.divider(colors)),
    );
    return Card(
      elevation: 0,
      margin: margin,
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// Soft headline surface shared with the nutrition "day summary" card: a
/// subtle neutral diagonal gradient and a 20 px radius. Optionally tappable
/// ([onTap]) and outlined ([bordered], as on the hero cards).
class AppSoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool bordered;

  const AppSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 16, 16),
    this.onTap,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = Padding(
      // Ink paints the border without reserving room for it, unlike Container.
      padding: bordered ? padding.add(const EdgeInsets.all(1)) : padding,
      child: child,
    );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppUi.heroRadius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.surfaceContainerHighest.withAlpha(200),
              colors.surfaceContainerLow,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppUi.heroRadius),
          border: bordered ? Border.all(color: AppUi.divider(colors)) : null,
        ),
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// Gradient hero container for the headline numbers of a screen.
class AppHeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 14),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppSoftCard(bordered: true, padding: padding, child: child),
    );
  }
}

/// Rounded tinted square holding an icon.
class AppIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  const AppIconBadge(
    this.icon, {
    super.key,
    this.color,
    this.size = 34,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// Divided column of rows inside a [AppSectionCard].
class AppDividedList extends StatelessWidget {
  final List<Widget> children;

  const AppDividedList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant.withAlpha(70);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, color: color),
          children[i],
        ],
      ],
    );
  }
}
