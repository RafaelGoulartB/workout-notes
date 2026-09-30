import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_screen.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'support/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  late Map<String, Object?> nativeState;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('workout_notes/sleep_monitor/events');

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    calls.clear();
    nativeState = {
      'supported': true,
      'microphone_granted': true,
      'status': 'idle',
      'updated_at': DateTime.now().toIso8601String(),
      'exact_alarm_granted': true,
      'full_screen_intent_granted': true,
    };
    // initialize() is shared per process; every case starts from scratch.
    SleepMonitorService.instance.resetInitializationForTest();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await installTestDb();
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getCapabilities':
          return {
            'supported': true,
            'microphone_granted': true,
            'exact_alarm_granted': true,
            'full_screen_intent_granted': true,
          };
        case 'getState':
          return nativeState;
        case 'getLiveLevel':
          return {'level_dbfs': -40.0, 'baseline_dbfs': -55.0};
        case 'getAlarmCapabilities':
          return {
            'exact_alarm_granted': true,
            'full_screen_intent_granted': true,
          };
        case 'listPendingSessions':
          return <Object?>[];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
    await uninstallTestDb();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows a minimal wake-time screen before monitoring', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpMonitor(tester, until: 'Planned wake-up');

    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(
      find.text('Planned wake-up'),
      findsOneWidget,
      reason: 'Rendered text: $renderedText; calls: $calls',
    );
    expect(find.byKey(const Key('sleep-monitor-wake-time')), findsOneWidget);
    expect(find.byTooltip('− 15 min'), findsOneWidget);
    expect(find.byTooltip('+ 15 min'), findsOneWidget);
    expect(find.byKey(const Key('sleep-monitor-mode')), findsOneWidget);
    expect(find.text('Start monitoring'), findsOneWidget);
    // Tips stay out of the way until asked for.
    expect(find.text('For a reliable analysis'), findsNothing);

    await tester.tap(find.byTooltip('Before you sleep'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('For a reliable analysis'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'shows the wake time, live waves and a quiet stop while running',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      nativeState = {
        ...nativeState,
        'status': 'running',
        'session_id': 'night',
        'started_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'alarm_at': DateTime.now()
            .add(const Duration(hours: 7))
            .toIso8601String(),
        'monitor_mode': 'alarm_with_mission',
        'mission_status': 'pending',
      };

      await _pumpMonitor(tester, until: 'Stop monitoring only');

      expect(find.byKey(const Key('sleep-monitor-wake-time')), findsOneWidget);
      expect(find.text('Mission pending'), findsOneWidget);
      expect(find.text('Listening to the room'), findsOneWidget);
      expect(find.text('Discard session'), findsNothing);
      // The waves sample the native level while they are on screen.
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, contains('getLiveLevel'));

      await tester.tap(find.byKey(const Key('sleep-monitor-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Discard session'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

Future<void> _pumpMonitor(WidgetTester tester, {required String until}) async {
  await tester.pumpWidget(
    const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SleepMonitorScreen(),
    ),
  );
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text(until).evaluate().isNotEmpty) break;
  }
}
