import 'dart:async';
import 'dart:math' as math;

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
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

import 'food_quantity_sheet.dart';
import 'food_library_screen.dart';
import 'food_search_screen.dart';
import 'nutrition_day_detail_screen.dart';
export 'nutrition_day_detail_screen.dart';

import 'nutrition_progress_screen.dart';
import 'nutrition_settings_screen.dart';
import 'settings_screen.dart';
import 'saved_meals_screen.dart';

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
  final NutritionRepository _repository = NutritionRepository();
  final NutritionGateway _gateway = OpenFoodFactsGateway();
  final ScrollController _scrollController = ScrollController();

  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  NutritionGoal? _goal;
  PeriodizationPhase? _periodizationPhase;
  PeriodizationTarget? _phaseTarget;
  Map<String, double> _weeklyCalories = const {};
  List<MealTypeDefinition> _mealTypes = const [];
  List<MealLogWithItems> _meals = const [];
  late DateTime _selectedDate;
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _showMeals = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(DateTime.now());
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
    final weekStart = _weekStart(selectedDate);
    setState(() => _isLoading = true);
    try {
      final date = _dateString(selectedDate);
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
        _goal = results[1] as NutritionGoal?;
        _periodizationPhase = null;
        _phaseTarget = null;
        _weeklyCalories = weeklyCalories;
        _mealTypes = results[2] as List<MealTypeDefinition>;
        _meals = results[3] as List<MealLogWithItems>;
        _isLoading = false;
        _hasLoaded = true;
      });
      // The plan target is an enhancement to the existing diary summary.
      // Loading it independently keeps diary navigation responsive even when
      // an older/test database has not reached the periodization migration.
      unawaited(_loadPeriodizationTarget(selectedDate, generation));
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
        _weeklyCalories = const {};
      });
    }
  }

  Future<void> _loadPeriodizationTarget(
    DateTime selectedDate,
    int generation,
  ) async {
    try {
      final repository = PeriodizationRepository();
      final phase = await repository.getEffectivePhase(selectedDate);
      final target = phase == null
          ? null
          : await repository.getEffectiveTarget(phase.id, date: selectedDate);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _periodizationPhase = phase;
        _phaseTarget = target;
      });
    } catch (_) {
      // Nutrition remains fully usable when no periodization data exists.
    }
  }

  Future<void> _selectDate(DateTime date) async {
    final normalized = _dateOnly(date);
    if (_isSameDay(normalized, _selectedDate)) return;
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
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
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
          date: _dateString(_selectedDate),
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persistAdd(
    String? mealType,
    String? mealLabel,
    NutritionQuantitySelection selection,
  ) async {
    final loc = AppLocalizations.of(context)!;
    final date = _dateString(_selectedDate);
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
      _showSnack(loc.nutritionSavedMealNoMealTypes);
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
      _showSnack(loc.nutritionItemSaved);
    } catch (e) {
      if (!mounted) return;
      _showSnack(loc.commonError(e.toString()));
    } finally {
      await _load();
    }
  }

  Future<void> _editItem(MealLogItem item) async {
    final details = await _repository.getFoodWithDetails(item.foodId ?? '');
    if (details == null) {
      if (!mounted) return;
      _showSnack(AppLocalizations.of(context)!.nutritionItemFoodUnavailable);
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
      _showSnack(loc.nutritionItemUpdated);
    } catch (e) {
      if (!mounted) return;
      _showSnack(loc.commonError(e.toString()));
    } finally {
      await _load();
    }
  }

  Future<void> _deleteItem(MealLogItem item) async {
    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.nutritionDeleteItem),
        content: Text(loc.nutritionDeleteItemConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.nutritionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
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
    } catch (e) {
      if (!mounted) return;
      _showSnack(loc.commonError(e.toString()));
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
      return [SliverToBoxAdapter(child: _NutritionHomeEmptyMeals())];
    }
    return [
      for (final type in _mealTypes)
        SliverToBoxAdapter(
          child: _NutritionHomeMealRow(
            title: type.displayName(loc),
            meal: _mealFor(type.key),
            onOpen: () => _openMealInDay(type.key),
            onAdd: () => _addToMeal(type),
            onEditItem: _editItem,
          ).animate().fadeIn(duration: 220.ms, delay: 30.ms),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(
          child: _NutritionHomeMealRow(
            title: meal.log.displayName(loc),
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
          ).animate().fadeIn(duration: 220.ms, delay: 30.ms),
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
      body: _isLoading && !_hasLoaded
          ? Column(
              children: [
                _NutritionWeekSelector(
                  selectedDate: _selectedDate,
                  onSelected: _selectDate,
                  collapseProgress: 0,
                  weeklyCalories: _weeklyCalories,
                  calorieGoal: _goal?.calories,
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
                          calorieGoal: _goal?.calories,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child:
                            _periodizationPhase == null || _phaseTarget == null
                            ? const SizedBox.shrink()
                            : _NutritionPhaseBanner(
                                phase: _periodizationPhase!,
                                target: _phaseTarget!,
                              ),
                      ),
                      SliverToBoxAdapter(
                        child:
                            _NutritionDashboardSummaryCard(
                                  summary: _summary,
                                  goal: _effectiveGoal,
                                  onTap: () => _openDay(),
                                  onConfigureGoal: _openSettings,
                                )
                                .animate()
                                .fadeIn(duration: 300.ms, delay: 60.ms)
                                .slideY(begin: 0.05),
                      ),
                      SliverToBoxAdapter(
                        child: _NutritionSectionHeader(
                          text: loc.nutritionHomeSectionTools,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _NutritionToolsGrid(
                          onProgress: _openProgress,
                          onSavedMeals: _openSavedMeals,
                          onFoods: _openFoodLibrary,
                          onSettings: _openSettings,
                        ).animate().fadeIn(duration: 350.ms, delay: 120.ms),
                      ),
                      SliverToBoxAdapter(
                        child: _CollapsibleSectionHeader(
                          icon: Icons.today_outlined,
                          iconBg: theme.colorScheme.primaryContainer,
                          iconFg: theme.colorScheme.onPrimaryContainer,
                          title: _isSameDay(_selectedDate, DateTime.now())
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
                          expanded: _showMeals,
                          onTap: () => setState(() => _showMeals = !_showMeals),
                        ),
                      ),
                      if (_showMeals) ..._buildMealSlivers(loc, theme),
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

  NutritionGoal? get _effectiveGoal {
    final phase = _phaseTarget;
    final base = _goal;
    if (phase == null || phase.nutritionJson.isEmpty) return base;
    final now = DateTime.now();
    return NutritionGoal(
      id: 'periodization:${phase.id}',
      calories: phase.calories ?? base?.calories,
      proteinG: phase.proteinG ?? base?.proteinG,
      carbsG: phase.carbsG ?? base?.carbsG,
      fatG: phase.fatG ?? base?.fatG,
      createdAt: phase.createdAt,
      updatedAt: now,
    );
  }

  static String _dateString(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _weekStart(DateTime value) =>
      value.subtract(Duration(days: value.weekday % DateTime.daysPerWeek));

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _NutritionPhaseBanner extends StatelessWidget {
  final PeriodizationPhase phase;
  final PeriodizationTarget target;

  const _NutritionPhaseBanner({required this.phase, required this.target});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final parts = <String>[];
    if (target.calories != null) {
      parts.add('${target.calories!.round()} kcal');
    }
    if (target.proteinG != null) {
      parts.add('${target.proteinG!.round()}g ${loc.periodizationProteinG}');
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Color(phase.color).withAlpha(30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(phase.color).withAlpha(100)),
      ),
      child: Row(
        children: [
          Icon(Icons.view_timeline_outlined, color: Color(phase.color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(loc.tabPlan, style: Theme.of(context).textTheme.labelSmall),
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
    final weekStart = _weekStart(selectedDate);

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
                isSelected: _isSameDay(
                  weekStart.add(Duration(days: index)),
                  selectedDate,
                ),
                isToday: _isSameDay(
                  weekStart.add(Duration(days: index)),
                  today,
                ),
                calorieProgress: _calorieProgress(
                  weeklyCalories[_dateString(
                    weekStart.add(Duration(days: index)),
                  )],
                ),
                isOverCalorieGoal: _isOverCalorieGoal(
                  weeklyCalories[_dateString(
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

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  double? _calorieProgress(double? calories) {
    if (calorieGoal == null || calorieGoal! <= 0) return null;
    return ((calories ?? 0) / calorieGoal!).clamp(0.0, 1.0).toDouble();
  }

  bool _isOverCalorieGoal(double? calories) =>
      calorieGoal != null && calorieGoal! > 0 && (calories ?? 0) > calorieGoal!;

  static String _dateString(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);

  static DateTime _weekStart(DateTime value) =>
      value.subtract(Duration(days: value.weekday % DateTime.daysPerWeek));
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

class _NutritionDashboardSummaryCard extends StatelessWidget {
  final DailyNutritionSummary summary;
  final NutritionGoal? goal;
  final VoidCallback onTap;
  final VoidCallback onConfigureGoal;

  const _NutritionDashboardSummaryCard({
    required this.summary,
    required this.goal,
    required this.onTap,
    required this.onConfigureGoal,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final calories = summary.consumed.calories ?? 0;
    final calorieGoal = goal?.calories;
    final hasGoal = calorieGoal != null && calorieGoal > 0;
    final progress = hasGoal
        ? (calories / calorieGoal).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
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
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _format(calories, 0),
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 38,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'kcal',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (hasGoal)
                        Text(
                          '${(progress * 100).round()}%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: progress > 1
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _goalLabel(loc, calories, calorieGoal),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: hasGoal ? progress : 0,
                      minHeight: 8,
                      backgroundColor: hasGoal
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surfaceContainerHighest.withAlpha(
                              180,
                            ),
                      color: progress > 1
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _NutritionMacroStat(
                          label: loc.nutritionProgressProtein,
                          value: summary.consumed.proteinG,
                          goal: goal?.proteinG,
                          color: _proteinMacroColor,
                        ),
                      ),
                      _NutritionStatDivider(theme: theme),
                      Expanded(
                        child: _NutritionMacroStat(
                          label: loc.nutritionProgressCarbs,
                          value: summary.consumed.carbsG,
                          goal: goal?.carbsG,
                          color: _carbMacroColor,
                        ),
                      ),
                      _NutritionStatDivider(theme: theme),
                      Expanded(
                        child: _NutritionMacroStat(
                          label: loc.nutritionProgressFat,
                          value: summary.consumed.fatG,
                          goal: goal?.fatG,
                          color: _fatMacroColor,
                        ),
                      ),
                    ],
                  ),
                  if (!hasGoal) ...[
                    const SizedBox(height: 14),
                    Container(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: onConfigureGoal,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.flag_outlined,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                loc.nutritionHomeConfigureGoalPrompt,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              loc.nutritionConfigureGoal,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

/// Color tokens shared with the diary screen so the home stats and
/// the per-meal macros stay in lockstep.
const Color _carbMacroColor = Color(0xFF20A39E);
const Color _proteinMacroColor = Color(0xFFF29E38);
const Color _fatMacroColor = Color(0xFF8E44AD);

class _NutritionStatDivider extends StatelessWidget {
  final ThemeData theme;
  const _NutritionStatDivider({required this.theme});
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

class _NutritionMacroStat extends StatelessWidget {
  final String label;
  final double? value;
  final double? goal;
  final Color color;

  const _NutritionMacroStat({
    required this.label,
    required this.value,
    required this.color,
    this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = value ?? 0;
    final hasGoal = goal != null && goal! > 0;
    final progress = hasGoal ? (current / goal!).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _format(current),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
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
        const SizedBox(height: 4),
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
            value: hasGoal ? progress : 0,
            minHeight: 3,
            backgroundColor: color.withAlpha(35),
            color: color,
          ),
        ),
      ],
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _NutritionSectionHeader extends StatelessWidget {
  final String text;

  const _NutritionSectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
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

/// 2x2 tools grid (4 cells), matching the workout home's
/// _buildNavGrid so the bottom of both tabs feels identical.
class _NutritionToolsGrid extends StatelessWidget {
  final VoidCallback onProgress;
  final VoidCallback onSavedMeals;
  final VoidCallback onFoods;
  final VoidCallback onSettings;

  const _NutritionToolsGrid({
    required this.onProgress,
    required this.onSavedMeals,
    required this.onFoods,
    required this.onSettings,
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
      _NutritionToolItemData(
        Icons.tune_rounded,
        loc.nutritionSettingsTitle,
        onSettings,
      ),
    ];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.7,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            final isLeft = i % 2 == 0;
            final isTop = i < 2;
            return _NutritionToolTile(
              icon: item.icon,
              label: item.label,
              onTap: item.onTap,
              showLeftBorder: !isLeft,
              showTopBorder: !isTop,
            );
          },
        ),
      ),
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
  final bool showLeftBorder;
  final bool showTopBorder;

  const _NutritionToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.showLeftBorder,
    required this.showTopBorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withAlpha(80);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: showLeftBorder
                  ? BorderSide(color: borderColor)
                  : BorderSide.none,
              top: showTopBorder
                  ? BorderSide(color: borderColor)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsible header used by the "Today" section. Renders a
/// small icon chip, a section title, an optional value (e.g. the
/// day's total calories), a count pill and an expand/collapse caret.
/// Matches the workout home's _CollapsibleSectionHeader visually.
class _CollapsibleSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final int count;
  final bool expanded;
  final String? value;
  final VoidCallback onTap;

  const _CollapsibleSectionHeader({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 18, color: iconFg),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (value != null) ...[
              Text(
                value!,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (count > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the "today" meals list. Shows meal name, calories, item
/// count and a circular + button that opens the food search bound to
/// that meal.
class _NutritionHomeMealRow extends StatelessWidget {
  final String title;
  final MealLogWithItems meal;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final ValueChanged<MealLogItem> onEditItem;

  const _NutritionHomeMealRow({
    required this.title,
    required this.meal,
    required this.onOpen,
    required this.onAdd,
    required this.onEditItem,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final kcal = meal.items.fold<double>(
      0,
      (sum, item) => sum + (item.calories ?? 0),
    );
    final itemCount = meal.items.length;
    final hasItems = itemCount > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: ValueKey('nutrition-home-meal-${meal.log.mealType}'),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: hasItems
                            ? theme.colorScheme.primaryContainer.withAlpha(140)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hasItems ? Icons.restaurant_rounded : Icons.add_rounded,
                        color: hasItems
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hasItems
                                ? '${_format(kcal)} kcal · ${loc.nutritionItemCount(itemCount)}'
                                : loc.nutritionHomeEmptyMeals,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: ValueKey('nutrition-home-add-${meal.log.mealType}'),
                      tooltip: loc.nutritionAddItem,
                      onPressed: onAdd,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary.withAlpha(
                          hasItems ? 18 : 28,
                        ),
                      ),
                      icon: Icon(
                        Icons.add_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasItems) ...[
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: theme.colorScheme.outlineVariant.withAlpha(70),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in meal.items.asMap().entries) ...[
                      _NutritionHomeFoodRow(
                        item: entry.value,
                        onTap: () => onEditItem(entry.value),
                      ),
                      if (entry.key < meal.items.length - 1)
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant.withAlpha(55),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _NutritionHomeFoodRow extends StatelessWidget {
  final MealLogItem item;
  final VoidCallback onTap;

  const _NutritionHomeFoodRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toStringAsFixed(0)
        : item.quantity.toStringAsFixed(1);
    final unit = item.unit.trim();
    final quantityLabel = unit.isEmpty ? quantity : '$quantity $unit';
    final calories = item.calories;
    return InkWell(
      key: ValueKey('nutrition-home-food-${item.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.foodNameSnapshot,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    quantityLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (calories != null) ...[
              const SizedBox(width: 10),
              Text(
                '${_NutritionHomeMealRow._format(calories)} kcal',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// First-time / empty state for the "today" meals list. Shown when
/// the meal catalog is empty AND no meals have been logged yet.
class _NutritionHomeEmptyMeals extends StatelessWidget {
  const _NutritionHomeEmptyMeals();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(28),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restaurant_outlined,
                color: theme.colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              loc.nutritionHomeEmptyMeals,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.nutritionHomeEmptyMealsSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
