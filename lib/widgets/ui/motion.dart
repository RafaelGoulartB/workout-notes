import 'package:flutter/material.dart';

/// Fades (and optionally slides up) its child in once, when first inserted.
///
/// The animation state lives in the element, so rebuilds with the same widget
/// position never replay it; give it a new key to play it again. [delay]
/// holds the child invisible before the fade starts, which staggers list
/// items without any timers.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  /// Starting vertical offset as a fraction of the child's height (a positive
  /// value starts below the final position). `0` means fade only.
  final double slideY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.delay = Duration.zero,
    this.slideY = 0,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _controller = AnimationController(vsync: this, duration: total);
    final start = total.inMicroseconds == 0
        ? 0.0
        : widget.delay.inMicroseconds / total.inMicroseconds;
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1.0),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;
    if (widget.slideY != 0) {
      child = SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.slideY),
          end: Offset.zero,
        ).animate(_progress),
        child: child,
      );
    }
    return FadeTransition(opacity: _progress, child: child);
  }
}

/// Solid dot with a soft ring that pulses outwards, for "live" indicators.
///
/// Driven by an [AnimationController], so it follows [TickerMode]: the pulse
/// stops while the tab is hidden or another page covers this one.
class AppPulsingDot extends StatefulWidget {
  final Color color;

  /// Diameter of the pulsing ring; the solid core is half of it.
  final double size;

  const AppPulsingDot({super.key, required this.color, this.size = 16});

  @override
  State<AppPulsingDot> createState() => _AppPulsingDotState();
}

class _AppPulsingDotState extends State<AppPulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final decoration = BoxDecoration(
      color: widget.color,
      shape: BoxShape.circle,
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Opacity(
              opacity: 0.6 * (1 - _controller.value),
              child: Transform.scale(
                scale: 0.6 + 0.4 * _controller.value,
                child: child,
              ),
            ),
            child: Container(width: size, height: size, decoration: decoration),
          ),
          Container(width: size / 2, height: size / 2, decoration: decoration),
        ],
      ),
    );
  }
}
