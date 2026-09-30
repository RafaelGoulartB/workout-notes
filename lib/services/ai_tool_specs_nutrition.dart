import 'package:workout_notes/services/ai_tool_spec.dart';

/// Nutrition tools (diary, history, food library, saved meals, profile).
List<AiToolSpec> nutritionToolSpecs(AiToolDeps d) => [
  AiToolSpec.window(
    name: 'get_nutrition_summary',
    description:
        'Resumo agregado de calorias, macros, gorduras, fibras, açúcares e micronutrientes, com meta ativa, cobertura e qualidade dos registros. Para itens/refeições de um dia use get_nutrition_diary_day.',
    defaultValue: 14,
    minimum: 3,
    maximum: 90,
    handler: (a) async => aiToolOk(
      await d.wellness.nutritionSummary(days: a.boundedInt('days', 14, 3, 90)),
    ),
  ),
  AiToolSpec(
    name: 'get_nutrition_diary_day',
    description:
        'Retorna o diário alimentar completo de um dia: refeições, alimentos, quantidades, origem, calorias, macros, gorduras, fibras, açúcares, sódio e todos os micronutrientes registrados. Preserva null como valor não informado.',
    properties: {
      'date': {
        'type': 'string',
        'description': 'Data local no formato YYYY-MM-DD. O padrão é hoje.',
      },
    },
    handler: (a) async => aiToolOk(
      await d.nutrition.diaryDay(date: a.string('date', alt: 'day')),
    ),
  ),
  AiToolSpec(
    name: 'get_nutrition_history',
    description:
        'Histórico diário completo de nutrientes. Retorna totais e cobertura por nutriente para cada dia registrado; dias sem registro ficam ausentes. Use end_date para paginar janelas antigas.',
    properties: {
      'days': {'type': 'integer', 'minimum': 1, 'maximum': 31, 'default': 30},
      'end_date': {
        'type': 'string',
        'description': 'Último dia da janela em YYYY-MM-DD; padrão hoje.',
      },
    },
    handler: (a) async => aiToolOk(
      await d.nutrition.history(
        days: a.boundedInt('days', 30, 1, 31),
        endDate: a.string('end_date'),
      ),
    ),
  ),
  AiToolSpec.window(
    name: 'get_micronutrient_summary',
    description:
        'Análise dedicada de fibras, açúcares, sódio, potássio, cálcio, ferro, magnésio, zinco e vitaminas A, C, D e B12. Inclui cobertura, médias somente em dias reportados e principais alimentos-fonte.',
    defaultValue: 30,
    minimum: 1,
    maximum: 90,
    handler: (a) async => aiToolOk(
      await d.nutrition.micronutrientSummary(
        days: a.boundedInt('days', 30, 1, 90),
      ),
    ),
  ),
  AiToolSpec(
    name: 'search_food_library',
    description:
        'Busca na biblioteca local de alimentos do usuário. Retorna IDs, origem, favorito, uso recente e a variante nutricional principal. Use get_food_detail com o ID para todas as variantes e porções.',
    properties: {
      'query': {
        'type': 'string',
        'description': 'Nome ou marca; vazio lista a biblioteca.',
      },
      'favorites_only': {'type': 'boolean', 'default': false},
      'recent_only': {'type': 'boolean', 'default': false},
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 30, 'default': 15},
    },
    handler: (a) async => aiToolOk(
      await d.nutrition.searchFoods(
        query: a.string('query', alt: 'search'),
        favoritesOnly: a.flag('favorites_only'),
        recentOnly: a.flag('recent_only'),
        limit: a.boundedInt('limit', 15, 1, 30),
      ),
    ),
  ),
  AiToolSpec(
    name: 'get_food_detail',
    description:
        'Detalha um alimento da biblioteca pelo ID: metadados, todas as variantes, nutrientes padronizados, nutrientes extras e porções/conversões.',
    properties: {
      'food_id': {
        'type': 'string',
        'description': 'ID retornado por search_food_library.',
      },
    },
    required: ['food_id'],
    handler: (a) async =>
        aiToolOk(await d.nutrition.foodDetail(a.requiredString('food_id'))),
  ),
  AiToolSpec(
    name: 'list_saved_meals',
    description:
        'Lista refeições-modelo salvas pelo usuário, com totais nutricionais atuais e IDs para detalhamento.',
    properties: {
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50, 'default': 20},
    },
    handler: (a) async => aiToolOk(
      await d.nutrition.listSavedMeals(limit: a.boundedInt('limit', 20, 1, 50)),
    ),
  ),
  AiToolSpec(
    name: 'get_saved_meal_detail',
    description:
        'Detalha uma refeição salva: porções, ingredientes, quantidades, referências de alimento e todos os nutrientes calculáveis.',
    properties: {
      'saved_meal_id': {
        'type': 'string',
        'description': 'ID retornado por list_saved_meals.',
      },
    },
    required: ['saved_meal_id'],
    handler: (a) async => aiToolOk(
      await d.nutrition.savedMealDetail(a.requiredString('saved_meal_id')),
    ),
  ),
  AiToolSpec(
    name: 'get_nutrition_profile',
    description:
        'Retorna a meta diária ativa e seu histórico, perfil usado na sugestão de meta (idade, sexo, altura, peso, atividade e razões de macros), tipos de refeição e contagens do diário, biblioteca e refeições salvas.',
    handler: (a) async => aiToolOk(await d.nutrition.profile()),
  ),
];
