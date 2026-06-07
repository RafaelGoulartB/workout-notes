import 'package:flutter/material.dart';

/// A single horizontal stacked bar (a "timeline" of sorts) where each
/// segment's width is proportional to its [value] relative to the sum of
/// every segment's value, filled with the segment's [color].
///
/// Designed for at-a-glance category distribution in tight spaces — e.g.
/// the collapsed state of a dashboard summary, where multiple small dots
/// would otherwise be used.
///
/// Segments with a value `<= 0` are skipped. Order is preserved
/// (left → right), so sort the input list beforehand if you want the
/// largest segment on the left.
class CategoryTimelineBar extends StatelessWidget {
  const CategoryTimelineBar({
    super.key,
    required this.segments,
    this.height = 8,
    this.borderRadius = 4,
  });

  /// Each entry pairs a fill [Color] with a numeric [value] (e.g. number
  /// of sets, total volume, etc.). The segment width is proportional to
  /// its value vs. the sum of every value in [segments].
  final List<({Color color, num value})> segments;

  /// Total height of the bar.
  final double height;

  /// Corner radius applied to the whole bar.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Drop zero / negative contributions so they don't take up flex space.
    final nonZero = segments.where((s) => s.value > 0).toList();
    if (nonZero.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final seg in nonZero)
              Expanded(
                // `clamp(1, ...)` ensures even a tiny value (e.g. 1 set in
                // a 1000-set routine) is still visible.
                flex: seg.value.round().clamp(1, 1 << 20),
                child: Container(color: seg.color),
              ),
          ],
        ),
      ),
    );
  }
}
