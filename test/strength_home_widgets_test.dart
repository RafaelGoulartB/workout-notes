import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/screens/strength/strength_home_screen.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_muscles_card.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_today_card.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_trends_card.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_week_card.dart';

import 'support/ai_test_db.dart';
import 'support/strength_home_fixtures.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

const _pushDay = StrengthRoutineDayInfo(
  routineId: 'ppl',
  routineName: 'PPL',
  routineDayId: 'push',
  dayName: 'Push A',
  exerciseCount: 6,
  categories: [
    StrengthCategoryInfo(
      id: 'chest',
      name: 'Chest',
      localeKey: null,
      color: 0xFFE53935,
    ),
    StrengthCategoryInfo(
      id: 'triceps',
      name: 'Triceps',
      localeKey: null,
      color: 0xFF8E24AA,
    ),
  ],
  estimatedSeconds: 3000,
);

Future<void> _pumpHub(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pt'),
        home: const StrengthHomeScreen(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  });
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    Intl.defaultLocale = 'pt_BR';
  });

  tearDownAll(() => Intl.defaultLocale = null);

  group('StrengthTodayCard', () {
    final date = DateTime(2026, 9, 29);

    testWidgets('planned: shows the day and starts it', (tester) async {
      _phone(tester);
      StrengthRoutineDayInfo? started;
      await tester.pumpWidget(
        _app(
          StrengthTodayCard(
            info: StrengthTodayInfo(
              status: StrengthTodayStatus.planned,
              date: date,
              day: _pushDay,
              fromPlan: true,
            ),
            onStartDay: (d) => started = d,
            onBlankWorkout: () {},
            onOpenRoutines: () {},
            onOpenWorkout: (_) {},
          ),
        ),
      );
      expect(find.text('Push A'), findsOneWidget);
      expect(find.textContaining('6 exercícios'), findsOneWidget);
      expect(find.textContaining('50min'), findsOneWidget);
      expect(find.text('Sugerido pelo seu planejamento'), findsOneWidget);
      await tester.tap(find.byKey(const Key('strength-today-start')));
      expect(started?.routineDayId, 'push');
      expect(tester.takeException(), isNull);
    });

    testWidgets('done: opens the finished workout', (tester) async {
      _phone(tester);
      String? opened;
      await tester.pumpWidget(
        _app(
          StrengthTodayCard(
            info: StrengthTodayInfo(
              status: StrengthTodayStatus.done,
              date: date,
              doneWorkout: StrengthWorkoutSummary(
                id: 'w1',
                date: date,
                routineDayName: 'Pull A',
                volumeKg: 4200,
                workingSets: 16,
                durationSeconds: 3900,
              ),
              next: _pushDay,
            ),
            onStartDay: (_) {},
            onBlankWorkout: () {},
            onOpenRoutines: () {},
            onOpenWorkout: (id) => opened = id,
          ),
        ),
      );
      expect(find.text('Treino de hoje concluído'), findsOneWidget);
      expect(find.text('Pull A'), findsOneWidget);
      expect(find.textContaining('16 séries'), findsOneWidget);
      expect(find.textContaining('A seguir: Push A'), findsOneWidget);
      await tester.tap(find.byKey(const Key('strength-today-done-workout')));
      expect(opened, 'w1');
    });

    testWidgets('rest: shows the next session and lets train anyway', (
      tester,
    ) async {
      _phone(tester);
      StrengthRoutineDayInfo? started;
      await tester.pumpWidget(
        _app(
          StrengthTodayCard(
            info: StrengthTodayInfo(
              status: StrengthTodayStatus.rest,
              date: date,
              next: _pushDay,
              nextDate: DateTime(2026, 9, 30),
            ),
            onStartDay: (d) => started = d,
            onBlankWorkout: () {},
            onOpenRoutines: () {},
            onOpenWorkout: (_) {},
          ),
        ),
      );
      expect(find.text('Dia de descanso'), findsOneWidget);
      expect(find.textContaining('Próximo:'), findsOneWidget);
      await tester.tap(find.byKey(const Key('strength-today-train-anyway')));
      expect(started?.dayName, 'Push A');
    });

    testWidgets('none: offers creating a routine or a blank workout', (
      tester,
    ) async {
      _phone(tester);
      var routines = 0;
      var blank = 0;
      await tester.pumpWidget(
        _app(
          StrengthTodayCard(
            info: StrengthTodayInfo(
              status: StrengthTodayStatus.none,
              date: date,
            ),
            onStartDay: (_) {},
            onBlankWorkout: () => blank++,
            onOpenRoutines: () => routines++,
            onOpenWorkout: (_) {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('strength-today-create-routine')));
      await tester.tap(find.byKey(const Key('strength-today-blank')));
      expect((routines, blank), (1, 1));
    });
  });

  testWidgets('muscles card draws one bar per muscle without overflow', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const StrengthMusclesCard(
          muscles: [
            StrengthMuscleLoad(
              category: StrengthCategoryInfo(
                id: 'chest',
                name: 'Chest',
                localeKey: null,
                color: 0xFFE53935,
              ),
              sets: 12,
              volumeKg: 5000,
            ),
            StrengthMuscleLoad(
              category: StrengthCategoryInfo(
                id: 'legs',
                name: 'Legs',
                localeKey: null,
                color: 0xFF1E88E5,
              ),
              sets: 28,
              volumeKg: 9000,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Peito'), findsOneWidget);
    expect(find.text('Pernas'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.textContaining('10–20'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week card shows goal, sets range and comparison', (
    tester,
  ) async {
    _phone(tester);
    final now = DateTime(2026, 9, 29, 12);
    StrengthWorkoutSummary w(String date, double volume) {
      final d = DateTime.parse(date);
      return StrengthWorkoutSummary(
        id: date,
        date: DateTime(d.year, d.month, d.day),
        volumeKg: volume,
        workingSets: 12,
        durationSeconds: 3600,
        categoryIds: const ['chest'],
      );
    }

    final analytics = StrengthWeekAnalytics.fromWorkouts(
      [w('2026-09-22', 4000), w('2026-09-28', 5000)],
      period: RunStatsPeriod.weeks4,
      now: now,
    );
    var edited = 0;
    await tester.pumpWidget(
      _app(
        StrengthWeekCard(
          analytics: analytics,
          snapshot: StrengthHomeSnapshot(
            today: StrengthTodayInfo(
              status: StrengthTodayStatus.none,
              date: _epoch,
            ),
            planSessionsPerWeek: 3,
            planMinSetsPerWeek: 20,
            planMaxSetsPerWeek: 30,
            plannedStrengthDays: [1, 3, 5],
          ),
          onEditGoal: () => edited++,
        ),
      ),
    );
    expect(find.text('1 de 3 treinos'), findsOneWidget);
    expect(find.textContaining('Meta do seu plano'), findsOneWidget);
    expect(find.text('12 de 20–30'), findsOneWidget);
    expect(find.text('Volume 25% acima da semana passada'), findsOneWidget);
    // A plan goal cannot be edited by hand.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    expect(edited, 0);
  });

  testWidgets('trends card switches between its three charts', (tester) async {
    _phone(tester);
    final analytics = StrengthWeekAnalytics.fromWorkouts(
      [
        for (var i = 0; i < 6; i++)
          StrengthWorkoutSummary(
            id: 'w$i',
            date: DateTime(2026, 9, 28).subtract(Duration(days: 7 * i)),
            volumeKg: 3000.0 + i * 500,
            workingSets: 12,
            durationSeconds: 3000 + i * 300,
          ),
      ],
      period: RunStatsPeriod.weeks12,
      now: DateTime(2026, 9, 29),
    );
    await tester.pumpWidget(_app(StrengthTrendsCard(analytics: analytics)));
    expect(find.textContaining('Média semanal'), findsOneWidget);
    await tester.tap(find.text('Frequência'));
    await tester.pump();
    expect(find.text('treinos'), findsOneWidget);
    await tester.tap(find.text('Duração'));
    await tester.pump();
    expect(find.text('min'), findsOneWidget);
    expect(find.textContaining('Duração média'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('StrengthHomeScreen', () {
    late Database db;

    setUp(() async {
      db = await installAiTestDb();
      await seedStrengthCatalog(db);
      // These fixtures assert titles as seeded; skip the one-off inference.
      await db.insert('app_settings', {
        'key': StrengthRoutineDayInference.flagKey,
        'value': 'test',
      });
    });

    tearDown(uninstallAiTestDb);

    testWidgets('empty state offers routines and a first workout', (
      tester,
    ) async {
      _phone(tester);
      await _pumpHub(tester);
      expect(find.text('Musculação'), findsWidgets);
      expect(find.text('Novo treino'), findsOneWidget);
      expect(find.text('Nenhuma rotina ainda'), findsOneWidget);
      expect(find.text('Nenhum treino de musculação ainda'), findsOneWidget);
      expect(find.byKey(const Key('strength-empty-start')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with history: today, week, muscles, period and recents', (
      tester,
    ) async {
      _phone(tester);
      await tester.runAsync(() async {
        await seedRoutine(
          db,
          id: 'ppl',
          name: 'PPL',
          days: [
            (id: 'push', name: 'Push A'),
            (id: 'legs-day', name: 'Legs A'),
          ],
        );
        await seedRoutineExercise(
          db,
          id: 're1',
          dayId: 'legs-day',
          exerciseId: 'squat',
        );
        String day(int back) => DateTime.now()
            .subtract(Duration(days: back))
            .toIso8601String()
            .substring(0, 10);
        await seedWorkout(
          db,
          id: 'w1',
          date: day(9),
          routineId: 'ppl',
          routineDayId: 'push',
          feeling: 4,
          sets: [
            seedSet('bench', 100, 5),
            seedSet('bench', 100, 5),
            seedSet('squat', 100, 5),
          ],
        );
        await seedWorkout(
          db,
          id: 'w2',
          date: day(20),
          sets: [seedSet('squat', 120, 5)],
        );
      });

      await _pumpHub(tester);

      expect(find.text('Hoje'), findsOneWidget);
      // The day after Push A.
      expect(find.text('Legs A'), findsWidgets);
      expect(find.byKey(const Key('strength-today-start')), findsOneWidget);
      expect(find.text('ESTA SEMANA'), findsOneWidget);
      expect(find.text('MÚSCULOS NA SEMANA'), findsOneWidget);
      expect(find.text('RESUMO DO PERÍODO'), findsOneWidget);
      expect(find.text('EVOLUÇÃO'), findsOneWidget);
      expect(find.text('RECORDES RECENTES'), findsOneWidget);
      expect(find.text('TREINOS RECENTES'), findsOneWidget);
      expect(find.text('Push A'), findsOneWidget);
      // A workout without a routine is named after its muscle group.
      expect(find.text('Pernas'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

final DateTime _epoch = DateTime(2026, 9, 29);
