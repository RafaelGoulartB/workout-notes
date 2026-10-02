import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';

/// Lightweight food + variant bundle returned by local search.
class FoodSearchResultLite {
  final Food food;
  final FoodVariant? primaryVariant;
  final List<FoodVariant> variants;
  final Map<String, List<FoodServing>> servings;

  const FoodSearchResultLite({
    required this.food,
    this.primaryVariant,
    this.variants = const [],
    this.servings = const {},
  });
}

/// A food with all its variants and servings loaded.
class FoodWithDetails {
  final Food food;
  final List<FoodVariant> variants;
  final Map<String, List<FoodServing>> servings;

  const FoodWithDetails({
    required this.food,
    required this.variants,
    required this.servings,
  });
}
