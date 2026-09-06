import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_screen.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late Map<String, Object?> nativeState;
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('workout_notes/sleep_monitor/events');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
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
        case 'openSnoozedAlarmMission':
          nativeState = {
            ...nativeState,
            'alarm_at': DateTime(2026, 9, 4, 7, 1).toIso8601String(),
            'alarm_ringing': true,
            'alarm_snoozing': false,
            'alarm_state': 'ringing',
          };
          return nativeState;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  testWidgets('opens a monitored mission directly from an active snooze', (
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
    await _pumpUntil(tester, find.text('Open mission now'));

    expect(find.text('Alarm snoozed'), findsOneWidget);
    expect(find.text('Snooze 1 of 3'), findsOneWidget);
    expect(find.byKey(const Key('sleep-monitor-snoozing-card')), findsOneWidget);

    await tester.tap(find.text('Open mission now'));
    await _pumpUntilCall(tester, calls, 'openSnoozedAlarmMission');
    await _pumpUntilAbsent(tester, find.text('Open mission now'));

    expect(calls, contains('openSnoozedAlarmMission'));
    expect(calls, isNot(contains('dismissSnoozedAlarm')));

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
    await _pumpUntil(tester, find.text('Dismiss this snooze'));

    expect(find.text('Dismiss this snooze'), findsOneWidget);
    expect(find.text('Open mission now'), findsNothing);
    expect(find.text('Snooze 1 of 3'), findsOneWidget);

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

Future<void> _pumpUntilAbsent(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}
