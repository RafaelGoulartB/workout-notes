import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/proposals/ai_proposal_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

String _timeOfDay(AppLocalizations l10n, String? key) => switch (key) {
  'morning' => l10n.bodyTrackerMorning,
  'afternoon' => l10n.bodyTrackerAfternoon,
  'evening' => l10n.bodyTrackerEvening,
  'night' => l10n.bodyTrackerNight,
  _ => '',
};

/// Preview of a `body_measurement` proposal: each measurement next to the
/// previous one of its type, so a typo stands out before it is saved.
class BodyMeasurementProposalBody extends StatelessWidget {
  final Map<String, dynamic> preview;

  const BodyMeasurementProposalBody({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final items = jsonMaps(preview['items']);
    final when = [
      fmt.date(jsonText(preview['date'])),
      _timeOfDay(l10n, jsonText(preview['time_of_day'])),
      if (jsonTrue(preview['is_fasted'])) l10n.aiProposalBodyFasted,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          when,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (jsonText(preview['comment']) != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              jsonText(preview['comment'])!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 6),
        for (final item in items) _MeasurementRow(item: item, fmt: fmt),
      ],
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final AiProposalFormat fmt;

  const _MeasurementRow({required this.item, required this.fmt});

  String _value(Object? value, Object? secondary, String unit) {
    final primary = fmt.number(jsonNum(value), maxFraction: 2);
    return secondary == null
        ? '$primary $unit'
        : '$primary/${fmt.number(jsonNum(secondary), maxFraction: 0)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = fmt.l10n;
    final theme = Theme.of(context);
    final unit = jsonText(item['unit']) ?? '';
    final previous = jsonMap(item['previous']);
    final side = jsonText(item['side']);
    final label = [
      fmt.measureLabel(jsonText(item['type']) ?? ''),
      if (side != null)
        side == 'left' ? l10n.bodyTrackerLeft : l10n.bodyTrackerRight,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  previous.isEmpty
                      ? l10n.aiProposalBodyNoPrevious
                      : l10n.aiProposalBodyPrevious(
                          _value(
                            previous['value'],
                            previous['secondary_value'],
                            unit,
                          ),
                          fmt.date(jsonText(previous['date'])),
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _value(item['value'], item['secondary_value'], unit),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _period(AppLocalizations l10n, String? period) => period == 'monthly'
    ? l10n.aiProposalPeriodMonth
    : l10n.aiProposalPeriodWeek;

String _metric(AppLocalizations l10n, String? metric) => switch (metric) {
  'volume' => l10n.goalMetricVolume,
  'days' => l10n.goalMetricDays,
  'distance' => l10n.goalMetricDistance,
  'time' => l10n.goalMetricTime,
  _ => '',
};

String _unit(AppLocalizations l10n, String? unit) => switch (unit) {
  'days' => l10n.aiProposalUnitDays,
  'min' => l10n.aiProposalUnitMinutes,
  _ => unit ?? '',
};

/// Preview of a `goal` proposal: the goal and, for an update, each changed
/// field as `before → after`.
class GoalProposalBody extends StatelessWidget {
  final Map<String, dynamic> preview;

  const GoalProposalBody({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final goal = jsonMap(preview['goal']);
    final changes = jsonMap(preview['changes']);
    final suggested = jsonNum(preview['suggested_target']);
    final unit = _unit(l10n, jsonText(goal['unit']));
    final title =
        jsonText(goal['title']) ?? _metric(l10n, jsonText(goal['metric']));
    final action = preview['action'];

    String target(Object? value) => fmt.number(jsonNum(value), maxFraction: 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AppMetricChip(
              text: goal['scope'] == 'aerobic'
                  ? l10n.goalScopeAerobic
                  : l10n.goalScopeAnaerobic,
            ),
            AppMetricChip(text: _metric(l10n, jsonText(goal['metric']))),
            if (action == 'activate' || action == 'deactivate')
              AppMetricChip(
                text: action == 'activate'
                    ? l10n.aiProposalGoalActive
                    : l10n.aiProposalGoalPaused,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (action == 'create' || changes.isEmpty)
          Text(
            l10n.aiProposalGoalTarget(
              target(goal['target']),
              unit,
              _period(l10n, jsonText(goal['period'])),
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        if (changes['target'] != null)
          AiProposalChangeLine(
            icon: Icons.flag_rounded,
            color: theme.colorScheme.primary,
            text: l10n.aiProposalFieldChange(
              _metric(l10n, jsonText(goal['metric'])),
              '${target(jsonMap(changes['target'])['from'])} $unit',
              '${target(jsonMap(changes['target'])['to'])} $unit',
            ),
          ),
        if (changes['period'] != null)
          AiProposalChangeLine(
            icon: Icons.event_repeat_rounded,
            color: theme.colorScheme.primary,
            text: l10n.aiProposalFieldChange(
              l10n.goalChoosePeriod,
              _periodName(l10n, jsonMap(changes['period'])['from']),
              _periodName(l10n, jsonMap(changes['period'])['to']),
            ),
          ),
        if (changes['title'] != null)
          AiProposalChangeLine(
            icon: Icons.title_rounded,
            color: theme.colorScheme.primary,
            text:
                '"${jsonMap(changes['title'])['from']}" → "${jsonMap(changes['title'])['to']}"',
          ),
        if (suggested != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.aiProposalGoalSuggested(target(suggested), unit),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  static String _periodName(AppLocalizations l10n, Object? period) =>
      period == 'monthly' ? l10n.goalPeriodMonthly : l10n.goalPeriodWeekly;
}

/// Preview of a `nutrition_goal` proposal: which goal changes (settings or the
/// active phase) and each target as `before → after`.
class NutritionGoalProposalBody extends StatelessWidget {
  final Map<String, dynamic> preview;

  const NutritionGoalProposalBody({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final before = jsonMap(preview['before']);
    final after = jsonMap(preview['after']);
    final phase = jsonMap(preview['phase']);
    final isPhase = preview['scope'] == 'active_phase';
    final rows = <(String, String, String)>[
      (l10n.nutritionProgressCalories, 'calories', 'kcal'),
      (l10n.nutritionProgressProtein, 'protein_g', 'g'),
      (l10n.nutritionProgressCarbs, 'carbs_g', 'g'),
      (l10n.nutritionProgressFat, 'fat_g', 'g'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isPhase
              ? l10n.aiProposalNutritionPhase(
                  jsonText(phase['name']) ?? '',
                  jsonNum(phase['from_week'])?.toInt() ?? 1,
                  jsonNum(phase['weeks_changed'])?.toInt() ?? 0,
                )
              : l10n.aiProposalNutritionSettings,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final (label, key, unit) in rows)
          if (jsonNum(after[key]) != null)
            _TargetRow(
              label: label,
              before: jsonNum(before[key]) == null
                  ? l10n.aiProposalNutritionNotSet
                  : fmt.withUnit(jsonNum(before[key]), unit, maxFraction: 0),
              after: fmt.withUnit(jsonNum(after[key]), unit, maxFraction: 0),
              changed: jsonNum(before[key]) != jsonNum(after[key]),
            ),
        if (isPhase)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.aiProposalNutritionLivedKept,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  final String label;
  final String before;
  final String after;
  final bool changed;

  const _TargetRow({
    required this.label,
    required this.before,
    required this.after,
    required this.changed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (changed) ...[
            Text(
              before,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_right_alt_rounded, size: 18),
            ),
          ],
          Text(
            after,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: changed ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
