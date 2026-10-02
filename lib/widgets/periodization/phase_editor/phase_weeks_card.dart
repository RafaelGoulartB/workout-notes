import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';

class PhaseWeeksCard extends StatelessWidget {
  final PhaseEditorController controller;

  const PhaseWeeksCard({super.key, required this.controller});

  Future<void> _openWeek(BuildContext context, int week) async {
    final result = await showModalBottomSheet<PhaseWeekSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => PhaseWeekSheet(controller: controller, week: week),
    );
    if (result == null) return;
    controller.setAdjustment(week, result.adjustment);
    if (result.applyToFollowing) controller.applyAdjustmentToFollowing(week);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final base = controller.buildBase();
    return PlanningCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              loc.planningWeeksHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var week = 0; week < controller.weeks; week++)
            PhaseWeekRow(
              key: Key('phaseWeek$week'),
              week: week,
              controller: controller,
              base: base,
              onTap: controller.isLocked(week)
                  ? null
                  : () => _openWeek(context, week),
            ),
        ],
      ),
    );
  }
}

class PhaseWeekRow extends StatelessWidget {
  final int week;
  final PhaseEditorController controller;
  final PeriodizationTarget base;
  final VoidCallback? onTap;

  const PhaseWeekRow({
    super.key,
    required this.week,
    required this.controller,
    required this.base,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = controller.targetForWeek(week, base: base);
    final start = controller.weekStart(week);
    final locked = controller.isLocked(week);
    final current = controller.currentWeek == week;
    final adjusted = controller.adjustments[week]?.changesTargets ?? false;
    final label = locked
        ? target?.weekLabel
        : controller.adjustments[week]?.label;
    final kcal = target?.calories;
    final rest = target?.restCalories;
    final accent = Color(controller.color);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: current
                    ? accent
                    : locked
                    ? scheme.surfaceContainerHighest.withAlpha(90)
                    : accent.withAlpha(36),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${week + 1}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: current
                      ? scheme.surface
                      : locked
                      ? scheme.onSurfaceVariant
                      : accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          planningDateRange(
                            start,
                            addDays(start, 6),
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (label != null && label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        PlanningPill(
                          icon: Icons.label_outline_rounded,
                          label: label,
                          color: accent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kcal == null
                        ? loc.planningNoNutritionTarget
                        : rest == null
                        ? '${planningKcal(kcal)} kcal'
                        : loc.planningKcalTrainingRest(
                            planningKcal(kcal),
                            planningKcal(rest),
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: adjusted ? accent : scheme.onSurfaceVariant,
                      fontWeight: adjusted ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              )
            else if (current)
              Text(
                loc.planningThisWeek,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              Icon(
                adjusted ? Icons.tune_rounded : Icons.chevron_right_rounded,
                size: 20,
                color: adjusted ? accent : scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class PhaseWeekSheetResult {
  final WeekAdjustment adjustment;
  final bool applyToFollowing;

  const PhaseWeekSheetResult(this.adjustment, {this.applyToFollowing = false});
}

class PhaseWeekSheet extends StatefulWidget {
  final PhaseEditorController controller;
  final int week;

  const PhaseWeekSheet({
    super.key,
    required this.controller,
    required this.week,
  });

  @override
  State<PhaseWeekSheet> createState() => _PhaseWeekSheetState();
}

class _PhaseWeekSheetState extends State<PhaseWeekSheet> {
  late final WeekAdjustment? _initial =
      widget.controller.adjustments[widget.week];
  late final _label = TextEditingController(text: _initial?.label ?? '');
  late final _calories = TextEditingController(
    text: _initial?.calories?.round().toString() ?? '',
  );
  late final _rest = TextEditingController(
    text: _initial?.restCalories?.round().toString() ?? '',
  );
  bool _applyFollowing = false;

  @override
  void dispose() {
    _label.dispose();
    _calories.dispose();
    _rest.dispose();
    super.dispose();
  }

  double? _parse(String raw) {
    final value = double.tryParse(raw.trim());
    return value == null || value <= 0 ? null : value;
  }

  WeekAdjustment get _current => WeekAdjustment(
    label: _label.text.trim().isEmpty ? null : _label.text.trim(),
    calories: _parse(_calories.text),
    restCalories: widget.controller.restEnabled ? _parse(_rest.text) : null,
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = widget.controller;
    final start = controller.weekStart(widget.week);
    final base = controller.buildBase();
    final presets = [
      loc.planningWeekLabelDeload,
      loc.planningWeekLabelRefeed,
      loc.planningWeekLabelDietBreak,
      loc.planningWeekLabelTest,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.planningWeekTitle(
                widget.week + 1,
                planningDateRange(start, addDays(start, 6)),
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.planningWeekSheetHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in presets)
                  ChoiceChip(
                    label: Text(preset),
                    selected: _label.text.trim() == preset,
                    onSelected: (selected) =>
                        setState(() => _label.text = selected ? preset : ''),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.planningWeekLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('weekSheetCalories'),
              controller: _calories,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: controller.restEnabled
                    ? loc.planningTrainingDayCalories
                    : loc.planningCaloriesPerDay,
                hintText: planningKcal(base.calories),
                helperText: loc.planningWeekKcalHelper(
                  planningKcal(base.calories),
                ),
                suffixText: 'kcal',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (controller.restEnabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _rest,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: loc.planningRestCalories,
                  hintText: planningKcal(base.restCalories),
                  helperText: loc.planningWeekKcalHelper(
                    planningKcal(base.restCalories),
                  ),
                  suffixText: 'kcal',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (widget.week < controller.weeks - 1)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _applyFollowing,
                onChanged: (value) =>
                    setState(() => _applyFollowing = value ?? false),
                title: Text(loc.planningApplyToFollowing),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_initial != null)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      PhaseWeekSheetResult(
                        const WeekAdjustment(),
                        applyToFollowing: _applyFollowing,
                      ),
                    ),
                    child: Text(loc.planningResetWeek),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('weekSheetApply'),
                  onPressed: () => Navigator.pop(
                    context,
                    PhaseWeekSheetResult(
                      _current,
                      applyToFollowing: _applyFollowing,
                    ),
                  ),
                  child: Text(loc.planningApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
