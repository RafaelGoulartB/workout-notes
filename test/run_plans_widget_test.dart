import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

import 'support/test_db.dart';

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
    initSqfliteFfiForTests();
    // Decimals follow the app locale, which main.dart sets in production.
    Intl.defaultLocale = 'pt_BR';
  });

  tearDownAll(() => Intl.defaultLocale = null);

  setUp(() async {
    database = await installTestDb();
    repo = RunPlanRepository();
  });

  tearDown(uninstallTestDb);

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

    testWidgets('completion badges use only the medal and repeated count', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await real(tester, () async {
        for (var count = 1; count <= 2; count++) {
          final plan = await repo.createPlan(name: 'Completo $count', weeks: 1);
          final session = await repo.addWorkout(
            planId: plan.id,
            weekIndex: 0,
            name: 'Corrida final',
            dayOfWeek: 2,
          );
          final activityId = 'badge-activity-$count';
          final now = DateTime.now().toIso8601String();
          await database.insert('run_activities', {
            'id': activityId,
            'started_at': now,
            'status': 'completed',
            'created_at': now,
            'updated_at': now,
          });
          await repo.markPlanWorkoutCompleted(
            planWorkoutId: session.id,
            date: DateTime.now(),
            runActivityId: activityId,
          );
          if (count == 2) {
            await database.update(
              'run_plans',
              {'completion_count': 2},
              where: 'id = ?',
              whereArgs: [plan.id],
            );
          }
        }
      });

      await pumpScreen(tester, const RunPlansScreen());

      expect(find.text('PLANO CONCLUÃDO'), findsNothing);
      expect(find.text('1x'), findsNothing);
      expect(find.text('2x'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium_rounded), findsNWidgets(2));
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

    testWidgets('long-press drag moves a session to another weekday', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late RunPlanWorkout session;
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Base', weeks: 1);
        session = await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Rodagem leve',
          dayOfWeek: DateTime.tuesday,
        );
        return plan.id;
      });

      await pumpScreen(tester, RunPlanDetailScreen(planId: planId));

      final source = find.byKey(ValueKey('run-plan-session-${session.id}'));
      final target = find.byKey(const ValueKey('run-plan-day-4'));
      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      });

      final moved = await real(tester, () => repo.getWorkout(session.id));
      expect(moved!.dayOfWeek, DateTime.thursday);
    });

    testWidgets('completed sessions are marked inside the training week', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Base', weeks: 1);
        final completed = await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Rodagem concluída',
          dayOfWeek: 2,
        );
        await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Longão pendente',
          dayOfWeek: 7,
        );
        await repo.activatePlan(plan.id);
        final now = DateTime.now().toIso8601String();
        await database.insert('run_activities', {
          'id': 'activity-widget',
          'started_at': now,
          'status': 'completed',
          'created_at': now,
          'updated_at': now,
        });
        await repo.markPlanWorkoutCompleted(
          planWorkoutId: completed.id,
          date: DateTime.now(),
          runActivityId: 'activity-widget',
        );
        return plan.id;
      });

      await pumpScreen(tester, RunPlanDetailScreen(planId: planId));

      // One badge says it: no strike-through and no second "done" label.
      expect(find.text('Concluído'), findsOneWidget);
      expect(find.text('Treino concluído neste plano'), findsNothing);
      expect(find.text('Resetar'), findsOneWidget);
      expect(find.text('Parar'), findsOneWidget);
    });

    testWidgets('fully completed plan shows its completion badge', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Meta completa', weeks: 1);
        final session = await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Corrida final',
          dayOfWeek: 2,
        );
        await repo.activatePlan(plan.id);
        final now = DateTime.now().toIso8601String();
        await database.insert('run_activities', {
          'id': 'activity-finish',
          'started_at': now,
          'status': 'completed',
          'created_at': now,
          'updated_at': now,
        });
        await repo.markPlanWorkoutCompleted(
          planWorkoutId: session.id,
          date: DateTime.now(),
          runActivityId: 'activity-finish',
        );
        return plan.id;
      });

      await pumpScreen(tester, RunPlanDetailScreen(planId: planId));

      expect(find.text('PLANO CONCLUÍDO'), findsOneWidget);
      expect(find.textContaining('concluiu todos os treinos'), findsOneWidget);
      expect(find.text('Seguir'), findsNothing);
    });
  });

  group('followed plans', () {
    Future<RunPlan> seedWeek({
      required String name,
      required DateTime monday,
      int weeks = 2,
      List<int> days = const [1, 3, 6],
    }) async {
      final plan = await repo.createPlan(name: name, weeks: weeks);
      for (final day in days) {
        await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Treino $day',
          dayOfWeek: day,
          targetDistanceMeters: 5000,
        );
      }
      await database.update(
        'run_plans',
        {
          'activated_at':
              '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
              '${monday.day.toString().padLeft(2, '0')}',
        },
        where: 'id = ?',
        whereArgs: [plan.id],
      );
      for (var week = 0; week < weeks; week++) {
        await repo.materializeWeek(
          planId: plan.id,
          weekIndex: week,
          weekStart: DateTime(monday.year, monday.month, monday.day + 7 * week),
        );
      }
      return plan;
    }

    testWidgets('detail shows real dates, today and one badge per session', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 2026-09-28 is a Monday; "today" is the Wednesday.
      final plan = await real(
        tester,
        () => seedWeek(name: 'Base', monday: DateTime(2026, 9, 28)),
      );

      await pumpScreen(
        tester,
        RunPlanDetailScreen(planId: plan.id, today: DateTime(2026, 9, 30)),
      );

      expect(find.text('28/09'), findsOneWidget);
      expect(find.text('30/09'), findsOneWidget);
      expect(find.text('HOJE'), findsOneWidget);
      // Monday passed without a run: missed. Nothing else carries a badge.
      expect(find.text('Perdido'), findsOneWidget);
      expect(find.text('Concluído'), findsNothing);
      // Only today's session starts directly.
      expect(find.text('Iniciar'), findsOneWidget);
      // A followed plan is already scheduled: the badge, never the button.
      expect(find.text('Agendada'), findsWidgets);
      expect(find.text('Agendar esta semana'), findsNothing);
      // Continuous sessions do not draw a meaningless profile bar.
      expect(find.byType(RunWorkoutProfileBar), findsNothing);
    });

    testWidgets('an unfollowed plan offers to schedule and has no dates', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Modelo', weeks: 2);
        await repo.addWorkout(
          planId: plan.id,
          weekIndex: 0,
          name: 'Treino',
          dayOfWeek: 2,
        );
        return plan.id;
      });

      await pumpScreen(
        tester,
        RunPlanDetailScreen(planId: planId, today: DateTime(2026, 9, 30)),
      );

      expect(find.text('Agendar esta semana'), findsOneWidget);
      expect(find.text('Agendada'), findsNothing);
      expect(find.text('HOJE'), findsNothing);
      expect(find.text('Iniciar'), findsNothing);
      expect(find.text('Não está seguindo este plano'), findsOneWidget);
    });

    testWidgets('a plan that ended by date is not "following" or "done"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final plan = await real(
        tester,
        () => seedWeek(name: 'Antigo', monday: DateTime(2026, 6, 1)),
      );

      await pumpScreen(
        tester,
        RunPlanDetailScreen(planId: plan.id, today: DateTime(2026, 9, 30)),
      );

      expect(find.text('O plano terminou'), findsOneWidget);
      expect(find.text('0 de 3 treinos (0%)'), findsOneWidget);
      expect(find.text('Recomeçar a partir de hoje'), findsOneWidget);
      expect(find.text('Escolher próximo plano'), findsOneWidget);
      expect(find.text('Encerrar plano'), findsOneWidget);
      expect(find.text('SEGUINDO'), findsNothing);
      expect(find.text('PLANO CONCLUÍDO'), findsNothing);
      expect(find.text('Parar'), findsNothing);
    });

    testWidgets('a done session shows one badge and the run it points at', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final plan = await real(tester, () async {
        final plan = await seedWeek(
          name: 'Base',
          monday: DateTime(2026, 9, 28),
        );
        final first = (await repo.getPlan(plan.id))!.workoutsForWeek(0).first;
        await database.insert('run_activities', {
          'id': 'act-done',
          'started_at': DateTime(2026, 9, 28, 7).toIso8601String(),
          'status': 'completed',
          'created_at': '2026-09-28T07:00:00',
          'updated_at': '2026-09-28T07:00:00',
          'distance_meters': 5210.0,
          'avg_pace_sec_per_km': 330.0,
        });
        await repo.markPlanWorkoutCompleted(
          planWorkoutId: first.id,
          date: DateTime(2026, 9, 28),
          runActivityId: 'act-done',
        );
        return plan;
      });

      await pumpScreen(
        tester,
        RunPlanDetailScreen(planId: plan.id, today: DateTime(2026, 9, 30)),
      );

      expect(find.text('Concluído'), findsOneWidget);
      expect(find.text('Perdido'), findsNothing);
      expect(find.textContaining('5,21 km'), findsOneWidget);
      // Planned (ghost) versus done (filled) km in the header.
      expect(find.textContaining('km feitos'), findsOneWidget);
    });

    testWidgets('backing out of "Add session" leaves nothing behind', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final planId = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Vazio', weeks: 1);
        return plan.id;
      });

      await pumpScreen(tester, RunPlanDetailScreen(planId: planId));
      await tapAndLoad(tester, find.text('Adicionar treino').first);
      // The editor is open on a fresh session; leave without editing.
      await tester.runAsync(() async {
        await tester.pump(const Duration(milliseconds: 600));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(RunPlanWorkoutEditorScreen), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      });

      final plan = await real(tester, () => repo.getPlan(planId));
      expect(plan!.workouts, isEmpty);
    });

    testWidgets('library pins the followed plan on top with a Start button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      await real(tester, () async {
        // Updated last, so the plain library order would put it on top.
        await seedWeek(
          name: 'Plano seguido',
          monday: monday,
          weeks: 4,
          days: [now.weekday],
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repo.createPlan(name: 'Plano guardado', weeks: 4);
      });

      await pumpScreen(tester, const RunPlansScreen());

      expect(find.text('SEGUINDO AGORA'), findsOneWidget);
      expect(find.text('SEUS PLANOS'), findsOneWidget);
      final followed = tester.getTopLeft(find.text('Plano seguido')).dy;
      final other = tester.getTopLeft(find.text('Plano guardado')).dy;
      expect(followed, lessThan(other));
      expect(find.text('Iniciar'), findsOneWidget);
      expect(find.text('Seguir'), findsOneWidget);
      expect(find.text('Semana 1 de 4'), findsOneWidget);
    });

    testWidgets('an ended plan in the library says so instead of "following"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await real(
        tester,
        () => seedWeek(name: 'Antigo', monday: DateTime(2025, 1, 6)),
      );

      await pumpScreen(tester, const RunPlansScreen());

      expect(find.text('TERMINOU'), findsOneWidget);
      expect(find.text('SEGUINDO'), findsNothing);
      // The badge plus the progress bar carry the status; no repeated line.
      expect(find.text('0 de 3 treinos'), findsOneWidget);
      expect(find.text('Iniciar'), findsNothing);
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
