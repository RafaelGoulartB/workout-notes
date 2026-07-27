import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_screen.dart';

Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
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
    expect(find.byType(Tooltip), findsNWidgets(3));
  });
}
