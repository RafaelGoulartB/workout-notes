import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

import 'food_quantity_sheet.dart';
import 'food_search_screen.dart';

/// One ingredient being edited, before it is persisted.
class _Ingredient {
  final String id;
  String? foodId;
  String? foodVariantId;
  String name;
  String? brand;
  double quantity;
  String unit;

  _Ingredient({
    required this.id,
    this.foodId,
    this.foodVariantId,
    required this.name,
    this.brand,
    required this.quantity,
    required this.unit,
  });

  factory _Ingredient.fromDraft(SavedMealItemDraft draft) => _Ingredient(
    id: '${draft.foodId ?? ''}-${draft.quantity}-${draft.unit}-${DateTime.now().microsecondsSinceEpoch}',
    foodId: draft.foodId,
    foodVariantId: draft.foodVariantId,
    name: draft.foodNameSnapshot,
    brand: draft.brandSnapshot,
    quantity: draft.quantity,
    unit: draft.unit,
  );
}

/// Screen to create or edit a saved meal (template). Ingredients are
/// picked through the regular food search + quantity sheet flows.
class SavedMealEditorScreen extends StatefulWidget {
  final NutritionRepository repository;
  final String? savedMealId;
  final String? initialName;
  final String? initialMealType;
  final double initialPortions;
  final List<SavedMealItemDraft> initialItems;

  const SavedMealEditorScreen({
    super.key,
    required this.repository,
    this.savedMealId,
    this.initialName,
    this.initialMealType,
    this.initialPortions = 1,
    this.initialItems = const [],
  });

  @override
  State<SavedMealEditorScreen> createState() => _SavedMealEditorScreenState();
}

