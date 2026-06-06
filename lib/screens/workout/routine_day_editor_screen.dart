import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/widgets/exercise_picker_sheet.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';

/// Full-screen editor for a routine day.
/// Allows adding/removing exercises and managing predefined sets,
/// using the same set editing controls as the active workout.
class RoutineDayEditorScreen extends StatefulWidget {
  final String routineDayId;
  final String routineId;
  final String dayName;

  const RoutineDayEditorScreen({
    super.key,
    required this.routineDayId,
    required this.routineId,
    required this.dayName,
  });

  @override
  State<RoutineDayEditorScreen> createState() =>
      _RoutineDayEditorScreenState();
}

class _RoutineDayEditorScreenState extends State<RoutineDayEditorScreen> {
  final _routineRepo = RoutineRepository();
  List<Map<String, dynamic>> _exercises = [];
  final Map<String, List<Map<String, dynamic>>> _predefinedSets = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _exercises =
        await _routineRepo.getRoutineExercises(widget.routineDayId);
    _predefinedSets.clear();
    for (final ex in _exercises) {
      final sets =
          await _routineRepo.getPredefinedSets(ex['id'] as String);
      _predefinedSets[ex['id'] as String] = sets;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Resolves exercise name from aliased JOIN columns.
  String _resolveExerciseName(Map<String, dynamic> ex) {
    final loc = AppLocalizations.of(context)!;
    final localeKey = ex['exercise_locale_key'] as String?;
    if (localeKey != null) {
      final translated =
          ExerciseLocaleHelper.exerciseNameFromKey(loc, localeKey);
      if (translated.isNotEmpty) return translated;
    }
    return (ex['exercise_name'] as String?) ?? '';
  }

  // ===================== EXERCISE MANAGEMENT =====================

  Future<void> _openExercisePicker() async {
    final currentExerciseIds =
        _exercises.map((e) => e['exercise_id'] as String).toSet();

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
                routineExercise['id'] as String);
            _load();
          }
        },
      ),
    );
  }

  Future<void> _removeExercise(Map<String, dynamic> ex) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Exercício?'),
        content: Text(
            'Remover "${_resolveExerciseName(ex)}" deste dia?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx)!.commonDelete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _routineRepo.removeRoutineExercise(ex['id'] as String);
      _load();
    }
  }

  // ===================== REST TIME =====================

  void _changeRestTime(Map<String, dynamic> exercise) {
    final currentRest =
        (exercise['rest_time_seconds'] as int?) ?? 90;
    final exId = exercise['id'] as String;
    final presets = [30, 60, 90, 120, 180];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
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
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ))),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.routinesRestTimeTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...presets.map((sec) => ChoiceChip(
                      label: Text(sec >= 60
                          ? '${sec ~/ 60}min${sec % 60}s'
                          : '${sec}s'),
                      selected: currentRest == sec,
                      onSelected: (_) {
                        _routineRepo.updateRoutineExerciseRestTime(
                            exId, sec);
                        _load();
                        Navigator.pop(ctx);
                      },
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===================== PREDEFINED SET MANAGEMENT =====================

  Future<void> _addPredefinedSet(
      Map<String, dynamic> exercise) async {
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
      _load();
      return;
    }

    // No previous set — open editor with defaults
    final result = await _showSetEditor(
      exerciseType: exercise['exercise_type'] as String? ?? 'weightReps',
      exerciseName: _resolveExerciseName(exercise),
      weight: 0,
      reps: 0,
      distance: 0,
      timeSeconds: 0,
      isWarmup: false,
      setNumber: 1,
    );
    if (result != null) {
      await _routineRepo.addPredefinedSet(
        exId,
        weight: result['weight'] as double?,
        reps: result['reps'] as int?,
        distance: result['distance'] as double?,
        timeSeconds: result['time_seconds'] as int?,
        isWarmup: result['is_warmup'] as bool,
      );
      _load();
    }
  }

  Future<void> _editPredefinedSet(Map<String, dynamic> exercise,
      Map<String, dynamic> setData, int index) async {
    final setId = setData['id'] as String;
    final exerciseType =
        exercise['exercise_type'] as String? ?? 'weightReps';

    final result = await _showSetEditor(
      exerciseType: exerciseType,
      exerciseName: _resolveExerciseName(exercise),
      weight: (setData['weight'] as num?)?.toDouble() ?? 0,
      reps: (setData['reps'] as int?) ?? 0,
      distance: (setData['distance'] as num?)?.toDouble() ?? 0,
      timeSeconds: (setData['time_seconds'] as int?) ?? 0,
      isWarmup: (setData['is_warmup'] as int?) == 1,
      setNumber: index,
    );
    if (result != null) {
      await _routineRepo.updatePredefinedSet(
        setId,
        weight: result['weight'] as double?,
        reps: result['reps'] as int?,
        distance: result['distance'] as double?,
        timeSeconds: result['time_seconds'] as int?,
        isWarmup: result['is_warmup'] as bool?,
      );
      _load();
    }
  }

  Future<void> _deletePredefinedSet(String setId) async {
    await _routineRepo.deletePredefinedSet(setId);
    _load();
  }

  // ===================== SET EDITOR (mirrors active workout controls) =====================

  Future<Map<String, dynamic>?> _showSetEditor({
    required String exerciseType,
    required String exerciseName,
    required double weight,
    required int reps,
    required double distance,
    required int timeSeconds,
    required bool isWarmup,
    required int setNumber,
  }) async {
    double editWeight = weight;
    int editReps = reps;
    double editDistance = distance;
    int editTime = timeSeconds;
    bool editWarmup = isWarmup;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                          color: Theme.of(ctx)
                              .colorScheme
                              .onSurfaceVariant
                              .withAlpha(80),
                          borderRadius: BorderRadius.circular(2),
                        ))),
                const SizedBox(height: 12),
                // Title
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        setNumber > 0
                            ? 'Editar Série $setNumber'
                            : 'Adicionar Série',
                        style: Theme.of(ctx)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      exerciseName,
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Warmup toggle
                Row(
                  children: [
                    Icon(Icons.whatshot,
                        size: 16,
                        color: editWarmup
                            ? Colors.orange
                            : Theme.of(ctx)
                                .colorScheme
                                .onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('Aquecimento',
                        style: Theme.of(ctx).textTheme.bodyMedium),
                    const Spacer(),
                    SizedBox(
                      height: 28,
                      child: Switch.adaptive(
                        value: editWarmup,
                        onChanged: (v) =>
                            setSheetState(() => editWarmup = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Field controls (same as active workout)
                ..._buildFieldControls(
                  ctx,
                  setSheetState,
                  exerciseType,
                  editWeight,
                  editReps,
                  editDistance,
                  editTime,
                  (String key, dynamic value) {
                    setSheetState(() {
                      switch (key) {
                        case 'weight':
                          editWeight =
                              (value as double).clamp(0, 999);
                          break;
                        case 'reps':
                          editReps =
                              (value as int).clamp(0, 999);
                          break;
                        case 'distance':
                          editDistance =
                              (value as double).clamp(0, 999);
                          break;
                        case 'time_seconds':
                          editTime =
                              (value as int).clamp(0, 99999);
                          break;
                      }
                    });
                  },
                ),

                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(AppLocalizations.of(ctx)!
                            .commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, {
                          'weight': editWeight,
                          'reps': editReps,
                          'distance': editDistance,
                          'time_seconds': editTime,
                          'is_warmup': editWarmup,
                        }),
                        child: Text(AppLocalizations.of(ctx)!
                            .commonSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds field controls for the given exercise type.
  /// Mirrors the active workout's _buildFieldControls.
  List<Widget> _buildFieldControls(
    BuildContext ctx,
    StateSetter setSheetState,
    String type,
    double weight,
    int reps,
    double distance,
    int timeSeconds,
    void Function(String key, dynamic value) onFieldChange,
  ) {
    final fields = getFieldsForType(type);
    final keys = fields.keys.toList();
    final widgets = <Widget>[];

    for (final key in keys) {
      if (key == 'weight') {
        widgets.add(_buildWeightControl(
            ctx, setSheetState, weight,
            (v) => onFieldChange('weight', v)));
      } else if (key == 'reps') {
        widgets.add(_buildRepsControl(
            ctx, setSheetState, reps,
            (v) => onFieldChange('reps', v)));
      } else if (key == 'distance') {
        widgets.add(_buildDistanceControl(
            ctx, setSheetState, distance,
            (v) => onFieldChange('distance', v)));
      } else if (key == 'time_seconds') {
        widgets.add(_buildTimeControl(
            ctx, setSheetState, timeSeconds,
            (v) => onFieldChange('time_seconds', v)));
      }
    }
    return widgets;
  }

  // ===================== FIELD CONTROLS (mirror active workout) =====================

  Widget _buildWeightControl(BuildContext ctx, StateSetter setSheetState,
      double weight, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Peso (kg)',
            style: Theme.of(ctx)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          _stepperButton(ctx, Icons.remove,
              onTap: () => onChanged(weight - 2.5)),
          const SizedBox(width: 6),
          _stepperButton(ctx, Icons.remove, small: true,
              onTap: () => onChanged(weight - 0.5)),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(
                  ctx, weight, false, onChanged),
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 4),
                padding:
                    const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(120),
                    borderRadius:
                        BorderRadius.circular(10)),
                child: Center(
                    child: Text(
                  weight.toStringAsFixed(1),
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                )),
              ),
            ),
          ),
          _stepperButton(ctx, Icons.add, small: true,
              onTap: () => onChanged(weight + 0.5)),
          const SizedBox(width: 6),
          _stepperButton(ctx, Icons.add,
              onTap: () => onChanged(weight + 2.5)),
        ]),
        const SizedBox(height: 4),
        Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [20, 30, 40, 50, 60, 80, 100, 120]
                .map((v) => ActionChip(
                      label: Text('$v',
                          style: const TextStyle(fontSize: 10)),
                      onPressed: () => onChanged(v.toDouble()),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList()),
      ],
    );
  }

  Widget _buildRepsControl(BuildContext ctx, StateSetter setSheetState,
      int reps, void Function(int) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text('Repetições',
            style: Theme.of(ctx)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          _stepperButton(ctx, Icons.remove,
              onTap: () => onChanged(reps - 1)),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(ctx, reps.toDouble(),
                  true, (v) => onChanged(v.round())),
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 4),
                padding:
                    const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(120),
                    borderRadius:
                        BorderRadius.circular(10)),
                child: Center(
                    child: Text(
                  '$reps',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                )),
              ),
            ),
          ),
          _stepperButton(ctx, Icons.add,
              onTap: () => onChanged(reps + 1)),
        ]),
        const SizedBox(height: 4),
        Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [1, 3, 5, 8, 10, 12, 15, 20]
                .map((v) => ActionChip(
                      label: Text('$v',
                          style: const TextStyle(fontSize: 10)),
                      onPressed: () => onChanged(v),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList()),
      ],
    );
  }

  Widget _buildDistanceControl(
      BuildContext ctx,
      StateSetter setSheetState,
      double distance,
      void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Distância (km)',
            style: Theme.of(ctx)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          _stepperButton(ctx, Icons.remove, small: true,
              onTap: () =>
                  onChanged((distance - 0.1).clamp(0, 999))),
          _stepperButton(ctx, Icons.remove,
              onTap: () =>
                  onChanged((distance - 0.5).clamp(0, 999))),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(
                  ctx, distance, false, onChanged,
                  title: 'Digite a distância',
                  suffix: ' km'),
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 4),
                padding:
                    const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(120),
                    borderRadius:
                        BorderRadius.circular(10)),
                child: Center(
                    child: Text(
                  distance.toStringAsFixed(1),
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                )),
              ),
            ),
          ),
          _stepperButton(ctx, Icons.add,
              onTap: () =>
                  onChanged((distance + 0.5).clamp(0, 999))),
          _stepperButton(ctx, Icons.add, small: true,
              onTap: () =>
                  onChanged((distance + 0.1).clamp(0, 999))),
        ]),
        const SizedBox(height: 4),
        Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [1.0, 2.0, 3.0, 5.0, 10.0]
                .map((v) => ActionChip(
                      label: Text(v.toStringAsFixed(1),
                          style:
                              const TextStyle(fontSize: 10)),
                      onPressed: () => onChanged(v),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList()),
      ],
    );
  }

  Widget _buildTimeControl(BuildContext ctx, StateSetter setSheetState,
      int timeSeconds, void Function(int) onChanged) {
    final minutes = timeSeconds ~/ 60;
    final seconds = timeSeconds % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Tempo (segundos)',
            style: Theme.of(ctx)
                .textTheme
                .labelSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          _stepperButton(ctx, Icons.remove,
              onTap: () =>
                  onChanged((timeSeconds - 30).clamp(0, 99999))),
          _stepperButton(ctx, Icons.remove, small: true,
              onTap: () =>
                  onChanged((timeSeconds - 5).clamp(0, 99999))),
          Expanded(
            child: GestureDetector(
              onTap: () => _quickEditNumber(
                  ctx, timeSeconds.toDouble(), true,
                  (v) => onChanged(v.round()),
                  title: 'Digite o tempo (segundos)',
                  suffix: ' s'),
              child: Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 4),
                padding:
                    const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(120),
                    borderRadius:
                        BorderRadius.circular(10)),
                child: Center(
                  child: Text(
                    timeSeconds >= 60
                        ? '$minutes:${seconds.toString().padLeft(2, '0')}'
                        : '${timeSeconds}s',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          _stepperButton(ctx, Icons.add, small: true,
              onTap: () =>
                  onChanged((timeSeconds + 5).clamp(0, 99999))),
          _stepperButton(ctx, Icons.add,
              onTap: () =>
                  onChanged((timeSeconds + 30).clamp(0, 99999))),
        ]),
        const SizedBox(height: 4),
        Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [30, 60, 120, 180, 300, 600]
                .map((v) => ActionChip(
                      label: Text(
                          v >= 60 ? '${v ~/ 60}min' : '${v}s',
                          style:
                              const TextStyle(fontSize: 10)),
                      onPressed: () => onChanged(v),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList()),
      ],
    );
  }

  Widget _stepperButton(BuildContext ctx, IconData icon,
      {VoidCallback? onTap, bool small = false}) {
    final size = small ? 36.0 : 48.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(ctx)
                  .colorScheme
                  .outlineVariant
                  .withAlpha(120)),
        ),
        child: Icon(icon,
            size: small ? 18 : 24,
            color: Theme.of(ctx).colorScheme.onSurface),
      ),
    );
  }

  void _quickEditNumber(
    BuildContext ctx,
    double current,
    bool isInt,
    void Function(double) onSet, {
    String? title,
    String? suffix,
  }) {
    final ctl = TextEditingController(
      text: isInt
          ? current.round().toString()
          : current.toStringAsFixed(1));
    showDialog(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: Text(title ?? 'Digite o valor'),
        content: TextField(
          controller: ctl,
          keyboardType:
              TextInputType.numberWithOptions(decimal: !isInt),
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            suffixText: suffix ?? (isInt ? ' reps' : ' kg'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text(AppLocalizations.of(ctx)!.commonCancel)),
          FilledButton(
            onPressed: () {
              final parsed =
                  double.tryParse(ctl.text.replaceAll(',', '.'));
              if (parsed != null && parsed >= 0) {
                onSet(isInt ? parsed.roundToDouble() : parsed);
              }
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openExercisePicker,
            tooltip: loc.routinesAddExercise,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exercises.isEmpty
              ? _buildEmptyState(theme, loc)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        12, 8, 12, 100),
                    itemCount: _exercises.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) return _buildCategorySummary(theme);
                      return _buildExerciseCard(
                          _exercises[i - 1], theme);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openExercisePicker,
        icon: const Icon(Icons.add),
        label: Text(loc.routinesAddExercise),
      ),
    );
  }

  Widget _buildCategorySummary(ThemeData theme) {
    if (_exercises.isEmpty) return const SizedBox.shrink();

    // Aggregate per-category data
    final List<_CategoryStat> stats = [];
    final Map<String, _CategoryStat> statMap = {};

    for (final ex in _exercises) {
      final catId = ex['category_id'] as String? ?? '';
      final catName = ex['category_name'] as String? ?? 'Outros';
      final colorVal = ex['category_color'] as int? ?? 0xFF757575;
      final exerciseType =
          ex['exercise_type'] as String? ?? 'weightReps';
      final sets = _predefinedSets[ex['id'] as String] ?? [];

      statMap.putIfAbsent(catId, () => _CategoryStat(
            name: catName,
            color: Color(colorVal),
          ));

      for (final s in sets) {
        final isWarmup = (s['is_warmup'] as int?) == 1;
        if (isWarmup) continue;
        statMap[catId]!.sets++;
        if (exerciseType == 'weightReps') {
          final w = (s['weight'] as num?)?.toDouble() ?? 0;
          final r = (s['reps'] as int?) ?? 0;
          statMap[catId]!.volume += w * r;
        }
      }
    }

    stats.addAll(statMap.values);
    if (stats.isEmpty) return const SizedBox.shrink();

    final totalSets = stats.fold<int>(0, (a, s) => a + s.sets);
    final totalVolume =
        stats.fold<double>(0, (a, s) => a + s.volume);
    final maxSets = stats
        .fold<int>(0, (a, s) => s.sets > a ? s.sets : a);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.bar_chart, size: 16,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Dashboard do Dia',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),

              // Per-category rows with visual bars
              ...stats.map((stat) {
                final pct = maxSets > 0 ? stat.sets / maxSets : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: stat.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(stat.name,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(
                                        fontWeight:
                                            FontWeight.w600)),
                          ),
                          Text('${stat.sets}s',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.bold)),
                          if (stat.volume > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                                '${stat.volume.toStringAsFixed(0)}kg',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: theme.colorScheme
                              .surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              stat.color.withAlpha(200)),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const Divider(height: 12),

              // Totals
              Row(
                children: [
                  _buildStatChip(theme, '$totalSets', 'séries'),
                  const SizedBox(width: 12),
                  if (totalVolume > 0)
                    _buildStatChip(
                        theme,
                        totalVolume.toStringAsFixed(0),
                        'kg volume'),
                  const SizedBox(width: 12),
                  _buildStatChip(
                      theme,
                      '${stats.length}',
                      'grupos'),
                ],
              ),

              // Balance insight
              if (stats.length >= 2) ...[const SizedBox(height: 8),
                _buildBalanceInsight(theme, stats, totalSets),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(
      ThemeData theme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              )),
          const SizedBox(width: 3),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              )),
        ],
      ),
    );
  }

  Widget _buildBalanceInsight(ThemeData theme,
      List<_CategoryStat> stats, int totalSets) {
    final sorted = List<_CategoryStat>.from(stats)
      ..sort((a, b) => b.sets.compareTo(a.sets));
    final highest = sorted.first;
    final lowest = sorted.last;
    final idealPerGroup = totalSets / stats.length;
    final deviation = (highest.sets - idealPerGroup).abs();

    String insight;
    if (deviation < 1) {
      insight =
          '⚖️ Distribuição equilibrada entre grupos';
    } else if (highest.sets >= lowest.sets * 3) {
      insight =
          '💪 ${highest.name} tem ${highest.sets}s — muito acima de ${lowest.name} (${lowest.sets}s). Considere reduzir.';
    } else {
      final pct = ((highest.sets / totalSets) * 100).round();
      insight =
          '📊 ${highest.name} lidera com $pct% das séries (${highest.sets}s). ${lowest.name} tem ${lowest.sets}s.';
    }

    return Text(insight,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ));
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations loc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fitness_center,
                size: 80,
                color: theme.colorScheme.primary.withAlpha(80)),
            const SizedBox(height: 24),
            Text('Nenhum exercício ainda',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
                'Adicione exercícios para montar seu template',
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openExercisePicker,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Exercício'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
      Map<String, dynamic> ex, ThemeData theme) {
    final sets =
        _predefinedSets[ex['id'] as String] ?? [];
    final exerciseType =
        ex['exercise_type'] as String? ?? 'weightReps';
    final fields = getFieldsForType(exerciseType);
    final keys = fields.keys.toList();
    final catColor =
        Color(ex['category_color'] as int? ?? 0xFF757575);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant
                .withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise header
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: catColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _resolveExerciseName(ex),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                // Rest time badge
                GestureDetector(
                  onTap: () => _changeRestTime(ex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme
                          .colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 14,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${ex['rest_time_seconds'] ?? 90}s',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Remove exercise
                GestureDetector(
                  onTap: () => _removeExercise(ex),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error
                          .withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.close,
                        size: 16,
                        color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Sets header
            if (sets.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(left: 24, bottom: 4),
                child: Row(
                  children: [
                    Text('#',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 11)),
                    const SizedBox(width: 8),
                    if (keys.contains('weight'))
                      Expanded(
                          child: Text('Peso',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.w600,
                                      fontSize: 11))),
                    if (keys.contains('reps'))
                      Expanded(
                          child: Text('Reps',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.w600,
                                      fontSize: 11))),
                    if (keys.contains('distance'))
                      Expanded(
                          child: Text('Dist.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.w600,
                                      fontSize: 11))),
                    if (keys.contains('time_seconds'))
                      Expanded(
                          child: Text('Tempo',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      fontWeight:
                                          FontWeight.w600,
                                      fontSize: 11))),
                    const SizedBox(width: 24),
                  ],
                ),
              ),

            // Set rows — tap anywhere on the row to open editor
            ...sets.asMap().entries.map((setEntry) {
              final idx = setEntry.key;
              final s = setEntry.value;
              final isWarmupSet =
                  (s['is_warmup'] as int?) == 1;

              return GestureDetector(
                onTap: () => _editPredefinedSet(
                    ex, s, idx + 1),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          isWarmupSet ? 'W' : '${idx + 1}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isWarmupSet
                                ? Colors.orange
                                : null,
                          ),
                        ),
                      ),
                      if (keys.contains('weight'))
                        Expanded(
                            child: Text(
                                formatFieldValue(
                                    s, 'weight'),
                                style: theme.textTheme
                                    .bodyMedium)),
                      if (keys.contains('reps'))
                        Expanded(
                            child: Text(
                                formatFieldValue(
                                    s, 'reps'),
                                style: theme.textTheme
                                    .bodyMedium)),
                      if (keys.contains('distance'))
                        Expanded(
                            child: Text(
                                formatFieldValue(
                                    s, 'distance'),
                                style: theme.textTheme
                                    .bodyMedium)),
                      if (keys.contains('time_seconds'))
                        Expanded(
                            child: Text(
                                formatFieldValue(
                                    s, 'time_seconds'),
                                style: theme.textTheme
                                    .bodyMedium)),
                      GestureDetector(
                        onTap: () =>
                            _deletePredefinedSet(
                                s['id'] as String),
                        child: Icon(Icons.close,
                            size: 16,
                            color: theme.colorScheme.error
                                .withAlpha(180)),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Add set button
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _addPredefinedSet(ex),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar Série'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }
}

/// Category stat accumulator.
class _CategoryStat {
  final String name;
  final Color color;
  int sets = 0;
  double volume = 0;

  _CategoryStat({required this.name, required this.color});
}
