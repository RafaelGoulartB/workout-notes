part of 'active_workout_screen.dart';

/// Handles routine import, rest preferences, exercise picking, and deletion.
mixin _ActiveWorkoutRoutineActions
    on State<ActiveWorkoutScreen>, _ActiveWorkoutController {
  // ===================== REST =====================

  Future<void> _importFromRoutine() async {
    final ctx = context;
    final scaffoldMessenger = ScaffoldMessenger.of(ctx);
    final loc = AppLocalizations.of(ctx);
    final routines = await _routineRepo.getRoutines();
    if (routines.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.activeWorkoutNoRoutineFound,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final plannedRoutineIds = await _plannedRoutineIdsForToday();
    if (!mounted) return;
    final orderedRoutines = [...routines]
      ..sort((a, b) {
        final aPlanned = plannedRoutineIds.contains(a['id'] as String);
        final bPlanned = plannedRoutineIds.contains(b['id'] as String);
        if (aPlanned == bPlanned) return 0;
        return aPlanned ? -1 : 1;
      });
    final routineId = await showModalBottomSheet<String>(
      // ignore: use_build_context_synchronously
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildRoutinePicker(orderedRoutines, plannedRoutineIds),
    );
    if (routineId == null || !mounted) return;

    final days = await _routineRepo.getRoutineDays(routineId);
    if (days.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(loc!.activeWorkoutNoRoutineDays),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final routineName =
        routines.firstWhere((r) => r['id'] == routineId)['name'] as String;
    final dayId = await showModalBottomSheet<String>(
      // ignore: use_build_context_synchronously
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildDayPicker(ctx, days, routineName),
    );
    if (dayId == null || !mounted) return;

    final workoutId = _workoutId;
    if (workoutId == null) return;
    if (!mounted) return;
    await _workoutRepo.importRoutineDayToWorkout(workoutId, dayId);
    await _loadExercises();
    if (!mounted) return;
    setState(() {});
    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(loc!.activeWorkoutRoutineImported),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<Set<String>> _plannedRoutineIdsForToday() async {
    try {
      final repository = PeriodizationRepository();
      final phase = await repository.getEffectivePhase(DateTime.now());
      if (phase == null) return const {};
      final target = await repository.getEffectiveTarget(phase.id);
      return target?.routineIds.toSet() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  Widget _buildRoutinePicker(
    List<Map<String, dynamic>> routines,
    Set<String> plannedRoutineIds,
  ) {
    final theme = Theme.of(context);
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
            AppLocalizations.of(context)!.activeWorkoutSelectRoutine,
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
                final routineId = routine['id'] as String;
                final isPlanned = plannedRoutineIds.contains(routineId);
                return Container(
                  decoration: isPlanned
                      ? BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withAlpha(
                            100,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.colorScheme.primary.withAlpha(110),
                          ),
                        )
                      : null,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isPlanned
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isPlanned ? Icons.star_rounded : Icons.repeat,
                        color: isPlanned
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSecondaryContainer,
                        size: 20,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            routine['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isPlanned)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              AppLocalizations.of(
                                context,
                              )!.activeWorkoutPlanRoutine,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, routineId),
                  ),
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
                label: Text(AppLocalizations.of(context)!.activeWorkoutBack),
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
            AppLocalizations.of(context)!.activeWorkoutSelectDay,
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

  void _changeExerciseRestTime(ExerciseWithSets exercise, int currentRest) {
    final presets = [30, 60, 90, 120, 180];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.routinesRestTimeTitle,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              exercise.localizedName(AppLocalizations.of(context)!),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...presets.map(
                  (sec) => ChoiceChip(
                    label: Text(
                      sec >= 60 ? '${sec ~/ 60}min${sec % 60}s' : '${sec}s',
                    ),
                    selected: currentRest == sec,
                    onSelected: (_) {
                      _updateRestTimeAndClose(exercise, sec);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCustomRestTimeDialog(exercise);
                },
                icon: const Icon(Icons.edit),
                label: Text(AppLocalizations.of(context)!.activeWorkoutCustom),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomRestTimeDialog(ExerciseWithSets exercise) {
    final ctl = TextEditingController(
      text: exercise.restTimeSeconds.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.activeWorkoutCustomTime),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.commonSeconds,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ),
            const SizedBox(width: 8),
            const Text('s'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctl.text);
              if (v != null && v > 0) {
                _updateRestTimeAndClose(exercise, v);
                Navigator.pop(ctx);
              }
            },
            child: Text(AppLocalizations.of(context)!.activeWorkoutSetValue),
          ),
        ],
      ),
    );
  }

  void _updateRestTimeAndClose(ExerciseWithSets exercise, int seconds) async {
    await _workoutRepo.updateExerciseEntryRestTime(exercise.entryId, seconds);
    await _loadExercises();
    setState(() {});
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
          await addExercise(
            exercise['id'] as String,
            ExerciseLocaleHelper.exerciseName(
              AppLocalizations.of(context)!,
              exercise,
            ),
            ExerciseLocaleHelper.categoryName(
              AppLocalizations.of(context)!,
              exercise,
            ),
            Color(exercise['category_color'] as int? ?? 0xFF757575),
            restTimeSeconds: (exercise['default_rest_time'] as int?),
          );
        },
        onExerciseRemoved: (exercise) async {
          final exerciseId = exercise['id'] as String;
          await _workoutRepo.removeExerciseEntryFromWorkout(
            _workoutId!,
            exerciseId,
          );
          if (mounted) {
            await _loadExercises();
            if (!mounted) return;
            setState(() {});
          }
        },
      ),
    );
  }

  Future<void> _deleteWorkout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.commonConfirmDelete),
        content: Text(AppLocalizations.of(context)!.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.commonDelete,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && _workoutId != null) {
      // Stop any running timers
      _elapsedTimer?.cancel();
      _timerService.stop();
      NotificationService.instance.cancelWorkoutTimer();

      await _workoutRepo.deleteWorkout(_workoutId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.workoutHomeDeleteWorkout,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }
}
