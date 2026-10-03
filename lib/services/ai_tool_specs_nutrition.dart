import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_nutrition_tool_service.dart';
import 'package:workout_notes/services/ai_tool_deps.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

const _nutritionDetails = [...AiNutritionToolService.details, 'day'];

/// Nutrition tools (ranged report, diary day, food library, saved meals).
/// `analyze_nutrition_body_trend` lives with the wellness specs.
List<AiToolSpec> nutritionToolSpecs(AiToolDeps d) => [
  AiToolSpec(
    name: 'get_nutrition',
    description:
        'Food intake. detail: summary (averages vs goal), daily (row per day), '
        'micros, foods (top calorie sources), day (meals and items of one day).',
    properties: {
      'days': AiParam.days(14, 1, 90),
      'end_date': AiParam.endDate('or the day for detail=day'),
      'detail': AiParam.enumOf(_nutritionDetails, 'Default summary.'),
    },
    domain: AiToolDomain.nutrition,
    handler: (a) async {
      final detail = a.enumValue('detail', _nutritionDetails, fallback: 'summary')!;
      final endDate = a.date('end_date', alt: 'date');
      if (detail == 'day') {
        return aiToolOk(await d.nutrition.diaryDay(date: endDate));
      }
      return aiToolOk(
        await d.nutrition.nutrition(
          days: a.integerOrNull('days', min: 1, max: 90),
          endDate: endDate,
          detail: detail,
        ),
      );
    },
  ),
  AiToolSpec(
    name: 'search_food_library',
    description:
        'Search the food library by name or brand, with macros. food_id: full '
        'detail of one food.',
    properties: {
      'query': AiParam.string('Name or brand.'),
      'favorites_only': AiParam.boolean('Only favorites.'),
      'limit': AiParam.limit(10, 30),
      'food_id': AiParam.string('Detail of this food.'),
    },
    domain: AiToolDomain.nutrition,
    handler: (a) async => aiToolOk(
      await d.nutrition.searchFoods(
        query: a.string('query'),
        favoritesOnly: a.flag('favorites_only'),
        recentOnly: false,
        limit: a.integer('limit', fallback: 10, min: 1, max: 30),
        foodId: a.string('food_id'),
      ),
    ),
  ),
  AiToolSpec(
    name: 'list_saved_meals',
    description:
        'Saved meal templates with calories and macros; saved_meal_id: items '
        'and all nutrient totals.',
    properties: {
      'limit': AiParam.limit(15, 40),
      'saved_meal_id': AiParam.string('Detail of this meal.'),
    },
    domain: AiToolDomain.nutrition,
    handler: (a) async => aiToolOk(
      await d.nutrition.listSavedMeals(
        limit: a.integer('limit', fallback: 15, min: 1, max: 40),
        savedMealId: a.string('saved_meal_id'),
      ),
    ),
  ),
];
