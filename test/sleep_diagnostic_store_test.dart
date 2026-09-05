import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/services/sleep_diagnostic_store.dart';

void main() {
  late Directory root;
  late SleepDiagnosticStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('sleep-diagnostics-test-');
    store = SleepDiagnosticStore(directoryProvider: () async => root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'disabled by default; only aggregates persist; disable removes archive',
    () async {
      final spool = {
        'session': {'id': 'night'},
        'segments': [],
        'unrelated': 'excluded',
      };
      await store.save(spool);
      expect(await store.latest(), isNull);
      await store.setEnabled(true);
      await store.save(spool);
      expect(
        await (await store.latest())!.readAsString(),
        isNot(contains('excluded')),
      );
      await store.setEnabled(false);
      expect(await store.latest(), isNull);
    },
  );
  test(
    'retention is bounded and identifiers cannot escape archive directory',
    () async {
      await store.setEnabled(true);
      for (var i = 0; i < 18; i++) {
        await store.save({
          'session': {'id': 'night-$i'},
          'segments': [],
        });
      }
      expect(await root.list().length, 14);
      await expectLater(
        store.save({
          'session': {'id': '../escape'},
        }),
        throwsFormatException,
      );
      final file = await store.latest();
      await file!.setLastModified(
        DateTime.now().subtract(const Duration(days: 15)),
      );
      await store.latest();
      expect(await file.exists(), false);
    },
  );
}
