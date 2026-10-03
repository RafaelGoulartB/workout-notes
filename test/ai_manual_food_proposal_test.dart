import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/ai_manual_food_proposal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_manual_food_creation';

void main() {
  late Database db;
  late AiProposalService service;

  setUp(() async {
    db = await installTestDb();
    service = AiProposalService();
    await AiProposalFixtures.seedThread(db);
  });

  tearDown(uninstallTestDb);

  Map<String, dynamic> banana() => {
    'name': 'Banana prata',
    'reference_amount': 100,
    'reference_unit': 'g',
    'per': {
      'calories': 98,
      'protein_g': 1.3,
      'carbs_g': 26,
      'fat_g': 0.1,
      'potassium_mg': 358,
    },
    'servings': [
      {
        'label': '1 unidade média',
        'quantity': 1,
        'unit': 'unidade',
        'grams_equivalent': 80,
      },
    ],
    'notes': 'Valores típicos.',
  };

  Future<Map<String, dynamic>> refused(Map<String, dynamic> args) async {
    final result = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'c',
      toolName: _tool,
      args: args,
    );
    expect(result.ok, isFalse, reason: '${result.toMap()}');
    return result.toMap();
  }

  test(
    'stores an awaiting, user-confirmed proposal and saves no food',
    () async {
      final id = await prepareProposal(service, _tool, banana());
      final proposal = (await service.get(id))!;
      expect(proposal.kind, 'manual_food');
      expect(proposal.status, AiProposalStatus.awaiting);
      expect(service.applyModeOf(proposal), AiProposalApplyMode.userConfirmed);
      expect(await db.query('foods'), isEmpty);

      expect(proposal.preview['name'], 'Banana prata');
      expect(proposal.preview['reference'], {'amount': 100.0, 'unit': 'g'});
      expect(dig(proposal.preview, 'values.potassium_mg'), 358);
      expect(dig(proposal.preview, 'values.zinc_mg'), isNull);
      expect(dig(proposal.preview, 'servings.0.grams_equivalent'), 80);
      expect(proposal.preview['estimated'], true);

      // The payload round-trips into the form's draft.
      final draft = AiManualFoodProposal.fromJson(proposal.payload).draft;
      expect(draft.name, 'Banana prata');
      expect(draft.referenceAmount, 100);
      expect(draft.values.potassiumMg, 358);
    },
  );

  test(
    'rejects a missing or unreadable reference instead of defaulting it',
    () async {
      for (final broken in [
        banana()..remove('reference_amount'),
        banana()..['reference_amount'] = 'about a hundred',
        banana()..['reference_amount'] = 0,
        banana()..remove('reference_unit'),
      ]) {
        final error = await refused(broken);
        expect(error['code'], 'invalid_args');
        expect((error['data'] as Map)['param'], startsWith('reference_'));
      }
      expect(await db.query('ai_proposals'), isEmpty);
    },
  );

  test('accepts leading numbers and ignores "null" strings', () async {
    final id = await prepareProposal(service, _tool, {
      ...banana(),
      'brand': 'null',
      'barcode': '',
      'reference_amount': '100 g',
      'per': {'calories': '98 kcal', 'protein_g': '<1', 'fat_g': 'null'},
    });
    final preview = (await service.get(id))!.preview;
    expect(preview['brand'], isNull);
    expect(preview['barcode'], isNull);
    expect(preview['values'], {'calories': 98, 'protein_g': 1});
  });

  test('rejects impossible nutrition and unknown arguments', () async {
    var error = await refused({
      ...banana(),
      'per': {'calories': 98, 'carbs_g': 400},
    });
    expect(error['message'], contains('not plausible'));
    error = await refused({...banana(), 'price': 3});
    expect(error['message'], contains('price'));
    error = await refused({...banana()..remove('name')});
    expect((error['data'] as Map)['param'], 'name');
  });

  test(
    'refuses a barcode that already exists and points to the food',
    () async {
      final existing = await NutritionRepository().createManualFood(
        name: 'Banana',
        barcode: '123',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 90),
      );
      final error = await refused({...banana(), 'barcode': '123'});
      expect(error['code'], 'already_exists');
      expect((error['data'] as Map)['hint'], contains(existing.id));
    },
  );

  test('warns when a food with the same name exists', () async {
    await NutritionRepository().createManualFood(
      name: 'Banana prata',
      referenceAmount: 100,
      referenceUnit: 'g',
      referenceValues: const NutritionValues(calories: 90),
    );
    final id = await prepareProposal(service, _tool, banana());
    final warnings = (await service.get(id))!.preview['warnings'] as List;
    expect(codes(warnings), ['similar_food_exists']);
  });

  test('the tool schema lists every nutrient the parser reads', () {
    final spec = service.toolSpecs().firstWhere((s) => s.name == _tool);
    final per =
        ((((spec.schema['function'] as Map)['parameters'] as Map)['properties']
                    as Map)['per']
                as Map)['properties']
            as Map;
    final perDescription =
        dig(
              (((spec.schema['function'] as Map)['parameters']
                      as Map)['properties']
                  as Map)['per'],
              'description',
            )
            as String;
    // Every nutrient the parser reads is a property or named in the
    // description (keeps the schema small).
    for (final key in AiFoodLabelDraft.nutrientKeys) {
      expect(
        per.containsKey(key) || perDescription.contains(key),
        isTrue,
        reason: key,
      );
    }
    expect(per.keys, contains('calories'));
    expect(perDescription, contains('kcal'));
  });
}
