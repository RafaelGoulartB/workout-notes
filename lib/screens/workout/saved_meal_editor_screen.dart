import 'dart:async';

import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

import 'food_quantity_sheet.dart';
import 'food_search_screen.dart';

/// Macro accent colors shared with `nutrition_home_screen.dart` so the
/// editor's summary and the home screen render the same color tokens.
const Color _carbMacroColor = Color(0xFF20A39E);
const Color _proteinMacroColor = Color(0xFFF29E38);
const Color _fatMacroColor = Color(0xFF8E44AD);

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
  final _nameController = TextEditingController();
  final _portionsController = TextEditingController(text: '1');
  late List<_Ingredient> _ingredients;
  bool _isSaving = false;

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

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
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
    _portionsController.addListener(_onPortionsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeTotals());
  }

  @override
  void dispose() {
    _portionsDebounce?.cancel();
    _portionsController.removeListener(_onPortionsChanged);
    _nameController.dispose();
    _portionsController.dispose();
    super.dispose();
  }

  void _onPortionsChanged() {
    _portionsDebounce?.cancel();
    _portionsDebounce = Timer(
      const Duration(milliseconds: 250),
      _recomputeTotals,
    );
  }

  Future<void> _recomputeTotals() async {
    final portions = _currentPortions();
    final drafts = _ingredients
        .map(
          (i) => SavedMealItemDraft(
            foodId: i.foodId,
            foodVariantId: i.foodVariantId,
            foodNameSnapshot: i.name,
            brandSnapshot: i.brand,
            quantity: i.quantity,
            unit: i.unit,
          ),
        )
        .toList();
    if (!mounted) return;
    setState(() => _isComputingTotals = true);
    try {
      final totals = await widget.repository.previewSavedMealTotals(
        items: drafts,
        portions: portions,
      );
      if (!mounted) return;
      setState(() {
        _totals = totals;
        _isComputingTotals = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isComputingTotals = false);
    }
  }

  double _currentPortions() {
    final parsed = double.tryParse(
      _portionsController.text.trim().replaceAll(',', '.'),
    );
    if (parsed == null || parsed <= 0 || !parsed.isFinite) return 1;
    return parsed;
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
    _recomputeTotals();
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
    _recomputeTotals();
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
    _recomputeTotals();
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
            TextFormField(
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
            const SizedBox(height: 20),
            _NutritionTotalsCard(
              totals: _totals,
              portions: _currentPortions(),
              isComputing: _isComputingTotals,
              hasIngredients: _ingredients.isNotEmpty,
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

/// Card that summarises the live nutrition totals for the saved meal
/// being edited. Mirrors the visual language of the home screen
/// `_NutritionMacroStat` (same colors, same label hierarchy) so the two
/// screens feel like part of the same product.
class _NutritionTotalsCard extends StatelessWidget {
  final NutritionValues? totals;
  final double portions;
  final bool isComputing;
  final bool hasIngredients;

  const _NutritionTotalsCard({
    required this.totals,
    required this.portions,
    required this.isComputing,
    required this.hasIngredients,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final showTotals = totals != null;
    final showPerPortion = portions > 1;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_fire_department_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  loc.nutritionSavedMealTotalsTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isComputing) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (!showTotals)
              Text(
                hasIngredients
                    ? loc.nutritionSavedMealTotalsPartial
                    : loc.nutritionSavedMealTotalsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              _CaloriesRow(calories: totals!.calories ?? 0),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MacroColumn(
                      label: loc.nutritionProgressProtein,
                      grams: totals!.proteinG ?? 0,
                      color: _proteinMacroColor,
                    ),
                  ),
                  _MacroDivider(theme: theme),
                  Expanded(
                    child: _MacroColumn(
                      label: loc.nutritionProgressCarbs,
                      grams: totals!.carbsG ?? 0,
                      color: _carbMacroColor,
                    ),
                  ),
                  _MacroDivider(theme: theme),
                  Expanded(
                    child: _MacroColumn(
                      label: loc.nutritionProgressFat,
                      grams: totals!.fatG ?? 0,
                      color: _fatMacroColor,
                    ),
                  ),
                ],
              ),
              if (showPerPortion) ...[
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                ),
                const SizedBox(height: 10),
                _PerPortionRow(
                  totals: totals!,
                  portions: portions,
                  label: loc.nutritionSavedMealTotalsPerPortion,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CaloriesRow extends StatelessWidget {
  final double calories;

  const _CaloriesRow({required this.calories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _formatKcal(calories),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'kcal',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static String _formatKcal(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _MacroColumn extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;

  const _MacroColumn({
    required this.label,
    required this.grams,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _formatGrams(grams),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'g',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: grams > 0 ? 1.0 : 0.0,
            minHeight: 3,
            backgroundColor: color.withAlpha(35),
            color: color,
          ),
        ),
      ],
    );
  }

  static String _formatGrams(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _MacroDivider extends StatelessWidget {
  final ThemeData theme;
  const _MacroDivider({required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: theme.colorScheme.outlineVariant.withAlpha(70),
    );
  }
}

class _PerPortionRow extends StatelessWidget {
  final NutritionValues totals;
  final double portions;
  final String label;

  const _PerPortionRow({
    required this.totals,
    required this.portions,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    final kcal = (totals.calories ?? 0) / portions;
    parts.add('${_formatGrams(kcal)} kcal');
    final protein = (totals.proteinG ?? 0) / portions;
    final carbs = (totals.carbsG ?? 0) / portions;
    final fat = (totals.fatG ?? 0) / portions;
    if (protein > 0) parts.add('P ${_formatGrams(protein)} g');
    if (carbs > 0) parts.add('C ${_formatGrams(carbs)} g');
    if (fat > 0) parts.add('G ${_formatGrams(fat)} g');
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: parts.join(' · ')),
        ],
      ),
    );
  }

  static String _formatGrams(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}
