import 'package:flutter/material.dart';

/// Look of an [AppBanner].
enum AppBannerKind {
  /// Something is wrong or invalid: error container colours.
  warning,

  /// Helpful context: tinted secondary container.
  info,

  /// Quiet neutral note, e.g. "nothing to show yet" inside a card.
  note,
}

/// Inline message box with an icon, for warnings, hints and empty notes.
class AppBanner extends StatelessWidget {
  final String message;
  final AppBannerKind kind;

  /// Defaults to a warning triangle / info circle depending on [kind].
  final IconData? icon;

  const AppBanner(
    this.message, {
    super.key,
    this.kind = AppBannerKind.info,
    this.icon,
  });

  const AppBanner.warning(String message, {Key? key, IconData? icon})
    : this(message, key: key, kind: AppBannerKind.warning, icon: icon);

  const AppBanner.note(String message, {Key? key, IconData? icon})
    : this(message, key: key, kind: AppBannerKind.note, icon: icon);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (
      background,
      foreground,
      textColor,
      radius,
      padding,
      iconSize,
    ) = switch (kind) {
      AppBannerKind.warning => (
        colors.errorContainer,
        colors.onErrorContainer,
        colors.onErrorContainer,
        12.0,
        const EdgeInsets.all(12),
        24.0,
      ),
      AppBannerKind.info => (
        colors.secondaryContainer.withAlpha(100),
        colors.onSecondaryContainer,
        null,
        12.0,
        const EdgeInsets.all(12),
        19.0,
      ),
      AppBannerKind.note => (
        colors.surfaceContainerHighest.withAlpha(120),
        colors.onSurfaceVariant,
        colors.onSurfaceVariant,
        10.0,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        16.0,
      ),
    };
    final defaultIcon = kind == AppBannerKind.warning
        ? Icons.warning_amber_rounded
        : Icons.info_outline_rounded;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        children: [
          Icon(icon ?? defaultIcon, size: iconSize, color: foreground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
