import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_helper.dart';
import '../../services/rest_timer_service.dart';
import '../../widgets/exercise_picker_sheet.dart';
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
  final _db = DatabaseHelper.instance;
  final _timerService = RestTimerService.instance;
  final _uuid = const Uuid();
  bool _isLoading = true;
  String? _workoutId;
  
  // Timer tracking
  DateTime? _timerStart;
  DateTime? _timerEnd;
  Timer? _elapsedTimer; // periodic tick for live elapsed time
  String _elapsedStr = '00:00';
  
  // Settings
  bool _autoStartTimer = false;

  List<_ExerciseWithSets> _exercises = [];

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
      }
    });
  }

  Future<void> _initialize() async {
    // Load settings
    final settings = await _db.getAllSettings();
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
    final id = await _db.createWorkout();
    _workoutId = id;
    // start_time is NOT set until user clicks "Iniciar"
  }

  Future<void> _loadExistingWorkout(String id) async {
    _workoutId = id;
    final workout = await _db.getWorkout(id);
    if (workout != null) {
      final startStr = workout['start_time'] as String?;
      if (startStr != null) _timerStart = DateTime.parse(startStr);
      final endStr = workout['end_time'] as String?;
      if (endStr != null) _timerEnd = DateTime.parse(endStr);
      
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
    final routineExercises = await _db.getRoutineExercises(widget.routineDayId!);
    final exercises = <Map<String, dynamic>>[];

    for (final re in routineExercises) {
      final sets = await _db.getPredefinedSets(re['id'] as String);
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

    final id = await _db.createWorkout(
      routineId: widget.routineId,
      exercises: exercises,
    );
    _workoutId = id;
    await _loadExercises();
  }

  Future<void> _loadExercises() async {
    if (_workoutId == null) return;
    final entries = await _db.getWorkoutExercises(_workoutId!);
    _exercises = [];
    for (final entry in entries) {
      final sets = List<Map<String, dynamic>>.from(
        await _db.getExerciseSets(entry['id'] as String));
      _exercises.add(_ExerciseWithSets(
        entryId: entry['id'] as String,
        exerciseId: entry['exercise_id'] as String,
        name: entry['exercise_name'] as String? ?? '',
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
    await _db.startWorkoutTimer(_workoutId!);
    _startElapsedTimer();
    setState(() => _elapsedStr = '00:00');
  }

  Future<void> _stopTimer() async {
    if (_workoutId == null) return;
    final now = DateTime.now();
    _timerEnd = now;
    _elapsedTimer?.cancel();
    await _db.stopWorkoutTimer(_workoutId!);
    _updateElapsedStr();
    setState(() {});
  }

  Future<void> _resetTimer() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resetar Timer?'),
        content: const Text('Isso vai limpar o tempo de início e fim do treino.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resetar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && _workoutId != null) {
      _timerStart = null;
      _timerEnd = null;
      _elapsedTimer?.cancel();
      _elapsedStr = '00:00';
      await _db.resetWorkoutTimer(_workoutId!);
      setState(() {});
    }
  }

  void _quickEditNumber(BuildContext sheetContext, double current, bool isInt, void Function(double) onSet) {
    final ctl = TextEditingController(
      text: isInt ? current.round().toString() : current.toStringAsFixed(1));
    showDialog(
      context: sheetContext,
      builder: (ctx) => AlertDialog(
        title: Text(isInt ? 'Digite as repetições' : 'Digite o peso'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            suffixText: isInt ? ' reps' : ' kg',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            final parsed = double.tryParse(ctl.text.replaceAll(',', '.'));
            if (parsed != null && parsed >= 0) {
              onSet(isInt ? parsed.roundToDouble() : parsed);
            }
            Navigator.pop(ctx);
          }, child: const Text('OK')),
        ],
      ),
    );
  }

  // ===================== EXERCISE ACTIONS =====================

  Future<void> _addExercise(String exerciseId, String name, String catName, Color catColor, {int? restTimeSeconds}) async {
    if (_workoutId == null) return;
    final entryId = _uuid.v4();
    final db = await _db.database;
    final rt = restTimeSeconds ?? 90;
    await db.insert('exercise_entries', {
      'id': entryId,
      'workout_id': _workoutId,
      'exercise_id': exerciseId,
      'order_index': _exercises.length,
      'rest_time_seconds': rt,
    });

    // Auto-populate from last workout
    final lastSets = await _db.getLastWorkoutSets(exerciseId);
    if (lastSets.isNotEmpty) {
      for (int i = 0; i < lastSets.length; i++) {
        await _db.addSet(
          exerciseEntryId: entryId,
          weight: (lastSets[i]['weight'] as num?)?.toDouble(),
          reps: (lastSets[i]['reps'] as int?),
          isWarmup: (lastSets[i]['is_warmup'] as int?) == 1,
        );
      }
    }

    setState(() {
      _exercises.add(_ExerciseWithSets(
        entryId: entryId,
        exerciseId: exerciseId,
        name: name,
        categoryName: catName,
        categoryColor: catColor,
        sets: [],
        restTimeSeconds: rt,
      ));
    });
  }

  Future<void> _addSet(_ExerciseWithSets exercise) async {
    double? lastWeight;
    int? lastReps;
    bool lastWarmup = false;
    if (exercise.sets.isNotEmpty) {
      final last = exercise.sets.last;
      lastWeight = (last['weight'] as num?)?.toDouble();
      lastReps = (last['reps'] as int?);
      lastWarmup = (last['is_warmup'] as int?) == 1;
    }

    await _db.addSet(
      exerciseEntryId: exercise.entryId,
      weight: lastWeight,
      reps: lastReps,
      isWarmup: lastWarmup,
    );
    await _loadExercises();
    setState(() {});
  }

  Future<void> _toggleSet(String setId) async {
    _ExerciseWithSets? parentExercise;
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
    await _db.toggleSetComplete(setId);
    await _loadExercises();
    setState(() {});

    if (!wasComplete && parentExercise != null && mounted) {
      // Auto-start rest timer
      _timerService.start(parentExercise.restTimeSeconds);

      // Auto-start workout timer if enabled and not started
      if (_autoStartTimer && _timerStart == null && _timerEnd == null) {
        await _startTimer();
      }

      // Auto-stop workout timer if all sets are now complete
      if (_autoStartTimer) {
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
        if (allComplete && _timerStart != null && _timerEnd == null) {
          await _stopTimer();
        }
      }
    }
  }

  Future<void> _editSetDialog(String setId, Map<String, dynamic> setData, String exerciseName, int setNumber) async {
    double weight = (setData['weight'] as num?)?.toDouble() ?? 0;
    int reps = (setData['reps'] as int?) ?? 0;
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
                      child: Text('Editar Série', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Text('$exerciseName • Série $setNumber', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
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
                    Text('Aquecimento', style: Theme.of(ctx).textTheme.bodyMedium),
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

                // WEIGHT row
                Text('Peso (kg)', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StepperButton(
                      icon: Icons.remove,
                      onTap: () => setSheetState(() {
                        weight = (weight - 2.5).clamp(0, 999);
                      }),
                    ),
                    const SizedBox(width: 6),
                    _StepperButton(
                      icon: Icons.remove, small: true,
                      onTap: () => setSheetState(() {
                        weight = (weight - 0.5).clamp(0, 999);
                      }),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _quickEditNumber(ctx, weight, false, (v) {
                          setSheetState(() => weight = v);
                        }),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(
                            weight.toStringAsFixed(1),
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          )),
                        ),
                      ),
                    ),
                    _StepperButton(
                      icon: Icons.add, small: true,
                      onTap: () => setSheetState(() {
                        weight = (weight + 0.5).clamp(0, 999);
                      }),
                    ),
                    const SizedBox(width: 6),
                    _StepperButton(
                      icon: Icons.add,
                      onTap: () => setSheetState(() {
                        weight = (weight + 2.5).clamp(0, 999);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [20, 30, 40, 50, 60, 80, 100, 120].map((v) => ActionChip(
                    label: Text('$v', style: const TextStyle(fontSize: 10)),
                    onPressed: () => setSheetState(() => weight = v.toDouble()),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
                const SizedBox(height: 14),

                // REPS row
                Text('Repetições', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StepperButton(
                      icon: Icons.remove,
                      onTap: () => setSheetState(() {
                        reps = (reps - 1).clamp(0, 999);
                      }),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _quickEditNumber(ctx, reps.toDouble(), true, (v) {
                          setSheetState(() => reps = v.round());
                        }),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(120),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(
                            '$reps',
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          )),
                        ),
                      ),
                    ),
                    _StepperButton(
                      icon: Icons.add,
                      onTap: () => setSheetState(() {
                        reps = (reps + 1).clamp(0, 999);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [1, 3, 5, 8, 10, 12, 15, 20].map((v) => ActionChip(
                    label: Text('$v', style: const TextStyle(fontSize: 10)),
                    onPressed: () => setSheetState(() => reps = v),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
                const SizedBox(height: 14),

                // RPE
                Row(
                  children: [
                    Text('RPE', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    ...List.generate(11, (i) {
                      final val = i.toDouble();
                      final isSet = rpe != null && rpe!.round() == i;
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: GestureDetector(
                          onTap: () => setSheetState(() {
                            rpe = (rpe == val) ? null : val;
                          }),
                          child: Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSet ? Theme.of(ctx).colorScheme.primary : null,
                              border: Border.all(color: isSet ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.outlineVariant),
                            ),
                            child: Center(child: Text(
                              i == 0 ? '-' : '$i',
                              style: TextStyle(
                                fontSize: 10,
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
                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Salvar'),
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
      await _db.updateSet(setId,
        weight: weight,
        reps: reps,
        rpe: rpe,
        comment: commentCtl.text,
        isWarmup: isWarmup,
      );
      await _loadExercises();
      setState(() {});
    }
  }

  Future<void> _deleteSet(String setId) async {
    await _db.deleteSet(setId);
    await _loadExercises();
    setState(() {});
  }

  Future<void> _finishWorkout() async {
    if (_workoutId == null) return;

    final feeling = await showDialog<int>(
      context: context,
      builder: (ctx) => _FeelingDialog(),
    );
    if (feeling == null) return;

    final commentCtl = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Observação do Treino'),
        content: TextField(
          controller: commentCtl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Como foi o treino?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Pular')),
          FilledButton(onPressed: () => Navigator.pop(ctx, commentCtl.text), child: const Text('Finalizar')),
        ],
      ),
    );

    // If timer is still running, stop it first
    if (_timerStart != null && _timerEnd == null) {
      await _stopTimer();
    }

    await _db.finishWorkout(_workoutId!, comment: comment ?? '', feelingRating: feeling);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('💪 Treino finalizado!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
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
        title: Text('Treino'),
        centerTitle: true,
        actions: [
          if (_timerService.isActive)
            GestureDetector(
              onTap: _openRestTimer,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
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
          IconButton(
            icon: const Icon(Icons.repeat_outlined),
            onPressed: _importFromRoutine,
            tooltip: 'Importar de Rotina',
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            onPressed: _exercises.isNotEmpty ? _finishWorkout : null,
            tooltip: 'Finalizar Treino',
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
        label: const Text('Adicionar Exercício'),
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
            Text('Nenhum exercício ainda', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Adicione exercícios para começar seu treino',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickExercise,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Exercício'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _importFromRoutine,
              icon: const Icon(Icons.repeat),
              label: const Text('Importar de Rotina'),
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
        totalSets++;
        if ((s['is_complete'] as int?) == 1) completedSets++;
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
                Text('$completedSets/$totalSets sets', style: theme.textTheme.bodySmall),
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
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
            itemCount: _exercises.length,
            itemBuilder: (context, index) => _ExerciseCard(
              exercise: _exercises[index],
              onAddSet: () => _addSet(_exercises[index]),
              onToggleSet: _toggleSet,
              onEditSet: (setId, data, setIdx) => _editSetDialog(setId, data, _exercises[index].name, setIdx),
              onDeleteSet: _deleteSet,
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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
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
                : _timerStart != null
                    ? Icons.timer_outlined
                    : Icons.play_circle_outline,
            color: _timerEnd != null
                ? Colors.green
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
                if (_timerStart != null && _timerEnd == null) ...[
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
                    'Início ${DateFormat('HH:mm').format(_timerStart!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else if (_timerStart != null && _timerEnd != null) ...[
                  // Finished
                  Text(
                    'Duração $_elapsedStr',
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
                    'Temporizador de Treino',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Iniciar cronômetro do treino',
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
                onPressed: _timerStart == null ? _startTimer : _stopTimer,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: _timerStart == null
                      ? theme.colorScheme.primary
                      : Colors.red.withAlpha(200),
                  foregroundColor: _timerStart == null
                      ? theme.colorScheme.onPrimary
                      : Colors.white,
                ),
                child: Text(
                  _timerStart == null ? 'Iniciar' : 'Finalizar',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          if (_timerStart != null)
            IconButton(
              onPressed: _resetTimer,
              icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.onSurfaceVariant.withAlpha(180)),
              tooltip: 'Resetar Timer',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }

  // ===================== REST =====================

  Future<void> _importFromRoutine() async {
    final routines = await _db.getRoutines();
    if (routines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma rotina encontrada. Crie uma primeiro!'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final routineId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildRoutinePicker(routines),
    );
    if (routineId == null || !mounted) return;

    final days = await _db.getRoutineDays(routineId);
    if (days.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta rotina não tem dias.'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final routineName = routines.firstWhere((r) => r['id'] == routineId)['name'] as String;
    final dayId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildDayPicker(ctx, days, routineName),
    );
    if (dayId == null || !mounted) return;

    if (_workoutId == null) return;
    await _db.importRoutineDayToWorkout(_workoutId!, dayId);
    await _loadExercises();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Exercícios importados da rotina!'), behavior: SnackBarBehavior.floating),
      );
    }
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
          Text('Selecione a Rotina', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ListView.separated(
              itemCount: routines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
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
                label: const Text('Voltar'),
              ),
            ],
          ),
          Text(routineName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Selecione o dia para importar', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: ListView.separated(
              itemCount: days.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
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

  void _changeExerciseRestTime(_ExerciseWithSets exercise, int currentRest) {
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
            Text(exercise.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                label: const Text('Personalizado'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomRestTimeDialog(_ExerciseWithSets exercise) {
    final ctl = TextEditingController(text: exercise.restTimeSeconds.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tempo Personalizado'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
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

  void _updateRestTimeAndClose(_ExerciseWithSets exercise, int seconds) async {
    await _db.updateExerciseEntryRestTime(exercise.entryId, seconds);
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
          await _addExercise(
            exercise['id'] as String,
            exercise['name'] as String,
            exercise['category_name'] as String? ?? '',
            Color(exercise['category_color'] as int? ?? 0xFF757575),
            restTimeSeconds: (exercise['default_rest_time'] as int?),
          );
        },
        onExerciseRemoved: (exercise) async {
          final exerciseId = exercise['id'] as String;
          await _db.removeExerciseEntryFromWorkout(_workoutId!, exerciseId);
          if (mounted) {
            setState(() {
              _exercises.removeWhere((e) => e.exerciseId == exerciseId);
            });
          }
        },
      ),
    );
  }
}

class _ExerciseWithSets {
  final String entryId;
  final String exerciseId;
  final String name;
  final String categoryName;
  final Color categoryColor;
  final List<Map<String, dynamic>> sets;
  final int restTimeSeconds;

  _ExerciseWithSets({
    required this.entryId,
    required this.exerciseId,
    required this.name,
    required this.categoryName,
    required this.categoryColor,
    List<Map<String, dynamic>>? sets,
    this.restTimeSeconds = 90,
  }) : sets = sets ?? [];

  int get completedSets => sets.where((s) => (s['is_complete'] as int?) == 1).length;
  double get maxWeight => sets.fold<double>(0, (max, s) {
    final w = (s['weight'] as num?)?.toDouble() ?? 0;
    return w > max ? w : max;
  });
}

class _ExerciseCard extends StatelessWidget {
  final _ExerciseWithSets exercise;
  final VoidCallback onAddSet;
  final Function(String) onToggleSet;
  final void Function(String, Map<String, dynamic>, int) onEditSet;
  final Function(String) onDeleteSet;
  final ThemeData theme;
  final ValueChanged<int> onChangeRestTime;

  const _ExerciseCard({
    required this.exercise, required this.onAddSet, required this.onToggleSet,
    required this.onEditSet, required this.onDeleteSet, required this.theme,
    required this.onChangeRestTime,
  });

  @override
  Widget build(BuildContext context) {
    final restMin = exercise.restTimeSeconds ~/ 60;
    final restSec = exercise.restTimeSeconds % 60;
    final restStr = restMin > 0 ? '${restMin}min$restSec' : '${restSec}s';

    return Card(
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
                  width: 4, height: 24,
                  decoration: BoxDecoration(
                    color: exercise.categoryColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(exercise.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                GestureDetector(
                  onTap: () => onChangeRestTime(exercise.restTimeSeconds),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(restStr, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(exercise.categoryName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 24),
                Expanded(flex: 2, child: Text('#', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(flex: 3, child: Text('Peso', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('Reps', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                if (exercise.sets.any((s) => s['rpe'] != null))
                  Expanded(flex: 2, child: Text('RPE', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                const SizedBox(width: 40),
              ],
            ),
            const Divider(height: 4),
            ...List.generate(exercise.sets.length, (i) {
              final set = exercise.sets[i];
              final isComplete = (set['is_complete'] as int?) == 1;
              final isWarmup = (set['is_warmup'] as int?) == 1;
              return InkWell(
                onTap: () => onEditSet(set['id'] as String, set, i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => onToggleSet(set['id'] as String),
                        child: Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isComplete ? theme.colorScheme.primary : null,
                            border: Border.all(color: isComplete ? theme.colorScheme.primary : theme.colorScheme.outline),
                          ),
                          child: isComplete
                              ? Icon(Icons.check, size: 16, color: theme.colorScheme.onPrimary)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: Text(
                        isWarmup ? 'W' : '${i + 1}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isWarmup ? Colors.orange : null,
                        ),
                      )),
                      Expanded(flex: 3, child: Text(
                        (set['weight'] as num?)?.toStringAsFixed(1) ?? '-',
                        style: theme.textTheme.bodyMedium),
                      ),
                      Expanded(flex: 2, child: Text(
                        (set['reps'] as int?)?.toString() ?? '-',
                        style: theme.textTheme.bodyMedium),
                      ),
                      if (exercise.sets.any((s) => s['rpe'] != null))
                        Expanded(flex: 2, child: Text(
                          (set['rpe'] as num?)?.toStringAsFixed(1) ?? '-',
                          style: theme.textTheme.bodyMedium),
                        ),
                      GestureDetector(
                        onTap: () => onDeleteSet(set['id'] as String),
                        child: Icon(Icons.close, size: 16, color: theme.colorScheme.error.withAlpha(180)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onAddSet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar Série'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeelingDialog extends StatefulWidget {
  @override
  State<_FeelingDialog> createState() => _FeelingDialogState();
}

class _FeelingDialogState extends State<_FeelingDialog> {
  int _rating = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Como foi o treino?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return IconButton(
                icon: Icon(
                  star <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 40,
                ),
                onPressed: () => setState(() => _rating = star),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _rating <= 1 ? 'Ruim' :
            _rating == 2 ? 'Ok' :
            _rating == 3 ? 'Bom' :
            _rating == 4 ? 'Ótimo' : 'Excelente!',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _rating), child: const Text('Confirmar')),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool small;

  const _StepperButton({
    required this.icon,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = small ? 36.0 : 48.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(120)),
        ),
        child: Icon(icon, size: small ? 18 : 24, color: theme.colorScheme.onSurface),
      ),
    );
  }
}
