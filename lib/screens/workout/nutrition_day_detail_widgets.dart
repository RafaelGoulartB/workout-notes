part of 'nutrition_day_detail_screen.dart';

/// Overflow menu of a meal card: repeat the last one or save it as a meal.
class _MealMenu extends StatelessWidget {
  final VoidCallback onRepeat;
  final VoidCallback onSaveAsMeal;

  const _MealMenu({required this.onRepeat, required this.onSaveAsMeal});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: loc.nutritionMealMenu,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
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
    );
  }
}

/// Shown when no meal types are configured and nothing was logged.
class _EmptyDayCard extends StatelessWidget {
  final VoidCallback onConfigureMeals;

  const _EmptyDayCard({required this.onConfigureMeals});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            AppIconBadge(Icons.restaurant_outlined),
            const SizedBox(height: 12),
            Text(
              loc.nutritionNoMealsTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.nutritionNoMealsSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onConfigureMeals,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: Text(loc.nutritionDiaryManageMeals),
            ),
          ],
        ),
      ),
    );
  }
}

/// One nutrient of the statistics tab.
class _Nutrient {
  final String id;
  final String label;
  final double? consumed;
  final double? goal;
  final String unit;
  final Color color;

  /// The goal is a ceiling (sugars, sodium, saturated fat): going over it
  /// is flagged instead of counting as done.
  final bool limit;

  const _Nutrient(
    this.id,
    this.label,
    this.consumed,
    this.unit,
    this.color, {
    this.goal,
    this.limit = false,
  });
}

