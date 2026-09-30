import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/planning/periodization_home_screen.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Building blocks shared by the nutrition home and the day diary, so the
/// summary card, meal cards and food rows look the same on both.

/// Macro colors used by every nutrition surface.
abstract final class NutritionMacroColors {
  static const Color protein = Color(0xFFF29E38);
  static const Color carbs = Color(0xFF20A39E);
  static const Color fat = Color(0xFF8E44AD);
}

/// `12`, `12,5` (one decimal at most, locale separator, no grouping).
String nutritionNumber(double value) =>
    NumberFormat('0.#', Intl.defaultLocale).format(value);

/// Grams of a macro with its share of the daily [goal] as a thin bar.
Widget nutritionMacroStat(
  String label,
  double? value,
  double? goal,
  Color color,
) {
  final current = value ?? 0;
  final hasGoal = goal != null && goal > 0;
  return AppProgressStat(
    value: nutritionNumber(current),
    unit: 'g',
    label: label,
    progress: hasGoal ? current / goal : 0,
    color: color,
  );
}

/// The day's calories against the goal with the three macros underneath.
/// [onTap] makes the whole card open something (the diary, from the home).
class NutritionSummaryCard extends StatelessWidget {
  final DailyNutritionSummary summary;
  final NutritionGoal? goal;
  final EffectiveNutritionGoal? planInfo;
  final VoidCallback? onTap;
  final VoidCallback onConfigureGoal;
  final EdgeInsetsGeometry padding;

  const NutritionSummaryCard({
    super.key,
    required this.summary,
    required this.goal,
    this.planInfo,
    this.onTap,
    required this.onConfigureGoal,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 0),
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final calories = summary.consumed.calories ?? 0;
    final calorieGoal = goal?.calories;
    final hasGoal = calorieGoal != null && calorieGoal > 0;
    final ratio = hasGoal ? calories / calorieGoal : 0.0;
    final over = ratio > 1;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 20,
                color: colors.primary,
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
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                nutritionNumber(calories.roundToDouble()),
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
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (hasGoal)
                Text(
                  '${(ratio * 100).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: over ? colors.error : colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _goalLabel(loc, calories, calorieGoal),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (planInfo != null && planInfo!.fromPlan) ...[
            const SizedBox(height: 8),
            NutritionPlanGoalBadge(planInfo: planInfo!),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: hasGoal ? ratio.clamp(0.0, 1.0) : 0,
              minHeight: 8,
              backgroundColor: hasGoal
                  ? colors.surfaceContainerHighest
                  : colors.surfaceContainerHighest.withAlpha(180),
              color: over ? colors.error : colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          AppStatRow(
            divider: const AppStatDivider(),
            children: [
              nutritionMacroStat(
                loc.nutritionProgressProtein,
                summary.consumed.proteinG,
                goal?.proteinG,
                NutritionMacroColors.protein,
              ),
              nutritionMacroStat(
                loc.nutritionProgressCarbs,
                summary.consumed.carbsG,
                goal?.carbsG,
                NutritionMacroColors.carbs,
              ),
              nutritionMacroStat(
                loc.nutritionProgressFat,
                summary.consumed.fatG,
                goal?.fatG,
                NutritionMacroColors.fat,
              ),
            ],
          ),
          if (!hasGoal) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: colors.outlineVariant.withAlpha(60)),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onConfigureGoal,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        loc.nutritionHomeConfigureGoalPrompt,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      loc.nutritionConfigureGoal,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.primary,
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
    );

    return Padding(
      padding: padding,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                colors.surfaceContainerHighest.withAlpha(200),
                colors.surfaceContainerLow,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: onTap == null
              ? content
              : InkWell(onTap: onTap, child: content),
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
    final remaining = (goal - calories).roundToDouble();
    return remaining >= 0
        ? loc.nutritionGoalRemaining(nutritionNumber(remaining))
        : loc.nutritionGoalSurplus(nutritionNumber(-remaining));
  }
}

/// Chip shown when an active plan's current week overrides the settings
/// goal. Tapping opens the periodization home.
class NutritionPlanGoalBadge extends StatelessWidget {
  final EffectiveNutritionGoal planInfo;

  const NutritionPlanGoalBadge({super.key, required this.planInfo});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final phase = planInfo.phase!;
    final color = Color(phase.color);
    final badge = loc.nutritionGoalPlanBadge(
      phase.name,
      planInfo.weekNumber ?? 1,
      planInfo.totalWeeks ?? 1,
    );
    // Phases with rest-day nutrition say which target the day uses.
    final label = switch (planInfo.trainingDay) {
      true => '$badge · ${loc.planningTrainingDayShort}',
      false => '$badge · ${loc.planningRestDayShort}',
      null => badge,
    };
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

/// Letter-spaced section label ("TODAY") with an optional value and count.
class NutritionSectionLabel extends StatelessWidget {
  final String title;
  final int count;
  final String? value;
  final EdgeInsetsGeometry padding;

  const NutritionSectionLabel({
    super.key,
    required this.title,
    this.count = 0,
    this.value,
    this.padding = const EdgeInsets.fromLTRB(20, 30, 20, 4),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
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
          if (count > 0)
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
        ],
      ),
    );
  }
}

