import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/widgets/ai/ai_proposal_card.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

/// Renders the card of every proposal kind from the preview the real handler
/// produced, so the card and the handlers cannot drift apart.
void main() {
  late Database db;
  late AiProposalService service;

  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pt_BR');
  });

  tearDown(() async => uninstallTestDb());

  Future<AiProposal> prepared(
    WidgetTester tester,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final proposal = await tester.runAsync(() async {
      final id = await prepareProposal(service, tool, args);
      return (await service.get(id))!;
    });
    return proposal!;
  }

  Future<void> show(
    WidgetTester tester,
    AiProposal proposal, {
    String locale = 'en',
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiProposalCard(
            proposal: proposal,
            busy: false,
            onApprove: () async {},
            onReject: () async {},
          ),
        ),
      ),
    ),
  );

  Future<void> setUpDb(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await installTestDb(seedMealTypes: true);
      service = AiProposalService(now: () => DateTime(2026, 9, 30, 9));
      await AiProposalFixtures.seedThreadAndExercises(db);
    });
  }

  testWidgets('routine update from the real handler', (tester) async {
    await setUpDb(tester);
    await tester.runAsync(() async {
      await db.insert('routines', {
        'id': 'r1',
        'name': 'Push',
        'created_at': AiProposalFixtures.now,
      });
      await db.insert('routine_days', {
        'id': 'd1',
        'routine_id': 'r1',
        'name': 'Mon',
        'order_index': 0,
      });
      await db.insert('routine_exercises', {
        'id': 'e1',
        'routine_day_id': 'd1',
        'exercise_id': 'bench',
        'order_index': 0,
      });
      await db.insert('predefined_sets', {
        'id': 's1',
        'routine_exercise_id': 'e1',
        'weight': 60.0,
        'reps': 10,
        'is_warmup': 0,
        'order_index': 0,
      });
    });
    final revision = await tester.runAsync(() => routineRevision(db, 'r1'));
    final proposal = await prepared(tester, 'propose_routine_change', {
      'action': 'update',
      'routine_id': 'r1',
      'revision': revision,
      'routine': {
        'name': 'Push',
        'days': [
          {
            'source_day_id': 'd1',
            'name': 'Mon',
            'exercises': [
              {
                'source_routine_exercise_id': 'e1',
                'exercise_id': 'squat',
                'sets': [
                  {'source_set_id': 's1', 'weight': 200, 'reps': 10},
                ],
              },
            ],
          },
        ],
      },
    });
    await show(tester, proposal);
    expect(find.textContaining('Bench press → Squat'), findsOneWidget);
    expect(
      find.textContaining('Weight: 60 kg → 200 kg', findRichText: true),
      findsOneWidget,
    );
    await show(tester, proposal, locale: 'pt');
    expect(
      find.textContaining('Carga: 60 kg → 200 kg', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('meal log, body measurement and goals', (tester) async {
    await setUpDb(tester);
    final food = await tester.runAsync(
      () => NutritionRepository().createManualFood(
        name: 'Oats',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 380,
          proteinG: 13,
          carbsG: 67,
          fatG: 7,
        ),
      ),
    );
    var proposal = await prepared(tester, 'propose_meal_log', {
      'meal_type': 'breakfast',
      'foods': [
        {'food_id': food!.id, 'quantity': 50, 'unit': 'g'},
      ],
    });
    await show(tester, proposal);
    expect(find.text('Log meal'), findsOneWidget);
    expect(find.text('Oats'), findsOneWidget);
    expect(find.text('190 kcal'), findsWidgets);
    expect(find.textContaining('Breakfast'), findsOneWidget);
    await show(tester, proposal, locale: 'pt');
    expect(find.text('Registrar refeição'), findsOneWidget);
    expect(find.textContaining('Café da manhã'), findsOneWidget);

    proposal = await prepared(tester, 'propose_body_measurement', {
      'measurements': [
        {'type': 'weight', 'value': 80.5},
        {'type': 'bloodPressure', 'value': 120, 'secondary_value': 80},
      ],
    });
    await show(tester, proposal, locale: 'pt');
    expect(find.text('Registrar medidas'), findsOneWidget);
    expect(find.text('80,5 kg'), findsOneWidget, reason: 'pt-BR decimals');
    expect(find.text('120/80 mmHg'), findsOneWidget);
    expect(find.text('Primeira medida deste tipo'), findsWidgets);

    proposal = await prepared(tester, 'propose_goal', {
      'action': 'create',
      'scope': 'aerobic',
      'metric': 'distance',
      'period': 'weekly',
      'target_value': 30,
    });
    await show(tester, proposal);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('30 km per week'), findsOneWidget);

    proposal = await prepared(tester, 'propose_nutrition_goal', {
      'calories': 2200,
      'protein_g': 150,
    });
    await show(tester, proposal);
    expect(find.text('Nutrition goal'), findsOneWidget);
    expect(find.text('2,200 kcal'), findsOneWidget);
    expect(find.text('150 g'), findsOneWidget);
  });

  testWidgets('workout schedule and manual food', (tester) async {
    await setUpDb(tester);
    await tester.runAsync(() async {
      await db.insert('routines', {
        'id': 'r1',
        'name': 'Push',
        'created_at': AiProposalFixtures.now,
      });
      await db.insert('routine_days', {
        'id': 'd1',
        'routine_id': 'r1',
        'name': 'Monday',
        'order_index': 0,
      });
      await db.insert('routine_exercises', {
        'id': 'e1',
        'routine_day_id': 'd1',
        'exercise_id': 'bench',
        'order_index': 0,
      });
    });
    var proposal = await prepared(tester, 'propose_workout_schedule', {
      'action': 'schedule_routine_day',
      'date': '2026-10-02',
      'routine_day_id': 'd1',
    });
    await show(tester, proposal);
    expect(find.text('Schedule workout'), findsOneWidget);
    expect(find.text('Push · Monday'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);
    await show(tester, proposal, locale: 'pt');
    expect(find.text('Agendar treino'), findsOneWidget);

    proposal = await prepared(tester, 'propose_manual_food_creation', {
      'name': 'Banana',
      'reference_amount': 100,
      'reference_unit': 'g',
      'per': {'calories': 89, 'protein_g': 1.1, 'carbs_g': 23, 'fat_g': 0.3},
    });
    await show(tester, proposal);
    expect(find.text('New food'), findsOneWidget);
    expect(find.text('Approve and review form'), findsOneWidget);
  });
}
