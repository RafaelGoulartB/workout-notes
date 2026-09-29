import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/body_stats_controller.dart';
import 'package:workout_notes/screens/workout/body_stats_screen.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

/// Pumps until [finder] shows up, letting real async SQLite work complete.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE body_measurements (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              value REAL NOT NULL,
              secondary_value REAL,
              unit TEXT NOT NULL DEFAULT 'kg',
              date TEXT NOT NULL,
              comment TEXT,
              time_of_day TEXT,
              is_fasted INTEGER DEFAULT 0,
              photos_paths TEXT,
              side TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
          );
          await db.insert('app_settings', {
            'key': 'nutrition_profile_height_cm',
            'value': '180',
          });
        },
      ),
    );
    DatabaseHelper.overrideDatabase = db;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await db.close();
  });

  Future<void> insertWeights(int weeks) async {
    final today = DateTime.now();
    for (var i = 0; i < weeks * 7; i += 2) {
      final date = today.subtract(Duration(days: i));
      await db.insert('body_measurements', {
        'id': 'w$i',
        'type': 'weight',
        // Losing weight: older entries are heavier.
        'value': 80.0 + i * 0.05,
        'unit': 'kg',
        'date': date.toIso8601String().substring(0, 10),
        'created_at': date.toIso8601String(),
      });
    }
  }

  testWidgets('shows the empty state without measurements', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const BodyStatsScreen()));
    await _pumpUntil(tester, find.text('Not enough data yet'));

    expect(find.text('Progress stats'), findsOneWidget);
    expect(find.text('Not enough data yet'), findsOneWidget);
  });

  testWidgets('renders the stats sections and switches chart tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => insertWeights(8));

    await tester.pumpWidget(_app(const BodyStatsScreen()));
    await _pumpUntil(tester, find.text('Weekly average'));

    expect(find.text('Weekly average'), findsOneWidget);
    expect(find.text('TRENDS'), findsOneWidget);
    expect(find.text('RATE OF CHANGE'), findsOneWidget);
    expect(find.text('CONSISTENCY'), findsOneWidget);
    // Height is configured, so the BMI metric is part of the rate card.
    expect(find.text('BMI'), findsOneWidget);

    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    expect(find.text('Weekly average'), findsOneWidget);

    await tester.tap(find.text('4 weeks'));
    await tester.pumpAndSettle();
    expect(find.text('TRENDS'), findsOneWidget);
  });

  group('BodyStatsController helpers', () {
    test('pace verdicts follow the 1 percent per week threshold', () {
      expect(BodyStatsController.paceFor(null, null), isNull);
      expect(BodyStatsController.paceFor(0.01, 0.01), BodyPace.stable);
      expect(BodyStatsController.paceFor(0.4, 0.05), BodyPace.stable);
      expect(BodyStatsController.paceFor(-1.2, -1.5), BodyPace.aggressive);
      expect(BodyStatsController.paceFor(-0.5, -0.6), BodyPace.sustainable);
    });

    test('BMI categories use the adult boundaries', () {
      expect(BodyStatsController.bmiCategory(18.4), BmiCategory.under);
      expect(BodyStatsController.bmiCategory(24.9), BmiCategory.normal);
      expect(BodyStatsController.bmiCategory(25), BmiCategory.over);
      expect(BodyStatsController.bmiCategory(30), BmiCategory.obese);
    });

    test('closestValue prefers the first entry on or after the date', () {
      final rows = [
        {'date': '2026-03-20', 'value': 78.0},
        {'date': '2026-03-10', 'value': 79.0},
        {'date': '2026-03-01', 'value': 80.0},
      ];
      expect(
        BodyStatsController.closestValue(rows, DateTime(2026, 3, 5)),
        79.0,
      );
      // After the newest entry, fall back to the latest one before.
      expect(
        BodyStatsController.closestValue(rows, DateTime(2026, 4, 1)),
        78.0,
      );
      expect(
        BodyStatsController.closestValue(const [], DateTime(2026)),
        isNull,
      );
    });

    test('signed values carry an explicit plus or minus', () {
      final controller = BodyStatsController(initialTypeId: 'weight');
      addTearDown(controller.dispose);
      expect(controller.signed(0.34), '+0.3');
      expect(controller.signed(-0.34), '-0.3');
      expect(controller.signed(0), '0.0');
      expect(controller.signed(null), '--');
      expect(controller.value(72.456), '72.5');
    });
  });
}
