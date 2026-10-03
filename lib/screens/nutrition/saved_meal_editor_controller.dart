import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/models/nutrition/saved_meal_item_draft.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';

/// One ingredient being edited, before it is persisted.
class SavedMealIngredient {
  final String id;
  String? foodId;
  String? foodVariantId;
  String name;
  String? brand;
  double quantity;
  String unit;
  String? servingLabel;
  double? servingGramsEquivalent;
  double? servingMlEquivalent;

  /// Calories of this ingredient for the whole meal, from the last totals
  /// preview.
  double? calories;

  SavedMealIngredient({
    required this.id,
    this.foodId,
    this.foodVariantId,
    required this.name,
    this.brand,
    required this.quantity,
    required this.unit,
    this.servingLabel,
    this.servingGramsEquivalent,
    this.servingMlEquivalent,
  });

  factory SavedMealIngredient.fromDraft(
    SavedMealItemDraft draft,
  ) => SavedMealIngredient(
    id: '${draft.foodId ?? ''}-${draft.quantity}-${draft.unit}-${DateTime.now().microsecondsSinceEpoch}',
    foodId: draft.foodId,
    foodVariantId: draft.foodVariantId,
    name: draft.foodNameSnapshot,
    brand: draft.brandSnapshot,
    quantity: draft.quantity,
    unit: draft.unit,
    servingLabel: draft.servingLabel,
    servingGramsEquivalent: draft.servingGramsEquivalent,
    servingMlEquivalent: draft.servingMlEquivalent,
  );

  SavedMealItemDraft toDraft() => SavedMealItemDraft(
    foodId: foodId,
    foodVariantId: foodVariantId,
    foodNameSnapshot: name,
    brandSnapshot: brand,
    quantity: quantity,
    unit: unit,
    servingLabel: servingLabel,
    servingGramsEquivalent: servingGramsEquivalent,
    servingMlEquivalent: servingMlEquivalent,
  );

  /// Builds a minimal [MealLogItem] so the quantity sheet can pre-fill the
  /// current amount and serving.
  MealLogItem toMealLogItem(FoodVariant variant, List<FoodServing> servings) {
    final byLabel = servings.where((s) => s.label == servingLabel);
    final matched = byLabel.isNotEmpty ? byLabel.first : null;
    final snapshot = NutritionSnapshot(
      version: NutritionSnapshot.currentVersion,
      source: FoodSource.manual,
      externalId: foodId ?? '',
      foodName: name,
      foodBrand: brand,
      variantLabel: variant.label,
      referenceAmount: variant.referenceAmount,
      referenceUnit: variant.referenceUnit,
      quantity: quantity,
      unit: unit,
      gramsEquivalent: matched?.gramsEquivalent ?? servingGramsEquivalent,
      mlEquivalent: matched?.mlEquivalent ?? servingMlEquivalent,
      consumed: NutritionValues.empty,
      isEstimated: variant.isEstimated,
      hasMissingValues: true,
    );
    return MealLogItem(
      id: id,
      mealLogId: '',
      foodId: foodId,
      foodVariantId: foodVariantId,
      foodNameSnapshot: name,
      brandSnapshot: brand,
      quantity: quantity,
      unit: unit,
      snapshotJson: snapshot.encode(),
      createdAt: DateTime.now(),
    );
  }
}

/// State of the saved-meal editor: the name, the portions, the ingredient
/// list and the live nutrition totals computed from the food cache. Saving is
/// exposed as [save]; navigation, dialogs and messages stay in the screen.
class SavedMealEditorController extends ChangeNotifier {
  SavedMealEditorController({
    required this.repository,
    this.savedMealId,
    String? initialName,
    double initialPortions = 1,
    List<SavedMealItemDraft> initialItems = const [],
  }) : ingredients = initialItems.map(SavedMealIngredient.fromDraft).toList() {
    nameController.text = initialName ?? '';
    if (initialPortions != 1) {
      portionsController.text = AppNumberFormat.decimal(
        initialPortions,
        initialPortions == initialPortions.roundToDouble() ? 0 : 1,
      );
    }
    portionsController.addListener(_onPortionsChanged);
  }

