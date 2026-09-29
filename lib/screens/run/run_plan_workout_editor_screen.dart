import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/plan_editor/run_plan_editor_blocks.dart';
import 'package:workout_notes/screens/run/plan_editor/run_plan_editor_sheets.dart';
import 'package:workout_notes/screens/run/plan_editor/run_plan_editor_summary.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Session editor — the running counterpart of [RoutineDayEditorScreen].
/// A session is either a continuous run (just a target) or a structured one
/// (an ordered list of steps, with repeat blocks for intervals).
class RunPlanWorkoutEditorScreen extends StatefulWidget {
  final String workoutId;

  const RunPlanWorkoutEditorScreen({super.key, required this.workoutId});

  @override
  State<RunPlanWorkoutEditorScreen> createState() =>
      _RunPlanWorkoutEditorScreenState();
}

class _RunPlanWorkoutEditorScreenState
    extends State<RunPlanWorkoutEditorScreen> {
  final _repo = RunPlanRepository();
  RunPlanWorkout? _workout;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workout = await _repo.getWorkout(widget.workoutId);
    if (!mounted) return;
    if (workout == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _workout = workout;
      _loading = false;
    });
  }

  // ===================== SESSION =====================

  Future<void> _editSession() async {
    final workout = _workout;
    if (workout == null) return;
    final draft = await showRunPlanSessionSheet(context, workout);
    if (draft == null) return;
    await _repo.updateWorkout(
      workout.id,
      name: draft.name,
      kind: draft.kind,
      dayOfWeek: draft.dayOfWeek,
      notes: draft.notes,
      targetDistanceMeters: draft.targetDistanceMeters,
      targetDurationSeconds: draft.targetDurationSeconds,
      targetPaceSecPerKm: draft.targetPaceSecPerKm,
    );
    if (mounted) _load();
  }

  Future<void> _deleteSession() async {
    final workout = _workout;
    if (workout == null) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runWorkoutDeleteConfirm(workout.name)),
        content: Text(loc.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteWorkout(workout.id);
    if (mounted) Navigator.pop(context);
  }

  // ===================== STEPS =====================

  Future<void> _addStep() async {
    final workout = _workout;
    if (workout == null) return;
    final result = await showRunPlanStepSheet(context);
    if (result == null) return;
    await _repo.addStep(
      workoutId: workout.id,
      role: result.role,
      metric: result.metric,
      value: result.value,
      repeatCount: result.repeatCount,
      targetPaceMinSecPerKm: result.paceMin,
      targetPaceMaxSecPerKm: result.paceMax,
    );
    if (mounted) _load();
  }

  Future<void> _editStep(RunWorkoutStep step) async {
    final result = await showRunPlanStepSheet(context, step: step);
    if (result == null) return;
    await _repo.updateStep(
      step.copyWith(
        role: result.role,
        metric: result.metric,
        value: result.value,
        repeatCount: result.repeatCount,
        targetPaceMinSecPerKm: result.paceMin,
        targetPaceMaxSecPerKm: result.paceMax,
      ),
    );
    if (mounted) _load();
  }

  /// Deletes with an undo, because a step is one tap to lose and several taps
  /// (role, metric, value, pace) to type back in.
  Future<void> _deleteStep(RunWorkoutStep step) =>
      _removeSteps([step], AppLocalizations.of(context)!.runWorkoutStepRemoved);

  /// Same undo for a whole `6x (800 m + 2 min)` block: one tap on the trash
  /// removes every leg, so one tap on "undo" has to bring them all back.
  Future<void> _deleteBlock(RunStepBlock block) => _removeSteps(
    block.steps,
    AppLocalizations.of(context)!.runPlanEditorBlockRemoved,
    wholeBlock: true,
  );

  /// Removes [removed] (ordered as in the session) and offers an undo that
  /// puts them back where they were. [wholeBlock] marks a repeat block that
  /// leaves no sibling legs behind.
  Future<void> _removeSteps(
    List<RunWorkoutStep> removed,
    String message, {
    bool wholeBlock = false,
  }) async {
    final workout = _workout;
    if (workout == null || removed.isEmpty) return;
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Remember the position so undo puts the steps back where they were, not
    // last.
    final position = _orderedIds(workout).indexOf(removed.first.id);
    for (final step in removed) {
      await _repo.deleteStep(step.id);
    }
    if (!mounted) return;
    _load();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: loc.commonUndo,
            onPressed: () => _restoreSteps(
              workout.id,
              removed,
              position,
              regroup: wholeBlock,
            ),
          ),
        ),
      );
  }

  static List<String> _orderedIds(RunPlanWorkout workout) =>
      ([...workout.steps]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)))
          .map((step) => step.id)
          .toList();

  /// Re-creates [removed] at [position], reading the session afresh: the
  /// athlete may have added or moved steps since the delete. A block whose
  /// repeat-group id was reused meanwhile gets a new one ([regroup]) so it
  /// does not merge into the newer block.
  Future<void> _restoreSteps(
    String workoutId,
    List<RunWorkoutStep> removed,
    int position, {
    required bool regroup,
  }) async {
    final current = await _repo.getWorkout(workoutId);
    if (current == null) return;
    final base = _orderedIds(current);
    var group = removed.first.repeatGroup;
    if (regroup &&
        group != null &&
        current.steps.any((step) => step.repeatGroup == group)) {
      group = _nextRepeatGroup(current);
    }
    final restoredIds = <String>[];
    for (final step in removed) {
      final restored = await _repo.addStep(
        workoutId: workoutId,
        role: step.role,
        metric: step.metric,
        value: step.value,
        repeatGroup: step.repeatGroup == null ? null : group,
        repeatCount: step.repeatCount,
        targetPaceMinSecPerKm: step.targetPaceMinSecPerKm,
        targetPaceMaxSecPerKm: step.targetPaceMaxSecPerKm,
        notes: step.notes,
      );
      restoredIds.add(restored.id);
    }
    final at = position < 0 ? base.length : position.clamp(0, base.length);
    await _repo.reorderSteps(workoutId, [
      ...base.take(at),
      ...restoredIds,
      ...base.skip(at),
    ]);
    if (mounted) _load();
  }

  /// Reorders whole blocks instead of individual steps: dragging one leg of a
  /// `6x (800 m + 2 min)` block out of the middle would silently split it.
  Future<void> _reorderBlock(int oldIndex, int newIndex) async {
    final workout = _workout;
    if (workout == null) return;
    final blocks = RunPlanUi.blocks(workout.steps);
    final moved = blocks.removeAt(oldIndex);
    blocks.insert(newIndex, moved);
    final ordered = [for (final block in blocks) ...block.steps];
    setState(() => _workout = workout.copyWith(steps: ordered));
    await _repo.reorderSteps(
      workout.id,
      ordered.map((step) => step.id).toList(),
    );
    if (mounted) _load();
  }

  /// Adds `effort + recovery` as one repeated block — the shape of a tiro
  /// session. Building it step by step would be four taps and easy to get wrong.
  Future<void> _addIntervalBlock() async {
    final workout = _workout;
    if (workout == null) return;
    final draft = await showRunPlanIntervalBlockSheet(context);
    if (draft == null) return;
    final pace = draft.pace;
    // A fresh group id so this block does not merge into an existing one.
    final group = _nextRepeatGroup(workout);

    await _repo.addStep(
      workoutId: workout.id,
      role: RunStepRole.work,
      metric: draft.effortMetric,
      value: draft.effort,
      repeatGroup: group,
      repeatCount: draft.repeats,
      targetPaceMinSecPerKm: pace,
      targetPaceMaxSecPerKm: pace == null ? null : pace + 10,
    );
    if (draft.recovery != null) {
      await _repo.addStep(
        workoutId: workout.id,
        role: RunStepRole.recovery,
        metric: draft.recoveryMetric,
        value: draft.recovery!,
        repeatGroup: group,
        repeatCount: draft.repeats,
      );
    }
    if (mounted) _load();
  }

  static int _nextRepeatGroup(RunPlanWorkout workout) {
    var max = 0;
    for (final step in workout.steps) {
      final group = step.repeatGroup;
      if (group != null && group > max) max = group;
    }
    return max + 1;
  }

  Future<void> _startSession() async {
    final workout = _workout;
    if (workout == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunRecordScreen(planWorkout: workout)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final workout = _workout;

    if (_loading || workout == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final blocks = RunPlanUi.blocks(workout.steps);

    return Scaffold(
      appBar: AppBar(
        title: Text(workout.name),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: loc.runWorkoutEditTitle,
            onPressed: _editSession,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _deleteSession();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'delete', child: Text(loc.runWorkoutDelete)),
            ],
          ),
        ],
      ),
      // The start button lives in a bottom bar so it stays reachable while the
      // step list grows.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _startSession,
            icon: const Icon(Icons.play_arrow),
            label: Text(loc.runWorkoutStartSession),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          RunPlanEditorSummary(workout: workout),
          RunSectionHeader(
            loc.runWorkoutStepsTitle,
            padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
          ),
          if (blocks.isEmpty)
            const RunPlanEditorStepsEmpty()
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: blocks.length,
              onReorderItem: _reorderBlock,
              itemBuilder: (context, index) {
                final block = blocks[index];
                return RunPlanEditorBlockTile(
                  key: ValueKey(block.steps.first.id),
                  index: index,
                  block: block,
                  onEditStep: _editStep,
                  onDeleteStep: _deleteStep,
                  onDeleteBlock: () => _deleteBlock(block),
                );
              },
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addStep,
            icon: const Icon(Icons.add, size: 18),
            label: Text(loc.runWorkoutAddStep),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addIntervalBlock,
            icon: const Icon(Icons.repeat, size: 18),
            label: Text(loc.runWorkoutAddIntervalBlock),
          ),
        ],
      ),
    );
  }
}
