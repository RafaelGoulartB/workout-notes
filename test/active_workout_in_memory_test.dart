import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/services/rest_timer_service.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

/// The done/undone circle of a set row.
final _setCircle = find.byWidgetPredicate(
  (w) =>
      w is AnimatedContainer &&
      w.constraints == const BoxConstraints.tightFor(width: 26, height: 26),
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
  late Database db;

  setUpAll(() => Intl.defaultLocale = 'en');
  tearDownAll(() => Intl.defaultLocale = null);

  setUp(() async {
    db = await installAiTestDb();
    await seedStrengthBasics(db);
    await seedWorkout(
      db,
      'live',
      date: '2026-09-15',
      finished: false,
      exercises: [
        ('bench', [seedSet(100, 5, done: false), seedSet(100, 5, done: false)]),
      ],
    );
  });

  tearDown(uninstallAiTestDb);

  testWidgets('toggling, adding and deleting a set update it in memory', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ActiveWorkoutScreen(workoutId: 'live'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);
    expect(find.text('0/2'), findsOneWidget);
    expect(_setCircle, findsNWidgets(2));

    // Out-of-band edit: a full reload would now count only one working set.
    await tester.runAsync(
      () =>
          db.rawUpdate("UPDATE sets SET is_warmup = 1 WHERE id = 'live-e0-s1'"),
    );

    await tester.tap(_setCircle.first);
    await _settle(tester);
    // Counts follow the tap, and nothing was re-read from the database.
    expect(find.text('1/2'), findsOneWidget);
    final done = await tester.runAsync(
      () => db.query('sets', where: "id = 'live-e0-s0'"),
    );
    expect(done!.single['is_complete'], 1);

    await tester.tap(_setCircle.first);
    await _settle(tester);
    expect(find.text('0/2'), findsOneWidget);

    // Add a set (the "add set" button of the exercise card).
    await tester.tap(find.byIcon(Icons.add).first);
    await _settle(tester);
    expect(_setCircle, findsNWidgets(3));
    expect(find.text('0/3'), findsOneWidget);
    final rows = await tester.runAsync(
      () => db.query('sets', where: "exercise_entry_id = 'live-e0'"),
    );
    expect(rows, hasLength(3));

    // Completing a set starts the rest timer; it must not outlive the test.
    RestTimerService.instance.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a deleted set can be restored from the snackbar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ActiveWorkoutScreen(workoutId: 'live'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);
    final before = await tester.runAsync(
      () => db.query('sets', orderBy: 'order_index'),
    );
    expect(_setCircle, findsNWidgets(2));

    await tester.tap(find.byTooltip('Delete set').first);
    await _settle(tester);
    expect(_setCircle, findsNWidgets(1));
    expect(find.text('Set deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(_setCircle, findsNWidgets(2));
    final after = await tester.runAsync(
      () => db.query('sets', orderBy: 'order_index'),
    );
    expect(after, before);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
