import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
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

  Future<void> _openDay([DateTime? date, String? mealType]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NutritionDayDetailScreen(
          initialDate: date ?? DateTime.now(),
          initialMealType: mealType,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openMealInDay(String mealType) =>
      _openDay(DateTime.now(), mealType);

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
          date: _dateString(DateTime.now()),
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
    final date = _dateString(DateTime.now());
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
          ).animate().fadeIn(duration: 220.ms, delay: 30.ms),
        ),
      for (final meal in orphanMeals)
        SliverToBoxAdapter(
          child: _NutritionHomeMealRow(
            title: meal.log.displayName(loc),
            meal: meal,
            onOpen: () => _openMealInDay(meal.log.mealType),
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
          const AiCoachHeaderButton(),
          IconButton(
            tooltip: loc.nutritionChooseDate,
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: loc.settingsTitle,
            onPressed: _openAppSettings,
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
                    child:
                        _NutritionDashboardSummaryCard(
                              summary: _summary,
                              goal: _goal,
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
                      title: loc.nutritionHomeSectionToday,
                      value: _formatKcalLabel(loc, _summary.consumed.calories),
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

  const _NutritionHomeMealRow({
    required this.title,
    required this.meal,
    required this.onOpen,
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
