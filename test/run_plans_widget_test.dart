import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_detail_screen.dart';
import 'package:workout_notes/screens/run/run_plan_workout_editor_screen.dart';
import 'package:workout_notes/screens/run/run_plans_screen.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: child,
);

/// Runs real-async work from inside a `testWidgets` body.
///
/// `sqflite_common_ffi` resolves on the real event loop, while a widget-test
/// body sits in a fake clock — awaiting a DB future directly there hangs
/// forever. Every seeding step has to go through here.
Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
  late T result;
  await tester.runAsync(() async {
    result = await body();
  });
  return result;
}

/// Pumps a screen that loads from SQLite, letting the load actually complete.
Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(_app(screen));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
  });
}

Future<void> tapAndLoad(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
  });
}

void main() {
  late Database database;
  late RunPlanRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 45,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE run_activities (id TEXT PRIMARY KEY, started_at TEXT NOT NULL, '
            'status TEXT NOT NULL DEFAULT \'completed\', created_at TEXT NOT NULL, '
            'updated_at TEXT NOT NULL, plan_workout_id TEXT)',
          );
          await DatabasePeriodizationSchema.create(db);
          await DatabaseRunPlanSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repo = RunPlanRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  /// `2 km warmup + 6x(800 m / 2 min) + 1 km cooldown`.
  Future<RunPlanWorkout> seedIntervalSession(String planId) async {
    final session = await repo.addWorkout(
      planId: planId,
      weekIndex: 0,
      name: '6x800m',
      kind: RunWorkoutKind.interval,
      dayOfWeek: 2,
    );
    await repo.addStep(
      workoutId: session.id,
      role: RunStepRole.warmup,
      metric: RunIntervalMetric.distance,
      value: 2000,
    );
    await repo.addStep(
      workoutId: session.id,
      role: RunStepRole.work,
      metric: RunIntervalMetric.distance,
      value: 800,
      repeatGroup: 1,
      repeatCount: 6,
      targetPaceMinSecPerKm: 235,
    );
    await repo.addStep(
      workoutId: session.id,
      role: RunStepRole.recovery,
      metric: RunIntervalMetric.time,
      value: 120,
      repeatGroup: 1,
      repeatCount: 6,
    );
    await repo.addStep(
      workoutId: session.id,
      role: RunStepRole.cooldown,
      metric: RunIntervalMetric.distance,
      value: 1000,
    );
    return (await repo.getWorkout(session.id))!;
  }

  group('RunPlansScreen', () {
    testWidgets('shows the empty state with no plan', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpScreen(tester, const RunPlansScreen());

      expect(find.text('Planos de corrida'), findsOneWidget);
      expect(find.text('Nenhum plano de corrida ainda'), findsOneWidget);
      expect(find.text('Novo plano'), findsOneWidget);
    });

    testWidgets('lists an existing plan with goal and weeks', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await real(
        tester,
        () => repo.createPlan(
          name: '10 km em 12 semanas',
          goalKind: RunPlanGoalKind.tenK,
          weeks: 12,
        ),
      );

      await pumpScreen(tester, const RunPlansScreen());

      expect(find.text('10 km em 12 semanas'), findsOneWidget);
      // Subtitle: goal label plus the plan length.
      expect(find.text('10 km · 12 semanas'), findsOneWidget);
    });

    testWidgets('archived plans are hidden until toggled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await real(tester, () async {
        final plan = await repo.createPlan(name: 'Antigo');
        await repo.updatePlan(plan.id, status: RunPlanStatus.archived);
      });

      await pumpScreen(tester, const RunPlansScreen());
      expect(find.text('Antigo'), findsNothing);

      await tapAndLoad(tester, find.byTooltip('Mostrar arquivados'));
      expect(find.text('Antigo'), findsOneWidget);
    });
  });

  group('RunPlanDetailScreen', () {
    testWidgets('renders the week strip and the session outline', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(
          name: '10 km',
          goalKind: RunPlanGoalKind.tenK,
          weeks: 4,
        );
        await seedIntervalSession(plan.id);
        await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Longão',
          kind: RunWorkoutKind.long,
          dayOfWeek: 7,
          targetDistanceMeters: 14000,
        );
        return plan.id;
      });

      await pumpScreen(tester, RunPlanDetailScreen(planId: planId));

      expect(find.text('6x800m'), findsOneWidget);
      expect(find.text('Longão'), findsWidgets);
      // The selected week is named in the week header; the picker tiles carry
      // just the number, so week 4 shows up as "4".
      expect(find.text('Semana 1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // 2 km + 6x800 m + 1 km = 7,8 km, plus the 14 km long run.
      expect(find.textContaining('21,8 km'), findsOneWidget);
      // The interval outline reads as one repeated block.
      expect(find.textContaining('6x (800 m + 2 min)'), findsOneWidget);
    });

    testWidgets('switching week shows that week as empty', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(name: '10 km', weeks: 3);
        await seedIntervalSession(plan.id);
        return plan.id;
      });

      await pumpScreen(tester, RunPlanDetailScreen(planId: planId));
      expect(find.text('6x800m'), findsOneWidget);

      await tapAndLoad(tester, find.text('2'));
      expect(find.text('6x800m'), findsNothing);
      expect(find.text('Nenhum treino nesta semana'), findsOneWidget);
    });
  });

  group('RunPlanWorkoutEditorScreen', () {
    testWidgets('lists the steps of an interval session', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sessionId = await real(tester, () async {
        final plan = await repo.createPlan(name: '10 km');
        final session = await seedIntervalSession(plan.id);
        return session.id;
      });

      await pumpScreen(
        tester,
        RunPlanWorkoutEditorScreen(workoutId: sessionId),
      );

      expect(find.text('Aquecimento'), findsWidgets);
      expect(find.text('Desaquecimento'), findsWidgets);
      // The two legs are grouped under one multiplier badge instead of
      // repeating "6x" on each row.
      expect(find.text('6x'), findsOneWidget);
      expect(find.text('800 m'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
      expect(find.text('Adicionar bloco de tiros'), findsOneWidget);
    });

    testWidgets('a continuous session shows the empty-steps hint', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sessionId = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Base');
        final session = await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Longão',
          kind: RunWorkoutKind.long,
          targetDistanceMeters: 14000,
        );
        return session.id;
      });

      await pumpScreen(
        tester,
        RunPlanWorkoutEditorScreen(workoutId: sessionId),
      );

      expect(find.text('Nenhuma etapa ainda'), findsOneWidget);
      expect(find.text('Longão'), findsWidgets);
    });
  });

  group('templates', () {
    test('the 10k template fills every week with its sessions', () async {
      final plan = await RunPlanTemplates.create(
        repo,
        RunPlanTemplates.tenK,
        name: '10 km',
      );
      expect(plan.weeks, 12);
      expect(plan.workoutsForWeek(0).length, 4);
      expect(plan.workoutsForWeek(11).length, 4);
      // Steps ride along into the copied weeks.
      final buildWeekInterval = plan
          .workoutsForWeek(6)
          .firstWhere((session) => session.kind == RunWorkoutKind.interval);
      expect(buildWeekInterval.workRepCount, 6);
      expect(plan.qualitySessionsForWeek(0), 2);
      expect(
        plan.weeklyDistanceMeters(6),
        greaterThan(plan.weeklyDistanceMeters(3)),
      );
    });

    test('the maintenance template is a single repeating week', () async {
      final plan = await RunPlanTemplates.create(
        repo,
        RunPlanTemplates.maintenance,
        name: 'Manutenção',
      );
      expect(plan.weeks, 1);
      expect(plan.workoutsForWeek(0).length, 3);
    });
  });

  group('RunPlanUi', () {
    test('parses pace in both mm:ss and decimal form', () {
      expect(RunPlanUi.parsePace('4:35'), 275);
      expect(RunPlanUi.parsePace('4,30'), 270);
      expect(RunPlanUi.parsePace(''), isNull);
      expect(RunPlanUi.parsePace('abc'), isNull);
      expect(RunPlanUi.parsePace('0'), isNull);
    });

    test('formats pace and pace ranges', () {
      expect(RunPlanUi.paceLabel(275), '4:35');
      expect(RunPlanUi.paceLabel(null), '—');
      expect(RunPlanUi.paceRangeLabel(230, 245), '3:50–4:05');
      expect(RunPlanUi.paceRangeLabel(230, null), '3:50');
      expect(RunPlanUi.paceRangeLabel(null, null), isNull);
    });

    test('formats distance and duration the way runners read them', () {
      expect(RunPlanUi.distanceLabel(800), '800 m');
      expect(RunPlanUi.distanceLabel(7800), '7,8 km');
      expect(RunPlanUi.distanceLabel(0), '—');
      expect(RunPlanUi.durationLabel(120), '2 min');
      expect(RunPlanUi.durationLabel(150), '2:30');
      expect(RunPlanUi.durationLabel(3600), '1h');
    });

    test('rounds estimates instead of showing them as a pace', () {
      expect(RunPlanUi.durationRoughLabel(2265), '38 min');
      expect(RunPlanUi.durationRoughLabel(20), '1 min');
      expect(RunPlanUi.durationRoughLabel(3900), '1h05');
      expect(RunPlanUi.durationRoughLabel(0), '—');
    });

    test('kilometres use the locale decimal separator', () {
      expect(RunPlanUi.kmValue(21700), '21,7');
      expect(RunPlanUi.kmValue(0), '0,0');
      expect(RunPlanUi.kmValue(123400), '123');
    });

    test('step durations round-trip through the editable mm:ss form', () {
      expect(RunPlanUi.secondsInput(45), '45');
      expect(RunPlanUi.secondsInput(120), '2:00');
      expect(RunPlanUi.secondsInput(150), '2:30');
      expect(RunPlanUi.parseSeconds('2:00'), 120);
      expect(RunPlanUi.parseSeconds('90'), 90);
      expect(RunPlanUi.parseSeconds('0'), isNull);
      expect(RunPlanUi.parseSeconds('abc'), isNull);
    });

    test('groups consecutive steps sharing a repeat group into one block', () {
      final steps = [
        _step(0, RunStepRole.warmup, 2000),
        _step(1, RunStepRole.work, 800, group: 1, repeats: 6),
        _step(2, RunStepRole.recovery, 120, group: 1, repeats: 6),
        _step(3, RunStepRole.cooldown, 1000),
      ];
      final blocks = RunPlanUi.blocks(steps);

      expect(blocks.length, 3);
      expect(blocks[0].isRepeat, isFalse);
      expect(blocks[1].isRepeat, isTrue);
      expect(blocks[1].repeats, 6);
      expect(blocks[1].steps.length, 2);
      expect(blocks[2].steps.single.role, RunStepRole.cooldown);
    });

    test('estimates a distance step from its own target pace', () {
      // 800 m at 3:45/km is 180 s; without a pace it falls back to easy pace.
      expect(
        RunPlanUi.estimatedSeconds(
          _step(0, RunStepRole.work, 800, paceMin: 225),
        ),
        180,
      );
      expect(RunPlanUi.estimatedSeconds(_step(0, RunStepRole.work, 1000)), 330);
      expect(
        RunPlanUi.estimatedSeconds(
          RunWorkoutStep(
            id: 't',
            runPlanWorkoutId: 'w',
            orderIndex: 0,
            role: RunStepRole.recovery,
            metric: RunIntervalMetric.time,
            value: 120,
          ),
        ),
        120,
      );
    });
  });
}

/// Bare step for the pure [RunPlanUi] helpers — no database involved.
RunWorkoutStep _step(
  int order,
  RunStepRole role,
  int value, {
  int? group,
  int repeats = 1,
  double? paceMin,
}) => RunWorkoutStep(
  id: 'step-$order',
  runPlanWorkoutId: 'workout',
  orderIndex: order,
  role: role,
  metric: role == RunStepRole.recovery
      ? RunIntervalMetric.time
      : RunIntervalMetric.distance,
  value: value,
  repeatGroup: group,
  repeatCount: repeats,
  targetPaceMinSecPerKm: paceMin,
);
