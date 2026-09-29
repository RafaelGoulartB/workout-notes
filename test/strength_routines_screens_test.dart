import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/routine_day_editor_screen.dart';
import 'package:workout_notes/screens/workout/routines_screen.dart';

import 'package:workout_notes/widgets/strength/routines/routine_exercise_card.dart';

import 'support/ai_test_db.dart';
import 'support/strength_routines_seed.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: home,
);

/// Lets real (sqflite ffi) I/O complete between frames.
Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Database db;

  setUpAll(() async {
    await initializeDateFormatting('pt');
    Intl.defaultLocale = 'pt';
  });

  setUp(() async {
    db = await installAiTestDb();
    await seedStrengthRoutines(db);
  });

  tearDown(() async => uninstallAiTestDb());

  testWidgets('routines list pins the routine in use with its days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => seedRoutineWorkout(
        db,
        'w1',
        '2026-09-10',
        routineId: 'r1',
        dayId: 'd1',
      ),
    );

    await tester.pumpWidget(_app(const RoutinesScreen()));
    await _settle(tester);

    expect(find.text('EM USO'), findsOneWidget); // section header
    expect(find.text('Em uso'), findsOneWidget); // badge on the card
    expect(find.text('PPL'), findsOneWidget);
    expect(find.text('SUAS ROTINAS'), findsOneWidget);
    expect(find.text('Full body'), findsOneWidget);
    // Days of the active routine, each with a start button.
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));
    // Push was trained last, so Pull is next.
    expect(find.text('Próximo'), findsOneWidget);
    expect(find.textContaining('Último treino:'), findsWidgets);
    expect(find.text('Ainda não treinada'), findsOneWidget);
    expect(find.text('Nova rotina'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate and delete (with confirmation) from the menu', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const RoutinesScreen()));
    await _settle(tester);

    // Open the menu of the "Full body" card (the last popup button).
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicar'));
    await _settle(tester);
    expect(find.text('Full body (cópia)'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    // Confirmation first; cancelling keeps the routine.
    expect(find.textContaining('Excluir "'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('(cópia)'), findsOneWidget);
  });

  testWidgets('empty state offers to create a routine', (tester) async {
    await tester.runAsync(() => db.delete('routines'));
    await tester.pumpWidget(_app(const RoutinesScreen()));
    await _settle(tester);
    expect(find.text('Nenhuma rotina ainda'), findsOneWidget);
    expect(find.text('Nova rotina'), findsOneWidget);
  });

  testWidgets('routine form shows the hero, weekly muscles and days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const RoutineFormScreen(routineId: 'r1')));
    await _settle(tester);

    expect(find.text('desc'), findsOneWidget);
    expect(find.text('Músculos por semana'), findsOneWidget);
    expect(find.text('Recomendado: 10–20 séries'), findsOneWidget);
    expect(find.text('Baixo'), findsWidgets); // 3 and 2 sets, under 10
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Adicionar Dia'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('10 a 20 séries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('day editor summarizes the day and confirms removals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        const RoutineDayEditorScreen(
          routineDayId: 'd1',
          routineId: 'r1',
          dayName: 'Push',
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('bench'), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget); // rest of the exercise
    expect(find.text('80'), findsNWidgets(3)); // kg without a trailing ,0
    expect(find.text('A'), findsOneWidget); // warm-up letter (aquecimento)

    // Removing the exercise asks first.
    await tester.tap(
      find.descendant(
        of: find.byType(RoutineExerciseCard),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover exercício'));
    await tester.pumpAndSettle();
    expect(find.text('Remover Exercício?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('bench'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
