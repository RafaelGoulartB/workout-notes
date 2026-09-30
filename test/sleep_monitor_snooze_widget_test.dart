import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_screen.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'support/sleep_bedside_fixture.dart';
import 'support/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, Object?> nativeState;
  late Database database;
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('workout_notes/sleep_monitor/events');

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await installTestDb();
    nativeState = {
      'supported': true,
      'microphone_granted': true,
      'status': 'completed',
      'session_id': 'night-snooze',
      'started_at': DateTime(2026, 9, 3, 23).toIso8601String(),
      'updated_at': DateTime(2026, 9, 4, 7).toIso8601String(),
      'alarm_at': DateTime(2026, 9, 4, 7, 5).toIso8601String(),
      'monitor_mode': 'alarm_with_mission',
      'mission_status': 'pending',
      'alarm_ringing': false,
      'alarm_snoozing': true,
      'alarm_state': 'scheduled',
      'snooze_count': 1,
      'max_snoozes': 3,
      'alarm_dismissed': false,
      'end_reason': 'alarm',
      'exact_alarm_granted': true,
      'full_screen_intent_granted': true,
    };
    calls.clear();
    // initialize() is shared per process; every case starts from scratch.
    SleepMonitorService.instance.resetInitializationForTest();
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
        case 'getAlarmCapabilities':
          return {
            'exact_alarm_granted': true,
            'full_screen_intent_granted': true,
          };
        case 'listPendingSessions':
          return <Object?>[];
        case 'dismissSnoozedAlarm':
          nativeState = {
            ...nativeState,
            'alarm_snoozing': false,
            'alarm_state': 'completed',
            'alarm_dismissed': true,
            'alarm_dismiss_method': 'button',
          };
          return nativeState;
        case 'openAlarmScreen':
          // The native screen opens over the app; a snooze stays silent.
          return nativeState;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
    await uninstallTestDb();
  });

  test('ringing and snoozed alarms both wait for an answer', () {
    final ringing = SleepMonitorState.fromMap({
      'status': 'completed',
      'alarm_ringing': true,
      'alarm_state': 'ringing',
    });
    expect(ringing.isAlarmRinging, isTrue);
    expect(ringing.isAlarmSnoozing, isFalse);
    expect(ringing.isAlarmPending, isTrue);

    final dismissed = SleepMonitorState.fromMap({
      'status': 'completed',
      'alarm_ringing': false,
      'alarm_state': 'completed',
      'alarm_dismissed': true,
      'snooze_count': 1,
    });
    expect(dismissed.isAlarmPending, isFalse);
  });

  testWidgets('completes the mission early from a snooze without ringing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SleepMonitorScreen(),
      ),
    );
    await _pumpUntil(tester, find.text('Complete mission now'));

    expect(find.byKey(const Key('sleep-monitor-alarm')), findsOneWidget);
    expect(find.text('Snoozed until'), findsOneWidget);
    expect(find.text('Snooze 1 of 3'), findsOneWidget);
    expect(find.text('Mission pending'), findsOneWidget);

    await tester.tap(find.text('Complete mission now'));
    await _pumpUntilCall(tester, calls, 'openAlarmScreen');

    expect(calls, isNot(contains('dismissSnoozedAlarm')));
    // Backing out of the native screen leaves the snooze in place.
    expect(find.text('Complete mission now'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('offers occurrence dismissal when the snooze has no mission', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeState = {
      ...nativeState,
      'monitor_mode': 'alarm_without_mission',
      'mission_status': 'unconfigured',
    };
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SleepMonitorScreen(),
      ),
    );
    await _pumpUntil(tester, find.text('Turn off alarm'));

    expect(find.text('Complete mission now'), findsNothing);
    expect(find.text('Mission pending'), findsNothing);
    expect(find.text('Snooze 1 of 3'), findsOneWidget);

    await tester.tap(find.text('Turn off alarm'));
    await _pumpUntilCall(tester, calls, 'dismissSnoozedAlarm');
    expect(calls, isNot(contains('openAlarmScreen')));

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an alarm answered earlier does not hijack the monitor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // Results open only while the app is in the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // The native state keeps the dismissal until the next night starts.
    nativeState = {
      ...nativeState,
      'alarm_snoozing': false,
      'alarm_state': 'completed',
      'alarm_dismissed': true,
      'alarm_dismiss_method': 'emergency_500_taps',
    };
    // Its result exists, so only the "already answered" rule keeps it away.
    await tester.runAsync(
      () => database.insert('sleep_monitor_sessions', {
        ...bedsideSession(reason: 'alarm').toMap(),
        'id': 'night-snooze',
      }),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SleepMonitorScreen(),
      ),
    );
    await _pumpUntil(tester, find.text('Start monitoring'));
    await _settleAsync(tester);

    expect(find.text('Monitoring result'), findsNothing);
    expect(find.text('Start monitoring'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('skips the result of a night that is no longer stored', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // Results open only while the app is in the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    nativeState = {
      ...nativeState,
      'monitor_mode': 'alarm_without_mission',
      'mission_status': 'unconfigured',
    };
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SleepMonitorScreen(),
      ),
    );
    await _pumpUntil(tester, find.text('Turn off alarm'));

    // Dismissed while the screen is open, but the session was never saved.
    await tester.tap(find.text('Turn off alarm'));
    await _pumpUntil(tester, find.text('Start monitoring'));
    await _settleAsync(tester);

    expect(find.text('Result not found.'), findsNothing);
    expect(find.text('Monitoring result'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('leads a ringing alarm to its mission instead of a new night', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeState = {
      ...nativeState,
      'alarm_ringing': true,
      'alarm_snoozing': false,
      'alarm_state': 'ringing',
      'snooze_count': 0,
    };
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SleepMonitorScreen(),
      ),
    );
    await _pumpUntil(tester, find.text('Open mission'));

    expect(find.text('Alarm ringing'), findsOneWidget);
    expect(find.text('Start monitoring'), findsNothing);

    await tester.tap(find.text('Open mission'));
    await _pumpUntilCall(tester, calls, 'openAlarmScreen');

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntilCall(
  WidgetTester tester,
  List<String> calls,
  String method,
) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (calls.contains(method)) return;
  }
  fail('Timed out waiting for $method');
}

/// Lets the real database calls behind a pending navigation finish.
Future<void> _settleAsync(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
