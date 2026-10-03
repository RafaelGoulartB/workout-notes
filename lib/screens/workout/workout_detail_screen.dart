import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/edit_workout_screen.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/services/export_service.dart';
import 'package:workout_notes/utils/strength_workout_records.dart';
import 'package:workout_notes/widgets/strength/workout/strength_workout_comparison_card.dart';
import 'package:workout_notes/widgets/strength/workout/strength_workout_exercise_card.dart';
import 'package:workout_notes/widgets/strength/workout/strength_workout_hero.dart';
import 'package:workout_notes/widgets/strength/workout/strength_workout_muscle_split.dart';
import 'package:workout_notes/widgets/strength/workout/strength_workout_records_card.dart';
import 'package:workout_notes/widgets/ui/guarded_load.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final String workoutId;
  const WorkoutDetailScreen({super.key, required this.workoutId});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

enum _DetailAction { continueWorkout, editDate, copy, delete }

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen>
    with GuardedLoad {
  final _workoutRepo = DatabaseHelper.instance.workoutRepo;
  final _historyRepo = DatabaseHelper.instance.strengthHistoryRepo;
  StrengthWorkoutDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guardedLoad(() async {
    final detail = await _historyRepo.loadDetail(widget.workoutId);
    if (!mounted) return;
    if (detail == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _detail = detail;
      isLoading = false;
    });
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final detail = _detail;
    final locale = Localizations.localeOf(context).toString();
    final day = detail == null
        ? null
        : DateTime.tryParse(detail.workout['date'] as String? ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Text(day != null ? DateFormat.MMMMd(locale).format(day) : ''),
        actions: detail == null ? null : _buildActions(loc, detail),
      ),
      body: loadFailed
          ? LoadErrorView(onRetry: _load)
          : isLoading || detail == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _buildBody(loc, detail)),
    );
  }

  List<Widget> _buildActions(AppLocalizations loc, StrengthWorkoutDetail d) {
    final colors = Theme.of(context).colorScheme;
    return [
      IconButton(
        icon: const Icon(Icons.share_outlined),
        tooltip: loc.workoutDetailShare,
        onPressed: () =>
            ExportService().shareWorkoutSummary(widget.workoutId, loc),
      ),
      IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: loc.workoutDetailEdit,
        onPressed: _editWorkout,
      ),
      PopupMenuButton<_DetailAction>(
        tooltip: loc.commonMoreOptions,
        onSelected: (action) {
          switch (action) {
            case _DetailAction.continueWorkout:
              _continueWorkout();
            case _DetailAction.editDate:
              _editDate();
            case _DetailAction.copy:
              _copyWorkout();
            case _DetailAction.delete:
              _deleteWorkout();
          }
        },
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: _DetailAction.continueWorkout,
            child: _MenuRow(
              icon: Icons.play_arrow_rounded,
              label: loc.workoutDetailContinue,
            ),
          ),
          PopupMenuItem(
            value: _DetailAction.editDate,
            child: _MenuRow(
              icon: Icons.calendar_today_outlined,
              label: loc.workoutDetailEditDate,
            ),
          ),
          PopupMenuItem(
            value: _DetailAction.copy,
            child: _MenuRow(
              icon: Icons.content_copy_outlined,
              label: loc.workoutDetailCopy,
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _DetailAction.delete,
            child: _MenuRow(
              icon: Icons.delete_outline_rounded,
              label: loc.workoutDetailDelete,
              color: colors.error,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildBody(AppLocalizations loc, StrengthWorkoutDetail detail) {
    final stats = detail.stats;
    final isActive = !detail.isFinished;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppUi.screenPadding,
      children: [
        StrengthWorkoutHero(detail: detail),
        if (detail.records.isNotEmpty) ...[
          AppSectionHeader(loc.workoutDetailRecordsTitle),
          StrengthWorkoutRecordsCard(records: detail.records),
        ],
        if (detail.comparison != null) ...[
          AppSectionHeader(loc.workoutDetailComparisonTitle),
          StrengthWorkoutComparisonCard(detail: detail),
        ],
        if (stats != null && stats.categories.isNotEmpty) ...[
          AppSectionHeader(loc.workoutStatsMuscleVolume),
          StrengthWorkoutMuscleSplit(stats: stats),
        ],
        AppSectionHeader(loc.commonExercises),
        if (detail.exercises.isEmpty)
          AppSectionCard(child: Text(loc.workoutDetailNoExercises))
        else
          for (final exercise in detail.exercises) ...[
            StrengthWorkoutExerciseCard(
              exercise: exercise,
              marks: StrengthWorkoutRecords.markSets(
                events: detail.records,
                exerciseId: exercise.exerciseId,
                sets: [
                  for (final s in exercise.sets)
                    StrengthMarkableSet(
                      id: s['id'] as String,
                      weight: (s['weight'] as num?)?.toDouble() ?? 0,
                      reps: (s['reps'] as num?)?.toInt() ?? 0,
                      isWarmup: (s['is_warmup'] as int?) == 1,
                      isComplete: (s['is_complete'] as int?) == 1,
                    ),
                ],
              ),
              onOpenExercise: () => _openExercise(
                exercise.exerciseId,
                exercise.localizedName(loc),
              ),
            ),
            const SizedBox(height: 10),
          ],
        if (isActive) ...[
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _resumeActive,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(loc.workoutDetailContinue),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ],
    );
  }

  void _openExercise(String exerciseId, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseDetailTabsScreen(
          exerciseId: exerciseId,
          exerciseName: name,
        ),
      ),
    );
  }

  Future<void> _resumeActive() async {
    final result = await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(workoutId: widget.workoutId),
      ),
    );
    if (result == true && mounted) await _load();
  }

  Future<void> _editDate() async {
    final loc = AppLocalizations.of(context)!;
    final currentDate = DateTime.parse(_detail!.workout['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: loc.workoutDetailSelectDate,
    );
    if (newDate == null || !mounted) return;
    await _workoutRepo.updateWorkoutDate(widget.workoutId, newDate);
    if (!mounted) return;
    unawaited(_load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.workoutDetailDateChanged),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editWorkout() async {
    final loc = AppLocalizations.of(context)!;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditWorkoutScreen(workoutId: widget.workoutId),
      ),
    );
    if (result != true || !mounted) return;
    unawaited(_load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.editWorkoutSaved),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _copyWorkout() async {
    final loc = AppLocalizations.of(context)!;
    final currentDate = DateTime.parse(_detail!.workout['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: loc.workoutDetailCopy,
    );
    if (newDate == null || !mounted) return;
    final newWorkoutId = await _workoutRepo.copyWorkoutToDate(
      widget.workoutId,
      newDate,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.workoutDetailCopyDateChanged),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: loc.workoutDetailGoToWorkout,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkoutDetailScreen(workoutId: newWorkoutId),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _continueWorkout() async {
    await _workoutRepo.resetWorkoutToInProgress(widget.workoutId);
    if (!mounted) return;
    final result = await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(workoutId: widget.workoutId),
      ),
    );
    if (mounted) Navigator.pop(context, result ?? true);
  }

  Future<void> _deleteWorkout() async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showConfirmDialog(
      context,
      title: loc.workoutDetailDeleteConfirm,
      message: loc.workoutDetailDeleteContent,
      confirmLabel: loc.commonDelete,
      destructive: true,
    );
    if (confirm != true) return;
    await _workoutRepo.deleteWorkout(widget.workoutId);
    if (mounted) Navigator.pop(context, true);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
