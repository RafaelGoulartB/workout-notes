import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

import 'food_quantity_sheet.dart';
import 'food_search_screen.dart';
import 'manual_food_screen.dart';
import 'nutrition_settings_screen.dart';

/// Daily nutrition screen. Lists the four meals, shows the daily
/// summary and surfaces the goal progress when one is configured.
class NutritionHomeScreen extends StatefulWidget {
  const NutritionHomeScreen({super.key});

  @override
  State<NutritionHomeScreen> createState() => _NutritionHomeScreenState();
}

class _NutritionHomeScreenState extends State<NutritionHomeScreen> {
  final NutritionRepository _repository = NutritionRepository();
  final NutritionGateway _gateway = OpenFoodFactsGateway();

  DateTime _selectedDate = _dateOnly(DateTime.now());
  List<MealLogWithItems> _meals = const [];
  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  NutritionGoal? _goal;
  bool _isLoading = true;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final date = _dateString(_selectedDate);
      final results = await Future.wait([
        _repository.getDayMeals(date),
        _repository.getDailySummary(date),
        _repository.getActiveGoal(),
      ]);
      if (!mounted) return;
      setState(() {
        _meals = results[0] as List<MealLogWithItems>;
        _summary = results[1] as DailyNutritionSummary;
        _goal = results[2] as NutritionGoal?;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeDay(int delta) async {
    setState(() {
      _selectedDate = _dateOnly(_selectedDate.add(Duration(days: delta)));
    });
    await _load();
  }

  Future<void> _jumpToToday() async {
    setState(() => _selectedDate = _dateOnly(DateTime.now()));
    await _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = _dateOnly(picked));
    await _load();
  }

  Future<void> _addItem(String mealType) async {
    final result = await Navigator.of(context).push<NutritionSelection>(
      MaterialPageRoute(
        builder: (_) =>
            FoodSearchScreen(gateway: _gateway, repository: _repository),
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    final quantity = await showFoodQuantitySheet(
      context: context,
      food: result.food,
      primaryVariant: result.primaryVariant,
      servings: result.servings,
    );
    if (quantity == null) return;
    await _persistAdd(mealType, quantity);
  }

  Future<void> _persistAdd(
    String mealType,
    NutritionQuantitySelection selection,
  ) async {
    final loc = AppLocalizations.of(context)!;
    setState(() => _isMutating = true);
    try {
      final upserted = await _repository.upsertFoodWithDetails(
        food: selection.food,
        variants: [selection.variant],
        servings: {selection.variant.id: selection.availableServings},
      );
      await _repository.addMealLogItem(
        date: _dateString(_selectedDate),
        mealType: mealType,
        food: upserted,
        variant: selection.variant,
        conversion: selection.conversion,
        availableServings: selection.availableServings,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionItemSaved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isMutating = false);
      await _load();
    }
  }

  Future<void> _editItem(MealLogItem item) async {
    final result = await _repository.getFoodWithDetails(item.foodId ?? '');
    if (result == null) return;
    final variant = result.variants.isEmpty
        ? null
        : result.variants.firstWhere(
            (v) => v.id == item.foodVariantId,
            orElse: () => result.variants.first,
          );
    if (variant == null) return;
    if (!mounted) return;
    final selection = await showFoodQuantitySheet(
      context: context,
      food: result.food,
      primaryVariant: variant,
      servings: result.servings[variant.id] ?? const [],
      existing: item,
    );
    if (selection == null) return;
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    setState(() => _isMutating = true);
    try {
      await _repository.updateMealLogItem(
        itemId: item.id,
        conversion: selection.conversion,
        variant: variant,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionItemUpdated)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isMutating = false);
      await _load();
    }
  }

  Future<void> _deleteItem(MealLogItem item) async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.nutritionDeleteItem),
        content: Text(loc.nutritionDeleteItemConfirm),
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
    if (confirm != true) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isMutating = true);
    try {
      await _repository.deleteMealLogItem(item.id);
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(loc.nutritionItemDeleted),
          action: SnackBarAction(
            label: loc.nutritionUndo,
            onPressed: () => _undoDelete(item),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  /// Re-inserts a deleted item (the snackbar "undo" action). The
  /// parent meal log still exists, so the original row can be put
  /// back with its id, snapshot and links intact.
  Future<void> _undoDelete(MealLogItem item) async {
    try {
      await _repository.restoreMealLogItem(item);
    } catch (_) {}
    if (!mounted) return;
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutritionSettingsScreen(repository: _repository),
      ),
    );
    await _load();
  }

