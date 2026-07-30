import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_diagnostics.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_screen.dart';

Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  test(
    'diagnostics accepts a four-hour session with complete valid coverage',
    () {
      final start = DateTime.utc(2026, 7, 26, 22);
      final segments = List.generate(
        4,
        (index) => SleepMonitorSegment(
          id: '$index',
          sessionId: 'session',
          startedAt: start.add(Duration(hours: index)),
          durationSeconds: 3600,
          audioRmsDbfs: -40,
          audioPeakDbfs: -20,
          noiseScore: index.isEven ? 2 : 12,
          classification: index.isEven ? 'quiet' : 'noise',
          validFraction: 1,
          noiseBurstCount: index.isEven ? 0 : 1,
        ),
      );
      final session = SleepMonitorSession(
        id: 'session',
        sleepEntryId: 'entry',
        status: SleepMonitorSession.completed,
        startedAt: start,
        endedAt: start.add(const Duration(hours: 4)),
        utcOffsetStartMinutes: -180,
        utcOffsetEndMinutes: -180,
        sensorMode: 'audio',
        algorithmVersion: 'test',
        timeInBedMinutes: 240,
        quietMinutes: 120,
        noisyMinutes: 120,
        estimatedSleepMinutes: null,
        noiseEventCount: 2,
        signalQualityScore: 1,
        endReason: SleepMonitorSession.endUser,
        createdAt: start,
      );

      final diagnostics = SleepMonitorDiagnostics.fromSession(
        session,
        segments,
      );
      expect(diagnostics.timelineCoverage, 1);
      expect(diagnostics.signalCoverage, 1);
      expect(diagnostics.averageNoiseScore, 7);
      expect(diagnostics.isAcceptableForNextPhase, isTrue);
    },
  );

  test('diagnostics rejects a completed night without segments', () {
    final start = DateTime.utc(2026, 7, 26, 22);
    final session = SleepMonitorSession(
      id: 'empty',
      sleepEntryId: null,
      status: SleepMonitorSession.completed,
      startedAt: start,
      endedAt: start.add(const Duration(hours: 8)),
      utcOffsetStartMinutes: -180,
      utcOffsetEndMinutes: -180,
      sensorMode: 'audio',
      algorithmVersion: 'test',
      timeInBedMinutes: 480,
      quietMinutes: 0,
      noisyMinutes: 0,
      estimatedSleepMinutes: null,
      noiseEventCount: 0,
      signalQualityScore: 0,
      endReason: SleepMonitorSession.endUser,
      createdAt: start,
    );

    final diagnostics = SleepMonitorDiagnostics.fromSession(session, const []);
    expect(diagnostics.hasData, isFalse);
    expect(diagnostics.isAcceptableForNextPhase, isFalse);
  });

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

  testWidgets('result timeline renders quiet, noise and invalid segments', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 26, 22);
    await tester.pumpWidget(
      _localized(
        Scaffold(
          body: SleepMonitorTimeline(
            segments: [
              SleepMonitorSegment(
                id: '1',
                sessionId: 's',
                startedAt: start,
                durationSeconds: 30,
                audioRmsDbfs: -50,
                audioPeakDbfs: -30,
                noiseScore: 1,
                classification: 'quiet',
                validFraction: 1,
                noiseBurstCount: 0,
              ),
              SleepMonitorSegment(
                id: '2',
                sessionId: 's',
                startedAt: start.add(const Duration(seconds: 30)),
                durationSeconds: 30,
                audioRmsDbfs: -20,
                audioPeakDbfs: -8,
                noiseScore: 15,
                classification: 'noise',
                validFraction: 1,
                noiseBurstCount: 1,
              ),
              SleepMonitorSegment(
                id: '3',
                sessionId: 's',
                startedAt: start.add(const Duration(seconds: 60)),
                durationSeconds: 30,
                audioRmsDbfs: null,
                audioPeakDbfs: null,
                noiseScore: null,
                classification: 'invalid',
                validFraction: 0,
                noiseBurstCount: 0,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Sleep monitoring timeline with 3 segments'),
      findsOneWidget,
    );
  });

  testWidgets('noise chart renders captured scores', (tester) async {
    final start = DateTime.utc(2026, 7, 26, 22);
    final segments = List.generate(
      4,
      (index) => SleepMonitorSegment(
        id: '$index',
        sessionId: 's',
        startedAt: start.add(Duration(minutes: index * 30)),
        durationSeconds: 30,
        audioRmsDbfs: -40,
        audioPeakDbfs: -20,
        noiseScore: index * 4,
        classification: index < 3 ? 'quiet' : 'noise',
        validFraction: 1,
        noiseBurstCount: 0,
      ),
    );

    await tester.pumpWidget(
      _localized(
        Scaffold(
          body: SleepNoiseChart(
            segments: segments,
            emptyTitle: 'No data',
            noiseScoreLabel: 'Noise score',
            thresholdLabel: 'Threshold',
          ),
        ),
      ),
    );

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Threshold: 10'), findsOneWidget);
  });
}
