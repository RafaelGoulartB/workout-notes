import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/edit_workout_screen.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

void main() {
  late Database db;

  setUpAll(() => Intl.defaultLocale = 'pt_BR');
  tearDownAll(() => Intl.defaultLocale = null);

  setUp(() async {
    db = await installAiTestDb();
    await seedStrengthBasics(db);
    await seedWorkout(
      db,
      'w1',
      date: '2026-09-01',
      routineId: 'ppl',
      dayId: 'push',
      exercises: [
        ('bench', [seedSet(100, 5), seedSet(100, 5)]),
      ],
    );
  });

  tearDown(uninstallAiTestDb);

  testWidgets('shows date, feedback and exercise sections and edits a set', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: EditWorkoutScreen(workoutId: 'w1'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });

    expect(find.text('DATA E HORÁRIO'), findsOneWidget);
    expect(find.text('AVALIAÇÃO DO TREINO'), findsOneWidget);
    expect(find.text('EXERCÍCIOS'), findsOneWidget);
    expect(find.text('1 de setembro de 2026'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('1h 00min'), findsOneWidget);

    await tester.tap(find.text('100.0').first);
    await tester.pumpAndSettle();
    expect(find.text('Bench Press · Série 1'), findsOneWidget);
  });
}
