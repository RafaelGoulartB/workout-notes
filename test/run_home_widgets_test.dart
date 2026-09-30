import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/home/run_home_plan_card.dart';
import 'package:workout_notes/widgets/run/home/run_home_today_card.dart';
import 'package:workout_notes/widgets/run/home/run_home_week_card.dart';
import 'package:workout_notes/widgets/run/run_pending_review_banner.dart';
import 'package:workout_notes/widgets/run/run_week_strip.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

// Wednesday.
final _today = DateTime(2026, 8, 19);

RunPlanWorkout _workout({
  String name = 'Tempo 6 km',
  RunWorkoutKind kind = RunWorkoutKind.tempo,
  double meters = 6000,
}) => RunPlanWorkout(
  id: 'w',
  runPlanId: 'p',
  weekIndex: 0,
  dayOfWeek: 3,
  orderIndex: 0,
  kind: kind,
  name: name,
  targetDistanceMeters: meters,
  targetDurationSeconds: 2100,
  createdAt: DateTime(2026),
);

RunActivity _activity(String id) => RunActivity(
  id: id,
  startedAt: DateTime(2026, 8, 19, 7),
  endedAt: DateTime(2026, 8, 19, 7, 30),
  durationSeconds: 1800,
  movingTimeSeconds: 1800,
  distanceMeters: 5000,
  avgPaceSecPerKm: 360,
  maxPaceSecPerKm: null,
  calories: null,
  title: null,
  notes: null,
  status: 'completed',
  polylineSummary: null,
  createdAt: DateTime(2026, 8, 19),
  updatedAt: DateTime(2026, 8, 19),
);

RunTodayCard _card(
  RunTodayInfo info, {
  VoidCallback? onStart,
  VoidCallback? onFree,
  VoidCallback? onPlans,
  ValueChanged<String>? onRun,
}) => RunTodayCard(
  info: info,
  onStartSession: onStart ?? () {},
  onFreeRun: onFree ?? () {},
  onOpenPlans: onPlans ?? () {},
  onOpenRun: onRun ?? (_) {},
);

