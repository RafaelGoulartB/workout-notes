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
                      color:
                          _timerService.remainingSeconds <= 5 &&
                              _timerService.isRunning
                          ? Colors.red
                          : Theme.of(context).colorScheme.onPrimaryContainer,
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
          _buildWorkoutProgressSection(theme, completedSets, totalSets),
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

  Widget _buildWorkoutProgressSection(
    ThemeData theme,
    int completedSets,
    int totalSets,
  ) {
    final loc = AppLocalizations.of(context)!;
    final hasVolumeData = _categoryVolumeComparisons.isNotEmpty;
    final maxVolume = _categoryVolumeComparisons.fold<double>(0, (max, item) {
      final itemMax = item.currentVolume > item.lastVolume
          ? item.currentVolume
          : item.lastVolume;
      return itemMax > max ? itemMax : max;
    });

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: hasVolumeData
                ? () {
                    setState(() {
                      _isVolumeSummaryExpanded = !_isVolumeSummaryExpanded;
                    });
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    loc.activeWorkoutSetsSummary(completedSets, totalSets),
                    style: theme.textTheme.bodySmall,
                  ),
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
                  if (hasVolumeData) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _isVolumeSummaryExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: hasVolumeData
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 10,
                          color: theme.colorScheme.outlineVariant.withAlpha(
                            120,
                          ),
                        ),
                        Text(
                          loc.activeWorkoutByMuscleGroup,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ..._categoryVolumeComparisons.map(
                          (comparison) => _buildCategoryVolumeRow(
                            theme,
                            comparison,
                            maxVolume,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
            crossFadeState: _isVolumeSummaryExpanded && hasVolumeData
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryVolumeRow(
    ThemeData theme,
    CategoryVolumeComparison comparison,
    double maxVolume,
  ) {
    final loc = AppLocalizations.of(context)!;
    final categoryName = comparison.categoryId.isNotEmpty
        ? ExerciseLocaleHelper.categoryNameFromId(loc, comparison.categoryId)
        : comparison.categoryName;
    final deltaColor = _volumeDeltaColor(theme, comparison.delta);
    final currentWidth = maxVolume > 0
        ? (comparison.currentVolume / maxVolume).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: comparison.categoryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  categoryName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatVolumeDelta(comparison.delta, comparison.deltaPercent),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: deltaColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      FractionallySizedBox(
                        widthFactor: currentWidth,
                        child: Container(
                          height: 6,
                          color: comparison.categoryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatVolume(comparison.currentVolume)} / '
                '${_formatVolume(comparison.lastVolume)} kg',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatVolume(double volume) {
    return NumberFormat.decimalPattern(
      AppLocalizations.of(context)!.localeName,
    ).format(volume.round());
  }

  String _formatVolumeDelta(double delta, double? deltaPercent) {
    final prefix = delta > 0 ? '+' : '';
    if (deltaPercent != null) {
      return '$prefix${_formatVolume(delta)} kg '
          '($prefix${deltaPercent.round()}%)';
    }
    return '$prefix${_formatVolume(delta)} kg';
  }

  Color _volumeDeltaColor(ThemeData theme, double delta) {
    if (delta > 0) return theme.colorScheme.primary;
    if (delta < 0) return theme.colorScheme.error;
    return theme.colorScheme.onSurfaceVariant;
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
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
                    AppLocalizations.of(
                      context,
                    )!.activeWorkoutStartTimerTooltip,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
