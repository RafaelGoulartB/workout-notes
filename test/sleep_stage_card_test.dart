import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/widgets/sleep/sleep_stage_card.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  testWidgets(
    'bedside result shows uncertainty without deep stage or confidence percent',
    (tester) async {
      final session = bedsideSession().copyWith(
        analysisStatus: SleepMonitorSession.analysisAvailable,
        awakeMinutes: 0,
        sleepingMinutes: 0,
        unknownMinutes: 60,
      );
      await tester.pumpWidget(_app(SleepStageCard(session: session)));
      await tester.pumpAndSettle();
      final loc = AppLocalizations.of(
        tester.element(find.byType(SleepStageCard)),
      )!;
      expect(find.text(loc.sleepWakeEstimateTitle), findsOneWidget);
      expect(find.text(loc.sleepStageUnknown), findsOneWidget);
      expect(find.text(loc.sleepStageDeepEstimated), findsNothing);
      expect(find.byType(Chip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('renders the three estimated stage aggregates at 320 px', (
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
    await tester.pumpWidget(_app(SleepStageCard(session: session)));
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
