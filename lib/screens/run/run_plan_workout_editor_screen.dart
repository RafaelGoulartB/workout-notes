import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

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
    final loc = AppLocalizations.of(context)!;
    final nameCtl = TextEditingController(text: workout.name);
    final notesCtl = TextEditingController(text: workout.notes ?? '');
    final distanceCtl = TextEditingController(
      text: workout.targetDistanceMeters == null
          ? ''
          : (workout.targetDistanceMeters! / 1000).toStringAsFixed(1),
    );
    final durationCtl = TextEditingController(
      text: workout.targetDurationSeconds == null
          ? ''
          : (workout.targetDurationSeconds! ~/ 60).toString(),
    );
    final paceCtl = TextEditingController(
      text: workout.targetPaceSecPerKm == null
          ? ''
          : RunPlanUi.paceLabel(workout.targetPaceSecPerKm),
    );
    var kind = workout.kind;
    var dayOfWeek = workout.dayOfWeek;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.runWorkoutEditTitle,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutName,
                    hintText: loc.runWorkoutNameHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RunWorkoutKind>(
                  initialValue: kind,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutKindLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in RunWorkoutKind.values)
                      DropdownMenuItem(
                        value: value,
                        child: Row(
                          children: [
                            Icon(
                              RunPlanUi.kindIcon(value),
                              size: 16,
                              color: RunPlanUi.kindColor(
                                Theme.of(ctx).colorScheme,
                                value,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(RunPlanUi.kindLabel(loc, value)),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => kind = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: dayOfWeek,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutDayOfWeek,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(loc.runWorkoutDayAny),
                    ),
                    for (var day = 1; day <= 7; day++)
                      DropdownMenuItem(
                        value: day,
                        child: Text(RunPlanUi.weekdayLabel(loc, day)),
                      ),
                  ],
                  onChanged: (value) => setSheetState(() => dayOfWeek = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: distanceCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: loc.runWorkoutTargetDistance,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: durationCtl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: loc.runWorkoutTargetDuration,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: paceCtl,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutTargetPace,
                    hintText: '4:35',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: loc.runPlanNotes,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(loc.commonSave),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;

    final km = double.tryParse(distanceCtl.text.trim().replaceAll(',', '.'));
    final minutes = int.tryParse(durationCtl.text.trim());
    await _repo.updateWorkout(
      workout.id,
      name: nameCtl.text.trim().isEmpty ? null : nameCtl.text.trim(),
      kind: kind,
      dayOfWeek: dayOfWeek,
      notes: notesCtl.text.trim(),
      targetDistanceMeters: km == null || km <= 0 ? null : km * 1000,
      targetDurationSeconds: minutes == null || minutes <= 0
          ? null
          : minutes * 60,
      targetPaceSecPerKm: RunPlanUi.parsePace(paceCtl.text),
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
    final result = await _showStepSheet();
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
    final result = await _showStepSheet(step: step);
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
  Future<void> _deleteStep(RunWorkoutStep step) async {
    final workout = _workout;
    if (workout == null) return;
    final loc = AppLocalizations.of(context)!;
    // Remember the order so undo puts the step back where it was, not last.
    final order =
        ([...workout.steps]
              ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)))
            .map((item) => item.id)
            .toList();
    final position = order.indexOf(step.id);
    await _repo.deleteStep(step.id);
    if (!mounted) return;
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.runWorkoutStepRemoved),
        action: SnackBarAction(
          label: loc.commonUndo,
          onPressed: () async {
            final restored = await _repo.addStep(
              workoutId: workout.id,
              role: step.role,
              metric: step.metric,
              value: step.value,
              repeatGroup: step.repeatGroup,
              repeatCount: step.repeatCount,
              targetPaceMinSecPerKm: step.targetPaceMinSecPerKm,
              targetPaceMaxSecPerKm: step.targetPaceMaxSecPerKm,
              notes: step.notes,
            );
            if (position >= 0) {
              order[position] = restored.id;
              await _repo.reorderSteps(workout.id, order);
            }
            if (mounted) _load();
          },
        ),
      ),
    );
  }

  Future<void> _deleteBlock(RunStepBlock block) async {
    for (final step in block.steps) {
      await _repo.deleteStep(step.id);
    }
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
    final loc = AppLocalizations.of(context)!;
    final repeatsCtl = TextEditingController(text: '6');
    final effortCtl = TextEditingController(text: '800');
    final recoveryCtl = TextEditingController(text: '2:00');
    final paceCtl = TextEditingController();
    var effortMetric = RunIntervalMetric.distance;
    var recoveryMetric = RunIntervalMetric.time;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.runWorkoutIntervalBlockTitle,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.runWorkoutIntervalBlockHint,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: repeatsCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutStepRepeats,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                _MetricValueRow(
                  label: loc.runWorkoutStepRoleWork,
                  controller: effortCtl,
                  metric: effortMetric,
                  onMetricChanged: (value) =>
                      setSheetState(() => effortMetric = value),
                ),
                const SizedBox(height: 12),
                _MetricValueRow(
                  label: loc.runWorkoutStepRoleRecovery,
                  controller: recoveryCtl,
                  metric: recoveryMetric,
                  onMetricChanged: (value) =>
                      setSheetState(() => recoveryMetric = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: paceCtl,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutStepPaceRange,
                    hintText: '3:50',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(loc.commonSave),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;

    final repeats = (int.tryParse(repeatsCtl.text.trim()) ?? 1).clamp(1, 99);
    final effort = _readMetric(effortCtl.text, effortMetric);
    final recovery = _readMetric(recoveryCtl.text, recoveryMetric);
    if (effort == null) return;
    final pace = RunPlanUi.parsePace(paceCtl.text);
    // A fresh group id so this block does not merge into an existing one.
    final group = _nextRepeatGroup(workout);

    await _repo.addStep(
      workoutId: workout.id,
      role: RunStepRole.work,
      metric: effortMetric,
      value: effort,
      repeatGroup: group,
      repeatCount: repeats,
      targetPaceMinSecPerKm: pace,
      targetPaceMaxSecPerKm: pace == null ? null : pace + 10,
    );
    if (recovery != null) {
      await _repo.addStep(
        workoutId: workout.id,
        role: RunStepRole.recovery,
        metric: recoveryMetric,
        value: recovery,
        repeatGroup: group,
        repeatCount: repeats,
      );
    }
    if (mounted) _load();
  }

  /// Distance stays plain metres; time also accepts `2:00`.
  static int? _readMetric(String raw, RunIntervalMetric metric) {
    if (metric == RunIntervalMetric.time) return RunPlanUi.parseSeconds(raw);
    final metres = int.tryParse(raw.trim());
    return metres == null || metres <= 0 ? null : metres;
  }

  static int _nextRepeatGroup(RunPlanWorkout workout) {
    var max = 0;
    for (final step in workout.steps) {
      final group = step.repeatGroup;
      if (group != null && group > max) max = group;
    }
    return max + 1;
  }

  Future<_StepDraft?> _showStepSheet({RunWorkoutStep? step}) {
    final loc = AppLocalizations.of(context)!;
    final valueCtl = TextEditingController(
      text: step == null
          ? ''
          : step.metric == RunIntervalMetric.time
          ? RunPlanUi.secondsInput(step.value)
          : step.value.toString(),
    );
    final repeatsCtl = TextEditingController(
      text: (step?.repeatCount ?? 1).toString(),
    );
    final paceFromCtl = TextEditingController(
      text: step?.targetPaceMinSecPerKm == null
          ? ''
          : RunPlanUi.paceLabel(step!.targetPaceMinSecPerKm),
    );
    final paceToCtl = TextEditingController(
      text: step?.targetPaceMaxSecPerKm == null
          ? ''
          : RunPlanUi.paceLabel(step!.targetPaceMaxSecPerKm),
    );
    var role = step?.role ?? RunStepRole.work;
    var metric = step?.metric ?? RunIntervalMetric.distance;

    return showModalBottomSheet<_StepDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  step == null ? loc.runWorkoutAddStep : loc.runWorkoutStepEdit,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                // Roles are five short words — chips beat a dropdown here.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in RunStepRole.values)
                      ChoiceChip(
                        selected: role == value,
                        label: Text(RunPlanUi.roleLabel(loc, value)),
                        onSelected: (_) => setSheetState(() => role = value),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _MetricValueRow(
                  controller: valueCtl,
                  metric: metric,
                  onMetricChanged: (value) =>
                      setSheetState(() => metric = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: repeatsCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: loc.runWorkoutStepRepeats,
                    helperText: step?.repeatGroup == null
                        ? null
                        : loc.runWorkoutStepRepeatHint,
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  loc.runWorkoutStepPaceRange,
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: paceFromCtl,
                        decoration: InputDecoration(
                          labelText: loc.runWorkoutStepPaceFrom,
                          hintText: '3:50',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: paceToCtl,
                        decoration: InputDecoration(
                          labelText: loc.runWorkoutStepPaceTo,
                          hintText: '4:05',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final value = _readMetric(valueCtl.text, metric);
                    if (value == null) return;
                    Navigator.pop(
                      ctx,
                      _StepDraft(
                        role: role,
                        metric: metric,
                        value: value,
                        repeatCount: (int.tryParse(repeatsCtl.text.trim()) ?? 1)
                            .clamp(1, 99),
                        paceMin: RunPlanUi.parsePace(paceFromCtl.text),
                        paceMax: RunPlanUi.parsePace(paceToCtl.text),
                      ),
                    );
                  },
                  child: Text(loc.commonSave),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
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
    final theme = Theme.of(context);
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
          _buildSummary(theme, loc, workout),
          const SizedBox(height: 20),
          Text(
            loc.runWorkoutStepsTitle.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (blocks.isEmpty)
            _buildStepsEmpty(theme, loc)
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: blocks.length,
              onReorderItem: _reorderBlock,
              itemBuilder: (context, index) {
                final block = blocks[index];
                return _BlockTile(
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

  Widget _buildSummary(
    ThemeData theme,
    AppLocalizations loc,
    RunPlanWorkout workout,
  ) {
    final color = RunPlanUi.kindColor(theme.colorScheme, workout.kind);
    final estimate = RunPlanUi.estimatedTotalSeconds(workout);
    final distance = workout.plannedDistanceMeters > 0
        ? workout.plannedDistanceMeters
        : (workout.targetDistanceMeters ?? 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RunPlanUi.kindIcon(workout.kind), color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                RunPlanUi.kindLabel(loc, workout.kind),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                RunPlanUi.weekdayLabel(loc, workout.dayOfWeek),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RunWorkoutProfileBar(workout: workout, height: 12),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              if (distance > 0)
                _SummaryStat(
                  label: loc.commonTotal,
                  value: RunPlanUi.distanceLabel(distance),
                ),
              if (estimate > 0)
                _SummaryStat(
                  label: loc.runWorkoutEstimatedTime,
                  value: '~${RunPlanUi.durationRoughLabel(estimate)}',
                ),
              if (RunPlanUi.repsLabel(workout) != null)
                _SummaryStat(
                  label: loc.runWorkoutStepRepeats,
                  value: RunPlanUi.repsLabel(workout)!,
                ),
              if (workout.targetPaceSecPerKm != null)
                _SummaryStat(
                  label: loc.commonPace,
                  value:
                      '${RunPlanUi.paceLabel(workout.targetPaceSecPerKm)}/km',
                ),
            ],
          ),
          if (workout.notes != null && workout.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(workout.notes!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildStepsEmpty(ThemeData theme, AppLocalizations loc) => Container(
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(70)),
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

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StepDraft {
  final RunStepRole role;
  final RunIntervalMetric metric;
  final int value;
  final int repeatCount;
  final double? paceMin;
  final double? paceMax;

  const _StepDraft({
    required this.role,
    required this.metric,
    required this.value,
    required this.repeatCount,
    this.paceMin,
    this.paceMax,
  });
}

/// Value field plus a distance/time toggle — the same control the step sheet
/// and the interval-block sheet need.
class _MetricValueRow extends StatelessWidget {
  /// Prefix for the field label ("Tiro", "Recuperação"). Null in the step sheet,
  /// where the role is already picked right above the field.
  final String? label;
  final TextEditingController controller;
  final RunIntervalMetric metric;
  final ValueChanged<RunIntervalMetric> onMetricChanged;

  const _MetricValueRow({
    required this.controller,
    required this.metric,
    required this.onMetricChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isTime = metric == RunIntervalMetric.time;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: isTime ? TextInputType.text : TextInputType.number,
            decoration: InputDecoration(
              labelText: [
                if (label != null) label,
                isTime ? loc.runWorkoutStepTime : loc.runWorkoutStepDistance,
              ].join(' · '),
              hintText: isTime ? '2:00' : '800',
              suffixText: isTime ? null : 'm',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<RunIntervalMetric>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: RunIntervalMetric.distance,
              icon: const Icon(Icons.straighten, size: 16),
              tooltip: loc.runWorkoutStepMetricDistance,
            ),
            ButtonSegment(
              value: RunIntervalMetric.time,
              icon: const Icon(Icons.timer_outlined, size: 16),
              tooltip: loc.runWorkoutStepMetricTime,
            ),
          ],
          selected: {metric},
          onSelectionChanged: (selection) => onMetricChanged(selection.first),
        ),
      ],
    );
  }
}

/// One step, or one repeated block drawn as a bracket. Before this, `8x 400 m`
/// and `8x 1:30` sat in two separate rows and read as sixteen efforts.
class _BlockTile extends StatelessWidget {
  final int index;
  final RunStepBlock block;
  final ValueChanged<RunWorkoutStep> onEditStep;
  final ValueChanged<RunWorkoutStep> onDeleteStep;
  final VoidCallback onDeleteBlock;

  const _BlockTile({
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
        borderRadius: BorderRadius.circular(12),
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
                  tooltip: loc.runWorkoutStepDelete,
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
