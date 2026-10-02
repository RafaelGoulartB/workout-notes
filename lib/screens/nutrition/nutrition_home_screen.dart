import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/food_library_screen.dart';
import 'package:workout_notes/screens/nutrition/food_quantity_sheet.dart';
import 'package:workout_notes/screens/nutrition/food_search_screen.dart';
import 'package:workout_notes/screens/nutrition/nutrition_day_detail_screen.dart';
import 'package:workout_notes/screens/nutrition/nutrition_progress_screen.dart';
import 'package:workout_notes/screens/nutrition/nutrition_settings_screen.dart';
import 'package:workout_notes/screens/nutrition/saved_meals_screen.dart';
import 'package:workout_notes/screens/settings/settings_screen.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/nutrition/nutrition_day_ui.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

export 'package:workout_notes/screens/nutrition/nutrition_day_detail_screen.dart';

/// Nutrition dashboard. Shows the day's totals at a glance, a tools
/// grid (progress, saved meals, food library, settings) and a
/// collapsible "today" panel with one row per configured meal. The
/// per-meal rows open the detailed diary at that meal. Their trailing
/// + buttons open food search pre-bound to the meal, while the summary
/// card opens the detailed diary at the top.
class NutritionHomeScreen extends StatefulWidget {
  const NutritionHomeScreen({super.key});

  @override
  State<NutritionHomeScreen> createState() => _NutritionHomeScreenState();
}

class _NutritionHomeScreenState extends State<NutritionHomeScreen> {
  final NutritionRepository _repository = DatabaseHelper.instance.nutritionRepo;
  final NutritionGateway _gateway = OpenFoodFactsGateway.instance;
  final ScrollController _scrollController = ScrollController();

  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  EffectiveNutritionGoal _effective = const EffectiveNutritionGoal();
  Map<String, double> _weeklyCalories = const {};
  List<MealTypeDefinition> _mealTypes = const [];
  List<MealLogWithItems> _meals = const [];
  late DateTime _selectedDate;
  bool _isLoading = true;
  bool _hasLoaded = false;

  // A failed read keeps the last data on screen (with a retry) instead of
  // passing for an empty diary; data of another day is never shown as this
  // day's, so then the whole body is the error.
  bool _loadFailed = false;
  DateTime? _dataDate;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedDate = dayOf(DateTime.now());
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    final selectedDate = _selectedDate;
    final weekStart = sundayOf(selectedDate);
    setState(() => _isLoading = true);
    try {
      final date = dateKey(selectedDate);
      final results = await Future.wait([
        _repository.getDailySummary(date),
        _repository.getActiveGoal(),
        _repository.getMealTypes(),
        _repository.getDayMeals(date),
        _repository.getDailyNutritionHistoryForRange(
          startDate: weekStart,
          endDate: weekStart.add(const Duration(days: 6)),
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final weeklyCalories = <String, double>{};
      for (final row in results[4] as List<Map<String, dynamic>>) {
        final rowDate = row['date'];
        if (rowDate is String) {
          weeklyCalories[rowDate] = (row['calories'] as num?)?.toDouble() ?? 0;
        }
      }
      setState(() {
        _summary = results[0] as DailyNutritionSummary;
        _effective = EffectiveNutritionGoal(goal: results[1] as NutritionGoal?);
        _weeklyCalories = weeklyCalories;
        _mealTypes = results[2] as List<MealTypeDefinition>;
        _meals = results[3] as List<MealLogWithItems>;
        _isLoading = false;
        _hasLoaded = true;
        _loadFailed = false;
        _dataDate = selectedDate;
      });
      // The plan target is an enhancement to the existing diary summary.
      // Loading it independently keeps diary navigation responsive even when
      // an older/test database has not reached the periodization migration.
      unawaited(_loadEffectiveGoal(selectedDate, generation));
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  bool get _showLoadError =>
      _loadFailed &&
      (_dataDate == null || !isSameDay(_dataDate!, _selectedDate));

  Future<void> _loadEffectiveGoal(DateTime selectedDate, int generation) async {
    try {
      final effective = await EffectiveNutritionGoalService.resolve(
        nutritionRepository: _repository,
        date: selectedDate,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _effective = effective;
      });
    } catch (_) {
      // Nutrition remains fully usable when no periodization data exists.
    }
  }

  Future<void> _selectDate(DateTime date) async {
    final normalized = dayOf(date);
    if (isSameDay(normalized, _selectedDate)) return;
    setState(() => _selectedDate = normalized);
    await _load();
  }

  Future<void> _openDay([DateTime? date, String? mealType]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutritionDayDetailScreen(
          initialDate: date ?? _selectedDate,
          initialMealType: mealType,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openMealInDay(String mealType) =>
      _openDay(_selectedDate, mealType);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    await _selectDate(picked);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutritionSettingsScreen(repository: _repository),
      ),
    );
    await _load();
  }

  Future<void> _openAppSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AppSettingsScreen()));
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

