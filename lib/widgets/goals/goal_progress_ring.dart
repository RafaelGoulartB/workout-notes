import 'package:flutter/material.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Circular progress ring with an optional centered child.
///
/// Animates the progress smoothly on changes.
class GoalProgressRing extends StatelessWidget {
  final double percent; // 0.0 to 1.0+
  final Color color;
  final Color? trackColor;
  final double size;
  final double strokeWidth;
  final Widget? child;

  const GoalProgressRing({
    super.key,
    required this.percent,
    required this.color,
    this.trackColor,
    this.size = 70,
    this.strokeWidth = 8,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = trackColor ?? theme.colorScheme.outlineVariant.withAlpha(60);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: RingPainter(
              progress: value,
              color: color,
              track: track,
              strokeWidth: strokeWidth,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

