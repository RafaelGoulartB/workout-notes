import 'food.dart';
import 'food_serving.dart';
import 'food_variant.dart';

/// A single result row used in the food search screen.
///
/// [FoodSearchResult] decouples the search UI from the persistence
/// shape: a result carries at most one default variant (and optional
/// servings), even if the food has more. The repository chooses the
/// variant with the most data when packing results.
class FoodSearchResult {
  final Food food;
  final FoodVariant? primaryVariant;
  final List<FoodServing> servings;

  /// True when this row was produced by a remote gateway call.
  final bool isRemote;

  const FoodSearchResult({
    required this.food,
    this.primaryVariant,
    this.servings = const [],
    this.isRemote = false,
  });

  /// (source, externalId) pair used to deduplicate search results.
  String get dedupKey => food.dedupKey;
}
