import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

/// Payload returned by the food quantity modal: a persisted food +
/// variant + the conversion the user picked. Used by the daily screen
/// to log the item.
class NutritionQuantitySelection {
  final Food food;
  final FoodVariant variant;
  final NutritionConversion conversion;
  final List<FoodServing> availableServings;

  const NutritionQuantitySelection({
    required this.food,
    required this.variant,
    required this.conversion,
    required this.availableServings,
  });
}

/// Payload returned by the food search screen. Carries the chosen
/// food + the variants the home screen needs to render the quantity
/// sheet.
class NutritionSelection {
  final Food food;
  final FoodVariant? primaryVariant;
  final List<FoodServing> servings;

  const NutritionSelection({
    required this.food,
    this.primaryVariant,
    this.servings = const [],
  });
}
