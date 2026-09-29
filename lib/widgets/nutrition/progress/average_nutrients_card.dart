import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/widgets/nutrition/progress/progress_shared.dart';
import 'package:workout_notes/models/nutrition/nutrition_progress.dart';

class AverageNutrientsCard extends StatelessWidget {
  final bool expanded;
  final bool loading;
  final bool loadFailed;
  final NutrientAverages? averages;
  final NutritionGoal? goal;
  final ValueChanged<bool> onExpansionChanged;

  const AverageNutrientsCard({
    super.key,
    required this.expanded,
    required this.loading,
    required this.loadFailed,
    required this.averages,
    required this.goal,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('balance-average-nutrients-tile'),
        initiallyExpanded: expanded,
        onExpansionChanged: onExpansionChanged,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.table_rows_rounded,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          loc.nutritionBalanceAverageNutrients,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          loc.nutritionBalanceAverageNutrientsSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: EdgeInsets.zero,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (loadFailed)
            ProgressEmptyNote(text: loc.nutritionBalanceAverageNutrientsError)
          else if (averages == null || averages!.daysLogged == 0)
            ProgressEmptyNote(text: loc.nutritionBalanceAverageNutrientsEmpty)
          else
            AverageNutrientTable(values: averages!.values, goal: goal),
        ],
      ),
    );
  }
}

class AverageNutrientTable extends StatelessWidget {
  final NutritionValues values;
  final NutritionGoal? goal;

  const AverageNutrientTable({
    super.key,
    required this.values,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final calorieGoal = goal?.calories;
    final hasCalorieGoal = calorieGoal != null && calorieGoal > 0;
    return Column(
      children: [
        const AverageNutrientHeader(),
        AverageNutrientRow(
          label: loc.nutritionProgressFiber,
          consumed: values.fiberG,
          goal: 25,
          unit: 'g',
          color: const Color(0xFF43A66A),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressSugars,
          consumed: values.sugarsG,
          goal: hasCalorieGoal ? calorieGoal * 0.10 / 4 : null,
          unit: 'g',
          color: const Color(0xFFD85F8A),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressSodium,
          consumed: values.sodiumMg,
          goal: 2300,
          unit: 'mg',
          color: const Color(0xFF3A9FCC),
        ),
        AverageNutrientGroup(title: loc.nutritionFatBreakdownTitle),
        AverageNutrientRow(
          label: _stripUnit(loc.nutritionFatSaturated),
          consumed: values.saturatedFatG,
          goal: hasCalorieGoal ? calorieGoal * 0.10 / 9 : null,
          unit: 'g',
          color: const Color(0xFFA95C68),
        ),
        AverageNutrientRow(
          label: _stripUnit(loc.nutritionFatPolyunsaturated),
          consumed: values.polyunsaturatedFatG,
          unit: 'g',
          color: const Color(0xFF658B6F),
        ),
        AverageNutrientRow(
          label: _stripUnit(loc.nutritionFatMonounsaturated),
          consumed: values.monounsaturatedFatG,
          unit: 'g',
          color: const Color(0xFFB58B3C),
        ),
        AverageNutrientRow(
          label: _stripUnit(loc.nutritionFatTrans),
          consumed: values.transFatG,
          unit: 'g',
          color: const Color(0xFF9A6B73),
        ),
        AverageNutrientGroup(title: loc.nutritionNutrientMineralsTitle),
        AverageNutrientRow(
          label: loc.nutritionProgressPotassium,
          consumed: values.potassiumMg,
          goal: 3500,
          unit: 'mg',
          color: const Color(0xFF4E8D7C),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressCalcium,
          consumed: values.calciumMg,
          goal: 1000,
          unit: 'mg',
          color: const Color(0xFF5C7AEA),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressIron,
          consumed: values.ironMg,
          goal: 14,
          unit: 'mg',
          color: const Color(0xFFB75D69),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressMagnesium,
          consumed: values.magnesiumMg,
          goal: 260,
          unit: 'mg',
          color: const Color(0xFF6D8299),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressZinc,
          consumed: values.zincMg,
          goal: 11,
          unit: 'mg',
          color: const Color(0xFF8F7A66),
        ),
        AverageNutrientGroup(title: loc.nutritionNutrientVitaminsTitle),
        AverageNutrientRow(
          label: loc.nutritionProgressVitaminA,
          consumed: values.vitaminAUg,
          goal: 800,
          unit: '\u00B5g',
          color: const Color(0xFFE38B29),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressVitaminC,
          consumed: values.vitaminCMg,
          goal: 100,
          unit: 'mg',
          color: const Color(0xFF6A994E),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressVitaminD,
          consumed: values.vitaminDUg,
          goal: 15,
          unit: '\u00B5g',
          color: const Color(0xFFF2C14E),
        ),
        AverageNutrientRow(
          label: loc.nutritionProgressVitaminB12,
          consumed: values.vitaminB12Ug,
          goal: 2.4,
          unit: '\u00B5g',
          color: const Color(0xFF7B61A8),
        ),
      ],
    );
  }
}

class AverageNutrientHeader extends StatelessWidget {
  const AverageNutrientHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            const Expanded(flex: 5, child: SizedBox.shrink()),
            AverageHeaderCell(label: loc.nutritionNutrientConsumedHeader),
            AverageHeaderCell(label: loc.nutritionNutrientGoalHeader),
            AverageHeaderCell(label: loc.nutritionNutrientRemainingHeader),
          ],
        ),
      ),
    );
  }
}

class AverageHeaderCell extends StatelessWidget {
  final String label;

  const AverageHeaderCell({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 3,
    child: Text(
      label,
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class AverageNutrientGroup extends StatelessWidget {
  final String title;

  const AverageNutrientGroup({super.key, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 20, 12, 7),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class AverageNutrientRow extends StatelessWidget {
  final String label;
  final double? consumed;
  final double? goal;
  final String unit;
  final Color color;

  const AverageNutrientRow({
    super.key,
    required this.label,
    required this.consumed,
    this.goal,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = consumed ?? 0;
    final hasGoal = goal != null && goal! > 0;
    final remaining = hasGoal ? goal! - current : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 13, 12, 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(90),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AverageNutrientValue(value: current, unit: unit),
              AverageNutrientValue(value: goal, unit: unit),
              AverageNutrientValue(value: remaining, unit: unit),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: hasGoal ? (current / goal!).clamp(0.0, 1.0) : 0,
              minHeight: 4,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class AverageNutrientValue extends StatelessWidget {
  final double? value;
  final String unit;

  const AverageNutrientValue({
    super.key,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 3,
    child: Text(
      value == null ? '—' : '${formatNutrient(value!)}$unit',
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String formatNutrient(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _stripUnit(String label) =>
    label.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
