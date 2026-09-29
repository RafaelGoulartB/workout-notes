import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Bottom sheet result: a [RunPlanTemplate], or the string `'blank'`.
Future<Object?> showRunPlanTemplatePicker(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<Object?>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => RunPlanTemplatePickerSheet(loc: loc),
  );
}

class RunPlanTemplatePickerSheet extends StatefulWidget {
  final AppLocalizations loc;
  const RunPlanTemplatePickerSheet({super.key, required this.loc});

  @override
  State<RunPlanTemplatePickerSheet> createState() =>
      _RunPlanTemplatePickerSheetState();
}

class _RunPlanTemplatePickerSheetState
    extends State<RunPlanTemplatePickerSheet> {
  RunPlanTemplateCategory? _selected;

  String _categoryLabel(RunPlanTemplateCategory? value) => switch (value) {
    null => widget.loc.runPlanTemplateCategoryAll,
    RunPlanTemplateCategory.gettingStarted =>
      widget.loc.runPlanTemplateCategoryStart,
    RunPlanTemplateCategory.fiveK => widget.loc.runPlanGoal5k,
    RunPlanTemplateCategory.tenK => widget.loc.runPlanGoal10k,
    RunPlanTemplateCategory.half => widget.loc.runPlanGoalHalf,
    RunPlanTemplateCategory.marathon => widget.loc.runPlanGoalMarathon,
    RunPlanTemplateCategory.conditioning =>
      widget.loc.runPlanTemplateCategoryConditioning,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = RunPlanTemplates.all
        .where((item) => _selected == null || item.category == _selected)
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.route_rounded,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.loc.runPlanTemplatePickerTitle,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.loc.runPlanTemplatePickerSubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _PlanFinder(
                      loc: widget.loc,
                      onPick: (template) => Navigator.pop(context, template),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.loc.runPlanTemplateChooseGoal,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final category in <RunPlanTemplateCategory?>[
                            null,
                            ...RunPlanTemplateCategory.values,
                          ]) ...[
                            ChoiceChip(
                              label: Text(_categoryLabel(category)),
                              selected: _selected == category,
                              onSelected: (_) =>
                                  setState(() => _selected = category),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              sliver: SliverList.separated(
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _GoalTemplateCard(
                  option: options[index],
                  onTap: () => Navigator.pop(context, options[index]),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'blank'),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(widget.loc.runPlansBlank),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Not sure where to start?" — two questions that point a person at a plan
/// whose prerequisite they already meet, instead of leaving them to compare
/// twenty-odd templates.
class _PlanFinder extends StatefulWidget {
  final AppLocalizations loc;
  final ValueChanged<RunPlanTemplate> onPick;

  const _PlanFinder({required this.loc, required this.onPick});

  @override
  State<_PlanFinder> createState() => _PlanFinderState();
}

class _PlanFinderState extends State<_PlanFinder> {
  bool _open = false;
  RunPlanExperience? _experience;
  RunPlanAim? _aim;

  /// Nothing to ask about the goal of someone who does not run yet.
  bool get _needsAim =>
      _experience != null &&
      _experience != RunPlanExperience.none &&
      _experience != RunPlanExperience.fewMinutes;

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final suggestion = _experience == null || (_needsAim && _aim == null)
        ? null
        : RunPlanTemplates.recommend(_experience!, _aim ?? RunPlanAim.habit);
    Widget chips<T>(List<(T, String)> options, T? value, ValueChanged<T> set) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (option, label) in options)
              ChoiceChip(
                label: Text(label),
                selected: value == option,
                onSelected: (_) => setState(() => set(option)),
              ),
          ],
        );
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: Text(loc.runPlanFinderTitle),
              subtitle: Text(loc.runPlanFinderSubtitle),
              trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _open = !_open),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runPlanFinderRunQuestion,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    chips<RunPlanExperience>(
                      [
                        (RunPlanExperience.none, loc.runPlanFinderRunNone),
                        (
                          RunPlanExperience.fewMinutes,
                          loc.runPlanFinderRunShort,
                        ),
                        (
                          RunPlanExperience.thirtyMinutes,
                          loc.runPlanFinderRun20,
                        ),
                        (RunPlanExperience.fiveK, loc.runPlanFinderRun5k),
                        (RunPlanExperience.tenK, loc.runPlanFinderRun10k),
                        (RunPlanExperience.half, loc.runPlanFinderRunHalf),
                      ],
                      _experience,
                      (value) => _experience = value,
                    ),
                    if (_needsAim) ...[
                      const SizedBox(height: 16),
                      Text(
                        loc.runPlanFinderGoalQuestion,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      chips<RunPlanAim>(
                        [
                          (RunPlanAim.habit, loc.runPlanFinderGoalHabit),
                          (RunPlanAim.further, loc.runPlanFinderGoalFurther),
                          (RunPlanAim.faster, loc.runPlanFinderGoalFaster),
                        ],
                        _aim,
                        (value) => _aim = value,
                      ),
                    ],
                    if (suggestion != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        loc.runPlanFinderSuggestion,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _GoalTemplateCard(
                        option: suggestion,
                        onTap: () => widget.onPick(suggestion),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoalTemplateCard extends StatelessWidget {
  final RunPlanTemplate option;
  final VoidCallback onTap;
  const _GoalTemplateCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final pt = Localizations.localeOf(context).languageCode == 'pt';
    final kinds = <String>{
      for (final week in option.schedule)
        for (final session in week) RunPlanUi.kindLabel(loc, session.kind),
    };
    final icon = switch (option.category) {
      RunPlanTemplateCategory.gettingStarted => Icons.directions_walk_rounded,
      RunPlanTemplateCategory.fiveK => Icons.speed_rounded,
      RunPlanTemplateCategory.tenK => Icons.trending_up_rounded,
      RunPlanTemplateCategory.half => Icons.route_rounded,
      RunPlanTemplateCategory.marathon => Icons.flag_rounded,
      RunPlanTemplateCategory.conditioning => Icons.favorite_rounded,
    };
    final level = switch (option.level) {
      RunPlanTemplateLevel.beginner => loc.runPlanTemplateLevelBeginner,
      RunPlanTemplateLevel.intermediate => loc.runPlanTemplateLevelIntermediate,
      RunPlanTemplateLevel.advanced => loc.runPlanTemplateLevelAdvanced,
    };
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(100)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      size: 23,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title(pt),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${loc.runPlanWeeksValue(option.weeks)} · ${loc.runPlanTemplateSessions(option.sessionsPerWeek)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                option.description(pt),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _PlanTemplateTag(
                    icon: Icons.signal_cellular_alt_rounded,
                    label: level,
                  ),
                  for (final kind in kinds.take(3))
                    _PlanTemplateTag(label: kind),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        option.prerequisite(pt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
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

class _PlanTemplateTag extends StatelessWidget {
  final IconData? icon;
  final String label;
  const _PlanTemplateTag({this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withAlpha(130),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: scheme.onSecondaryContainer),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
