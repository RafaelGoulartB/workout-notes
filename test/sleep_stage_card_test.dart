import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/widgets/sleep/sleep_stage_card.dart';

void main() {
  testWidgets('renders the three estimated stage labels at 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final start = DateTime.utc(2026, 8, 1, 22);
    final session = _session(
      start,
      analysisStatus: SleepMonitorSession.analysisAvailable,
    );
    await tester.pumpWidget(
      _app(
        SleepStageCard(
          session: session,
          stages: [
            _epoch(start, SleepStageType.awake, 'awake'),
            _epoch(
              start.add(const Duration(seconds: 30)),
              SleepStageType.sleeping,
              'sleeping',
            ),
            _epoch(
              start.add(const Duration(seconds: 60)),
              SleepStageType.deep,
              'deep',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fases do sono'), findsOneWidget);
    expect(find.text('Acordado'), findsWidgets);
    expect(find.text('Dormindo'), findsWidgets);
    expect(find.text('Sono profundo estimado'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains that legacy recordings have no phases', (tester) async {
    final start = DateTime.utc(2026, 8, 1, 22);
    await tester.pumpWidget(
      _app(
        SleepStageCard(
          session: _session(
            start,
            analysisStatus: SleepMonitorSession.analysisLegacyUnavailable,
          ),
          stages: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fases do sono indispon\u00edveis'), findsOneWidget);
    expect(
      find.textContaining('grava\u00e7\u00e3o \u00e9 anterior'),
      findsOneWidget,
    );
  });
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('pt'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

SleepMonitorSession _session(
  DateTime start, {
  required String analysisStatus,
}) => SleepMonitorSession(
  id: 'session-1',
  sleepEntryId: 'entry-1',
  status: SleepMonitorSession.completed,
  startedAt: start,
  endedAt: start.add(const Duration(hours: 8)),
  utcOffsetStartMinutes: -180,
  utcOffsetEndMinutes: -180,
  sensorMode: 'audio',
  algorithmVersion: SleepMonitorSession.defaultAlgorithmVersion,
  timeInBedMinutes: 480,
  quietMinutes: 420,
  noisyMinutes: 60,
  estimatedSleepMinutes: 420,
  noiseEventCount: 0,
  signalQualityScore: 1,
  endReason: SleepMonitorSession.endUser,
  createdAt: start,
  analysisStatus: analysisStatus,
  awakeMinutes: 60,
  sleepingMinutes: 360,
  deepSleepMinutes: 60,
  unknownMinutes: 0,
  stageConfidence: 0.82,
);

SleepStageEpoch _epoch(DateTime startedAt, SleepStageType stage, String id) =>
    SleepStageEpoch(
      id: id,
      sessionId: 'session-1',
      startedAt: startedAt,
      durationSeconds: 30,
      stage: stage,
      confidence: 0.8,
      awakeProbability: stage == SleepStageType.awake ? 0.8 : 0.1,
      sleepingProbability: stage == SleepStageType.sleeping ? 0.8 : 0.1,
      deepProbability: stage == SleepStageType.deep ? 0.8 : 0.1,
      algorithmVersion: 'acoustic-staging-test',
    );
