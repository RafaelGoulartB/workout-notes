import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/traditional_alarm_repository.dart';
import 'package:workout_notes/screens/workout/traditional_alarms_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late List<Map<String, Object?>> nativeStates;
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('workout_notes/traditional_alarms/methods');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE traditional_alarms (
            id TEXT PRIMARY KEY, hour INTEGER NOT NULL, minute INTEGER NOT NULL,
            weekdays_json TEXT NOT NULL, enabled INTEGER NOT NULL,
            snooze_enabled INTEGER NOT NULL, snooze_minutes INTEGER NOT NULL,
            max_snoozes INTEGER NOT NULL,
            requires_mission INTEGER NOT NULL, next_trigger_at TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL
          )
        '''),
      ),
    );
    DatabaseHelper.overrideDatabase = database;

    final repository = TraditionalAlarmRepository();
    final missionAlarm = await repository.insert(
      hour: 7,
      minute: 0,
      weekdays: [1, 2, 3, 4, 5],
      snoozeEnabled: true,
      snoozeMinutes: 5,
      maxSnoozes: 3,
      requiresMission: true,
    );
    final regularAlarm = await repository.insert(
      hour: 8,
      minute: 0,
      weekdays: [1, 2, 3, 4, 5],
      snoozeEnabled: true,
      snoozeMinutes: 10,
      maxSnoozes: 3,
      requiresMission: false,
    );
    nativeStates = [
      {
        'id': missionAlarm.id,
        'enabled': true,
        'state': 'scheduled',
        'alarm_at_epoch_ms': DateTime(2026, 9, 4, 7, 5).millisecondsSinceEpoch,
        'snooze_count': 1,
        'max_snoozes': 3,
        'requires_mission': true,
      },
      {
        'id': regularAlarm.id,
        'enabled': true,
        'state': 'scheduled',
        'alarm_at_epoch_ms': DateTime(2026, 9, 4, 8, 10).millisecondsSinceEpoch,
        'snooze_count': 2,
        'max_snoozes': 3,
        'requires_mission': false,
      },
    ];
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'states':
          return nativeStates;
        case 'openSnoozedMission':
          final id = (call.arguments as Map<Object?, Object?>)['id'];
          nativeStates = nativeStates
              .map(
                (state) => state['id'] == id
                    ? {...state, 'state': 'ringing'}
                    : state,
              )
              .toList();
          return null;
        case 'dismissSnooze':
          final id = (call.arguments as Map<Object?, Object?>)['id'];
          nativeStates = nativeStates
              .map(
                (state) => state['id'] == id
                    ? {...state, 'snooze_count': 0}
                    : state,
              )
              .toList();
          return null;
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  testWidgets('shows active snoozes and exposes the correct action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TraditionalAlarmsScreen(),
      ),
    );
    await _pumpUntil(tester, find.text('Open mission now'));

    expect(find.text('Snooze 1 of 3'), findsOneWidget);
    expect(find.text('Snooze 2 of 3'), findsOneWidget);
    expect(find.text('Dismiss this snooze'), findsOneWidget);

    await tester.tap(find.text('Open mission now'));
    await _pumpUntilCall(tester, calls, 'openSnoozedMission');
    expect(calls, contains('openSnoozedMission'));
    await _pumpUntilButtonEnabled(tester, 'Dismiss this snooze');

    await tester.tap(find.text('Dismiss this snooze'));
    await _pumpUntilCall(tester, calls, 'dismissSnooze');
    expect(calls, contains('dismissSnooze'));
    await _pumpUntilFabEnabled(tester);

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

Future<void> _pumpUntilButtonEnabled(
  WidgetTester tester,
  String label,
) async {
  final buttonFinder = find.ancestor(
    of: find.text(label),
    matching: find.byType(FilledButton),
  );
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (buttonFinder.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(buttonFinder).onPressed != null) {
      return;
    }
  }
  fail('Timed out waiting for $label to become enabled');
}

Future<void> _pumpUntilFabEnabled(WidgetTester tester) async {
  final finder = find.byType(FloatingActionButton);
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<FloatingActionButton>(finder).onPressed != null) {
      return;
    }
  }
  fail('Timed out waiting for the alarm screen action to finish');
}
