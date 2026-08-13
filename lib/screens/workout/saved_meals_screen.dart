import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';

import 'saved_meal_editor_screen.dart';

/// Lists the user's saved meal templates and lets them log a template
/// into today with a single tap.
class SavedMealsScreen extends StatefulWidget {
  final NutritionRepository repository;

  const SavedMealsScreen({super.key, required this.repository});

  @override
  State<SavedMealsScreen> createState() => _SavedMealsScreenState();
}

class _SavedMealsScreenState extends State<SavedMealsScreen> {
  List<SavedMealWithItems> _meals = const [];
  List<MealTypeDefinition> _mealTypes = const [];
  bool _isLoading = true;
  bool _isLogging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.repository.getSavedMeals(),
        widget.repository.getMealTypes(),
      ]);
      if (!mounted) return;
      setState(() {
        _meals = results[0] as List<SavedMealWithItems>;
        _mealTypes = results[1] as List<MealTypeDefinition>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createMeal() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SavedMealEditorScreen(repository: widget.repository),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _editMeal(SavedMealWithItems meal) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SavedMealEditorScreen(
          repository: widget.repository,
          savedMealId: meal.meal.id,
          initialName: meal.meal.name,
          initialPortions: meal.meal.portions,
          initialItems: [
            for (final item in meal.items)
              SavedMealItemDraft(
                foodId: item.foodId,
                foodVariantId: item.foodVariantId,
                foodNameSnapshot: item.foodNameSnapshot,
                brandSnapshot: item.brandSnapshot,
                quantity: item.quantity,
                unit: item.unit,
                servingLabel: item.servingLabel,
                servingGramsEquivalent: item.servingGramsEquivalent,
                servingMlEquivalent: item.servingMlEquivalent,
              ),
          ],
        ),
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _deleteMeal(SavedMealWithItems meal) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.nutritionSavedMealDelete),
        content: Text(loc.nutritionSavedMealDeleteConfirm(meal.meal.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.nutritionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.deleteSavedMeal(meal.meal.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionSavedMealDeleted)));
    await _load();
  }

  /// Logs [meal] into today. The user picks which configured meal type
  /// the template goes into (the meal types are managed in the
  /// nutrition settings).
  Future<void> _logToday(SavedMealWithItems meal) async {
    final loc = AppLocalizations.of(context)!;
    if (_mealTypes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.nutritionSavedMealNoMealTypes)),
      );
      return;
    }
    final mealType = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.nutritionSavedMealPickMeal),
        children: [
          for (final type in _mealTypes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, type.key),
              child: Text(type.displayName(loc)),
            ),
        ],
      ),
    );
    if (mealType == null || !mounted) return;
    final type = _mealTypes.firstWhere((t) => t.key == mealType);
    setState(() => _isLogging = true);
    try {
      final result = await widget.repository.addSavedMealToDate(
        date: _todayString(),
        mealType: mealType,
        mealName: type.displayName(loc),
        savedMealId: meal.meal.id,
      );
      if (!mounted) return;
      final message = result.added == 0
          ? loc.nutritionSavedMealNothingLogged
          : (result.skipped > 0
                ? loc.nutritionSavedMealPartialLogged(
                    result.added,
                    result.skipped,
                  )
                : loc.nutritionSavedMealLogged(result.added));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isLogging = false);
    }
  }

  static String _todayString() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionSavedMeals),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: loc.nutritionSavedMealNew,
            onPressed: _isLogging ? null : _createMeal,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _meals.isEmpty
          ? EmptyStatePlaceholder(
              icon: Icons.restaurant_menu_outlined,
              title: loc.nutritionSavedMealsEmptyTitle,
              subtitle: loc.nutritionSavedMealsEmptySubtitle,
              actionLabel: loc.nutritionSavedMealNew,
              onAction: _createMeal,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _meals.length,
              itemBuilder: (context, index) {
                final meal = _meals[index];
                return _SavedMealCard(
                  meal: meal,
                  onTap: () => _editMeal(meal),
                  onLog: () => _logToday(meal),
                  onDelete: () => _deleteMeal(meal),
                  isLogging: _isLogging,
                ).animate().fadeIn(duration: 250.ms);
              },
            ),
      floatingActionButton: _isLogging
          ? null
          : FloatingActionButton.extended(
              onPressed: _createMeal,
              icon: const Icon(Icons.add),
              label: Text(loc.nutritionSavedMealNew),
            ),
    );
  }
}

class _SavedMealCard extends StatelessWidget {
  final SavedMealWithItems meal;
  final VoidCallback onTap;
  final VoidCallback onLog;
  final VoidCallback onDelete;
  final bool isLogging;

  const _SavedMealCard({
    required this.meal,
    required this.onTap,
    required this.onLog,
    required this.onDelete,
    required this.isLogging,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final totals = meal.totals;
    final subtitle = <String>[
      if (meal.meal.mealType != null) _mealLabel(loc, meal.meal.mealType!),
      if (meal.meal.portions != 1)
        loc.nutritionSavedMealPortionsLabel(_format(meal.meal.portions)),
      if (totals?.calories != null)
        loc.nutritionConsumedKcal(_format(totals!.calories!)),
    ];
    final macros = <String>[
      if (totals?.proteinG != null) 'P ${_format(totals!.proteinG!)} g',
      if (totals?.carbsG != null) 'C ${_format(totals!.carbsG!)} g',
      if (totals?.fatG != null) 'G ${_format(totals!.fatG!)} g',
    ];
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.meal.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (macros.isNotEmpty)
                      Text(
                        macros.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isLogging)
                IconButton(
                  tooltip: loc.nutritionSavedMealLogToday,
                  onPressed: onLog,
                  icon: const Icon(Icons.playlist_add),
                ),
              PopupMenuButton<String>(
                tooltip: loc.nutritionMealMenu,
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      onTap();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(loc.nutritionEditItem),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_outline),
                      title: Text(loc.nutritionSavedMealDelete),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _mealLabel(AppLocalizations loc, String type) {
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

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
