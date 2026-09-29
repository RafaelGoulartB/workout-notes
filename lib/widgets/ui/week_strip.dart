import 'package:flutter/material.dart';

import 'package:workout_notes/widgets/ui/painters.dart';

/// One day of a Monday-to-Sunday strip: a small vertical track with the
/// day's amount as a filled bar (or a dashed "ghost" for a planned session
/// still ahead / missed), a short value above and the weekday below.
///
/// [barRatio] draws the filled bar; otherwise [ghostColor] draws the dashed
/// ghost (sized by [ghostRatio], with [ghostIcon] centered in it).
class AppWeekStripDay extends StatelessWidget {
  final String tooltip;

  /// Weekday letters below the track.
  final String label;
  final bool isToday;
  final bool isFuture;

  /// Short value above the track (distance, set count).
  final String? topLabel;
  final FontWeight topLabelWeight;
  final Color? topLabelColor;

  /// Fraction (0..1) of the track height covered by the filled bar.
  final double? barRatio;
  final Color barColor;

  final Color? ghostColor;
  final double ghostRatio;
  final Widget? ghostIcon;

  const AppWeekStripDay({
    super.key,
    required this.tooltip,
    required this.label,
    required this.isToday,
    required this.isFuture,
    required this.barColor,
    this.topLabel,
    this.topLabelWeight = FontWeight.w800,
    this.topLabelColor,
    this.barRatio,
    this.ghostColor,
    this.ghostRatio = 1,
    this.ghostIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ghost = ghostColor;
    final Widget? track = barRatio != null
        ? FractionallySizedBox(
            widthFactor: 1,
            heightFactor: barRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          )
        : ghost != null
        ? FractionallySizedBox(
            widthFactor: 1,
            heightFactor: ghostRatio,
            child: CustomPaint(
              painter: DashedRRectPainter(
                color: ghost.withValues(alpha: 0.75),
                fill: ghost.withValues(alpha: 0.08),
              ),
              child: ghostIcon == null ? null : Center(child: ghostIcon),
            ),
          )
        : null;

    return Tooltip(
      message: tooltip,
      child: Column(
        children: [
          SizedBox(
            height: 14,
            child: topLabel == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      topLabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: topLabelWeight,
                        color: topLabelColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
          ),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: isFuture
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.3)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.bottomCenter,
            child: track,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              color: isToday ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
