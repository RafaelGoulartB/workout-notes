import 'package:flutter/material.dart';

/// Loading skeleton — keeps the layout stable so the transition into real
/// content doesn't cause a jarring jump.
class WorkoutHomeLoadingSkeleton extends StatelessWidget {
  const WorkoutHomeLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHighest;
    BoxDecoration box({double r = 8}) =>
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(r));
    Widget line({required double h, double? w, double r = 8}) => Container(
      height: h,
      width: w,
      decoration: box(r: r),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        line(h: 24, w: 180),
        const SizedBox(height: 8),
        line(h: 14, w: 240),
        const SizedBox(height: 20),
        line(h: 90, r: 20),
        const SizedBox(height: 20),
        line(h: 12, w: 80),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: line(h: 90, r: 16)),
            const SizedBox(width: 12),
            Expanded(child: line(h: 90, r: 16)),
          ],
        ),
        const SizedBox(height: 20),
        line(h: 12, w: 60),
        const SizedBox(height: 12),
        line(h: 110, r: 16),
        const SizedBox(height: 20),
        line(h: 12, w: 100),
        const SizedBox(height: 12),
        line(h: 64, r: 12),
        const SizedBox(height: 8),
        line(h: 64, r: 12),
      ],
    );
  }
}

class WorkoutHomeTimerPill extends StatelessWidget {
  final int remainingSeconds;
  final bool isRunning;
  final bool isPaused;
  final String shortTime;
  final VoidCallback onTap;

  const WorkoutHomeTimerPill({
    super.key,
    required this.remainingSeconds,
    required this.isRunning,
    required this.isPaused,
    required this.shortTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrgent = remainingSeconds <= 5 && isRunning;
    final bg = isUrgent
        ? Colors.red.withAlpha(40)
        : theme.colorScheme.primaryContainer;
    final fg = isUrgent ? Colors.red : theme.colorScheme.onPrimaryContainer;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isPaused ? Icons.pause : Icons.timer, size: 18, color: fg),
            const SizedBox(width: 4),
            Text(
              shortTime,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
