import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/widgets/periodization/phase_editor/phase_editor_fields.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class PhaseNutritionCard extends StatelessWidget {
  final PhaseEditorController controller;
  final ValueChanged<String> onSnack;

  const PhaseNutritionCard({
    super.key,
    required this.controller,
    required this.onSnack,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tdee = controller.tdee;
    final kcal = controller.calories;
    final weight = controller.latestWeightKg;
    String? perKg(double? grams) => grams == null || weight == null
        ? null
        : loc.planningGramsPerKg(AppNumberFormat.decimal(grams / weight, 1));
    final tdeeHint = tdee == null || kcal == null
        ? null
        : loc.planningVsTdee(
            planningKcal(tdee),
            _signedPercent((kcal / tdee - 1) * 100),
          );
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.restEnabled
                      ? loc.planningTrainingDay
                      : loc.planningEveryDay,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  if (!controller.suggestNutrition()) {
                    onSnack(loc.planningSuggestNeedsTdee);
                  }
                },
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(loc.planningSuggest),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PhaseNumberField(
            key: const Key('phaseCalories'),
            controller: controller.caloriesText,
            label: loc.planningCaloriesPerDay,
            suffix: 'kcal',
            helper: tdeeHint,
            onChanged: controller.touch,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PhaseNumberField(
                  key: const Key('phaseProtein'),
                  controller: controller.proteinText,
                  label: loc.planningProtein,
                  suffix: 'g',
                  helper: perKg(controller.proteinG),
                  onChanged: controller.touch,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PhaseNumberField(
                  key: const Key('phaseFat'),
                  controller: controller.fatText,
                  label: loc.planningFat,
                  suffix: 'g',
                  helper: perKg(controller.fatG),
                  onChanged: controller.touch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PhaseCarbsLine(carbs: controller.carbsG),
          if (controller.macroConflict) ...[
            const SizedBox(height: 8),
            AppBanner.warning(loc.planningMacroConflict),
          ],
          const Divider(height: 28),
          SwitchListTile(
            key: const Key('phaseRestToggle'),
            contentPadding: EdgeInsets.zero,
            value: controller.restEnabled,
            onChanged: controller.setRestEnabled,
            title: Text(
              loc.planningRestDayDifferent,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(loc.planningRestDayHint),
          ),
          if (controller.restEnabled) ...[
            const SizedBox(height: 4),
            PhaseNumberField(
              key: const Key('phaseRestCalories'),
              controller: controller.restCaloriesText,
              label: loc.planningRestCalories,
              suffix: 'kcal',
              helper: kcal == null || controller.restCalories == null
                  ? null
                  : loc.planningRestDelta(
                      _signed(controller.restCalories! - kcal),
                    ),
              onChanged: controller.touch,
            ),
            const SizedBox(height: 10),
            PhaseCarbsLine(carbs: controller.restCarbsG),
            if (controller.strengthDays.isEmpty &&
                controller.runPlan == null &&
                controller.runDays.isEmpty) ...[
              const SizedBox(height: 8),
              AppBanner.warning(loc.planningRestNeedsDays),
            ],
          ],
          if (tdee == null) ...[
            const SizedBox(height: 8),
            Text(
              loc.planningNoTdeeHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _signed(double value) =>
      '${value > 0
          ? '+'
          : value < 0
          ? '−'
          : ''}${value.abs().round()}';

  static String _signedPercent(double value) =>
      '${value > 0
          ? '+'
          : value < 0
          ? '−'
          : ''}${value.abs().round()}%';
}

class PhaseCarbsLine extends StatelessWidget {
  final double? carbs;

  const PhaseCarbsLine({super.key, required this.carbs});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.grain_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            loc.planningCarbsRemaining(
              carbs == null ? '—' : '${carbs!.round()} g',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

