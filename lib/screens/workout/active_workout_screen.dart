import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/screens/workout/rest_timer_screen.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/services/rest_timer_service.dart';
import 'package:workout_notes/services/workout_summary_service.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/utils/workout_volume_comparison.dart';
import 'package:workout_notes/widgets/strength/exercises/exercise_picker_sheet.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_today_card.dart';
import 'package:workout_notes/widgets/strength/workout/active_workout_header.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/workout/exercise_card.dart';
import 'package:workout_notes/widgets/workout/finish_workout_sheet.dart';
import 'package:workout_notes/widgets/workout/set_deleted_snack_bar.dart';
import 'package:workout_notes/widgets/workout/set_editor_fields.dart';

part 'active_workout_controller.dart';
part 'active_workout_routine_actions.dart';

class ActiveWorkoutScreen extends StatefulWidget {
  final String? workoutId;
  final String? routineId;
  final String? routineDayId;

  /// Today's routine day, offered on the empty screen of a new workout; the
  /// workout only takes its exercises when the user picks it.
  final StrengthRoutineDayInfo? suggestedDay;

  const ActiveWorkoutScreen({
    super.key,
    this.workoutId,
    this.routineId,
    this.routineDayId,
    this.suggestedDay,
  });

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with _ActiveWorkoutController, _ActiveWorkoutRoutineActions {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _elapsed.dispose();
    _discardBlankWorkout();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An untouched routine preview is dropped before the route closes, so
    // the screen underneath never sees it as a workout in progress.
    final preview = _routinePreview && _createdHere && _timerStart == null;
    return PopScope(
      canPop: !preview,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final id = _workoutId;
        if (id != null) {
          await _workoutRepo.deleteUntouchedDraft(id);
          _workoutId = null;
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            // The rest timer ticks every second: only this action listens.
            ListenableBuilder(
              listenable: _timerService,
              builder: (context, _) => _buildRestTimerAction(theme),
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
                tooltip: AppLocalizations.of(
                  context,
                )!.activeWorkoutFinishWorkout,
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: AppLocalizations.of(context)!.commonMoreOptions,
              onSelected: (value) {
                switch (value) {
                  case 'import_routine':
                    _importFromRoutine();
                  case 'reset_timer':
                    _resetTimer();
                  case 'delete_workout':
                    _deleteWorkout();
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(
                  value: 'import_routine',
                  child: Row(
                    children: [
                      const Icon(Icons.repeat_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.activeWorkoutImportRoutine,
                      ),
                    ],
                  ),
                ),
                if (_timerStart != null)
                  PopupMenuItem<String>(
                    value: 'reset_timer',
                    child: Row(
                      children: [
                        Icon(
                          Icons.restart_alt,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppLocalizations.of(context)!.activeWorkoutReset,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'delete_workout',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
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
            : _loadFailed
            ? LoadErrorView(onRetry: _initialize)
            : _exercises.isEmpty && _timerStart == null
            ? _buildEmptyState(theme)
            : _buildWorkoutView(theme),
        floatingActionButton: _exercises.isEmpty && _timerStart == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _pickExercise,
                icon: const Icon(Icons.add),
                label: Text(
                  AppLocalizations.of(context)!.activeWorkoutAddExercise,
                ),
              ),
      ),
    );
  }

  Widget _buildRestTimerAction(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    if (!_timerService.isActive) {
      return IconButton(
        icon: const Icon(Icons.timer_outlined),
        onPressed: _openRestTimer,
        tooltip: loc.activeWorkoutRestTimerTooltip,
      );
    }
    final urgent =
        _timerService.remainingSeconds <= 5 && _timerService.isRunning;
    final color = urgent
        ? theme.colorScheme.error
        : theme.colorScheme.onPrimaryContainer;
    return GestureDetector(
      onTap: _openRestTimer,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: urgent
              ? theme.colorScheme.error.withAlpha(40)
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _timerService.isPaused ? Icons.pause : Icons.timer,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              _timerService.shortTime,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _useSuggestedDay(StrengthRoutineDayInfo day) async {
    final workoutId = _workoutId;
    if (workoutId == null) return;
    await _workoutRepo.importRoutineDayToWorkout(workoutId, day.routineDayId);
    _routinePreview = _createdHere;
    await _loadExercises();
    if (mounted) setState(() {});
  }

  /// Empty new workout: a title, today's routine day as a suggestion (same
  /// card as the hub's "Today") and the ways to add exercises.
  Widget _buildEmptyState(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final colors = theme.colorScheme;
    final suggestion = widget.suggestedDay;
    final date = DateFormat.MMMMEEEEd(
      Localizations.localeOf(context).toString(),
    ).format(DateTime.now());

    return ListView(
      padding: AppUi.screenPadding.copyWith(top: 4),
      children: [
        Text(
          loc.strengthHomeNewWorkout,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          toBeginningOfSentenceCase(date),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        if (suggestion != null)
          AppSoftCard(
            key: const Key('active-workout-suggestion'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTodayHeader(
                  title: loc.activeWorkoutSuggestionTitle,
                  icon: Icons.lightbulb_outline_rounded,
                  showDate: false,
                ),
                const SizedBox(height: 14),
                StrengthDayDetails(
                  day: suggestion,
                  actionKey: const Key('active-workout-use-suggestion'),
                  actionLabel: loc.activeWorkoutSuggestionUse,
                  onAction: () => _useSuggestedDay(suggestion),
                ),
              ],
            ),
          )
        else
          AppSectionCard(
            child: Row(
              children: [
                const AppIconBadge(
                  Icons.fitness_center,
                  size: 44,
                  iconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.activeWorkoutEmptyTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        loc.activeWorkoutEmptySubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        AppSectionHeader(loc.activeWorkoutBuildSection),
        AppSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: AppDividedList(
            children: [
              AppListRow(
                key: const Key('active-workout-add-exercise'),
                leading: const AppIconBadge(Icons.add_rounded),
                title: loc.activeWorkoutAddExercise,
                subtitle: loc.activeWorkoutAddExerciseHint,
                onTap: _pickExercise,
              ),
              AppListRow(
                leading: AppIconBadge(
                  Icons.repeat_rounded,
                  color: colors.secondary,
                ),
                title: loc.activeWorkoutImportRoutine,
                subtitle: loc.activeWorkoutImportRoutineHint,
                onTap: _importFromRoutine,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutView(ThemeData theme) {
    int totalSets = 0;
    int completedSets = 0;
    double volume = 0;
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        // Warmup sets are excluded from the progress counter and volume.
        if ((s['is_warmup'] as int?) != 1) {
          totalSets++;
          if ((s['is_complete'] as int?) == 1) {
            completedSets++;
            volume +=
                ((s['weight'] as num?)?.toDouble() ?? 0) *
                ((s['reps'] as num?)?.toInt() ?? 0);
          }
        }
      }
    }

    return Column(
      children: [
        ActiveWorkoutHeader(
          phase: _timerEnd != null
              ? ActiveWorkoutTimerPhase.finished
              : _isPaused
              ? ActiveWorkoutTimerPhase.paused
              : _timerStart != null
              ? ActiveWorkoutTimerPhase.running
              : ActiveWorkoutTimerPhase.idle,
          elapsed: _elapsed,
          startedAt: _timerStart,
          endedAt: _timerEnd,
          onStart: _startTimer,
          onPause: _pauseTimer,
          onResume: _resumeTimer,
          completedSets: completedSets,
          totalSets: totalSets,
          volume: volume,
          categories: _categoryVolumeComparisons,
          expanded: _isVolumeSummaryExpanded,
          onToggleExpanded: () => setState(() {
            _isVolumeSummaryExpanded = !_isVolumeSummaryExpanded;
          }),
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
                    onEditSet: (setId, data, setIdx) => _editSetDialog(
                      setId,
                      data,
                      _exercises[index].localizedName(
                        AppLocalizations.of(context)!,
                      ),
                      setIdx,
                      _exercises[index].exerciseType,
                      _exercises[index].weightIncrement,
                    ),
                    onDeleteSet: _deleteSet,
                    onRemoveExercise: () => _removeExercise(_exercises[index]),
                    onChangeRestTime: (currentRest) =>
                        _changeExerciseRestTime(_exercises[index], currentRest),
                    volumeComparison:
                        _exerciseVolumeComparisons[_exercises[index]
                            .exerciseId],
                    theme: theme,
                  ),
                ),
        ),
      ],
    );
  }
}