  final NutritionRepository repository;
  final String? savedMealId;

  final nameController = TextEditingController();
  final portionsController = TextEditingController(text: '1');
  final List<SavedMealIngredient> ingredients;

  bool _isSaving = false;
  bool _disposed = false;

  /// Live-computed nutrition totals for the current ingredients. `null`
  /// means there are no ingredients, or none of them could be resolved
  /// against the food cache.
  NutritionValues? _totals;

  /// `true` while a totals recomputation is running. Used to render the
  /// card placeholder without flickering between recomputes.
  bool _isComputingTotals = false;

  /// Debounce timer for the portions text field so the totals card does
  /// not refetch on every keystroke.
  Timer? _portionsDebounce;

  bool get isSaving => _isSaving;
  NutritionValues? get totals => _totals;
  bool get isComputingTotals => _isComputingTotals;

  void _onPortionsChanged() {
    _portionsDebounce?.cancel();
    _portionsDebounce = Timer(
      const Duration(milliseconds: 250),
      recomputeTotals,
    );
  }

  double get currentPortions {
    final parsed = double.tryParse(
      portionsController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0 || !parsed.isFinite) return 1;
    return parsed;
  }

  void changePortions(double delta) {
    final next = (currentPortions + delta).clamp(1, 999).toDouble();
    portionsController.text = formatQuantity(next);
    portionsController.selection = TextSelection.collapsed(
      offset: portionsController.text.length,
    );
  }

  Future<void> recomputeTotals() async {
    final portions = currentPortions;
    final ingredientIds = ingredients
        .map((ingredient) => ingredient.id)
        .toList(growable: false);
    final drafts = ingredients.map((i) => i.toDraft()).toList();
    if (_disposed) return;
    _isComputingTotals = true;
    notifyListeners();
    try {
      final preview = await repository.previewSavedMealNutrition(
        items: drafts,
        portions: portions,
      );
      if (_disposed) return;
      _totals = preview.totals;
      for (var i = 0; i < drafts.length; i++) {
        final currentIndex = ingredients.indexWhere(
          (ingredient) => ingredient.id == ingredientIds[i],
        );
        if (currentIndex >= 0) {
          ingredients[currentIndex].calories = preview.byItem[i]?.calories;
        }
      }
      _isComputingTotals = false;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _isComputingTotals = false;
      notifyListeners();
    }
  }

  void addIngredient(SavedMealIngredient ingredient) {
    ingredients.add(ingredient);
    notifyListeners();
    recomputeTotals();
  }

  /// Applies [change] to an ingredient the user edited, then refreshes totals.
  void updateIngredient(
    SavedMealIngredient ingredient,
    void Function(SavedMealIngredient ingredient) change,
  ) {
    change(ingredient);
    notifyListeners();
    recomputeTotals();
  }

  void removeIngredient(SavedMealIngredient ingredient) {
    ingredients.remove(ingredient);
    notifyListeners();
    recomputeTotals();
  }

  /// Persists the meal. Busy while it runs; rethrows repository failures.
  Future<void> save() async {
    _isSaving = true;
    notifyListeners();
    try {
      final portions =
          double.tryParse(
            portionsController.text.trim().replaceAll(',', '.'),
          ) ??
          1;
      await repository.saveSavedMeal(
        id: savedMealId,
        name: nameController.text,
        portions: portions,
        items: [for (final ingredient in ingredients) ingredient.toDraft()],
      );
    } finally {
      if (!_disposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  /// Quantities and portions: no decimals when whole, otherwise two.
  static String formatQuantity(double value) {
    if (value == value.roundToDouble()) {
      return AppNumberFormat.decimal(value, 0);
    }
    return AppNumberFormat.decimal(value, 2);
  }

  @override
  void dispose() {
    _disposed = true;
    _portionsDebounce?.cancel();
    portionsController.removeListener(_onPortionsChanged);
    nameController.dispose();
    portionsController.dispose();
    super.dispose();
  }
}
