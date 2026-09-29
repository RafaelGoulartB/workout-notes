import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/widgets/ai/ai_thumbnail.dart';

void main() {
  testWidgets('thumbnails decode near their drawn size, scaled by DPR', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    late ImageProvider provider;
    final source = MemoryImage(Uint8List(8));
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          provider = aiThumbnailProvider(
            context,
            source,
            width: 104,
            height: 104,
          );
          return const SizedBox();
        },
      ),
    );

    expect(provider, isA<ResizeImage>());
    final resized = provider as ResizeImage;
    // 104 logical px * 3 (DPR) * 4/3 headroom for 4:3 photos = 416.
    expect(resized.width, 416);
    expect(resized.height, 416);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(resized.imageProvider, same(source));
  });
}
