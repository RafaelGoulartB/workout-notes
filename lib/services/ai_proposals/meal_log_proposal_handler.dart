import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_with_items.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_derived_id.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

/// `propose_meal_log`: log what the user ate (foods from the library and/or
/// saved meals) into a meal of a day, several items in one card.
///
/// Foods are resolved by id from the food library and converted exactly like
/// the app's quantity sheet does (`NutritionConversion`), so the numbers on
/// the card are the numbers that land in the diary. The preview carries a
/// fingerprint of every food/saved meal it used: if one is edited before the
/// user approves, the proposal goes stale instead of logging different numbers
/// than the user saw.
class MealLogProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;
  final DateTime Function() _now;

  MealLogProposalHandler({DatabaseHelper? db, DateTime Function()? now})
    : _db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  @override
  String get kind => 'meal_log';

  @override
  String get toolName => 'propose_meal_log';

  @override
  AiToolDomain get domain => AiToolDomain.nutrition;

  static const maxFoods = 20;
  static const maxSavedMeals = 5;
  static const maxQuantity = 10000.0;

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Log what the user ate into one meal of a day. food_id, variant_id and serving_id come from search_food_library (food_id gives the detail), saved_meal_id from list_saved_meals. A food not in the library: propose_manual_food_creation first.',
    properties: {
      'date': AiSchema.date('Default today'),
      'meal_type': AiSchema.str(
        'breakfast, lunch, dinner, snacks or custom key.',
      ),
      'foods': AiSchema.list(
        AiSchema.object(
          {
            'food_id': AiSchema.str(),
            'quantity': AiSchema.number('In unit.'),
            'unit': AiSchema.str('g, ml or serving.'),
            'serving_id': AiSchema.str(),
            'variant_id': AiSchema.str(),
          },
          required: ['food_id', 'quantity', 'unit'],
        ),
      ),
      'saved_meals': AiSchema.list(
        AiSchema.object(
          {'saved_meal_id': AiSchema.str()},
          required: ['saved_meal_id'],
        ),
      ),
    },
    required: ['meal_type'],
  );

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({'date', 'meal_type', 'foods', 'saved_meals'});
    final today = dateKey(_now());
    final date = args.optionalDate('date') ?? today;
    if (date.compareTo(today) > 0) {
      throw AiProposalException(
        'invalid_args',
        '"date" cannot be in the future.',
        param: 'date',
        expected: 'a date on or before $today',
        received: date,
        hint: 'Log meals on the day they were eaten (today or earlier).',
      );
    }
    final mealKey = args.requiredString('meal_type', maxLength: 60);
    final foodArgs = args.optionalObjects('foods', max: maxFoods) ?? const [];
    final savedArgs =
        args.optionalObjects('saved_meals', max: maxSavedMeals) ?? const [];
    if (foodArgs.isEmpty && savedArgs.isEmpty) {
      throw const AiProposalException(
        'invalid_args',
        'Nothing to log.',
        param: 'foods',
        hint: 'Send at least one entry in "foods" or "saved_meals".',
      );
    }
    final nutrition = _db.nutritionRepo;
    final mealType = await nutrition.getMealTypeByKeyIn(db, mealKey);
    if (mealType == null) {
      final keys = [for (final t in await nutrition.getMealTypes()) t.key];
      throw AiProposalException(
        'invalid_args',
        'Unknown meal type "$mealKey".',
        param: 'meal_type',
        expected: 'one of: ${keys.join(', ')}',
        received: mealKey,
        hint: 'Use one of these meal keys: ${keys.join(', ')}.',
      );
    }

    final foods = <Map<String, dynamic>>[];
    final items = <Map<String, dynamic>>[];
    final warnings = <Map<String, dynamic>>[];
    var incomplete = false;
    final totals = _Totals();

    for (final entry in foodArgs) {
      entry.allowOnly({
        'food_id',
        'quantity',
        'unit',
        'serving_id',
        'variant_id',
      });
      final foodId = entry.requiredString('food_id', maxLength: 80);
      final quantity = entry.requiredNumber(
        'quantity',
        min: 0.0001,
        max: maxQuantity,
      );
      final unit = entry.requiredString('unit', maxLength: 40);
      final servingId = entry.optionalString('serving_id', maxLength: 80);
      final variantId = entry.optionalString('variant_id', maxLength: 80);
      final details = await nutrition.getFoodWithDetailsIn(db, foodId);
      if (details == null || details.variants.isEmpty) {
        throw AiProposalException(
          'not_found',
          details == null
              ? 'Food "$foodId" is not in the food library.'
              : 'Food "${details.food.name}" has no nutrition variant.',
          param: '${entry.path}.food_id',
          received: foodId,
          hint:
              'Use a food id returned by search_food_library. If the food is not there, tell the user or offer propose_manual_food_creation.',
        );
      }
      final variant = _pickVariant(entry, details.variants, variantId);
      final servings = details.servings[variant.id] ?? const <FoodServing>[];
      final serving = _pickServing(entry, servings, servingId, unit);
      final conversion = NutritionConversion(
        quantity: quantity,
        unit: unit,
        referenceAmount: variant.referenceAmount,
        referenceUnit: variant.referenceUnit,
        serving: serving,
      );
      final NutritionValues consumed;
      try {
        consumed = conversion.apply(variant.values);
      } on NutritionConversionException catch (error) {
        throw _conversionError(
          error,
          entry: entry,
          foodName: details.food.name,
          variant: variant,
          servings: servings,
        );
      }
      final missing = consumed.hasMissingFields;
      incomplete = incomplete || missing;
      totals.add(consumed);
      if ((consumed.calories ?? 0) > 3000) {
        warnings.add({
          'code': 'large_portion',
          'name': details.food.name,
          'calories': consumed.calories!.round(),
        });
      }
      foods.add({
        'food_id': foodId,
        'variant_id': variant.id,
        'serving_id': serving?.id,
        'quantity': quantity,
        'unit': unit,
      });
      items.add({
        'kind': 'food',
        'food_id': foodId,
        'name': details.food.name,
        'brand': details.food.brand,
        'quantity': quantity,
        'unit': unit,
        'serving': serving == null
            ? null
            : {'label': serving.label, 'id': serving.id},
        'estimated': variant.isEstimated,
        'incomplete': missing,
        ..._values(consumed),
      });
    }

    final savedIds = <String>[];
    for (final entry in savedArgs) {
      entry.allowOnly({'saved_meal_id'});
      final id = entry.requiredString('saved_meal_id', maxLength: 80);
      final meal = await nutrition.getSavedMealIn(db, id);
      if (meal == null) {
        throw AiProposalException(
          'not_found',
          'Saved meal "$id" does not exist.',
          param: '${entry.path}.saved_meal_id',
          received: id,
          hint: 'Use a saved meal id returned by list_saved_meals.',
        );
      }
      if (meal.items.isEmpty) {
        throw AiProposalException(
          'invalid_args',
          'The saved meal "${meal.meal.name}" has no ingredients.',
          param: '${entry.path}.saved_meal_id',
          hint: 'Pick another saved meal or log foods one by one.',
        );
      }
      final unavailable = meal.items.where((i) => i.foodId == null).length;
      if (unavailable > 0) {
        warnings.add({
          'code': 'saved_meal_items_unavailable',
          'name': meal.meal.name,
          'count': unavailable,
        });
      }
      final consumed = meal.totals;
      if (consumed == null || consumed.hasMissingFields) incomplete = true;
      if (consumed != null) totals.add(consumed);
      savedIds.add(id);
      items.add({
        'kind': 'saved_meal',
        'saved_meal_id': id,
        'name': meal.meal.name,
        'ingredients': [for (final item in meal.items) item.foodNameSnapshot],
        'portions': meal.meal.portions,
        'incomplete': consumed == null || consumed.hasMissingFields,
        ..._values(consumed ?? NutritionValues.empty),
      });
    }

    // What is already in the meal and the day, so the user sees the effect.
    final existing = await db.rawQuery(
      '''
      SELECT mli.food_id, mli.food_name_snapshot AS name
      FROM meal_log_items mli JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date = ? AND ml.meal_type = ?
      ''',
      [date, mealKey],
    );
    final alreadyLogged = {
      for (final row in existing)
        if (row['food_id'] != null) row['food_id'] as String: row['name'],
    };
    for (final food in foods) {
      final name = alreadyLogged[food['food_id']];
      if (name != null && !warnings.any((w) => w['name'] == name)) {
        warnings.add({'code': 'already_in_meal', 'name': name});
      }
    }
    final summary = await nutrition.getDailySummary(date);
    final goalKcal = (await nutrition.getActiveGoalIn(db))?.calories;
    final dayBefore = summary.consumed.calories;

    final fingerprint = await _fingerprint(db, foods, savedIds);
    return AiProposalDraft(
      payload: {
        'date': date,
        'meal_type': mealKey,
        'meal_name': mealType.name,
        'foods': foods,
        'saved_meals': savedIds,
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'date': date,
        'meal_type': mealKey,
        'meal_name': mealType.name,
        'items': items,
        'totals': {...totals.toMap(), 'incomplete': incomplete},
        'day': {
          'before_kcal': dayBefore?.round(),
          if (dayBefore != null && totals.calories != null)
            'after_kcal': (dayBefore + totals.calories!).round(),
          'goal_kcal': goalKcal?.round(),
        },
        'warnings': warnings,
      },
      base: {'foods': foods.length, 'saved_meals': savedIds.length},
      baseHash: fingerprint,
      summary: {
        'date': date,
        'meal_type': mealKey,
        'items': [for (final i in items) i['name']],
        'calories': totals.calories?.round(),
        'protein_g': totals.proteinG?.round(),
        'carbs_g': totals.carbsG?.round(),
        'fat_g': totals.fatG?.round(),
        if (incomplete) 'incomplete': true,
      },
    );
  }

  FoodVariant _pickVariant(
    AiProposalArgs entry,
    List<FoodVariant> variants,
    String? variantId,
  ) {
    if (variantId == null) return variants.first;
    final match = variants.where((v) => v.id == variantId).firstOrNull;
    if (match != null) return match;
    throw AiProposalException(
      'invalid_args',
      'variant_id does not belong to this food.',
      param: '${entry.path}.variant_id',
      received: variantId,
      hint:
          'Use a variant id from search_food_library (food_id), or omit it for the main variant.',
    );
  }

  FoodServing? _pickServing(
    AiProposalArgs entry,
    List<FoodServing> servings,
    String? servingId,
    String unit,
  ) {
    final normalized = NutritionConversion.normalizeUnit(unit);
    final wantsServing = normalized == 'serving' || normalized == 'unit';
    // A serving_id next to a g/ml quantity is not used (often a placeholder).
    if (servingId != null && wantsServing) {
      final match = servings.where((s) => s.id == servingId).firstOrNull;
      if (match != null) return match;
      throw AiProposalException(
        'invalid_args',
        'serving_id does not belong to this food variant.',
        param: '${entry.path}.serving_id',
        received: servingId,
        hint: servings.isEmpty
            ? 'This food has no servings: use g or ml.'
            : 'Use one of: ${_servingList(servings)}.',
      );
    }
    if (!wantsServing) return null;
    if (servings.length == 1) return servings.first;
    throw AiProposalException(
      'invalid_args',
      servings.isEmpty
          ? 'This food has no servings to count in.'
          : 'Several servings exist: say which one.',
      param: '${entry.path}.serving_id',
      hint: servings.isEmpty
          ? 'Use g or ml with the amount instead.'
          : 'Send serving_id, one of: ${_servingList(servings)}.',
    );
  }

  String _servingList(List<FoodServing> servings) =>
      servings.map((s) => '${s.id} (${s.label})').join(', ');

  AiProposalException _conversionError(
    NutritionConversionException error, {
    required AiProposalArgs entry,
    required String foodName,
    required FoodVariant variant,
    required List<FoodServing> servings,
  }) {
    final reference = '${variant.referenceAmount} ${variant.referenceUnit}';
    final hint = switch (error.code) {
      'unsupported_unit_combination' =>
        '"$foodName" is measured per $reference: use ${variant.referenceUnit} or a serving with serving_id.',
      'serving_equivalence_missing' ||
      'grams_equivalence_missing' ||
      'ml_equivalence_missing' =>
        'That serving cannot be converted to ${variant.referenceUnit}: use g or ml with the amount.',
      'negative_nutrient' || 'invalid_scaled_value' =>
        'The food has invalid nutrition values; ask the user to fix it in the library.',
      _ => 'Check quantity and unit for "$foodName".',
    };
    return AiProposalException(
      'invalid_args',
      'Cannot convert the quantity for "$foodName" (${error.code}).',
      param: '${entry.path}.unit',
      hint: hint,
    );
  }

  Map<String, dynamic> _values(NutritionValues v) => {
    'calories': v.calories,
    'protein_g': v.proteinG,
    'carbs_g': v.carbsG,
    'fat_g': v.fatG,
  };

  /// Hash of everything the preview numbers came from: each food's variant
  /// values, reference and serving equivalents, and each saved meal's items.
  Future<String> _fingerprint(
    DatabaseExecutor executor,
    List<Map<String, dynamic>> foods,
    List<String> savedMeals,
  ) async {
    final nutrition = _db.nutritionRepo;
    final parts = <Object?>[];
    for (final food in foods) {
      final details = await nutrition.getFoodWithDetailsIn(
        executor,
        food['food_id'] as String,
      );
      final variant = details?.variants
          .where((v) => v.id == food['variant_id'])
          .firstOrNull;
      final serving = variant == null
          ? null
          : details!.servings[variant.id]
                ?.where((s) => s.id == food['serving_id'])
                .firstOrNull;
      parts.add([food, variant?.toMap(), serving?.toMap()]);
    }
    for (final id in savedMeals) {
      final meal = await nutrition.getSavedMealIn(executor, id);
      parts.add([
        id,
        meal?.meal.portions,
        [
          for (final item in meal?.items ?? const <SavedMealItem>[])
            [item.foodId, item.foodVariantId, item.quantity, item.unit],
        ],
        meal?.totals?.toMap(),
      ]);
    }
    return aiRevision(parts);
  }

  @override
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async {
    final payload = proposal.payload;
    final nutrition = _db.nutritionRepo;
    if (await nutrition.getMealTypeByKeyIn(
          txn,
          payload['meal_type'] as String? ?? '',
        ) ==
        null) {
      return 'stale_target_missing';
    }
    final foods = [
      for (final f in (payload['foods'] as List? ?? const []))
        (f as Map).cast<String, dynamic>(),
    ];
    final saved = [
      for (final id in (payload['saved_meals'] as List? ?? const []))
        id as String,
    ];
    for (final food in foods) {
      if (await nutrition.getFoodWithDetailsIn(
            txn,
            food['food_id'] as String,
          ) ==
          null) {
        return 'food_missing';
      }
    }
    for (final id in saved) {
      if (await nutrition.getSavedMealIn(txn, id) == null) {
        return 'saved_meal_missing';
      }
    }
    final hash = await _fingerprint(txn, foods, saved);
    return hash == proposal.baseHash ? null : 'stale_revision';
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final payload = proposal.payload;
    final date = payload['date'] as String;
    final mealType = payload['meal_type'] as String;
    final mealName = payload['meal_name'] as String?;
    final nutrition = _db.nutritionRepo;

    final entries = <MealLogEntryDraft>[];
    for (final raw in (payload['foods'] as List? ?? const [])) {
      final food = (raw as Map).cast<String, dynamic>();
      final details = await nutrition.getFoodWithDetailsIn(
        txn,
        food['food_id'] as String,
      );
      if (details == null) {
        throw const AiProposalException.stale(
          'food_missing',
          'A food of the proposal no longer exists.',
        );
      }
      final variant = details.variants.firstWhere(
        (v) => v.id == food['variant_id'],
        orElse: () => details.variants.first,
      );
      final servings = details.servings[variant.id] ?? const <FoodServing>[];
      final serving = servings
          .where((s) => s.id == food['serving_id'])
          .firstOrNull;
      entries.add((
        food: details.food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: (food['quantity'] as num).toDouble(),
          unit: food['unit'] as String,
          referenceAmount: variant.referenceAmount,
          referenceUnit: variant.referenceUnit,
          serving: serving,
        ),
        servings: servings,
      ));
    }
    var added = 0;
    if (entries.isNotEmpty) {
      final items = await nutrition.addMealLogItemsIn(
        txn,
        date: date,
        mealType: mealType,
        mealName: mealName,
        entries: entries,
        itemIdFor: (i) => aiDerivedId(proposal.id, 'food$i'),
      );
      added += items.length;
    }
    final saved = (payload['saved_meals'] as List? ?? const []).cast<String>();
    var skipped = 0;
    for (var k = 0; k < saved.length; k++) {
      final result = await nutrition.addSavedMealToDateIn(
        txn,
        date: date,
        mealType: mealType,
        mealName: mealName,
        savedMealId: saved[k],
        itemIdFor: (i) => aiDerivedId(proposal.id, 'saved$k/item$i'),
      );
      added += result.added;
      skipped += result.skipped;
    }
    return {
      'date': date,
      'meal_type': mealType,
      'items_added': added,
      if (skipped > 0) 'items_skipped': skipped,
    };
  }
}

class _Totals {
  double? calories;
  double? proteinG;
  double? carbsG;
  double? fatG;

  void add(NutritionValues v) {
    calories = _sum(calories, v.calories);
    proteinG = _sum(proteinG, v.proteinG);
    carbsG = _sum(carbsG, v.carbsG);
    fatG = _sum(fatG, v.fatG);
  }

  static double? _sum(double? a, double? b) => b == null ? a : (a ?? 0) + b;

  Map<String, dynamic> toMap() => {
    'calories': calories,
    'protein_g': proteinG,
    'carbs_g': carbsG,
    'fat_g': fatG,
  };
}
