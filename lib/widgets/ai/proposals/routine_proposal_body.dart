import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/proposals/ai_proposal_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// The honest diff of a routine proposal: every day, exercise and set that is
/// added, removed, replaced, moved or changed, with `before → after` per field
/// ("Weight: 60 → 200 kg"), plus the current routine name for an update.
/// Removed items are listed by name.
class RoutineProposalBody extends StatefulWidget {
  final Map<String, dynamic> preview;

  const RoutineProposalBody({super.key, required this.preview});

  @override
  State<RoutineProposalBody> createState() => _RoutineProposalBodyState();
}

class _RoutineProposalBodyState extends State<RoutineProposalBody> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final preview = widget.preview;
    final isUpdate = preview['action'] == 'update';
    final days = jsonMaps(preview['days']);
    final counts = jsonMap(preview['counts']);
    int count(String key) => jsonNum(counts[key])?.toInt() ?? 0;

    final chips = isUpdate
        ? [
            if (count('days_added') > 0)
              l10n.aiProposalChangeDaysAdded(count('days_added')),
            if (count('days_removed') > 0)
              l10n.aiProposalChangeDaysRemoved(count('days_removed')),
            if (count('exercises_added') > 0)
              l10n.aiProposalChangeExercisesAdded(count('exercises_added')),
            if (count('exercises_removed') > 0)
              l10n.aiProposalChangeExercisesRemoved(count('exercises_removed')),
            if (count('exercises_swapped') > 0)
              l10n.aiProposalChangeExercisesReplaced(
                count('exercises_swapped'),
              ),
            if (count('exercises_moved') > 0)
              l10n.aiProposalChangeExercisesMoved(count('exercises_moved')),
            if (count('sets_added') > 0)
              l10n.aiProposalChangeSetsAdded(count('sets_added')),
            if (count('sets_removed') > 0)
              l10n.aiProposalChangeSetsRemoved(count('sets_removed')),
            if (count('sets_changed') > 0)
              l10n.aiProposalChangeSetsChanged(count('sets_changed')),
          ]
        : [
            l10n.aiProposalCountDays(days.length),
            l10n.aiProposalCountExercises(count('exercises_added')),
            l10n.aiProposalCountSets(count('sets_added')),
          ];

    final notes = <String>[
      if (jsonTrue(preview['name_changed']) &&
          preview['current_name'] is String)
        l10n.aiProposalRoutineRenamed(preview['current_name'] as String),
      if (jsonTrue(preview['notes_changed']))
        l10n.aiProposalRoutineNotesChanged,
      if (jsonTrue(preview['days_reordered']))
        l10n.aiProposalRoutineDaysReordered,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final text in chips) AppMetricChip(text: text)],
          ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final day in days)
          _DayBlock(day: day, fmt: fmt, details: _details, isUpdate: isUpdate),
        if (days.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('ai-proposal-routine-details'),
              onPressed: () => setState(() => _details = !_details),
              icon: Icon(
                _details
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                _details
                    ? l10n.aiProposalHideDetails
                    : l10n.aiProposalShowDetails,
              ),
            ),
          ),
      ],
    );
  }
}

class _DayBlock extends StatelessWidget {
  final Map<String, dynamic> day;
  final AiProposalFormat fmt;
  final bool details;
  final bool isUpdate;

