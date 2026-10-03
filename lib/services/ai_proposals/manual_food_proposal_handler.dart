import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_json.dart';

/// `propose_manual_food_creation`: a food the user asked to register. The
/// proposal is user-confirmed: approving it opens the regular manual food form
/// pre-filled with the draft, and the food only exists once the user saves
/// that form (the UI then calls `AiProposalService.markApplied`).
class ManualFoodProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;

  ManualFoodProposalHandler({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  @override
  String get kind => 'manual_food';

  @override
  String get toolName => 'propose_manual_food_creation';

  @override
  AiToolDomain get domain => AiToolDomain.nutrition;

  @override
  AiProposalApplyMode get applyMode => AiProposalApplyMode.userConfirmed;

  static const _keys = {
    'name',
    'brand',
    'barcode',
    'reference_amount',
    'reference_unit',
    'per',
    'servings',
    'notes',
  };

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Draft a NEW library food (to log what was eaten use propose_meal_log). Fill in every nutrient and usual serving you can identify (typical values are fine without a label). The user reviews and saves it in the food form.',
    properties: {
      'name': AiSchema.str(),
      'brand': AiSchema.str(),
      'barcode': AiSchema.str(),
      'reference_amount': AiSchema.number('Values refer to this amount.'),
      'reference_unit': AiSchema.enumOf(['g', 'ml']),
      'per': AiSchema.object(
        {for (final key in _mainNutrients) key: AiSchema.number()},
        description:
            'calories kcal, *_g grams, *_mg mg, *_ug µg. Also: ${_otherNutrients.join(', ')}.',
      ),
      'servings': AiSchema.list(
        AiSchema.object(
          {
            'label': AiSchema.str(),
            'quantity': AiSchema.number(),
            'unit': AiSchema.str(),
            'grams_equivalent': AiSchema.number(),
            'ml_equivalent': AiSchema.number(),
          },
          required: ['label', 'unit'],
        ),
      ),
      'notes': AiSchema.str(),
    },
    required: ['name', 'reference_amount', 'reference_unit', 'per'],
  );

  static const _mainNutrients = ['calories', 'protein_g', 'carbs_g', 'fat_g'];

  /// The other nutrients the parser reads, named in the `per` description
  /// instead of repeated as properties (keeps the schema small).
  static final List<String> _otherNutrients = [
    for (final key in AiFoodLabelDraft.nutrientKeys)
      if (!_mainNutrients.contains(key)) key,
  ];

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly(_keys);
    final AiFoodLabelDraft draft;
    try {
      draft = AiFoodLabelDraft.fromJson(args.raw);
    } on FormatException catch (error) {
      var param = 'name';
      for (final key in _keys) {
        if (error.message.startsWith(key)) param = key;
      }
      throw AiProposalException(
        'invalid_args',
        error.message,
        param: param,
        hint: 'Fix "$param" and call the tool again.',
      );
    }
    final problems = draft.problems();
    if (problems.isNotEmpty) {
      throw AiProposalException(
        'invalid_args',
        'The nutrition values are not plausible: ${problems.first}.',
        param: 'per',
        hint:
            'Nutrient values are per ${draft.referenceAmount} ${draft.referenceUnit}. Check the numbers and units.',
      );
    }
    final nutrition = _db.nutritionRepo;
    final barcode = draft.barcode;
    if (barcode != null) {
      final existing = await nutrition.getFoodByBarcode(barcode);
      if (existing != null) {
        throw AiProposalException(
          'already_exists',
          'A food with this barcode already exists: "${existing.food.name}".',
          param: 'barcode',
          received: barcode,
          hint:
              'Use food id ${existing.food.id} with propose_meal_log instead of creating a duplicate.',
        );
      }
    }
    final warnings = <Map<String, dynamic>>[];
    final normalized = Food.normalizeForSearch(draft.name);
    final similar = await nutrition.searchLocalFoods(draft.name, limit: 5);
    final exact = similar.where(
      (r) =>
          Food.normalizeForSearch(r.food.name) == normalized &&
          (draft.brand == null ||
              (r.food.brand ?? '').toLowerCase() == draft.brand!.toLowerCase()),
    );
    if (exact.isNotEmpty) {
      warnings.add({
        'code': 'similar_food_exists',
        'name': exact.first.food.name,
      });
    }
    final notes = AiJson.text(args.raw['notes']);
    final values = {
      for (final entry in draft.values.toMap().entries)
        if (entry.value != null) entry.key: entry.value,
    };
    return AiProposalDraft(
      payload: {'draft': draft.toJson(), 'notes': ?notes},
      preview: {
        'v': kAiProposalPreviewVersion,
        'name': draft.name,
        'brand': draft.brand,
        'barcode': draft.barcode,
        'reference': {
          'amount': draft.referenceAmount,
          'unit': draft.referenceUnit,
        },
        'values': values,
        'servings': [for (final s in draft.servings) s.toJson()],
        'notes': notes,
        'estimated': true,
        'warnings': warnings,
      },
      summary: {
        'name': draft.name,
        'brand': draft.brand,
        'reference': '${draft.referenceAmount} ${draft.referenceUnit}',
        'calories': draft.values.calories,
        'protein_g': draft.values.proteinG,
        'carbs_g': draft.values.carbsG,
        'fat_g': draft.values.fatG,
        'servings': draft.servings.length,
        'next_step':
            'The user reviews and saves the food in a form; it is not saved yet.',
      },
    );
  }

  @override
  Map<String, dynamic> resultFacts(AiProposal proposal) => {
    'saved': true,
    if (proposal.result?['food_id'] != null)
      'food_id': proposal.result!['food_id'],
  };
}
