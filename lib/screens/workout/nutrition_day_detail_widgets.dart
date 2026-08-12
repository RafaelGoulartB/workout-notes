part of 'nutrition_day_detail_screen.dart';

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
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            loc.nutritionNutrientsTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _SecondaryNutrientsCard(
          storageKey: 'fat-breakdown',
          title: loc.nutritionFatBreakdownTitle,
          icon: Icons.opacity_outlined,
          children: [
            _NutrientProgressRow(
              label: loc.nutritionFatSaturated,
              consumed: values.saturatedFatG,
              unit: 'g',
              color: const Color(0xFFA95C68),
            ),
            _NutrientProgressRow(
              label: loc.nutritionFatMonounsaturated,
              consumed: values.monounsaturatedFatG,
              unit: 'g',
              color: const Color(0xFFB58B3C),
            ),
            _NutrientProgressRow(
              label: loc.nutritionFatPolyunsaturated,
              consumed: values.polyunsaturatedFatG,
              unit: 'g',
              color: const Color(0xFF658B6F),
            ),
            _NutrientProgressRow(
              label: loc.nutritionFatTrans,
              consumed: values.transFatG,
              unit: 'g',
              color: const Color(0xFF9A6B73),
              isLast: true,
            ),
          ],
        ).animate().fadeIn(duration: 280.ms, delay: 70.ms),
        const SizedBox(height: 12),
        _SecondaryNutrientsCard(
          storageKey: 'other-nutrients',
          title: loc.nutritionOtherNutrientsTitle,
          icon: Icons.tune_rounded,
          children: [
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
              label: loc.nutritionProgressSodium,
              consumed: values.sodiumMg,
              unit: 'mg',
              color: Theme.of(context).colorScheme.primary,
              isLast: true,
            ),
          ],
        ).animate().fadeIn(duration: 300.ms, delay: 90.ms),
        const SizedBox(height: 12),
        _SecondaryNutrientsCard(
          storageKey: 'micronutrients',
          title: loc.nutritionManualSectionMicronutrients,
          icon: Icons.eco_outlined,
          children: [
            _NutrientProgressRow(
              label: loc.nutritionProgressPotassium,
              consumed: values.potassiumMg,
              unit: 'mg',
              color: const Color(0xFF4E8D7C),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressCalcium,
              consumed: values.calciumMg,
              unit: 'mg',
              color: const Color(0xFF5C7AEA),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressIron,
              consumed: values.ironMg,
              unit: 'mg',
              color: const Color(0xFFB75D69),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressMagnesium,
              consumed: values.magnesiumMg,
              unit: 'mg',
              color: const Color(0xFF6D8299),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressZinc,
              consumed: values.zincMg,
              unit: 'mg',
              color: const Color(0xFF8F7A66),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressVitaminA,
              consumed: values.vitaminAUg,
              unit: 'µg',
              color: const Color(0xFFE38B29),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressVitaminC,
              consumed: values.vitaminCMg,
              unit: 'mg',
              color: const Color(0xFF6A994E),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressVitaminD,
              consumed: values.vitaminDUg,
              unit: 'µg',
              color: const Color(0xFFF2C14E),
            ),
            _NutrientProgressRow(
              label: loc.nutritionProgressVitaminB12,
              consumed: values.vitaminB12Ug,
              unit: 'µg',
              color: const Color(0xFF7B61A8),
              isLast: true,
            ),
          ],
        ).animate().fadeIn(duration: 320.ms, delay: 110.ms),
      ],
    );
  }
}

class _SecondaryNutrientsCard extends StatelessWidget {
  final String storageKey;
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SecondaryNutrientsCard({
    required this.storageKey,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(70)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('nutrition-$storageKey'),
        leading: Icon(icon, size: 20, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          AppLocalizations.of(context)!.nutritionTapForDetails,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: children,
      ),
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
                value: hasGoal ? _formatNutritionNumber(goal!) : '—',
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
                    ? '—'
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
              : '—',
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
  final String unit;
  final Color color;
  final bool isLast;

  const _NutrientProgressRow({
    required this.label,
    required this.consumed,
    required this.unit,
    required this.color,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = consumed != null;
    final current = consumed ?? 0;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                hasValue ? '${_formatNutritionNumber(current)}$unit' : '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
    super.key,
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
            Icon(Icons.add_rounded, size: 18, color: theme.colorScheme.primary),
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
