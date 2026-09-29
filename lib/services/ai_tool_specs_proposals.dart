import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/ai_manual_food_proposal.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// Guarded proposal tools. They never write data: the app previews the
/// proposal and the user approves it.
///
/// `propose_routine_change` is handled by `AiRoutineMutationService`, so it
/// has no handler here.
List<AiToolSpec> proposalToolSpecs() => [
  AiToolSpec(
    name: 'propose_manual_food_creation',
    proposal: true,
    description:
        'Prepare a prévia de um NOVO ALIMENTO MANUAL quando o usuário pedir para criar ou cadastrar um alimento. Identifique o alimento descrito e preencha o máximo possível de calorias, macronutrientes, gorduras, fibras, açúcares, sódio, micronutrientes e porções usuais. Use valores típicos estimados quando não houver rótulo exato e deixe de fora somente o que não puder ser identificado com segurança. Não salva nada: o app exibirá uma prévia e, após aprovação, abrirá o formulário manual preenchido para revisão e salvamento pelo usuário.',
    properties: {
      'name': {
        'type': 'string',
        'description': 'Nome claro e específico do alimento.',
      },
      'brand': {
        'type': 'string',
        'description':
            'Marca somente quando informada ou identificada; omita se desconhecida.',
      },
      'barcode': {
        'type': 'string',
        'description':
            'Código de barras somente quando informado; nunca invente.',
      },
      'reference_amount': {
        'type': 'number',
        'description':
            'Quantidade à qual todos os nutrientes se referem; prefira 100.',
      },
      'reference_unit': {
        'type': 'string',
        'description':
            'Unidade da referência; prefira g ou ml conforme o alimento.',
      },
      'per': {
        'type': 'object',
        'properties': _manualFoodNutrientProperties,
        'required': const [],
      },
      'servings': {
        'type': 'array',
        'description': 'Porções comuns úteis para registrar o alimento.',
        'items': {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'quantity': {'type': 'number'},
            'unit': {'type': 'string'},
            'grams_equivalent': {'type': 'number'},
            'ml_equivalent': {'type': 'number'},
          },
          'required': ['label', 'quantity', 'unit'],
        },
      },
      'notes': {
        'type': 'string',
        'description':
            'Resumo curto das estimativas, preparo ou variedade assumidos; não exponha raciocínio interno.',
      },
    },
    required: ['name', 'reference_amount', 'reference_unit', 'per', 'servings'],
    handler: (a) async => _prepareManualFoodProposal(a),
  ),
  AiToolSpec(
    name: 'propose_routine_change',
    proposal: true,
    description:
        'PREPARE A PROPOSTA quando o usuário pedir explicitamente para criar ou editar uma rotina. Não aplica dados: o app mostrará a prévia para aprovação. Para criar, primeiro use list_exercises e use IDs retornados. Para editar, primeiro use list_routines e get_routine_detail; mantenha os source_*_id retornados. Envie a árvore final inteira da rotina.',
    properties: {
      'action': {
        'type': 'string',
        'enum': ['create', 'update'],
      },
      'routine_id': {'type': 'string'},
      'routine': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'notes': {'type': 'string'},
          'days': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'source_day_id': {'type': 'string'},
                'name': {'type': 'string'},
                'notes': {'type': 'string'},
                'exercises': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'source_routine_exercise_id': {'type': 'string'},
                      'exercise_id': {'type': 'string'},
                      'rest_time_seconds': {'type': 'integer'},
                      'superset_group_id': {'type': 'string'},
                      'sets': {
                        'type': 'array',
                        'items': {
                          'type': 'object',
                          'properties': {
                            'source_set_id': {'type': 'string'},
                            'weight': {'type': 'number'},
                            'reps': {'type': 'integer'},
                            'distance': {'type': 'number'},
                            'time_seconds': {'type': 'integer'},
                            'is_warmup': {'type': 'boolean'},
                          },
                          'required': const [],
                        },
                      },
                    },
                    'required': ['exercise_id', 'sets'],
                  },
                },
              },
              'required': ['name', 'exercises'],
            },
          },
        },
        'required': ['name', 'days'],
      },
    },
    required: ['action', 'routine'],
  ),
];

AiToolResult _prepareManualFoodProposal(AiToolArgs args) {
  try {
    final draft = AiFoodLabelDraft.fromJson(args.raw);
    if (draft.referenceAmount <= 0 || draft.referenceUnit.trim().isEmpty) {
      return const AiToolResult(
        ok: false,
        code: 'invalid_args',
        message: 'A referência nutricional deve ter quantidade e unidade.',
      );
    }
    final proposal = AiManualFoodProposal(
      draft: draft,
      notes: nullableString(args['notes']),
    );
    return aiToolOk(proposal.toJson());
  } on FormatException catch (error) {
    return AiToolResult(
      ok: false,
      code: 'invalid_args',
      message: error.message,
    );
  }
}

const Map<String, dynamic> _manualFoodNutrientProperties = {
  'calories': {'type': 'number'},
  'protein_g': {'type': 'number'},
  'carbs_g': {'type': 'number'},
  'fat_g': {'type': 'number'},
  'saturated_fat_g': {'type': 'number'},
  'monounsaturated_fat_g': {'type': 'number'},
  'polyunsaturated_fat_g': {'type': 'number'},
  'trans_fat_g': {'type': 'number'},
  'fiber_g': {'type': 'number'},
  'sugars_g': {'type': 'number'},
  'sodium_mg': {'type': 'number'},
  'potassium_mg': {'type': 'number'},
  'calcium_mg': {'type': 'number'},
  'iron_mg': {'type': 'number'},
  'magnesium_mg': {'type': 'number'},
  'zinc_mg': {'type': 'number'},
  'vitamin_a_ug': {'type': 'number'},
  'vitamin_c_mg': {'type': 'number'},
  'vitamin_d_ug': {'type': 'number'},
  'vitamin_b12_ug': {'type': 'number'},
};
