import 'package:flutter/material.dart';

/// A single horizontal stacked bar where each segment's width is proportional
/// to its [value] relative to the sum of every segment's value, filled with the
/// segment's [color]. Segments are separated by a thin gap and fully rounded so
/// the bar reads like the other progress bars of the app.
///
/// Designed for at-a-glance category distribution in tight spaces, such as a
/// routine card showing which muscle groups it trains.
///
/// Segments with a value `<= 0` are skipped. Order is preserved
/// (left to right), so sort the input list beforehand if you want the
/// largest segment on the left.
class CategoryTimelineBar extends StatelessWidget {
  const CategoryTimelineBar({
    super.key,
    required this.segments,
    this.height = 8,
    this.borderRadius = 999,
    this.gap = 2,
  });

  /// Each entry pairs a fill [Color] with a numeric [value] (e.g. number
  /// of sets, total volume, etc.). The segment width is proportional to
  /// its value vs. the sum of every value in [segments].
  final List<({Color color, num value})> segments;

  /// Total height of the bar.
  final double height;

  /// Corner radius applied to the whole bar (clamped to half the height).
  final double borderRadius;

  /// Space between neighbouring segments.
  final double gap;

  @override
  Widget build(BuildContext context) {
    // Drop zero / negative contributions so they don't take up flex space.
    final nonZero = segments.where((s) => s.value > 0).toList();
    if (nonZero.isEmpty) return const SizedBox.shrink();

    final radius = borderRadius.clamp(0, height / 2).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < nonZero.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                // `clamp(1, ...)` ensures even a tiny value (e.g. 1 set in
                // a 1000-set routine) is still visible.
                flex: nonZero[i].value.round().clamp(1, 1 << 20),
                child: ColoredBox(color: nonZero[i].color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
