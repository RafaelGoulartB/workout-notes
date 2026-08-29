part of 'active_workout_screen.dart';

/// Owns mutable workout state, timer coordination, and set mutations.
mixin _ActiveWorkoutController on State<ActiveWorkoutScreen> {
  final _workoutRepo = WorkoutRepository();
  final _routineRepo = RoutineRepository();
  final _settingsRepo = SettingsRepository();
  final _bodyRepo = BodyMeasurementRepository();
  final _timerService = RestTimerService.instance;
  final _uuid = const Uuid();
  bool _isLoading = true;
  String? _workoutId;

  // Timer tracking
  DateTime? _timerStart;
  DateTime? _timerEnd;
  Timer? _elapsedTimer; // periodic tick for live elapsed time
  String _elapsedStr = '00:00';
  bool _isPaused = false;
  DateTime? _pauseStart;

  // Settings
  bool _autoStartTimer = false;

  List<ExerciseWithSets> _exercises = [];
  Map<String, ExerciseVolumeComparison> _exerciseVolumeComparisons = {};
  List<CategoryVolumeComparison> _categoryVolumeComparisons = [];
  bool _isVolumeSummaryExpanded = false;

  /// Handles drag-to-reorder of exercises during an active workout.
  /// Updates the local list order optimistically and persists the new
  /// `order_index` values in a single batch transaction.
  ///
  /// The framework's `onReorderItem` callback already adjusts `newIndex` to
  /// account for the item removed at `oldIndex`, so we use `newIndex`
  /// directly as the insert position.
  Future<void> _onReorderExercises(int oldIndex, int newIndex) async {
    if (_workoutId == null) return;
    if (oldIndex == newIndex) return;

    final reordered = List<ExerciseWithSets>.from(_exercises);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    setState(() => _exercises = reordered);

    final orderedIds = reordered.map((e) => e.entryId).toList(growable: false);
    try {
      await _workoutRepo.reorderWorkoutExercises(_workoutId!, orderedIds);
    } catch (e) {
      // Roll back to the persisted order on failure.
      if (!mounted) return;
      await _loadExercises();
      if (!mounted) return;
      setState(() {});
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

  /// Provides a subtle visual lift + shadow while dragging an exercise
  /// card during reorder, matching Material 3 guidance.
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

  void _onTimerTick() {
    if (mounted) setState(() {});
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _timerStart != null && _timerEnd == null) {
        final elapsed = DateTime.now().difference(_timerStart!);
        final hours = elapsed.inHours;
        final minutes = elapsed.inMinutes.remainder(60);
        final seconds = elapsed.inSeconds.remainder(60);
        setState(() {
          _elapsedStr = hours > 0
              ? '${hours}h${minutes.toString().padLeft(2, '0')}min'
              : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        });
        // Update workout timer notification
        NotificationService.instance.showWorkoutTimer(_elapsedStr);
      }
    });
  }

  Future<void> _initialize() async {
    // Load settings
    final settings = await _settingsRepo.getAllSettings();
    _autoStartTimer = settings['auto_start_workout_timer'] == 'true';

    if (widget.workoutId != null) {
      await _loadExistingWorkout(widget.workoutId!);
    } else if (widget.routineDayId != null) {
      await _createFromRoutine();
    } else {
      await _createNewWorkout();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _createNewWorkout() async {
    final id = await _workoutRepo.createWorkout();
    _workoutId = id;
    // start_time is NOT set until user clicks "Iniciar"
  }

  Future<void> _loadExistingWorkout(String id) async {
    _workoutId = id;
    final workout = await _workoutRepo.getWorkout(id);
    if (workout != null) {
      final startStr = workout['start_time'] as String?;
      if (startStr != null) _timerStart = DateTime.parse(startStr);
      final endStr = workout['end_time'] as String?;
      if (endStr != null) _timerEnd = DateTime.parse(endStr);
      final pauseStr = workout['pause_start_time'] as String?;

      // If the app was closed while paused, treat the reopen as an implicit
      // resume: shift the start time forward by the elapsed pause duration
      // and clear the pause state so the pause time is not counted.
      if (pauseStr != null && _timerStart != null && _timerEnd == null) {
        final pauseStart = DateTime.parse(pauseStr);
        final pausedDuration = DateTime.now().difference(pauseStart);
        _timerStart = _timerStart!.add(pausedDuration);
        await _workoutRepo.clearWorkoutPause(_workoutId!, _timerStart!);
      }

      if (_timerStart != null && _timerEnd == null) {
        _startElapsedTimer();
      }
      if (_timerStart != null && _timerEnd != null) {
        _updateElapsedStr();
      }

      await _loadExercises();
    }
  }

  void _updateElapsedStr() {
    if (_timerStart == null) {
      _elapsedStr = '00:00';
      return;
    }
    final end = _timerEnd ?? DateTime.now();
    final elapsed = end.difference(_timerStart!);
    _elapsedStr = _formatDuration(elapsed);
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h${d.inMinutes.remainder(60).toString().padLeft(2, '0')}min';
    }
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _createFromRoutine() async {
    if (widget.routineDayId == null) return;
    final routineExercises = await _routineRepo.getRoutineExercises(
      widget.routineDayId!,
    );
    final exercises = <Map<String, dynamic>>[];

    for (final re in routineExercises) {
      final sets = await _routineRepo.getPredefinedSets(re['id'] as String);
      exercises.add({
        'exercise_id': re['exercise_id'],
        'notes': null,
        'sets': sets
            .map(
              (s) => {
                'weight': s['weight'],
                'reps': s['reps'],
                'distance': s['distance'],
                'time_seconds': s['time_seconds'],
                'is_warmup': s['is_warmup'],
              },
            )
            .toList(),
      });
    }
    final id = await _workoutRepo.createWorkout(
      routineId: widget.routineId,
      exercises: exercises,
    );
    _workoutId = id;
    await _loadExercises();
  }

  Future<void> _loadExercises() async {
    if (_workoutId == null) return;
    final entries = await _workoutRepo.getWorkoutExercises(_workoutId!);
    final loadedExercises = <ExerciseWithSets>[];
    for (final entry in entries) {
      final sets = List<Map<String, dynamic>>.from(
        await _workoutRepo.getExerciseSets(entry['id'] as String),
      );
      loadedExercises.add(
        ExerciseWithSets(
          entryId: entry['id'] as String,
          exerciseId: entry['exercise_id'] as String,
          name: entry['exercise_name'] as String? ?? '',
          localeKey: entry['exercise_locale_key'] as String?,
          categoryId: entry['category_id'] as String?,
          exerciseType: entry['exercise_type'] as String? ?? 'weightReps',
          weightIncrement: (entry['weight_increment'] as num?)?.toDouble() ?? 1,
          categoryName: entry['category_name'] as String? ?? '',
          categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
          sets: sets,
          restTimeSeconds: (entry['rest_time_seconds'] as int?) ?? 90,
        ),
      );
    }
    final exerciseComparisons = await _workoutRepo.getExerciseVolumeComparisons(
      _workoutId!,
    );
    final categoryComparisons = await _workoutRepo.getCategoryVolumeComparisons(
      _workoutId!,
    );
    _exercises = loadedExercises;
    _exerciseVolumeComparisons = {
      for (final comparison in exerciseComparisons)
        comparison.exerciseId: comparison,
    };
    _categoryVolumeComparisons = categoryComparisons;
  }

  // ===================== TIMER CARD ACTIONS =====================

  Future<void> _startTimer() async {
    if (_workoutId == null) return;
    final now = DateTime.now();
    _timerStart = now;
    _timerEnd = null;
    await _workoutRepo.startWorkoutTimer(_workoutId!);
    _startElapsedTimer();
    setState(() => _elapsedStr = '00:00');
    NotificationService.instance.showWorkoutTimer('00:00');
  }

  Future<void> _stopTimer() async {
    if (_workoutId == null) return;
    final now = DateTime.now();
    _timerEnd = now;
    _elapsedTimer?.cancel();
    await _workoutRepo.stopWorkoutTimer(_workoutId!);
    _updateElapsedStr();
    setState(() {});
    NotificationService.instance.cancelWorkoutTimer();
  }

  Future<void> _pauseTimer() async {
    if (_workoutId == null || _isPaused || _timerStart == null) return;
    _pauseStart = DateTime.now();
    _isPaused = true;
    _elapsedTimer?.cancel();
    // Persist the pause start so the pause time is not counted even if the
    // app is closed or reloaded before resuming.
    await _workoutRepo.setWorkoutPause(_workoutId!, _pauseStart!);
    setState(() {});
  }

  Future<void> _resumeTimer() async {
    if (_workoutId == null || !_isPaused || _pauseStart == null) return;
    final now = DateTime.now();
    final pausedDuration = now.difference(_pauseStart!);
    _timerStart = _timerStart!.add(pausedDuration);
    _pauseStart = null;
    _isPaused = false;
    // Persist the shifted start time and clear the pause state so the
    // adjustment survives an app reload.
    await _workoutRepo.clearWorkoutPause(_workoutId!, _timerStart!);
    _startElapsedTimer();
    setState(() {});
  }

  Future<void> _resetTimer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.activeWorkoutResetTimer),
        content: Text(
          AppLocalizations.of(context)!.activeWorkoutResetTimerContent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.activeWorkoutReset,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && _workoutId != null) {
      _timerStart = null;
      _timerEnd = null;
      _isPaused = false;
      _pauseStart = null;
      _elapsedTimer?.cancel();
      _elapsedStr = '00:00';
      await _workoutRepo.resetWorkoutTimer(_workoutId!);
      setState(() {});
      NotificationService.instance.cancelWorkoutTimer();
    }
  }

  // ===================== EXERCISE ACTIONS =====================

  Future<void> addExercise(
    String exerciseId,
    String name,
    String catName,
    Color catColor, {
    int? restTimeSeconds,
  }) async {
    if (_workoutId == null) return;
    final entryId = _uuid.v4();
    final db = await DatabaseHelper.instance.database;
    final rt = restTimeSeconds ?? 90;
    await db.insert('exercise_entries', {
      'id': entryId,
      'workout_id': _workoutId,
      'exercise_id': exerciseId,
      'order_index': _exercises.length,
      'rest_time_seconds': rt,
    });

    // Auto-populate sets from last workout (excluding current workout)
    if (_workoutId != null) {
      final lastSets = await _workoutRepo.getLastWorkoutSets(
        exerciseId,
        excludeWorkoutId: _workoutId,
      );
      for (final s in lastSets) {
        await _workoutRepo.addSet(
          exerciseEntryId: entryId,
          weight: (s['weight'] as num?)?.toDouble(),
          reps: (s['reps'] as int?),
          isWarmup: (s['is_warmup'] as int?) == 1,
        );
      }
    }

    await _loadExercises();
    setState(() {});
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
    await _loadExercises();
    setState(() {});
  }

  Future<void> _toggleSet(String setId) async {
    ExerciseWithSets? parentExercise;
    Map<String, dynamic>? theSet;
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        if (s['id'] == setId) {
          parentExercise = ex;
          theSet = s;
          break;
        }
      }
      if (parentExercise != null) break;
    }

    final wasComplete = (theSet?['is_complete'] as int?) == 1;
    await _workoutRepo.toggleSetComplete(setId);
    await _loadExercises();
    setState(() {});

    if (!wasComplete && parentExercise != null && mounted) {
      // Check if all sets are now complete (this was the last one)
      bool allComplete = true;
      for (final ex in _exercises) {
        for (final s in ex.sets) {
          if ((s['is_complete'] as int?) != 1) {
            allComplete = false;
            break;
          }
        }
        if (!allComplete) break;
      }

      // If this was the last set, cancel any active rest timer
      if (allComplete) {
        if (_timerService.isActive) {
          _timerService.stop();
        }
      } else {
        // Auto-start rest timer for next set
        _timerService.start(parentExercise.restTimeSeconds);
      }

      // Auto-start workout timer if enabled and not started
      if (_autoStartTimer && _timerStart == null && _timerEnd == null) {
        await _startTimer();
      }

      // Auto-stop workout timer if all sets are now complete
      if (_autoStartTimer &&
          allComplete &&
          _timerStart != null &&
          _timerEnd == null) {
        await _stopTimer();
      }
    }
  }

  Future<void> _editSetDialog(
    String setId,
    Map<String, dynamic> setData,
    String exerciseName,
    int setNumber,
    String exerciseType,
    double weightIncrement,
  ) async {
    double weight = (setData['weight'] as num?)?.toDouble() ?? 0;
    int reps = (setData['reps'] as int?) ?? 0;
    double distance = (setData['distance'] as num?)?.toDouble() ?? 0;
    int timeSeconds = (setData['time_seconds'] as int?) ?? 0;
    double? rpe = (setData['rpe'] as num?)?.toDouble();
    final commentCtl = TextEditingController(
      text: (setData['comment'] as String?) ?? '',
    );
    bool isWarmup = (setData['is_warmup'] as int?) == 1;

    final result = await showModalBottomSheet<bool>(
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
                // Handle
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
                // Title
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.activeWorkoutEditSet,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '$exerciseName • ${AppLocalizations.of(context)!.activeWorkoutSetLabel(setNumber)}',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Comment (top)
                TextField(
                  controller: commentCtl,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.activeWorkoutSetNote,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 8),

                // Warmup toggle
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
                    Text(
                      AppLocalizations.of(context)!.activeWorkoutWarmup,
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 28,
                      child: Switch.adaptive(
                        value: isWarmup,
                        onChanged: (v) => setSheetState(() => isWarmup = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Field controls based on exercise type
                WorkoutSetFieldControls(
                  exerciseType: exerciseType,
                  weight: weight,
                  reps: reps,
                  distance: distance,
                  timeSeconds: timeSeconds,
                  weightIncrement: weightIncrement,
                  showPace: true,
                  onWeightChanged: (value) =>
                      setSheetState(() => weight = value),
                  onRepsChanged: (value) => setSheetState(() => reps = value),
                  onDistanceChanged: (value) =>
                      setSheetState(() => distance = value),
                  onTimeChanged: (value) =>
                      setSheetState(() => timeSeconds = value),
                ),
                const SizedBox(height: 16),

                // RPE
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 6),
                        child: Text(
                          'RPE',
                          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...List.generate(11, (i) {
                        final val = i.toDouble();
                        final isSet = rpe != null && rpe!.round() == i;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4, top: 4),
                          child: GestureDetector(
                            onTap: () => setSheetState(() {
                              rpe = (rpe == val) ? null : val;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSet
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSet
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
                                    color: isSet
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

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(AppLocalizations.of(context)!.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(AppLocalizations.of(context)!.commonSave),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && _workoutId != null) {
      await _workoutRepo.updateSet(
        setId,
        weight: weight,
        reps: reps,
        distance: distance,
        timeSeconds: timeSeconds,
        rpe: rpe,
        comment: commentCtl.text,
        isWarmup: isWarmup,
      );
      await _loadExercises();
      setState(() {});
    }
  }

  Future<void> _removeExercise(ExerciseWithSets exercise) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.activeWorkoutRemoveExercise),
        content: Text(
          AppLocalizations.of(context)!.activeWorkoutRemoveExerciseContent(
            exercise.localizedName(AppLocalizations.of(context)!),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.activeWorkoutRemove,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && _workoutId != null) {
      await _workoutRepo.deleteExerciseEntry(exercise.entryId);
      await _loadExercises();
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.activeWorkoutRemoved(
                exercise.localizedName(AppLocalizations.of(context)!),
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteSet(String setId) async {
    await _workoutRepo.deleteSet(setId);
    await _loadExercises();
    setState(() {});
  }

  int _estimateCurrentWorkoutDurationSeconds() {
    final estimateExercises = _exercises.map(
      (exercise) => WorkoutEstimateExercise(
        restTimeSeconds: exercise.restTimeSeconds,
        sets: exercise.sets
            .map(
              (set) => WorkoutEstimateSet(
                reps: (set['reps'] as num?)?.toInt(),
                timeSeconds: (set['time_seconds'] as num?)?.toInt(),
              ),
            )
            .toList(),
      ),
    );
    return WorkoutEstimateCalculator.estimateDurationSeconds(estimateExercises);
  }

  Future<void> _finishWorkout() async {
    if (_workoutId == null) return;
    if (_exercises.isEmpty) return;

    // Stop timer if still running or paused
    if (_timerStart != null && _timerEnd == null) {
      if (_isPaused) {
        await _resumeTimer();
      }
      await _stopTimer();
    }

    // Compute workout summary with PR detection
    final summary = await _computeSummary();

    if (!mounted) return;

    // Unified finish sheet
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => FinishWorkoutSheet(summary: summary),
    );

    if (result == null || !mounted) return;

    final feeling = result['feeling'] as int;
    final comment = result['comment'] as String? ?? '';

    await _workoutRepo.finishWorkout(
      _workoutId!,
      comment: comment,
      feelingRating: feeling,
      estimatedCalories: summary.estimatedCalories,
    );

    if (mounted) {
      final loc = AppLocalizations.of(context)!;
      final msg = summary.prs.isNotEmpty
          ? loc.activeWorkoutFinishedWithPRs(summary.prs.length)
          : loc.activeWorkoutFinished;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
      Navigator.pop(context, true);
    }
  }

  /// Compute workout summary: duration, volume, sets, distance/time, and PRs.
  Future<WorkoutSummary> _computeSummary() async {
    final loc = AppLocalizations.of(context)!;
    int durationSeconds = 0;
    double totalVolume = 0;
    int totalSets = 0;
    int completedSets = 0;
    double totalDistance = 0;
    int totalCardioTime = 0;
    final List<PR> prs = [];

    if (_timerStart != null) {
      final end = _timerEnd ?? DateTime.now();
      durationSeconds = end.difference(_timerStart!).inSeconds;
    }
    final plannedDurationSeconds = _estimateCurrentWorkoutDurationSeconds();
    final calorieDurationSeconds = durationSeconds > 0
        ? durationSeconds
        : plannedDurationSeconds;
    final bodyWeightKg = await _bodyRepo.getLatestWeightKg();
    final estimatedCalories = WorkoutEstimateCalculator.estimateCalories(
      durationSeconds: calorieDurationSeconds,
      bodyWeightKg: bodyWeightKg,
    );

    // Collect strength and cardio stats per exercise
    final Map<String, ExerciseBests> thisWorkoutBests = {};
    final Map<String, CardioBests> thisWorkoutCardio = {};

    for (final ex in _exercises) {
      double maxWeight = 0;
      int bestReps = 0;
      double exerciseVolume = 0;
      int exCompletedSets = 0;
      double exerciseDistance = 0;
      int exerciseTime = 0;

      for (final s in ex.sets) {
        final isComplete = (s['is_complete'] as int?) == 1;
        final isWarmup = (s['is_warmup'] as int?) == 1;

        if (!isWarmup) {
          totalSets++;
          final dist = (s['distance'] as num?)?.toDouble() ?? 0;
          final time = (s['time_seconds'] as int?) ?? 0;

          if (dist > 0) {
            exerciseDistance += dist;
            totalDistance += dist;
          }
          if (time > 0) {
            exerciseTime += time;
            totalCardioTime += time;
          }

          if (isComplete) {
            completedSets++;
            final weight = (s['weight'] as num?)?.toDouble() ?? 0;
            final reps = (s['reps'] as int?) ?? 0;
            final setVolume = weight * reps;
            exerciseVolume += setVolume;
            totalVolume += setVolume;
            if (weight > maxWeight) {
              maxWeight = weight;
              bestReps = reps;
            }
            exCompletedSets++;
          }
        }
      }

      if (maxWeight > 0) {
        thisWorkoutBests[ex.exerciseId] = ExerciseBests(
          name: ex.localizedName(loc),
          maxWeight: maxWeight,
          bestReps: bestReps,
          volume: exerciseVolume,
          completedSets: exCompletedSets,
        );
      }

      // Track cardio bests (longest distance, best pace)
      if (exerciseDistance > 0 && exerciseTime > 0) {
        thisWorkoutCardio[ex.exerciseId] = CardioBests(
          name: ex.localizedName(loc),
          distance: exerciseDistance,
          timeSeconds: exerciseTime,
        );
      }
    }

    // Detect PRs
    if (_workoutId != null) {
      final db = await DatabaseHelper.instance.database;

      // Strength PRs
      for (final entry in thisWorkoutBests.entries) {
        final exId = entry.key;
        final current = entry.value;

        final rows = await db.rawQuery(
          '''
          SELECT
            COALESCE(MAX(s.weight), 0) as best_weight,
            COALESCE(SUM(s.weight * s.reps), 0) as best_volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          WHERE ee.exercise_id = ? AND ee.workout_id != ?
            AND s.is_warmup = 0 AND s.is_complete = 1
        ''',
          [exId, _workoutId],
        );

        if (rows.isNotEmpty) {
          final bestWeight =
              (rows.first['best_weight'] as num?)?.toDouble() ?? 0;
          final bestVolume =
              (rows.first['best_volume'] as num?)?.toDouble() ?? 0;

          if (bestWeight > 0 && current.maxWeight >= bestWeight) {
            prs.add(
              PR(
                exerciseName: current.name,
                type: 'weight',
                value:
                    '${current.maxWeight.toStringAsFixed(1)}kg × ${current.bestReps}',
                previous: '${bestWeight.toStringAsFixed(1)}kg',
              ),
            );
          }
          if (bestVolume > 0 && current.volume > bestVolume) {
            prs.add(
              PR(
                exerciseName: current.name,
                type: 'volume',
                value: '${current.volume.toStringAsFixed(0)} kg',
                previous: '${bestVolume.toStringAsFixed(0)} kg',
              ),
            );
          }
        }
      }

      // Cardio PRs (best distance, best pace)
      for (final entry in thisWorkoutCardio.entries) {
        final exId = entry.key;
        final current = entry.value;

        final rows = await db.rawQuery(
          '''
          SELECT
            COALESCE(MAX(s.distance), 0) as best_distance,
            COALESCE(MIN(CAST(s.time_seconds AS REAL) / NULLIF(s.distance, 0)), 999999) as best_pace
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          WHERE ee.exercise_id = ? AND ee.workout_id != ?
            AND s.is_warmup = 0 AND s.is_complete = 1
            AND s.distance IS NOT NULL AND s.distance > 0
        ''',
          [exId, _workoutId],
        );

        if (rows.isNotEmpty) {
          final bestDist =
              (rows.first['best_distance'] as num?)?.toDouble() ?? 0;
          if (bestDist > 0 && current.distance >= bestDist) {
            prs.add(
              PR(
                exerciseName: current.name,
                type: 'distance',
                value: '${current.distance.toStringAsFixed(1)} km',
                previous: '${bestDist.toStringAsFixed(1)} km',
              ),
            );
          }
        }
      }
    }

    return WorkoutSummary(
      durationSeconds: durationSeconds,
      totalVolume: totalVolume,
      totalSets: totalSets,
      completedSets: completedSets,
      totalDistance: totalDistance,
      totalCardioTime: totalCardioTime,
      estimatedCalories: estimatedCalories,
      prs: prs,
    );
  }

  Future<void> _openRestTimer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RestTimerScreen()),
    );
  }
}
