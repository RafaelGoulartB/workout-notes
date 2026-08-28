import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/widgets/category_timeline_bar.dart';
import 'package:workout_notes/widgets/exercise_picker_sheet.dart';
import 'package:workout_notes/widgets/workout/set_editor_fields.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';
import 'package:workout_notes/utils/workout_estimator.dart';

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
  final Map<String, List<Map<String, dynamic>>> _predefinedSets = {};
  bool _isLoading = true;
  bool _dashboardExpanded = false;

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
    _load();
  }

  Future<void> _load() async {
    _exercises = await _routineRepo.getRoutineExercises(widget.routineDayId);
    _predefinedSets.clear();
    for (final ex in _exercises) {
      final sets = await _routineRepo.getPredefinedSets(ex['id'] as String);
      _predefinedSets[ex['id'] as String] = sets;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  int get _estimatedDurationSeconds {
    final estimateExercises = _exercises.map((ex) {
      final sets = _predefinedSets[ex['id'] as String] ?? const [];
      return WorkoutEstimateExercise(
        restTimeSeconds: ex['rest_time_seconds'] as int?,
        sets: sets
            .map(
              (s) => WorkoutEstimateSet(
                reps: (s['reps'] as num?)?.toInt(),
                timeSeconds: (s['time_seconds'] as num?)?.toInt(),
              ),
            )
            .toList(),
      );
    });
    return WorkoutEstimateCalculator.estimateDurationSeconds(estimateExercises);
  }

  /// Resolves exercise name from aliased JOIN columns.
  String _resolveExerciseName(Map<String, dynamic> ex) {
    final loc = AppLocalizations.of(context)!;
    final localeKey = ex['exercise_locale_key'] as String?;
    if (localeKey != null) {
      final translated = ExerciseLocaleHelper.exerciseNameFromKey(
        loc,
        localeKey,
      );
      if (translated.isNotEmpty) return translated;
    }
    return (ex['exercise_name'] as String?) ?? '';
  }

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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.activeWorkoutRemoveExercise),
        content: Text(
          AppLocalizations.of(
            ctx,
          )!.activeWorkoutRemoveExerciseContent(_resolveExerciseName(ex)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(ctx)!.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _routineRepo.removeRoutineExercise(ex['id'] as String);
      _load();
    }
  }

  void _openExerciseDetails(BuildContext context, Map<String, dynamic> ex) {
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
    final nameCtl = TextEditingController(text: widget.dayName);
    final notesCtl = TextEditingController(text: widget.dayNotes ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.routinesEditDay),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(ctx)!.routinesDayName,
                border: const OutlineInputBorder(),
                hintText: AppLocalizations.of(ctx)!.routinesDayNameHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(ctx)!.routinesNotes,
                border: const OutlineInputBorder(),
                hintText: AppLocalizations.of(ctx)!.routinesNotesHint,
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx, {
                  'name': name,
                  'notes': notesCtl.text.trim(),
                });
              }
            },
            child: Text(AppLocalizations.of(ctx)!.commonSave),
          ),
        ],
      ),
    );

    if (result != null) {
      await _routineRepo.updateRoutineDay(
        widget.routineDayId,
        name: result['name'],
        notes: result['notes']?.isEmpty == true ? null : result['notes'],
      );
      if (!mounted) return;
      // Pop with result to refresh the parent screen
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteDay() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(ctx)!.routinesDeleteConfirm(widget.dayName),
        ),
        content: Text(AppLocalizations.of(ctx)!.routinesDeleteContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(ctx)!.commonDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _routineRepo.deleteRoutineDay(widget.routineDayId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.routinesDeleteDay),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  // ===================== REST TIME =====================

  void _changeRestTime(Map<String, dynamic> exercise) {
    final currentRest = (exercise['rest_time_seconds'] as int?) ?? 90;
    final exId = exercise['id'] as String;
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
                      _routineRepo.updateRoutineExerciseRestTime(exId, sec);
                      _load();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
      _load();
      return;
    }

    // No previous set — open editor with defaults
    final result = await _showSetEditor(
      exerciseType: exercise['exercise_type'] as String? ?? 'weightReps',
      weightIncrement: (exercise['weight_increment'] as num?)?.toDouble() ?? 1,
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

  Future<void> _editPredefinedSet(
    Map<String, dynamic> exercise,
    Map<String, dynamic> setData,
    int index,
  ) async {
    final setId = setData['id'] as String;
    final exerciseType = exercise['exercise_type'] as String? ?? 'weightReps';

    final result = await _showSetEditor(
      exerciseType: exerciseType,
      weightIncrement: (exercise['weight_increment'] as num?)?.toDouble() ?? 1,
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
    required double weightIncrement,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                        setNumber > 0
                            ? AppLocalizations.of(
                                ctx,
                              )!.activeWorkoutEditSetNumber(setNumber)
                            : AppLocalizations.of(ctx)!.activeWorkoutAddSet,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      exerciseName,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Warmup toggle
                Row(
                  children: [
                    Icon(
                      Icons.whatshot,
                      size: 16,
                      color: editWarmup
                          ? Colors.orange
                          : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppLocalizations.of(ctx)!.activeWorkoutWarmup,
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 28,
                      child: Switch.adaptive(
                        value: editWarmup,
                        onChanged: (v) => setSheetState(() => editWarmup = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Field controls (same as active workout)
                WorkoutSetFieldControls(
                  exerciseType: exerciseType,
                  weight: editWeight,
                  reps: editReps,
                  distance: editDistance,
                  timeSeconds: editTime,
                  weightIncrement: weightIncrement,
                  showPace: true,
                  onWeightChanged: (value) =>
                      setSheetState(() => editWeight = value),
                  onRepsChanged: (value) =>
                      setSheetState(() => editReps = value),
                  onDistanceChanged: (value) =>
                      setSheetState(() => editDistance = value),
                  onTimeChanged: (value) =>
                      setSheetState(() => editTime = value),
                ),

                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(AppLocalizations.of(ctx)!.commonCancel),
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
                        child: Text(AppLocalizations.of(ctx)!.commonSave),
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
                child: Text(AppLocalizations.of(context)!.routinesEditDay),
              ),
              PopupMenuItem<String>(
                value: 'delete_day',
                child: Text(AppLocalizations.of(context)!.routinesDeleteDay),
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
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    sliver: SliverToBoxAdapter(
                      child: _buildCategorySummary(theme, loc),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                    sliver: SliverReorderableList(
                      itemCount: _exercises.length,
                      proxyDecorator: _dragProxyDecorator,
                      onReorderStart: (_) => HapticFeedback.mediumImpact(),
                      onReorderItem: _onReorderExercises,
                      itemBuilder: (ctx, i) =>
                          ReorderableDelayedDragStartListener(
                            key: ValueKey(_exercises[i]['id'] as String),
                            index: i,
                            child: _buildExerciseCard(
                              _exercises[i],
                              theme,
                              loc,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openExercisePicker,
        icon: const Icon(Icons.add),
        label: Text(loc.routinesAddExercise),
      ),
    );
  }

  Widget _buildCategorySummary(ThemeData theme, AppLocalizations loc) {
    if (_exercises.isEmpty) return const SizedBox.shrink();

    // Aggregate per-category data
    final List<_CategoryStat> stats = [];
    final Map<String, _CategoryStat> statMap = {};

    for (final ex in _exercises) {
      final catId = ex['category_id'] as String? ?? '';
      final catName = ExerciseLocaleHelper.categoryName(loc, ex);
      final colorVal = ex['category_color'] as int? ?? 0xFF757575;
      final exerciseType = ex['exercise_type'] as String? ?? 'weightReps';
      final sets = _predefinedSets[ex['id'] as String] ?? [];

      statMap.putIfAbsent(
        catId,
        () => _CategoryStat(name: catName, color: Color(colorVal)),
      );

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
    final totalVolume = stats.fold<double>(0, (a, s) => a + s.volume);
    final maxSets = stats.fold<int>(0, (a, s) => s.sets > a ? s.sets : a);
    final estimatedDuration = WorkoutEstimateCalculator.formatDuration(
      _estimatedDurationSeconds,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _dashboardExpanded = !_dashboardExpanded),
          child: AnimatedCrossFade(
            firstChild: _buildDayDashboardCollapsed(
              theme,
              loc,
              stats,
              totalSets,
              totalVolume,
              estimatedDuration,
            ),
            secondChild: _buildDayDashboardExpanded(
              theme,
              loc,
              stats,
              totalSets,
              totalVolume,
              maxSets,
              estimatedDuration,
            ),
            crossFadeState: _dashboardExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ),
      ),
    );
  }

  Widget _buildDayDashboardCollapsed(
    ThemeData theme,
    AppLocalizations loc,
    List<_CategoryStat> stats,
    int totalSets,
    double totalVolume,
    String? estimatedDuration,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${loc.routinesDayDashboard} — '
                  '$totalSets ${loc.routinesDayDashboardSets}'
                  '${totalVolume > 0 ? ' · ${totalVolume.toStringAsFixed(0)} ${loc.routinesDayDashboardVolume}' : ''}'
                  ' · ${stats.length} ${loc.routinesDayDashboardGroups}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _dashboardExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          if (estimatedDuration != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  loc.routinesEstimatedDuration(estimatedDuration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Single category timeline bar — width is proportional to each
            // category's share of the total sets. Replaces the old row of
            // small dots for better at-a-glance distribution.
            CategoryTimelineBar(
              segments: [
                for (final stat in stats) (color: stat.color, value: stat.sets),
              ],
              height: 7,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayDashboardExpanded(
    ThemeData theme,
    AppLocalizations loc,
    List<_CategoryStat> stats,
    int totalSets,
    double totalVolume,
    int maxSets,
    String? estimatedDuration,
  ) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.bar_chart, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                loc.routinesDayDashboard,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Icon(
                _dashboardExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          if (estimatedDuration != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  loc.routinesEstimatedDuration(estimatedDuration),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
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
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: stat.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          stat.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${stat.sets}s',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (stat.volume > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${stat.volume.toStringAsFixed(0)}kg',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
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
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        stat.color.withAlpha(200),
                      ),
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
              _buildStatChip(theme, '$totalSets', loc.routinesDayDashboardSets),
              const SizedBox(width: 12),
              if (totalVolume > 0)
                _buildStatChip(
                  theme,
                  totalVolume.toStringAsFixed(0),
                  loc.routinesDayDashboardVolume,
                ),
              const SizedBox(width: 12),
              _buildStatChip(
                theme,
                '${stats.length}',
                loc.routinesDayDashboardGroups,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(ThemeData theme, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations loc) {
    return Center(
      child: Padding(
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
            Text(loc.routinesNoExercises, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              loc.routinesNoExercisesHint,
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

  Widget _buildExerciseCard(
    Map<String, dynamic> ex,
    ThemeData theme,
    AppLocalizations loc,
  ) {
    final sets = _predefinedSets[ex['id'] as String] ?? [];
    final exerciseType = ex['exercise_type'] as String? ?? 'weightReps';
    final fields = getFieldsForType(exerciseType);
    final keys = fields.keys.toList();
    final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);

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
            // Exercise header
            Row(
              children: [
                // Drag handle — purely visual; long-pressing anywhere on
                // the card starts the drag (SliverReorderableList default).
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
                  ),
                ),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Rest time badge
                GestureDetector(
                  onTap: () => _changeRestTime(ex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${ex['rest_time_seconds'] ?? 90}s',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Info button — opens the exercise details screen
                GestureDetector(
                  onTap: () => _openExerciseDetails(context, ex),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withAlpha(80),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.onPrimaryContainer,
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
                      color: theme.colorScheme.error.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Sets header
            if (sets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      '#',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (keys.contains('weight'))
                      Expanded(
                        child: Text(
                          fields['weight'] ?? 'Peso',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (keys.contains('reps'))
                      Expanded(
                        child: Text(
                          fields['reps'] ?? 'Reps',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (keys.contains('distance'))
                      Expanded(
                        child: Text(
                          fields['distance'] ?? 'Dist.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (keys.contains('time_seconds'))
                      Expanded(
                        child: Text(
                          fields['time_seconds'] ?? 'Tempo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(width: 24),
                  ],
                ),
              ),

            // Set rows — tap anywhere on the row to open editor
            ...sets.asMap().entries.map((setEntry) {
              final idx = setEntry.key;
              final s = setEntry.value;
              final isWarmupSet = (s['is_warmup'] as int?) == 1;

              return GestureDetector(
                onTap: () => _editPredefinedSet(ex, s, idx + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          isWarmupSet ? 'W' : '${idx + 1}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isWarmupSet ? Colors.orange : null,
                          ),
                        ),
                      ),
                      if (keys.contains('weight'))
                        Expanded(
                          child: Text(
                            formatFieldValue(s, 'weight'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      if (keys.contains('reps'))
                        Expanded(
                          child: Text(
                            formatFieldValue(s, 'reps'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      if (keys.contains('distance'))
                        Expanded(
                          child: Text(
                            formatFieldValue(s, 'distance'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      if (keys.contains('time_seconds'))
                        Expanded(
                          child: Text(
                            formatFieldValue(s, 'time_seconds'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _deletePredefinedSet(s['id'] as String),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: theme.colorScheme.error.withAlpha(180),
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
              onPressed: () => _addPredefinedSet(ex),
              icon: const Icon(Icons.add, size: 18),
              label: Text(loc.activeWorkoutAddSet),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
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
