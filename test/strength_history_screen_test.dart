import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/strength/strength_history_screen.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
  late T result;
  await tester.runAsync(() async {
    result = await body();
  });
  return result;
}

Future<void> settle(WidgetTester tester, {int millis = 250}) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration(milliseconds: millis));
    await tester.pump();
  });
}

void main() {
  late Database db;

  setUpAll(() => Intl.defaultLocale = 'pt_BR');
  tearDownAll(() => Intl.defaultLocale = null);

  setUp(() async {
    db = await installAiTestDb();
    await seedStrengthBasics(db);
    // These fixtures assert titles as seeded; skip the one-off inference.
    await db.insert('app_settings', {
      'key': StrengthRoutineDayInference.flagKey,
      'value': 'test',
    });
  });

  tearDown(uninstallAiTestDb);

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('pt'),
          home: StrengthHistoryScreen(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
  }

  testWidgets('shows the empty state without workouts', (tester) async {
    await pump(tester);
    expect(find.text('Nenhum treino ainda'), findsOneWidget);
  });

  testWidgets('lists workouts by month with titles, volume and records', (
    tester,
  ) async {
    await real(tester, () async {
      await seedWorkout(
        db,
        'w1',
        date: '2026-08-30',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          ('bench', [seedSet(100, 5), seedSet(100, 5)]),
        ],
      );
      await seedWorkout(
        db,
        'w2',
        date: '2026-09-10',
        routineId: 'ppl',
        exercises: [
          ('bench', [seedSet(105, 5)]),
        ],
      );
      await seedWorkout(
        db,
        'w3',
        date: '2026-09-12',
        exercises: [
          ('row', [seedSet(80, 10), seedSet(80, 10)]),
        ],
      );
    });
    await pump(tester);

    expect(find.textContaining('3 treinos · 3,1 t'), findsOneWidget);
    expect(find.text('Setembro de 2026'), findsOneWidget);
    expect(find.text('2 treinos · 2,1 t'), findsOneWidget);
    expect(find.text('Agosto de 2026'), findsOneWidget);
    // Day name, routine fallback, and muscle groups for a free workout.
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Costas'), findsWidgets);
    expect(find.text('1,6 t'), findsOneWidget);
    // The bench PR of 2026-09-10 shows the trophy badge.
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);
  });

  testWidgets('search narrows the list and can be cleared', (tester) async {
    await real(tester, () async {
      await seedWorkout(
        db,
        'w1',
        date: '2026-09-01',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          ('bench', [seedSet(100, 5)]),
        ],
      );
      await seedWorkout(
        db,
        'w2',
        date: '2026-09-02',
        routineId: 'ppl',
        dayId: 'pull',
        exercises: [
          ('row', [seedSet(80, 8)]),
        ],
      );
    });
    await pump(tester);
    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Pull A'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'pull a');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Push A'), findsNothing);
    expect(find.text('Pull A'), findsOneWidget);
    expect(find.text('Limpar filtros'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Nenhum treino encontrado'), findsOneWidget);

    await tester.tap(find.text('Limpar filtros'));
    await settle(tester);
    expect(find.text('Push A'), findsOneWidget);
  });

  testWidgets('muscle filter keeps only matching workouts', (tester) async {
    await real(tester, () async {
      await seedWorkout(
        db,
        'w1',
        date: '2026-09-01',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          ('bench', [seedSet(100, 5)]),
        ],
      );
      await seedWorkout(
        db,
        'w2',
        date: '2026-09-02',
        routineId: 'ppl',
        dayId: 'pull',
        exercises: [
          ('row', [seedSet(80, 8)]),
        ],
      );
    });
    await pump(tester);

    final chip = find.byKey(const ValueKey('strengthHistoryMuscle'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<String>).at(2));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(find.text('Push A'), findsNothing);
    expect(find.text('Pull A'), findsOneWidget);
  });
}
