import 'package:flutter/material.dart';

/// A measurement point on the body silhouette.
class BodyMeasurementPoint {
  final String type;
  final Offset position;
  final String label;
  final String unit;
  final double? value;
  final Color color;

  const BodyMeasurementPoint({
    required this.type,
    required this.position,
    required this.label,
    required this.unit,
    this.value,
    required this.color,
  });
}

/// Paints a realistic human body silhouette as a single continuous outline.
/// All body parts (head, torso, arms, legs) are drawn as one unified path
/// to ensure smooth, connected, uniform contours.
class BodySilhouettePainter extends CustomPainter {
  final Color outlineColor;
  final Color fillColor;
  final List<BodyMeasurementPoint> points;
  final String? highlightedType;

  BodySilhouettePainter({
    required this.outlineColor,
    required this.fillColor,
    this.points = const [],
    this.highlightedType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Reference proportions: head ~1/7 of total height, better anatomical ratios
    // Reference: 220 wide × 440 tall for better detail
    double sx(double x) => x * w / 220;
    double sy(double y) => y * h / 440;

    final outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // ─────────────────────────────────────────────────────────
    //  SINGLE CONTINUOUS BODY OUTLINE
    //  Trace clockwise from top of head, down right side,
    //  across legs, up left side, back to top.
    //  Using smoother curves and better anatomical proportions.
    // ─────────────────────────────────────────────────────────
    final body = Path();

    // ── TOP OF HEAD ──
    body.moveTo(cx, sy(0));

    // ── RIGHT SIDE OF HEAD (rounder, more natural) ──
    body.cubicTo(sx(125), sy(0), sx(135), sy(8), sx(135), sy(22));
    body.cubicTo(sx(135), sy(32), sx(132), sy(40), sx(127), sy(46));

    // ── RIGHT JAW → NECK (smoother transition) ──
    body.cubicTo(sx(123), sy(50), sx(120), sy(54), sx(120), sy(58));
    body.cubicTo(sx(120), sy(62), sx(122), sy(65), sx(124), sy(68));

    // ── RIGHT SHOULDER (more rounded deltoid) ──
    body.cubicTo(sx(130), sy(70), sx(142), sy(72), sx(150), sy(74));
    body.cubicTo(sx(156), sy(76), sx(158), sy(80), sx(158), sy(86));

    // ── RIGHT UPPER ARM (outer - more muscular shape) ──
    body.cubicTo(sx(158), sy(94), sx(158), sy(106), sx(157), sy(116));
    // Elbow (outer - smooth curve)
    body.cubicTo(sx(156), sy(122), sx(155), sy(126), sx(153), sy(130));

    // ── RIGHT FOREARM (outer - natural taper) ──
    body.cubicTo(sx(151), sy(138), sx(149), sy(148), sx(148), sy(158));

    // ── RIGHT HAND (rounded, natural) ──
    body.cubicTo(sx(147), sy(162), sx(146), sy(166), sx(145), sy(169));
    body.cubicTo(sx(144), sy(172), sx(142), sy(174), sx(140), sy(173));
    body.cubicTo(sx(138), sy(172), sx(137), sy(169), sx(137), sy(166));

    // ── RIGHT FOREARM (inner) ──
    body.cubicTo(sx(138), sy(160), sx(139), sy(152), sx(140), sy(144));

    // ── RIGHT ELBOW (inner) ──
    body.cubicTo(sx(141), sy(138), sx(142), sy(134), sx(142), sy(130));

    // ── RIGHT UPPER ARM (inner) ──
    body.cubicTo(sx(142), sy(122), sx(141), sy(110), sx(141), sy(100));

    // ── RIGHT ARMPIT → TORSO ──
    body.cubicTo(sx(141), sy(94), sx(139), sy(90), sx(136), sy(88));

    // ── RIGHT CHEST / TORSO (more natural ribcage shape) ──
    body.cubicTo(sx(134), sy(92), sx(132), sy(100), sx(131), sy(110));
    // Ribcage → waist (smooth V-taper)
    body.cubicTo(sx(130), sy(122), sx(127), sy(136), sx(125), sy(148));
    // Waist (narrowest point - more defined)
    body.cubicTo(sx(123), sy(156), sx(122), sy(162), sx(122), sy(168));
    // Waist → hip (smooth flare)
    body.cubicTo(sx(123), sy(174), sx(126), sy(182), sx(129), sy(190));
    // Outer hip (rounded)
    body.cubicTo(sx(131), sy(194), sx(132), sy(198), sx(132), sy(202));

    // ── RIGHT OUTER THIGH (natural muscle curve) ──
    body.cubicTo(sx(133), sy(210), sx(135), sy(224), sx(135), sy(238));
    body.cubicTo(sx(135), sy(248), sx(134), sy(256), sx(133), sy(262));

    // ── RIGHT KNEE (outer - smooth) ──
    body.cubicTo(sx(132), sy(268), sx(130), sy(272), sx(128), sy(276));

    // ── RIGHT CALF (outer - natural gastrocnemius bulge) ──
    body.cubicTo(sx(129), sy(286), sx(130), sy(298), sx(129), sy(310));
    body.cubicTo(sx(128), sy(318), sx(126), sy(324), sx(124), sy(330));

    // ── RIGHT ANKLE / FOOT (natural arch) ──
    body.cubicTo(sx(123), sy(334), sx(122), sy(338), sx(124), sy(342));
    body.cubicTo(sx(126), sy(345), sx(132), sy(347), sx(138), sy(348));
    body.cubicTo(sx(142), sy(348), sx(145), sy(347), sx(145), sy(345));
    body.cubicTo(sx(144), sy(343), sx(140), sy(342), sx(136), sy(342));

    // ── RIGHT FOOT INNER ──
    body.lineTo(sx(126), sy(342));
    body.cubicTo(sx(124), sy(342), sx(122), sy(340), sx(122), sy(338));
    body.cubicTo(sx(122), sy(335), sx(122), sy(332), sx(122), sy(330));

    // ── RIGHT INNER ANKLE ──
    body.cubicTo(sx(121), sy(326), sx(120), sy(322), sx(120), sy(318));

    // ── RIGHT CALF (inner) ──
    body.cubicTo(sx(120), sy(308), sx(120), sy(296), sx(121), sy(286));

    // ── RIGHT INNER KNEE ──
    body.cubicTo(sx(121), sy(280), sx(120), sy(276), sx(119), sy(272));

    // ── RIGHT INNER THIGH ──
    body.cubicTo(sx(118), sy(264), sx(117), sy(254), sx(116), sy(244));
    body.cubicTo(sx(115), sy(234), sx(114), sy(224), sx(112), sy(214));

    // ── CROTCH (smooth natural curve) ──
    body.cubicTo(sx(110), sy(208), sx(106), sy(204), cx, sy(206));
    body.cubicTo(sx(106), sy(204), sx(102), sy(208), sx(100), sy(214));

    // ── LEFT INNER THIGH ──
    body.cubicTo(sx(98), sy(224), sx(97), sy(234), sx(96), sy(244));
    body.cubicTo(sx(95), sy(254), sx(94), sy(264), sx(93), sy(272));

    // ── LEFT INNER KNEE ──
    body.cubicTo(sx(92), sy(276), sx(91), sy(280), sx(91), sy(286));

    // ── LEFT CALF (inner) ──
    body.cubicTo(sx(92), sy(296), sx(92), sy(308), sx(92), sy(318));

    // ── LEFT INNER ANKLE ──
    body.cubicTo(sx(92), sy(322), sx(91), sy(326), sx(90), sy(330));
    body.cubicTo(sx(90), sy(332), sx(90), sy(335), sx(90), sy(338));
    body.cubicTo(sx(90), sy(340), sx(88), sy(342), sx(86), sy(342));

    // ── LEFT FOOT INNER ──
    body.lineTo(sx(76), sy(342));
    body.cubicTo(sx(72), sy(342), sx(68), sy(343), sx(67), sy(345));
    body.cubicTo(sx(67), sy(347), sx(70), sy(348), sx(74), sy(348));
    body.cubicTo(sx(80), sy(347), sx(86), sy(345), sx(88), sy(342));

    // ── LEFT ANKLE (outer) ──
    body.cubicTo(sx(90), sy(338), sx(89), sy(334), sx(88), sy(330));

    // ── LEFT CALF (outer) ──
    body.cubicTo(sx(86), sy(324), sx(84), sy(318), sx(83), sy(310));
    body.cubicTo(sx(82), sy(298), sx(83), sy(286), sx(84), sy(276));

    // ── LEFT KNEE (outer) ──
    body.cubicTo(sx(84), sy(272), sx(82), sy(268), sx(81), sy(262));

    // ── LEFT OUTER THIGH ──
    body.cubicTo(sx(80), sy(256), sx(79), sy(248), sx(79), sy(238));
    body.cubicTo(sx(79), sy(224), sx(81), sy(210), sx(82), sy(202));

    // ── LEFT OUTER HIP ──
    body.cubicTo(sx(82), sy(198), sx(83), sy(194), sx(85), sy(190));
    body.cubicTo(sx(88), sy(182), sx(91), sy(174), sx(92), sy(168));

    // ── LEFT WAIST → TORSO ──
    body.cubicTo(sx(92), sy(162), sx(91), sy(156), sx(89), sy(148));
    body.cubicTo(sx(87), sy(136), sx(84), sy(122), sx(83), sy(110));
    body.cubicTo(sx(82), sy(100), sx(80), sy(92), sx(78), sy(88));

    // ── LEFT ARMPIT → TORSO ──
    body.cubicTo(sx(75), sy(90), sx(73), sy(94), sx(73), sy(100));

    // ── LEFT UPPER ARM (inner) ──
    body.cubicTo(sx(73), sy(110), sx(72), sy(122), sx(72), sy(130));

    // ── LEFT ELBOW (inner) ──
    body.cubicTo(sx(72), sy(134), sx(73), sy(138), sx(74), sy(144));

    // ── LEFT FOREARM (inner) ──
    body.cubicTo(sx(75), sy(152), sx(76), sy(160), sx(77), sy(166));
    body.cubicTo(sx(77), sy(169), sx(76), sy(172), sx(74), sy(173));
    body.cubicTo(sx(72), sy(174), sx(70), sy(172), sx(69), sy(169));

    // ── LEFT HAND (rounded) ──
    body.cubicTo(sx(68), sy(166), sx(67), sy(162), sx(66), sy(158));

    // ── LEFT FOREARM (outer) ──
    body.cubicTo(sx(65), sy(148), sx(63), sy(138), sx(61), sy(130));

    // ── LEFT ELBOW (outer) ──
    body.cubicTo(sx(59), sy(126), sx(58), sy(122), sx(58), sy(116));

    // ── LEFT UPPER ARM (outer) ──
    body.cubicTo(sx(58), sy(106), sx(58), sy(94), sx(58), sy(86));

    // ── LEFT SHOULDER (rounded deltoid) ──
    body.cubicTo(sx(58), sy(80), sx(60), sy(76), sx(66), sy(74));

    // ── LEFT SHOULDER → NECK ──
    body.cubicTo(sx(74), sy(72), sx(86), sy(70), sx(92), sy(68));
    body.cubicTo(sx(94), sy(65), sx(94), sy(62), sx(94), sy(58));

    // ── LEFT NECK → JAW ──
    body.cubicTo(sx(94), sy(54), sx(91), sy(50), sx(87), sy(46));

    // ── LEFT SIDE OF HEAD ──
    body.cubicTo(sx(82), sy(40), sx(79), sy(32), sx(79), sy(22));
    body.cubicTo(sx(79), sy(8), sx(89), sy(0), cx, sy(0));

    body.close();

    // Draw the complete body
    canvas.drawPath(body, fillPaint);
    canvas.drawPath(body, outlinePaint);

    // ─────────────────────────────────────────────────────────
    //  MEASUREMENT POINTS
    // ─────────────────────────────────────────────────────────
    for (final point in points) {
      final px = point.position.dx * w;
      final py = point.position.dy * h;
      final isHighlighted = point.type == highlightedType;

      if (isHighlighted) {
        canvas.drawCircle(
          Offset(px, py),
          18,
          Paint()..color = outlineColor.withAlpha(30),
        );
      }

      canvas.drawCircle(
        Offset(px, py),
        isHighlighted ? 9 : 7,
        Paint()..color = point.color,
      );

      canvas.drawCircle(
        Offset(px, py),
        isHighlighted ? 4.5 : 3.5,
        Paint()..color = Colors.white,
      );

      canvas.drawCircle(
        Offset(px, py),
        isHighlighted ? 9 : 7,
        Paint()
          ..color = point.color.withAlpha(160)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BodySilhouettePainter oldDelegate) {
    return oldDelegate.outlineColor != outlineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.highlightedType != highlightedType ||
        oldDelegate.points.length != points.length;
  }
}
