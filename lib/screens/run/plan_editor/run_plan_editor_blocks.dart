import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Shown instead of the step list while a session has no steps.
class RunPlanEditorStepsEmpty extends StatelessWidget {
  const RunPlanEditorStepsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(70),
        ),
      ),
      child: Column(
        children: [
          Text(loc.runWorkoutStepsEmpty, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            loc.runWorkoutStepsEmptySubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One step, or one repeated block drawn as a bracket. Before this, `8x 400 m`
/// and `8x 1:30` sat in two separate rows and read as sixteen efforts.
class RunPlanEditorBlockTile extends StatelessWidget {
  final int index;
  final RunStepBlock block;
  final ValueChanged<RunWorkoutStep> onEditStep;
  final ValueChanged<RunWorkoutStep> onDeleteStep;
  final VoidCallback onDeleteBlock;

  const RunPlanEditorBlockTile({
    super.key,
    required this.index,
    required this.block,
    required this.onEditStep,
    required this.onDeleteStep,
    required this.onDeleteBlock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final accent = RunPlanUi.roleColor(scheme, block.steps.first.role);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 12,
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (block.isRepeat) ...[
                const SizedBox(width: 4),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    loc.runWorkoutBlockRepeats(block.repeats),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 4),
              Expanded(
                child: Column(
                  children: [
                    for (final step in block.steps)
                      _StepRow(
                        step: step,
                        onTap: () => onEditStep(step),
                        // Inside a repeat block the trash sits on the block, so
                        // "delete" always means the whole `6x` unit.
                        onDelete: block.isRepeat
                            ? null
                            : () => onDeleteStep(step),
                      ),
                  ],
                ),
              ),
              if (block.isRepeat)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: loc.runPlanEditorBlockDelete,
                  onPressed: onDeleteBlock,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final RunWorkoutStep step;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _StepRow({required this.step, required this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final color = RunPlanUi.roleColor(theme.colorScheme, step.role);
    final pace = RunPlanUi.paceRangeLabel(
      step.targetPaceMinSecPerKm,
      step.targetPaceMaxSecPerKm,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 26,
              decoration: BoxDecoration(
                color: color.withAlpha(step.role.isEffort ? 235 : 110),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    RunPlanUi.stepAmountLabel(step),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      RunPlanUi.roleLabel(loc, step.role),
                      if (pace != null) '$pace/km',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: loc.runWorkoutStepDelete,
                onPressed: onDelete,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
