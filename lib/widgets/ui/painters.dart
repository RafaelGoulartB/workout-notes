import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular progress ring: a full [track] circle with the [progress] arc
/// (0..1, clockwise from the top) drawn over it with round ends.
class RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  const RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    this.strokeWidth = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}

/// Dashed rounded-rectangle outline with a faint fill, used for the planned
/// ("ghost") bars of the week strips.
class DashedRRectPainter extends CustomPainter {
  final Color color;
  final Color fill;

  const DashedRRectPainter({required this.color, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      const Radius.circular(6),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(DashedRRectPainter old) =>
      old.color != color || old.fill != fill;
}
