import 'package:flutter/material.dart';

/// Design tokens shared by the UI kit (cards, headers, tiles, pills) so every
/// module looks the same.
abstract final class AppUi {
  static const double cardRadius = 16;
  static const double heroRadius = 20;
  static const double tileRadius = 12;
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(16, 12, 16, 110);

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static Color divider(ColorScheme colors) =>
      colors.outlineVariant.withAlpha(80);
}
