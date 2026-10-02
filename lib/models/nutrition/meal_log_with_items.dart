import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

/// One food ready to be logged: the food, the variant it is measured in, the
/// exact quantity conversion and the servings of that variant.
typedef MealLogEntryDraft = ({
  Food food,
  FoodVariant variant,
  NutritionConversion conversion,
  List<FoodServing> servings,
});

/// A meal log with its items, used by the day screen.
class MealLogWithItems {
  final MealLog log;
  final List<MealLogItem> items;

  const MealLogWithItems({required this.log, required this.items});
}
