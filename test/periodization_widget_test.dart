import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/screens/workout/periodization_home_screen.dart';
import 'package:workout_notes/screens/workout/periodization_phase_form_screen.dart';

Widget _app() => const MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale('pt'),
  home: PeriodizationHomeScreen(),
);

Widget _appWith(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: home,
);

void main() {
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 37,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE routines (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await DatabasePeriodizationSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  testWidgets('empty plan opens the complete guided creation flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(_app());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(find.text('Planejamento'), findsOneWidget);
    expect(find.text('Crie seu primeiro plano'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Criar plano'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(find.text('Novo plano'), findsWidgets);
    expect(find.text('Estrutura do plano'), findsOneWidget);
    expect(find.text('Cutting → Deload → Bulking'), findsOneWidget);
    expect(find.text('Ciclo de força'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan wizard stays usable on a 320px-wide screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(_app());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.tap(find.text('Criar plano'));
      await tester.pumpAndSettle();
    });

    expect(find.text('Estrutura do plano'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('PRÓXIMAS FASES'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('ALVOS DA FASE'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phase editor adapts its target fields on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'responsive-plan',
      name: 'Plano responsivo',
      startDate: now,
      endDate: now.add(const Duration(days: 180)),
      status: PeriodizationPlanStatus.draft,
      createdAt: now,
      updatedAt: now,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _appWith(PeriodizationPhaseFormScreen(plan: plan)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(find.text('Nova fase'), findsOneWidget);
    expect(find.text('PERÍODO E IDENTIDADE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
