import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/widgets/nutrition/progress/progress_shared.dart';
import 'package:workout_notes/models/nutrition/nutrition_progress.dart';
import 'package:workout_notes/widgets/nutrition/progress/average_nutrients_card.dart';

class MacroBalanceCard extends StatelessWidget {
  final MacroSummary? summary;
  final NutritionGoal? goal;

  const MacroBalanceCard({
    super.key,
    required this.summary,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final data = summary;
    if (data == null || data.totalKcal == 0) {
      return ProgressSectionCard(
        icon: Icons.pie_chart_outline_rounded,
        iconColor: theme.colorScheme.primary,
        title: loc.nutritionBalanceMacros,
        child: ProgressEmptyNote(text: loc.nutritionBalanceMacrosEmpty),
      );
    }
    final proteinKcal = data.proteinG * 4;
    final carbsKcal = data.carbsG * 4;
    final fatKcal = data.fatG * 9;
    final proteinPct = proteinKcal / data.totalKcal * 100;
    final carbsPct = carbsKcal / data.totalKcal * 100;
    final fatPct = fatKcal / data.totalKcal * 100;
    return ProgressSectionCard(
      icon: Icons.pie_chart_outline_rounded,
      iconColor: theme.colorScheme.primary,
      title: loc.nutritionBalanceMacros,
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: MacroDonut(
              proteinPct: proteinPct,
              carbsPct: carbsPct,
              fatPct: fatPct,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                MacroLegendRow(
                  label: loc.nutritionProgressProtein,
                  percent: proteinPct,
                  grams: data.proteinG,
                  goalG: goal?.proteinG,
                  color: const Color(0xFFF29E38),
                ),
                const SizedBox(height: 10),
                MacroLegendRow(
                  label: loc.nutritionProgressCarbs,
                  percent: carbsPct,
                  grams: data.carbsG,
                  goalG: goal?.carbsG,
                  color: const Color(0xFF20A39E),
                ),
                const SizedBox(height: 10),
                MacroLegendRow(
                  label: loc.nutritionProgressFat,
                  percent: fatPct,
                  grams: data.fatG,
                  goalG: goal?.fatG,
                  color: const Color(0xFF8E44AD),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MacroDonut extends StatelessWidget {
  final double proteinPct;
  final double carbsPct;
  final double fatPct;

  const MacroDonut({
    super.key,
    required this.proteinPct,
    required this.carbsPct,
    required this.fatPct,
  });

  @override
  Widget build(BuildContext context) => PieChart(
    PieChartData(
      sectionsSpace: 2,
      centerSpaceRadius: 32,
      startDegreeOffset: -90,
      sections: [
        PieChartSectionData(
          value: proteinPct,
          color: const Color(0xFFF29E38),
          radius: 22,
          showTitle: false,
        ),
        PieChartSectionData(
          value: carbsPct,
          color: const Color(0xFF20A39E),
          radius: 22,
          showTitle: false,
        ),
        PieChartSectionData(
          value: fatPct,
          color: const Color(0xFF8E44AD),
          radius: 22,
          showTitle: false,
        ),
      ],
    ),
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
  );
}

class MacroLegendRow extends StatelessWidget {
  final String label;
  final double percent;
  final double grams;
  final double? goalG;
  final Color color;

  const MacroLegendRow({
    super.key,
    required this.label,
    required this.percent,
    required this.grams,
    required this.goalG,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGoal = goalG != null && goalG! > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${percent.round()}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hasGoal
              ? '${formatNutrient(grams)} / ${formatNutrient(goalG!)} g'
              : '${formatNutrient(grams)} g',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (hasGoal) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (grams / goalG!).clamp(0.0, 1.0),
              minHeight: 4,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ],
    );
  }
}
