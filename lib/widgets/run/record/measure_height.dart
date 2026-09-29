import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's laid-out height, without affecting layout. Lets the run
/// sheet size itself from what it actually renders instead of from an estimate
/// that has to be kept in sync by hand.
class MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double>? onHeight;

  const MeasureHeight({
    super.key,
    required this.onHeight,
    required Widget super.child,
  });

  @override
  RenderMeasureHeight createRenderObject(BuildContext context) =>
      RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMeasureHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class RenderMeasureHeight extends RenderProxyBox {
  RenderMeasureHeight(this.onHeight);

  ValueChanged<double>? onHeight;
  double _reported = 0;

  @override
  void performLayout() {
    super.performLayout();
    final callback = onHeight;
    if (callback == null) return;
    final height = size.height;
    if ((height - _reported).abs() < 1) return;
    _reported = height;
    // setState is illegal during layout — report on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(height));
  }
}
