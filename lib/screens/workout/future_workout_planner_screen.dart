import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/widgets/exercise_picker_sheet.dart';
import 'package:workout_notes/widgets/workout/set_editor_fields.dart';
import '../../repositories/workout_repository.dart';
import '../../repositories/routine_repository.dart';
import '../../models/exercise_with_sets.dart';

/// Screen for planning/editing a future workout.
/// Similar to WorkoutDetailScreen but tailored for future dates:
/// no "continue workout" button, no timer, focuses on editing exercises and sets.
class FutureWorkoutPlannerScreen extends StatefulWidget {
  final String workoutId;
  const FutureWorkoutPlannerScreen({super.key, required this.workoutId});

  @override
  State<FutureWorkoutPlannerScreen> createState() =>
      _FutureWorkoutPlannerScreenState();
}

class _FutureWorkoutPlannerScreenState
    extends State<FutureWorkoutPlannerScreen> {
  final _workoutRepo = WorkoutRepository();
  final _routineRepo = RoutineRepository();
  Map<String, dynamic>? _workout;
  List<ExerciseWithSets> _exercises = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _workout = await _workoutRepo.getWorkout(widget.workoutId);
    if (_workout == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final entries = await _workoutRepo.getWorkoutExercises(widget.workoutId);
    final exercises = <ExerciseWithSets>[];
    for (final entry in entries) {
      final sets = await _workoutRepo.getExerciseSets(entry['id'] as String);
      exercises.add(
        ExerciseWithSets(
          entryId: entry['id'] as String,
          exerciseId: entry['exercise_id'] as String? ?? '',
          name: entry['exercise_name'] as String? ?? '',
          localeKey: entry['exercise_locale_key'] as String?,
          exerciseType: entry['exercise_type'] as String? ?? 'weightReps',
          weightIncrement: (entry['weight_increment'] as num?)?.toDouble() ?? 1,
          categoryId: entry['category_id'] as String?,
          categoryName: entry['category_name'] as String? ?? '',
          categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
          sets: sets,
          restTimeSeconds: (entry['rest_time_seconds'] as int?) ?? 90,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _exercises = exercises;
        _isLoading = false;
      });
    }
  }

  int get _totalSets =>
      _exercises.fold<int>(0, (sum, e) => sum + e.sets.length);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _workout != null
              ? DateFormat(
                  Intl.defaultLocale?.startsWith('pt') == true
                      ? "d 'de' MMMM"
                      : 'MMMM d',
                  Intl.defaultLocale,
                ).format(DateTime.parse(_workout!['date'] as String))
              : '',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: loc.activeWorkoutAddExercise,
            onPressed: _pickExercise,
          ),
          PopupMenuButton(
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'import_routine',
                child: Row(
                  children: [
                    const Icon(Icons.repeat_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(loc.activeWorkoutImportRoutine),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit_date',
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: 8),
                    Text(loc.workoutDetailEditDate),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    const Icon(Icons.content_copy, size: 18),
                    const SizedBox(width: 8),
                    Text(loc.workoutDetailCopy),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(
                      loc.workoutDetailDelete,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (v) {
              if (v == 'import_routine') _importFromRoutine();
              if (v == 'edit_date') _editDate();
              if (v == 'copy') _copyWorkout();
              if (v == 'delete') _deleteWorkout();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header info
                _buildHeader(theme, loc),

                const Divider(height: 1),

                // Exercises list
                Expanded(
                  child: _exercises.isEmpty
                      ? _buildEmptyState(theme, loc)
                      : _buildExercisesList(theme, loc),
                ),

                // Bottom add button (when exercises exist)
                if (_exercises.isNotEmpty)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: FilledButton.icon(
                        onPressed: _pickExercise,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(loc.activeWorkoutAddExercise),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations loc) {
    if (_workout == null) return const SizedBox.shrink();
    final dateStr = DateFormat(
      Intl.defaultLocale?.startsWith('pt') == true
          ? "EEEE, d 'de' MMMM 'de' yyyy"
          : 'EEEE, MMMM d, yyyy',
      Intl.defaultLocale,
    ).format(DateTime.parse(_workout!['date'] as String));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.edit_calendar,
              color: theme.colorScheme.onTertiaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_exercises.length} ${loc.commonExercises}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_totalSets ${loc.commonSets}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            dateStr[0].toUpperCase() + dateStr.substring(1),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations loc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 16),
            Text(
              loc.activeWorkoutEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.activeWorkoutEmptySubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickExercise,
              icon: const Icon(Icons.add, size: 18),
              label: Text(loc.activeWorkoutAddExercise),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _importFromRoutine,
              icon: const Icon(Icons.repeat_outlined, size: 18),
              label: Text(loc.activeWorkoutImportRoutine),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExercisesList(ThemeData theme, AppLocalizations loc) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _exercises.length,
      onReorderItem: _onReorderItem,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      itemBuilder: (ctx, i) {
        final ex = _exercises[i];
        return _buildExerciseCard(ex, i, theme, loc);
      },
    );
  }

  Widget _buildExerciseCard(
    ExerciseWithSets ex,
    int index,
    ThemeData theme,
    AppLocalizations loc,
  ) {
    return Card(
      key: ValueKey(ex.entryId),
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise header with drag handle
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: ex.categoryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ex.localizedName(loc),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ex.localizedCategory(loc),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Delete button
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _removeExercise(ex),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                // Drag handle
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.drag_handle, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Sets table header
            if (ex.sets.isNotEmpty) ...[
              Row(
                children: [
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 2,
                    child: Text(
                      loc.workoutDetailSetNumber,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      loc.workoutDetailWeight,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      loc.commonReps,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      loc.workoutDetailRpe,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 4),
            ],

            // Sets rows
            ...ex.sets.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              final isWarmup = (s['is_warmup'] as int?) == 1;
              return GestureDetector(
                onTap: () => _editSetDialog(ex, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isWarmup
                              ? Colors.orange.withAlpha(30)
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: Center(
                          child: Text(
                            isWarmup ? 'W' : '${i + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isWarmup ? Colors.orange : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: Text(
                          (s['weight'] as num?)?.toStringAsFixed(1) ?? '-',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          (s['reps'] as int?)?.toString() ?? '-',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          (s['rpe'] as num?)?.toStringAsFixed(1) ?? '-',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Add set button
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _addSet(ex),
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                loc.activeWorkoutAddSet,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== ACTIONS =====================

  Future<void> _pickExercise() async {
    final currentExerciseIds = _exercises.map((e) => e.exerciseId).toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (_) => ExercisePickerSheet(
        currentExerciseIds: currentExerciseIds,
        onExerciseAdded: (exercise) async {
          await _addExerciseToWorkout(exercise);
        },
        onExerciseRemoved: (exercise) async {
          final exerciseId = exercise['id'] as String;
          await _workoutRepo.removeExerciseEntryFromWorkout(
            widget.workoutId,
            exerciseId,
          );
          if (mounted) {
            setState(() {
              _exercises.removeWhere((e) => e.exerciseId == exerciseId);
            });
          }
        },
      ),
    );
  }

  Future<void> _addExerciseToWorkout(Map<String, dynamic> exercise) async {
    final exerciseId = exercise['id'] as String;
    final loc = AppLocalizations.of(context)!;
    final rt = exercise['default_rest_time'] as int?;

    final entryId = await _workoutRepo.addExerciseToWorkout(
      widget.workoutId,
      exerciseId,
      restTimeSeconds: rt,
    );

    final sets = await _workoutRepo.getExerciseSets(entryId);
    if (mounted) {
      setState(() {
        _exercises.add(
          ExerciseWithSets(
            entryId: entryId,
            exerciseId: exerciseId,
            name: ExerciseLocaleHelper.exerciseName(loc, exercise),
            localeKey: exercise['locale_key'] as String?,
            exerciseType: exercise['type'] as String? ?? 'weightReps',
            weightIncrement:
                (exercise['weight_increment'] as num?)?.toDouble() ?? 1,
            categoryId: exercise['category_id'] as String?,
            categoryName: ExerciseLocaleHelper.categoryName(loc, exercise),
            categoryColor: Color(
              exercise['category_color'] as int? ?? 0xFF757575,
            ),
            sets: sets,
            restTimeSeconds: rt ?? 90,
          ),
        );
      });
    }
  }

  Future<void> _removeExercise(ExerciseWithSets ex) async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.activeWorkoutRemoveExercise),
        content: Text(
          loc.activeWorkoutRemoveExerciseContent(ex.localizedName(loc)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              loc.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _workoutRepo.deleteExerciseEntry(ex.entryId);
      if (mounted) {
        setState(() {
          _exercises.removeWhere((e) => e.entryId == ex.entryId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.activeWorkoutRemoved(ex.localizedName(loc))),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addSet(ExerciseWithSets exercise) async {
    double? lastWeight;
    int? lastReps;
    bool lastWarmup = false;
    if (exercise.sets.isNotEmpty) {
      final last = exercise.sets.last;
      lastWeight = (last['weight'] as num?)?.toDouble();
      lastReps = (last['reps'] as int?);
      lastWarmup = (last['is_warmup'] as int?) == 1;
    }

    await _workoutRepo.addSet(
      exerciseEntryId: exercise.entryId,
      weight: lastWeight,
      reps: lastReps,
      isWarmup: lastWarmup,
    );
    await _load();
    if (mounted) setState(() {});
  }

  Future<void> _editSetDialog(ExerciseWithSets exercise, int setIndex) async {
    final loc = AppLocalizations.of(context)!;
    final set = exercise.sets[setIndex];
    double weight = (set['weight'] as num?)?.toDouble() ?? 0;
    int reps = (set['reps'] as num?)?.toInt() ?? 0;
    double distance = (set['distance'] as num?)?.toDouble() ?? 0;
    int timeSeconds = (set['time_seconds'] as num?)?.toInt() ?? 0;
    double? rpe = (set['rpe'] as num?)?.toDouble();
    bool isWarmup = (set['is_warmup'] as int?) == 1;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurfaceVariant.withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${exercise.localizedName(loc)} · ${loc.workoutDetailSetNumber} ${setIndex + 1}',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.whatshot,
                      size: 16,
                      color: isWarmup
                          ? Colors.orange
                          : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(loc.activeWorkoutWarmup),
                    const Spacer(),
                    Switch.adaptive(
                      value: isWarmup,
                      onChanged: (value) =>
                          setSheetState(() => isWarmup = value),
                    ),
                  ],
                ),
                WorkoutSetFieldControls(
                  exerciseType: exercise.exerciseType,
                  weight: weight,
                  reps: reps,
                  distance: distance,
                  timeSeconds: timeSeconds,
                  weightIncrement: exercise.weightIncrement,
                  showPace: true,
                  onWeightChanged: (value) =>
                      setSheetState(() => weight = value),
                  onRepsChanged: (value) => setSheetState(() => reps = value),
                  onDistanceChanged: (value) =>
                      setSheetState(() => distance = value),
                  onTimeChanged: (value) =>
                      setSheetState(() => timeSeconds = value),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          'RPE',
                          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...List.generate(11, (i) {
                        final value = i.toDouble();
                        final selected = rpe != null && rpe!.round() == i;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: GestureDetector(
                            onTap: () => setSheetState(() {
                              rpe = rpe == value ? null : value;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(
                                          ctx,
                                        ).colorScheme.outlineVariant,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  i == 0 ? '-' : '$i',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: selected
                                        ? Theme.of(ctx).colorScheme.onPrimary
                                        : Theme.of(ctx).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, 'cancel'),
                        child: Text(loc.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: loc.commonDelete,
                      onPressed: () => Navigator.pop(ctx, 'delete'),
                      color: Theme.of(ctx).colorScheme.error,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, 'save'),
                        child: Text(loc.commonSave),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == 'delete') {
      await _workoutRepo.deleteSet(set['id'] as String);
      await _load();
      if (mounted) setState(() {});
    } else if (result == 'save') {
      await _workoutRepo.updateSet(
        set['id'] as String,
        weight: weight,
        reps: reps,
        distance: distance,
        timeSeconds: timeSeconds,
        rpe: rpe,
        isWarmup: isWarmup,
      );
      await _load();
      if (mounted) setState(() {});
    }
  }

  Future<void> _onReorderItem(int oldIndex, int newIndex) {
    final exercise = _exercises.removeAt(oldIndex);
    _exercises.insert(newIndex, exercise);

    final orderedIds = _exercises.map((e) => e.entryId).toList();
    _workoutRepo.reorderWorkoutExercises(widget.workoutId, orderedIds);
    setState(() {});
    return Future.value();
  }

  Future<void> _importFromRoutine() async {
    final loc = AppLocalizations.of(context)!;
    final routines = await _routineRepo.getRoutines();
    if (!mounted) return;
    if (routines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.activeWorkoutNoRoutineFound),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final routineId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildRoutinePicker(routines),
    );
    if (routineId == null || !mounted) return;

    final days = await _routineRepo.getRoutineDays(routineId);
    if (!mounted) return;
    if (days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.activeWorkoutNoRoutineDays),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final routineName =
        routines.firstWhere((r) => r['id'] == routineId)['name'] as String;
    final dayId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildDayPicker(ctx, days, routineName),
    );
    if (dayId == null || !mounted) return;

    await _workoutRepo.importRoutineDayToWorkout(widget.workoutId, dayId);
    await _load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.activeWorkoutRoutineImported),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildRoutinePicker(List<Map<String, dynamic>> routines) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            loc.activeWorkoutSelectRoutine,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ListView.separated(
              itemCount: routines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final routine = routines[i];
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.repeat,
                      color: theme.colorScheme.onSecondaryContainer,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    routine['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, routine['id'] as String),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayPicker(
    BuildContext sheetContext,
    List<Map<String, dynamic>> days,
    String routineName,
  ) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(loc.activeWorkoutBack),
              ),
            ],
          ),
          Text(
            routineName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.activeWorkoutSelectDay,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ListView.separated(
              itemCount: days.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final day = days[i];
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.today,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    day['name'] as String? ?? 'Dia ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.download),
                  onTap: () => Navigator.pop(ctx, day['id'] as String),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDate() async {
    if (_workout == null) return;
    final loc = AppLocalizations.of(context)!;
    final currentDate = DateTime.parse(_workout!['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: loc.workoutDetailSelectDate,
    );
    if (newDate == null || !mounted) return;

    await _workoutRepo.updateWorkoutDate(widget.workoutId, newDate);
    _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.workoutDetailDateChanged),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyWorkout() async {
    if (_workout == null) return;
    final loc = AppLocalizations.of(context)!;
    final currentDate = DateTime.parse(_workout!['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: loc.workoutDetailCopy,
    );
    if (newDate == null || !mounted) return;

    final newWorkoutId = await _workoutRepo.copyWorkoutToDate(
      widget.workoutId,
      newDate,
    );
    if (!mounted) return;

    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.workoutDetailCopyDateChanged),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: loc.workoutDetailGoToWorkout,
          onPressed: () {
            navigator.pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    FutureWorkoutPlannerScreen(workoutId: newWorkoutId),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteWorkout() async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.workoutDetailDeleteConfirm),
        content: Text(loc.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              loc.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _workoutRepo.deleteWorkout(widget.workoutId);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }
}