/// One meal: icon, name, calories and item count, a round + button and the
/// logged foods underneath. [detailed] (the diary) adds the macro split of
/// the meal and of each food; [menu] adds a trailing overflow menu.
class NutritionMealCard extends StatelessWidget {
  final String title;
  final MealLogWithItems meal;
  final VoidCallback? onOpen;
  final VoidCallback onAdd;
  final ValueChanged<MealLogItem> onEditItem;
  final String emptyLabel;
  final bool detailed;
  final Widget? menu;

  /// Prefix of the row, add button and food keys (`<prefix>-meal-<type>`).
  final String keyPrefix;

  const NutritionMealCard({
    super.key,
    required this.title,
    required this.meal,
    this.onOpen,
    required this.onAdd,
    required this.onEditItem,
    required this.emptyLabel,
    this.detailed = false,
    this.menu,
    this.keyPrefix = 'nutrition-home',
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    double total(double? Function(MealLogItem) of) =>
        meal.items.fold<double>(0, (sum, item) => sum + (of(item) ?? 0));
    final kcal = total((i) => i.calories);
    final itemCount = meal.items.length;
    final hasItems = itemCount > 0;
    final type = meal.log.mealType;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: ValueKey('$keyPrefix-meal-$type'),
              onTap: onOpen,
              child: Padding(
                padding: EdgeInsets.fromLTRB(14, 12, menu == null ? 10 : 2, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: hasItems
                            ? colors.primaryContainer.withAlpha(140)
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        hasItems ? Icons.restaurant_rounded : Icons.add_rounded,
                        color: hasItems
                            ? colors.primary
                            : colors.onSurfaceVariant,
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
                                ? '${nutritionNumber(kcal.roundToDouble())} kcal · ${loc.nutritionItemCount(itemCount)}'
                                : emptyLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (detailed && hasItems) ...[
                            const SizedBox(height: 6),
                            NutritionMacroLine(
                              proteinG: total((i) => i.proteinG),
                              carbsG: total((i) => i.carbsG),
                              fatG: total((i) => i.fatG),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: ValueKey('$keyPrefix-add-$type'),
                      tooltip: loc.nutritionAddItem,
                      onPressed: onAdd,
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary.withAlpha(
                          hasItems ? 18 : 28,
                        ),
                      ),
                      icon: Icon(
                        Icons.add_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                    ?menu,
                  ],
                ),
              ),
            ),
            if (hasItems) ...[
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: colors.outlineVariant.withAlpha(70),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in meal.items.asMap().entries) ...[
                      NutritionFoodRow(
                        tapKey: ValueKey('$keyPrefix-food-${entry.value.id}'),
                        item: entry.value,
                        detailed: detailed,
                        onTap: () => onEditItem(entry.value),
                      ),
                      if (entry.key < meal.items.length - 1)
                        Divider(
                          height: 1,
                          color: colors.outlineVariant.withAlpha(55),
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
}

/// One logged food: name, quantity (and brand / macros when [detailed]) and
/// its calories. Tapping opens the quantity sheet.
class NutritionFoodRow extends StatelessWidget {
  final MealLogItem item;
  final VoidCallback onTap;
  final bool detailed;
  final Key? tapKey;

  const NutritionFoodRow({
    super.key,
    this.tapKey,
    required this.item,
    required this.onTap,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = item.unit.trim();
    final quantity = nutritionNumber(item.quantity);
    final brand = item.brandSnapshot?.trim();
    final details = [
      unit.isEmpty ? quantity : '$quantity $unit',
      if (detailed && brand != null && brand.isNotEmpty) brand,
    ].join(' · ');
    final calories = item.calories;
    return InkWell(
      key: tapKey,
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
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (detailed) ...[
              const SizedBox(width: 10),
              NutritionMacroLine(
                proteinG: item.proteinG ?? 0,
                carbsG: item.carbsG ?? 0,
                fatG: item.fatG ?? 0,
                compact: true,
              ),
            ],
            if (calories != null) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 54),
                child: Text(
                  '${nutritionNumber(calories.roundToDouble())} kcal',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `● P 29  ● C 34  ● G 24` with the macro colors. [compact] drops the
/// letters' spacing for use inside a food row.
class NutritionMacroLine extends StatelessWidget {
  final double proteinG;
  final double carbsG;
  final double fatG;
  final bool compact;

  const NutritionMacroLine({
    super.key,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget macro(String label, double grams, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          compact
              ? nutritionNumber(grams.roundToDouble())
              : '${label.characters.first} ${nutritionNumber(grams)} g',
          style: style,
        ),
      ],
    );
    return Wrap(
      spacing: compact ? 7 : 12,
      runSpacing: 4,
      children: [
        macro(
          loc.nutritionProgressProtein,
          proteinG,
          NutritionMacroColors.protein,
        ),
        macro(loc.nutritionProgressCarbs, carbsG, NutritionMacroColors.carbs),
        macro(loc.nutritionProgressFat, fatG, NutritionMacroColors.fat),
      ],
    );
  }
}
