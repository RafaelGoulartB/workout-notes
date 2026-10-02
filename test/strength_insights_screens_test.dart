import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/strength/strength_insights_screen.dart';
import 'package:workout_notes/screens/strength/strength_records_screen.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';

import 'support/ai_test_db.dart';

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

var _seq = 0;

Future<void> _workout(
  Database db,
  String id,
  DateTime day,
  Map<String, List<(double, int)>> exercises, {
  bool finished = true,
  int feeling = 4,
}) async {
  final date = day.toIso8601String().substring(0, 10);
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': DateTime(day.year, day.month, day.day, 8).toIso8601String(),
    'end_time': finished
        ? DateTime(day.year, day.month, day.day, 9).toIso8601String()
        : null,
    'duration_seconds': 3600,
    'feeling_rating': feeling,
    'created_at': DateTime(day.year, day.month, day.day, 7).toIso8601String(),
  });
  var order = 0;
  for (final entry in exercises.entries) {
    final entryId = 'ee${_seq++}';
    await db.insert('exercise_entries', {
      'id': entryId,
      'workout_id': id,
      'exercise_id': entry.key,
      'order_index': order++,
    });
    for (final (i, s) in entry.value.indexed) {
      await db.insert('sets', {
        'id': 's${_seq++}',
        'exercise_entry_id': entryId,
        'weight': s.$1,
        'reps': s.$2,
        'is_complete': 1,
        'is_warmup': 0,
        'order_index': i,
      });
    }
  }
}

Future<void> _seed(Database db) async {
  await db.insert('exercise_categories', {
    'id': 'chest',
    'name': 'Chest',
    'color': 0xFF2196F3,
    'order_index': 0,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercise_categories', {
    'id': 'back',
    'name': 'Back',
    'color': 0xFF4CAF50,
    'order_index': 1,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercises', {
    'id': 'bench',
    'name': 'Supino teste',
    'category_id': 'chest',
    'equipment': 'Barbell',
    'created_at': '2026-01-01T00:00:00.000',
  });
  await db.insert('exercises', {
    'id': 'row',
    'name': 'Remada teste',
    'category_id': 'back',
    'created_at': '2026-01-01T00:00:00.000',
  });
  final today = DateTime.now();
  DateTime ago(int d) => DateTime(today.year, today.month, today.day - d);
  await _workout(db, 'w1', ago(20), {
    'bench': [(80, 8), (80, 8)],
    'row': [(60, 10)],
  });
  await _workout(db, 'w2', ago(13), {
    'bench': [(82.5, 8), (82.5, 7)],
  });
  await _workout(db, 'w3', ago(6), {
    'bench': [(85, 8), (85, 6)],
    'row': [(65, 10)],
  });
  // Unfinished sessions never count.
  await _workout(db, 'w4', ago(1), {
    'bench': [(200, 10)],
  }, finished: false);
}

void main() {
  late Database db;

  setUpAll(() async {
    await initializeDateFormatting('pt');
    Intl.defaultLocale = 'pt';
  });

  setUp(() async {
    db = await installAiTestDb();
    await _seed(db);
  });

  tearDown(() async => uninstallAiTestDb());

  testWidgets('analysis shows the four tabs and their cards', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const StrengthInsightsScreen()));
    await _settle(tester);

    expect(find.text('Análise'), findsOneWidget);
    for (final tab in ['Volume', 'Frequência', 'Exercícios', 'Bem-estar']) {
      expect(find.text(tab), findsWidgets);
    }
    // Volume tab.
    expect(find.text('Resumo do período'), findsOneWidget);
    expect(find.text('Evolução do volume'), findsOneWidget);

    // Changing the period rebuilds without errors.
    await tester.tap(find.text('4 sem'));
    await _settle(tester, rounds: 2);
    await tester.tap(find.text('Ano'));
    await _settle(tester, rounds: 2);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Séries por grupo muscular'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Peito'), findsWidgets);

    // Frequency tab.
    await tester.tap(find.text('Frequência').first);
    await _settle(tester, rounds: 2);
    expect(find.text('Calendário de treinos'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Dia da semana'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Consistência'), findsOneWidget);
    expect(find.text('Treinos por semana'), findsWidgets);
    // All workouts start in the morning: a single bucket is not shown.
    expect(find.text('Horário'), findsNothing);
    expect(tester.takeException(), isNull);

    // Exercises tab: search filters the list, tapping opens the detail.
    await tester.tap(find.text('Exercícios').first);
    await _settle(tester, rounds: 2);
    expect(find.text('Supino teste'), findsOneWidget);
    expect(find.text('Remada teste'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'remada');
    await tester.pump();
    expect(find.text('Supino teste'), findsNothing);
    expect(find.text('Remada teste'), findsOneWidget);

    // Wellness tab.
    await tester.tap(find.text('Bem-estar').first);
    await _settle(tester, rounds: 3);
    expect(find.text('Sensação após o treino'), findsOneWidget);
    expect(find.text('Corpo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analysis shows an empty state without workouts', (tester) async {
    await tester.runAsync(() => db.delete('workouts'));
    await tester.pumpWidget(_app(const StrengthInsightsScreen()));
    await _settle(tester);
    expect(find.text('Ainda sem dados suficientes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('records screen lists timeline and best marks per exercise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const StrengthRecordsScreen()));
    await _settle(tester);

    expect(find.text('Recordes'), findsOneWidget);
    expect(find.text('Neste mês'), findsOneWidget);
    expect(find.text('RECORDES RECENTES'), findsOneWidget);
    expect(find.text('POR EXERCÍCIO'), findsOneWidget);
    // Bench improved twice after its baseline session.
    expect(find.text('Supino teste'), findsWidgets);
    expect(find.text('1RM est.'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('Nenhum exercício encontrado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('records screen has an empty state', (tester) async {
    await tester.runAsync(() => db.delete('workouts'));
    await tester.pumpWidget(_app(const StrengthRecordsScreen()));
    await _settle(tester);
    expect(find.text('Ainda sem recordes'), findsOneWidget);
  });

  testWidgets('exercise detail shows records, history and charts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        const ExerciseDetailTabsScreen(
          exerciseId: 'bench',
          exerciseName: 'Supino teste',
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('Supino teste'), findsWidgets);
    // Equipment is translated, the unfinished workout is ignored.
    expect(find.text('Barra'), findsOneWidget);
    expect(find.text('3 treinos'), findsOneWidget);
    expect(find.text('1RM est.'), findsOneWidget);
    expect(find.text('Recorde'), findsWidgets);
    expect(find.text('85 kg × 8'), findsOneWidget);
    expect(find.textContaining('200'), findsNothing);

    await tester.tap(find.text('Gráficos'));
    await _settle(tester, rounds: 2);
    expect(find.text('Carga máx.'), findsOneWidget);
    await tester.tap(find.text('Carga máx.'));
    await _settle(tester, rounds: 2);
    expect(find.text('Melhor: 85 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
