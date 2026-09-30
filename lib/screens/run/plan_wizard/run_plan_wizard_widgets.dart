import 'package:flutter/material.dart';

import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Whole kilometres for the coach copy ("peak 42 km").
String wizardKm(double value) => RunFormatters.decimal(value, 0);

String wizardDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date);

TextStyle? wizardMutedStyle(ThemeData theme) => theme.textTheme.bodySmall
    ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

/// Big step title with an optional help paragraph under it.
class RunPlanWizardStepTitle extends StatelessWidget {
  final String title;
  final String? help;

  const RunPlanWizardStepTitle(this.title, {super.key, this.help});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (help != null) ...[
          const SizedBox(height: 8),
          Text(
            help!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Small section label inside a step (`titleSmall`).
class RunPlanWizardSubtitle extends StatelessWidget {
  final String text;

  const RunPlanWizardSubtitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

/// Colour-coded verdict on the goal time.
class RunPlanWizardGoalFeedback extends StatelessWidget {
  final RunPlanGoalAssessment assessment;
  final String message;

  const RunPlanWizardGoalFeedback({
    super.key,
    required this.assessment,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (assessment) {
      RunPlanGoalAssessment.realistic => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      RunPlanGoalAssessment.ambitious => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.trending_up,
      ),
      RunPlanGoalAssessment.unrealistic => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning_amber_rounded,
      ),
      RunPlanGoalAssessment.none => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.flag_outlined,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Radio-style card for a two-way choice ("finish" vs "personal best").
class RunPlanWizardOptionCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const RunPlanWizardOptionCard({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppUi.tileRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle, style: wizardMutedStyle(theme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
