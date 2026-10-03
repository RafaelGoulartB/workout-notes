import 'package:workout_notes/models/nutrition/meal_log_item.dart';

/// Input for a saved meal ingredient. Built by the UI from either a
/// meal log item or a food + quantity selection.
class SavedMealItemDraft {
  final String? foodId;
  final String? foodVariantId;
  final String foodNameSnapshot;
  final String? brandSnapshot;
  final double quantity;
  final String unit;
  final String? servingLabel;
  final double? servingGramsEquivalent;
  final double? servingMlEquivalent;

  const SavedMealItemDraft({
    this.foodId,
    this.foodVariantId,
    required this.foodNameSnapshot,
    this.brandSnapshot,
    required this.quantity,
    required this.unit,
    this.servingLabel,
    this.servingGramsEquivalent,
    this.servingMlEquivalent,
  });

  factory SavedMealItemDraft.fromMealLogItem(MealLogItem item) {
    return SavedMealItemDraft(
      foodId: item.foodId,
      foodVariantId: item.foodVariantId,
      foodNameSnapshot: item.foodNameSnapshot,
      brandSnapshot: item.brandSnapshot,
      quantity: item.quantity,
      unit: item.unit,
      servingGramsEquivalent: item.snapshot.gramsEquivalent,
      servingMlEquivalent: item.snapshot.mlEquivalent,
    );
  }
}
