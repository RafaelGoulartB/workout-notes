import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_achievements_screen.dart';
import 'package:workout_notes/screens/run/run_insights_screen.dart';
import 'package:workout_notes/screens/run/run_stats_screen.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: child,
);

/// Pumps a screen that loads from SQLite and lets the load finish (the DB
/// resolves on the real event loop, not the widget-test clock).
Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(_app(screen));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
  });
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Intl.defaultLocale = 'pt_BR';
  });

  tearDownAll(() => Intl.defaultLocale = null);

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE routines (id TEXT PRIMARY KEY, name TEXT NOT NULL, notes TEXT, created_at TEXT NOT NULL)',
          );
          await db.execute('''
            CREATE TABLE run_activities (
              id TEXT PRIMARY KEY,
              activity_type TEXT NOT NULL DEFAULT 'running',
              started_at TEXT NOT NULL,
              ended_at TEXT,
              duration_seconds INTEGER NOT NULL DEFAULT 0,
              moving_time_seconds INTEGER NOT NULL DEFAULT 0,
              distance_meters REAL NOT NULL DEFAULT 0,
              avg_pace_sec_per_km REAL,
              max_pace_sec_per_km REAL,
              calories INTEGER,
              title TEXT,
              notes TEXT,
              rpe REAL,
              feeling_rating INTEGER,
              status TEXT NOT NULL DEFAULT 'completed',
              polyline_summary TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              best_split_pace_sec_per_km REAL,
              best_effort_1k_sec INTEGER,
              best_effort_3k_sec INTEGER,
              best_effort_5k_sec INTEGER,
              best_effort_10k_sec INTEGER,
              best_effort_half_sec INTEGER,
              best_effort_marathon_sec INTEGER,
              efforts_computed INTEGER NOT NULL DEFAULT 0,
              elevation_gain_meters REAL,
              plan_workout_id TEXT,
              gear_id TEXT
            )
          ''');
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await DatabasePeriodizationSchema.create(db);
          await DatabaseRunPlanSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  /// Eight easy/tempo runs over the last four weeks, two with a 5K effort.
  Future<void> seedRuns() async {
    final now = DateTime.now();
    for (var i = 0; i < 8; i++) {
      final started = DateTime(
        now.year,
        now.month,
        now.day,
        7,
      ).subtract(Duration(days: 3 * i + 1));
      final meters = 5000.0 + i * 500;
      final seconds = (meters / 1000 * (330 + i * 4)).round();
      await database.insert('run_activities', {
        'id': 'run$i',
        'started_at': started.toIso8601String(),
        'ended_at': started.add(Duration(seconds: seconds)).toIso8601String(),
        'duration_seconds': seconds,
        'moving_time_seconds': seconds,
        'distance_meters': meters,
        'avg_pace_sec_per_km': seconds / (meters / 1000),
        'title': i == 0 ? 'Corrida da manhã' : null,
        'rpe': i.isEven ? 5.0 : null,
        'feeling_rating': i % 3 == 0 ? 4 : null,
        'status': 'completed',
        'polyline_summary':
            '-23.5505,-46.6333;-23.5520,-46.6310;-23.5540,-46.6300;-23.5560,-46.6330',
        'created_at': started.toIso8601String(),
        'updated_at': started.toIso8601String(),
        'best_split_pace_sec_per_km': 300.0 + i,
        'best_effort_5k_sec': i < 2 ? 1500 + i * 30 : null,
        'efforts_computed': 1,
        'elevation_gain_meters': 30.0 + i,
      });
    }
  }

  Future<void> seedPlan() async {
    final plans = RunPlanRepository();
    final plan = await plans.createPlan(
      name: 'Plano 10 km',
      goalKind: RunPlanGoalKind.tenK,
      weeks: 4,
    );
    final today = DateTime.now();
    await plans.addWorkout(
      planId: plan.id,
      weekIndex: 0,
      name: 'Tempo de hoje',
      kind: RunWorkoutKind.tempo,
      dayOfWeek: today.weekday,
      targetDistanceMeters: 6000,
    );
    await plans.activatePlan(plan.id);
  }

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> scrollThrough(WidgetTester tester) async {
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 8; i++) {
      await tester.drag(list, const Offset(0, -700));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('RunStatsScreen', () {
    testWidgets('with no runs and no plan offers a plan or a free run', (
      tester,
    ) async {
      phoneSize(tester);
      await _pump(tester, const RunStatsScreen());

      expect(find.text('Corrida'), findsOneWidget);
      expect(find.text('Nenhum plano de corrida ainda'), findsOneWidget);
      expect(find.byKey(const Key('run-today-choose-plan')), findsOneWidget);
      expect(find.text('Nenhuma corrida ainda'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows today, the week, fitness and records for a runner', (
      tester,
    ) async {
      phoneSize(tester);
      await tester.runAsync(() async {
        await seedRuns();
        await seedPlan();
      });
      await _pump(tester, const RunStatsScreen());

      expect(find.byKey(const Key('run-today-start')), findsOneWidget);
      expect(find.text('Tempo de hoje'), findsOneWidget);
      expect(find.text('Iniciar este treino'), findsOneWidget);
      expect(find.text('ESTA SEMANA'), findsOneWidget);
      expect(find.text('PLANO ATIVO'), findsOneWidget);
      expect(find.text('Plano 10 km'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await scrollThrough(tester);
      expect(find.text('FORMA ATUAL'), findsOneWidget);
      expect(find.text('RECORDES E DESTAQUES'), findsOneWidget);
      expect(find.text('CORRIDAS RECENTES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('period chips switch the summary without errors', (
      tester,
    ) async {
      phoneSize(tester);
      await tester.runAsync(seedRuns);
      await _pump(tester, const RunStatsScreen());

      await tester.ensureVisible(find.text('4 semanas'));
      await tester.pump();
      for (final label in ['4 semanas', 'Ano', 'Tudo', '12 semanas']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull, reason: label);
      }
    });

    testWidgets('chart tabs render volume, pace and frequency', (tester) async {
      phoneSize(tester);
      await tester.runAsync(seedRuns);
      await _pump(tester, const RunStatsScreen());

      await tester.ensureVisible(find.text('Frequência'));
      await tester.pump();
      for (final tab in ['Pace', 'Frequência', 'Volume']) {
        await tester.tap(find.text(tab).first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  });

  group('RunInsightsScreen', () {
    testWidgets('groups the analysis into form, training and year tabs', (
      tester,
    ) async {
      phoneSize(tester);
      await tester.runAsync(seedRuns);
      await _pump(tester, const RunInsightsScreen());

      Future<void> expectCards(List<String> titles) async {
        final list = find.byType(Scrollable).first;
        for (final title in titles) {
          await tester.dragUntilVisible(
            find.text(title),
            list,
            const Offset(0, -300),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text(title), findsOneWidget, reason: title);
          expect(tester.takeException(), isNull, reason: title);
        }
      }

      expect(find.textContaining('VDOT'), findsWidgets);
      await expectCards([
        'Condicionamento',
        'Previsão de provas',
        'Carga de treino',
      ]);

      await tester.tap(find.text('Treinos'));
      await tester.pump(const Duration(milliseconds: 300));
      await expectCards([
        'Distribuição de intensidade',
        'Consistência',
        'Esforço e sensação',
      ]);

      await tester.tap(find.text('Ano'));
      await tester.pump(const Duration(milliseconds: 300));
      await expectCards(['Calendário de atividade', 'Volume', 'Tênis']);
    });

    testWidgets('shows an empty state without runs', (tester) async {
      phoneSize(tester);
      await _pump(tester, const RunInsightsScreen());
      expect(find.text('Ainda sem dados suficientes'), findsOneWidget);
    });
  });

  group('RunAchievementsScreen', () {
    testWidgets('shows an empty state and no board without runs', (
      tester,
    ) async {
      phoneSize(tester);
      await _pump(tester, const RunAchievementsScreen());
      expect(find.text('Nenhum recorde ainda'), findsOneWidget);
      expect(find.byKey(const Key('run-achievements-hero')), findsNothing);
    });

    testWidgets('locked categories use a lock, not an open lock', (
      tester,
    ) async {
      phoneSize(tester);
      await tester.runAsync(seedRuns);
      await _pump(tester, const RunAchievementsScreen());

      expect(find.byKey(const Key('run-achievements-hero')), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.dragUntilVisible(
        find.byKey(const Key('run-achievement-bestEffortMarathon')),
        list,
        const Offset(0, -300),
      );
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
      // The unlock hint uses the formatted distance, not a hard-coded one.
      expect(find.textContaining('42,2 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Let the staggered entry animations finish.
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
