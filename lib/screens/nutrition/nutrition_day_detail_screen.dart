import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/meal_log_with_items.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/saved_meal_item_draft.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/food_quantity_sheet.dart';
import 'package:workout_notes/screens/nutrition/food_search_screen.dart';
import 'package:workout_notes/screens/nutrition/nutrition_progress_screen.dart';
import 'package:workout_notes/screens/nutrition/nutrition_replicate_day_dialog.dart';
import 'package:workout_notes/screens/nutrition/nutrition_settings_screen.dart';
import 'package:workout_notes/screens/nutrition/saved_meal_editor_screen.dart';
import 'package:workout_notes/screens/nutrition/saved_meals_screen.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/nutrition/nutrition_day_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

part 'nutrition_day_detail_widgets.dart';

enum _NutritionMenuAction {
  progress,
  savedMeals,
  copyPreviousDay,
  replicateDay,
  manageMeals,
}

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
  final NutritionRepository _repository = DatabaseHelper.instance.nutritionRepo;
  final NutritionGateway _gateway = OpenFoodFactsGateway.instance;

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
    _selectedDate = dayOf(widget.initialDate ?? DateTime.now());
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
      final date = dateKey(_selectedDate);
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
        duration: Duration.zero,
      );
    });
  }

  GlobalKey _mealSectionKey(String mealType) => _mealSectionKeys.putIfAbsent(
    mealType,
    () => GlobalKey(debugLabel: 'nutrition-diary-meal-$mealType'),
  );

  Future<void> _changeDay(int delta) async {
    setState(() {
      _selectedDate = dayOf(addDays(_selectedDate, delta));
    });
    await _load();
  }

  Future<void> _jumpToToday() async {
    setState(() => _selectedDate = dayOf(DateTime.now()));
    await _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2018),
      lastDate: addDays(DateTime.now(), 365),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = dayOf(picked));
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
          date: dateKey(_selectedDate),
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
        date: dateKey(_selectedDate),
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
    } catch (e, stack) {
      debugPrint('nutrition_day_detail_screen: action failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonSomethingWentWrong)));
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
      onRemove: () => _deleteItem(item),
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
    } catch (e, stack) {
      debugPrint('nutrition_day_detail_screen: action failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonSomethingWentWrong)));
    } finally {
      if (mounted) setState(() => _isMutating = false);
      await _load();
    }
  }

  Future<void> _deleteItem(MealLogItem item) async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showConfirmDialog(
      context,
      title: loc.nutritionDeleteItem,
      message: loc.nutritionDeleteItemConfirm,
      confirmLabel: loc.commonDelete,
      cancelLabel: loc.nutritionCancel,
      destructive: true,
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
    } catch (error) {
      debugPrint('Restoring the deleted meal item failed: $error');
    }
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
    final yesterday = dateKey(
      dayOf(addDays(_selectedDate, -1)),
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
        date: dateKey(_selectedDate),
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
    final sourceDate = dateKey(_selectedDate);
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
        targetDates: selectedDates.map(dateKey),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.nutritionReplicatedDays(count))),
      );
    } catch (e, stack) {
      debugPrint('nutrition_day_detail_screen: action failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonSomethingWentWrong)));
    } finally {
      if (mounted) setState(() => _isMutating = false);
      await _load();
    }
  }

  /// Repeats the most recent instance of [meal]'s type (before the
  /// selected day) into the selected day, keeping the section name.
  Future<void> _repeatMeal(MealLogWithItems meal) async {
    final loc = AppLocalizations.of(context)!;
    final before = dateKey(_selectedDate);
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
    final isToday = _selectedDate == dayOf(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        centerTitle: false,
        title: Tooltip(
          message: loc.nutritionChooseDate,
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      isToday
                          ? loc.nutritionJumpToday
                          : DateFormat(
                              'EEE, d MMM',
                              Intl.defaultLocale,
                            ).format(_selectedDate),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (!isToday)
            IconButton(
              tooltip: loc.nutritionJumpToday,
              onPressed: _jumpToToday,
              icon: const Icon(Icons.today_rounded),
            ),
          IconButton(
            tooltip: loc.nutritionPreviousDay,
            onPressed: () => _changeDay(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: loc.nutritionNextDay,
            onPressed: () => _changeDay(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          _buildMenu(loc),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => AppSegmentedTabs<int>(
                values: const [0, 1],
                selected: _tabController.index,
                labelOf: (tab) => tab == 0
                    ? loc.nutritionDiaryTab
                    : loc.nutritionDailyStatsTab,
                onChanged: _tabController.animateTo,
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : IgnorePointer(
              ignoring: _isMutating,
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
                          child: FadeSlideIn(
                            duration: const Duration(milliseconds: 220),
                            child: NutritionSummaryCard(
                              summary: _summary,
                              goal: _effective.goal,
                              planInfo: _effective,
                              onConfigureGoal: _openSettings,
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: NutritionSectionLabel(
                            title: loc.nutritionDiaryMealsSection,
                            value: (_summary.consumed.calories ?? 0) > 0
                                ? loc.nutritionConsumedKcal(
                                    nutritionNumber(
                                      _summary.consumed.calories!
                                          .roundToDouble(),
                                    ),
                                  )
                                : null,
                            count: _meals.fold<int>(
                              0,
                              (sum, meal) => sum + meal.items.length,
                            ),
                            padding: const EdgeInsets.fromLTRB(20, 26, 20, 4),
                          ),
                        ),
                        ..._buildMealSlivers(loc),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
    );
  }

  Widget _buildMenu(AppLocalizations loc) {
    PopupMenuItem<_NutritionMenuAction> item(
      _NutritionMenuAction value,
      IconData icon,
      String label,
    ) => PopupMenuItem(
      value: value,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
      ),
    );
    return PopupMenuButton<_NutritionMenuAction>(
      tooltip: loc.nutritionMoreOptions,
      onSelected: (action) => switch (action) {
        _NutritionMenuAction.progress => _openProgress(),
        _NutritionMenuAction.savedMeals => _openSavedMeals(),
        _NutritionMenuAction.copyPreviousDay => _copyPreviousDay(),
        _NutritionMenuAction.replicateDay => _replicateDay(),
        _NutritionMenuAction.manageMeals => _openSettings(),
      },
      itemBuilder: (context) => [
        item(
          _NutritionMenuAction.manageMeals,
          Icons.restaurant_outlined,
          loc.nutritionDiaryManageMeals,
        ),
        item(
          _NutritionMenuAction.progress,
          Icons.insights_outlined,
          loc.nutritionProgressTitle,
        ),
        item(
          _NutritionMenuAction.savedMeals,
          Icons.restaurant_menu_outlined,
          loc.nutritionSavedMeals,
        ),
        const PopupMenuDivider(),
        item(
          _NutritionMenuAction.copyPreviousDay,
          Icons.content_copy_outlined,
          loc.nutritionCopyPreviousDay,
        ),
        item(
          _NutritionMenuAction.replicateDay,
          Icons.calendar_month_outlined,
          loc.nutritionReplicateDay,
        ),
      ],
    );
  }

  /// Renders one card per configured meal type (in catalog order), then
  /// any leftover meals whose type was deleted from the catalog — history
  /// stays visible with its stored name.
  List<Widget> _buildMealSlivers(AppLocalizations loc) {
    final configuredKeys = {for (final type in _mealTypes) type.key};
    final orphanMeals = _meals
        .where((m) => !configuredKeys.contains(m.log.mealType))
        .toList();
    if (_mealTypes.isEmpty && orphanMeals.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: AppEmptyCard(
            icon: Icons.restaurant_outlined,
            title: loc.nutritionNoMealsTitle,
            subtitle: loc.nutritionNoMealsSubtitle,
            action: FilledButton.tonalIcon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(loc.nutritionDiaryManageMeals),
            ),
          ),
        ),
      ];
    }
    Widget card(MealLogWithItems meal, String title) {
      void add() => _addItem(meal.log.mealType, title);
      return FadeSlideIn(
        duration: const Duration(milliseconds: 250),
        delay: const Duration(milliseconds: 40),
        slideY: 0.02,
        child: NutritionMealCard(
          key: _mealSectionKey(meal.log.mealType),
          keyPrefix: 'nutrition-diary',
          title: title,
          meal: meal,
          detailed: true,
          emptyLabel: loc.nutritionMealEmptyHint,
          onOpen: meal.items.isEmpty ? add : null,
          onAdd: add,
          onEditItem: _editItem,
          menu: _MealMenu(
            onRepeat: () => _repeatMeal(meal),
            onSaveAsMeal: () => _saveMealFromDay(meal),
          ),
        ),
      );
    }

    return [
      for (final type in _mealTypes)
        SliverToBoxAdapter(
          child: card(_mealFor(type.key), type.displayName(loc)),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(child: card(meal, meal.log.displayName(loc))),
    ];
  }

  MealLogWithItems _mealFor(String mealType) {
    for (final meal in _meals) {
      if (meal.log.mealType == mealType) return meal;
    }
    return MealLogWithItems(
      log: MealLog(
        id: '',
        date: dateKey(_selectedDate),
        mealType: mealType,
        createdAt: DateTime.now(),
      ),
      items: const [],
    );
  }

}
