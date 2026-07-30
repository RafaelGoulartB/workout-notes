import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/workout_stats.dart';
import '../../navigation/ai_coach_navigation.dart';
import '../../repositories/workout_repository.dart';
import '../../services/export_service.dart';
import 'exercise_detail_tabs_screen.dart';
import 'active_workout_screen.dart';
import 'edit_workout_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final String workoutId;
  const WorkoutDetailScreen({super.key, required this.workoutId});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  final _workoutRepo = WorkoutRepository();
  Map<String, dynamic>? _workout;
  List<_ExerciseWithSets> _exercises = [];
  WorkoutStats? _stats;
  WorkoutStatsComparison? _comparison;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _workout = await _workoutRepo.getWorkout(widget.workoutId);
    if (_workout == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final entries = await _workoutRepo.getWorkoutExercises(widget.workoutId);
    final stats = await _workoutRepo.getWorkoutStats(widget.workoutId);
    final comparison = await _workoutRepo.getWorkoutStatsComparison(
      widget.workoutId,
    );
    final exercises = <_ExerciseWithSets>[];
    for (final entry in entries) {
      final sets = await _workoutRepo.getExerciseSets(entry['id'] as String);
      exercises.add(
        _ExerciseWithSets(
          exerciseId: entry['exercise_id'] as String? ?? '',
          name: entry['exercise_name'] as String? ?? '',
          localeKey: entry['exercise_locale_key'] as String?,
          categoryId: entry['category_id'] as String?,
          categoryName: entry['category_name'] as String? ?? '',
          categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
          sets: sets,
        ),
      );
    }

    setState(() {
      _exercises = exercises;
      _stats = stats;
      _comparison = comparison;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _workout != null
              ? DateFormat(
                  Intl.defaultLocale?.startsWith('pt') == true
                      ? "d 'de' MMMM"
                      : 'MMMM d',
                  Intl.defaultLocale,
                ).format(DateTime.parse(_workout!['date'] as String))
              : AppLocalizations.of(context)!.workoutDetailContinue,
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton(
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'continue',
                child: Row(
                  children: [
                    Icon(Icons.play_arrow, size: 18, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.workoutDetailContinue,
                      style: TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.workoutDetailEdit),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit_date',
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.workoutDetailEditDate),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.content_copy, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.workoutDetailCopy),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.workoutDetailDelete,
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (v) {
              if (v == 'continue') _continueWorkout();
              if (v == 'edit') _editWorkout();
              if (v == 'edit_date') _editDate();
              if (v == 'copy') _copyWorkout();
              if (v == 'delete') _deleteWorkout();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => ExportService().shareWorkoutSummary(
              widget.workoutId,
              AppLocalizations.of(context)!,
            ),
            tooltip: AppLocalizations.of(context)!.workoutDetailShare,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(child: _buildHeader(theme)),

                  // Exercises
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildExerciseCard(_exercises[index], theme),
                      childCount: _exercises.length,
                    ),
                  ),

                  // Actions
                  SliverToBoxAdapter(child: _buildActions(theme)),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    if (_workout == null) return const SizedBox.shrink();
    final date = DateFormat(
      Intl.defaultLocale?.startsWith('pt') == true
          ? "EEEE, d 'de' MMMM 'de' yyyy"
          : 'EEEE, MMMM d, yyyy',
      Intl.defaultLocale,
    ).format(DateTime.parse(_workout!['date'] as String));
    final end = _workout!['end_time'] as String?;
    final duration = (_workout!['duration_seconds'] as int?) ?? 0;
    final feeling = (_workout!['feeling_rating'] as int?) ?? 0;
    final comment = _workout!['comment'] as String?;
    final stats = _stats;

    final isActive = end == null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionCard(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date[0].toUpperCase() + date.substring(1),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (feeling > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < feeling ? Icons.star : Icons.star_border,
                        size: 20,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
                if (comment != null && comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    comment,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (stats != null)
                  _buildStatsOverview(theme, stats, isActive)
                else
                  _InfoChip(
                    icon: Icons.schedule,
                    label: isActive
                        ? AppLocalizations.of(context)!.workoutHomeOngoing
                        : _formatDuration(duration),
                  ),
              ],
            ),
          ),
          if (_comparison != null && _comparison!.hasAnyDelta) ...[
            const SizedBox(height: 10),
            _buildSectionCard(
              theme,
              child: _buildEvolutionSection(theme, _comparison!),
            ),
          ],
          if (stats != null && _hasHighlights(stats)) ...[
            const SizedBox(height: 10),
            _buildSectionCard(
              theme,
              child: _buildHighlightsSection(theme, stats),
            ),
          ],
          if (stats != null && stats.categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildSectionCard(
              theme,
              child: _buildCategoryVolumeSection(theme, stats),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard(ThemeData theme, {required Widget child}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildStatsOverview(
    ThemeData theme,
    WorkoutStats stats,
    bool isActive,
  ) {
    final loc = AppLocalizations.of(context)!;
    final density = stats.densityKgPerMinute;
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        _InlineMetric(
          icon: Icons.schedule,
          label: loc.activeWorkoutTimerDuration,
          value: isActive
              ? loc.workoutHomeOngoing
              : _formatDuration(stats.durationSeconds),
          color: theme.colorScheme.primary,
        ),
        _InlineMetric(
          icon: Icons.monitor_weight,
          label: loc.commonVolume,
          value: '${_formatVolume(stats.totalVolume)} ${loc.workoutDetailKg}',
          color: theme.colorScheme.secondary,
        ),
        _InlineMetric(
          icon: Icons.repeat,
          label: loc.commonSets,
          value: '${stats.completedSets}/${stats.totalSets}',
          color: Colors.orange,
        ),
        if (density != null)
          _InlineMetric(
            icon: Icons.speed,
            label: loc.workoutStatsDensity,
            value: '${_formatDecimal(density)} ${loc.workoutStatsKgPerMin}',
            color: Colors.teal,
          ),
        if (stats.estimatedCalories != null && stats.estimatedCalories! > 0)
          _InlineMetric(
            icon: Icons.local_fire_department,
            label: loc.workoutEstimatedCalories,
            value: '${stats.estimatedCalories!.round()} kcal',
            color: Colors.deepOrange,
          ),
      ],
    );
  }

  Widget _buildEvolutionSection(
    ThemeData theme,
    WorkoutStatsComparison comparison,
  ) {
    final loc = AppLocalizations.of(context)!;
    final densityDelta = comparison.densityDelta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.trending_up,
          title: loc.workoutStatsEvolution,
          subtitle: loc.workoutStatsVsSimilarWorkout,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DeltaPill(
              label: loc.commonVolume,
              value:
                  '${_formatSignedVolume(comparison.volumeDelta)} ${loc.workoutDetailKg}',
              delta: comparison.volumeDelta,
            ),
            if (densityDelta != null)
              _DeltaPill(
                label: loc.workoutStatsDensity,
                value:
                    '${_formatSignedDecimal(densityDelta)} ${loc.workoutStatsKgPerMin}',
                delta: densityDelta,
              ),
            _DeltaPill(
              label: loc.commonSets,
              value: _formatSignedInt(comparison.setsDelta),
              delta: comparison.setsDelta.toDouble(),
            ),
            _DeltaPill(
              label: loc.activeWorkoutTimerDuration,
              value: _formatSignedDuration(comparison.durationDelta),
              delta: comparison.durationDelta.toDouble(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHighlightsSection(ThemeData theme, WorkoutStats stats) {
    final loc = AppLocalizations.of(context)!;
    final topSet = stats.topSet;
    final highest = stats.highestVolumeExercise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.bolt, title: loc.workoutStatsHighlights),
        const SizedBox(height: 8),
        if (topSet != null)
          _HighlightRow(
            icon: Icons.whatshot,
            label: loc.workoutStatsTopSet,
            value:
                '${_localizedExercise(topSet.exerciseName, topSet.exerciseLocaleKey)} · ${_formatWeight(topSet.weight)} x ${topSet.reps}',
          ),
        if (highest != null)
          _HighlightRow(
            icon: Icons.auto_graph,
            label: loc.workoutStatsHighestVolume,
            value:
                '${_localizedExercise(highest.name, highest.localeKey)} · ${_formatVolume(highest.volume)} ${loc.workoutDetailKg}',
          ),
        if (stats.averageRpe != null)
          _HighlightRow(
            icon: Icons.speed,
            label: loc.workoutStatsAverageRpe,
            value: stats.averageRpe!.toStringAsFixed(1),
          ),
      ],
    );
  }

  Widget _buildCategoryVolumeSection(ThemeData theme, WorkoutStats stats) {
    final loc = AppLocalizations.of(context)!;
    final maxVolume = stats.categories.fold<double>(
      0,
      (max, category) => category.volume > max ? category.volume : max,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.donut_small,
          title: loc.workoutStatsMuscleVolume,
        ),
        const SizedBox(height: 8),
        ...stats.categories.take(5).map((category) {
          final name = category.categoryId != null
              ? ExerciseLocaleHelper.categoryNameFromId(
                  loc,
                  category.categoryId!,
                )
              : category.categoryName;
          final width = maxVolume > 0
              ? (category.volume / maxVolume).clamp(0.0, 1.0)
              : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 86,
                  child: Text(
                    name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(
                          height: 8,
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        FractionallySizedBox(
                          widthFactor: width.toDouble(),
                          child: Container(
                            height: 8,
                            color: category.categoryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatVolume(category.volume)} ${loc.workoutDetailKg}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  bool _hasHighlights(WorkoutStats stats) {
    return stats.topSet != null ||
        stats.highestVolumeExercise != null ||
        stats.averageRpe != null;
  }

  String _localizedExercise(String name, String? localeKey) {
    if (localeKey != null) {
      final translated = ExerciseLocaleHelper.exerciseNameFromKey(
        AppLocalizations.of(context)!,
        localeKey,
      );
      if (translated.isNotEmpty) return translated;
    }
    return name;
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '--';
    return _formatDurationCompact(seconds);
  }

  String _formatDurationCompact(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes >= 24 * 60) {
      final days = minutes ~/ (24 * 60);
      final hours = (minutes % (24 * 60)) ~/ 60;
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final restMinutes = minutes % 60;
      return restMinutes > 0 ? '${hours}h${restMinutes}min' : '${hours}h';
    }
    return AppLocalizations.of(
      context,
    )!.workoutDetailDuration(minutes, remainingSeconds);
  }

  String _formatSignedDuration(int seconds) {
    if (seconds == 0) return '0min';
    final sign = seconds > 0 ? '+' : '-';
    return '$sign${_formatDurationCompact(seconds.abs())}';
  }

  String _formatVolume(double value) {
    return NumberFormat.decimalPattern(
      AppLocalizations.of(context)!.localeName,
    ).format(value.round());
  }

  String _formatSignedVolume(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${_formatVolume(value)}';
  }

  String _formatDecimal(double value) {
    return value.toStringAsFixed(value.abs() >= 10 ? 0 : 1);
  }

  String _formatSignedDecimal(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${_formatDecimal(value)}';
  }

  String _formatSignedInt(int value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix$value';
  }

  String _formatWeight(double value) {
    return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}kg';
  }

  void _showExerciseModal(BuildContext context, _ExerciseWithSets exercise) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        exercise.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(
                  AppLocalizations.of(context)!.workoutDetailViewExercise,
                ),
                subtitle: Text(exercise.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExerciseDetailTabsScreen(
                        exerciseId: exercise.exerciseId,
                        exerciseName: exercise.name,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExerciseCard(_ExerciseWithSets exercise, ThemeData theme) {
    final exerciseStats = _exerciseStatsFor(exercise.exerciseId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onLongPress: () => _showExerciseModal(context, exercise),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: exercise.categoryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      exercise.localizedName(AppLocalizations.of(context)!),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      exercise.localizedCategory(AppLocalizations.of(context)!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (exerciseStats != null) ...[
                  const SizedBox(height: 8),
                  _buildExerciseStatsStrip(theme, exerciseStats),
                ],
                const SizedBox(height: 8),
                if (exercise.sets.isEmpty)
                  Text(
                    AppLocalizations.of(context)!.workoutDetailNoSets,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      const SizedBox(width: 34),
                      Expanded(
                        flex: 2,
                        child: Text(
                          AppLocalizations.of(context)!.workoutDetailSetNumber,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          AppLocalizations.of(context)!.workoutDetailWeight,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          AppLocalizations.of(context)!.commonReps,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          AppLocalizations.of(context)!.workoutDetailRpe,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 4),
                  ...exercise.sets.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;
                    final isWarmup = (s['is_warmup'] as int?) == 1;
                    final isComplete = (s['is_complete'] as int?) == 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isComplete
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceContainerHighest,
                            ),
                            child: isComplete
                                ? Icon(
                                    Icons.check,
                                    size: 14,
                                    color: theme.colorScheme.onPrimary,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: Text(
                              isWarmup ? 'W' : '${i + 1}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isWarmup ? Colors.orange : null,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              (s['weight'] as num?)?.toStringAsFixed(1) ?? '-',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              (s['reps'] as int?)?.toString() ?? '-',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              (s['rpe'] as num?)?.toStringAsFixed(1) ?? '-',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  ExerciseWorkoutStats? _exerciseStatsFor(String exerciseId) {
    final stats = _stats;
    if (stats == null) return null;
    for (final exercise in stats.exercises) {
      if (exercise.exerciseId == exerciseId) return exercise;
    }
    return null;
  }

  Widget _buildExerciseStatsStrip(ThemeData theme, ExerciseWorkoutStats stats) {
    final loc = AppLocalizations.of(context)!;
    final topSet = stats.topSet;
    final parts = [
      '${_formatVolume(stats.volume)} ${loc.workoutDetailKg}',
      '${stats.completedSets} ${loc.commonSets.toLowerCase()}',
      if (topSet != null)
        '${loc.workoutStatsTopSet}: ${_formatWeight(topSet.weight)} x ${topSet.reps}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        parts.join(' · '),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    final isActive = (_workout?['end_time'] as String?) == null;
    if (!isActive) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: () async {
              final result = await Navigator.pushReplacement(
                context,
                AiCoachNavigation.route(
                  kind: AiCoachRouteKind.activeWorkout,
                  builder: (_) =>
                      ActiveWorkoutScreen(workoutId: widget.workoutId),
                ),
              );
              if (result == true) _load();
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(AppLocalizations.of(context)!.workoutDetailContinue),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _deleteWorkout(),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: Text(
              AppLocalizations.of(context)!.workoutDetailDelete,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDate() async {
    final currentDate = DateTime.parse(_workout!['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: AppLocalizations.of(context)!.workoutDetailSelectDate,
    );
    if (newDate != null && mounted) {
      await _workoutRepo.updateWorkoutDate(widget.workoutId, newDate);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.workoutDetailDateChanged,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _editWorkout() async {
    final loc = AppLocalizations.of(context)!;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditWorkoutScreen(workoutId: widget.workoutId),
      ),
    );
    if (result == true) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.editWorkoutSaved),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _copyWorkout() async {
    final currentDate = DateTime.parse(_workout!['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: AppLocalizations.of(context)!.workoutDetailCopy,
    );
    if (newDate != null && mounted) {
      final newWorkoutId = await _workoutRepo.copyWorkoutToDate(
        widget.workoutId,
        newDate,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.workoutDetailCopyDateChanged,
            ),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: AppLocalizations.of(context)!.workoutDetailGoToWorkout,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        WorkoutDetailScreen(workoutId: newWorkoutId),
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _continueWorkout() async {
    await _workoutRepo.resetWorkoutToInProgress(widget.workoutId);
    if (mounted) {
      final result = await Navigator.pushReplacement(
        context,
        AiCoachNavigation.route(
          kind: AiCoachRouteKind.activeWorkout,
          builder: (_) => ActiveWorkoutScreen(workoutId: widget.workoutId),
        ),
      );
      if (mounted) Navigator.pop(context, result ?? true);
    }
  }

  Future<void> _deleteWorkout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.workoutDetailDeleteConfirm),
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
    if (confirm == true) {
      await _workoutRepo.deleteWorkout(widget.workoutId);
      if (mounted) Navigator.pop(context, true);
    }
  }
}

class _ExerciseWithSets {
  final String exerciseId;
  final String name;
  final String? localeKey;
  final String? categoryId;
  final String categoryName;
  final Color categoryColor;
  final List<Map<String, dynamic>> sets;
  _ExerciseWithSets({
    required this.exerciseId,
    required this.name,
    this.localeKey,
    this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.sets,
  });

  String localizedName(AppLocalizations loc) {
    if (localeKey != null) {
      final translated = ExerciseLocaleHelper.exerciseNameFromKey(
        loc,
        localeKey!,
      );
      if (translated.isNotEmpty) return translated;
    }
    return name;
  }

  String localizedCategory(AppLocalizations loc) {
    if (categoryId != null) {
      final translated = ExerciseLocaleHelper.categoryNameFromId(
        loc,
        categoryId!,
      );
      if (translated.isNotEmpty) return translated;
    }
    return categoryName;
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InlineMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        RichText(
          text: TextSpan(
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: '  $label',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final String label;
  final String value;
  final double delta;

  const _DeltaPill({
    required this.label,
    required this.value,
    required this.delta,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = delta > 0
        ? Colors.green
        : delta < 0
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            delta > 0
                ? Icons.trending_up
                : delta < 0
                ? Icons.trending_down
                : Icons.trending_flat,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            '$label $value',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HighlightRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
