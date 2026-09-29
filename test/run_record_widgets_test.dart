import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_data_field.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/services/run_interval_engine.dart';
import 'package:workout_notes/services/run_workout_step_engine.dart';
import 'package:workout_notes/services/stationary_bike_tracking_service.dart';
import 'package:workout_notes/widgets/run/record/run_data_fields_grid.dart';
import 'package:workout_notes/widgets/run/record/run_goal_sheet.dart';
import 'package:workout_notes/widgets/run/record/run_record_countdown.dart';
import 'package:workout_notes/widgets/run/record/run_record_sheet.dart';
import 'package:workout_notes/widgets/run/record/run_record_step_card.dart';
import 'support/run_plan_fixtures.dart';

RunTrackingState _recording({bool autoPaused = false}) => RunTrackingState(
  supported: true,
  locationGranted: true,
  status: RunTrackingState.recording,
  activityId: 'a',
  startedAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  distanceMeters: 3200,
  durationSeconds: 1000,
  movingTimeSeconds: 980,
  currentPaceSecPerKm: 305,
  lat: 1,
  lng: 1,
  accuracyMeters: 5,
  trail: const [],
  splits: const [],
  currentSplit: null,
  errorCode: null,
  errorMessage: null,
  autoPaused: autoPaused,
);

Widget _app(Widget child, {String locale = 'pt'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    Intl.defaultLocale = 'pt_BR';
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('RunDataFieldsGrid', () {
    Future<void> pumpGrid(
      WidgetTester tester,
      List<RunDataField> fields, {
      ValueChanged<int>? onLongPress,
      VoidCallback? onCustomize,
    }) async {
      phone(tester);
      await tester.pumpWidget(
        _app(
          RunDataFieldsGrid(
            fields: fields,
            state: _recording(),
            activityType: CardioActivityType.running,
            now: DateTime(2026, 1, 1, 7, 5),
            onFieldLongPress: onLongPress,
            onCustomize: onCustomize,
          ),
        ),
      );
    }

    testWidgets('shows every chosen field with its label and value', (
      tester,
    ) async {
      await pumpGrid(tester, [
        RunDataField.time,
        RunDataField.distance,
        RunDataField.avgPace,
        RunDataField.clock,
        RunDataField.calories,
        RunDataField.lapTime,
      ]);
      expect(find.text('TEMPO'), findsOneWidget);
      expect(find.text('DISTÂNCIA'), findsOneWidget);
      expect(find.text('PACE MÉDIO'), findsOneWidget);
      expect(find.text('HORA ATUAL'), findsOneWidget);
      expect(find.text('CALORIAS'), findsOneWidget);
      expect(find.text('TEMPO DA VOLTA'), findsOneWidget);
      expect(find.text('16:40'), findsOneWidget); // 1000 s
      expect(find.text('3,20'), findsOneWidget);
      expect(find.text('07:05'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-pressing a field reports its position', (tester) async {
      int? pressed;
      await pumpGrid(
        tester,
        RunDataFieldLayout.defaults,
        onLongPress: (index) => pressed = index,
      );
      await tester.longPress(
        find.byKey(const ValueKey('run-data-field-distance')),
      );
      expect(pressed, 1);
    });

    testWidgets('the customize button is offered when editable', (
      tester,
    ) async {
      var opened = 0;
      await pumpGrid(
        tester,
        RunDataFieldLayout.defaults,
        onCustomize: () => opened++,
      );
      await tester.tap(find.byKey(const ValueKey('run-data-fields-customize')));
      expect(opened, 1);
    });
  });

  group('showRunDataFieldsSheet', () {
    testWidgets('adds, removes and restores fields, never below three', (
      tester,
    ) async {
      phone(tester);
      var current = List.of(RunDataFieldLayout.defaults);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showRunDataFieldsSheet(
                context,
                initial: current,
                onChanged: (next) => current = next,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Campos de dados'), findsOneWidget);
      // Add "Calorias" from the available chips.
      await tester.tap(find.widgetWithText(ActionChip, 'Calorias'));
      await tester.pumpAndSettle();
      expect(current, [...RunDataFieldLayout.defaults, RunDataField.calories]);

      // Remove it again, then try to go below three fields.
      final removeButtons = find.byIcon(Icons.remove_circle_outline_rounded);
      await tester.tap(removeButtons.last);
      await tester.pumpAndSettle();
      expect(current, RunDataFieldLayout.defaults);
      await tester.tap(find.byIcon(Icons.remove_circle_outline_rounded).first);
      await tester.pump();
      expect(current, RunDataFieldLayout.defaults);
      expect(find.text('Mantenha pelo menos 3 campos'), findsOneWidget);
    });
  });

  group('RunRecordStepCard', () {
    testWidgets('shows the next step and lets the runner skip', (tester) async {
      phone(tester);
      var skipped = 0;
      await tester.pumpWidget(
        _app(
          RunRecordStepCard(
            stepSnapshot: const RunStepSnapshot(
              phase: RunStepEnginePhase.running,
              stepIndex: 1,
              totalSteps: 4,
              role: RunStepRole.work,
              repIndex: 2,
              repTotal: 6,
              metric: RunIntervalMetric.distance,
              target: 400,
              progress: .4,
              remaining: 240,
              workRepsDone: 1,
              workRepsTotal: 6,
              nextRole: RunStepRole.recovery,
              nextMetric: RunIntervalMetric.time,
              nextTarget: 90,
              nextRepIndex: 2,
              nextRepTotal: 6,
            ),
            intervalSnapshot: const RunIntervalSnapshot.idle(),
            intervalsOn: false,
            onSkip: () => skipped++,
          ),
        ),
      );
      expect(find.text('Tiro 2 de 6'), findsOneWidget);
      expect(find.text('240 m'), findsOneWidget);
      expect(
        find.text('A seguir: Recuperação · Tiro 2 de 6 1:30'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('run-skip-step')));
      expect(skipped, 1);
    });

    testWidgets('quick intervals preview the following phase', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        _app(
          RunRecordStepCard(
            stepSnapshot: const RunStepSnapshot.idle(),
            intervalSnapshot: const RunIntervalSnapshot(
              phase: RunIntervalPhase.work,
              workIndex: 1,
              totalWorks: 8,
              progress: .5,
              remaining: 200,
              currentMetric: RunIntervalMetric.distance,
              currentTarget: 400,
              nextPhase: RunIntervalPhase.rest,
              nextMetric: RunIntervalMetric.time,
              nextTarget: 90,
            ),
            intervalsOn: true,
            onSkip: () {},
          ),
        ),
      );
      expect(find.text('Tiro 1/8'), findsOneWidget);
      expect(find.text('A seguir: Recuperação 1:30'), findsOneWidget);
    });

    testWidgets('the last step has no next preview', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        _app(
          RunRecordStepCard(
            stepSnapshot: const RunStepSnapshot(
              phase: RunStepEnginePhase.running,
              stepIndex: 3,
              totalSteps: 4,
              role: RunStepRole.cooldown,
              repIndex: 1,
              repTotal: 1,
              metric: RunIntervalMetric.distance,
              target: 500,
              progress: 0,
              remaining: 500,
              workRepsDone: 6,
              workRepsTotal: 6,
            ),
            intervalSnapshot: const RunIntervalSnapshot.idle(),
            intervalsOn: false,
            onSkip: () {},
          ),
        ),
      );
      expect(find.text('Última etapa'), findsOneWidget);
    });
  });

  group('RunRecordCountdown', () {
    testWidgets('a tap skips it', (tester) async {
      var skipped = 0;
      await tester.pumpWidget(
        _app(RunRecordCountdown(value: 3, onSkip: () => skipped++)),
      );
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Toque para pular'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-countdown')));
      expect(skipped, 1);
    });
  });

  group('showRunGoalSheet', () {
    Future<RunSessionGoal?> openAndDrive(
      WidgetTester tester,
      RunSessionGoal goal,
      Future<void> Function() interact,
    ) async {
      phone(tester);
      RunSessionGoal? result;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showRunGoalSheet(context, goal: goal),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await interact();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('accepts a custom distance with decimals', (tester) async {
      final result = await openAndDrive(
        tester,
        const RunSessionGoal.defaults(),
        () async {
          await tester.tap(find.text('Distância'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, '7,5');
          await tester.tap(find.text('Salvar'));
        },
      );
      expect(result!.enabled, isTrue);
      expect(result.metric, RunIntervalMetric.distance);
      expect(result.value, 7500);
    });

    testWidgets('accepts a custom time in minutes', (tester) async {
      final result = await openAndDrive(
        tester,
        const RunSessionGoal.defaults(),
        () async {
          await tester.tap(find.text('Tempo'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, '52');
          await tester.tap(find.text('Salvar'));
        },
      );
      expect(result!.metric, RunIntervalMetric.time);
      expect(result.value, 52 * 60);
    });

    testWidgets(
      'a preset still works and an invalid custom value blocks save',
      (tester) async {
        final blocked = await openAndDrive(
          tester,
          const RunSessionGoal.defaults(),
          () async {
            await tester.tap(find.text('Distância'));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField).first, '0');
            await tester.pump();
            expect(
              find.text('Informe um valor maior que zero'),
              findsOneWidget,
            );
            await tester.tap(find.text('Salvar'));
          },
        );
        expect(blocked, isNull);
      },
    );

    testWidgets('a pace goal with tolerance can be set alone', (tester) async {
      final result = await openAndDrive(
        tester,
        const RunSessionGoal.defaults(),
        () async {
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, '5:30');
          await tester.tap(find.text('±10%'));
          await tester.pump();
          await tester.tap(find.text('Salvar'));
        },
      );
      expect(result!.enabled, isFalse);
      expect(result.paceTargetSecPerKm, 330);
      expect(result.paceTolerancePercent, 10);
    });

    testWidgets('an invalid pace does not save', (tester) async {
      final result = await openAndDrive(
        tester,
        const RunSessionGoal.defaults(),
        () async {
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, '5,5');
          await tester.pump();
          await tester.tap(find.text('Salvar'));
          await tester.pump();
          expect(find.text('Use m:ss, por exemplo 5:30'), findsOneWidget);
        },
      );
      expect(result, isNull);
    });

    testWidgets('an existing goal opens filled in', (tester) async {
      final result = await openAndDrive(
        tester,
        const RunSessionGoal(
          enabled: true,
          metric: RunIntervalMetric.distance,
          value: 8400,
          paceTargetSecPerKm: 345,
        ),
        () async {
          expect(find.widgetWithText(TextField, '8,40'), findsOneWidget);
          expect(find.widgetWithText(TextField, '5:45'), findsOneWidget);
          await tester.tap(find.text('Salvar'));
        },
      );
      expect(result!.value, 8400);
      expect(result.paceTargetSecPerKm, 345);
    });
  });

  group('RunRecordSheet while recording', () {
    Widget sheet(
      RunTrackingState state, {
      CardioActivityType type = CardioActivityType.running,
      List<String>? calls,
      List<RunDataField>? fields,
    }) {
      void log(String name) => calls?.add(name);
      return MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RunRecordSheet(
            scrollController: ScrollController(),
            onContentHeight: (_) {},
            state: state,
            activityType: type,
            busy: false,
            expanded: false,
            showDebugSimulate: false,
            fields: fields ?? RunDataFieldLayout.defaults,
            bodyWeightKg: 70,
            onCustomizeFields: () => log('customize'),
            onFieldLongPress: (i) => log('field-$i'),
            intervalsOn: false,
            intervalSnapshot: const RunIntervalSnapshot.idle(),
            intervalPreset: const RunIntervalPreset.defaults(),
            planWorkout: null,
            onDetachPlan: null,
            todayWorkout: null,
            onUseTodayWorkout: null,
            stepSnapshot: const RunStepSnapshot.idle(),
            goal: const RunSessionGoal.defaults(),
            goalSnapshot: const RunGoalSnapshot.none(),
            onEditGoal: null,
            onClearGoal: null,
            onIntervalsChanged: null,
            voiceEnabled: true,
            headphonesOnly: false,
            headsetConnected: false,
            notificationsNeedAttention: false,
            onActivityTypeChanged: null,
            onOpenVoiceSettings: () {},
            onOpenPermissions: () {},
            onStart: () => log('start'),
            onDebugSimulate: () {},
            onPause: () => log('pause'),
            onResume: () => log('resume'),
            onLap: () => log('lap'),
            onFinish: () => log('finish'),
            onSkipStep: () => log('skip'),
          ),
        ),
      );
    }

    testWidgets('shows the chosen fields plus pause, lap and finish', (
      tester,
    ) async {
      phone(tester);
      final calls = <String>[];
      await tester.pumpWidget(
        sheet(
          _recording(),
          calls: calls,
          fields: [
            RunDataField.time,
            RunDataField.distance,
            RunDataField.pace,
            RunDataField.avgPace,
          ],
        ),
      );
      expect(
        find.byKey(const ValueKey('run-data-field-avg_pace')),
        findsOneWidget,
      );
      expect(find.text('Pausar'), findsOneWidget);
      expect(find.text('Volta'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-paused-pill')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('run-lap')));
      await tester.tap(find.byKey(const ValueKey('run-pause-resume')));
      await tester.tap(find.byKey(const ValueKey('run-finish')));
      await tester.longPress(find.byKey(const ValueKey('run-data-field-pace')));
      await tester.tap(find.byKey(const ValueKey('run-data-fields-customize')));
      expect(calls, ['lap', 'pause', 'finish', 'field-2', 'customize']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('auto-pause is shown and the button resumes early', (
      tester,
    ) async {
      phone(tester);
      final calls = <String>[];
      await tester.pumpWidget(
        sheet(_recording(autoPaused: true), calls: calls),
      );
      expect(find.text('Auto-pausado'), findsOneWidget);
      expect(
        find.textContaining('Retoma quando você se mexer'),
        findsOneWidget,
      );
      expect(find.text('Retomar'), findsOneWidget);
      // Standing still: no stale pace on screen.
      expect(find.text('--:--'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-pause-resume')));
      expect(calls, ['resume']);
    });

    testWidgets('a treadmill session shows time, calories and clock only', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        sheet(_recording(), type: CardioActivityType.treadmill),
      );
      expect(find.byKey(const ValueKey('run-data-field-time')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('run-data-field-calories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('run-data-field-clock')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('run-data-field-distance')),
        findsNothing,
      );
      // No laps indoors, and the fixed layout has no editor.
      expect(find.byKey(const ValueKey('run-lap')), findsNothing);
      expect(
        find.byKey(const ValueKey('run-data-fields-customize')),
        findsNothing,
      );
    });

    testWidgets('the start button is the only control before the run', (
      tester,
    ) async {
      phone(tester);
      final calls = <String>[];
      await tester.pumpWidget(
        sheet(
          _recording().copyWith(status: RunTrackingState.idle),
          calls: calls,
        ),
      );
      expect(find.byKey(const ValueKey('run-lap')), findsNothing);
      expect(find.byKey(const ValueKey('run-data-field-time')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('run-start')));
      expect(calls, ['start']);
    });
  });

  group('RunRecordScreen during a debug run', () {
    testWidgets('marks a lap from the record screen', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      phone(tester);
      SharedPreferences.setMockInitialValues({});
      final service = RunTrackingService.instance;
      try {
        await service.startDebugSimulation();
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const RunRecordScreen(),
          ),
        );
        await tester.pump(const Duration(seconds: 4));

        expect(
          find.byKey(const ValueKey('run-data-field-time')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('run-lap')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(service.state.laps, hasLength(1));
        expect(find.text('Volta 1 marcada'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await service.discard();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('RunRecordScreen before the run', () {
    late Database database;

    setUp(() async {
      database = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 53,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: DatabaseSchema.onCreate,
        ),
      );
      DatabaseHelper.overrideDatabase = database;
    });

    tearDown(() async {
      await StationaryBikeTrackingService.instance.discard();
      DatabaseHelper.overrideDatabase = null;
      await database.close();
    });

    /// Runs [body] as a non-Android platform (the native tracking channels do
    /// not exist in tests) and restores the platform before the framework's
    /// invariant check.
    void screenTest(
      String description,
      Future<void> Function(WidgetTester tester) body,
    ) {
      testWidgets(description, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await body(tester);
          // Tear the screen (and the map's tile timers) down before the
          // framework checks for pending timers.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 11));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    Future<void> pumpScreen(
      WidgetTester tester, {
      CardioActivityType type = CardioActivityType.running,
    }) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunRecordScreen(initialActivityType: type),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    screenTest('hides the zero metrics and localizes the interval preset', (
      tester,
    ) async {
      await pumpScreen(tester);

      // No live numbers before starting.
      expect(find.byKey(const ValueKey('run-data-field-time')), findsNothing);
      expect(find.text('00:00'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
      expect(find.text('Nesta corrida'.toUpperCase()), findsOneWidget);
      // No English left in the preset summary.
      expect(find.textContaining('Work'), findsNothing);
      expect(find.textContaining('Rest'), findsNothing);
      expect(find.text('Tiro 400 m · Recuperação 1:30 · ×8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    screenTest('offers the treadmill next to run and bike', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('cardio-activity-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Esteira'), findsOneWidget);
      expect(find.text('Bicicleta estacionária'), findsOneWidget);

      await tester.tap(find.text('Esteira'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Informe a distância mostrada na esteira'),
        findsOneWidget,
      );
      // Indoor: no GPS settings/chip, no goal / interval rows.
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.text('Intervalos'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    screenTest('suggests today\'s workout and attaches it in one tap', (
      tester,
    ) async {
      final repo = RunPlanRepository();
      final plan = await tester.runAsync(
        () => repo.createPlan(name: 'Plano 10K', weeks: 4),
      );
      final workout = await tester.runAsync(
        () => repo.addWorkout(
          planId: plan!.id,
          weekIndex: 0,
          kind: RunWorkoutKind.tempo,
          name: 'Tempo run 6 km',
          targetDistanceMeters: 6000,
        ),
      );
      await tester.runAsync(
        () => scheduleRunFixture(repo, 
          date: DateTime.now(),
          runPlanId: plan!.id,
          runPlanWorkoutId: workout!.id,
        ),
      );

      await pumpScreen(tester);

      expect(find.text('TREINO DE HOJE'), findsOneWidget);
      expect(find.text('Tempo run 6 km'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-use-today-workout')));
      await tester.pumpAndSettle();

      // The suggestion becomes the attached workout of "Nesta corrida".
      expect(find.text('TREINO DE HOJE'), findsNothing);
      expect(find.text('Tempo run 6 km'), findsOneWidget);
      expect(find.byTooltip('Remover treino'), findsOneWidget);
      // A workout replaces the quick interval preset.
      expect(find.text('Intervalos'), findsNothing);

      await tester.tap(find.byTooltip('Remover treino'));
      await tester.pumpAndSettle();
      expect(find.text('TREINO DE HOJE'), findsOneWidget);
      expect(find.text('Intervalos'), findsOneWidget);
    });

    screenTest('a screen opened with a workout does not suggest another', (
      tester,
    ) async {
      final workout = RunPlanWorkout(
        id: 'w',
        runPlanId: 'p',
        weekIndex: 0,
        orderIndex: 0,
        kind: RunWorkoutKind.easy,
        name: 'Rodagem',
        targetDistanceMeters: 5000,
        createdAt: DateTime(2026, 1, 1),
      );
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunRecordScreen(planWorkout: workout),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('TREINO DE HOJE'), findsNothing);
      expect(find.text('Rodagem'), findsOneWidget);
      // Opened by the calendar: the runner cannot detach it here.
      expect(find.byTooltip('Remover treino'), findsNothing);
    });
  });
}