void main() {
  setUpAll(() => Intl.defaultLocale = 'pt_BR');
  tearDownAll(() => Intl.defaultLocale = null);

  group('RunTodayCard', () {
    testWidgets('planned session shows details and starts on tap', (
      tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(
        _app(
          _card(
            RunTodayInfo(
              status: RunTodayStatus.planned,
              date: _today,
              session: RunPlannedSession(
                date: _today,
                workout: _workout(),
                planName: 'Plano 10 km',
              ),
            ),
            onStart: () => started++,
          ),
        ),
      );

      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Tempo 6 km'), findsOneWidget);
      expect(find.textContaining('Tempo'), findsWidgets);
      expect(find.textContaining('Do plano Plano 10 km'), findsOneWidget);
      await tester.tap(find.byKey(const Key('run-today-start')));
      expect(started, 1);
    });

    testWidgets('done state shows the run and opens it', (tester) async {
      String? opened;
      await tester.pumpWidget(
        _app(
          _card(
            RunTodayInfo(
              status: RunTodayStatus.done,
              date: _today,
              session: RunPlannedSession(date: _today, workout: _workout()),
              doneActivity: _activity('run1'),
            ),
            onRun: (id) => opened = id,
          ),
        ),
      );

      expect(find.text('Treino de hoje concluído'), findsOneWidget);
      expect(find.textContaining('5,00'), findsOneWidget);
      await tester.tap(find.byTooltip('Abrir corrida'));
      expect(opened, 'run1');
    });

    testWidgets('rest day shows the next planned session', (tester) async {
      await tester.pumpWidget(
        _app(
          _card(
            RunTodayInfo(
              status: RunTodayStatus.rest,
              date: _today,
              next: RunPlannedSession(
                date: DateTime(2026, 8, 23),
                workout: _workout(
                  name: 'Longão',
                  kind: RunWorkoutKind.long,
                  meters: 14000,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Dia de descanso'), findsOneWidget);
      expect(find.text('Próximo treino'), findsOneWidget);
      expect(find.textContaining('Domingo'), findsOneWidget);
      expect(find.textContaining('Longão'), findsOneWidget);
      expect(find.textContaining('14 km'), findsOneWidget);
    });

    testWidgets('no plan offers a plan and a free run', (tester) async {
      var plans = 0;
      var free = 0;
      await tester.pumpWidget(
        _app(
          _card(
            RunTodayInfo(status: RunTodayStatus.none, date: _today),
            onPlans: () => plans++,
            onFree: () => free++,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('run-today-choose-plan')));
      await tester.tap(find.text('Corrida livre'));
      expect(plans, 1);
      expect(free, 1);
    });
  });

  group('RunWeekStrip', () {
    testWidgets('marks planned, missed and skipped days with tooltips', (
      tester,
    ) async {
      final monday = DateTime(2026, 8, 17);
      final days = [
        for (var i = 0; i < 7; i++)
          RunDayBucket(
            date: monday.add(Duration(days: i)),
            runCount: i == 0 ? 1 : 0,
            distanceMeters: i == 0 ? 5000 : 0,
          ),
      ];
      RunPlannedDay planned(
        int offset,
        RunPlannedDayState state, {
        String name = 'Tempo',
      }) => RunPlannedDay(
        date: monday.add(Duration(days: offset)),
        kind: RunWorkoutKind.tempo,
        name: name,
        plannedMeters: 8000,
        state: state,
      );

      await tester.pumpWidget(
        _app(
          RunWeekStrip(
            days: days,
            today: _today,
            planned: [
              planned(0, RunPlannedDayState.done),
              planned(1, RunPlannedDayState.missed, name: 'Leve'),
              planned(2, RunPlannedDayState.pending),
              planned(3, RunPlannedDayState.skipped, name: 'Fartlek'),
            ],
          ),
        ),
      );

      // Done day: the distance actually run.
      expect(find.byTooltip('5,00 km'), findsOneWidget);
      expect(find.byTooltip('Não realizado: Leve'), findsOneWidget);
      expect(find.byTooltip('Planejado: Tempo · 8,0 km'), findsOneWidget);
      expect(find.byTooltip('Pulado: Fartlek'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('RunWeekCard', () {
    RunProgressAnalytics analytics(List<RunActivity> runs) =>
        RunProgressAnalytics.fromActivities(
          runs,
          period: RunStatsPeriod.weeks4,
          now: DateTime(2026, 8, 19, 12),
        );

    RunHomeSnapshot snapshot({double? userGoal}) => RunHomeSnapshot(
      today: RunTodayInfo(status: RunTodayStatus.none, date: _today),
      plan: null,
      weekPlan: const [],
      userWeeklyGoalMeters: userGoal,
    );

    testWidgets('shows progress towards the user goal and lets it be edited', (
      tester,
    ) async {
      var edits = 0;
      await tester.pumpWidget(
        _app(
          RunWeekCard(
            analytics: analytics([_activity('a')]),
            snapshot: snapshot(userGoal: 20000),
            onEditGoal: () => edits++,
          ),
        ),
      );

      expect(find.text('25%'), findsOneWidget);
      expect(find.textContaining('5,00 km de 20,0 km'), findsOneWidget);
      expect(find.textContaining('Sua meta semanal'), findsOneWidget);
      expect(find.textContaining('Faltam 15,0 km'), findsOneWidget);
      await tester.tap(find.byTooltip('Definir meta semanal'));
      expect(edits, 1);
    });

    testWidgets('a reached goal says so', (tester) async {
      await tester.pumpWidget(
        _app(
          RunWeekCard(
            analytics: analytics([_activity('a')]),
            snapshot: snapshot(userGoal: 4000),
            onEditGoal: () {},
          ),
        ),
      );
      expect(find.textContaining('Meta atingida'), findsOneWidget);
    });

    testWidgets('no comparison line when both weeks are empty', (tester) async {
      await tester.pumpWidget(
        _app(
          RunWeekCard(
            analytics: analytics([
              RunActivity(
                id: 'old',
                startedAt: DateTime(2026, 7, 1, 7),
                endedAt: null,
                durationSeconds: 1800,
                movingTimeSeconds: 1800,
                distanceMeters: 5000,
                avgPaceSecPerKm: 360,
                maxPaceSecPerKm: null,
                calories: null,
                title: null,
                notes: null,
                status: 'completed',
                polylineSummary: null,
                createdAt: DateTime(2026, 7, 1),
                updatedAt: DateTime(2026, 7, 1),
              ),
            ]),
            snapshot: snapshot(),
          ),
        ),
      );
      expect(find.text('Semelhante à semana passada'), findsNothing);
      expect(find.text('Nenhuma corrida esta semana ainda'), findsOneWidget);
    });

    testWidgets('weekly goal dialog validates, saves and clears', (
      tester,
    ) async {
      RunWeeklyGoalEdit? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('pt'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showRunWeeklyGoalDialog(context, currentKm: 15);
                completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Meta semanal (km)'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('run-weekly-goal-field')),
        '0',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      expect(find.text('Informe uma distância maior que zero'), findsOneWidget);
      expect(completed, isFalse);

      await tester.enterText(
        find.byKey(const Key('run-weekly-goal-field')),
        '22,5',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(result?.km, 22.5);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover meta'));
      await tester.pumpAndSettle();
      expect(result?.km, isNull);
      expect(completed, isTrue);
    });
  });

  testWidgets('active plan card shows the week, progress and next session', (
    tester,
  ) async {
    var opened = 0;
    var all = 0;
    final plan = RunPlan(
      id: 'p',
      name: 'Plano 10 km',
      goalKind: RunPlanGoalKind.tenK,
      weeks: 8,
      status: RunPlanStatus.active,
      activatedAt: DateTime(2026, 8, 10),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      _app(
        RunActivePlanCard(
          planContext: RunPlanContext(
            plan: plan,
            weekIndex: 1,
            progress: const RunPlanProgress(
              totalSessions: 16,
              completedSessions: 5,
            ),
          ),
          next: RunPlannedSession(
            date: DateTime(2026, 8, 23),
            workout: _workout(name: 'Longão', kind: RunWorkoutKind.long),
          ),
          today: _today,
          onOpenPlan: () => opened++,
          onAllPlans: () => all++,
        ),
      ),
    );

    expect(find.text('Plano 10 km'), findsOneWidget);
    expect(find.textContaining('Semana 2 de 8'), findsOneWidget);
    expect(find.text('5 de 16 treinos'), findsOneWidget);
    expect(find.textContaining('Próximo:'), findsOneWidget);
    await tester.tap(find.text('Todos os planos'));
    expect(all, 1);
    await tester.tap(find.text('Plano 10 km'));
    expect(opened, 1);
  });

  testWidgets('the unsaved-run banner stays hidden without a pending run', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app(const RunPendingReviewBanner()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    expect(find.byKey(const Key('run-pending-review-banner')), findsNothing);
  });
}
