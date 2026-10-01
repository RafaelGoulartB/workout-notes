import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports how much a chat row at the bottom of a reversed list grew, during
/// layout, so the screen can correct the scroll position in the same frame
/// and keep what the user is reading from moving.
///
/// A reversed list measures its offset from the newest message, so anything
/// that grows below the reader pushes the text they are reading upwards. The
/// callback receives the height change in logical pixels (negative when the
/// row shrinks or is removed).
///
/// - [reportInitial]: the first layout counts as growth (a row that was just
///   appended). Rows built lazily while scrolling must leave it false.
/// - [trackChanges]: later height changes count too (the live answer that
///   streams in).
/// - [reportRemoval]: asked when the row is disposed; true when it really
///   left the list (the live answer turned into a stored message) and false
///   when the lazy list only recycled it far out of view.
///
/// A row far outside the viewport is not laid out at all, so its growth does
/// not move what is on screen and nothing needs to be corrected for it.
class AiScrollAnchor extends StatefulWidget {
  final bool reportInitial;
  final bool trackChanges;
  final bool Function()? reportRemoval;
  final ValueChanged<double> onHeightDelta;
  final Widget child;

  const AiScrollAnchor({
    super.key,
    required this.onHeightDelta,
    required this.child,
    this.reportInitial = false,
    this.trackChanges = false,
    this.reportRemoval,
  });

  @override
  State<AiScrollAnchor> createState() => _AiScrollAnchorState();
}

class _AiScrollAnchorState extends State<AiScrollAnchor> {
  double _height = 0;

  void _onLayout(double? previous, double current) {
    if (previous == null) {
      if (widget.reportInitial) widget.onHeightDelta(current);
    } else if (widget.trackChanges && current != previous) {
      widget.onHeightDelta(current - previous);
    }
    _height = current;
  }

  @override
  void dispose() {
    if (_height > 0 && (widget.reportRemoval?.call() ?? false)) {
      widget.onHeightDelta(-_height);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AnchorLayout(onLayout: _onLayout, child: widget.child);
}

class _AnchorLayout extends SingleChildRenderObjectWidget {
  final void Function(double? previous, double current) onLayout;

  const _AnchorLayout({required this.onLayout, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchorLayout(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAnchorLayout renderObject,
  ) => renderObject.onLayout = onLayout;
}

class _RenderAnchorLayout extends RenderProxyBox {
  void Function(double? previous, double current) onLayout;
  double? _previous;

  _RenderAnchorLayout(this.onLayout);

  @override
  void performLayout() {
    super.performLayout();
    final previous = _previous;
    final current = size.height;
    _previous = current;
    if (previous == null || previous != current) onLayout(previous, current);
  }
}
