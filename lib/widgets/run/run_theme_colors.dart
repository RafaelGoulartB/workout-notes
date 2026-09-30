import 'package:flutter/material.dart';

/// Warm / effort colours derived from the active theme, so they follow light
/// and dark mode instead of being hard-coded hex values.
abstract final class RunThemeColors {
  /// Orange used for "slower than average".
  static Color warm(ColorScheme colors) => _withHue(colors, 28);

  /// Green -> amber -> orange -> red for a 1..10 perceived-effort value.
  static Color effort(ColorScheme colors, int value) {
    if (value <= 3) return _withHue(colors, 135);
    if (value <= 6) return _withHue(colors, 45);
    if (value <= 8) return _withHue(colors, 28);
    return colors.error;
  }

  static Color _withHue(ColorScheme colors, double hue) {
    final base = HSLColor.fromColor(colors.error);
    return base.withHue(hue).toColor();
  }
}