  Future<void> _openManualFood() async {
    final created = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => ManualFoodScreen(repository: _repository),
      ),
    );
    if (created == null) return;
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionManualSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: loc.nutritionConfigureGoal,
            onPressed: _openSettings,
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _DateNavigator(
                      date: _selectedDate,
                      // Always navigable: disabling the arrow on empty
                      // days made it fall back to "go to today", so the
                      // user could never reach a previous day from an
                      // empty one.
                      onPrevious: () => _changeDay(-1),
                      onNext: () => _changeDay(1),
                      onJumpToday: _jumpToToday,
                      onPickDate: _pickDate,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _DailySummaryCard(
                      summary: _summary,
                      goal: _goal,
                      onConfigureGoal: _openSettings,
                    ).animate().fadeIn(duration: 250.ms),
                  ),
                  if (_summary.hasIncompleteData)
                    SliverToBoxAdapter(child: _IncompleteWarning()),
                  ..._buildMealSlivers(loc, theme),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
      floatingActionButton: _isMutating
          ? null
          : FloatingActionButton.extended(
              onPressed: _openManualFood,
              icon: const Icon(Icons.add),
              label: Text(loc.nutritionAddManually),
            ),
    );
  }

  List<Widget> _buildMealSlivers(AppLocalizations loc, ThemeData theme) {
    final widgets = <Widget>[];
    final presentTypes = {for (final m in _meals) m.log.mealType};
    for (final type in MealType.displayOrder) {
      final meal = _meals.firstWhere(
        (m) => m.log.mealType == type,
        orElse: () => MealLogWithItems(
          log: MealLog(
            id: '',
            date: _dateString(_selectedDate),
            mealType: type,
            createdAt: DateTime.now(),
          ),
          items: const [],
        ),
      );
      widgets.add(
        SliverToBoxAdapter(
          child: _MealSection(
            title: _mealLabel(loc, type),
            meal: meal,
            isEmpty: !presentTypes.contains(type),
            onAdd: () => _addItem(type),
            onEdit: _editItem,
            onDelete: _deleteItem,
          ),
        ),
      );
    }
    return widgets;
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

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      _dateOnly(value).toIso8601String().substring(0, 10);
}

class _DateNavigator extends StatelessWidget {
  final DateTime date;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onJumpToday;
  final VoidCallback onPickDate;

