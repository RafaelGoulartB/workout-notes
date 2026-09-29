import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/load_generation.dart';

void main() {
  group('LoadGeneration', () {
    test('only the newest load is current', () {
      final generation = LoadGeneration();
      final first = generation.begin();
      expect(generation.isCurrent(first), isTrue);
      final second = generation.begin();
      expect(generation.isCurrent(first), isFalse);
      expect(generation.isCurrent(second), isTrue);
    });

    test('invalidate makes every load in flight stale', () {
      final generation = LoadGeneration();
      final token = generation.begin();
      generation.invalidate();
      expect(generation.isCurrent(token), isFalse);
    });

    test('a slow older load cannot overwrite a newer result', () async {
      final generation = LoadGeneration();
      var shown = '';

      Future<void> load(String label, Future<void> wait) async {
        final token = generation.begin();
        await wait;
        if (!generation.isCurrent(token)) return;
        shown = label;
      }

      final slow = Completer<void>();
      final fast = Completer<void>();
      final older = load('old', slow.future);
      final newer = load('new', fast.future);

      fast.complete();
      await newer;
      expect(shown, 'new');

      // The older read finishes last: it must not replace the newer data.
      slow.complete();
      await older;
      expect(shown, 'new');
    });
  });
}