class _SavedMealEditorScreenState extends State<SavedMealEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _portionsController = TextEditingController(text: '1');
  String? _mealType;
  late List<_Ingredient> _ingredients;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    _mealType = widget.initialMealType;
    if (widget.initialPortions != 1) {
      _portionsController.text = widget.initialPortions
          .toStringAsFixed(
            widget.initialPortions == widget.initialPortions.roundToDouble()
                ? 0
                : 1,
          )
          .replaceAll(',', '.');
    }
    _ingredients = widget.initialItems.map(_Ingredient.fromDraft).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portionsController.dispose();
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final selection = await Navigator.of(context).push<NutritionSelection>(
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          gateway: OpenFoodFactsGateway(),
          repository: widget.repository,
        ),
      ),
    );
    if (selection == null) return;
    if (!mounted) return;
    final quantity = await showFoodQuantitySheet(
      context: context,
      food: selection.food,
      primaryVariant: selection.primaryVariant,
      servings: selection.servings,
    );
    if (quantity == null) return;
    if (!mounted) return;
    setState(() {
      _ingredients.add(
        _Ingredient(
          id: '${selection.food.id}-${DateTime.now().microsecondsSinceEpoch}',
          foodId: quantity.food.id,
          foodVariantId: quantity.variant.id,
          name: quantity.food.name,
          brand: quantity.food.brand,
          quantity: quantity.conversion.quantity,
          unit: quantity.conversion.unit,
        ),
      );
    });
  }

  Future<void> _editIngredient(_Ingredient ingredient) async {
    if (ingredient.foodId == null) return;
    final details = await widget.repository
        .getFoodWithDetails(ingredient.foodId!);
    if (details == null) return;
    if (!mounted) return;
    final variant = details.variants.isEmpty
        ? null
        : details.variants.firstWhere(
            (v) => v.id == ingredient.foodVariantId,
            orElse: () => details.variants.first,
          );
    if (variant == null) return;
    final quantity = await showFoodQuantitySheet(
      context: context,
      food: details.food,
      primaryVariant: variant,
      servings: details.servings[variant.id] ?? const <FoodServing>[],
      existing: _itemForDraft(ingredient, variant, details.servings[variant.id] ?? const []),
    );
    if (quantity == null) return;
    if (!mounted) return;
    setState(() {
      ingredient.foodVariantId = quantity.variant.id;
      ingredient.quantity = quantity.conversion.quantity;
      ingredient.unit = quantity.conversion.unit;
    });
  }

  /// Builds a minimal [MealLogItem] from an ingredient so the quantity
  /// sheet can pre-fill the current amount and serving.
  MealLogItem _itemForDraft(
    _Ingredient ingredient,
    FoodVariant variant,
    List<FoodServing> servings,
  ) {
    final serving = servings.where(
      (s) => s.label == ingredient.unit || s.unit == ingredient.unit,
    );
    final matched = serving.isEmpty ? null : serving.first;
    final snapshot = NutritionSnapshot(
      version: NutritionSnapshot.currentVersion,
      source: FoodSource.manual,
      externalId: ingredient.foodId ?? '',
      foodName: ingredient.name,
      foodBrand: ingredient.brand,
      variantLabel: variant.label,
      referenceAmount: variant.referenceAmount,
      referenceUnit: variant.referenceUnit,
      quantity: ingredient.quantity,
      unit: ingredient.unit,
      gramsEquivalent: matched?.gramsEquivalent,
      mlEquivalent: matched?.mlEquivalent,
      consumed: NutritionValues.empty,
      isEstimated: variant.isEstimated,
      hasMissingValues: true,
    );
    return MealLogItem(
      id: ingredient.id,
      mealLogId: '',
      foodId: ingredient.foodId,
      foodVariantId: ingredient.foodVariantId,
      foodNameSnapshot: ingredient.name,
      brandSnapshot: ingredient.brand,
      quantity: ingredient.quantity,
      unit: ingredient.unit,
      snapshotJson: snapshot.encode(),
      createdAt: DateTime.now(),
    );
  }

  void _removeIngredient(_Ingredient ingredient) {
    setState(() => _ingredients.remove(ingredient));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final loc = AppLocalizations.of(context)!;
    setState(() => _isSaving = true);
    try {
      final portions = double.tryParse(
            _portionsController.text.trim().replaceAll(',', '.'),
          ) ??
          1;
      await widget.repository.saveSavedMeal(
        id: widget.savedMealId,
        name: _nameController.text,
        mealType: _mealType,
        portions: portions,
        items: [
          for (final ingredient in _ingredients)
            SavedMealItemDraft(
              foodId: ingredient.foodId,
              foodVariantId: ingredient.foodVariantId,
              foodNameSnapshot: ingredient.name,
              brandSnapshot: ingredient.brand,
              quantity: ingredient.quantity,
              unit: ingredient.unit,
            ),
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionSavedMealSaved)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static String _mealLabel(AppLocalizations loc, String? type) {
    if (type == null) return loc.nutritionSavedMealNoType;
    switch (type) {
      case MealType.breakfast:
        return loc.nutritionMealBreakfast;
      case MealType.lunch:
        return loc.nutritionMealLunch;
      case MealType.dinner:
        return loc.nutritionMealDinner;
      case MealType.snacks:
        return loc.nutritionMealSnacks;
    }
    return type;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.savedMealId == null
              ? loc.nutritionSavedMealNew
              : loc.nutritionSavedMealEdit,
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc.nutritionSave),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: loc.nutritionSavedMealName,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withAlpha(60),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                  ? loc.nutritionFieldRequired
                  : null,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _mealType,
                    decoration: InputDecoration(
                      labelText: loc.nutritionSavedMealMealType,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(60),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(loc.nutritionSavedMealNoType),
                      ),
                      for (final type in MealType.displayOrder)
                        DropdownMenuItem(
                          value: type,
                          child: Text(_mealLabel(loc, type)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _mealType = value),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _portionsController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: loc.nutritionSavedMealPortions,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(60),
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      if (parsed == null || parsed <= 0) {
                        return loc.nutritionInvalidQuantity;
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    loc.nutritionSavedMealIngredients,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSaving ? null : _addIngredient,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(loc.nutritionAddItem),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_ingredients.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(50),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.restaurant_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.nutritionSavedMealEmptyIngredients,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _ingredients.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant
                              .withAlpha(60),
                        ),
                      ListTile(
                        title: Text(_ingredients[i].name),
                        subtitle: Text(
                          '${_format(_ingredients[i].quantity)} '
                          '${_ingredients[i].unit}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: loc.nutritionEditItem,
                              onPressed: _isSaving
                                  ? null
                                  : () => _editIngredient(_ingredients[i]),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: loc.nutritionDeleteItem,
                              onPressed: _isSaving
                                  ? null
                                  : () => _removeIngredient(_ingredients[i]),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(loc.nutritionSave),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}
