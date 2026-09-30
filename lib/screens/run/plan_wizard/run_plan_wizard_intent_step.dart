import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_controller.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_widgets.dart';
import 'package:workout_notes/services/run_plan_composer.dart';

/// Step 2: intent, intensity, terrain, strength/test toggles, current volume.
class RunPlanWizardIntentStep extends StatelessWidget {
  final RunPlanWizardController controller;

  const RunPlanWizardIntentStep({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = wizardMutedStyle(theme);
    final history = controller.history;
    final isMaintain = controller.isMaintain;
    final pbOnly = controller.pbOnly;
    final intensity = controller.intensity;
    final terrain = controller.terrain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunPlanWizardStepTitle(
          isMaintain
              ? loc.runPlanCustomizeMaintainTitle
              : loc.runPlanCustomizeIntentTitle,
          help: isMaintain || !pbOnly
              ? (isMaintain
                    ? loc.runPlanCustomizeMaintainHelp
                    : loc.runPlanCustomizeIntentHelp)
              : null,
        ),
        if (!isMaintain && !pbOnly && !controller.isRunWalk) ...[
          const SizedBox(height: 16),
          RunPlanWizardOptionCard(
            selected: controller.intent == RunPlanIntent.finish,
            title: loc.runPlanCustomizeIntentFinish,
            subtitle: loc.runPlanCustomizeIntentFinishHint,
            onTap: () => controller.setIntent(RunPlanIntent.finish),
          ),
          const SizedBox(height: 8),
          RunPlanWizardOptionCard(
            selected: controller.intent == RunPlanIntent.pb,
            title: loc.runPlanCustomizeIntentPb,
            subtitle: loc.runPlanCustomizeIntentPbHint,
            onTap: () => controller.setIntent(RunPlanIntent.pb),
          ),
        ],
        const SizedBox(height: 24),
        RunPlanWizardSubtitle(loc.runPlanCustomizeIntensity),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in RunPlanIntensity.values)
              ChoiceChip(
                label: Text(switch (value) {
                  RunPlanIntensity.conservative =>
                    loc.runPlanCustomizeIntensityConservative,
                  RunPlanIntensity.standard =>
                    loc.runPlanCustomizeIntensityStandard,
                  RunPlanIntensity.aggressive =>
                    loc.runPlanCustomizeIntensityAggressive,
                }),
                selected: intensity == value,
                onSelected: (_) => controller.setIntensity(value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(switch (intensity) {
          RunPlanIntensity.conservative =>
            loc.runPlanCustomizeIntensityConservativeHint,
          RunPlanIntensity.standard =>
            loc.runPlanCustomizeIntensityStandardHint,
          RunPlanIntensity.aggressive =>
            loc.runPlanCustomizeIntensityAggressiveHint,
        }, style: muted),
        if (controller.canHaveHills) ...[
          const SizedBox(height: 24),
          RunPlanWizardSubtitle(loc.runPlanCustomizeTerrainTitle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in RunPlanWizardTerrain.values)
                ChoiceChip(
                  avatar: Icon(switch (value) {
                    RunPlanWizardTerrain.hill => Icons.landscape_outlined,
                    RunPlanWizardTerrain.stairs => Icons.stairs_outlined,
                    RunPlanWizardTerrain.treadmill => Icons.directions_run,
                    RunPlanWizardTerrain.flat => Icons.horizontal_rule,
                  }, size: 18),
                  label: Text(switch (value) {
                    RunPlanWizardTerrain.hill =>
                      loc.runPlanCustomizeTerrainHill,
                    RunPlanWizardTerrain.stairs =>
                      loc.runPlanCustomizeTerrainStairs,
                    RunPlanWizardTerrain.treadmill =>
                      loc.runPlanCustomizeTerrainTreadmill,
                    RunPlanWizardTerrain.flat =>
                      loc.runPlanCustomizeTerrainFlat,
                  }),
                  selected: terrain == value,
                  onSelected: (_) => controller.setTerrain(value),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(switch (terrain) {
            RunPlanWizardTerrain.hill => loc.runPlanCustomizeTerrainHillHelp,
            RunPlanWizardTerrain.stairs =>
              loc.runPlanCustomizeTerrainStairsHelp,
            RunPlanWizardTerrain.treadmill =>
              loc.runPlanCustomizeTerrainTreadmillHelp,
            RunPlanWizardTerrain.flat => loc.runPlanCustomizeTerrainFlatHelp,
          }, style: muted),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fitness_center_rounded),
          title: Text(loc.runPlanCustomizeStrengthTitle),
          subtitle: Text(loc.runPlanCustomizeStrengthHelp),
          value: controller.includeStrength,
          onChanged: controller.setIncludeStrength,
        ),
        if (controller.offersTest)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.timer_outlined),
            title: Text(loc.runPlanCustomizeTestTitle),
            subtitle: Text(loc.runPlanCustomizeTestHelp),
            value: controller.includeTest,
            onChanged: controller.setIncludeTest,
          ),
        const SizedBox(height: 24),
        RunPlanWizardSubtitle(loc.runPlanCustomizeBaselineTitle),
        const SizedBox(height: 8),
        Text(
          isMaintain
              ? loc.runPlanCustomizeBaselineHelpMaintain
              : loc.runPlanCustomizeBaselineHelp,
          style: muted,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.weeklyKmCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: loc.runPlanCustomizeBaselineField,
            hintText: loc.runPlanCustomizeBaselineHint,
            suffixText: 'km',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => controller.markChanged(),
        ),
        if (history?.medianWeeklyKm != null &&
            history!.medianWeekCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            loc.runPlanCustomizeBaselineFromHistory(history.medianWeekCount),
            style: muted,
          ),
        ],
      ],
    );
  }
}
