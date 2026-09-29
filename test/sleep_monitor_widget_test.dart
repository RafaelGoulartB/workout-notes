import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_screen.dart';
import 'support/test_db.dart';

Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  setUpAll(initSqfliteFfiForTests);

  test('active elapsed time keeps advancing after the last native event', () {
    final now = DateTime.now();
    final state = SleepMonitorState(
      supported: true,
      microphoneGranted: true,
      status: SleepMonitorState.running,
      sessionId: 'session',
      startedAt: now.subtract(const Duration(minutes: 10)),
      updatedAt: now.subtract(const Duration(minutes: 5)),
      latestSegment: null,
      currentNoiseScore: null,
      errorCode: null,
      errorMessage: null,
    );

    expect(state.elapsed, greaterThanOrEqualTo(const Duration(minutes: 9)));
  });

  testWidgets('monitor screen explains Android-only support off Android', (
    tester,
  ) async {
    await tester.pumpWidget(_localized(const SleepMonitorScreen()));
    await tester.pump();

    if (defaultTargetPlatform != TargetPlatform.android) {
      expect(
        find.text('Monitoring is available only on Android.'),
        findsOneWidget,
      );
      expect(find.text('Monitor sleep'), findsOneWidget);
      expect(find.text('Start monitoring'), findsNothing);
    }
  });

  testWidgets(
    'result screen shows the persisted aggregate breakdown without epochs',
    (tester) async {
      final start = DateTime.utc(2026, 7, 29, 5);
      final session = _session(start, const Duration(hours: 4));
      final database = (await tester.runAsync(
        () => _resultDatabase(session),
      ))!;
      addTearDown(() async {
        DatabaseHelper.overrideDatabase = null;
        await database.close();
      });

      await tester.pumpWidget(
        _localized(SleepMonitorResultScreen(sessionId: session.id)),
      );
      await _pumpUntilLoaded(tester);

      expect(find.text('Time monitored'), findsOneWidget);
      // The stage card renders the persisted aggregates even though no
      // epochs are stored.
      expect(find.text('Sleep stages'), findsOneWidget);
      expect(find.text('Awake'), findsOneWidget);
      expect(find.text('Sleeping'), findsOneWidget);
      expect(find.text('Estimated deep sleep'), findsOneWidget);
    },
  );
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Sleep result screen did not finish loading');
}

Future<Database> _resultDatabase(SleepMonitorSession session) async {
  final database = await installTestDb();
  await database.insert('sleep_monitor_sessions', session.toMap());
  return database;
}

SleepMonitorSession _session(DateTime start, Duration duration) {
  return SleepMonitorSession(
    id: 's',
    sleepEntryId: null,
    status: SleepMonitorSession.completed,
    startedAt: start,
    endedAt: start.add(duration),
    utcOffsetStartMinutes: -180,
    utcOffsetEndMinutes: -180,
    sensorMode: 'audio',
    algorithmVersion: 'audio-features-v2',
    timeInBedMinutes: duration.inMinutes,
    quietMinutes: null,
    noisyMinutes: null,
    estimatedSleepMinutes: 200,
    noiseEventCount: 0,
    signalQualityScore: 1,
    analysisStatus: SleepMonitorSession.analysisAvailable,
    sleepOnsetAt: start.add(const Duration(minutes: 20)),
    finalWakeAt: start.add(duration).subtract(const Duration(minutes: 10)),
    sleepLatencyMinutes: 20,
    awakeMinutes: 20,
    sleepingMinutes: 150,
    deepSleepMinutes: 30,
    unknownMinutes: 10,
    awakeningCount: 2,
    sleepEfficiency: 0.83,
    stageConfidence: 0.79,
    stageAlgorithmVersion: 'sleep-stage-v2',
    endReason: SleepMonitorSession.endUser,
    createdAt: start,
  );
}