  const _DayBlock({
    required this.day,
    required this.fmt,
    required this.details,
    required this.isUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = fmt.l10n;
    final theme = Theme.of(context);
    final status = day['status'] as String? ?? 'unchanged';
    final exercises = jsonMaps(day['exercises']);
    final unchanged = [
      for (final e in exercises)
        if (e['status'] == 'unchanged') e,
    ];
    final visible = [
      for (final e in exercises)
        if (e['status'] != 'unchanged' || !isUpdate) e,
    ];
    final removedDay = status == 'removed';
    final tag = switch (status) {
      'added' when isUpdate => l10n.aiProposalTagNew,
      'removed' => l10n.aiProposalTagRemoved,
      _ => null,
    };
    final tint = switch (status) {
      'removed' => theme.colorScheme.error,
      'added' => Colors.green.shade700,
      _ => theme.colorScheme.onSurface,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: day['name'] as String? ?? '',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tint,
                          decoration: removedDay
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (day['old_name'] is String)
                        TextSpan(
                          text:
                              '  ${l10n.aiProposalRoutineWasDay(day['old_name'] as String)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (tag != null)
                AppPill(
                  label: tag,
                  color: tint,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                ),
            ],
          ),
          if (jsonTrue(day['reordered']))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.aiProposalRoutineExercisesReordered,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final exercise in visible)
            _ExerciseBlock(exercise: exercise, fmt: fmt, details: details),
          if (isUpdate && unchanged.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.aiProposalRoutineUnchangedExercises(unchanged.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final AiProposalFormat fmt;
  final bool details;

  const _ExerciseBlock({
    required this.exercise,
    required this.fmt,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = fmt.l10n;
    final theme = Theme.of(context);
    final status = exercise['status'] as String? ?? 'unchanged';
    final name = fmt.exerciseName(exercise);
    final old = jsonMap(exercise['old']);
    final swapped = old.isNotEmpty;
    final sets = jsonMaps(exercise['sets']);
    final setCount = jsonNum(exercise['set_count'])?.toInt() ?? sets.length;
    final green = Colors.green.shade700;
    final red = theme.colorScheme.error;
    final primary = theme.colorScheme.primary;

    final (icon, color) = switch (status) {
      'added' => (Icons.add_circle_outline_rounded, green),
      'removed' => (Icons.remove_circle_outline_rounded, red),
      'moved' => (Icons.drive_file_move_outline, primary),
      'changed' when swapped => (Icons.swap_horiz_rounded, primary),
      'changed' => (Icons.edit_outlined, primary),
      _ => (Icons.fitness_center_rounded, theme.colorScheme.outline),
    };
    final title = swapped ? '${fmt.exerciseName(old)} → $name' : name;
    final caption = <String>[
      if (status == 'added' || status == 'removed')
        l10n.aiProposalCountSets(setCount),
      if (exercise['from_day'] is Map)
        l10n.aiProposalRoutineMovedFrom(
          (exercise['from_day'] as Map)['name'] as String? ?? '',
        ),
      if (status == 'added' && exercise['rest'] is Map)
        l10n.aiProposalRoutineRest(
          fmt.seconds((exercise['rest'] as Map)['to'] as int?),
        ),
    ].join(' · ');

    final changes = <Widget>[];
    final rest = jsonMap(exercise['rest']);
    if (status != 'added' && rest.containsKey('from')) {
      changes.add(
        AiProposalChangeLine(
          icon: Icons.timer_outlined,
          text: l10n.aiProposalRoutineRestChange(
            rest['from'] == null
                ? l10n.aiProposalNone
                : fmt.seconds(rest['from'] as int?),
            rest['to'] == null
                ? l10n.aiProposalNone
                : fmt.seconds(rest['to'] as int?),
          ),
        ),
      );
    }
    final superset = jsonMap(exercise['superset']);
    if (status != 'added' && superset.containsKey('from')) {
      changes.add(
        AiProposalChangeLine(
          icon: Icons.link_rounded,
          text: l10n.aiProposalRoutineSupersetChange(
            (superset['from'] as String?) ?? l10n.aiProposalNone,
            (superset['to'] as String?) ?? l10n.aiProposalNone,
          ),
        ),
      );
    }
    if (status == 'changed' || status == 'moved') {
      for (final set in sets) {
        final line = _setChange(set, fmt, theme);
        if (line != null) changes.add(line);
      }
    }
    final grouped = status == 'added' && details
        ? _groupSets(sets, fmt)
        : const <String>[];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiProposalChangeLine(
            icon: icon,
            color: color,
            text: title,
            caption: caption.isEmpty ? null : caption,
            strike: status == 'removed',
          ),
          if (changes.isNotEmpty || grouped.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 21),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...changes,
                  for (final line in grouped)
                    Text(line, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (details && jsonNum(exercise['unchanged_sets']) != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 21),
              child: Text(
                l10n.aiProposalRoutineUnchangedSets(
                  jsonNum(exercise['unchanged_sets'])!.toInt(),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One line for a changed/added/removed set of a kept exercise.
  Widget? _setChange(
    Map<String, dynamic> set,
    AiProposalFormat fmt,
    ThemeData theme,
  ) {
    final l10n = fmt.l10n;
    switch (set['status']) {
      case 'added':
        return AiProposalChangeLine(
          icon: Icons.add_rounded,
          color: Colors.green.shade700,
          text: '${l10n.aiProposalTagNew}: ${_setText(set, fmt)}',
        );
      case 'removed':
        return AiProposalChangeLine(
          icon: Icons.remove_rounded,
          color: theme.colorScheme.error,
          text: _setText(set, fmt),
          strike: true,
        );
      case 'changed':
        final changes = jsonMap(set['changes']);
        final parts = <String>[];
        for (final field in const [
          'weight',
          'reps',
          'distance',
          'time_seconds',
        ]) {
          final change = jsonMap(changes[field]);
          if (change.isEmpty) continue;
          parts.add(
            l10n.aiProposalFieldChange(
              _fieldLabel(l10n, field),
              _fieldValue(change['from'], field, fmt),
              _fieldValue(change['to'], field, fmt),
            ),
          );
        }
        final warm = jsonMap(changes['is_warmup']);
        if (warm.isNotEmpty) {
          parts.add(
            warm['to'] == true
                ? l10n.aiProposalSetWarmupOn
                : l10n.aiProposalSetWarmupOff,
          );
        }
        return AiProposalChangeLine(
          icon: Icons.arrow_right_alt_rounded,
          color: theme.colorScheme.primary,
          text: parts.join(' · '),
        );
    }
    return null;
  }

  static String _fieldLabel(AppLocalizations l10n, String field) =>
      switch (field) {
        'weight' => l10n.aiProposalFieldWeight,
        'reps' => l10n.aiProposalFieldReps,
        'distance' => l10n.aiProposalFieldDistance,
        _ => l10n.aiProposalFieldTime,
      };

  /// A set field value with its unit; absent values read as "none".
  static String _fieldValue(Object? value, String field, AiProposalFormat fmt) {
    final number = jsonNum(value);
    if (number == null) return fmt.l10n.aiProposalNone;
    return switch (field) {
      'weight' => fmt.withUnit(number, 'kg'),
      'distance' => fmt.withUnit(number, 'km', maxFraction: 2),
      'time_seconds' => fmt.seconds(number.toInt()),
      _ => fmt.number(number, maxFraction: 0),
    };
  }

  /// `60 kg × 10`, `5 km · 25:00`, with a warm-up tag.
  static String _setText(Map<String, dynamic> set, AiProposalFormat fmt) {
    final values = jsonMap(set['values']);
    final weight = jsonNum(values['weight']);
    final reps = jsonNum(values['reps'])?.toInt();
    final distance = jsonNum(values['distance']);
    final time = jsonNum(values['time_seconds'])?.toInt();
    final parts = <String>[];
    if (weight != null && reps != null) {
      parts.add('${fmt.withUnit(weight, 'kg')} × $reps');
    } else {
      if (weight != null) parts.add(fmt.withUnit(weight, 'kg'));
      if (reps != null) parts.add(fmt.l10n.aiProposalRepsValue(reps));
    }
    if (distance != null) {
      parts.add(fmt.withUnit(distance, 'km', maxFraction: 2));
    }
    if (time != null) parts.add(fmt.seconds(time));
    var text = parts.isEmpty ? '—' : parts.join(' · ');
    if (set['warmup'] == true) text += ' (${fmt.l10n.aiProposalSetWarmup})';
    return text;
  }

  /// `3× 60 kg × 10` for runs of identical sets.
  static List<String> _groupSets(
    List<Map<String, dynamic>> sets,
    AiProposalFormat fmt,
  ) {
    final out = <String>[];
    String? last;
    var run = 0;
    void flush() {
      if (last != null) out.add(run > 1 ? '$run× $last' : last);
    }

    for (final set in sets) {
      final text = _setText(set, fmt);
      if (text == last) {
        run++;
      } else {
        flush();
        last = text;
        run = 1;
      }
    }
    flush();
    return out;
  }
}
