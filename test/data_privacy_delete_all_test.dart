import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/settings/data_privacy_screen.dart';

import 'support/test_db.dart';

void main() {
  late Database database;

  setUpAll(initSqfliteFfiForTests);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(uninstallTestDb);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DataPrivacyScreen(),
      ),
    );
    await tester.pump();
  }

  /// SQLite runs on real time; give it room between frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> confirmDeleteAll(WidgetTester tester) async {
    await tester.tap(find.text('Delete All Workout History'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Delete Everything'));
    await tester.pump();
  }

  testWidgets('the delete-all subtitle is its own localized string', (
    tester,
  ) async {
    await tester.runAsync(() async => database = await installTestDb());
    await open(tester);

    expect(
      find.text(
        'Deletes all workouts, sleep, nutrition and body measurements',
      ),
      findsOneWidget,
    );
  });

  testWidgets('delete all wipes the data, reseeds meal types and confirms', (
    tester,
  ) async {
    await tester.runAsync(() async {
      database = await installTestDb(seedMealTypes: true);
      await database.insert('sleep_entries', {
        'id': 'entry',
        'date': '2026-09-01',
        'sleep_minutes': 400,
        'source': 'manual',
        'created_at': '2026-09-01T07:00:00.000',
      });
    });
    await open(tester);

    await confirmDeleteAll(tester);
    await settle(tester);

    expect(find.text('History deleted'), findsOneWidget);
    final sleep = await tester.runAsync(() => database.query('sleep_entries'));
    final types = await tester.runAsync(() => database.query('meal_types'));
    expect(sleep, isEmpty);
    expect(types, hasLength(4));
    // The progress dialog is gone.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failure shows a localized error and keeps the data', (
    tester,
  ) async {
    await tester.runAsync(() async {
      database = await installTestDb(seedMealTypes: true);
      await database.insert('sleep_entries', {
        'id': 'entry',
        'date': '2026-09-01',
        'sleep_minutes': 400,
        'source': 'manual',
        'created_at': '2026-09-01T07:00:00.000',
      });
      await database.execute('''
        CREATE TRIGGER block_meal_type_delete BEFORE DELETE ON meal_types
        BEGIN SELECT RAISE(ABORT, 'blocked'); END
      ''');
    });
    await open(tester);

    await confirmDeleteAll(tester);
    await settle(tester);

    expect(find.textContaining('Could not delete history'), findsOneWidget);
    expect(find.text('History deleted'), findsNothing);
    final sleep = await tester.runAsync(() => database.query('sleep_entries'));
    expect(sleep, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
