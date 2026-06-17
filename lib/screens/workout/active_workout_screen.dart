import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_helper.dart';
import '../../repositories/workout_repository.dart';
import '../../repositories/routine_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/rest_timer_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/exercise_picker_sheet.dart';
import '../../widgets/workout/stepper_button.dart';
import '../../widgets/workout/exercise_card.dart';
import '../../widgets/workout/finish_workout_sheet.dart';
import '../../models/exercise_with_sets.dart';
import '../../utils/workout_card_helpers.dart';
import 'rest_timer_screen.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  final String? workoutId;
  final String? routineId;
  final String? routineDayId;

  const ActiveWorkoutScreen({
    super.key,
    this.workoutId,
    this.routineId,
    this.routineDayId,
  });

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  final _workoutRepo = WorkoutRepository();
  final _routineRepo = RoutineRepository();
  final _settingsRepo = SettingsRepository();
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

    final orderedIds =
        reordered.map((e) => e.entryId).toList(growable: false);
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
          content: Text('Erro ao reordenar: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Provides a subtle visual lift + shadow while dragging an exercise
  /// card during reorder, matching Material 3 guidance.
  Widget _dragProxyDecorator(
      Widget child, int index, Animation<double> animation) {
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
  void initState() {
    super.initState();
    _timerService.addListener(_onTimerTick);
    _initialize();
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerTick);
    _elapsedTimer?.cancel();
    super.dispose();
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
    final routineExercises = await _routineRepo.getRoutineExercises(widget.routineDayId!);
    final exercises = <Map<String, dynamic>>[];

    for (final re in routineExercises) {
      final sets = await _routineRepo.getPredefinedSets(re['id'] as String);
      exercises.add({
        'exercise_id': re['exercise_id'],
        'notes': null,
        'sets': sets.map((s) => {
          'weight': s['weight'],
          'reps': s['reps'],
          'distance': s['distance'],
          'time_seconds': s['time_seconds'],
          'is_warmup': s['is_warmup'],
        }).toList(),
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
    _exercises = [];
    for (final entry in entries) {
      final sets = List<Map<String, dynamic>>.from(
        await _workoutRepo.getExerciseSets(entry['id'] as String));
      _exercises.add(ExerciseWithSets(
        entryId: entry['id'] as String,
        exerciseId: entry['exercise_id'] as String,
        name: entry['exercise_name'] as String? ?? '',
        localeKey: entry['exercise_locale_key'] as String?,
        categoryId: entry['category_id'] as String?,
        exerciseType: entry['exercise_type'] as String? ?? 'weightReps',
        categoryName: entry['category_name'] as String? ?? '',
        categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
        sets: sets,
        restTimeSeconds: (entry['rest_time_seconds'] as int?) ?? 90,
      ));
    }
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
        content: Text(AppLocalizations.of(context)!.activeWorkoutResetTimerContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context)!.activeWorkoutReset, style: TextStyle(color: Colors.red))),
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

  void _quickEditNumber(BuildContext sheetContext, double current, bool isInt, void Function(double) onSet, {String? title, String? suffix}) {
    final ctl = TextEditingController(
      text: isInt ? current.round().toString() : current.toStringAsFixed(1));
    showDialog(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: Text(title ?? (isInt ? 'Digite as repetições' : 'Digite o peso')),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            suffixText: suffix ?? (isInt ? ' reps' : ' kg'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
          FilledButton(onPressed: () {
            final parsed = double.tryParse(ctl.text.replaceAll(',', '.'));
            if (parsed != null && parsed >= 0) {
              onSet(isInt ? parsed.roundToDouble() : parsed);
            }
            Navigator.pop(ctx);
          }, child: Text(AppLocalizations.of(context)!.activeWorkoutOK)),
        ],
      ),
    );
  }

  /// Builds dynamic field controls for the set editor based on exercise type.
  List<Widget> _buildFieldControls(
    String type, BuildContext ctx, StateSetter setSheetState,
    double weight, int reps, double distance, int timeSeconds,
    void Function(String key, dynamic value) onFieldChange,
  ) {
    final fields = getFieldsForType(type);
    final keys = fields.keys.toList();
    final widgets = <Widget>[];
    bool hasDistance = false;

    for (final key in keys) {
      if (key == 'weight') {
        widgets.add(_buildWeightControl(ctx, setSheetState, weight, (v) => onFieldChange('weight', v)));
      } else if (key == 'reps') {
        widgets.add(_buildRepsControl(ctx, setSheetState, reps, (v) => onFieldChange('reps', v)));
      } else if (key == 'distance') {
        hasDistance = true;
        widgets.add(_buildDistanceControl(ctx, setSheetState, distance, (v) => onFieldChange('distance', v)));
      } else if (key == 'time_seconds') {
        if (hasDistance && distance > 0 && timeSeconds > 0) {
          final pace = timeSeconds / distance;
          widgets.add(_buildPaceDisplay(ctx, pace));
        }
        widgets.add(_buildTimeControl(ctx, setSheetState, timeSeconds, (v) => onFieldChange('time_seconds', v)));
      }
    }
    return widgets;
  }

  Widget _buildPaceDisplay(BuildContext ctx, double paceSecPerKm) {
    final theme = Theme.of(ctx);
    final minutes = paceSecPerKm ~/ 60;
    final seconds = paceSecPerKm.round() % 60;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF6D4C41).withAlpha(15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speed, size: 16, color: const Color(0xFF6D4C41)),
            const SizedBox(width: 6),
            Text(
              'Pace: $minutes:${seconds.toString().padLeft(2, '0')} /km',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6D4C41),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightControl(BuildContext ctx, StateSetter setSheetState, double weight, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.activeWorkoutWeight, style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          StepperButton(icon: Icons.remove, onTap: () => onChanged(weight - 2)),
          const SizedBox(width: 6),
          StepperButton(icon: Icons.remove, small: true, onTap: () => onChanged(weight - 1)),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(ctx, weight, false, onChanged),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(weight.toStringAsFixed(1), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          StepperButton(icon: Icons.add, small: true, onTap: () => onChanged(weight + 1)),
          const SizedBox(width: 6),
          StepperButton(icon: Icons.add, onTap: () => onChanged(weight + 2)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [20, 30, 40, 50, 60, 80, 100, 120].map((v) => ActionChip(
          label: Text('$v', style: const TextStyle(fontSize: 10)),
          onPressed: () => onChanged(v.toDouble()),
          visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )).toList()),
      ],
    );
  }

  Widget _buildRepsControl(BuildContext ctx, StateSetter setSheetState, int reps, void Function(int) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(AppLocalizations.of(context)!.activeWorkoutReps, style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          StepperButton(icon: Icons.remove, onTap: () => onChanged(reps - 1)),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(ctx, reps.toDouble(), true, (v) => onChanged(v.round())),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text('$reps', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          StepperButton(icon: Icons.add, onTap: () => onChanged(reps + 1)),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [1, 3, 5, 8, 10, 12, 15, 20].map((v) => ActionChip(
          label: Text('$v', style: const TextStyle(fontSize: 10)),
          onPressed: () => onChanged(v),
          visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )).toList()),
      ],
    );
  }

  Widget _buildDistanceControl(BuildContext ctx, StateSetter setSheetState, double distance, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.activeWorkoutDistance, style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          StepperButton(icon: Icons.remove, small: true, onTap: () => onChanged((distance - 0.1).clamp(0, 999))),
          StepperButton(icon: Icons.remove, onTap: () => onChanged((distance - 0.5).clamp(0, 999))),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(ctx, distance, false, onChanged, title: 'Digite a distância', suffix: ' km'),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(distance.toStringAsFixed(1), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          StepperButton(icon: Icons.add, onTap: () => onChanged((distance + 0.5).clamp(0, 999))),
          StepperButton(icon: Icons.add, small: true, onTap: () => onChanged((distance + 0.1).clamp(0, 999))),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [1.0, 2.0, 3.0, 5.0, 10.0].map((v) => ActionChip(
          label: Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
          onPressed: () => onChanged(v),
          visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )).toList()),
      ],
    );
  }

  Widget _buildTimeControl(BuildContext ctx, StateSetter setSheetState, int timeSeconds, void Function(int) onChanged) {
    final minutes = timeSeconds ~/ 60;
    final seconds = timeSeconds % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context)!.activeWorkoutTime, style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          StepperButton(icon: Icons.remove, onTap: () => onChanged((timeSeconds - 30).clamp(0, 99999))),
          StepperButton(icon: Icons.remove, small: true, onTap: () => onChanged((timeSeconds - 5).clamp(0, 99999))),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(ctx, timeSeconds.toDouble(), true, (v) => onChanged(v.round()), title: 'Digite o tempo (segundos)', suffix: ' s'),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120), borderRadius: BorderRadius.circular(10)),
                child: Center(
                  child: Text(
                    timeSeconds >= 60 ? '$minutes:${seconds.toString().padLeft(2, '0')}' : '${timeSeconds}s',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          StepperButton(icon: Icons.add, small: true, onTap: () => onChanged((timeSeconds + 5).clamp(0, 99999))),
          StepperButton(icon: Icons.add, onTap: () => onChanged((timeSeconds + 30).clamp(0, 99999))),
        ]),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [30, 60, 120, 180, 300, 600].map((v) => ActionChip(
          label: Text(v >= 60 ? '${v ~/ 60}min' : '${v}s', style: const TextStyle(fontSize: 10)),
          onPressed: () => onChanged(v),
          visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )).toList()),
      ],
    );
  }

  // ===================== EXERCISE ACTIONS =====================

  Future<void> addExercise(String exerciseId, String name, String catName, Color catColor, {int? restTimeSeconds}) async {
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
    List<Map<String, dynamic>> autoSets = [];
    if (_workoutId != null) {
      final lastSets = await _workoutRepo.getLastWorkoutSets(exerciseId, excludeWorkoutId: _workoutId);
      for (final s in lastSets) {
        await _workoutRepo.addSet(
          exerciseEntryId: entryId,
          weight: (s['weight'] as num?)?.toDouble(),
          reps: (s['reps'] as int?),
          isWarmup: (s['is_warmup'] as int?) == 1,
        );
      }
      // Reload the newly created sets to get their IDs
      autoSets = await _workoutRepo.getExerciseSets(entryId);
    }

    setState(() {
      _exercises.add(ExerciseWithSets(
        entryId: entryId,
        exerciseId: exerciseId,
        name: name,
        exerciseType: 'weightReps',
        categoryName: catName,
        categoryColor: catColor,
        sets: autoSets,
        restTimeSeconds: rt,
      ));
    });
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
      if (_autoStartTimer && allComplete && _timerStart != null && _timerEnd == null) {
        await _stopTimer();
      }
    }
  }

  Future<void> _editSetDialog(String setId, Map<String, dynamic> setData, String exerciseName, int setNumber, String exerciseType) async {
    double weight = (setData['weight'] as num?)?.toDouble() ?? 0;
    int reps = (setData['reps'] as int?) ?? 0;
    double distance = (setData['distance'] as num?)?.toDouble() ?? 0;
    int timeSeconds = (setData['time_seconds'] as int?) ?? 0;
    double? rpe = (setData['rpe'] as num?)?.toDouble();
    final commentCtl = TextEditingController(text: (setData['comment'] as String?) ?? '');
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
            left: 16, right: 16, top: 8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ))),
                const SizedBox(height: 12),
                // Title
                Row(
                  children: [
                    Expanded(
                      child: Text(AppLocalizations.of(context)!.activeWorkoutEditSet, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Text('$exerciseName • ${AppLocalizations.of(context)!.activeWorkoutSetLabel(setNumber)}', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    )),
                  ],
                ),
                const SizedBox(height: 12),

                // Comment (top)
                TextField(
                  controller: commentCtl,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 8),

                // Warmup toggle
                Row(
                  children: [
                    Icon(Icons.whatshot, size: 16, color: isWarmup ? Colors.orange : Theme.of(ctx).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context)!.activeWorkoutWarmup, style: Theme.of(ctx).textTheme.bodyMedium),
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
                ..._buildFieldControls(exerciseType, ctx, setSheetState, weight, reps, distance, timeSeconds, (String key, dynamic value) {
                  setSheetState(() {
                    switch (key) {
                      case 'weight': weight = (value as double).clamp(0, 999); break;
                      case 'reps': reps = (value as int).clamp(0, 999); break;
                      case 'distance': distance = (value as double).clamp(0, 999); break;
                      case 'time_seconds': timeSeconds = (value as int).clamp(0, 99999); break;
                    }
                  });
                }),
                const SizedBox(height: 16),

                // RPE
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 6),
                        child: Text('RPE', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
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
                              width: 30, height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSet ? Theme.of(ctx).colorScheme.primary : Colors.transparent,
                                border: Border.all(
                                  color: isSet ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.outlineVariant,
                                  width: 1.5,
                                ),
                              ),
                              child: Center(child: Text(
                                i == 0 ? '-' : '$i',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSet ? Theme.of(ctx).colorScheme.onPrimary : Theme.of(ctx).colorScheme.onSurface,
                                ),
                              )),
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
      await _workoutRepo.updateSet(setId,
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
        content: Text('Remover "${exercise.localizedName(AppLocalizations.of(context)!)}" do treino? Todas as séries registradas serão perdidas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.activeWorkoutRemove, style: TextStyle(color: Colors.red)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.activeWorkoutRemoved(exercise.localizedName(AppLocalizations.of(context)!))), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _deleteSet(String setId) async {
    await _workoutRepo.deleteSet(setId);
    await _loadExercises();
    setState(() {});
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

    await _workoutRepo.finishWorkout(_workoutId!, comment: comment, feelingRating: feeling);

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
          name: ex.localizedName(AppLocalizations.of(context)!),
          maxWeight: maxWeight,
          bestReps: bestReps,
          volume: exerciseVolume,
          completedSets: exCompletedSets,
        );
      }

      // Track cardio bests (longest distance, best pace)
      if (exerciseDistance > 0 && exerciseTime > 0) {
        thisWorkoutCardio[ex.exerciseId] = CardioBests(
          name: ex.localizedName(AppLocalizations.of(context)!),
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

        final rows = await db.rawQuery('''
          SELECT
            COALESCE(MAX(s.weight), 0) as best_weight,
            COALESCE(SUM(s.weight * s.reps), 0) as best_volume
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          WHERE ee.exercise_id = ? AND ee.workout_id != ?
            AND s.is_warmup = 0 AND s.is_complete = 1
        ''', [exId, _workoutId]);

        if (rows.isNotEmpty) {
          final bestWeight =
              (rows.first['best_weight'] as num?)?.toDouble() ?? 0;
          final bestVolume =
              (rows.first['best_volume'] as num?)?.toDouble() ?? 0;

          if (bestWeight > 0 && current.maxWeight >= bestWeight) {
            prs.add(PR(
              exerciseName: current.name,
              type: 'weight',
              value:
                  '${current.maxWeight.toStringAsFixed(1)}kg × ${current.bestReps}',
              previous:
                  '${bestWeight.toStringAsFixed(1)}kg',
            ));
          }
          if (bestVolume > 0 && current.volume > bestVolume) {
            prs.add(PR(
              exerciseName: current.name,
              type: 'volume',
              value: '${current.volume.toStringAsFixed(0)} kg',
              previous: '${bestVolume.toStringAsFixed(0)} kg',
            ));
          }
        }
      }

      // Cardio PRs (best distance, best pace)
      for (final entry in thisWorkoutCardio.entries) {
        final exId = entry.key;
        final current = entry.value;

        final rows = await db.rawQuery('''
          SELECT
            COALESCE(MAX(s.distance), 0) as best_distance,
            COALESCE(MIN(CAST(s.time_seconds AS REAL) / NULLIF(s.distance, 0)), 999999) as best_pace
          FROM sets s
          JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
          WHERE ee.exercise_id = ? AND ee.workout_id != ?
            AND s.is_warmup = 0 AND s.is_complete = 1
            AND s.distance IS NOT NULL AND s.distance > 0
        ''', [exId, _workoutId]);

        if (rows.isNotEmpty) {
          final bestDist =
              (rows.first['best_distance'] as num?)?.toDouble() ?? 0;
          if (bestDist > 0 && current.distance >= bestDist) {
            prs.add(PR(
              exerciseName: current.name,
              type: 'distance',
              value: '${current.distance.toStringAsFixed(1)} km',
              previous: '${bestDist.toStringAsFixed(1)} km',
            ));
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
      prs: prs,
    );
  }

  Future<void> _openRestTimer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RestTimerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.activeWorkoutTitle),
        centerTitle: true,
        actions: [
          if (_timerService.isActive)
            GestureDetector(
              onTap: _openRestTimer,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _timerService.remainingSeconds <= 5 && _timerService.isRunning
                      ? Colors.red.withAlpha(40)
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _timerService.isPaused ? Icons.pause : Icons.timer,
                      size: 18,
                      color: _timerService.remainingSeconds <= 5 && _timerService.isRunning
                          ? Colors.red
                          : Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _timerService.shortTime,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _timerService.remainingSeconds <= 5 && _timerService.isRunning
                            ? Colors.red
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.timer_outlined),
              onPressed: _openRestTimer,
              tooltip: 'Temporizador',
            ),
          if (_isPaused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _resumeTimer,
              tooltip: AppLocalizations.of(context)!.restTimerResume,
            )
          else if (_timerStart != null && _timerEnd == null)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: _pauseTimer,
              tooltip: AppLocalizations.of(context)!.restTimerPause,
            ),
          if (_exercises.isNotEmpty)
            IconButton.filledTonal(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: _finishWorkout,
              tooltip: AppLocalizations.of(context)!.activeWorkoutFinishWorkout,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Mais opções',
            onSelected: (value) {
              switch (value) {
                case 'import_routine':
                  _importFromRoutine();
                  break;
                case 'reset_timer':
                  _resetTimer();
                  break;
                case 'delete_workout':
                  _deleteWorkout();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'import_routine',
                child: Row(
                  children: [
                    const Icon(Icons.repeat_outlined, size: 20),
                    const SizedBox(width: 12),
                    Text(AppLocalizations.of(context)!.activeWorkoutImportRoutine),
                  ],
                ),
              ),
              if (_timerStart != null)
                PopupMenuItem<String>(
                  value: 'reset_timer',
                  child: Row(
                    children: [
                      Icon(Icons.restart_alt, size: 20, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)!.activeWorkoutReset,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete_workout',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.workoutHomeDeleteWorkout,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exercises.isEmpty && _timerStart == null
              ? _buildEmptyState(theme)
              : _buildWorkoutView(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickExercise,
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context)!.activeWorkoutAddExercise),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center, size: 80, color: theme.colorScheme.primary.withAlpha(80)),
            const SizedBox(height: 24),
            Text(AppLocalizations.of(context)!.activeWorkoutEmptyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.activeWorkoutEmptySubtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickExercise,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context)!.activeWorkoutAddExercise),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _importFromRoutine,
              icon: const Icon(Icons.repeat),
              label: Text(AppLocalizations.of(context)!.activeWorkoutImportRoutine),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutView(ThemeData theme) {
    int totalSets = 0;
    int completedSets = 0;
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        // Warmup sets are excluded from the progress counter.
        if ((s['is_warmup'] as int?) != 1) {
          totalSets++;
          if ((s['is_complete'] as int?) == 1) completedSets++;
        }
      }
    }

    return Column(
      children: [
        // Timer Card (top)
        _buildTimerCard(theme),

        // Progress bar
        if (totalSets > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerLow,
            child: Row(
              children: [
                Text(AppLocalizations.of(context)!.activeWorkoutSetsSummary(completedSets, totalSets), style: theme.textTheme.bodySmall),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: completedSets / totalSets,
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _exercises.isEmpty
              ? const SizedBox.shrink()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  itemCount: _exercises.length,
                  buildDefaultDragHandles: true,
                  proxyDecorator: _dragProxyDecorator,
                  onReorderStart: (_) => HapticFeedback.mediumImpact(),
                  onReorderItem: _onReorderExercises,
                  itemBuilder: (context, index) => ExerciseCard(
                    key: ValueKey(_exercises[index].entryId),
                    exercise: _exercises[index],
                    onAddSet: () => _addSet(_exercises[index]),
                    onToggleSet: _toggleSet,
                    onEditSet: (setId, data, setIdx) => _editSetDialog(setId, data, _exercises[index].localizedName(AppLocalizations.of(context)!), setIdx, _exercises[index].exerciseType),
                    onDeleteSet: _deleteSet,
                    onRemoveExercise: () => _removeExercise(_exercises[index]),
                    onChangeRestTime: (currentRest) => _changeExerciseRestTime(_exercises[index], currentRest),
                    theme: theme,
                  ),
                ),
        ),
      ],
    );
  }

  // ===================== TIMER CARD =====================
  Widget _buildTimerCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withAlpha(200),
            theme.colorScheme.surfaceContainerHighest.withAlpha(180),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            _timerEnd != null
                ? Icons.check_circle
                : _isPaused
                    ? Icons.pause_circle_outline
                    : _timerStart != null
                        ? Icons.timer_outlined
                        : Icons.play_circle_outline,
            color: _timerEnd != null
                ? Colors.green
                : _isPaused
                    ? Colors.orange
                    : _timerStart != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isPaused) ...[
                  // Paused
                  Text(
                    _elapsedStr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.restTimerPaused,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${AppLocalizations.of(context)!.activeWorkoutTimerStartLabel} ${DateFormat('HH:mm').format(_timerStart!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ] else if (_timerStart != null && _timerEnd == null) ...[
                  // Running
                  Text(
                    _elapsedStr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${AppLocalizations.of(context)!.activeWorkoutTimerStartLabel} ${DateFormat('HH:mm').format(_timerStart!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (_timerStart != null && _timerEnd != null) ...[
                  // Finished
                  Text(
                    '${AppLocalizations.of(context)!.activeWorkoutTimerDuration} $_elapsedStr',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('HH:mm').format(_timerStart!)} → ${DateFormat('HH:mm').format(_timerEnd!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  // Not started
                  Text(
                    AppLocalizations.of(context)!.activeWorkoutTimerTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.activeWorkoutStartTimerTooltip,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_timerStart == null || (_timerStart != null && _timerEnd == null))
            SizedBox(
              height: 36,
              child: FilledButton(
                onPressed: _timerStart == null
                    ? _startTimer
                    : (_isPaused ? _resumeTimer : _pauseTimer),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: _timerStart == null
                      ? theme.colorScheme.primary
                      : (_isPaused
                          ? theme.colorScheme.primary
                          : Colors.orange.withAlpha(200)),
                  foregroundColor: _timerStart == null
                      ? theme.colorScheme.onPrimary
                      : Colors.white,
                ),
                child: Text(
                  _timerStart == null
                      ? AppLocalizations.of(context)!.activeWorkoutStart
                      : (_isPaused
                          ? AppLocalizations.of(context)!.restTimerResume
                          : AppLocalizations.of(context)!.restTimerPause),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===================== REST =====================

  Future<void> _importFromRoutine() async {
    final ctx = context;
    final scaffoldMessenger = ScaffoldMessenger.of(ctx);
    final loc = AppLocalizations.of(ctx);
    final routines = await _routineRepo.getRoutines();
    if (routines.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.activeWorkoutNoRoutineFound), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final routineId = await showModalBottomSheet<String>(
      // ignore: use_build_context_synchronously
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildRoutinePicker(routines),
    );
    if (routineId == null || !mounted) return;

    final days = await _routineRepo.getRoutineDays(routineId);
    if (days.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(loc!.activeWorkoutNoRoutineDays), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final routineName = routines.firstWhere((r) => r['id'] == routineId)['name'] as String;
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
      SnackBar(content: Text(loc!.activeWorkoutRoutineImported), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildRoutinePicker(List<Map<String, dynamic>> routines) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
            borderRadius: BorderRadius.circular(2),
          ))),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context)!.activeWorkoutSelectRoutine, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                    child: Icon(Icons.repeat, color: theme.colorScheme.onSecondaryContainer, size: 20),
                  ),
                  title: Text(routine['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
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

  Widget _buildDayPicker(BuildContext sheetContext, List<Map<String, dynamic>> days, String routineName) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
            borderRadius: BorderRadius.circular(2),
          ))),
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
          Text(routineName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context)!.activeWorkoutSelectDay, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                    child: Icon(Icons.today, color: theme.colorScheme.onPrimaryContainer, size: 20),
                  ),
                  title: Text(day['name'] as String? ?? 'Dia ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
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
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 16),
            Text('Tempo de Descanso', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(exercise.localizedName(AppLocalizations.of(context)!), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...presets.map((sec) => ChoiceChip(
                  label: Text(sec >= 60 ? '${sec ~/ 60}min${sec % 60}s' : '${sec}s'),
                  selected: currentRest == sec,
                  onSelected: (_) {
                    _updateRestTimeAndClose(exercise, sec);
                    Navigator.pop(ctx);
                  },
                )),
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
    final ctl = TextEditingController(text: exercise.restTimeSeconds.toString());
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
                decoration: const InputDecoration(
                  labelText: 'Segundos',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ),
            const SizedBox(width: 8),
            const Text('s'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
          FilledButton(onPressed: () {
            final v = int.tryParse(ctl.text);
            if (v != null && v > 0) {
              _updateRestTimeAndClose(exercise, v);
              Navigator.pop(ctx);
            }
          }, child: const Text('Definir')),
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
            ExerciseLocaleHelper.exerciseName(AppLocalizations.of(context)!, exercise),
            ExerciseLocaleHelper.categoryName(AppLocalizations.of(context)!, exercise),
            Color(exercise['category_color'] as int? ?? 0xFF757575),
            restTimeSeconds: (exercise['default_rest_time'] as int?),
          );
        },
        onExerciseRemoved: (exercise) async {
          final exerciseId = exercise['id'] as String;
          await _workoutRepo.removeExerciseEntryFromWorkout(_workoutId!, exerciseId);
          if (mounted) {
            setState(() {
              _exercises.removeWhere((e) => e.exerciseId == exerciseId);
            });
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
            child: Text(AppLocalizations.of(context)!.commonDelete, style: TextStyle(color: Colors.red)),
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
            content: Text(AppLocalizations.of(context)!.workoutHomeDeleteWorkout),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }
}

/// Returns the field labels and keys for a given exercise type.
