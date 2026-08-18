import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
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
          await db.execute('''
            CREATE TABLE body_measurements (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL DEFAULT 'kg',
              date TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE nutrition_goals (
              id TEXT PRIMARY KEY,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              tdee REAL,
              adjustment_kind TEXT,
              adjustment_percent REAL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1
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

  Future<void> seedTdeeGoal({required double tdee}) async {
    final now = DateTime.now().toIso8601String();
    await database.insert('nutrition_goals', {
      'id': 'goal-tdee',
      'calories': tdee,
      'protein_g': null,
      'carbs_g': null,
      'fat_g': null,
      'tdee': tdee,
      'adjustment_kind': 'maintenance',
      'adjustment_percent': 0,
      'created_at': now,
      'updated_at': now,
      'is_active': 1,
    });
  }

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
      await tester.drag(
        find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('phase editor opens automatic nutrition target suggestion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'suggestion-plan',
      name: 'Plano com sugestões',
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

    final suggestion = find.text('Calcular pelo meu perfil');
    await tester.scrollUntilVisible(
      suggestion,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(suggestion);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Estimar gasto diário'), findsOneWidget);
    expect(find.text('Seu perfil'), findsOneWidget);
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

  testWidgets('phase editor shows week stepper and computes macros live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'weekly-plan',
      name: 'Plano semanal',
      startDate: now,
      endDate: now.add(const Duration(days: 180)),
      status: PeriodizationPlanStatus.draft,
      createdAt: now,
      updatedAt: now,
    );
    await tester.runAsync(() async {
      await seedTdeeGoal(tdee: 2200);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _appWith(PeriodizationPhaseFormScreen(plan: plan)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    await tester.scrollUntilVisible(
      find.text('Semana base'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Semana base'), findsOneWidget);

    final adjustmentField = find.widgetWithText(
      TextField,
      'Déficit / Superávit (kcal)',
    );
    await tester.scrollUntilVisible(
      adjustmentField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(adjustmentField, '+200');
    await tester.enterText(
      find.widgetWithText(TextField, 'Proteína (g/kg)'),
      '2.2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Gordura (g/kg)'),
      '0.8',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Peso de referência (kg)'),
      '75',
    );
    // The controller commits target edits on a 300ms debounce, so the
    // preview only rebuilds after the fake clock passes it.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Macros calculados'), findsOneWidget);
    expect(find.text('165 g'), findsOneWidget);
    expect(find.text('60 g'), findsOneWidget);
    expect(find.text('300 g'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inherited weeks offer customize and revert actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'inherit-plan',
      name: 'Plano herança',
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

    await tester.scrollUntilVisible(
      find.byKey(const Key('weekStepperNext')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('weekStepperNext')));
    await tester.pumpAndSettle();
    expect(find.text('Herdando da semana 1'), findsOneWidget);

    await tester.tap(find.text('Personalizar'));
    await tester.pumpAndSettle();
    expect(find.text('Personalizada'), findsOneWidget);

    await tester.tap(find.text('Herdar da anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Herdando da semana 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy sheet applies the base week targets to picked weeks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'copy-plan',
      name: 'Plano cópia',
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

    // Fill one base-week target so the copy has real content.
    await tester.scrollUntilVisible(
      find.text('Treino'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treino'));
    await tester.pumpAndSettle();
    final workoutsField = find.widgetWithText(TextField, 'Treinos por semana');
    await tester.scrollUntilVisible(
      workoutsField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(workoutsField, '4');
    await tester.pumpAndSettle();
    // The controller commits target edits on a 300ms debounce.
    await tester.pump(const Duration(milliseconds: 350));

    // Customize week 2 with a different value so the copy has something
    // to overwrite.
    await tester.ensureVisible(
      find.byKey(const Key('weekStepperNext')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weekStepperNext')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Personalizar'));
    await tester.tap(find.text('Personalizar'));
    await tester.pumpAndSettle();
    // Switching to an inherited week replaced the editable cards with the
    // read-only ones, so the training card comes back collapsed.
    await tester.scrollUntilVisible(
      find.text('Treino'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Treino'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      workoutsField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(workoutsField, '6');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));

    // Back on the base week, open the copy sheet and pick two weeks.
    await tester.ensureVisible(
      find.byKey(const Key('weekStepperPrev')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weekStepperPrev')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copiar para…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar para…'));
    await tester.pumpAndSettle();

    expect(find.text('Copiar metas da semana 1'), findsOneWidget);
    expect(find.text('Aplicar às semanas seguintes'), findsOneWidget);

    await tester.tap(find.textContaining('S3 ·'));
    await tester.tap(find.textContaining('S4 ·'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar (2)'));
    await tester.pumpAndSettle();

    // Weeks 3 and 4 were inheriting week 2's 6/week, so both differ from
    // the base (4/week) and get their own override.
    expect(find.text('Metas aplicadas em 2 semanas'), findsOneWidget);

    // Week 3 had no override before the copy; now it must be customized.
    await tester.ensureVisible(
      find.byKey(const Key('weekStepperNext')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weekStepperNext')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('weekStepperNext')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('weekStepperNext')));
    await tester.pumpAndSettle();
    expect(find.text('Personalizada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a phase persists one version per customized week', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await seedTdeeGoal(tdee: 2200);
    });
    final plan = (await tester.runAsync(
      () => PeriodizationRepository().createPlan(
        name: 'Plano persistente',
        startDate: now,
        endDate: now.add(const Duration(days: 180)),
      ),
    ))!;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _appWith(PeriodizationPhaseFormScreen(plan: plan)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    await tester.enterText(find.byType(TextFormField), 'Fase de teste');

    final adjustmentField = find.widgetWithText(
      TextField,
      'Déficit / Superávit (kcal)',
    );
    await tester.scrollUntilVisible(
      adjustmentField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(adjustmentField, '+200');
    await tester.enterText(
      find.widgetWithText(TextField, 'Proteína (g/kg)'),
      '2.2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Gordura (g/kg)'),
      '0.8',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Peso de referência (kg)'),
      '75',
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Salvar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final phases = await tester.runAsync(
      () => PeriodizationRepository().getPhases(plan.id),
    );
    final history = await tester.runAsync(
      () => PeriodizationRepository().getTargetHistory(phases!.single.id),
    );
    expect(history, hasLength(1));
    expect(history!.single.calories, 2400);
    expect(history.single.carbsG, 300);
    expect(history.single.proteinGPerKg, 2.2);
    expect(history.single.fatGPerKg, 0.8);
    expect(history.single.weightKgUsed, 75);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked past weeks render read-only targets in edit mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Single-week phase that already ended yesterday.
    final start = today.subtract(const Duration(days: 7));
    final end = today.subtract(const Duration(days: 1));
    final plan = (await tester.runAsync(
      () => PeriodizationRepository().createPlan(
        name: 'Plano histórico',
        startDate: start,
        endDate: end,
      ),
    ))!;
    final phase = (await tester.runAsync(() async {
      final repository = PeriodizationRepository();
      return repository.addPhase(
        planId: plan.id,
        name: 'Fase histórica',
        startDate: start,
        endDate: end,
        color: 1,
        weeklyTargets: List.filled(
          1,
          PeriodizationTarget(
            id: '',
            phaseId: '',
            version: 0,
            validFrom: start,
            calories: 2200,
            proteinG: 180,
            carbsG: 250,
            fatG: 60,
            createdAt: now,
          ),
        ),
      );
    }))!;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _appWith(PeriodizationPhaseFormScreen(plan: plan, phase: phase)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    await tester.pumpAndSettle();
    // The single week is already locked and is selected by default.
    await tester.scrollUntilVisible(
      find.text('Encerrada'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Encerrada'), findsOneWidget);
    expect(find.text('2200 kcal'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan wizard reuses the phase editor for weekly targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await seedTdeeGoal(tdee: 2200);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(_app());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
      await tester.tap(find.text('Criar plano'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    expect(find.text('Novo plano'), findsWidgets);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('ALVOS DA FASE'), findsWidgets);

    // Tapping the phase opens the shared full-screen editor (draft mode).
    await tester.runAsync(() async {
      await tester.tap(find.text('Cutting').first);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
    });
    // The editor route is pushed once the controller's async load()
    // completes, which can land after the last in-block pump.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Editar fase'), findsOneWidget);

    final adjustmentField = find.widgetWithText(
      TextField,
      'Déficit / Superávit (kcal)',
    );
    await tester.scrollUntilVisible(
      adjustmentField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(adjustmentField, '+200');
    await tester.enterText(
      find.widgetWithText(TextField, 'Proteína (g/kg)'),
      '2.2',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Gordura (g/kg)'),
      '0.8',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Peso de referência (kg)'),
      '75',
    );
    // Let the 300ms target debounce commit before saving.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.runAsync(() async {
      await tester.tap(find.text('Salvar'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('2400 kcal'), findsWidgets);

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Criar e ativar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    final plan = (await tester.runAsync(
      () => PeriodizationRepository().getActivePlan(),
    ))!;
    final phases = (await tester.runAsync(
      () => PeriodizationRepository().getPhases(plan.id),
    ))!;
    expect(phases, hasLength(4));
    final history = (await tester.runAsync(
      () => PeriodizationRepository().getTargetHistory(phases.first.id),
    ))!;
    expect(history, hasLength(1));
    expect(history.single.calories, 2400);
    expect(history.single.carbsG, 300);
    expect(history.single.proteinGPerKg, 2.2);
    expect(history.single.weightKgUsed, 75);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phase duration input opens the weeks modal and applies the pick', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: 'weeks-picker-plan',
      name: 'Plano semanas',
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

    // Default phase duration is 4 weeks (start + 27 days).
    expect(find.text('4 semanas'), findsOneWidget);

    await tester.tap(find.text('4 semanas'));
    await tester.pumpAndSettle();
    expect(find.text('Número de semanas'), findsOneWidget);

    final field = find.widgetWithText(TextField, '4');
    expect(field, findsOneWidget);
    await tester.enterText(field, '8');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Salvar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8 semanas'), findsOneWidget);
    expect(find.text('Número de semanas'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
