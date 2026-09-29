import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Wraps [provider] so it is decoded near the size it is drawn at instead of
/// at the full resolution of the picked photo (up to 1600 px). Only the
/// on-screen thumbnail is affected; the original bytes/file stay untouched
/// for the zoom viewer and for analysis.
///
/// Thumbnails use `BoxFit.cover`, whose crop depends on the photo's aspect
/// ratio, so the decode is bounded by a square that fits the photo with
/// headroom for 4:3 pictures rather than by the box itself.
ImageProvider aiThumbnailProvider(
  BuildContext context,
  ImageProvider provider, {
  required double width,
  required double height,
}) {
  final pixelRatio = MediaQuery.devicePixelRatioOf(context);
  final side = (math.max(width, height) * pixelRatio * 4 / 3).ceil();
  return ResizeImage(
    provider,
    width: side,
    height: side,
    policy: ResizeImagePolicy.fit,
  );
}
