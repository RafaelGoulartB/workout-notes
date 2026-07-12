import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import '../../repositories/workout_repository.dart';
import '../../models/exercise_with_sets.dart';
import '../../widgets/exercise_picker_sheet.dart';

/// Screen for editing a completed (or in-progress) workout.
///
/// The user can:
/// - Add, remove, reorder and edit exercises & their sets.
/// - Change the workout date (day) and adjust the start and end times so
///   that the resulting `duration_seconds` reflects the user's intent.
///
/// All edits are persisted through [WorkoutRepository]. The duration is
/// recomputed server-side in `updateWorkoutTimes` based on the chosen
/// start and end times.
class EditWorkoutScreen extends StatefulWidget {
  final String workoutId;
  const EditWorkoutScreen({super.key, required this.workoutId});

  @override
  State<EditWorkoutScreen> createState() => _EditWorkoutScreenState();
}

class _EditWorkoutScreenState extends State<EditWorkoutScreen> {
  final _workoutRepo = WorkoutRepository();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  Map<String, dynamic>? _workout;
  List<ExerciseWithSets> _exercises = [];
  bool _isLoading = true;

  DateTime? _startTime;
  DateTime? _endTime;
  DateTime _workoutDate = DateTime.now();

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
          categoryId: entry['category_id'] as String?,
          categoryName: entry['category_name'] as String? ?? '',
          categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
          sets: sets,
          restTimeSeconds: (entry['rest_time_seconds'] as int?) ?? 90,
        ),
      );
    }

    final startStr = _workout!['start_time'] as String?;
    final endStr = _workout!['end_time'] as String?;
    final dateStr = _workout!['date'] as String?;

    if (mounted) {
      setState(() {
        _exercises = exercises;
        _isLoading = false;
        _workoutDate = dateStr != null
            ? DateTime.parse(dateStr)
            : DateTime.now();
        _startTime = startStr != null ? DateTime.parse(startStr) : null;
        _endTime = endStr != null ? DateTime.parse(endStr) : null;
      });
    }
  }

  int get _totalSets =>
      _exercises.fold<int>(0, (sum, e) => sum + e.sets.length);

  int get _durationSeconds {
    if (_startTime == null || _endTime == null) return 0;
    final diff = _endTime!.difference(_startTime!).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get _hasUnsavedTimeEdits {
    if (_workout == null) return false;
    final origStart = _workout!['start_time'] as String?;
    final origEnd = _workout!['end_time'] as String?;
    final origDate = _workout!['date'] as String?;

    if (_workoutDate.toIso8601String().substring(0, 10) != origDate) {
      return true;
    }
    final curStartIso = _startTime?.toIso8601String();
    final curEndIso = _endTime?.toIso8601String();
    return curStartIso != origStart || curEndIso != origEnd;
  }

  Future<void> _pickDate() async {
    final loc = AppLocalizations.of(context)!;
    final picked = await showDatePicker(
      context: context,
      initialDate: _workoutDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: loc.editWorkoutSelectDate,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _workoutDate = picked;
      // Keep the time-of-day component, but move the start/end to the new day.
      if (_startTime != null) {
        _startTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _startTime!.hour,
          _startTime!.minute,
        );
      }
      if (_endTime != null) {
        _endTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _endTime!.hour,
          _endTime!.minute,
        );
      }
    });
  }

  Future<void> _pickStartDateTime() async {
    final loc = AppLocalizations.of(context)!;
    final initial =
        _startTime ??
        DateTime(_workoutDate.year, _workoutDate.month, _workoutDate.day, 8, 0);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: loc.editWorkoutSelectDate,
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: loc.editWorkoutSelectTime,
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _workoutDate = pickedDate;
      _startTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      // If end is set and is now before start, push it after start by 1 hour.
      if (_endTime != null && !_endTime!.isAfter(_startTime!)) {
        _endTime = _startTime!.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickEndDateTime() async {
    final loc = AppLocalizations.of(context)!;
    final base = _endTime ?? _startTime ?? DateTime.now();
    final initial = base.isBefore(_workoutDate)
        ? DateTime(
            _workoutDate.year,
            _workoutDate.month,
            _workoutDate.day,
            9,
            0,
          )
        : base;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: loc.editWorkoutSelectDate,
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      helpText: loc.editWorkoutSelectTime,
    );
    if (pickedTime == null || !mounted) return;

    final newEnd = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      _endTime = newEnd;
    });
  }

  Future<void> _save() async {
    final loc = AppLocalizations.of(context)!;
    if (_startTime != null && _endTime != null) {
      if (!_endTime!.isAfter(_startTime!)) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(loc.editWorkoutEndAfterStart),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    // Persist date.
    await _workoutRepo.updateWorkoutDate(widget.workoutId, _workoutDate);
    // Persist start/end (and recomputed duration).
    await _workoutRepo.updateWorkoutTimes(
      widget.workoutId,
      startTime: _startTime,
      endTime: _endTime,
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

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
        _scaffoldMessengerKey.currentState?.showSnackBar(
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
    double? lastDistance;
    int? lastTimeSeconds;
    bool lastWarmup = false;
    if (exercise.sets.isNotEmpty) {
      final last = exercise.sets.last;
      lastWeight = (last['weight'] as num?)?.toDouble();
      lastReps = (last['reps'] as int?);
      lastDistance = (last['distance'] as num?)?.toDouble();
      lastTimeSeconds = (last['time_seconds'] as int?);
      lastWarmup = (last['is_warmup'] as int?) == 1;
    }

    await _workoutRepo.addSet(
      exerciseEntryId: exercise.entryId,
      weight: lastWeight,
      reps: lastReps,
      distance: lastDistance,
      timeSeconds: lastTimeSeconds,
      isWarmup: lastWarmup,
    );
    await _load();
    if (mounted) setState(() {});
  }

  Future<void> _deleteSet(String setId) async {
    await _workoutRepo.deleteSet(setId);
    await _load();
    if (mounted) setState(() {});
  }

  Future<void> _editSetDialog(ExerciseWithSets exercise, int setIndex) async {
    final loc = AppLocalizations.of(context)!;
    final set = exercise.sets[setIndex];
    final weightCtl = TextEditingController(
      text: (set['weight'] as num?)?.toStringAsFixed(1) ?? '',
    );
    final repsCtl = TextEditingController(
      text: (set['reps'] as int?)?.toString() ?? '',
    );
    final rpeCtl = TextEditingController(
      text: (set['rpe'] as num?)?.toStringAsFixed(1) ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${exercise.localizedName(loc)} — #${setIndex + 1}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightCtl,
              decoration: InputDecoration(
                labelText: loc.activeWorkoutWeight,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repsCtl,
              decoration: InputDecoration(
                labelText: loc.activeWorkoutReps,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rpeCtl,
              decoration: InputDecoration(
                labelText: loc.workoutDetailRpe,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.commonSave),
          ),
        ],
      ),
    );

    if (result == true) {
      await _workoutRepo.updateSet(
        set['id'] as String,
        weight: double.tryParse(weightCtl.text),
        reps: int.tryParse(repsCtl.text),
        rpe: double.tryParse(rpeCtl.text),
      );
      await _load();
      if (mounted) setState(() {});
    }
  }

  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final reordered = List<ExerciseWithSets>.from(_exercises);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _exercises = reordered);

    final orderedIds = reordered.map((e) => e.entryId).toList();
    try {
      await _workoutRepo.reorderWorkoutExercises(widget.workoutId, orderedIds);
    } catch (e) {
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Erro ao reordenar: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

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
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc.editWorkoutTitle),
              if (_exercises.isNotEmpty)
                Text(
                  '${_exercises.length} ${loc.commonExercises} • $_totalSets ${loc.commonSets}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(
                loc.commonSave,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildDateTimeCard(theme, loc),
                  const Divider(height: 1),
                  Expanded(
                    child: _exercises.isEmpty
                        ? _buildEmptyState(theme, loc)
                        : _buildExercisesList(theme, loc),
                  ),
                  if (_exercises.isNotEmpty)
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: FilledButton.icon(
                          onPressed: _pickExercise,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(loc.editWorkoutAddExercise),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildDateTimeCard(ThemeData theme, AppLocalizations loc) {
    final dateStr = DateFormat(
      Intl.defaultLocale?.startsWith('pt') == true
          ? "d 'de' MMMM 'de' yyyy"
          : 'MMMM d, yyyy',
      Intl.defaultLocale,
    ).format(_workoutDate);
    final timeStr = DateFormat('HH:mm', Intl.defaultLocale);
    final startStr = _startTime != null ? timeStr.format(_startTime!) : '—';
    final endStr = _endTime != null ? timeStr.format(_endTime!) : '—';
    final durSec = _durationSeconds;
    final durStr = durSec > 0 ? '${durSec ~/ 60}min ${durSec % 60}s' : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                loc.editWorkoutDateTime,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withAlpha(100),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(dateStr, style: theme.textTheme.bodyLarge),
                  ),
                  Icon(Icons.edit, size: 16, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  icon: Icons.play_arrow,
                  iconColor: Colors.green,
                  label: loc.editWorkoutStart,
                  value: startStr,
                  onTap: _pickStartDateTime,
                  theme: theme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TimeField(
                  icon: Icons.stop,
                  iconColor: Colors.red,
                  label: loc.editWorkoutEnd,
                  value: endStr,
                  onTap: _pickEndDateTime,
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${loc.editWorkoutDuration}: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                durStr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_hasUnsavedTimeEdits) ...[
            const SizedBox(height: 6),
            Text(
              loc.reorderHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontStyle: FontStyle.italic,
                fontSize: 11,
              ),
            ),
          ],
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
              label: Text(loc.editWorkoutAddExercise),
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
      buildDefaultDragHandles: false,
      proxyDecorator: _dragProxyDecorator,
      onReorderItem: _onReorderItem,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            ...ex.sets.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              final isWarmup = (s['is_warmup'] as int?) == 1;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _deleteSet(s['id'] as String),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isWarmup
                              ? Colors.orange.withAlpha(30)
                              : theme.colorScheme.surfaceContainerHighest,
                        ),
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
                      child: GestureDetector(
                        onTap: () => _editSetDialog(ex, i),
                        child: Text(
                          (s['weight'] as num?)?.toStringAsFixed(1) ?? '-',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: () => _editSetDialog(ex, i),
                        child: Text(
                          (s['reps'] as int?)?.toString() ?? '-',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: () => _editSetDialog(ex, i),
                        child: Text(
                          (s['rpe'] as num?)?.toStringAsFixed(1) ?? '-',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
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
}

class _TimeField extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;
  final ThemeData theme;

  const _TimeField({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(100),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
