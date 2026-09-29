import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimal GPS trail drawn from a run's polyline summary: no tiles, no
/// network. Used for list thumbnails, the post-run hero and share cards.
class RunRouteSketch extends StatelessWidget {
  final List<Offset> points;
  final double width;
  final double height;
  final Color? color;
  final Color? endColor;
  final double strokeWidth;

  const RunRouteSketch({
    super.key,
    required this.points,
    required this.width,
    required this.height,
    this.color,
    this.endColor,
    this.strokeWidth = 3.2,
  });

  /// Square sketch parsed straight from a `polyline_summary` string.
  factory RunRouteSketch.fromSummary(
    String? summary, {
    Key? key,
    double size = 48,
    Color? color,
    Color? endColor,
    double strokeWidth = 2.4,
  }) => RunRouteSketch(
    key: key,
    points: parse(summary),
    width: size,
    height: size,
    color: color,
    endColor: endColor,
    strokeWidth: strokeWidth,
  );

  /// `lat,lng;lat,lng;…` as produced by `RunRepository._buildPolylineSummary`.
  /// Returned offsets are `(lng, lat)`.
  static List<Offset> parse(String? summary) {
    if (summary == null || summary.isEmpty) return const [];
    final parsed = <Offset>[];
    for (final chunk in summary.split(';')) {
      final parts = chunk.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat == null || lng == null) continue;
      parsed.add(Offset(lng, lat));
    }
    return parsed;
  }

  /// A trail worth drawing: at least two points spanning ~11 m or more.
  static bool hasShape(List<Offset> points) {
    if (points.length < 2) return false;
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return (maxX - minX) >= 1e-4 || (maxY - minY) >= 1e-4;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: RunRoutePainter(
          points: points,
          color: color ?? colors.primary,
          endColor: endColor ?? colors.tertiary,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class RunRoutePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final Color endColor;
  final double strokeWidth;

  const RunRoutePainter({
    required this.points,
    required this.color,
    required this.endColor,
    this.strokeWidth = 3.2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // Longitude degrees shrink with latitude; scale so the shape is not skewed.
    final meanLat =
        points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    final lngScale = math.cos(meanLat * math.pi / 180).abs().clamp(0.05, 1.0);

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final p in points) {
      final x = p.dx * lngScale;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    final padding = math.max(4.0, strokeWidth * 2.5);
    final scale = math.min(
      (size.width - padding * 2) / spanX,
      (size.height - padding * 2) / spanY,
    );
    final offsetX = (size.width - spanX * scale) / 2;
    final offsetY = (size.height - spanY * scale) / 2;

    Offset project(Offset p) => Offset(
      offsetX + (p.dx * lngScale - minX) * scale,
      // Flip Y so north points up.
      size.height - offsetY - (p.dy - minY) * scale,
    );

    final path = Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final projected = project(p);
      path.lineTo(projected.dx, projected.dy);
    }

    // Soft halo under the trail keeps it legible over gradients and photos.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawCircle(
      project(points.first),
      strokeWidth * 1.1,
      Paint()..color = color,
    );
    canvas.drawCircle(
      project(points.last),
      strokeWidth * 1.4,
      Paint()..color = endColor,
    );
    canvas.drawCircle(
      project(points.last),
      strokeWidth * 0.6,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(RunRoutePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.endColor != endColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