  /// Total number of food items logged for the selected day.
  int get _totalItemsForSelectedDay =>
      _meals.fold<int>(0, (sum, meal) => sum + meal.items.length);

  /// Formats a calorie value as a compact label for the section header
  /// (e.g. "584 kcal"). Returns null when there is nothing to show so
  /// the header hides the value cleanly on an empty day.
  String? _formatKcalLabel(AppLocalizations loc, double? calories) {
    final value = calories ?? 0;
    if (value <= 0) return null;
    return loc.nutritionConsumedKcal(_formatNum(value));
  }

  static String _formatNum(double value) {
    if (value == value.roundToDouble()) return AppNumberFormat.decimal(value, 0);
    return AppNumberFormat.decimal(value, 1);
  }

  Future<void> _openFoodSearchForMeal(
    String? mealType,
    String? mealLabel,
  ) async {
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
      // Saved meals are logged directly by FoodSearchScreen and therefore
      // return no food selection. Refresh when the route closes so those
      // changes are reflected on the dashboard as well.
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
      // The user may have logged a saved meal before selecting this food.
      await _load();
      return;
    }
    await _persistAdd(
      result.mealType ?? mealType,
      result.mealName ?? mealLabel,
      quantity,
    );
  }

  /// Adds a food directly to a specific meal — the action used by the
  /// per-meal "tap-to-add" buttons in the today's meals list.
  Future<void> _addToMeal(MealTypeDefinition type) async {
    final loc = AppLocalizations.of(context)!;
    await _openFoodSearchForMeal(type.key, type.displayName(loc));
  }

  Future<void> _persistAdd(
    String? mealType,
    String? mealLabel,
    NutritionQuantitySelection selection,
  ) async {
    final loc = AppLocalizations.of(context)!;
    final date = dateKey(_selectedDate);
    // If the user came from a per-meal tap and the search screen
    // didn't bind a meal, fall back to the first configured type so
    // we always persist to a real section.
    final resolvedType = mealType ?? _mealTypes.firstOrNull?.key;
    final resolvedLabel =
        mealLabel ??
        (resolvedType == null
            ? null
            : _mealTypes
                  .firstWhere(
                    (t) => t.key == resolvedType,
                    orElse: () => _mealTypes.first,
                  )
                  .displayName(loc));
    if (resolvedType == null || resolvedLabel == null) {
      showAppSnack(context, loc.nutritionSavedMealNoMealTypes);
      return;
    }
    try {
      final upserted = await _repository.upsertFoodWithDetails(
        food: selection.food,
        variants: [selection.variant],
        servings: {selection.variant.id: selection.availableServings},
      );
      await _repository.addMealLogItem(
        date: date,
        mealType: resolvedType,
        name: resolvedLabel,
        food: upserted,
        variant: selection.variant,
        conversion: selection.conversion,
        availableServings: selection.availableServings,
      );
      if (!mounted) return;
      showAppSnack(context, loc.nutritionItemSaved);
    } catch (e, stack) {
      debugPrint('nutrition_home_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    } finally {
      await _load();
    }
  }

  Future<void> _editItem(MealLogItem item) async {
    final details = await _repository.getFoodWithDetails(item.foodId ?? '');
    if (details == null) {
      if (!mounted) return;
      showAppSnack(context, AppLocalizations.of(context)!.nutritionItemFoodUnavailable);
      return;
    }
    final variant = details.variants.isEmpty
        ? null
        : details.variants.firstWhere(
            (candidate) => candidate.id == item.foodVariantId,
            orElse: () => details.variants.first,
          );
    if (variant == null || !mounted) return;
    final selection = await showFoodQuantitySheet(
      context: context,
      food: details.food,
      primaryVariant: variant,
      servings: details.servings[variant.id] ?? const [],
      existing: item,
      onRemove: () => _deleteItem(item),
    );
    if (selection == null || !mounted) return;
    final loc = AppLocalizations.of(context)!;
    try {
      await _repository.updateMealLogItem(
        itemId: item.id,
        conversion: selection.conversion,
        variant: variant,
      );
      if (!mounted) return;
      showAppSnack(context, loc.nutritionItemUpdated);
    } catch (e, stack) {
      debugPrint('nutrition_home_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    } finally {
      await _load();
    }
  }

  Future<void> _deleteItem(MealLogItem item) async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.nutritionDeleteItem,
      message: loc.nutritionDeleteItemConfirm,
      confirmLabel: loc.commonDelete,
      cancelLabel: loc.nutritionCancel,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.deleteMealLogItem(item.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.nutritionItemDeleted),
          action: SnackBarAction(
            label: loc.nutritionUndo,
            onPressed: () async {
              await _repository.restoreMealLogItem(item);
              await _load();
            },
          ),
        ),
      );
    } catch (e, stack) {
      debugPrint('nutrition_home_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    }
  }

  /// Renders one section per configured meal type, then any orphan
  /// sections whose type was deleted from the catalog. Mirrors the
  /// diary's _buildMealSlivers but in a compact form suitable for the
  /// home dashboard.
  List<Widget> _buildMealSlivers(AppLocalizations loc, ThemeData theme) {
    final configuredKeys = {for (final type in _mealTypes) type.key};
    final orphanMeals = _meals
        .where((m) => !configuredKeys.contains(m.log.mealType))
        .toList();
    final empty = _mealTypes.isEmpty && orphanMeals.isEmpty && _meals.isEmpty;
    if (empty) {
      return [
        SliverToBoxAdapter(
          child: AppEmptyCard(
            icon: Icons.restaurant_outlined,
            title: AppLocalizations.of(context)!.nutritionHomeEmptyMeals,
            subtitle: AppLocalizations.of(
              context,
            )!.nutritionHomeEmptyMealsSubtitle,
          ),
        ),
      ];
    }
    return [
      for (final type in _mealTypes)
        SliverToBoxAdapter(
          child: FadeSlideIn(
            duration: const Duration(milliseconds: 220),
            delay: const Duration(milliseconds: 30),
            child: NutritionMealCard(
              title: type.displayName(loc),
              emptyLabel: loc.nutritionHomeEmptyMeals,
              meal: _mealFor(type.key),
              onOpen: () => _openMealInDay(type.key),
              onAdd: () => _addToMeal(type),
              onEditItem: _editItem,
            ),
          ),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(
          child: FadeSlideIn(
            duration: const Duration(milliseconds: 220),
            delay: const Duration(milliseconds: 30),
            child: NutritionMealCard(
              title: meal.log.displayName(loc),
              emptyLabel: loc.nutritionHomeEmptyMeals,
              meal: meal,
              onOpen: () => _openMealInDay(meal.log.mealType),
              onEditItem: _editItem,
              onAdd: () => _addToMeal(
                MealTypeDefinition(
                  id: meal.log.mealType,
                  key: meal.log.mealType,
                  name: meal.log.name,
                  orderIndex: 0,
                  createdAt: DateTime.now(),
                ),
              ),
            ),
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
        date: dateKey(_selectedDate),
        mealType: mealType,
        createdAt: DateTime.now(),
      ),
      items: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Tooltip(
          message: loc.nutritionChooseDate,
          child: InkWell(
            onTap: _pickDay,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      DateFormat(
                        'EEEE, d MMMM',
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
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          const AiCoachHeaderButton(),
          IconButton(
            tooltip: loc.settingsTitle,
            onPressed: _openAppSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _showLoadError
          ? Column(
              children: [
                _NutritionWeekSelector(
                  selectedDate: _selectedDate,
                  onSelected: _selectDate,
                  collapseProgress: 0,
                  weeklyCalories: _weeklyCalories,
                  calorieGoal: _effective.goal?.calories,
                ),
                Expanded(child: LoadErrorView(onRetry: _load)),
              ],
            )
          : _isLoading && !_hasLoaded
          ? Column(
              children: [
                _NutritionWeekSelector(
                  selectedDate: _selectedDate,
                  onSelected: _selectDate,
                  collapseProgress: 0,
                  weeklyCalories: _weeklyCalories,
                  calorieGoal: _effective.goal?.calories,
                ),
                const Expanded(child: _NutritionHomeSkeleton()),
              ],
            )
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _NutritionWeekHeaderDelegate(
                          selectedDate: _selectedDate,
                          onSelected: _selectDate,
                          weeklyCalories: _weeklyCalories,
                          calorieGoal: _effective.goal?.calories,
                        ),
                      ),
                      if (_loadFailed)
                        SliverToBoxAdapter(
                          child: LoadErrorBanner(onRetry: _load),
                        ),
                      SliverToBoxAdapter(
                        child: FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          slideY: 0.05,
                          child: NutritionSummaryCard(
                            summary: _summary,
                            goal: _effective.goal,
                            planInfo: _effective,
                            onTap: _openDay,
                            onConfigureGoal: _openSettings,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: FadeSlideIn(
                            duration: const Duration(milliseconds: 350),
                            delay: const Duration(milliseconds: 120),
                            child: _NutritionToolsGrid(
                              onProgress: _openProgress,
                              onSavedMeals: _openSavedMeals,
                              onFoods: _openFoodLibrary,
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: NutritionSectionLabel(
                          title: isSameDay(_selectedDate, DateTime.now())
                              ? loc.nutritionHomeSectionToday
                              : DateFormat(
                                  'EEEE',
                                  Intl.defaultLocale,
                                ).format(_selectedDate).toUpperCase(),
                          value: _formatKcalLabel(
                            loc,
                            _summary.consumed.calories,
                          ),
                          count: _totalItemsForSelectedDay,
                        ),
                      ),
                      ..._buildMealSlivers(loc, theme),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
                if (_isLoading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
    );
  }
}

class _NutritionWeekSelector extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;
  final double collapseProgress;
  final Map<String, double> weeklyCalories;
  final double? calorieGoal;

  const _NutritionWeekSelector({
    required this.selectedDate,
    required this.onSelected,
    required this.collapseProgress,
    required this.weeklyCalories,
    required this.calorieGoal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = DateTime.now();
    final weekStart = sundayOf(selectedDate);

    return Container(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 10 - (collapseProgress * 4)),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < DateTime.daysPerWeek; index++)
            Expanded(
              child: _NutritionDayButton(
                date: weekStart.add(Duration(days: index)),
                locale: locale,
                collapseProgress: collapseProgress,
                isSelected: isSameDay(
                  weekStart.add(Duration(days: index)),
                  selectedDate,
                ),
                isToday: isSameDay(
                  weekStart.add(Duration(days: index)),
                  today,
                ),
                calorieProgress: _calorieProgress(
                  weeklyCalories[dateKey(
                    weekStart.add(Duration(days: index)),
                  )],
                ),
                isOverCalorieGoal: _isOverCalorieGoal(
                  weeklyCalories[dateKey(
                    weekStart.add(Duration(days: index)),
                  )],
                ),
                onTap: onSelected,
              ),
            ),
        ],
      ),
    );
  }

  double? _calorieProgress(double? calories) {
    if (calorieGoal == null || calorieGoal! <= 0) return null;
    return ((calories ?? 0) / calorieGoal!).clamp(0.0, 1.0).toDouble();
  }

  bool _isOverCalorieGoal(double? calories) =>
      calorieGoal != null && calorieGoal! > 0 && (calories ?? 0) > calorieGoal!;
}

class _NutritionWeekHeaderDelegate extends SliverPersistentHeaderDelegate {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;
  final Map<String, double> weeklyCalories;
  final double? calorieGoal;

  const _NutritionWeekHeaderDelegate({
    required this.selectedDate,
    required this.onSelected,
    required this.weeklyCalories,
    required this.calorieGoal,
  });

  @override
  double get minExtent => 58;

  @override
  double get maxExtent => 86;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    // SliverPersistentHeaderDelegate receives a loose box constraint. Force
    // the child to the exact current sliver extent so its paintExtent never
    // becomes smaller than the layoutExtent while the header is pinned.
    return SizedBox.expand(
      child: Material(
        elevation: overlapsContent ? 1 : 0,
        color: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        child: _NutritionWeekSelector(
          selectedDate: selectedDate,
          onSelected: onSelected,
          collapseProgress: progress,
          weeklyCalories: weeklyCalories,
          calorieGoal: calorieGoal,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _NutritionWeekHeaderDelegate oldDelegate) =>
      oldDelegate.selectedDate != selectedDate ||
      oldDelegate.onSelected != onSelected ||
      oldDelegate.weeklyCalories != weeklyCalories ||
      oldDelegate.calorieGoal != calorieGoal;
}

class _NutritionDayButton extends StatelessWidget {
  final DateTime date;
  final String locale;
  final double collapseProgress;
  final bool isSelected;
  final bool isToday;
  final double? calorieProgress;
  final bool isOverCalorieGoal;
  final ValueChanged<DateTime> onTap;

  const _NutritionDayButton({
    required this.date,
    required this.locale,
    required this.collapseProgress,
    required this.isSelected,
    required this.isToday,
    required this.calorieProgress,
    required this.isOverCalorieGoal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final weekday = DateFormat.E(locale).format(date).characters.first;
    final fullDate = DateFormat.yMMMMEEEEd(locale).format(date);
    const dayCircleSize = 36.0;
    final verticalPadding = 2 * (1 - collapseProgress);

    return Semantics(
      button: true,
      selected: isSelected,
      label: fullDate,
      child: InkResponse(
        onTap: () => onTap(date),
        radius: 28,
        containedInkWell: true,
        highlightShape: BoxShape.circle,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: Align(
                  heightFactor: 1 - collapseProgress,
                  child: Opacity(
                    opacity: 1 - collapseProgress,
                    child: Text(
                      weekday.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isSelected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 5 * (1 - collapseProgress)),
              SizedBox(
                width: dayCircleSize,
                height: dayCircleSize,
                child: CustomPaint(
                  foregroundPainter: calorieProgress == null
                      ? null
                      : _NutritionDayProgressPainter(
                          progress: calorieProgress!,
                          trackColor: colors.outlineVariant.withAlpha(80),
                          progressColor: isOverCalorieGoal
                              ? colors.error
                              : colors.primary,
                        ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    width: dayCircleSize,
                    height: dayCircleSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? colors.primary : Colors.transparent,
                      border: calorieProgress == null
                          ? Border.all(
                              width: isSelected || isToday ? 2 : 1.5,
                              color: isSelected
                                  ? colors.primary
                                  : isToday
                                  ? colors.primary
                                  : colors.outlineVariant,
                            )
                          : null,
                    ),
                    child: Text(
                      '${date.day}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isSelected ? colors.onPrimary : colors.onSurface,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NutritionDayProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;

  const _NutritionDayProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      bounds,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NutritionDayProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

/// Compact row of the three most-used nutrition destinations.
class _NutritionToolsGrid extends StatelessWidget {
  final VoidCallback onProgress;
  final VoidCallback onSavedMeals;
  final VoidCallback onFoods;

  const _NutritionToolsGrid({
    required this.onProgress,
    required this.onSavedMeals,
    required this.onFoods,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final items = [
      _NutritionToolItemData(
        Icons.fastfood_rounded,
        loc.nutritionFoodLibraryTitle,
        onFoods,
      ),
      _NutritionToolItemData(
        Icons.bookmark_outline_rounded,
        loc.nutritionHomeToolMeals,
        onSavedMeals,
      ),
      _NutritionToolItemData(
        Icons.insights_rounded,
        loc.nutritionHomeToolBalance,
        onProgress,
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _NutritionToolTile(
              icon: items[index].icon,
              label: items[index].label,
              onTap: items[index].onTap,
            ),
          ),
        ],
      ],
    );
  }
}

class _NutritionToolItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _NutritionToolItemData(this.icon, this.label, this.onTap);
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
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 21, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton that mirrors the real layout so the first
/// paint doesn't cause a visible jump.
class _NutritionHomeSkeleton extends StatelessWidget {
  const _NutritionHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHighest;
    BoxDecoration box({double r = 8}) =>
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(r));
    Widget line({required double h, double? w, double r = 8}) => Container(
      height: h,
      width: w,
      decoration: box(r: r),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        line(h: 22, w: 160),
        const SizedBox(height: 14),
        line(h: 130, r: 20),
        const SizedBox(height: 22),
        line(h: 12, w: 80),
        const SizedBox(height: 12),
        line(h: 168, r: 16),
        const SizedBox(height: 22),
        line(h: 12, w: 80),
        const SizedBox(height: 8),
        line(h: 62, r: 14),
        const SizedBox(height: 6),
        line(h: 62, r: 14),
        const SizedBox(height: 6),
        line(h: 62, r: 14),
      ],
    );
  }
}