  const _DateNavigator({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onJumpToday,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final today = _dateOnly(DateTime.now());
    final isToday = _dateOnly(date) == today;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: loc.nutritionPreviousDay,
            onPressed: onPrevious ?? onJumpToday,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  children: [
                    Text(
                      DateFormat.yMMMMEEEEd(Intl.defaultLocale).format(date),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!isToday)
                      TextButton(
                        onPressed: onJumpToday,
                        child: Text(loc.nutritionJumpToday),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: loc.nutritionNextDay,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _DailySummaryCard extends StatelessWidget {
  final DailyNutritionSummary summary;
  final NutritionGoal? goal;
  final VoidCallback onConfigureGoal;

  const _DailySummaryCard({
    required this.summary,
    required this.goal,
    required this.onConfigureGoal,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final calories = summary.consumed.calories;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    loc.nutritionSummaryTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (calories == null)
                Text(
                  '0 kcal',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                Text(
                  loc.nutritionConsumedKcal(_formatNumber(calories, 0)),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 6),
              if (goal?.calories != null)
                Text(
                  _remainingText(loc, goal!.calories!, calories ?? 0),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        loc.nutritionGoalNoGoal,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onConfigureGoal,
                      child: Text(loc.nutritionConfigureGoal),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              _MacroProgress(
                label: loc.nutritionProgressProtein,
                consumed: summary.consumed.proteinG,
                goal: goal?.proteinG,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: 8),
              _MacroProgress(
                label: loc.nutritionProgressCarbs,
                consumed: summary.consumed.carbsG,
                goal: goal?.carbsG,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 8),
              _MacroProgress(
                label: loc.nutritionProgressFat,
                consumed: summary.consumed.fatG,
                goal: goal?.fatG,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _remainingText(
    AppLocalizations loc,
    double goal,
    double consumed,
  ) {
    final delta = goal - consumed;
    if (delta >= 0) {
      return loc.nutritionGoalRemaining(_formatNumber(delta, 0));
    }
    return loc.nutritionGoalSurplus(_formatNumber(-delta, 0));
  }

  static String _formatNumber(double value, int decimals) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(decimals);
  }
}

class _MacroProgress extends StatelessWidget {
  final String label;
  final double? consumed;
  final double? goal;
  final Color color;

  const _MacroProgress({
    required this.label,
    required this.consumed,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGoal = goal != null && goal! > 0;
    final fraction = hasGoal
        ? ((consumed ?? 0) / goal!).clamp(0.0, 1.5).toDouble()
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            if (consumed != null)
              Text(
                '${_format(consumed!)} g',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (hasGoal)
              Text(
                ' / ${_format(goal!)} g',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (hasGoal) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: color.withAlpha(40),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ],
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

class _IncompleteWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withAlpha(110),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loc.nutritionIncompleteWarning,
                style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  final String title;
  final MealLogWithItems meal;
  final bool isEmpty;
  final VoidCallback onAdd;
  final void Function(MealLogItem item) onEdit;
  final void Function(MealLogItem item) onDelete;

  const _MealSection({
    required this.title,
    required this.meal,
    required this.isEmpty,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          loc.nutritionItemCount(meal.items.length),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(loc.nutritionAddItem),
                  ),
                ],
              ),
            ),
            if (meal.items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: isEmpty
                    ? Text(
                        loc.nutritionEmptySubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Text(
                        loc.nutritionEmptySubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              )
            else
              ...meal.items.asMap().entries.map(
                (entry) => _MealItemTile(
                  item: entry.value,
                  isLast: entry.key == meal.items.length - 1,
                  onEdit: () => onEdit(entry.value),
                  onDelete: () => onDelete(entry.value),
                ),
              ),
            if (meal.items.isEmpty)
              const SizedBox(height: 4)
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _MealItemTile extends StatelessWidget {
  final MealLogItem item;
  final bool isLast;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MealItemTile({
    required this.item,
    required this.isLast,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final qty = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toStringAsFixed(0)
        : item.quantity.toStringAsFixed(1);
    final unitSuffix = item.unit.trim().isEmpty ? '' : ' ${item.unit}';
    final subtitle = <String>[
      '$qty$unitSuffix',
      if (item.calories != null)
        loc.nutritionConsumedKcal(
          item.calories!.toStringAsFixed(item.calories! < 10 ? 1 : 0),
        ),
    ].join(' · ');
    return Column(
      children: [
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        ListTile(
          title: Text(item.foodNameSnapshot),
          subtitle: Text(subtitle),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: loc.nutritionEditItem,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: loc.nutritionDeleteItem,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Helper used by the home screen to present the quantity modal. The
/// function lives in this file so it has access to the same imports as
/// the surrounding screen.
Future<NutritionQuantitySelection?> showFoodQuantitySheet({
  required BuildContext context,
  required Food food,
  required FoodVariant? primaryVariant,
  required List<FoodServing> servings,
  MealLogItem? existing,
}) async {
  if (primaryVariant == null) {
    return null;
  }
  return showModalBottomSheet<NutritionQuantitySelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return FoodQuantitySheet(
        food: food,
        primaryVariant: primaryVariant,
        servings: servings,
        existing: existing,
      );
    },
  );
}
