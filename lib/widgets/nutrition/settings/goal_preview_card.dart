import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/planning/periodization_home_screen.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Compact summary card showing the calorie headline + macro split bars.
/// Replaces the previous full-size preview block so the screen starts
/// with a single dense overview instead of two stacked cards.
class GoalPreviewCard extends StatelessWidget {
  final String? label;
  final double? calories;
  final double? tdee;
  final double? adjustmentPercent;
  final String? adjustmentKind;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  const GoalPreviewCard({
    super.key,
    this.label,
    this.calories,
    this.tdee,
    this.adjustmentPercent,
    this.adjustmentKind,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final proteinKcal = (proteinG ?? 0) * 4;
    final carbsKcal = (carbsG ?? 0) * 4;
    final fatKcal = (fatG ?? 0) * 9;
    final macroTotal = proteinKcal + carbsKcal + fatKcal;
    final headline = calories ?? (macroTotal > 0 ? macroTotal : null);
    final hasAny =
        headline != null || proteinG != null || carbsG != null || fatG != null;

    if (!hasAny) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.pie_chart_outline_rounded,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.nutritionSettingsEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AppSectionCard(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pie_chart_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  label ?? loc.nutritionSettingsPreviewLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (headline != null) ...[
              Text(
                loc.nutritionPreviewGoal(_formatNum(headline)),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
            ],
            if (tdee != null)
              Text(
                loc.nutritionPreviewTdee(_formatNum(tdee!)),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (tdee != null && adjustmentPercent != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _relationshipLabel(loc),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (macroTotal > 0) ...[
              const SizedBox(height: 12),
              MacroBar(
                label: loc.nutritionProgressProtein,
                value: proteinKcal,
                total: macroTotal,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: 6),
              MacroBar(
                label: loc.nutritionProgressCarbs,
                value: carbsKcal,
                total: macroTotal,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(height: 6),
              MacroBar(
                label: loc.nutritionProgressFat,
                value: fatKcal,
                total: macroTotal,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _relationshipLabel(AppLocalizations loc) {
    final kind = NutritionObjective.values.firstWhere(
      (o) => o.name == adjustmentKind,
      orElse: () => NutritionObjective.maintenance,
    );
    final kindLabel = _kindLabel(loc, kind);
    final percent = adjustmentPercent!;
    final signed = percent == 0
        ? '0%'
        : (percent > 0 ? '+${percent.round()}%' : '${percent.round()}%');
    return loc.nutritionPreviewRelationship(kindLabel, signed);
  }

  static String _kindLabel(AppLocalizations loc, NutritionObjective kind) {
    switch (kind) {
      case NutritionObjective.cut:
        return loc.nutritionSuggestObjectiveCut;
      case NutritionObjective.maintenance:
        return loc.nutritionSuggestObjectiveMaintenance;
      case NutritionObjective.bulk:
        return loc.nutritionSuggestObjectiveBulk;
    }
  }

  static String _formatNum(double value) {
    if (value == value.roundToDouble()) {
      return AppNumberFormat.decimal(value, 0);
    }
    return AppNumberFormat.decimal(value, 1);
  }
}

class MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;

  const MacroBar({
    super.key,
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total > 0
        ? (value / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percent = total > 0 ? '${((value / total) * 100).round()}%' : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              percent,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            backgroundColor: color.withAlpha(40),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// Banner shown when an active periodization plan's current week is
/// overriding the goal configured here. Tapping opens the plan.
class PlanOverrideBanner extends StatelessWidget {
  final EffectiveNutritionGoal planInfo;

  const PlanOverrideBanner({super.key, required this.planInfo});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final phase = planInfo.phase!;
    final color = Color(phase.color);
    String formatGoal(double? value) {
      if (value == null) return '—';
      return value == value.roundToDouble()
          ? AppNumberFormat.decimal(value, 0)
          : AppNumberFormat.decimal(value, 1);
    }

    return Material(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PeriodizationHomeScreen(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.event_note_rounded, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.nutritionSettingsPlanOverrideBanner(
                        phase.name,
                        planInfo.weekNumber ?? 1,
                        planInfo.totalWeeks ?? 1,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (planInfo.goal != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        loc.nutritionSettingsPlanCurrentTarget(
                          formatGoal(planInfo.goal!.calories),
                          formatGoal(planInfo.goal!.proteinG),
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
