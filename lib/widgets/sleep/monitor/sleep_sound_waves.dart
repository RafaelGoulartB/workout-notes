import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Minimal layered waves for the sleep monitor. With a [sampler] they follow
/// the live microphone level (0–1); without one they only breathe slowly.
///
/// Sampling is tied to the animation ticker, so it stops by itself when the
/// app is in the background or another route covers the screen, and nothing
/// polls while the waves are not on screen.
class SleepSoundWaves extends StatefulWidget {
  const SleepSoundWaves({
    super.key,
    this.sampler,
    this.height = 120,
    this.color,
  });

  /// Returns the current level (0–1), or null when there is none.
  final Future<double?> Function()? sampler;
  final double height;
  final Color? color;

  @override
  State<SleepSoundWaves> createState() => _SleepSoundWavesState();
}

class _SleepSoundWavesState extends State<SleepSoundWaves>
    with SingleTickerProviderStateMixin {
  static const _sampleEvery = Duration(milliseconds: 150);

  late final Ticker _ticker = createTicker(_onTick);
  final _motion = _WaveMotion();
  Duration _lastTick = Duration.zero;
  Duration _lastSample = -_sampleEvery;
  bool _sampling = false;
  double _target = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _ticker.isActive) {
      _ticker.stop();
    } else if (!reduceMotion && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _lastSample = -_sampleEvery;
      unawaited(_ticker.start());
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (widget.sampler != null && elapsed - _lastSample >= _sampleEvery) {
      _lastSample = elapsed;
      unawaited(_sample());
    }
    _motion.advance(dt.clamp(0.0, 0.1), _target);
  }

  Future<void> _sample() async {
    final sampler = widget.sampler;
    if (_sampling || sampler == null) return;
    _sampling = true;
    try {
      final level = await sampler();
      if (mounted) _target = level ?? 0;
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(painter: _WavePainter(_motion, color)),
        ),
      ),
    );
  }
}

/// Phase and eased amplitude of the waves; repaints the painter only.
class _WaveMotion extends ChangeNotifier {
  double phase = 0;
  double amplitude = 0;

  void advance(double dt, double target) {
    // Rise quickly with a sound, settle slowly like a breath.
    final rate = target > amplitude ? 9.0 : 2.5;
    amplitude += (target - amplitude) * (1 - math.exp(-rate * dt));
    phase += dt * (0.9 + amplitude * 3.2);
    notifyListeners();
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.motion, this.color) : super(repaint: motion);

  final _WaveMotion motion;
  final Color color;

  // (cycles across the width, phase speed, phase offset, opacity, stroke).
  static const _layers = [
    (1.3, 1.0, 0.0, 0.95, 2.4),
    (2.1, -1.4, 1.9, 0.5, 1.6),
    (3.2, 1.9, 4.1, 0.28, 1.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final mid = size.height / 2;
    // Never fully flat: a calm room still shows a slow, faint breath.
    final breath = 0.1 + 0.03 * math.sin(motion.phase * 0.7);
    final reach = (breath + motion.amplitude * (1 - breath)) * mid * 0.92;
    const step = 3.0;
    for (final (cycles, speed, offset, opacity, stroke) in _layers) {
      final tint = color.withValues(alpha: opacity);
      // Fade the line ends so the waves float instead of hitting the edges.
      final shader = LinearGradient(
        colors: [tint.withAlpha(0), tint, tint, tint.withAlpha(0)],
        stops: const [0, 0.22, 0.78, 1],
      ).createShader(Offset.zero & size);
      final path = Path();
      for (var x = 0.0; x <= size.width + step; x += step) {
        final u = (x / size.width).clamp(0.0, 1.0);
        // Taper to the centre line at both edges.
        final envelope = math.pow(math.sin(math.pi * u), 2).toDouble();
        final y =
            mid +
            reach *
                envelope *
                math.sin(
                  2 * math.pi * cycles * u + motion.phase * speed + offset,
                );
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.color != color;
}
