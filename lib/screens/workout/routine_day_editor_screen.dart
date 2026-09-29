import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/widgets/exercise_picker_sheet.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/routines/routine_exercise_card.dart';
import 'package:workout_notes/widgets/strength/routines/routine_set_sheets.dart';
import 'package:workout_notes/widgets/strength/routines/routine_sheets.dart';

/// Full-screen editor for a routine day.
/// Allows adding/removing exercises and managing predefined sets,
/// using the same set editing controls as the active workout.
class RoutineDayEditorScreen extends StatefulWidget {
  final String routineDayId;
  final String routineId;
  final String dayName;
  final String? dayNotes;

  const RoutineDayEditorScreen({
    super.key,
    required this.routineDayId,
    required this.routineId,
    required this.dayName,
    this.dayNotes,
  });

  @override
  State<RoutineDayEditorScreen> createState() => _RoutineDayEditorScreenState();
}

class _RoutineDayEditorScreenState extends State<RoutineDayEditorScreen> {
  final _routineRepo = RoutineRepository();
  List<Map<String, dynamic>> _exercises = [];
  Map<String, List<Map<String, dynamic>>> _predefinedSets = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exercises = await _routineRepo.getRoutineExercises(
      widget.routineDayId,
    );
    final sets = await _routineRepo.getPredefinedSetsForDay(
      widget.routineDayId,
    );
    if (!mounted) return;
    setState(() {
      _exercises = exercises;
      _predefinedSets = sets;
      _isLoading = false;
    });
  }

  RoutineDaySummary get _summary => StrengthRoutineSummaryBuilder.buildDay(
    day: {
      'id': widget.routineDayId,
      'routine_id': widget.routineId,
      'name': widget.dayName,
      'notes': widget.dayNotes,
      'order_index': 0,
    },
    rows: StrengthRoutineSummaryBuilder.setRowsFromDay(
      _exercises,
      _predefinedSets,
    ),
    lastTrainedAt: null,
  );

  /// Handles drag-to-reorder of routine exercises. Updates the local list
  /// optimistically and persists the new `order_index` values in a single
  /// batch transaction.
  ///
  /// The framework's `onReorderItem` callback already adjusts `newIndex` to
  /// account for the item removed at `oldIndex`, so we use `newIndex`
  /// directly as the insert position.
  Future<void> _onReorderExercises(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final reordered = List<Map<String, dynamic>>.from(_exercises);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _exercises = reordered);

    final orderedIds = reordered
        .map((e) => e['id'] as String)
        .toList(growable: false);
    try {
      await _routineRepo.reorderRoutineExercises(
        widget.routineDayId,
        orderedIds,
      );
    } catch (e) {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.commonReorderError(e.toString()),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Provides a subtle visual lift + shadow while dragging a routine
  /// exercise card during reorder, matching Material 3 guidance.
  Widget _dragProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return Material(
          elevation: 8 * t,
          color: Colors.transparent,
          shadowColor: Colors.black.withAlpha(80),
          borderRadius: BorderRadius.circular(RunUi.cardRadius),
          child: child,
        );
      },
      child: child,
    );
  }

  /// Resolves exercise name from aliased JOIN columns.
  String _resolveExerciseName(Map<String, dynamic> ex) =>
      ExerciseLocaleHelper.exerciseName(AppLocalizations.of(context)!, {
        'locale_key': ex['exercise_locale_key'],
        'name': ex['exercise_name'],
      });

  // ===================== EXERCISE MANAGEMENT =====================

  Future<void> _openExercisePicker() async {
    final currentExerciseIds = _exercises
        .map((e) => e['exercise_id'] as String)
        .toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (_) => ExercisePickerSheet(
        currentExerciseIds: currentExerciseIds,
        onExerciseAdded: (exercise) async {
          await _routineRepo.addRoutineExercise(
            widget.routineDayId,
            exercise['id'] as String,
            restTimeSeconds: (exercise['default_rest_time'] as int?),
          );
          _load();
        },
        onExerciseRemoved: (exercise) async {
          final exerciseId = exercise['id'] as String;
          final routineExercise = _exercises.firstWhere(
            (e) => e['exercise_id'] == exerciseId,
            orElse: () => <String, dynamic>{},
          );
          if (routineExercise.isNotEmpty) {
            await _routineRepo.removeRoutineExercise(
              routineExercise['id'] as String,
            );
            _load();
          }
        },
      ),
    );
  }

  Future<void> _removeExercise(Map<String, dynamic> ex) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await confirmRoutineDestructive(
      context,
      title: loc.activeWorkoutRemoveExercise,
      content: loc.routineRemoveExerciseContent(_resolveExerciseName(ex)),
    );
    if (!confirmed) return;
    await _routineRepo.removeRoutineExercise(ex['id'] as String);
    if (mounted) _load();
  }

  void _openExerciseDetails(Map<String, dynamic> ex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseDetailTabsScreen(
          exerciseId: ex['exercise_id'] as String,
          exerciseName: _resolveExerciseName(ex),
        ),
      ),
    );
  }

  Future<void> _editDay() async {
    final loc = AppLocalizations.of(context)!;
    final details = await showRoutineDetailsSheet(
      context,
      title: loc.routinesEditDay,
      nameLabel: loc.routinesDayName,
      nameHint: loc.routinesDayNameHint,
      submitLabel: loc.commonSave,
      initialName: widget.dayName,
      withNotes: true,
      initialNotes: widget.dayNotes ?? '',
      notesLabel: loc.routinesNotes,
      notesHint: loc.routinesNotesHint,
    );
    if (details == null) return;
    await _routineRepo.updateRoutineDay(
      widget.routineDayId,
      name: details.name,
      notes: details.notes.isEmpty ? null : details.notes,
    );
    if (!mounted) return;
    // Pop with result to refresh the parent screen
    Navigator.pop(context, true);
  }

  Future<void> _deleteDay() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await confirmRoutineDestructive(
      context,
      title: loc.routinesDeleteConfirm(widget.dayName),
      content: loc.routineDeleteDayContent,
    );
    if (!confirmed) return;
    await _routineRepo.deleteRoutineDay(widget.routineDayId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.routineDayDeleted),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context, true);
  }

  // ===================== REST TIME =====================

  Future<void> _changeRestTime(Map<String, dynamic> exercise) async {
    final seconds = await showRoutineRestSheet(
      context,
      currentSeconds: (exercise['rest_time_seconds'] as int?) ?? 90,
    );
    if (seconds == null) return;
    await _routineRepo.updateRoutineExerciseRestTime(
      exercise['id'] as String,
      seconds,
    );
    if (mounted) _load();
  }

  // ===================== PREDEFINED SET MANAGEMENT =====================

  Future<void> _addPredefinedSet(Map<String, dynamic> exercise) async {
    final exId = exercise['id'] as String;
    final existingSets = _predefinedSets[exId] ?? [];

    if (existingSets.isNotEmpty) {
      // Copy last set values silently — no dialog needed
      final last = existingSets.last;
      await _routineRepo.addPredefinedSet(
        exId,
        weight: (last['weight'] as num?)?.toDouble(),
        reps: (last['reps'] as int?),
        distance: (last['distance'] as num?)?.toDouble(),
        timeSeconds: (last['time_seconds'] as int?),
        isWarmup: (last['is_warmup'] as int?) == 1,
      );
      if (mounted) _load();
      return;
    }

    // No previous set — open editor with defaults
    final result = await showRoutineSetEditor(
      context,
      exerciseType: exercise['exercise_type'] as String? ?? 'weightReps',
      weightIncrement: (exercise['weight_increment'] as num?)?.toDouble() ?? 1,
      exerciseName: _resolveExerciseName(exercise),
      setNumber: 1,
    );
    if (result == null) return;
    await _routineRepo.addPredefinedSet(
      exId,
      weight: result.weight,
      reps: result.reps,
      distance: result.distance,
      timeSeconds: result.timeSeconds,
      isWarmup: result.isWarmup,
    );
    if (mounted) _load();
  }

  Future<void> _editPredefinedSet(
    Map<String, dynamic> exercise,
    Map<String, dynamic> setData,
    int index,
  ) async {
    final result = await showRoutineSetEditor(
      context,
      exerciseType: exercise['exercise_type'] as String? ?? 'weightReps',
      weightIncrement: (exercise['weight_increment'] as num?)?.toDouble() ?? 1,
      exerciseName: _resolveExerciseName(exercise),
      weight: (setData['weight'] as num?)?.toDouble() ?? 0,
      reps: (setData['reps'] as int?) ?? 0,
      distance: (setData['distance'] as num?)?.toDouble() ?? 0,
      timeSeconds: (setData['time_seconds'] as int?) ?? 0,
      isWarmup: (setData['is_warmup'] as int?) == 1,
      setNumber: index,
    );
    if (result == null) return;
    await _routineRepo.updatePredefinedSet(
      setData['id'] as String,
      weight: result.weight,
      reps: result.reps,
      distance: result.distance,
      timeSeconds: result.timeSeconds,
      isWarmup: result.isWarmup,
    );
    if (mounted) _load();
  }

  Future<void> _deletePredefinedSet(String setId) async {
    await _routineRepo.deletePredefinedSet(setId);
    if (mounted) _load();
  }

  // ===================== BUILD =====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.dayName),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: loc.commonMoreOptions,
            onSelected: (value) {
              switch (value) {
                case 'edit_day':
                  _editDay();
                  break;
                case 'delete_day':
                  _deleteDay();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'edit_day',
                child: Text(loc.routinesEditDay),
              ),
              PopupMenuItem<String>(
                value: 'delete_day',
                child: Text(
                  loc.routinesDeleteDay,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exercises.isEmpty
          ? _buildEmptyState(theme, loc)
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverList.list(
                      children: [
                        RoutineDaySummaryCard(summary: _summary),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                          child: Text(
                            loc.routineDayReorderHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                    sliver: SliverReorderableList(
                      itemCount: _exercises.length,
                      proxyDecorator: _dragProxyDecorator,
                      onReorderStart: (_) => HapticFeedback.mediumImpact(),
                      onReorderItem: _onReorderExercises,
                      itemBuilder: (ctx, i) {
                        final ex = _exercises[i];
                        final id = ex['id'] as String;
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(id),
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RoutineExerciseCard(
                              exercise: ex,
                              sets: _predefinedSets[id] ?? const [],
                              actions: RoutineExerciseCardActions(
                                onRest: () => _changeRestTime(ex),
                                onDetails: () => _openExerciseDetails(ex),
                                onRemove: () => _removeExercise(ex),
                                onAddSet: () => _addPredefinedSet(ex),
                                onEditSet: (set, number) =>
                                    _editPredefinedSet(ex, set, number),
                                onRemoveSet: (set) =>
                                    _deletePredefinedSet(set['id'] as String),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _exercises.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openExercisePicker,
              icon: const Icon(Icons.add),
              label: Text(loc.routinesAddExercise),
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations loc) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center,
              size: 80,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 24),
            Text(
              loc.routinesNoExercises,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              loc.routinesNoExercisesHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openExercisePicker,
              icon: const Icon(Icons.add),
              label: Text(loc.routinesAddExercise),
            ),
          ],
        ),
      ),
    );
  }
}
