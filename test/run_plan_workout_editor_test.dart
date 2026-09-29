import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_workout_editor_screen.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: child,
);

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
  Future<String> seedIntervalSession() async {
    final plan = await repo.createPlan(name: '10 km');
    final session = await repo.addWorkout(
      planId: plan.id,
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
    return session.id;
  }

  /// The session's steps as `role:value:repeatCount` in order.
  Future<List<String>> stepsOf(String workoutId) async {
    final workout = (await repo.getWorkout(workoutId))!;
    final ordered = [...workout.steps]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return [
      for (final step in ordered)
        '${step.role.name}:${step.value}:${step.repeatCount}',
    ];
  }

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
    late T result;
    await tester.runAsync(() async => result = await body());
    return result;
  }

  /// Lets the DB work behind a tap finish on the real event loop.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    // Let a SnackBar finish sliding in before anything taps it.
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openEditor(WidgetTester tester, String workoutId) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _app(RunPlanWorkoutEditorScreen(workoutId: workoutId)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
  }

  final blockDelete = find.byTooltip('Excluir bloco');

  testWidgets('deleting a repeat block removes every leg and offers undo', (
    tester,
  ) async {
    final id = await real(tester, seedIntervalSession);
    await openEditor(tester, id);
    expect(find.text('6x'), findsOneWidget);

    await tester.tap(blockDelete);
    await settle(tester);

    expect(find.text('6x'), findsNothing);
    expect(find.text('Bloco removido'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);
    expect(await real(tester, () => stepsOf(id)), [
      'warmup:2000:1',
      'cooldown:1000:1',
    ]);
  });

  testWidgets('undo puts the block back at the same position', (tester) async {
    final id = await real(tester, seedIntervalSession);
    await openEditor(tester, id);

    await tester.tap(blockDelete);
    await settle(tester);
    await tester.tap(find.text('Desfazer'));
    await settle(tester);

    expect(find.text('6x'), findsOneWidget);
    expect(await real(tester, () => stepsOf(id)), [
      'warmup:2000:1',
      'work:800:6',
      'recovery:120:6',
      'cooldown:1000:1',
    ]);
    // Still one block, not two loose legs.
    final workout = await real(tester, () => repo.getWorkout(id));
    final blocks = RunPlanUi.blocks(workout!.steps);
    expect(blocks.length, 3);
    expect(blocks[1].isRepeat, isTrue);
    expect(blocks[1].repeats, 6);
  });

  testWidgets('undo does not merge into a block added after the delete', (
    tester,
  ) async {
    final id = await real(tester, seedIntervalSession);
    await openEditor(tester, id);

    await tester.tap(blockDelete);
    await settle(tester);
    // A new block created meanwhile reuses group 1 (the highest is gone).
    await real(tester, () async {
      await repo.addStep(
        workoutId: id,
        role: RunStepRole.work,
        metric: RunIntervalMetric.distance,
        value: 400,
        repeatGroup: 1,
        repeatCount: 4,
      );
    });
    await tester.tap(find.text('Desfazer'));
    await settle(tester);

    final workout = await real(tester, () => repo.getWorkout(id));
    final blocks = RunPlanUi.blocks(workout!.steps);
    expect(blocks.map((b) => b.steps.length).toList(), [1, 2, 1, 1]);
    expect(blocks[1].steps.first.value, 800);
    final added = blocks.singleWhere((b) => b.steps.first.value == 400);
    expect(added.steps.length, 1);
    expect(added.group, isNot(blocks[1].group));
  });

  testWidgets('deleting a single step still offers undo', (tester) async {
    final id = await real(tester, seedIntervalSession);
    await openEditor(tester, id);

    await tester.tap(find.byTooltip('Excluir etapa').first);
    await settle(tester);
    expect(find.text('Etapa removida'), findsOneWidget);
    expect(await real(tester, () => stepsOf(id)), [
      'work:800:6',
      'recovery:120:6',
      'cooldown:1000:1',
    ]);

    await tester.tap(find.text('Desfazer'));
    await settle(tester);
    expect(await real(tester, () => stepsOf(id)), [
      'warmup:2000:1',
      'work:800:6',
      'recovery:120:6',
      'cooldown:1000:1',
    ]);
  });
}
