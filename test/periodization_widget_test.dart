import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
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
          await db.execute('''
            CREATE TABLE routine_days (
              id TEXT PRIMARY KEY,
              routine_id TEXT NOT NULL,
              name TEXT NOT NULL,
              order_index INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE workouts (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              start_time TEXT,
              end_time TEXT,
              routine_id TEXT
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

  testWidgets('active plan hero follows the compact summary layout at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'hero-plan',
      name: 'Preparação completa para a temporada',
      startDate: now.subtract(const Duration(days: 28)),
      endDate: now.add(const Duration(days: 83)),
      status: PeriodizationPlanStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    final phases = [
      PeriodizationPhase(
        id: 'hero-phase-1',
        planId: plan.id,
        name: 'Base',
        color: 0xFFF0A33B,
        startDate: plan.startDate,
        endDate: now.subtract(const Duration(days: 1)),
        orderIndex: 0,
        createdAt: now,
        updatedAt: now,
      ),
      PeriodizationPhase(
        id: 'hero-phase-2',
        planId: plan.id,
        name: 'Construção',
        color: 0xFF36B7AA,
        startDate: now,
        endDate: now.add(const Duration(days: 41)),
        orderIndex: 1,
        createdAt: now,
        updatedAt: now,
      ),
      PeriodizationPhase(
        id: 'hero-phase-3',
        planId: plan.id,
        name: 'Pico',
        color: 0xFFB25FC7,
        startDate: now.add(const Duration(days: 42)),
        endDate: plan.endDate,
        orderIndex: 2,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await tester.runAsync(() async {
      await database.insert('periodization_plans', plan.toMap());
      for (final phase in phases) {
        await database.insert('periodization_phases', phase.toMap());
      }
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(_app());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
    });

    expect(find.text('Resumo do plano'), findsOneWidget);
    expect(find.text('Preparação completa para a temporada'), findsOneWidget);
    expect(find.text('Semana atual'), findsOneWidget);
    expect(find.text('Término'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(find.text('Pico'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
