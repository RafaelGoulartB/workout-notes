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

enum _NutritionMenuAction { progress, savedMeals, copyPreviousDay, manageMeals }

/// Nutrition dashboard. Shows the day's totals at a glance, a tools
/// grid (progress, saved meals, food library, settings) and a
/// collapsible "today" panel with one row per configured meal. The
/// per-meal rows open the food search pre-bound to that meal so the
/// most common action — adding a food — is a single tap away. Tapping
/// the summary card opens the detailed diary.
class NutritionHomeScreen extends StatefulWidget {
  const NutritionHomeScreen({super.key});

  @override
  State<NutritionHomeScreen> createState() => _NutritionHomeScreenState();
}

class _NutritionHomeScreenState extends State<NutritionHomeScreen> {
  final NutritionRepository _repository = NutritionRepository();
  final NutritionGateway _gateway = OpenFoodFactsGateway();

  DailyNutritionSummary _summary = DailyNutritionSummary.empty;
  NutritionGoal? _goal;
  List<MealTypeDefinition> _mealTypes = const [];
  List<MealLogWithItems> _meals = const [];
  bool _isLoading = true;
  bool _showMeals = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final date = _dateString(DateTime.now());
      final results = await Future.wait([
        _repository.getDailySummary(date),
        _repository.getActiveGoal(),
        _repository.getMealTypes(),
        _repository.getDayMeals(date),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as DailyNutritionSummary;
        _goal = results[1] as NutritionGoal?;
        _mealTypes = results[2] as List<MealTypeDefinition>;
        _meals = results[3] as List<MealLogWithItems>;
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

  /// Total number of food items logged today across all meal sections.
  int get _totalItemsToday =>
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

  Future<void> _openFoodSearchForMeal(String? mealType, String? mealLabel) async {
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
    if (result == null || !mounted) return;
    final quantity = await showFoodQuantitySheet(
      context: context,
      food: result.food,
      primaryVariant: result.primaryVariant,
      servings: result.servings,
    );
    if (quantity == null) return;
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persistAdd(
    String? mealType,
    String? mealLabel,
    NutritionQuantitySelection selection,
  ) async {
    final loc = AppLocalizations.of(context)!;
    final date = _dateString(DateTime.now());
    // If the user came from a per-meal tap and the search screen
    // didn't bind a meal, fall back to the first configured type so
    // we always persist to a real section.
    final resolvedType = mealType ?? _mealTypes.firstOrNull?.key;
    final resolvedLabel = mealLabel ?? (resolvedType == null
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

  /// Renders one section per configured meal type, then any orphan
  /// sections whose type was deleted from the catalog. Mirrors the
  /// diary's _buildMealSlivers but in a compact form suitable for the
  /// home dashboard.
  List<Widget> _buildMealSlivers(AppLocalizations loc, ThemeData theme) {
    final configuredKeys = {for (final type in _mealTypes) type.key};
    final orphanMeals = _meals
        .where((m) => !configuredKeys.contains(m.log.mealType))
        .toList();
    final empty =
        _mealTypes.isEmpty && orphanMeals.isEmpty && _meals.isEmpty;
    if (empty) {
      return [SliverToBoxAdapter(child: _NutritionHomeEmptyMeals())];
    }
    return [
      for (final type in _mealTypes)
        SliverToBoxAdapter(
          child: _NutritionHomeMealRow(
            title: type.displayName(loc),
            meal: _mealFor(type.key),
            onAdd: () => _addToMeal(type),
          ).animate().fadeIn(duration: 220.ms, delay: 30.ms),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(
          child: _NutritionHomeMealRow(
            title: meal.log.displayName(loc),
            meal: meal,
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
        date: _dateString(DateTime.now()),
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
          ? const _NutritionHomeSkeleton()
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
                      onConfigureGoal: _openSettings,
                    ).animate().fadeIn(duration: 300.ms, delay: 60.ms).slideY(
                      begin: 0.05,
                    ),
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
                      title: loc.nutritionHomeSectionToday,
                      value: _formatKcalLabel(
                        loc,
                        _summary.consumed.calories,
                      ),
                      count: _totalItemsToday,
                      expanded: _showMeals,
                      onTap: () => setState(() => _showMeals = !_showMeals),
                    ),
                  ),
                  if (_showMeals) ..._buildMealSlivers(loc, theme),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
                    style: theme.textTheme.bodySmall?.copyWith(
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
                          : theme.colorScheme.surfaceContainerHighest
                                .withAlpha(180),
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
        Icons.insights_rounded,
        loc.nutritionHomeToolHistory,
        onProgress,
      ),
      _NutritionToolItemData(
        Icons.bookmark_outline_rounded,
        loc.nutritionHomeToolMeals,
        onSavedMeals,
      ),
      _NutritionToolItemData(
        Icons.fastfood_rounded,
        loc.nutritionFoodLibraryTitle,
        onFoods,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
  final VoidCallback onAdd;

  const _NutritionHomeMealRow({
    required this.title,
    required this.meal,
    required this.onAdd,
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
        child: InkWell(
          onTap: onAdd,
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
                    hasItems
                        ? Icons.restaurant_rounded
                        : Icons.add_rounded,
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(hasItems ? 18 : 28),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
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

/// Daily food diary. This is opened from the nutrition dashboard so meal
/// management stays focused and does not overwhelm the primary tab.
class NutritionDayDetailScreen extends StatefulWidget {
  final DateTime? initialDate;

  const NutritionDayDetailScreen({super.key, this.initialDate});

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
  NutritionGoal? _goal;
  bool _isLoading = true;
  bool _isMutating = false;
  late final TabController _tabController;

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
                                  child: _StatisticsSectionCard(
                                    title: loc.nutritionCaloriesTitle,
                                    icon: Icons.local_fire_department_rounded,
                                    compact: true,
                                    child: _CalorieEquation(
                                      consumed: _summary.consumed.calories ?? 0,
                                      goal: _goal?.calories,
                                      carbsG: _summary.consumed.carbsG,
                                      proteinG: _summary.consumed.proteinG,
                                      fatG: _summary.consumed.fatG,
                                      onConfigureGoal: _openSettings,
                                    ),
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
                            goal: _goal,
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
  /// â€” history stays visible with its stored name.
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

class _CompactTabLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CompactTabLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 17),
      const SizedBox(width: 7),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

class _DateNavigator extends StatelessWidget {
  final DateTime date;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onJumpToday;
  final VoidCallback onPickDate;
  final bool compact;

  const _DateNavigator({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onJumpToday,
    required this.onPickDate,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isToday = _dateOnly(date) == _dateOnly(DateTime.now());
    final formattedDate = isToday
        ? loc.nutritionJumpToday
        : compact
        ? DateFormat.MMMEd(Intl.defaultLocale).format(date)
        : DateFormat.yMMMMEEEEd(Intl.defaultLocale).format(date);
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: loc.nutritionPreviousDay,
            onPressed: onPrevious ?? onJumpToday,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        formattedDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!isToday && !compact) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: onJumpToday,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 26),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(loc.nutritionJumpToday),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: loc.nutritionNextDay,
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Statistics for the currently selected diary date. Keeping this inside the
/// day screen makes date navigation update the diary and its analysis together.
class _DailyStatisticsView extends StatelessWidget {
  final DailyNutritionSummary summary;
  final NutritionGoal? goal;

  const _DailyStatisticsView({
    super.key,
    required this.summary,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final values = summary.consumed;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _StatisticsSectionCard(
          title: loc.nutritionMacrosTitle,
          icon: Icons.donut_large_rounded,
          child: Row(
            children: [
              Expanded(
                child: _MacroRing(
                  label: loc.nutritionProgressCarbs,
                  consumed: values.carbsG,
                  goal: goal?.carbsG,
                  color: const Color(0xFF20A39E),
                ),
              ),
              Expanded(
                child: _MacroRing(
                  label: loc.nutritionProgressProtein,
                  consumed: values.proteinG,
                  goal: goal?.proteinG,
                  color: const Color(0xFFF29E38),
                ),
              ),
              Expanded(
                child: _MacroRing(
                  label: loc.nutritionProgressFat,
                  consumed: values.fatG,
                  goal: goal?.fatG,
                  color: const Color(0xFF8E44AD),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 260.ms, delay: 40.ms),
        const SizedBox(height: 12),
        _StatisticsSectionCard(
          title: loc.nutritionNutrientsTitle,
          icon: Icons.monitor_heart_outlined,
          child: Column(
            children: [
              _NutrientProgressRow(
                label: loc.nutritionProgressProtein,
                consumed: values.proteinG,
                goal: goal?.proteinG,
                unit: 'g',
                color: const Color(0xFFF29E38),
              ),
              _NutrientProgressRow(
                label: loc.nutritionProgressCarbs,
                consumed: values.carbsG,
                goal: goal?.carbsG,
                unit: 'g',
                color: const Color(0xFF20A39E),
              ),
              _NutrientProgressRow(
                label: loc.nutritionProgressFiber,
                consumed: values.fiberG,
                unit: 'g',
                color: const Color(0xFF5B9D63),
              ),
              _NutrientProgressRow(
                label: loc.nutritionProgressSugars,
                consumed: values.sugarsG,
                unit: 'g',
                color: const Color(0xFFD4758F),
              ),
              _NutrientProgressRow(
                label: loc.nutritionProgressFat,
                consumed: values.fatG,
                goal: goal?.fatG,
                unit: 'g',
                color: const Color(0xFF8E44AD),
              ),
              _NutrientProgressRow(
                label: loc.nutritionProgressSodium,
                consumed: values.sodiumMg,
                unit: 'mg',
                color: Theme.of(context).colorScheme.primary,
                isLast: true,
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms, delay: 80.ms),
      ],
    );
  }
}

class _StatisticsSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final bool compact;

  const _StatisticsSectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
            : const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 9 : 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _CalorieEquation extends StatelessWidget {
  final double consumed;
  final double? goal;
  final double? carbsG;
  final double? proteinG;
  final double? fatG;
  final VoidCallback onConfigureGoal;

  const _CalorieEquation({
    required this.consumed,
    required this.goal,
    this.carbsG,
    this.proteinG,
    this.fatG,
    required this.onConfigureGoal,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasGoal = goal != null && goal! > 0;
    final remaining = hasGoal ? goal! - consumed : null;
    final carbCalories = (carbsG ?? 0) * 4;
    final proteinCalories = (proteinG ?? 0) * 4;
    final fatCalories = (fatG ?? 0) * 9;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _EquationValue(
                value: hasGoal ? _formatNutritionNumber(goal!) : 'â€”',
                label: loc.nutritionCaloriesGoalLabel,
              ),
            ),
            const _EquationSymbol(Icons.remove_rounded),
            Expanded(
              child: _EquationValue(
                value: _formatNutritionNumber(consumed),
                label: loc.nutritionCaloriesFoodLabel,
              ),
            ),
            const _EquationSymbol(Icons.drag_handle_rounded),
            Expanded(
              child: _EquationValue(
                value: remaining == null
                    ? 'â€”'
                    : _formatNutritionNumber(remaining),
                label: loc.nutritionCaloriesRemainingLabel,
                color: remaining != null && remaining < 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        if (hasGoal) ...[
          const SizedBox(height: 10),
          _MacroCalorieBar(
            goalCalories: goal!,
            carbCalories: carbCalories,
            proteinCalories: proteinCalories,
            fatCalories: fatCalories,
          ),
          const SizedBox(height: 7),
          _MacroCalorieLegend(
            carbCalories: carbCalories,
            proteinCalories: proteinCalories,
            fatCalories: fatCalories,
          ),
        ] else ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: onConfigureGoal,
            child: Text(loc.nutritionConfigureGoal),
          ),
        ],
      ],
    );
  }
}

class _EquationValue extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;

  const _EquationValue({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MacroCalorieBar extends StatelessWidget {
  final double goalCalories;
  final double carbCalories;
  final double proteinCalories;
  final double fatCalories;

  const _MacroCalorieBar({
    required this.goalCalories,
    required this.carbCalories,
    required this.proteinCalories,
    required this.fatCalories,
  });

  @override
  Widget build(BuildContext context) {
    final total = carbCalories + proteinCalories + fatCalories;
    final scale = total > goalCalories && total > 0
        ? goalCalories / total
        : 1.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 7,
        child: LayoutBuilder(
          builder: (context, constraints) {
            double widthFor(double calories) =>
                constraints.maxWidth * calories * scale / goalCalories;
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  SizedBox(
                    width: widthFor(carbCalories),
                    child: const ColoredBox(color: _carbMacroColor),
                  ),
                  SizedBox(
                    width: widthFor(proteinCalories),
                    child: const ColoredBox(color: _proteinMacroColor),
                  ),
                  SizedBox(
                    width: widthFor(fatCalories),
                    child: const ColoredBox(color: _fatMacroColor),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MacroCalorieLegend extends StatelessWidget {
  final double carbCalories;
  final double proteinCalories;
  final double fatCalories;

  const _MacroCalorieLegend({
    required this.carbCalories,
    required this.proteinCalories,
    required this.fatCalories,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MacroLegendItem(
          color: _carbMacroColor,
          label: loc.nutritionProgressCarbs,
          calories: carbCalories,
        ),
        _MacroLegendItem(
          color: _proteinMacroColor,
          label: loc.nutritionProgressProtein,
          calories: proteinCalories,
        ),
        _MacroLegendItem(
          color: _fatMacroColor,
          label: loc.nutritionProgressFat,
          calories: fatCalories,
        ),
      ],
    );
  }
}

class _MacroLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final double calories;

  const _MacroLegendItem({
    required this.color,
    required this.label,
    required this.calories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${label.characters.first} ${_formatNutritionNumber(calories)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EquationSymbol extends StatelessWidget {
  final IconData icon;

  const _EquationSymbol(this.icon);

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    size: 17,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

class _MacroRing extends StatelessWidget {
  final String label;
  final double? consumed;
  final double? goal;
  final Color color;

  const _MacroRing({
    required this.label,
    required this.consumed,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = consumed ?? 0;
    final hasGoal = goal != null && goal! > 0;
    final progress = hasGoal ? (current / goal!).clamp(0.0, 1.0) : 0.0;
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 9),
        SizedBox.square(
          dimension: 70,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: hasGoal ? progress : 0,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: color.withAlpha(35),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatNutritionNumber(current),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    hasGoal ? '/${_formatNutritionNumber(goal!)}g' : 'g',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Text(
          hasGoal
              ? '${_formatNutritionNumber((goal! - current).clamp(0, double.infinity).toDouble())} g ${AppLocalizations.of(context)!.nutritionRemainingLabel.toLowerCase()}'
              : 'â€”',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _NutrientProgressRow extends StatelessWidget {
  final String label;
  final double? consumed;
  final double? goal;
  final String unit;
  final Color color;
  final bool isLast;

  const _NutrientProgressRow({
    required this.label,
    required this.consumed,
    this.goal,
    required this.unit,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = consumed ?? 0;
    final hasGoal = goal != null && goal! > 0;
    final remaining = hasGoal ? goal! - current : null;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_formatNutritionNumber(current)}$unit',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hasGoal) ...[
                Text(
                  '  /  ${_formatNutritionNumber(goal!)}$unit',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: Text(
                    '${_formatNutritionNumber(remaining!)}$unit',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: remaining < 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: hasGoal ? (current / goal!).clamp(0.0, 1.0) : 0,
              minHeight: 4,
              color: color,
              backgroundColor: color.withAlpha(32),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatNutritionNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// One meal section: clean header (title + totals + add/menu) over a
/// bordered list of items. No colored header band — the card stays
/// uniform with the rest of the app.
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
    final kcalTotal = meal.items.fold<double>(
      0,
      (sum, item) => sum + (item.calories ?? 0),
    );
    final proteinTotal = meal.items.fold<double>(
      0,
      (sum, item) => sum + (item.proteinG ?? 0),
    );
    final carbsTotal = meal.items.fold<double>(
      0,
      (sum, item) => sum + (item.carbsG ?? 0),
    );
    final fatTotal = meal.items.fold<double>(
      0,
      (sum, item) => sum + (item.fatG ?? 0),
    );
    final hasItems = meal.items.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The header sits on a subtly tinted surface (one step
            // darker/lighter than the card body, depending on the
            // brightness) so the eye can read the title row as a
            // distinct "section" above the items without the saturated
            // primaryContainer band the previous design used.
            ColoredBox(
              color: theme.colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitleText(
                              loc: loc,
                              itemCount: meal.items.length,
                              carbsG: carbsTotal,
                              proteinG: proteinTotal,
                              fatG: fatTotal,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (hasItems) ...[
                      Text(
                        '${_format(kcalTotal)} kcal',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      tooltip: loc.nutritionAddItem,
                      onPressed: onAdd,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle_outline),
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
            ),
            if (hasItems)
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            if (!hasItems)
              _MealEmptyState(onAdd: onAdd)
            else
              ...meal.items.asMap().entries.map(
                (entry) => _MealItemTile(
                  item: entry.value,
                  isLast: entry.key == meal.items.length - 1,
                  onEdit: () => onEdit(entry.value),
                  onDelete: () => onDelete(entry.value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds the header subtitle. When the meal is empty we show the
  /// localized "0 items" string; when it has items we surface a single
  /// readable line with the count and the macro grams.
  static String _subtitleText({
    required AppLocalizations loc,
    required int itemCount,
    required double carbsG,
    required double proteinG,
    required double fatG,
  }) {
    if (itemCount == 0) return loc.nutritionItemCount(0);
    return '${loc.nutritionItemCount(itemCount)}  ·  '
        'C ${_format(carbsG)}g  ·  '
        'P ${_format(proteinG)}g  ·  '
        'G ${_format(fatG)}g';
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

/// Inline empty state for a meal section. Renders a dashed placeholder
/// row that calls the same add callback as the header + button.
class _MealEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _MealEmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              Icons.add_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              loc.nutritionAddItem,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
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

/// One row inside a meal section. Renders the food name, a compact
/// subtitle (quantity · brand), the per-item calories on the right and
/// a single overflow menu with edit / delete actions. Tapping the row
/// itself opens the quantity sheet to edit.
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
    final subtitleParts = <String>[
      '$qty$unitSuffix',
      if (item.brandSnapshot != null && item.brandSnapshot!.trim().isNotEmpty)
        item.brandSnapshot!,
    ];
    final hasWarning = item.hasMissingValues || item.isEstimated;
    final calories = item.calories;
    return Column(
      children: [
        if (!isLast)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: theme.colorScheme.outlineVariant.withAlpha(60),
          ),
        InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.foodNameSnapshot,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (hasWarning) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: loc.nutritionMissingValues,
                              child: Icon(
                                Icons.info_outline,
                                size: 14,
                                color: _nutritionWarningColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (calories != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      loc.nutritionConsumedKcal(
                        calories.toStringAsFixed(calories < 10 ? 1 : 0),
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: loc.nutritionEditItem,
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        onEdit();
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
                        leading: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          loc.nutritionDeleteItem,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Soft amber used for incomplete/estimated data warnings in both
/// light and dark themes.
const Color _nutritionWarningColor = Color(0xFFF0A202);
