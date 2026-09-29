import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_helper.dart';
import '../../repositories/workout_repository.dart';
import '../../repositories/routine_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/body_measurement_repository.dart';
import '../../repositories/periodization_repository.dart';
import '../../services/rest_timer_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/exercise_picker_sheet.dart';
import '../../widgets/workout/set_editor_fields.dart';
import '../../widgets/workout/exercise_card.dart';
import '../../widgets/workout/finish_workout_sheet.dart';
import '../../models/exercise_with_sets.dart';
import '../../utils/workout_estimator.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/utils/strength_workout_records.dart';
import 'package:workout_notes/widgets/strength/workout/active_workout_header.dart';
import 'rest_timer_screen.dart';

part 'active_workout_controller.dart';
part 'active_workout_routine_actions.dart';

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

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen>
    with _ActiveWorkoutController, _ActiveWorkoutRoutineActions {
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
    _discardBlankWorkout();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_timerService.isActive)
            GestureDetector(
              onTap: _openRestTimer,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      _timerService.remainingSeconds <= 5 &&
                          _timerService.isRunning
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
                      color:
                          _timerService.remainingSeconds <= 5 &&
                              _timerService.isRunning
                          ? theme.colorScheme.error
                          : theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _timerService.shortTime,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color:
                            _timerService.remainingSeconds <= 5 &&
                                _timerService.isRunning
                            ? theme.colorScheme.error
                            : theme.colorScheme.onPrimaryContainer,
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
              tooltip: AppLocalizations.of(
                context,
              )!.activeWorkoutRestTimerTooltip,
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
            tooltip: AppLocalizations.of(context)!.commonMoreOptions,
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
                    Text(
                      AppLocalizations.of(context)!.activeWorkoutImportRoutine,
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
              PopupMenuDivider(),
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
            Icon(
              Icons.fitness_center,
              size: 80,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.activeWorkoutEmptyTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.activeWorkoutEmptySubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickExercise,
              icon: const Icon(Icons.add),
              label: Text(
                AppLocalizations.of(context)!.activeWorkoutAddExercise,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _importFromRoutine,
              icon: const Icon(Icons.repeat),
              label: Text(
                AppLocalizations.of(context)!.activeWorkoutImportRoutine,
              ),
            ),
          ],
        ),
      ),
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
          elapsed: _elapsedStr,
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
