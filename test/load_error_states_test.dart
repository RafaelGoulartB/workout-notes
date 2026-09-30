import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/screens/planning/periodization_home_screen.dart';
import 'package:workout_notes/screens/sleep/sleep_tracker_screen.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/widgets/goals/goals_section.dart';

/// A database that opens but lacks every feature table, so each read fails.
Future<Database> _bareDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
      ),
    ),
  );
  DatabaseHelper.overrideDatabase = db;
  return db;
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const sleepEvents = MethodChannel('workout_notes/sleep_monitor/events');

  setUp(() async {
    db = await _bareDatabase();
    // The sleep monitor talks to Android; here it just answers nothing.
    SleepMonitorService.instance.resetInitializationForTest();
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, (_) async {
      return null;
    });
    messenger.setMockMethodCallHandler(sleepEvents, (_) async => null);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
    messenger.setMockMethodCallHandler(sleepEvents, null);
    DatabaseHelper.overrideDatabase = null;
    await db.close();
  });

  testWidgets('goals: a failed read is an error, not "no goals yet"', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _app(
          GoalsSection(
            db: DatabaseHelper.instance,
            settingsRepo: SettingsRepository(),
          ),
        ),
      );
    });
    await _settle(tester);

    expect(find.byKey(const Key('load-error-banner-retry')), findsOneWidget);
    expect(find.text('Could not load your data.'), findsOneWidget);
  });

  testWidgets('planning: a failed load ends in an error with retry', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app(const PeriodizationHomeScreen()));
    });
    await _settle(tester);

    // No forever spinner, no misleading "create your first plan".
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('load-error-retry')), findsOneWidget);
  });

  testWidgets('sleep: a failed load ends in an error with retry', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app(const SleepTrackerScreen()));
    });
    await _settle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('load-error-retry')), findsOneWidget);
  });
}
