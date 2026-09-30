import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/strength_routine_format.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';
import 'package:workout_notes/widgets/workout/set_editor_fields.dart';

/// Values chosen in [showRoutineSetEditor].
class RoutineSetValues {
  final double weight;
  final int reps;
  final double distance;
  final int timeSeconds;
  final bool isWarmup;

  const RoutineSetValues({
    required this.weight,
    required this.reps,
    required this.distance,
    required this.timeSeconds,
    required this.isWarmup,
  });
}

/// Bottom sheet that edits one preset set with the same controls as the
/// active workout.
Future<RoutineSetValues?> showRoutineSetEditor(
  BuildContext context, {
  required String exerciseType,
  required double weightIncrement,
  required String exerciseName,
  required int setNumber,
  double weight = 0,
  int reps = 0,
  double distance = 0,
  int timeSeconds = 0,
  bool isWarmup = false,
}) {
  return showModalBottomSheet<RoutineSetValues>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _RoutineSetEditor(
      exerciseType: exerciseType,
      weightIncrement: weightIncrement,
      exerciseName: exerciseName,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      distance: distance,
      timeSeconds: timeSeconds,
      isWarmup: isWarmup,
    ),
  );
}

class _RoutineSetEditor extends StatefulWidget {
  final String exerciseType;
  final double weightIncrement;
  final String exerciseName;
  final int setNumber;
  final double weight;
  final int reps;
  final double distance;
  final int timeSeconds;
  final bool isWarmup;

  const _RoutineSetEditor({
    required this.exerciseType,
    required this.weightIncrement,
    required this.exerciseName,
    required this.setNumber,
    required this.weight,
    required this.reps,
    required this.distance,
    required this.timeSeconds,
    required this.isWarmup,
  });

  @override
  State<_RoutineSetEditor> createState() => _RoutineSetEditorState();
}

class _RoutineSetEditorState extends State<_RoutineSetEditor> {
  late double _weight = widget.weight;
  late int _reps = widget.reps;
  late double _distance = widget.distance;
  late int _time = widget.timeSeconds;
  late bool _warmup = widget.isWarmup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.setNumber > 0
                      ? loc.activeWorkoutEditSetNumber(widget.setNumber)
                      : loc.activeWorkoutAddSet,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  widget.exerciseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.whatshot,
                size: 16,
                color: _warmup
                    ? Colors.orange
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(loc.activeWorkoutWarmup, style: theme.textTheme.bodyMedium),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _warmup,
                  onChanged: (v) => setState(() => _warmup = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          WorkoutSetFieldControls(
            exerciseType: widget.exerciseType,
            weight: _weight,
            reps: _reps,
            distance: _distance,
            timeSeconds: _time,
            weightIncrement: widget.weightIncrement,
            showPace: true,
            onWeightChanged: (v) => setState(() => _weight = v),
            onRepsChanged: (v) => setState(() => _reps = v),
            onDistanceChanged: (v) => setState(() => _distance = v),
            onTimeChanged: (v) => setState(() => _time = v),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(loc.commonCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    RoutineSetValues(
                      weight: _weight,
                      reps: _reps,
                      distance: _distance,
                      timeSeconds: _time,
                      isWarmup: _warmup,
                    ),
                  ),
                  child: Text(loc.commonSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rest presets sheet; returns the chosen seconds.
Future<int?> showRoutineRestSheet(
  BuildContext context, {
  required int currentSeconds,
}) {
  const presets = [30, 45, 60, 90, 120, 150, 180, 240];
  final theme = Theme.of(context);
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.routinesRestTimeTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final seconds in presets)
                  ChoiceChip(
                    label: Text(StrengthRoutineFormat.rest(seconds)),
                    selected: currentSeconds == seconds,
                    onSelected: (_) => Navigator.pop(ctx, seconds),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Formats one field of a preset set for the compact set table.
String routineSetCell(Map<String, dynamic> set, String key) {
  switch (key) {
    case 'weight':
      final v = (set['weight'] as num?)?.toDouble();
      return v == null ? '-' : StrengthRoutineFormat.kg(v);
    case 'distance':
      final v = (set['distance'] as num?)?.toDouble();
      return v == null ? '-' : StrengthRoutineFormat.kg(v);
    default:
      return formatFieldValue(set, key);
  }
}
