import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

Future<void> settle(WidgetTester tester, {int millis = 300}) async {
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
    await seedWorkout(
      db,
      'w2',
      date: '2026-09-08',
      routineId: 'ppl',
      dayId: 'push',
      comment: 'Ombro incomodou',
      exercises: [
        (
          'bench',
          [seedSet(60, 10, warmup: true), seedSet(100, 5), seedSet(120, 5)],
        ),
      ],
    );
    await seedWorkout(
      db,
      'w3',
      date: '2026-09-15',
      routineId: 'ppl',
      dayId: 'push',
      exercises: [
        ('bench', [seedSet(110, 6), seedSet(110, 6)]),
      ],
    );
  });

  tearDown(uninstallAiTestDb);

  Future<void> pump(WidgetTester tester, String id) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('pt'),
          home: WorkoutDetailScreen(workoutId: id),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
  }

  testWidgets('shows hero, records, comparison and the sets table', (
    tester,
  ) async {
    await pump(tester, 'w2');

    expect(find.text('Push A'), findsWidgets);
    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Ombro incomodou'), findsOneWidget);
    // Hero numbers: 100x5 + 120x5 = 1100 kg, 2 working sets.
    expect(find.text('1,1 t'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('RECORDES NESTE TREINO'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('RECORDES NESTE TREINO'), findsOneWidget);
    expect(find.text('1RM estimado · 120 kg × 5'), findsOneWidget);
    expect(find.text('Maior carga · 120 kg × 5'), findsOneWidget);

    // Comparison against the previous Push A session (1000 kg -> 1100 kg).
    expect(find.text('COMPARADO À ÚLTIMA VEZ'), findsOneWidget);
    expect(find.text('vs Push A de 1 de set.'), findsOneWidget);
    expect(find.text('Volume +100 kg'), findsOneWidget);

    // Exercise card: warm-up muted with "A", record star on the 120 set.
    await tester.scrollUntilVisible(
      find.text('A'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_rounded), findsWidgets);
  });

  testWidgets('first session has no comparison or record sections', (
    tester,
  ) async {
    await pump(tester, 'w1');
    expect(find.text('RECORDES NESTE TREINO'), findsNothing);
    expect(find.text('COMPARADO À ÚLTIMA VEZ'), findsNothing);
    expect(find.text('Bench Press'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and removes the workout', (
    tester,
  ) async {
    await pump(tester, 'w3');

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir Treino'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir Treino?'), findsOneWidget);

    // Cancel keeps the workout.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    final still = await tester.runAsync(
      () => WorkoutRepository().getWorkout('w3'),
    );
    expect(still, isNotNull);

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir Treino'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
    await settle(tester);
    await tester.pumpAndSettle();
    final gone = await tester.runAsync(
      () => WorkoutRepository().getWorkout('w3'),
    );
    expect(gone, isNull);
  });
}
