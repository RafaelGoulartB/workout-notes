import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/exercise_form_screen.dart';
import 'package:workout_notes/screens/workout/exercise_library_screen.dart';

import 'support/ai_test_db.dart';
import 'support/strength_routines_seed.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: home,
);

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
    await db.update(
      'exercises',
      {'equipment': 'Cable', 'name': 'Crossover'},
      where: 'id = ?',
      whereArgs: ['bench'],
    );
    await db.update(
      'exercises',
      {'equipment': 'Dumbbell', 'is_favorite': 1},
      where: 'id = ?',
      whereArgs: ['row'],
    );
  });

  tearDown(() async => uninstallAiTestDb());

  testWidgets('groups by muscle, localizes equipment and shows dense rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const ExerciseLibraryScreen()));
    await _settle(tester);

    // Sections follow the category order.
    expect(find.text('PEITO'), findsOneWidget);
    expect(find.text('COSTAS'), findsOneWidget);
    expect(find.text('Crossover'), findsOneWidget);
    expect(find.textContaining('Polia'), findsOneWidget);
    expect(find.textContaining('Halter'), findsOneWidget);
    expect(find.textContaining('Cable'), findsNothing);
    expect(find.text('3 exercícios'), findsOneWidget);
    expect(find.text('Novo Exercício'), findsOneWidget);
    // One favorite star is filled.
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favorites chip, category chip and search filter the list', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const ExerciseLibraryScreen()));
    await _settle(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'Favoritos'));
    await _settle(tester, rounds: 1);
    expect(find.text('1 exercício'), findsOneWidget);
    expect(find.text('Crossover'), findsNothing);
    expect(find.text('row'), findsOneWidget);

    // Untick favorites, filter by search.
    await tester.tap(find.widgetWithText(FilterChip, 'Favoritos'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'cross');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 exercício'), findsOneWidget);
    expect(find.text('Crossover'), findsOneWidget);

    // Equipment is searchable by its localized name too.
    await tester.enterText(find.byType(TextField), 'halter');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('row'), findsOneWidget);
    expect(find.text('Crossover'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nenhum exercício encontrado'), findsOneWidget);
    await tester.tap(find.text('Limpar filtros'));
    await tester.pump();
    expect(find.text('3 exercícios'), findsOneWidget);
  });

  testWidgets('sort menu switches to a flat list ranked by usage', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedRoutineWorkout(db, 'w1', '2026-09-01');
      await db.insert('exercise_entries', {
        'id': 'ee1',
        'workout_id': 'w1',
        'exercise_id': 'row',
        'order_index': 0,
      });
      await db.insert('sets', {
        'id': 's1',
        'exercise_entry_id': 'ee1',
        'weight': 60.0,
        'reps': 8,
        'is_complete': 1,
        'is_warmup': 0,
        'order_index': 0,
      });
    });

    await tester.pumpWidget(_app(const ExerciseLibraryScreen()));
    await _settle(tester);
    // Best e1RM for the trained lift: 60 x (1 + 8/30) = 76,0 kg.
    expect(find.textContaining('Último: 1 set'), findsOneWidget);
    expect(find.text('76 kg'), findsOneWidget);

    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mais treinados'));
    await tester.pumpAndSettle();
    expect(find.text('PEITO'), findsNothing, reason: 'flat list, no sections');
    final rowY = tester.getTopLeft(find.text('row')).dy;
    final crossY = tester.getTopLeft(find.text('Crossover')).dy;
    expect(rowY, lessThan(crossY));
  });

  testWidgets('exercise form offers localized equipment chips', (tester) async {
    await tester.pumpWidget(
      _app(const ExerciseFormScreen(exerciseId: 'bench')),
    );
    await _settle(tester);
    expect(find.widgetWithText(ChoiceChip, 'Polia'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Peso corporal'), findsOneWidget);
    final polia = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Polia'),
    );
    expect(polia.selected, isTrue);

    // Picking another chip and saving stores the English identifier.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Halter'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Halter'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await _settle(tester);
    final rows = (await tester.runAsync(
      () => db.query('exercises', where: 'id = ?', whereArgs: ['bench']),
    ))!;
    expect(rows.single['equipment'], 'Dumbbell');
  });
}
