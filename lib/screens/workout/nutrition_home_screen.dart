import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

import 'food_quantity_sheet.dart';
import 'food_library_screen.dart';
import 'food_search_screen.dart';
import 'nutrition_progress_screen.dart';
import 'nutrition_settings_screen.dart';
import 'saved_meal_editor_screen.dart';
import 'saved_meals_screen.dart';

enum _NutritionMenuAction {
  progress,
  savedMeals,
  copyPreviousDay,
  manageMeals,
}

/// Nutrition dashboard with a compact daily overview and tools section.
class NutritionHomeScreen extends StatefulWidget {
  const NutritionHomeScreen({super.key});

  @override
  State<NutritionHomeScreen> createState() => _NutritionHomeScreenState();
}

class _NutritionHomeScreenState extends State<NutritionHomeScreen> {
  final NutritionRepository _repository = NutritionRepository();
  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  NutritionGoal? _goal;
  bool _isLoading = true;

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
        _repository.getDailySummary(_dateString(DateTime.now())),
        _repository.getActiveGoal(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as DailyNutritionSummary;
        _goal = results[1] as NutritionGoal?;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openDay([DateTime? date]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NutritionDayDetailScreen(initialDate: date ?? DateTime.now()),
      ),
    );
    await _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    await _openDay(picked);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutritionSettingsScreen(repository: _repository),
      ),
    );
    await _load();
  }

  Future<void> _openProgress() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NutritionProgressScreen()));
  }

  Future<void> _openSavedMeals() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedMealsScreen(repository: _repository),
      ),
    );
    await _load();
  }

  Future<void> _openFoodLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoodLibraryScreen(repository: _repository),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          DateFormat('EEEE, d MMMM', Intl.defaultLocale).format(DateTime.now()),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: loc.nutritionChooseDate,
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: loc.nutritionSettingsTitle,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _NutritionDashboardSummaryCard(
                      summary: _summary,
                      goal: _goal,
                      onTap: _openDay,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _NutritionSectionHeader(
                      text: loc.nutritionHomeSectionTools,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _NutritionToolsCard(
                      onProgress: _openProgress,
                      onSavedMeals: _openSavedMeals,
                      onFoods: _openFoodLibrary,
                    ).animate().fadeIn(duration: 350.ms, delay: 160.ms),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
    );
  }

  static String _dateString(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

class _NutritionDashboardSummaryCard extends StatelessWidget {
  final DailyNutritionSummary summary;
  final NutritionGoal? goal;
  final VoidCallback onTap;

  const _NutritionDashboardSummaryCard({
    required this.summary,
    required this.goal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final calories = summary.consumed.calories ?? 0;
    final calorieGoal = goal?.calories;
    final progress = calorieGoal == null || calorieGoal <= 0
        ? null
        : (calories / calorieGoal).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.surfaceContainerHighest.withAlpha(200),
                theme.colorScheme.surfaceContainerLow,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_outlined,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loc.nutritionSummaryTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.nutritionConsumedKcal(_format(calories, 0)),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _goalLabel(loc, calories, calorieGoal),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _NutritionMacroStat(
                          label: loc.nutritionProgressProtein,
                          value: summary.consumed.proteinG,
                        ),
                      ),
                      Expanded(
                        child: _NutritionMacroStat(
                          label: loc.nutritionProgressCarbs,
                          value: summary.consumed.carbsG,
                        ),
                      ),
                      Expanded(
                        child: _NutritionMacroStat(
                          label: loc.nutritionProgressFat,
                          value: summary.consumed.fatG,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          loc.nutritionHomeSummarySubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 80.ms).slideY(begin: 0.04);
  }

  static String _goalLabel(
    AppLocalizations loc,
    double calories,
    double? goal,
  ) {
    if (goal == null) return loc.nutritionGoalNoGoal;
    final remaining = goal - calories;
    return remaining >= 0
        ? loc.nutritionGoalRemaining(_format(remaining, 0))
        : loc.nutritionGoalSurplus(_format(-remaining, 0));
  }

  static String _format(double value, int decimals) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(decimals == 0 ? 1 : decimals);
  }
}

class _NutritionMacroStat extends StatelessWidget {
  final String label;
  final double? value;

  const _NutritionMacroStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = value == null
        ? '—'
        : value! == value!.roundToDouble()
        ? value!.toStringAsFixed(0)
        : value!.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$formatted g',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _NutritionSectionHeader extends StatelessWidget {
  final String text;

  const _NutritionSectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NutritionToolsCard extends StatelessWidget {
  final VoidCallback onProgress;
  final VoidCallback onSavedMeals;
  final VoidCallback onFoods;

  const _NutritionToolsCard({
    required this.onProgress,
    required this.onSavedMeals,
    required this.onFoods,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
        child: SizedBox(
          height: 225,
          child: Column(
            children: [
              SizedBox(
                height: 112,
                child: Row(
                  children: [
                    Expanded(
                      child: _NutritionToolTile(
                        icon: Icons.insights_outlined,
                        label: loc.nutritionProgressTitle,
                        onTap: onProgress,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant.withAlpha(70),
                    ),
                    Expanded(
                      child: _NutritionToolTile(
                        icon: Icons.restaurant_menu_outlined,
                        label: loc.nutritionSavedMeals,
                        onTap: onSavedMeals,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withAlpha(70),
              ),
              SizedBox(
                height: 112,
                child: _NutritionToolTile(
                  icon: Icons.fastfood_outlined,
                  label: loc.nutritionFoodLibraryTitle,
                  onTap: onFoods,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NutritionToolTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NutritionToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Daily food diary. This is opened from the nutrition dashboard so meal
/// management stays focused and does not overwhelm the primary tab.
class NutritionDayDetailScreen extends StatefulWidget {
  final DateTime? initialDate;

  const NutritionDayDetailScreen({super.key, this.initialDate});

  @override
  State<NutritionDayDetailScreen> createState() =>
      _NutritionDayDetailScreenState();
}

class _NutritionDayDetailScreenState extends State<NutritionDayDetailScreen> {
  final NutritionRepository _repository = NutritionRepository();
  final NutritionGateway _gateway = OpenFoodFactsGateway();

  late DateTime _selectedDate;
  List<MealTypeDefinition> _mealTypes = const [];
  List<MealLogWithItems> _meals = const [];
  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  NutritionGoal? _goal;
  bool _isLoading = true;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.initialDate ?? DateTime.now());
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final date = _dateString(_selectedDate);
      final results = await Future.wait([
        _repository.getMealTypes(),
        _repository.getDayMeals(date),
        _repository.getDailySummary(date),
        _repository.getActiveGoal(),
      ]);
      if (!mounted) return;
      setState(() {
        _mealTypes = results[0] as List<MealTypeDefinition>;
        _meals = results[1] as List<MealLogWithItems>;
        _summary = results[2] as DailyNutritionSummary;
        _goal = results[3] as NutritionGoal?;
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

  Future<void> _addItem(String mealType, String mealLabel) async {
    final result = await Navigator.of(context).push<NutritionSelection>(
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          gateway: _gateway,
          repository: _repository,
          mealType: mealType,
          mealName: mealLabel,
        ),
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
    await _persistAdd(mealType, mealLabel, quantity);
  }

  Future<void> _persistAdd(
    String mealType,
    String mealLabel,
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
        name: mealLabel,
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

  Future<void> _openProgress() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NutritionProgressScreen()));
  }

  Future<void> _openSavedMeals() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedMealsScreen(repository: _repository),
      ),
    );
    await _load();
  }

  /// Copies the meals of the previous day into the selected day. The
  /// user picks which meal types to carry over via a checkbox dialog.
  Future<void> _copyPreviousDay() async {
    final loc = AppLocalizations.of(context)!;
    final yesterday = _dateString(
      _dateOnly(_selectedDate.subtract(const Duration(days: 1))),
    );
    final source = (await _repository.getDayMeals(
      yesterday,
    )).where((m) => m.items.isNotEmpty).toList();
    if (source.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionCopyNothingToCopy)));
      return;
    }
    final selected = <String>{for (final m in source) m.log.mealType};
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.nutritionCopyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in source)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.log.displayName(loc)),
                  subtitle: Text(loc.nutritionItemCount(m.items.length)),
                  value: selected.contains(m.log.mealType),
                  onChanged: (checked) => setDialogState(() {
                    if (checked ?? false) {
                      selected.add(m.log.mealType);
                    } else {
                      selected.remove(m.log.mealType);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.nutritionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.nutritionCopyConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    var count = 0;
    for (final m in source) {
      if (!selected.contains(m.log.mealType)) continue;
      count += await _repository.copyItemsToMeal(
        date: _dateString(_selectedDate),
        mealType: m.log.mealType,
        name: m.log.name,
        items: m.items,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionCopiedItems(count))));
    await _load();
  }

  /// Repeats the most recent instance of [meal]'s type (before the
  /// selected day) into the selected day, keeping the section name.
  Future<void> _repeatMeal(MealLogWithItems meal) async {
    final loc = AppLocalizations.of(context)!;
    final before = _dateString(_selectedDate);
    final items = await _repository.getLatestMealItems(
      meal.log.mealType,
      beforeDate: before,
    );
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionRepeatNoPrevious)));
      return;
    }
    final name = await _repository.getLatestMealName(
      meal.log.mealType,
      beforeDate: before,
    );
    final count = await _repository.copyItemsToMeal(
      date: before,
      mealType: meal.log.mealType,
      name: name,
      items: items,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionCopiedItems(count))));
    await _load();
  }

  /// Saves [meal]'s items as a meal template.
  Future<void> _saveMealFromDay(MealLogWithItems meal) async {
    final loc = AppLocalizations.of(context)!;
    if (meal.items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionSaveMealEmpty)));
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavedMealEditorScreen(
          repository: _repository,
          initialName: meal.log.displayName(loc),
          initialItems: meal.items
              .map(SavedMealItemDraft.fromMealLogItem)
              .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionHomeDiary),
        actions: [
          IconButton(
            tooltip: loc.nutritionSettingsTitle,
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<_NutritionMenuAction>(
            tooltip: loc.nutritionMoreOptions,
            onSelected: (action) {
              switch (action) {
                case _NutritionMenuAction.progress:
                  _openProgress();
                  break;
                case _NutritionMenuAction.savedMeals:
                  _openSavedMeals();
                  break;
                case _NutritionMenuAction.copyPreviousDay:
                  _copyPreviousDay();
                  break;
                case _NutritionMenuAction.manageMeals:
                  _openSettings();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _NutritionMenuAction.manageMeals,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restaurant_outlined),
                  title: Text(loc.nutritionDiaryManageMeals),
                ),
              ),
              PopupMenuItem(
                value: _NutritionMenuAction.progress,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insights_outlined),
                  title: Text(loc.nutritionProgressTitle),
                ),
              ),
              PopupMenuItem(
                value: _NutritionMenuAction.savedMeals,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restaurant_menu_outlined),
                  title: Text(loc.nutritionSavedMeals),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _NutritionMenuAction.copyPreviousDay,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.content_copy_outlined),
                  title: Text(loc.nutritionCopyPreviousDay),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : IgnorePointer(
              ignoring: _isMutating,
              child: RefreshIndicator(
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
                    ..._buildMealSlivers(loc, theme),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
    );
  }

  /// Renders one section per configured meal type (in catalog order),
  /// then any leftover sections whose type was deleted from the catalog
  /// — history stays visible with its stored name.
  List<Widget> _buildMealSlivers(AppLocalizations loc, ThemeData theme) {
    final configuredKeys = {for (final type in _mealTypes) type.key};
    final orphanMeals = _meals
        .where((m) => !configuredKeys.contains(m.log.mealType))
        .toList();
    if (_mealTypes.isEmpty && orphanMeals.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _EmptyDayCard(onConfigureMeals: _openSettings),
        ),
      ];
    }
    return [
      for (final type in _mealTypes)
        SliverToBoxAdapter(
          child: _MealSection(
            title: type.displayName(loc),
            meal: _mealFor(type.key),
            onAdd: () => _addItem(type.key, type.displayName(loc)),
            onEdit: _editItem,
            onDelete: _deleteItem,
            onRepeat: () => _repeatMeal(_mealFor(type.key)),
            onSaveAsMeal: () => _saveMealFromDay(_mealFor(type.key)),
          ),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(
          child: _MealSection(
            title: meal.log.displayName(loc),
            meal: meal,
            onAdd: () => _addItem(meal.log.mealType, meal.log.displayName(loc)),
            onEdit: _editItem,
            onDelete: _deleteItem,
            onRepeat: () => _repeatMeal(meal),
            onSaveAsMeal: () => _saveMealFromDay(meal),
          ),
        ),
    ];
  }

  MealLogWithItems _mealFor(String mealType) {
    for (final meal in _meals) {
      if (meal.log.mealType == mealType) return meal;
    }
    return MealLogWithItems(
      log: MealLog(
        id: '',
        date: _dateString(_selectedDate),
        mealType: mealType,
        createdAt: DateTime.now(),
      ),
      items: const [],
    );
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
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniNutrientStat(
                      label: loc.nutritionProgressFiber,
                      value: summary.consumed.fiberG,
                      suffix: 'g',
                      icon: Icons.grass,
                    ),
                  ),
                  Expanded(
                    child: _MiniNutrientStat(
                      label: loc.nutritionProgressSugars,
                      value: summary.consumed.sugarsG,
                      suffix: 'g',
                      icon: Icons.cookie_outlined,
                    ),
                  ),
                  Expanded(
                    child: _MiniNutrientStat(
                      label: loc.nutritionProgressSodium,
                      value: summary.consumed.sodiumMg,
                      suffix: 'mg',
                      icon: Icons.water_drop_outlined,
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

class _MiniNutrientStat extends StatelessWidget {
  final String label;
  final double? value;
  final String suffix;
  final IconData icon;

  const _MiniNutrientStat({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          value == null ? '—' : '${_format(value!)} $suffix',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
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

class _MealSection extends StatelessWidget {
  final String title;
  final MealLogWithItems meal;
  final VoidCallback onAdd;
  final void Function(MealLogItem item) onEdit;
  final void Function(MealLogItem item) onDelete;
  final VoidCallback onRepeat;
  final VoidCallback onSaveAsMeal;

  const _MealSection({
    required this.title,
    required this.meal,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRepeat,
    required this.onSaveAsMeal,
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
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
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
                  PopupMenuButton<String>(
                    tooltip: loc.nutritionMealMenu,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) {
                      switch (action) {
                        case 'repeat':
                          onRepeat();
                        case 'save':
                          onSaveAsMeal();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'repeat',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.replay_outlined),
                          title: Text(loc.nutritionRepeatMeal),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'save',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.bookmark_add_outlined),
                          title: Text(loc.nutritionSaveMeal),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (meal.items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
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
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// Shown when the selected day has no meal sections yet.
class _EmptyDayCard extends StatelessWidget {
  final VoidCallback onConfigureMeals;

  const _EmptyDayCard({required this.onConfigureMeals});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          child: Column(
            children: [
              Icon(
                Icons.restaurant_menu_rounded,
                size: 56,
                color: theme.colorScheme.primary.withAlpha(140),
              ),
              const SizedBox(height: 16),
              Text(
                loc.nutritionNoMealsTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.nutritionNoMealsSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onConfigureMeals,
                icon: const Icon(Icons.settings_outlined),
                label: Text(loc.nutritionDiaryManageMeals),
              ),
            ],
          ),
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
