import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/workout/food_quantity_sheet.dart';
import 'package:workout_notes/screens/workout/food_search_screen.dart';
import 'package:workout_notes/screens/workout/saved_meal_editor_controller.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';
import 'package:workout_notes/widgets/nutrition/saved_meal/saved_meal_form_widgets.dart';
import 'package:workout_notes/widgets/nutrition/saved_meal/saved_meal_totals_card.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Screen to create or edit a saved meal (template). Ingredients are
/// picked through the regular food search + quantity sheet flows.
class SavedMealEditorScreen extends StatefulWidget {
  final NutritionRepository repository;
  final String? savedMealId;
  final String? initialName;
  final double initialPortions;
  final List<SavedMealItemDraft> initialItems;

  const SavedMealEditorScreen({
    super.key,
    required this.repository,
    this.savedMealId,
    this.initialName,
    this.initialPortions = 1,
    this.initialItems = const [],
  });

  @override
  State<SavedMealEditorScreen> createState() => _SavedMealEditorScreenState();
}

class _SavedMealEditorScreenState extends State<SavedMealEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final SavedMealEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SavedMealEditorController(
      repository: widget.repository,
      savedMealId: widget.savedMealId,
      initialName: widget.initialName,
      initialPortions: widget.initialPortions,
      initialItems: widget.initialItems,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.recomputeTotals(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final selection = await Navigator.of(context).push<NutritionSelection>(
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          gateway: OpenFoodFactsGateway.instance,
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
    _controller.addIngredient(
      SavedMealIngredient(
        id: '${selection.food.id}-${DateTime.now().microsecondsSinceEpoch}',
        foodId: quantity.food.id,
        foodVariantId: quantity.variant.id,
        name: quantity.food.name,
        brand: quantity.food.brand,
        quantity: quantity.conversion.quantity,
        unit: quantity.conversion.unit,
        servingLabel: quantity.conversion.serving?.label,
        servingGramsEquivalent: quantity.conversion.serving?.gramsEquivalent,
        servingMlEquivalent: quantity.conversion.serving?.mlEquivalent,
      ),
    );
  }

  Future<void> _editIngredient(SavedMealIngredient ingredient) async {
    if (ingredient.foodId == null) return;
    final details = await widget.repository.getFoodWithDetails(
      ingredient.foodId!,
    );
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
      existing: ingredient.toMealLogItem(
        variant,
        details.servings[variant.id] ?? const [],
      ),
    );
    if (quantity == null) return;
    if (!mounted) return;
    _controller.updateIngredient(ingredient, (ingredient) {
      ingredient.foodVariantId = quantity.variant.id;
      ingredient.quantity = quantity.conversion.quantity;
      ingredient.unit = quantity.conversion.unit;
      ingredient.servingLabel = quantity.conversion.serving?.label;
      ingredient.servingGramsEquivalent =
          quantity.conversion.serving?.gramsEquivalent;
      ingredient.servingMlEquivalent =
          quantity.conversion.serving?.mlEquivalent;
    });
  }

  Future<void> _confirmRemoveIngredient(SavedMealIngredient ingredient) async {
    final loc = AppLocalizations.of(context)!;
    final shouldRemove = await showConfirmDialog(
      context,
      title: loc.nutritionDeleteItem,
      message: loc.nutritionDeleteItemConfirm,
      confirmLabel: loc.nutritionDeleteItem,
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (shouldRemove == true && mounted) {
      _controller.removeIngredient(ingredient);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final loc = AppLocalizations.of(context)!;
    try {
      await _controller.save();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final c = _controller;
    final ingredients = c.ingredients;
    final isSaving = c.isSaving;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.savedMealId == null
              ? loc.nutritionSavedMealNew
              : loc.nutritionSavedMealEdit,
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            SavedMealDetailsCard(
              nameController: c.nameController,
              portionsController: c.portionsController,
              onDecreasePortions: isSaving || c.currentPortions <= 1
                  ? null
                  : () => c.changePortions(-1),
              onIncreasePortions: isSaving || c.currentPortions >= 999
                  ? null
                  : () => c.changePortions(1),
            ),
            const SizedBox(height: 16),
            SavedMealTotalsCard(
              totals: c.totals,
              portions: c.currentPortions,
              isComputing: c.isComputingTotals,
              hasIngredients: ingredients.isNotEmpty,
              ingredientCount: ingredients.length,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.nutritionSavedMealIngredients,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loc.nutritionSavedMealFoodsCount(ingredients.length),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ingredients.isNotEmpty)
                  TextButton.icon(
                    onPressed: isSaving ? null : _addIngredient,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(loc.nutritionAddItem),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (ingredients.isEmpty)
              SavedMealEmptyIngredientsCard(
                onAdd: isSaving ? null : _addIngredient,
              )
            else
              for (var i = 0; i < ingredients.length; i++) ...[
                SavedMealIngredientCard(
                  ingredient: ingredients[i],
                  enabled: !isSaving,
                  onEdit: () => _editIngredient(ingredients[i]),
                  onRemove: () => _confirmRemoveIngredient(ingredients[i]),
                ),
                if (i < ingredients.length - 1) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: isSaving ? null : _save,
            icon: isSaving
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
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
