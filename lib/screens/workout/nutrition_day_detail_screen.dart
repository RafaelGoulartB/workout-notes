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
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

import 'food_quantity_sheet.dart';
import 'food_search_screen.dart';
import 'nutrition_progress_screen.dart';
import 'nutrition_replicate_day_dialog.dart';
import 'nutrition_settings_screen.dart';
import 'periodization_home_screen.dart';
import 'saved_meal_editor_screen.dart';
import 'saved_meals_screen.dart';

part 'nutrition_day_detail_widgets.dart';

enum _NutritionMenuAction {
  progress,
  savedMeals,
  copyPreviousDay,
  replicateDay,
  manageMeals,
}

const _proteinMacroColor = Color(0xFF2563EB);
const _carbMacroColor = Color(0xFFD97706);
const _fatMacroColor = Color(0xFF7C3AED);

/// Daily food diary. This is opened from the nutrition dashboard so meal
/// management stays focused and does not overwhelm the primary tab.
class NutritionDayDetailScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialMealType;

  const NutritionDayDetailScreen({
    super.key,
    this.initialDate,
    this.initialMealType,
  });

  @override
  State<NutritionDayDetailScreen> createState() =>
      _NutritionDayDetailScreenState();
}

class _NutritionDayDetailScreenState extends State<NutritionDayDetailScreen>
    with SingleTickerProviderStateMixin {
  final NutritionRepository _repository = NutritionRepository();
  final NutritionGateway _gateway = OpenFoodFactsGateway();

  late DateTime _selectedDate;
  List<MealTypeDefinition> _mealTypes = const [];
  List<MealLogWithItems> _meals = const [];
  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  EffectiveNutritionGoal _effective = const EffectiveNutritionGoal();
  bool _isLoading = true;
  bool _isMutating = false;
  late final TabController _tabController;
  final Map<String, GlobalKey> _mealSectionKeys = {};
  bool _didScrollToInitialMeal = false;
  int _initialMealScrollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedDate = _dateOnly(widget.initialDate ?? DateTime.now());
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        // The active plan's current week overrides the settings goal.
        EffectiveNutritionGoalService.resolve(
          nutritionRepository: _repository,
          date: _selectedDate,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _mealTypes = results[0] as List<MealTypeDefinition>;
        _meals = results[1] as List<MealLogWithItems>;
        _summary = results[2] as DailyNutritionSummary;
        _effective = results[3] as EffectiveNutritionGoal;
        _isLoading = false;
      });
      _scheduleInitialMealScroll();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _scheduleInitialMealScroll() {
    final mealType = widget.initialMealType;
    if (_didScrollToInitialMeal || mealType == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didScrollToInitialMeal) return;
      final targetContext = _mealSectionKeys[mealType]?.currentContext;
      if (targetContext == null) {
        if (_initialMealScrollAttempts++ < 2) {
          _scheduleInitialMealScroll();
        }
        return;
      }
      _didScrollToInitialMeal = true;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  GlobalKey _mealSectionKey(String mealType) => _mealSectionKeys.putIfAbsent(
    mealType,
    () => GlobalKey(debugLabel: 'nutrition-diary-meal-$mealType'),
  );

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
          date: _dateString(_selectedDate),
        ),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      // Saved meals are persisted inside FoodSearchScreen and do not return
      // a food selection. Reload the diary after leaving the search route.
      await _load();
      return;
    }
    final quantity = await showFoodQuantitySheet(
      context: context,
      food: result.food,
      primaryVariant: result.primaryVariant,
      servings: result.servings,
    );
    if (quantity == null) {
      // A saved meal may already have been logged during this search visit.
      await _load();
      return;
    }
    await _persistAdd(
      result.mealType ?? mealType,
      result.mealName ?? mealLabel,
      quantity,
    );
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
    if (result == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.nutritionItemFoodUnavailable,
          ),
        ),
      );
      return;
    }
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

  /// Replicates every meal with items from the selected day into multiple
  /// dates chosen in the calendar. Existing target items are preserved.
  Future<void> _replicateDay() async {
    final loc = AppLocalizations.of(context)!;
    final sourceDate = _dateString(_selectedDate);
    final source = (await _repository.getDayMeals(
      sourceDate,
    )).where((meal) => meal.items.isNotEmpty).toList();
    if (source.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionReplicateDayNoMeals)));
      return;
    }
    if (!mounted) return;
    final selectedDates = await showDialog<Set<DateTime>>(
      context: context,
      builder: (_) => NutritionReplicateDayDialog(sourceDate: _selectedDate),
    );
    if (selectedDates == null || selectedDates.isEmpty || !mounted) return;

    setState(() => _isMutating = true);
    try {
      final count = await _repository.replicateDayToDates(
        sourceDate: sourceDate,
        targetDates: selectedDates.map(_dateString),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.nutritionReplicatedDays(count))),
      );
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
        titleSpacing: 0,
        title: _DateNavigator(
          date: _selectedDate,
          onPrevious: () => _changeDay(-1),
          onNext: () => _changeDay(1),
          onJumpToday: _jumpToToday,
          onPickDate: _pickDate,
          compact: true,
        ),
        actions: [
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
                case _NutritionMenuAction.replicateDay:
                  _replicateDay();
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
              PopupMenuItem(
                value: _NutritionMenuAction.replicateDay,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(loc.nutritionReplicateDay),
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
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant.withAlpha(90),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      height: 44,
                      child: TabBar(
                        controller: _tabController,
                        dividerHeight: 0,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                        tabs: [
                          Tab(
                            child: _CompactTabLabel(
                              icon: Icons.menu_book_outlined,
                              label: loc.nutritionDiaryTab,
                            ),
                          ),
                          Tab(
                            child: _CompactTabLabel(
                              icon: Icons.donut_large_outlined,
                              label: loc.nutritionDailyStatsTab,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: CustomScrollView(
                            key: const PageStorageKey('nutrition-diary'),
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_effective.fromPlan)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _DayPlanGoalChip(
                                            planInfo: _effective,
                                          ),
                                        ),
                                      _StatisticsSectionCard(
                                        title: loc.nutritionCaloriesTitle,
                                        icon:
                                            Icons
                                                .local_fire_department_outlined,
                                        compact: true,
                                        child: _CalorieEquation(
                                          consumed:
                                              _summary.consumed.calories ?? 0,
                                          goal: _effective.goal?.calories,
                                          carbsG: _summary.consumed.carbsG,
                                          proteinG: _summary.consumed.proteinG,
                                          fatG: _summary.consumed.fatG,
                                          onConfigureGoal: _openSettings,
                                        ),
                                      ),
                                    ],
                                  ),
                                ).animate().fadeIn(duration: 220.ms),
                              ),
                              ..._buildMealSlivers(loc, theme),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 32),
                              ),
                            ],
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _DailyStatisticsView(
                            key: const PageStorageKey('nutrition-statistics'),
                            summary: _summary,
                            goal: _effective.goal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
          child:
              _MealSection(
                    key: _mealSectionKey(type.key),
                    title: type.displayName(loc),
                    meal: _mealFor(type.key),
                    onAdd: () => _addItem(type.key, type.displayName(loc)),
                    onEdit: _editItem,
                    onDelete: _deleteItem,
                    onRepeat: () => _repeatMeal(_mealFor(type.key)),
                    onSaveAsMeal: () => _saveMealFromDay(_mealFor(type.key)),
                  )
                  .animate()
                  .fadeIn(duration: 250.ms, delay: 40.ms)
                  .slideY(begin: 0.02),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(
          child:
              _MealSection(
                    key: _mealSectionKey(meal.log.mealType),
                    title: meal.log.displayName(loc),
                    meal: meal,
                    onAdd: () =>
                        _addItem(meal.log.mealType, meal.log.displayName(loc)),
                    onEdit: _editItem,
                    onDelete: _deleteItem,
                    onRepeat: () => _repeatMeal(meal),
                    onSaveAsMeal: () => _saveMealFromDay(meal),
                  )
                  .animate()
                  .fadeIn(duration: 250.ms, delay: 40.ms)
                  .slideY(begin: 0.02),
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

/// Small chip shown when an active plan's current week is overriding
/// the settings goal for the viewed day. Tapping opens the
/// periodization home.
class _DayPlanGoalChip extends StatelessWidget {
  final EffectiveNutritionGoal planInfo;

  const _DayPlanGoalChip({required this.planInfo});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final phase = planInfo.phase!;
    final color = Color(phase.color);
    final label = loc.nutritionGoalPlanBadge(
      phase.name,
      planInfo.weekNumber ?? 1,
      planInfo.totalWeeks ?? 1,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PeriodizationHomeScreen(),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_note_rounded, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
