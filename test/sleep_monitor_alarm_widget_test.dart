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
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('workout_notes/sleep_monitor/events');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
          );
          await db.insert('app_settings', {
            'key': 'sleep_alarm_default_minutes',
            'value': '420',
          });
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
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
          return {
            'supported': true,
            'microphone_granted': true,
            'status': 'idle',
            'updated_at': DateTime.now().toIso8601String(),
            'exact_alarm_granted': true,
            'full_screen_intent_granted': true,
          };
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
    DatabaseHelper.overrideDatabase = null;
    await database.close();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows the alarm-first daily monitoring experience', (
    tester,
  ) async {
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(
      find.text('Your wake-up time'),
      findsOneWidget,
      reason: 'Rendered text: $renderedText; calls: $calls',
    );
    expect(find.text('Next alarm'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('− 15 min'), findsOneWidget);
    expect(find.text('+ 15 min'), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    expect(find.textContaining('Start and wake at'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pump();
    expect(find.text('System alarm sound + vibration'), findsNothing);
    expect(find.text('Prepare your phone'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
