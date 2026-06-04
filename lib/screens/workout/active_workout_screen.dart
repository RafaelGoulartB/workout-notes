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
  DateTime? _startTime;
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
    super.dispose();
  }

  void _onTimerTick() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
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
    _startTime = DateTime.now();
  }

  Future<void> _loadExistingWorkout(String id) async {
    _workoutId = id;
    final workout = await _db.getWorkout(id);
    if (workout != null) {
      _startTime = DateTime.parse(workout['start_time'] as String);
      await _loadExercises();
    }
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
    _startTime = DateTime.now();
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
    // Copy data from previous set if available
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
    // Find which exercise this set belongs to
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

    // Auto-start timer when set is marked complete
    if (!wasComplete && parentExercise != null && mounted) {
      _timerService.start(parentExercise.restTimeSeconds);
    }
  }

  Future<void> _editSetDialog(String setId, Map<String, dynamic> setData, String exerciseName) async {
    final weightCtl = TextEditingController(
      text: (setData['weight'] as num?)?.toStringAsFixed(1) ?? '');
    final repsCtl = TextEditingController(
      text: (setData['reps'] as int?)?.toString() ?? '');
    final rpeCtl = TextEditingController(
      text: (setData['rpe'] as num?)?.toStringAsFixed(1) ?? '');
    final commentCtl = TextEditingController(
      text: (setData['comment'] as String?) ?? '');
    bool isWarmup = (setData['is_warmup'] as int?) == 1;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Editar Série - $exerciseName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: weightCtl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(controller: repsCtl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repetições', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(controller: rpeCtl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'RPE (1-10)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(controller: commentCtl,
                  decoration: const InputDecoration(labelText: 'Observação', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Aquecimento'),
                  value: isWarmup,
                  onChanged: (v) => setDialogState(() => isWarmup = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (result == true) {
      await _db.updateSet(setId,
        weight: double.tryParse(weightCtl.text.replaceAll(',', '.')),
        reps: int.tryParse(repsCtl.text),
        rpe: double.tryParse(rpeCtl.text.replaceAll(',', '.')),
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
        title: Text(_startTime != null
            ? DateFormat('HH:mm').format(_startTime!)
            : 'Novo Treino'),
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
            icon: const Icon(Icons.timer_outlined),
            onPressed: _openRestTimer,
            tooltip: 'Temporizador',
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
          : _exercises.isEmpty
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
    // Calculate totals
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
              onEditSet: (setId, data) => _editSetDialog(setId, data, _exercises[index].name),
              onDeleteSet: _deleteSet,
              onChangeRestTime: (currentRest) => _changeExerciseRestTime(_exercises[index], currentRest),
              theme: theme,
            ),
          ),
        ),
      ],
    );
  }

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

    // Step 1: Pick a routine
    final routineId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _buildRoutinePicker(routines),
    );
    if (routineId == null || !mounted) return;

    // Step 2: Pick a day
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

    // Step 3: Import
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
  final Function(String, Map<String, dynamic>) onEditSet;
  final Function(String) onDeleteSet;
  final ThemeData theme;
  final VoidCallback? onStartRestTimer;
  final ValueChanged<int> onChangeRestTime;

  const _ExerciseCard({
    required this.exercise, required this.onAddSet, required this.onToggleSet,
    required this.onEditSet, required this.onDeleteSet, required this.theme,
    this.onStartRestTimer,
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
                // Rest time chip
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
            // Header row
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
            // Sets
            ...List.generate(exercise.sets.length, (i) {
              final set = exercise.sets[i];
              final isComplete = (set['is_complete'] as int?) == 1;
              final isWarmup = (set['is_warmup'] as int?) == 1;
              return InkWell(
                onTap: () => onEditSet(set['id'] as String, set),
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