/// Statistics for the selected diary date: the macro rings and the
/// calorie split, then every tracked nutrient grouped in cards.
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
    final calorieGoal = goal?.calories;
    final hasCalorieGoal = calorieGoal != null && calorieGoal > 0;

    final groups = <(String, List<_Nutrient>)>[
      (
        loc.nutritionNutrientsTitle,
        [
          _Nutrient(
            'fiber',
            loc.nutritionProgressFiber,
            values.fiberG,
            'g',
            const Color(0xFF43A66A),
            goal: 25,
          ),
          _Nutrient(
            'sugars',
            loc.nutritionProgressSugars,
            values.sugarsG,
            'g',
            const Color(0xFFD85F8A),
            goal: hasCalorieGoal ? calorieGoal * 0.10 / 4 : null,
            limit: true,
          ),
          _Nutrient(
            'sodium',
            loc.nutritionProgressSodium,
            values.sodiumMg,
            'mg',
            const Color(0xFF3A9FCC),
            goal: 2300,
            limit: true,
          ),
        ],
      ),
      (
        loc.nutritionFatBreakdownTitle,
        [
          _Nutrient(
            'saturated-fat',
            _withoutTrailingUnit(loc.nutritionFatSaturated),
            values.saturatedFatG,
            'g',
            const Color(0xFFA95C68),
            goal: hasCalorieGoal ? calorieGoal * 0.10 / 9 : null,
            limit: true,
          ),
          _Nutrient(
            'polyunsaturated-fat',
            _withoutTrailingUnit(loc.nutritionFatPolyunsaturated),
            values.polyunsaturatedFatG,
            'g',
            const Color(0xFF658B6F),
          ),
          _Nutrient(
            'monounsaturated-fat',
            _withoutTrailingUnit(loc.nutritionFatMonounsaturated),
            values.monounsaturatedFatG,
            'g',
            const Color(0xFFB58B3C),
          ),
          _Nutrient(
            'trans-fat',
            _withoutTrailingUnit(loc.nutritionFatTrans),
            values.transFatG,
            'g',
            const Color(0xFF9A6B73),
          ),
        ],
      ),
      (
        loc.nutritionNutrientMineralsTitle,
        [
          _Nutrient(
            'potassium',
            loc.nutritionProgressPotassium,
            values.potassiumMg,
            'mg',
            const Color(0xFF4E8D7C),
            goal: 3500,
          ),
          _Nutrient(
            'calcium',
            loc.nutritionProgressCalcium,
            values.calciumMg,
            'mg',
            const Color(0xFF5C7AEA),
            goal: 1000,
          ),
          _Nutrient(
            'iron',
            loc.nutritionProgressIron,
            values.ironMg,
            'mg',
            const Color(0xFFB75D69),
            goal: 14,
          ),
          _Nutrient(
            'magnesium',
            loc.nutritionProgressMagnesium,
            values.magnesiumMg,
            'mg',
            const Color(0xFF6D8299),
            goal: 260,
          ),
          _Nutrient(
            'zinc',
            loc.nutritionProgressZinc,
            values.zincMg,
            'mg',
            const Color(0xFF8F7A66),
            goal: 11,
          ),
        ],
      ),
      (
        loc.nutritionNutrientVitaminsTitle,
        [
          _Nutrient(
            'vitamin-a',
            loc.nutritionProgressVitaminA,
            values.vitaminAUg,
            'µg',
            const Color(0xFFE38B29),
            goal: 800,
          ),
          _Nutrient(
            'vitamin-c',
            loc.nutritionProgressVitaminC,
            values.vitaminCMg,
            'mg',
            const Color(0xFF6A994E),
            goal: 100,
          ),
          _Nutrient(
            'vitamin-d',
            loc.nutritionProgressVitaminD,
            values.vitaminDUg,
            'µg',
            const Color(0xFFF2C14E),
            goal: 15,
          ),
          _Nutrient(
            'vitamin-b12',
            loc.nutritionProgressVitaminB12,
            values.vitaminB12Ug,
            'µg',
            const Color(0xFF7B61A8),
            goal: 2.4,
          ),
        ],
      ),
    ];

    return FadeSlideIn(
      duration: const Duration(milliseconds: 260),
      delay: const Duration(milliseconds: 40),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _MacrosCard(summary: summary, goal: goal),
          for (final (title, nutrients) in groups) ...[
            AppSectionHeader(title),
            AppSectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < nutrients.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        color: AppUi.divider(Theme.of(context).colorScheme),
                      ),
                    _NutrientStatRow(nutrient: nutrients[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Macro rings against the goal plus the share of calories of each macro.
class _MacrosCard extends StatelessWidget {
  final DailyNutritionSummary summary;
  final NutritionGoal? goal;

  const _MacrosCard({required this.summary, required this.goal});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final values = summary.consumed;
    final proteinKcal = (values.proteinG ?? 0) * 4;
    final carbsKcal = (values.carbsG ?? 0) * 4;
    final fatKcal = (values.fatG ?? 0) * 9;
    final totalKcal = proteinKcal + carbsKcal + fatKcal;

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconBadge(Icons.donut_large_rounded, size: 34, iconSize: 18),
              const SizedBox(width: 10),
              Text(
                loc.nutritionMacrosTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MacroRing(
                  label: loc.nutritionProgressProtein,
                  consumed: values.proteinG,
                  goal: goal?.proteinG,
                  color: NutritionMacroColors.protein,
                ),
              ),
              Expanded(
                child: _MacroRing(
                  label: loc.nutritionProgressCarbs,
                  consumed: values.carbsG,
                  goal: goal?.carbsG,
                  color: NutritionMacroColors.carbs,
                ),
              ),
              Expanded(
                child: _MacroRing(
                  label: loc.nutritionProgressFat,
                  consumed: values.fatG,
                  goal: goal?.fatG,
                  color: NutritionMacroColors.fat,
                ),
              ),
            ],
          ),
          if (totalKcal > 0) ...[
            const SizedBox(height: 18),
            Divider(height: 1, color: AppUi.divider(theme.colorScheme)),
            const SizedBox(height: 14),
            Text(
              loc.nutritionMacroSplitTitle,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (kcal, color) in [
                      (proteinKcal, NutritionMacroColors.protein),
                      (carbsKcal, NutritionMacroColors.carbs),
                      (fatKcal, NutritionMacroColors.fat),
                    ])
                      if (kcal > 0)
                        Expanded(
                          flex: (kcal / totalKcal * 1000).round().clamp(
                            1,
                            1000,
                          ),
                          child: ColoredBox(color: color),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                for (final (label, kcal, color) in [
                  (
                    loc.nutritionProgressProtein,
                    proteinKcal,
                    NutritionMacroColors.protein,
                  ),
                  (
                    loc.nutritionProgressCarbs,
                    carbsKcal,
                    NutritionMacroColors.carbs,
                  ),
                  (loc.nutritionProgressFat, fatKcal, NutritionMacroColors.fat),
                ])
                  AppLegendItem(
                    color: color,
                    label: '$label ${(kcal / totalKcal * 100).round()}%',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
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
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final current = consumed ?? 0;
    final hasGoal = goal != null && goal! > 0;
    final remaining = hasGoal ? goal! - current : null;

    return Column(
      children: [
        SizedBox.square(
          dimension: 74,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: hasGoal ? (current / goal!).clamp(0.0, 1.0) : 0,
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
                    nutritionNumber(current.roundToDouble()),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    hasGoal ? '/ ${nutritionNumber(goal!)} g' : 'g',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          remaining == null
              ? '—'
              : remaining > 0
              ? loc.nutritionNutrientLeft(
                  '${nutritionNumber(remaining.roundToDouble())} g',
                )
              : loc.nutritionNutrientGoalReached,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Nutrient name with "consumed of goal" and a progress bar in its color.
class _NutrientStatRow extends StatelessWidget {
  final _Nutrient nutrient;

  const _NutrientStatRow({required this.nutrient});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final n = nutrient;
    final current = n.consumed ?? 0;
    final goal = n.goal;
    final hasGoal = goal != null && goal > 0;

    final over = n.limit && hasGoal && current > goal;
    final barColor = over ? theme.colorScheme.error : n.color;

    return Padding(
      key: ValueKey('nutrition-stat-${n.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: n.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${nutritionNumber(current)} ${n.unit}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: over ? theme.colorScheme.error : null,
                      ),
                    ),
                    if (hasGoal)
                      TextSpan(
                        text:
                            ' ${loc.nutritionNutrientOfGoal('${nutritionNumber(goal)} ${n.unit}')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                style: const TextStyle(fontFeatures: AppUi.tabular),
              ),
            ],
          ),
          if (hasGoal) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (current / goal).clamp(0.0, 1.0),
                minHeight: 4,
                color: barColor,
                backgroundColor: barColor.withAlpha(35),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _withoutTrailingUnit(String label) =>
    label.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
