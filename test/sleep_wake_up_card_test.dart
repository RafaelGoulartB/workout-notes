import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/widgets/sleep/sleep_wake_up_card.dart';

void main() {
  final deadline = DateTime.utc(2026, 9, 30, 10);

  SleepMonitorSession night({
    int? window = 30,
    DateTime? firedAt,
    String? trigger,
    int? feeling,
  }) => SleepMonitorSession(
    id: 'night',
    sleepEntryId: null,
    status: SleepMonitorSession.completed,
    startedAt: DateTime.utc(2026, 9, 30, 2),
    endedAt: firedAt ?? deadline,
    alarmAt: deadline,
    utcOffsetStartMinutes: -180,
    utcOffsetEndMinutes: -180,
    sensorMode: 'audio_bedside',
    algorithmVersion: 'audio-features-v5',
    timeInBedMinutes: 480,
    quietMinutes: null,
    noisyMinutes: null,
    estimatedSleepMinutes: 420,
    noiseEventCount: 0,
    signalQualityScore: 1,
    endReason: 'alarm',
    createdAt: DateTime.utc(2026, 9, 30, 2),
    smartWindowMinutes: window,
    alarmFiredAt: firedAt,
    alarmTrigger: trigger,
    wakeFeeling: feeling,
  );

  Future<void> pump(
    WidgetTester tester,
    SleepMonitorSession session, {
    ValueChanged<int>? onFeeling,
    String locale = 'pt',
  }) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SleepWakeUpCard(
              session: session,
              onFeeling: onFeeling ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an early smart ring says when, how early and why', (
    tester,
  ) async {
    int? answered;
    await pump(
      tester,
      night(
        firedAt: DateTime.utc(2026, 9, 30, 9, 47),
        trigger: SleepMonitorSession.triggerStirring,
      ),
      onFeeling: (value) => answered = value,
    );

    expect(find.text('Despertador inteligente'), findsOneWidget);
    expect(
      find.text('Tocou às 06:47, 13 min antes do horário'),
      findsOneWidget,
    );
    expect(find.textContaining('Você estava se mexendo'), findsOneWidget);
    expect(find.text('Despertar entre 06:30 e 07:00'), findsOneWidget);
    expect(find.text('Como você acordou?'), findsOneWidget);

    await tester.tap(find.text('Com energia'));
    await tester.pump();
    expect(answered, SleepMonitorSession.feelingRefreshed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a restless moment it rang at the wake time', (
    tester,
  ) async {
    await pump(
      tester,
      night(firedAt: deadline, trigger: SleepMonitorSession.triggerDeadline),
      locale: 'en',
    );
    expect(
      find.text(
        'No restless moment in the window: rang at 07:00, the wake time',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a fixed-time alarm only reports when it rang', (tester) async {
    await pump(tester, night(window: null, feeling: 2), locale: 'en');
    expect(find.text('Alarm rang at 07:00'), findsOneWidget);
    expect(find.text('Smart alarm'), findsNothing);
    expect(find.textContaining('Wake between'), findsNothing);
    final button = tester.widget<SegmentedButton<int>>(
      find.byKey(const Key('sleep-wake-feeling')),
    );
    expect(button.selected, {SleepMonitorSession.feelingOkay});
  });

  test('only nights whose alarm rang get the card', () {
    expect(SleepWakeUpCard.appliesTo(night()), isTrue);
    expect(
      SleepWakeUpCard.appliesTo(
        SleepMonitorSession.fromMap({
          ...night().toMap(),
          'alarm_at': null,
          'end_reason': 'user',
        }),
      ),
      isFalse,
    );
  });
}
