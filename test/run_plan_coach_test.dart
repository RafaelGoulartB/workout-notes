import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_detail_screen.dart';
import 'package:workout_notes/services/run_plan_adaptation.dart';
import 'package:workout_notes/services/run_plan_coach.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/runner_strength_routine.dart';

/// A runner following a "Faster 5K" plan, as the app stores it: created by
/// the wizard, activated, sessions on the calendar, runs recorded.
void main() {
  late Database database;
  late RunPlanRepository plans;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 52,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    plans = RunPlanRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  DateTime monday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  final today = monday(DateTime.now());

  Future<RunPlan> followFiveK({int weeksAgo = 3}) async {
    final plan = await RunPlanTemplates.create(
      plans,
      RunPlanTemplates.fiveK,
      name: '5 km mais rápido',
      config: const RunPlanBuildConfig(
        sessionsPerWeek: 4,
        availableDays: [2, 4, 6, 7],
        intent: RunPlanIntent.pb,
        currentWeeklyKm: 20,
        calibration: RunPlanPaceCalibration(
          distanceMeters: 5000,
          timeSeconds: 1500,
        ),
        paceSource: RunPlanPaceSource.recent,
      ),
    );
    final start = today.subtract(Duration(days: 7 * weeksAgo));
    await plans.activatePlan(plan.id, from: start);
    // activatePlan only materialises from the activation week on; the past
    // weeks are what this runner had on the calendar.
    for (var w = 0; w < weeksAgo; w++) {
      await plans.materializeWeek(
        planId: plan.id,
        weekIndex: w,
        weekStart: start.add(Duration(days: 7 * w)),
      );
    }
    return (await plans.getPlan(plan.id))!;
  }

  /// Records a run on [date] and ticks off the calendar row of that day.
  Future<void> run(
    RunPlan plan,
    DateTime date, {
    double km = 5,
    double? rpe,
    bool linkToPlan = true,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await database.insert('run_activities', {
      'id': id,
      'started_at': date.add(const Duration(hours: 7)).toIso8601String(),
      'duration_seconds': (km * 360).round(),
      'moving_time_seconds': (km * 360).round(),
      'distance_meters': km * 1000,
      'status': 'completed',
      'rpe': rpe,
      'created_at': now,
      'updated_at': now,
    });
    if (!linkToPlan) return;
    final rows = await plans.getScheduledRunsForDate(date);
    for (final row in rows.where((r) => r.runPlanId == plan.id)) {
      await plans.markPlanWorkoutCompleted(
        planWorkoutId: row.runPlanWorkoutId!,
        date: date,
        runActivityId: id,
      );
    }
  }

  /// Runs every session of plan week [week] at its planned distance.
  Future<void> runWeek(RunPlan plan, int week, {double fraction = 1}) async {
    final start = monday(plan.activatedAt!).add(Duration(days: 7 * week));
    final sessions = plan.workoutsForWeek(week);
    var budget = sessions.fold<double>(
      0,
      (s, w) => s + w.plannedDistanceMeters / 1000,
    );
    budget *= fraction;
    for (final session in sessions) {
      final km = session.plannedDistanceMeters / 1000;
      if (budget <= 0) break;
      await run(
        plan,
        start.add(Duration(days: session.dayOfWeek! - 1)),
        km: km <= budget ? km : budget,
      );
      budget -= km;
    }
  }

  test('the plan remembers how it was built', () async {
    final plan = await followFiveK(weeksAgo: 0);
    expect(plan.templateKey, '5k');
    final config = RunPlanBuildConfig.fromJson(plan.config);
    expect(config?.currentWeeklyKm, 20);
    expect(config?.sessionsPerWeek, 4);
  });

  test('a fully run week needs no adjustment', () async {
    var plan = await followFiveK(weeksAgo: 1);
    await runWeek(plan, 0);
    plan = (await plans.getPlan(plan.id))!;
    expect(await RunPlanCoach().review(plan), isNull);
  });

  test('a missed week is proposed as a step back and re-planned', () async {
    var plan = await followFiveK(weeksAgo: 2);
    await runWeek(plan, 0);
    // Week 1: sick. One 3 km jog, not even started from the plan.
    await run(
      plan,
      monday(plan.activatedAt!).add(const Duration(days: 9)),
      km: 3,
      linkToPlan: false,
    );
    plan = (await plans.getPlan(plan.id))!;
    final weeksBefore = plan.weeks;
    final plannedWeek2 = plan.weeklyDistanceMeters(2) / 1000;

    final coach = RunPlanCoach();
    final proposal = await coach.review(plan);
    expect(proposal, isNotNull);
    expect(proposal!.adjustment, RunPlanAdjustment.stepBack);
    expect(proposal.fromWeek, 2);
    expect(proposal.lastWeek!.doneKm, closeTo(3, 0.01));

    await coach.apply(plan, proposal);
    plan = (await plans.getPlan(plan.id))!;
    // The missed week pushes the plan one week further instead of being
    // skipped (no race date).
    expect(plan.weeks, weeksBefore + 1);
    // This week restarts below what was planned before the break.
    expect(plan.weeklyDistanceMeters(2) / 1000, lessThan(plannedWeek2));
    // History is untouched: week 0 is still fully completed.
    final statuses = await plans.getPlanWorkoutStatuses(plan.id);
    expect(
      plan
          .workoutsForWeek(0)
          .every((w) => statuses[w.id] == ScheduledRunStatus.completed),
      isTrue,
    );
    // The new weeks are on the calendar.
    final thisWeek = await plans.getScheduledRuns(
      today,
      today.add(const Duration(days: 6)),
    );
    expect(thisWeek.where((r) => r.runPlanId == plan.id), isNotEmpty);
    expect(plan.config?[RunPlanCoach.replannedFromWeekKey], 2);

    // Answered once per week.
    expect(await coach.review(plan), isNull);
    final log = await plans.listAdaptations(plan.id);
    expect(log.single.applied, isTrue);
    expect(log.single.kind, 'stepBack');
  });

  test('a partial week can be dismissed and is not asked again', () async {
    var plan = await followFiveK(weeksAgo: 1);
    await runWeek(plan, 0, fraction: 0.6);
    plan = (await plans.getPlan(plan.id))!;
    final coach = RunPlanCoach();
    final proposal = await coach.review(plan);
    expect(proposal?.adjustment, RunPlanAdjustment.hold);
    final before = plan.weeklyDistanceMeters(1);
    await coach.dismiss(plan, proposal!);
    plan = (await plans.getPlan(plan.id))!;
    expect(plan.weeklyDistanceMeters(1), before);
    expect(await coach.review(plan), isNull);
  });

  test('re-planning never overwrites a week already under way', () async {
    final plan = await followFiveK(weeksAgo: 1);
    await runWeek(plan, 1, fraction: 0.2);
    expect(
      () => plans.replaceWeeksFrom(plan.id, fromWeek: 1, weeks: const []),
      throwsStateError,
    );
  });

  test('moving a session moves its calendar row too', () async {
    final plan = await followFiveK(weeksAgo: 0);
    final session = plan
        .workoutsForWeek(0)
        .firstWhere((w) => w.kind != RunWorkoutKind.long);
    await plans.moveWorkoutToDay(session.id, 3);
    final rows = await plans.getScheduledRunsForPlan(plan.id);
    final row = rows.firstWhere((r) => r.runPlanWorkoutId == session.id);
    expect(row.date.weekday, 3);
    expect(monday(row.date), monday(plan.activatedAt!));
  });

  test('strength for runners is created once and starts a workout', () async {
    final strength = RunnerStrengthRoutine();
    final id = await strength.ensure(pt: true);
    expect(await strength.ensure(pt: true), id);
    final days = await RoutineRepository().getRoutineDays(id);
    expect(days, hasLength(2));
    final exercises = await RoutineRepository().getRoutineExercises(
      days.first['id'] as String,
    );
    expect(exercises, hasLength(greaterThanOrEqualTo(4)));
    final workoutId = await strength.startWorkout(pt: true, sessionIndex: 1);
    final entries = await database.query(
      'exercise_entries',
      where: 'workout_id = ?',
      whereArgs: [workoutId],
    );
    expect(entries, isNotEmpty);
  });

  group('plan screen', () {
    Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
      late T result;
      await tester.runAsync(() async {
        result = await body();
      });
      return result;
    }

    Future<void> pumpPlan(WidgetTester tester, String planId) async {
      await tester.binding.setSurfaceSize(const Size(430, 1600));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: RunPlanDetailScreen(planId: planId),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      });
    }

    testWidgets('a missed week shows the adjustment and applies it', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final plan = await real(tester, () async {
        final plan = await followFiveK(weeksAgo: 2);
        await runWeek(plan, 0);
        return plan;
      });
      await pumpPlan(tester, plan.id);

      expect(find.text('Semana perdida — retomada mais leve'), findsOneWidget);
      expect(find.textContaining('Semana passada: '), findsOneWidget);
      expect(find.textContaining('O plano ganha 1 semana'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Aplicar ajuste'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await tester.pump();
      });
      expect(find.text('Semana perdida — retomada mais leve'), findsNothing);
      expect(find.textContaining('Ajustado em'), findsOneWidget);
      final log = await real(tester, () => plans.listAdaptations(plan.id));
      expect(log.single.applied, isTrue);
    });

    testWidgets('a finished plan offers the next step instead of week 1', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final plan = await real(tester, () => followFiveK(weeksAgo: 14));
      await pumpPlan(tester, plan.id);

      expect(find.text('Plano concluído'), findsOneWidget);
      expect(find.text('Próximo passo'.toUpperCase()), findsOneWidget);
      expect(find.text('Dos 5 aos 10 km'), findsOneWidget);
      expect(find.textContaining('Semana 1 de'), findsNothing);
    });
  });
}
